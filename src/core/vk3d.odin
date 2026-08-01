package voidengine

// ============================================================================
// vk3d — Vulkan backend for 3D sprite rendering
//
// Mirrors gl3d.odin: instanced, lit, normal-mapped billboard sprites rendered
// into an HDR target, then a post chain (bright pass -> separable gaussian
// blur -> tonemap/bloom/vignette composite) presented to the swapchain.
//
// Shaders are compiled offline to SPIR-V (tools/compile-vk-shaders.sh) and
// loaded from shader_dir at init:
//   vk_sprite.vert/.frag, vk_post.vert, vk_bright.frag, vk_blur.frag,
//   vk_composite.frag  (each as "<name>.spv")
//
// Usage:
//   config.use_vulkan = true  (engine_init creates the window, no GL context)
//   r := vk3d_init(engine.window, width, height, shader_dir)
//   each frame:
//     if vk3d_begin_frame(r) {
//         vk3d_set_camera(r, &cam); vk3d_set_ambient(r, amb)
//         vk3d_clear_lights(r); vk3d_add_light(r, light); ...
//         vk3d_draw_sprite(r, diffuse, normal, pos, size)  (xN)
//         vk3d_end_frame(r)   // flushes, post-processes, presents
//     }
// ============================================================================

import "core:c"
import "core:fmt"
import "core:os"
import "core:math/linalg"
import "core:image"
import _ "core:image/png"
import vk "vendor:vulkan"
import SDL "vendor:sdl2"

VK3D_FRAMES_IN_FLIGHT  :: 2
VK3D_INITIAL_INSTANCES :: 16384   // per-frame instance buffer capacity (1.5 MB)
VK3D_MAX_TEX_SETS      :: 1024    // descriptor pool capacity for texture pairs

// ----------------------------------------------------------------------------
// Public types
// ----------------------------------------------------------------------------

// A Vulkan texture handle. The zero value is "no texture" (nil).
VK3D_Texture :: struct {
    image:   vk.Image,
    memory:  vk.DeviceMemory,
    view:    vk.ImageView,
    sampler: vk.Sampler,
}

// GPU mesh: interleaved R3D_Vertex buffer + u32 index buffer.
VK3D_Mesh :: struct {
    vbo:         vk.Buffer,
    vbo_memory:  vk.DeviceMemory,
    ebo:         vk.Buffer,
    ebo_memory:  vk.DeviceMemory,
    index_count: i32,
}

// Push constants for the mesh pipeline (112 bytes, VERTEX|FRAGMENT).
VK3D_Mesh_Push :: struct {
    model:  linalg.Matrix4f32,
    color:  linalg.Vector4f32,
    params: linalg.Vector4f32, // spec, shininess, emissive, has_texture
    misc:   linalg.Vector4f32, // uv_tiling.xy
}

// Queued shadow-caster draw (recorded at begin_frame from the sun's view).
VK3D_Shadow_Draw :: struct {
    mesh:  VK3D_Mesh,
    model: linalg.Matrix4f32,
}

// Offscreen render target (color image + view + framebuffer + post descriptor).
VK3D_Target :: struct {
    image:       vk.Image,
    memory:      vk.DeviceMemory,
    view:        vk.ImageView,
    framebuffer: vk.Framebuffer,
    post_set:    vk.DescriptorSet, // samples this target in a post pass
    layout:      vk.ImageLayout,   // tracked current layout (post targets)
}

// Per-frame-in-flight resources.
VK3D_Frame :: struct {
    cmd:             vk.CommandBuffer,
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
    in_flight:       vk.Fence,
    ubo:             vk.Buffer,
    ubo_memory:      vk.DeviceMemory,
    ubo_mapped:      rawptr,
    ubo_set:         vk.DescriptorSet,
    inst_buf:        vk.Buffer,
    inst_memory:     vk.DeviceMemory,
    inst_mapped:     rawptr,
    inst_capacity:   int,
    retired:         [dynamic]VK3D_Retired_Buffer,
}

VK3D_Retired_Buffer :: struct {
    buf: vk.Buffer,
    mem: vk.DeviceMemory,
}

VK3D_Tex_Key :: struct {
    diffuse: vk.ImageView,
    normal:  vk.ImageView,
}

// Push constants shared by the three post shaders (p0/p1 in vk_*.frag).
VK3D_Post_Push :: struct {
    p0: linalg.Vector4f32,
    p1: linalg.Vector4f32,
}

VK3D_Renderer :: struct {
    window:           ^SDL.Window,
    width, height:    i32,
    post_w, post_h:   i32,

    // core objects
    instance:         vk.Instance,
    surface:          vk.SurfaceKHR,
    physical_device:  vk.PhysicalDevice,
    device:           vk.Device,
    queue:            vk.Queue,
    queue_family:     u32,
    cmd_pool:         vk.CommandPool,

    // swapchain
    swapchain:        vk.SwapchainKHR,
    swap_format:      vk.Format,
    swap_extent:      vk.Extent2D,
    swap_images:      []vk.Image,
    swap_views:       []vk.ImageView,
    swap_framebuffers: []vk.Framebuffer,
    swap_image_index: u32,

    // render passes
    scene_pass:       vk.RenderPass, // HDR color + depth -> SHADER_READ_ONLY
    post_pass:        vk.RenderPass, // half-res ping-pong   -> SHADER_READ_ONLY
    composite_pass:   vk.RenderPass, // swapchain image       -> PRESENT_SRC

    // offscreen targets
    scene:            VK3D_Target,
    depth_image:      vk.Image,
    depth_memory:     vk.DeviceMemory,
    depth_view:       vk.ImageView,
    bright_a:         VK3D_Target,
    blur:             [2]VK3D_Target,
    composite_set:    vk.DescriptorSet,

    // descriptors
    desc_pool:            vk.DescriptorPool,
    frame_set_layout:     vk.DescriptorSetLayout, // set 0: frame UBO
    tex_set_layout:       vk.DescriptorSetLayout, // set 1: diffuse + normal
    post_set_layout:      vk.DescriptorSetLayout, // set 0: 1 sampler
    composite_set_layout: vk.DescriptorSetLayout, // set 0: scene + bloom
    desc_cache:           map[VK3D_Tex_Key]vk.DescriptorSet,
    mesh_tex_cache:       map[vk.ImageView]vk.DescriptorSet,

    // pipelines
    sprite_layout:      vk.PipelineLayout,
    sprite_pipeline:    vk.Pipeline,
    post_layout:        vk.PipelineLayout, // bright + blur
    bright_pipeline:    vk.Pipeline,
    blur_pipeline:      vk.Pipeline,
    composite_layout:   vk.PipelineLayout,
    composite_pipeline: vk.Pipeline,
    mesh_layout:        vk.PipelineLayout,
    mesh_pipeline:      vk.Pipeline,
    shadow_pass:        vk.RenderPass,
    shadow_layout:      vk.PipelineLayout,
    shadow_pipeline:    vk.Pipeline,
    shadow_image:       vk.Image,
    shadow_memory:      vk.DeviceMemory,
    shadow_view:        vk.ImageView,
    shadow_fb:          vk.Framebuffer,
    sampler_shadow:     vk.Sampler,
    shadow_res:         i32,
    sun:                R3D_Sun,
    shadow_draws:       [dynamic]VK3D_Shadow_Draw,

    // static geometry
    quad_vbo:         vk.Buffer,
    quad_vbo_memory:  vk.DeviceMemory,
    quad_ebo:         vk.Buffer,
    quad_ebo_memory:  vk.DeviceMemory,

    // shared samplers + flat normal fallback
    sampler_repeat:   vk.Sampler,
    sampler_clamp:    vk.Sampler,
    flat_normal:      VK3D_Texture,

    // frames in flight
    frames:           [VK3D_FRAMES_IN_FLIGHT]VK3D_Frame,
    frame_index:      u32,

    // batch state
    instances:        [dynamic]R3D_Instance,
    inst_frame_base:  int, // instances already streamed this frame (byte offset base)
    cur_diffuse:      vk.ImageView,
    cur_normal:       vk.ImageView,
    cur_diffuse_tex:  VK3D_Texture,
    cur_normal_tex:   VK3D_Texture,
    cur_use_normal:   i32,

    // scene state
    camera:           R3D_Camera,
    ambient:          linalg.Vector3f32,
    lights:           [dynamic]R3D_Light,

    // post settings (same defaults as gl3d)
    bloom:            bool,
    bloom_strength:   f32,
    bloom_threshold:  f32,
    exposure:         f32,
    vignette:         f32,
}

// ----------------------------------------------------------------------------
// Bootstrap: SDL loads libvulkan; we resolve procs through SDL's
// vkGetInstanceProcAddr, then re-resolve per instance/device.
// ----------------------------------------------------------------------------

@(private)
vk3d_gipa: vk.ProcGetInstanceProcAddr

@(private)
vk3d_set_proc :: proc(p: rawptr, name: cstring) {
    (transmute(^rawptr)p)^ = transmute(rawptr)vk3d_gipa(nil, name)
}

// ----------------------------------------------------------------------------
// Small helpers
// ----------------------------------------------------------------------------

@(private)
vk3d_find_memory_type :: proc(r: ^VK3D_Renderer, type_bits: u32, props: vk.MemoryPropertyFlags) -> u32 {
    mem_props: vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(r.physical_device, &mem_props)
    for i in 0 ..< mem_props.memoryTypeCount {
        if (type_bits & (1 << i)) != 0 && (mem_props.memoryTypes[i].propertyFlags & props) == props {
            return i
        }
    }
    fmt.eprintln("vk3d: no suitable memory type")
    return 0
}

@(private)
vk3d_create_buffer :: proc(
    r:     ^VK3D_Renderer,
    size:  vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    props: vk.MemoryPropertyFlags,
) -> (vk.Buffer, vk.DeviceMemory) {
    bci := vk.BufferCreateInfo{
        sType       = .BUFFER_CREATE_INFO,
        size        = size,
        usage       = usage,
        sharingMode = .EXCLUSIVE,
    }
    buf: vk.Buffer
    vk.CreateBuffer(r.device, &bci, nil, &buf)
    reqs: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(r.device, buf, &reqs)
    mai := vk.MemoryAllocateInfo{
        sType           = .MEMORY_ALLOCATE_INFO,
        allocationSize  = reqs.size,
        memoryTypeIndex = vk3d_find_memory_type(r, reqs.memoryTypeBits, props),
    }
    mem: vk.DeviceMemory
    vk.AllocateMemory(r.device, &mai, nil, &mem)
    vk.BindBufferMemory(r.device, buf, mem, 0)
    return buf, mem
}

@(private)
vk3d_create_image :: proc(
    r:      ^VK3D_Renderer,
    w, h:   u32,
    format: vk.Format,
    usage:  vk.ImageUsageFlags,
    mip_levels: u32 = 1,
) -> (vk.Image, vk.DeviceMemory) {
    ici := vk.ImageCreateInfo{
        sType         = .IMAGE_CREATE_INFO,
        imageType     = .D2,
        format        = format,
        extent        = {width = w, height = h, depth = 1},
        mipLevels     = mip_levels,
        arrayLayers   = 1,
        samples       = {._1},
        tiling        = .OPTIMAL,
        usage         = usage,
        sharingMode   = .EXCLUSIVE,
        initialLayout = .UNDEFINED,
    }
    image: vk.Image
    vk.CreateImage(r.device, &ici, nil, &image)
    reqs: vk.MemoryRequirements
    vk.GetImageMemoryRequirements(r.device, image, &reqs)
    mai := vk.MemoryAllocateInfo{
        sType           = .MEMORY_ALLOCATE_INFO,
        allocationSize  = reqs.size,
        memoryTypeIndex = vk3d_find_memory_type(r, reqs.memoryTypeBits, {.DEVICE_LOCAL}),
    }
    memory: vk.DeviceMemory
    vk.AllocateMemory(r.device, &mai, nil, &memory)
    vk.BindImageMemory(r.device, image, memory, 0)
    return image, memory
}

@(private)
vk3d_create_image_view :: proc(r: ^VK3D_Renderer, image: vk.Image, format: vk.Format, aspect: vk.ImageAspectFlags, level_count: u32 = 1) -> vk.ImageView {
    vci := vk.ImageViewCreateInfo{
        sType    = .IMAGE_VIEW_CREATE_INFO,
        image    = image,
        viewType = .D2,
        format   = format,
        subresourceRange = {
            aspectMask     = aspect,
            baseMipLevel   = 0,
            levelCount     = level_count,
            baseArrayLayer = 0,
            layerCount     = 1,
        },
    }
    view: vk.ImageView
    vk.CreateImageView(r.device, &vci, nil, &view)
    return view
}

@(private)
vk3d_create_sampler :: proc(r: ^VK3D_Renderer, address_mode: vk.SamplerAddressMode) -> vk.Sampler {
    sci := vk.SamplerCreateInfo{
        sType        = .SAMPLER_CREATE_INFO,
        magFilter    = .LINEAR,
        minFilter    = .LINEAR,
        mipmapMode   = .LINEAR,
        addressModeU = address_mode,
        addressModeV = address_mode,
        addressModeW = address_mode,
        minLod       = 0,
        maxLod       = 16,
        anisotropyEnable = true,
        maxAnisotropy    = 8,
    }
    sampler: vk.Sampler
    vk.CreateSampler(r.device, &sci, nil, &sampler)
    return sampler
}

// One-shot command buffers for uploads/transitions (init + texture load only).
@(private)
vk3d_begin_one_shot :: proc(r: ^VK3D_Renderer) -> vk.CommandBuffer {
    ai := vk.CommandBufferAllocateInfo{
        sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool        = r.cmd_pool,
        level              = .PRIMARY,
        commandBufferCount = 1,
    }
    cmd: vk.CommandBuffer
    vk.AllocateCommandBuffers(r.device, &ai, &cmd)
    bi := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    }
    vk.BeginCommandBuffer(cmd, &bi)
    return cmd
}

@(private)
vk3d_end_one_shot :: proc(r: ^VK3D_Renderer, cmd: vk.CommandBuffer) {
    vk.EndCommandBuffer(cmd)
    cmd_buf := cmd
    si := vk.SubmitInfo{
        sType              = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers    = &cmd_buf,
    }
    vk.QueueSubmit(r.queue, 1, &si, 0)
    vk.QueueWaitIdle(r.queue)
    vk.FreeCommandBuffers(r.device, r.cmd_pool, 1, &cmd_buf)
}

// ----------------------------------------------------------------------------
// Descriptors
// ----------------------------------------------------------------------------

@(private)
vk3d_alloc_desc_set :: proc(r: ^VK3D_Renderer, layout: vk.DescriptorSetLayout) -> (vk.DescriptorSet, bool) {
    set_layout := layout
    ai := vk.DescriptorSetAllocateInfo{
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = r.desc_pool,
        descriptorSetCount = 1,
        pSetLayouts        = &set_layout,
    }
    set: vk.DescriptorSet
    if vk.AllocateDescriptorSets(r.device, &ai, &set) != .SUCCESS {
        fmt.eprintln("vk3d: descriptor pool exhausted")
        return 0, false
    }
    return set, true
}

// Descriptor set sampling a single target in a post pass (linear clamp).
@(private)
vk3d_alloc_post_set :: proc(r: ^VK3D_Renderer, view: vk.ImageView) -> vk.DescriptorSet {
    set, ok := vk3d_alloc_desc_set(r, r.post_set_layout)
    if !ok { return 0 }
    info := vk.DescriptorImageInfo{
        sampler     = r.sampler_clamp,
        imageView   = view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    write := vk.WriteDescriptorSet{
        sType           = .WRITE_DESCRIPTOR_SET,
        dstSet          = set,
        dstBinding      = 0,
        descriptorCount = 1,
        descriptorType  = .COMBINED_IMAGE_SAMPLER,
        pImageInfo      = &info,
    }
    vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
    return set
}

// Sprite texture-pair descriptor set, deduplicated by (diffuse, normal).
@(private)
vk3d_get_tex_set :: proc(r: ^VK3D_Renderer, diffuse, normal: VK3D_Texture) -> (vk.DescriptorSet, bool) {
    key := VK3D_Tex_Key{diffuse = diffuse.view, normal = normal.view}
    if set, ok := r.desc_cache[key]; ok {
        return set, true
    }
    set, ok := vk3d_alloc_desc_set(r, r.tex_set_layout)
    if !ok { return 0, false }
    infos := [2]vk.DescriptorImageInfo{
        {sampler = diffuse.sampler, imageView = diffuse.view, imageLayout = .SHADER_READ_ONLY_OPTIMAL},
        {sampler = normal.sampler,  imageView = normal.view,  imageLayout = .SHADER_READ_ONLY_OPTIMAL},
    }
    writes := [2]vk.WriteDescriptorSet{
        {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = set,
            dstBinding      = 0,
            descriptorCount = 1,
            descriptorType  = .COMBINED_IMAGE_SAMPLER,
            pImageInfo      = &infos[0],
        },
        {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = set,
            dstBinding      = 1,
            descriptorCount = 1,
            descriptorType  = .COMBINED_IMAGE_SAMPLER,
            pImageInfo      = &infos[1],
        },
    }
    vk.UpdateDescriptorSets(r.device, 2, &writes[0], 0, nil)
    r.desc_cache[key] = set
    return set, true
}

// ----------------------------------------------------------------------------
// Device / swapchain setup
// ----------------------------------------------------------------------------

@(private)
vk3d_find_queue_family :: proc(surface: vk.SurfaceKHR, pd: vk.PhysicalDevice) -> (u32, bool) {
    count: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(pd, &count, nil)
    props := make([]vk.QueueFamilyProperties, int(count), context.temp_allocator)
    vk.GetPhysicalDeviceQueueFamilyProperties(pd, &count, raw_data(props))
    for p, i in props {
        if .GRAPHICS in p.queueFlags {
            supported: b32
            vk.GetPhysicalDeviceSurfaceSupportKHR(pd, u32(i), surface, &supported)
            if supported {
                return u32(i), true
            }
        }
    }
    return 0, false
}

@(private)
vk3d_device_has_extension :: proc(pd: vk.PhysicalDevice, name: string) -> bool {
    count: u32
    vk.EnumerateDeviceExtensionProperties(pd, nil, &count, nil)
    props := make([]vk.ExtensionProperties, int(count), context.temp_allocator)
    vk.EnumerateDeviceExtensionProperties(pd, nil, &count, raw_data(props))
    for &p in props {
        if string(cstring(&p.extensionName[0])) == name {
            return true
        }
    }
    return false
}

// Create (or recreate) the swapchain itself: handle, format, extent, images.
@(private)
vk3d_create_swapchain :: proc(r: ^VK3D_Renderer) -> bool {
    caps: vk.SurfaceCapabilitiesKHR
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(r.physical_device, r.surface, &caps)

    extent := caps.currentExtent
    if extent.width == ~u32(0) {
        // surface size is negotiable; request the window size, clamped
        extent = {width = u32(max(r.width, 1)), height = u32(max(r.height, 1))}
        extent.width  = min(max(extent.width,  caps.minImageExtent.width),  caps.maxImageExtent.width)
        extent.height = min(max(extent.height, caps.minImageExtent.height), caps.maxImageExtent.height)
    }

    // surface format: prefer B8G8R8A8, take whatever if that's all there is
    fmt_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(r.physical_device, r.surface, &fmt_count, nil)
    if fmt_count == 0 {
        fmt.eprintln("vk3d: surface reports no formats")
        return false
    }
    formats := make([]vk.SurfaceFormatKHR, int(fmt_count), context.temp_allocator)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(r.physical_device, r.surface, &fmt_count, raw_data(formats))
    chosen := formats[0]
    if fmt_count == 1 && formats[0].format == .UNDEFINED {
        chosen = {format = .B8G8R8A8_UNORM, colorSpace = .SRGB_NONLINEAR}
    } else {
        for f in formats {
            if f.format == .B8G8R8A8_UNORM {
                chosen = f
                break
            }
        }
    }

    image_count := caps.minImageCount + 1
    if caps.maxImageCount > 0 && image_count > caps.maxImageCount {
        image_count = caps.maxImageCount
    }

    old := r.swapchain
    ci := vk.SwapchainCreateInfoKHR{
        sType            = .SWAPCHAIN_CREATE_INFO_KHR,
        surface          = r.surface,
        minImageCount    = image_count,
        imageFormat      = chosen.format,
        imageColorSpace  = chosen.colorSpace,
        imageExtent      = extent,
        imageArrayLayers = 1,
        imageUsage       = {.COLOR_ATTACHMENT},
        imageSharingMode = .EXCLUSIVE,
        preTransform     = caps.currentTransform,
        compositeAlpha   = {.OPAQUE},
        presentMode      = .FIFO,
        clipped          = true,
        oldSwapchain     = old,
    }
    if vk.CreateSwapchainKHR(r.device, &ci, nil, &r.swapchain) != .SUCCESS {
        fmt.eprintln("vk3d: swapchain creation failed")
        r.swapchain = old
        return false
    }
    if old != 0 {
        vk.DestroySwapchainKHR(r.device, old, nil)
    }

    r.swap_format = chosen.format
    r.swap_extent = extent
    r.width       = i32(extent.width)
    r.height      = i32(extent.height)

    count: u32
    vk.GetSwapchainImagesKHR(r.device, r.swapchain, &count, nil)
    r.swap_images = make([]vk.Image, int(count))
    vk.GetSwapchainImagesKHR(r.device, r.swapchain, &count, raw_data(r.swap_images))
    return true
}

// ----------------------------------------------------------------------------
// Render passes
// ----------------------------------------------------------------------------

@(private)
vk3d_create_render_passes :: proc(r: ^VK3D_Renderer) -> bool {
    // --- scene pass: HDR RGBA16F + D32 depth, ends SHADER_READ_ONLY ---
    {
        attachments := [2]vk.AttachmentDescription{
            {
                format         = .R16G16B16A16_SFLOAT,
                samples        = {._1},
                loadOp         = .CLEAR,
                storeOp        = .STORE,
                stencilLoadOp  = .DONT_CARE,
                stencilStoreOp = .DONT_CARE,
                initialLayout  = .UNDEFINED,
                finalLayout    = .SHADER_READ_ONLY_OPTIMAL,
            },
            {
                format         = .D32_SFLOAT,
                samples        = {._1},
                loadOp         = .CLEAR,
                storeOp        = .DONT_CARE,
                stencilLoadOp  = .DONT_CARE,
                stencilStoreOp = .DONT_CARE,
                initialLayout  = .UNDEFINED,
                finalLayout    = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            },
        }
        color_ref := vk.AttachmentReference{attachment = 0, layout = .COLOR_ATTACHMENT_OPTIMAL}
        depth_ref := vk.AttachmentReference{attachment = 1, layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL}
        subpass := vk.SubpassDescription{
            pipelineBindPoint       = .GRAPHICS,
            colorAttachmentCount    = 1,
            pColorAttachments       = &color_ref,
            pDepthStencilAttachment = &depth_ref,
        }
        deps := [2]vk.SubpassDependency{
            {
                srcSubpass    = vk.SUBPASS_EXTERNAL,
                dstSubpass    = 0,
                srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
                dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
                srcAccessMask = {},
                dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
            },
            {
                srcSubpass    = 0,
                dstSubpass    = vk.SUBPASS_EXTERNAL,
                srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
                dstStageMask  = {.FRAGMENT_SHADER},
                srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
                dstAccessMask = {.SHADER_READ},
            },
        }
        ci := vk.RenderPassCreateInfo{
            sType           = .RENDER_PASS_CREATE_INFO,
            attachmentCount = 2,
            pAttachments    = &attachments[0],
            subpassCount    = 1,
            pSubpasses      = &subpass,
            dependencyCount = 2,
            pDependencies   = &deps[0],
        }
        if vk.CreateRenderPass(r.device, &ci, nil, &r.scene_pass) != .SUCCESS {
            fmt.eprintln("vk3d: scene render pass failed")
            return false
        }
    }

    // --- post pass: RGBA16F only; explicit barriers move targets in/out of
    //     COLOR_ATTACHMENT_OPTIMAL, the pass itself ends SHADER_READ_ONLY ---
    {
        attachment := vk.AttachmentDescription{
            format         = .R16G16B16A16_SFLOAT,
            samples        = {._1},
            loadOp         = .DONT_CARE,
            storeOp        = .STORE,
            stencilLoadOp  = .DONT_CARE,
            stencilStoreOp = .DONT_CARE,
            initialLayout  = .COLOR_ATTACHMENT_OPTIMAL,
            finalLayout    = .SHADER_READ_ONLY_OPTIMAL,
        }
        color_ref := vk.AttachmentReference{attachment = 0, layout = .COLOR_ATTACHMENT_OPTIMAL}
        subpass := vk.SubpassDescription{
            pipelineBindPoint    = .GRAPHICS,
            colorAttachmentCount = 1,
            pColorAttachments    = &color_ref,
        }
        deps := [2]vk.SubpassDependency{
            {
                srcSubpass    = vk.SUBPASS_EXTERNAL,
                dstSubpass    = 0,
                srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
                dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
                srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
                dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
            },
            {
                srcSubpass    = 0,
                dstSubpass    = vk.SUBPASS_EXTERNAL,
                srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
                dstStageMask  = {.FRAGMENT_SHADER, .COLOR_ATTACHMENT_OUTPUT},
                srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
                dstAccessMask = {.SHADER_READ, .COLOR_ATTACHMENT_WRITE},
            },
        }
        ci := vk.RenderPassCreateInfo{
            sType           = .RENDER_PASS_CREATE_INFO,
            attachmentCount = 1,
            pAttachments    = &attachment,
            subpassCount    = 1,
            pSubpasses      = &subpass,
            dependencyCount = 2,
            pDependencies   = &deps[0],
        }
        if vk.CreateRenderPass(r.device, &ci, nil, &r.post_pass) != .SUCCESS {
            fmt.eprintln("vk3d: post render pass failed")
            return false
        }
    }

    // --- composite pass: straight to the swapchain image ---
    {
        attachment := vk.AttachmentDescription{
            format         = r.swap_format,
            samples        = {._1},
            loadOp         = .CLEAR,
            storeOp        = .STORE,
            stencilLoadOp  = .DONT_CARE,
            stencilStoreOp = .DONT_CARE,
            initialLayout  = .UNDEFINED,
            finalLayout    = .PRESENT_SRC_KHR,
        }
        color_ref := vk.AttachmentReference{attachment = 0, layout = .COLOR_ATTACHMENT_OPTIMAL}
        subpass := vk.SubpassDescription{
            pipelineBindPoint    = .GRAPHICS,
            colorAttachmentCount = 1,
            pColorAttachments    = &color_ref,
        }
        dep := vk.SubpassDependency{
            srcSubpass    = vk.SUBPASS_EXTERNAL,
            dstSubpass    = 0,
            srcStageMask  = {.FRAGMENT_SHADER, .COLOR_ATTACHMENT_OUTPUT},
            dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
            srcAccessMask = {.SHADER_READ, .COLOR_ATTACHMENT_WRITE},
            dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
        }
        ci := vk.RenderPassCreateInfo{
            sType           = .RENDER_PASS_CREATE_INFO,
            attachmentCount = 1,
            pAttachments    = &attachment,
            subpassCount    = 1,
            pSubpasses      = &subpass,
            dependencyCount = 1,
            pDependencies   = &dep,
        }
        if vk.CreateRenderPass(r.device, &ci, nil, &r.composite_pass) != .SUCCESS {
            fmt.eprintln("vk3d: composite render pass failed")
            return false
        }
    }

    // --- shadow pass: D32 depth only, ends DEPTH_STENCIL_READ_ONLY ---
    {
        attachment := vk.AttachmentDescription{
            format         = .D32_SFLOAT,
            samples        = {._1},
            loadOp         = .CLEAR,
            storeOp        = .STORE,
            stencilLoadOp  = .DONT_CARE,
            stencilStoreOp = .DONT_CARE,
            initialLayout  = .UNDEFINED,
            finalLayout    = .DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        }
        depth_ref := vk.AttachmentReference{attachment = 0, layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL}
        subpass := vk.SubpassDescription{
            pipelineBindPoint       = .GRAPHICS,
            colorAttachmentCount    = 0,
            pDepthStencilAttachment = &depth_ref,
        }
        deps := [2]vk.SubpassDependency{
            {
                srcSubpass    = vk.SUBPASS_EXTERNAL,
                dstSubpass    = 0,
                srcStageMask  = {.FRAGMENT_SHADER},
                dstStageMask  = {.EARLY_FRAGMENT_TESTS},
                srcAccessMask = {.SHADER_READ},
                dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
            },
            {
                srcSubpass    = 0,
                dstSubpass    = vk.SUBPASS_EXTERNAL,
                srcStageMask  = {.LATE_FRAGMENT_TESTS},
                dstStageMask  = {.FRAGMENT_SHADER},
                srcAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
                dstAccessMask = {.SHADER_READ},
            },
        }
        ci := vk.RenderPassCreateInfo{
            sType           = .RENDER_PASS_CREATE_INFO,
            attachmentCount = 1,
            pAttachments    = &attachment,
            subpassCount    = 1,
            pSubpasses      = &subpass,
            dependencyCount = 2,
            pDependencies   = &deps[0],
        }
        if vk.CreateRenderPass(r.device, &ci, nil, &r.shadow_pass) != .SUCCESS {
            fmt.eprintln("vk3d: shadow render pass failed")
            return false
        }
    }
    return true
}

// ----------------------------------------------------------------------------
// Size-dependent resources (rebuilt on resize / swapchain recreation)
// ----------------------------------------------------------------------------

@(private)
vk3d_create_target :: proc(r: ^VK3D_Renderer, t: ^VK3D_Target, w, h: i32, pass: vk.RenderPass, depth_view: vk.ImageView) {
    t.image, t.memory = vk3d_create_image(r, u32(w), u32(h), .R16G16B16A16_SFLOAT, {.COLOR_ATTACHMENT, .SAMPLED})
    t.view = vk3d_create_image_view(r, t.image, .R16G16B16A16_SFLOAT, {.COLOR})
    if depth_view != 0 {
        atts := [2]vk.ImageView{t.view, depth_view}
        fbci := vk.FramebufferCreateInfo{
            sType           = .FRAMEBUFFER_CREATE_INFO,
            renderPass      = pass,
            attachmentCount = 2,
            pAttachments    = &atts[0],
            width           = u32(w),
            height          = u32(h),
            layers          = 1,
        }
        vk.CreateFramebuffer(r.device, &fbci, nil, &t.framebuffer)
    } else {
        fbci := vk.FramebufferCreateInfo{
            sType           = .FRAMEBUFFER_CREATE_INFO,
            renderPass      = pass,
            attachmentCount = 1,
            pAttachments    = &t.view,
            width           = u32(w),
            height          = u32(h),
            layers          = 1,
        }
        vk.CreateFramebuffer(r.device, &fbci, nil, &t.framebuffer)
    }
    t.post_set = vk3d_alloc_post_set(r, t.view)
    t.layout   = .UNDEFINED
}

@(private)
vk3d_destroy_target :: proc(r: ^VK3D_Renderer, t: ^VK3D_Target) {
    if t.post_set != 0 {
        vk.FreeDescriptorSets(r.device, r.desc_pool, 1, &t.post_set)
        t.post_set = 0
    }
    if t.framebuffer != 0 {
        vk.DestroyFramebuffer(r.device, t.framebuffer, nil)
        t.framebuffer = 0
    }
    if t.view != 0 {
        vk.DestroyImageView(r.device, t.view, nil)
        t.view = 0
    }
    if t.image != 0 {
        vk.DestroyImage(r.device, t.image, nil)
        t.image = 0
    }
    if t.memory != 0 {
        vk.FreeMemory(r.device, t.memory, nil)
        t.memory = 0
    }
}

@(private)
vk3d_create_size_dependent :: proc(r: ^VK3D_Renderer) {
    // swapchain image views + composite framebuffers
    r.swap_views       = make([]vk.ImageView, len(r.swap_images))
    r.swap_framebuffers = make([]vk.Framebuffer, len(r.swap_images))
    for img, i in r.swap_images {
        r.swap_views[i] = vk3d_create_image_view(r, img, r.swap_format, {.COLOR})
        fbci := vk.FramebufferCreateInfo{
            sType           = .FRAMEBUFFER_CREATE_INFO,
            renderPass      = r.composite_pass,
            attachmentCount = 1,
            pAttachments    = &r.swap_views[i],
            width           = r.swap_extent.width,
            height          = r.swap_extent.height,
            layers          = 1,
        }
        vk.CreateFramebuffer(r.device, &fbci, nil, &r.swap_framebuffers[i])
    }

    // depth buffer
    r.depth_image, r.depth_memory = vk3d_create_image(
        r, u32(r.width), u32(r.height), .D32_SFLOAT, {.DEPTH_STENCIL_ATTACHMENT},
    )
    r.depth_view = vk3d_create_image_view(r, r.depth_image, .D32_SFLOAT, {.DEPTH})

    // HDR scene target (full res) + half-res post targets
    r.post_w = max(r.width / 2, 1)
    r.post_h = max(r.height / 2, 1)
    vk3d_create_target(r, &r.scene, r.width, r.height, r.scene_pass, r.depth_view)
    vk3d_create_target(r, &r.bright_a, r.post_w, r.post_h, r.post_pass, 0)
    vk3d_create_target(r, &r.blur[0], r.post_w, r.post_h, r.post_pass, 0)
    vk3d_create_target(r, &r.blur[1], r.post_w, r.post_h, r.post_pass, 0)

    // composite descriptor: scene + final blur target (blur[1] after 4 passes)
    set, ok := vk3d_alloc_desc_set(r, r.composite_set_layout)
    if ok {
        r.composite_set = set
        infos := [2]vk.DescriptorImageInfo{
            {sampler = r.sampler_clamp, imageView = r.scene.view,   imageLayout = .SHADER_READ_ONLY_OPTIMAL},
            {sampler = r.sampler_clamp, imageView = r.blur[1].view, imageLayout = .SHADER_READ_ONLY_OPTIMAL},
        }
        writes := [2]vk.WriteDescriptorSet{
            {
                sType           = .WRITE_DESCRIPTOR_SET,
                dstSet          = set,
                dstBinding      = 0,
                descriptorCount = 1,
                descriptorType  = .COMBINED_IMAGE_SAMPLER,
                pImageInfo      = &infos[0],
            },
            {
                sType           = .WRITE_DESCRIPTOR_SET,
                dstSet          = set,
                dstBinding      = 1,
                descriptorCount = 1,
                descriptorType  = .COMBINED_IMAGE_SAMPLER,
                pImageInfo      = &infos[1],
            },
        }
        vk.UpdateDescriptorSets(r.device, 2, &writes[0], 0, nil)
    }
}

@(private)
vk3d_destroy_size_dependent :: proc(r: ^VK3D_Renderer) {
    if r.composite_set != 0 {
        vk.FreeDescriptorSets(r.device, r.desc_pool, 1, &r.composite_set)
        r.composite_set = 0
    }
    vk3d_destroy_target(r, &r.scene)
    vk3d_destroy_target(r, &r.bright_a)
    vk3d_destroy_target(r, &r.blur[0])
    vk3d_destroy_target(r, &r.blur[1])
    if r.depth_view != 0 {
        vk.DestroyImageView(r.device, r.depth_view, nil)
        r.depth_view = 0
    }
    if r.depth_image != 0 {
        vk.DestroyImage(r.device, r.depth_image, nil)
        r.depth_image = 0
    }
    if r.depth_memory != 0 {
        vk.FreeMemory(r.device, r.depth_memory, nil)
        r.depth_memory = 0
    }
    for v in r.swap_views {
        vk.DestroyImageView(r.device, v, nil)
    }
    delete(r.swap_views)
    r.swap_views = nil
    for fb in r.swap_framebuffers {
        vk.DestroyFramebuffer(r.device, fb, nil)
    }
    delete(r.swap_framebuffers)
    r.swap_framebuffers = nil
    delete(r.swap_images)
    r.swap_images = nil
    if r.swapchain != 0 {
        vk.DestroySwapchainKHR(r.device, r.swapchain, nil)
        r.swapchain = 0
    }
}

// Recreate the swapchain + all size-dependent resources. Caller must have
// waited for the device to be idle (vk3d_resize / frame-path both do).
@(private)
vk3d_recreate_swapchain :: proc(r: ^VK3D_Renderer) {
    vk.DeviceWaitIdle(r.device)
    vk3d_destroy_size_dependent(r)
    if !vk3d_create_swapchain(r) {
        fmt.eprintln("vk3d: swapchain recreation failed")
        return
    }
    vk3d_create_size_dependent(r)
}

// ----------------------------------------------------------------------------
// Shaders + pipelines
// ----------------------------------------------------------------------------

@(private)
vk3d_load_shader_module :: proc(r: ^VK3D_Renderer, dir: string, name: string) -> (vk.ShaderModule, bool) {
    path := fmt.tprintf("%s/%s.spv", dir, name)
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("vk3d: cannot read shader:", path)
        return 0, false
    }
    defer delete(data)
    ci := vk.ShaderModuleCreateInfo{
        sType    = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(data),
        pCode    = (^u32)(raw_data(data)),
    }
    module: vk.ShaderModule
    if vk.CreateShaderModule(r.device, &ci, nil, &module) != .SUCCESS {
        fmt.eprintln("vk3d: cannot create shader module:", path)
        return 0, false
    }
    return module, true
}

@(private)
vk3d_create_sprite_pipeline :: proc(r: ^VK3D_Renderer, vert, frag: vk.ShaderModule) -> bool {
    stages := [2]vk.PipelineShaderStageCreateInfo{
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX},   module = vert, pName = "main"},
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag, pName = "main"},
    }

    // binding 0: quad corner+uv (per-vertex); binding 1: R3D_Instance (per-instance)
    bindings := [2]vk.VertexInputBindingDescription{
        {binding = 0, stride = 16,                   inputRate = .VERTEX},
        {binding = 1, stride = R3D_INSTANCE_STRIDE,  inputRate = .INSTANCE},
    }
    attrs := [9]vk.VertexInputAttributeDescription{
        {location = 0, binding = 0, format = .R32G32_SFLOAT,       offset = 0},
        {location = 1, binding = 0, format = .R32G32_SFLOAT,       offset = 8},
        {location = 2, binding = 1, format = .R32G32B32_SFLOAT,    offset = u32(offset_of(R3D_Instance, origin))},
        {location = 3, binding = 1, format = .R32G32B32_SFLOAT,    offset = u32(offset_of(R3D_Instance, right))},
        {location = 4, binding = 1, format = .R32G32B32_SFLOAT,    offset = u32(offset_of(R3D_Instance, up))},
        {location = 5, binding = 1, format = .R32G32B32_SFLOAT,    offset = u32(offset_of(R3D_Instance, normal))},
        {location = 6, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(R3D_Instance, uv_rect))},
        {location = 7, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(R3D_Instance, color))},
        {location = 8, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(R3D_Instance, params))},
    }
    vi := vk.PipelineVertexInputStateCreateInfo{
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 2,
        pVertexBindingDescriptions      = &bindings[0],
        vertexAttributeDescriptionCount = 9,
        pVertexAttributeDescriptions    = &attrs[0],
    }
    ia := vk.PipelineInputAssemblyStateCreateInfo{
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }
    vp := vk.PipelineViewportStateCreateInfo{
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount  = 1,
    }
    rs := vk.PipelineRasterizationStateCreateInfo{
        sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode = .FILL,
        cullMode    = {},
        frontFace   = .COUNTER_CLOCKWISE,
        lineWidth   = 1.0,
    }
    ms := vk.PipelineMultisampleStateCreateInfo{
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
    }
    ds := vk.PipelineDepthStencilStateCreateInfo{
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = true,
        depthWriteEnable = true,
        depthCompareOp   = .LESS,
    }
    blend_att := vk.PipelineColorBlendAttachmentState{
        blendEnable         = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp        = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
        alphaBlendOp        = .ADD,
        colorWriteMask      = {.R, .G, .B, .A},
    }
    cb := vk.PipelineColorBlendStateCreateInfo{
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 1,
        pAttachments    = &blend_att,
    }
    dyn_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    dyn := vk.PipelineDynamicStateCreateInfo{
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = &dyn_states[0],
    }
    ci := vk.GraphicsPipelineCreateInfo{
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount          = 2,
        pStages             = &stages[0],
        pVertexInputState   = &vi,
        pInputAssemblyState = &ia,
        pViewportState      = &vp,
        pRasterizationState = &rs,
        pMultisampleState   = &ms,
        pDepthStencilState  = &ds,
        pColorBlendState    = &cb,
        pDynamicState       = &dyn,
        layout              = r.sprite_layout,
        renderPass          = r.scene_pass,
        subpass             = 0,
    }
    if vk.CreateGraphicsPipelines(r.device, 0, 1, &ci, nil, &r.sprite_pipeline) != .SUCCESS {
        fmt.eprintln("vk3d: sprite pipeline creation failed")
        return false
    }
    return true
}

// Fullscreen-triangle post pipeline (no vertex input, no depth, no blend).
@(private)
vk3d_create_post_pipeline :: proc(
    r:      ^VK3D_Renderer,
    vert:   vk.ShaderModule,
    frag:   vk.ShaderModule,
    layout: vk.PipelineLayout,
    pass:   vk.RenderPass,
) -> (vk.Pipeline, bool) {
    stages := [2]vk.PipelineShaderStageCreateInfo{
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX},   module = vert, pName = "main"},
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag, pName = "main"},
    }
    vi := vk.PipelineVertexInputStateCreateInfo{
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    }
    ia := vk.PipelineInputAssemblyStateCreateInfo{
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }
    vp := vk.PipelineViewportStateCreateInfo{
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount  = 1,
    }
    rs := vk.PipelineRasterizationStateCreateInfo{
        sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode = .FILL,
        cullMode    = {},
        frontFace   = .COUNTER_CLOCKWISE,
        lineWidth   = 1.0,
    }
    ms := vk.PipelineMultisampleStateCreateInfo{
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
    }
    blend_att := vk.PipelineColorBlendAttachmentState{
        blendEnable    = false,
        colorWriteMask = {.R, .G, .B, .A},
    }
    cb := vk.PipelineColorBlendStateCreateInfo{
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 1,
        pAttachments    = &blend_att,
    }
    dyn_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    dyn := vk.PipelineDynamicStateCreateInfo{
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = &dyn_states[0],
    }
    ci := vk.GraphicsPipelineCreateInfo{
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount          = 2,
        pStages             = &stages[0],
        pVertexInputState   = &vi,
        pInputAssemblyState = &ia,
        pViewportState      = &vp,
        pRasterizationState = &rs,
        pMultisampleState   = &ms,
        pColorBlendState    = &cb,
        pDynamicState       = &dyn,
        layout              = layout,
        renderPass          = pass,
        subpass             = 0,
    }
    pipeline: vk.Pipeline
    if vk.CreateGraphicsPipelines(r.device, 0, 1, &ci, nil, &pipeline) != .SUCCESS {
        fmt.eprintln("vk3d: post pipeline creation failed")
        return 0, false
    }
    return pipeline, true
}

// ----------------------------------------------------------------------------
// Init / shutdown
// ----------------------------------------------------------------------------

vk3d_init :: proc(window: ^SDL.Window, width, height: i32, shader_dir: string) -> ^VK3D_Renderer {
    if SDL.Vulkan_LoadLibrary(nil) != 0 {
        fmt.eprintln("vk3d: SDL_Vulkan_LoadLibrary failed")
        return nil
    }
    vk3d_gipa = transmute(vk.ProcGetInstanceProcAddr)SDL.Vulkan_GetVkGetInstanceProcAddr()
    if vk3d_gipa == nil {
        fmt.eprintln("vk3d: vkGetInstanceProcAddr unavailable")
        return nil
    }
    vk.load_proc_addresses_custom(vk3d_set_proc)

    r := new(VK3D_Renderer)
    r.window    = window
    r.width     = width
    r.height    = height
    r.instances = make([dynamic]R3D_Instance)
    r.lights    = make([dynamic]R3D_Light)
    r.desc_cache = make(map[VK3D_Tex_Key]vk.DescriptorSet)
    r.mesh_tex_cache = make(map[vk.ImageView]vk.DescriptorSet)
    r.shadow_draws = make([dynamic]VK3D_Shadow_Draw)

    // sensible synthwave defaults (same as gl3d)
    r.ambient         = {0.10, 0.07, 0.16}
    r.bloom           = true
    r.bloom_strength  = 0.7
    r.bloom_threshold = 1.0
    r.exposure        = 1.1
    r.vignette        = 0.35

    // --- instance (extensions come from SDL) ---
    app_info := vk.ApplicationInfo{
        sType              = .APPLICATION_INFO,
        pApplicationName   = "voidengine",
        applicationVersion = vk.MAKE_VERSION(1, 0, 0),
        pEngineName        = "voidengine",
        engineVersion      = vk.MAKE_VERSION(1, 0, 0),
        apiVersion         = vk.API_VERSION_1_1,
    }
    ext_count: c.uint
    SDL.Vulkan_GetInstanceExtensions(window, &ext_count, nil)
    ext_names := make([]cstring, int(ext_count), context.temp_allocator)
    if !SDL.Vulkan_GetInstanceExtensions(window, &ext_count, raw_data(ext_names)) {
        fmt.eprintln("vk3d: SDL_Vulkan_GetInstanceExtensions failed")
        return nil
    }
    ici := vk.InstanceCreateInfo{
        sType                   = .INSTANCE_CREATE_INFO,
        pApplicationInfo        = &app_info,
        enabledExtensionCount   = u32(ext_count),
        ppEnabledExtensionNames = raw_data(ext_names),
    }
    if vk.CreateInstance(&ici, nil, &r.instance) != .SUCCESS {
        fmt.eprintln("vk3d: instance creation failed")
        return nil
    }
    vk.load_proc_addresses(r.instance)

    if !SDL.Vulkan_CreateSurface(window, r.instance, &r.surface) {
        fmt.eprintln("vk3d: surface creation failed")
        return nil
    }

    // --- physical device: graphics+present queue, swapchain ext, discrete preferred ---
    {
        pd_count: u32
        vk.EnumeratePhysicalDevices(r.instance, &pd_count, nil)
        if pd_count == 0 {
            fmt.eprintln("vk3d: no Vulkan devices")
            return nil
        }
        pds := make([]vk.PhysicalDevice, int(pd_count), context.temp_allocator)
        vk.EnumeratePhysicalDevices(r.instance, &pd_count, raw_data(pds))

        best_score := -1
        for pd in pds {
            family, ok := vk3d_find_queue_family(r.surface, pd)
            if !ok { continue }
            if !vk3d_device_has_extension(pd, vk.KHR_SWAPCHAIN_EXTENSION_NAME) { continue }
            score := 1
            props: vk.PhysicalDeviceProperties
            vk.GetPhysicalDeviceProperties(pd, &props)
            if props.deviceType == .DISCRETE_GPU {
                score = 1000
            }
            if score > best_score {
                best_score        = score
                r.physical_device = pd
                r.queue_family    = family
            }
        }
        if best_score < 0 {
            fmt.eprintln("vk3d: no suitable GPU (graphics+present+swapchain)")
            return nil
        }
    }

    // --- logical device ---
    {
        queue_prio := f32(1.0)
        qci := vk.DeviceQueueCreateInfo{
            sType            = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = r.queue_family,
            queueCount       = 1,
            pQueuePriorities = &queue_prio,
        }
        dev_exts := [1]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
        features := vk.PhysicalDeviceFeatures{samplerAnisotropy = true}
        dci := vk.DeviceCreateInfo{
            sType                   = .DEVICE_CREATE_INFO,
            queueCreateInfoCount    = 1,
            pQueueCreateInfos       = &qci,
            enabledExtensionCount   = 1,
            ppEnabledExtensionNames = &dev_exts[0],
            pEnabledFeatures        = &features,
        }
        if vk.CreateDevice(r.physical_device, &dci, nil, &r.device) != .SUCCESS {
            fmt.eprintln("vk3d: device creation failed")
            return nil
        }
    }
    vk.load_proc_addresses(r.device)
    vk.GetDeviceQueue(r.device, r.queue_family, 0, &r.queue)

    // --- command pool ---
    {
        cpci := vk.CommandPoolCreateInfo{
            sType            = .COMMAND_POOL_CREATE_INFO,
            flags            = {.RESET_COMMAND_BUFFER},
            queueFamilyIndex = r.queue_family,
        }
        if vk.CreateCommandPool(r.device, &cpci, nil, &r.cmd_pool) != .SUCCESS {
            fmt.eprintln("vk3d: command pool creation failed")
            return nil
        }
    }

    // --- descriptor set layouts ---
    {
        frame_binding := vk.DescriptorSetLayoutBinding{
            binding         = 0,
            descriptorType  = .UNIFORM_BUFFER,
            descriptorCount = 1,
            stageFlags      = {.VERTEX, .FRAGMENT},
        }
        frame_bindings := [2]vk.DescriptorSetLayoutBinding{
            frame_binding,
            {binding = 1, descriptorType = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        }
        ci := vk.DescriptorSetLayoutCreateInfo{
            sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            bindingCount = 2,
            pBindings    = &frame_bindings[0],
        }
        if vk.CreateDescriptorSetLayout(r.device, &ci, nil, &r.frame_set_layout) != .SUCCESS {
            fmt.eprintln("vk3d: frame set layout failed")
            return nil
        }

        tex_bindings := [2]vk.DescriptorSetLayoutBinding{
            {binding = 0, descriptorType = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
            {binding = 1, descriptorType = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        }
        ci.bindingCount = 2
        ci.pBindings    = &tex_bindings[0]
        if vk.CreateDescriptorSetLayout(r.device, &ci, nil, &r.tex_set_layout) != .SUCCESS {
            fmt.eprintln("vk3d: texture set layout failed")
            return nil
        }
        if vk.CreateDescriptorSetLayout(r.device, &ci, nil, &r.composite_set_layout) != .SUCCESS {
            fmt.eprintln("vk3d: composite set layout failed")
            return nil
        }

        post_binding := vk.DescriptorSetLayoutBinding{
            binding         = 0,
            descriptorType  = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = 1,
            stageFlags      = {.FRAGMENT},
        }
        ci.bindingCount = 1
        ci.pBindings    = &post_binding
        if vk.CreateDescriptorSetLayout(r.device, &ci, nil, &r.post_set_layout) != .SUCCESS {
            fmt.eprintln("vk3d: post set layout failed")
            return nil
        }
    }

    // --- descriptor pool ---
    {
        pool_sizes := [2]vk.DescriptorPoolSize{
            {type = .UNIFORM_BUFFER,         descriptorCount = VK3D_FRAMES_IN_FLIGHT},
            {type = .COMBINED_IMAGE_SAMPLER, descriptorCount = VK3D_MAX_TEX_SETS * 2 + 64},
        }
        ci := vk.DescriptorPoolCreateInfo{
            sType         = .DESCRIPTOR_POOL_CREATE_INFO,
            flags         = {.FREE_DESCRIPTOR_SET},
            maxSets       = VK3D_MAX_TEX_SETS + 64,
            poolSizeCount = 2,
            pPoolSizes    = &pool_sizes[0],
        }
        if vk.CreateDescriptorPool(r.device, &ci, nil, &r.desc_pool) != .SUCCESS {
            fmt.eprintln("vk3d: descriptor pool creation failed")
            return nil
        }
    }

    // --- pipeline layouts ---
    {
        // sprite: set 0 frame UBO, set 1 textures, push const use_normal_map
        sprite_sets := [2]vk.DescriptorSetLayout{r.frame_set_layout, r.tex_set_layout}
        push := vk.PushConstantRange{stageFlags = {.FRAGMENT}, offset = 0, size = 4}
        ci := vk.PipelineLayoutCreateInfo{
            sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
            setLayoutCount         = 2,
            pSetLayouts            = &sprite_sets[0],
            pushConstantRangeCount = 1,
            pPushConstantRanges    = &push,
        }
        if vk.CreatePipelineLayout(r.device, &ci, nil, &r.sprite_layout) != .SUCCESS {
            fmt.eprintln("vk3d: sprite pipeline layout failed")
            return nil
        }

        // post (bright/blur): set 0 one sampler, push consts p0+p1
        post_push := vk.PushConstantRange{stageFlags = {.FRAGMENT}, offset = 0, size = size_of(VK3D_Post_Push)}
        ci.setLayoutCount      = 1
        ci.pSetLayouts         = &r.post_set_layout
        ci.pPushConstantRanges = &post_push
        if vk.CreatePipelineLayout(r.device, &ci, nil, &r.post_layout) != .SUCCESS {
            fmt.eprintln("vk3d: post pipeline layout failed")
            return nil
        }

        // composite: set 0 two samplers, push consts p0+p1
        ci.pSetLayouts = &r.composite_set_layout
        if vk.CreatePipelineLayout(r.device, &ci, nil, &r.composite_layout) != .SUCCESS {
            fmt.eprintln("vk3d: composite pipeline layout failed")
            return nil
        }

        // mesh: set 0 frame UBO, set 1 single sampler, push consts model+params
        mesh_sets := [2]vk.DescriptorSetLayout{r.frame_set_layout, r.post_set_layout}
        mesh_push := vk.PushConstantRange{stageFlags = {.VERTEX, .FRAGMENT}, offset = 0, size = size_of(VK3D_Mesh_Push)}
        ci.setLayoutCount      = 2
        ci.pSetLayouts         = &mesh_sets[0]
        ci.pushConstantRangeCount = 1
        ci.pPushConstantRanges = &mesh_push
        if vk.CreatePipelineLayout(r.device, &ci, nil, &r.mesh_layout) != .SUCCESS {
            fmt.eprintln("vk3d: mesh pipeline layout failed")
            return nil
        }

        // shadow: set 0 frame UBO (+shadow sampler), push const model only
        shadow_sets := [1]vk.DescriptorSetLayout{r.frame_set_layout}
        shadow_push := vk.PushConstantRange{stageFlags = {.VERTEX}, offset = 0, size = 64}
        ci.setLayoutCount      = 1
        ci.pSetLayouts         = &shadow_sets[0]
        ci.pushConstantRangeCount = 1
        ci.pPushConstantRanges = &shadow_push
        if vk.CreatePipelineLayout(r.device, &ci, nil, &r.shadow_layout) != .SUCCESS {
            fmt.eprintln("vk3d: shadow pipeline layout failed")
            return nil
        }
    }

    // --- samplers ---
    r.sampler_repeat = vk3d_create_sampler(r, .REPEAT)
    r.sampler_clamp  = vk3d_create_sampler(r, .CLAMP_TO_EDGE)
    r.sampler_shadow = vk3d_create_shadow_sampler(r)

    // --- swapchain + render passes + offscreen targets ---
    if !vk3d_create_swapchain(r) { return nil }
    if !vk3d_create_render_passes(r) { return nil }
    vk3d_create_size_dependent(r)
    vk3d_create_shadow_target(r)

    // --- frames in flight ---
    for i in 0 ..< VK3D_FRAMES_IN_FLIGHT {
        f := &r.frames[i]
        ai := vk.CommandBufferAllocateInfo{
            sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
            commandPool        = r.cmd_pool,
            level              = .PRIMARY,
            commandBufferCount = 1,
        }
        vk.AllocateCommandBuffers(r.device, &ai, &f.cmd)
        sci := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
        vk.CreateSemaphore(r.device, &sci, nil, &f.image_available)
        vk.CreateSemaphore(r.device, &sci, nil, &f.render_finished)
        fci := vk.FenceCreateInfo{sType = .FENCE_CREATE_INFO, flags = {.SIGNALED}}
        vk.CreateFence(r.device, &fci, nil, &f.in_flight)

        f.ubo, f.ubo_memory = vk3d_create_buffer(
            r, size_of(R3D_Frame_Uniforms), {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
        )
        vk.MapMemory(r.device, f.ubo_memory, 0, size_of(R3D_Frame_Uniforms), {}, &f.ubo_mapped)
        set, ok := vk3d_alloc_desc_set(r, r.frame_set_layout)
        if !ok { return nil }
        f.ubo_set = set
        buf_info := vk.DescriptorBufferInfo{
            buffer = f.ubo,
            offset = 0,
            range  = size_of(R3D_Frame_Uniforms),
        }
        write := vk.WriteDescriptorSet{
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = set,
            dstBinding      = 0,
            descriptorCount = 1,
            descriptorType  = .UNIFORM_BUFFER,
            pBufferInfo     = &buf_info,
        }
        vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)

        // binding 1: shadow map sampler (same image for all frames)
        shadow_info := vk.DescriptorImageInfo{
            sampler     = r.sampler_shadow,
            imageView   = r.shadow_view,
            imageLayout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        }
        shadow_write := vk.WriteDescriptorSet{
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = set,
            dstBinding      = 1,
            descriptorCount = 1,
            descriptorType  = .COMBINED_IMAGE_SAMPLER,
            pImageInfo      = &shadow_info,
        }
        vk.UpdateDescriptorSets(r.device, 1, &shadow_write, 0, nil)

        f.inst_capacity = VK3D_INITIAL_INSTANCES
        f.inst_buf, f.inst_memory = vk3d_create_buffer(
            r, vk.DeviceSize(f.inst_capacity * R3D_INSTANCE_STRIDE), {.VERTEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
        )
        vk.MapMemory(r.device, f.inst_memory, 0, vk.DeviceSize(vk.WHOLE_SIZE), {}, &f.inst_mapped)
        f.retired = make([dynamic]VK3D_Retired_Buffer)
    }

    // --- sprite quad geometry (corner + uv interleaved, 4 verts) ---
    // uv convention matches gl3d: v=1 at corner -0.5 (bottom), v=0 at +0.5.
    {
        quad_verts := [?]f32{
            -0.5, -0.5, 0, 1,
             0.5, -0.5, 1, 1,
             0.5,  0.5, 1, 0,
            -0.5,  0.5, 0, 0,
        }
        quad_idx := [?]u16{0, 1, 2, 2, 3, 0}

        r.quad_vbo, r.quad_vbo_memory = vk3d_create_buffer(
            r, size_of(quad_verts), {.VERTEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
        )
        mapped: rawptr
        vk.MapMemory(r.device, r.quad_vbo_memory, 0, size_of(quad_verts), {}, &mapped)
        vdst := ([^]f32)(mapped)[:len(quad_verts)]
        copy(vdst, quad_verts[:])
        vk.UnmapMemory(r.device, r.quad_vbo_memory)

        r.quad_ebo, r.quad_ebo_memory = vk3d_create_buffer(
            r, size_of(quad_idx), {.INDEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
        )
        vk.MapMemory(r.device, r.quad_ebo_memory, 0, size_of(quad_idx), {}, &mapped)
        idst := ([^]u16)(mapped)[:len(quad_idx)]
        copy(idst, quad_idx[:])
        vk.UnmapMemory(r.device, r.quad_ebo_memory)
    }

    // --- flat normal map fallback (tangent-space up) ---
    {
        flat := [?]u8{128, 128, 255, 255}
        r.flat_normal = vk3d_upload_pixels(r, flat[:], 1, 1, false)
    }

    // --- pipelines (SPIR-V from shader_dir) ---
    {
        sprite_vert, ok_sv := vk3d_load_shader_module(r, shader_dir, "vk_sprite.vert")
        sprite_frag, ok_sf := vk3d_load_shader_module(r, shader_dir, "vk_sprite.frag")
        post_vert,   ok_pv := vk3d_load_shader_module(r, shader_dir, "vk_post.vert")
        bright_frag, ok_bf := vk3d_load_shader_module(r, shader_dir, "vk_bright.frag")
        blur_frag,   ok_uf := vk3d_load_shader_module(r, shader_dir, "vk_blur.frag")
        comp_frag,   ok_cf := vk3d_load_shader_module(r, shader_dir, "vk_composite.frag")
        mesh_vert,   ok_mv := vk3d_load_shader_module(r, shader_dir, "vk_mesh.vert")
        mesh_frag,   ok_mf := vk3d_load_shader_module(r, shader_dir, "vk_mesh.frag")
        shadow_vert, ok_wv := vk3d_load_shader_module(r, shader_dir, "vk_shadow.vert")
        if !(ok_sv && ok_sf && ok_pv && ok_bf && ok_uf && ok_cf && ok_mv && ok_mf && ok_wv) {
            fmt.eprintln("vk3d: shader load failed (run tools/compile-vk-shaders.sh)")
            return nil
        }
        defer {
            vk.DestroyShaderModule(r.device, sprite_vert, nil)
            vk.DestroyShaderModule(r.device, sprite_frag, nil)
            vk.DestroyShaderModule(r.device, post_vert, nil)
            vk.DestroyShaderModule(r.device, bright_frag, nil)
            vk.DestroyShaderModule(r.device, blur_frag, nil)
            vk.DestroyShaderModule(r.device, comp_frag, nil)
            vk.DestroyShaderModule(r.device, mesh_vert, nil)
            vk.DestroyShaderModule(r.device, mesh_frag, nil)
            vk.DestroyShaderModule(r.device, shadow_vert, nil)
        }

        if !vk3d_create_sprite_pipeline(r, sprite_vert, sprite_frag) { return nil }
        ok: bool
        r.bright_pipeline, ok = vk3d_create_post_pipeline(r, post_vert, bright_frag, r.post_layout, r.post_pass)
        if !ok { return nil }
        r.blur_pipeline, ok = vk3d_create_post_pipeline(r, post_vert, blur_frag, r.post_layout, r.post_pass)
        if !ok { return nil }
        r.composite_pipeline, ok = vk3d_create_post_pipeline(r, post_vert, comp_frag, r.composite_layout, r.composite_pass)
        if !ok { return nil }
        if !vk3d_create_mesh_pipeline(r, mesh_vert, mesh_frag) { return nil }
        if !vk3d_create_shadow_pipeline(r, shadow_vert) { return nil }
    }

    return r
}

vk3d_shutdown :: proc(r: ^VK3D_Renderer) {
    if r == nil { return }
    vk.DeviceWaitIdle(r.device)

    vk3d_destroy_texture(r, r.flat_normal)

    for i in 0 ..< VK3D_FRAMES_IN_FLIGHT {
        f := &r.frames[i]
        vk.DestroySemaphore(r.device, f.image_available, nil)
        vk.DestroySemaphore(r.device, f.render_finished, nil)
        vk.DestroyFence(r.device, f.in_flight, nil)
        vk.DestroyBuffer(r.device, f.ubo, nil)
        vk.FreeMemory(r.device, f.ubo_memory, nil)
        vk.DestroyBuffer(r.device, f.inst_buf, nil)
        vk.FreeMemory(r.device, f.inst_memory, nil)
        for rb in f.retired {
            vk.DestroyBuffer(r.device, rb.buf, nil)
            vk.FreeMemory(r.device, rb.mem, nil)
        }
        delete(f.retired)
    }

    vk.DestroyBuffer(r.device, r.quad_vbo, nil)
    vk.FreeMemory(r.device, r.quad_vbo_memory, nil)
    vk.DestroyBuffer(r.device, r.quad_ebo, nil)
    vk.FreeMemory(r.device, r.quad_ebo_memory, nil)

    vk.DestroyPipeline(r.device, r.sprite_pipeline, nil)
    vk.DestroyPipeline(r.device, r.bright_pipeline, nil)
    vk.DestroyPipeline(r.device, r.blur_pipeline, nil)
    vk.DestroyPipeline(r.device, r.composite_pipeline, nil)
    vk.DestroyPipeline(r.device, r.mesh_pipeline, nil)
    vk.DestroyPipeline(r.device, r.shadow_pipeline, nil)
    vk.DestroyPipelineLayout(r.device, r.sprite_layout, nil)
    vk.DestroyPipelineLayout(r.device, r.post_layout, nil)
    vk.DestroyPipelineLayout(r.device, r.composite_layout, nil)
    vk.DestroyPipelineLayout(r.device, r.mesh_layout, nil)
    vk.DestroyPipelineLayout(r.device, r.shadow_layout, nil)
    vk.DestroyRenderPass(r.device, r.shadow_pass, nil)
    vk.DestroyFramebuffer(r.device, r.shadow_fb, nil)
    vk.DestroyImageView(r.device, r.shadow_view, nil)
    vk.DestroyImage(r.device, r.shadow_image, nil)
    vk.FreeMemory(r.device, r.shadow_memory, nil)
    vk.DestroySampler(r.device, r.sampler_shadow, nil)
    delete(r.shadow_draws)

    vk3d_destroy_size_dependent(r)

    vk.DestroyRenderPass(r.device, r.scene_pass, nil)
    vk.DestroyRenderPass(r.device, r.post_pass, nil)
    vk.DestroyRenderPass(r.device, r.composite_pass, nil)

    vk.DestroySampler(r.device, r.sampler_repeat, nil)
    vk.DestroySampler(r.device, r.sampler_clamp, nil)

    vk.DestroyDescriptorPool(r.device, r.desc_pool, nil)
    vk.DestroyDescriptorSetLayout(r.device, r.frame_set_layout, nil)
    vk.DestroyDescriptorSetLayout(r.device, r.tex_set_layout, nil)
    vk.DestroyDescriptorSetLayout(r.device, r.post_set_layout, nil)
    vk.DestroyDescriptorSetLayout(r.device, r.composite_set_layout, nil)

    vk.DestroyCommandPool(r.device, r.cmd_pool, nil)
    vk.DestroyDevice(r.device, nil)
    vk.DestroySurfaceKHR(r.instance, r.surface, nil)
    vk.DestroyInstance(r.instance, nil)
    SDL.Vulkan_UnloadLibrary()

    delete(r.instances)
    delete(r.lights)
    delete(r.desc_cache)
    free(r)
}

vk3d_resize :: proc(r: ^VK3D_Renderer, width, height: i32) {
    if r == nil || width <= 0 || height <= 0 { return }
    r.width  = width
    r.height = height
    vk3d_recreate_swapchain(r)
}

// ----------------------------------------------------------------------------
// Textures
// ----------------------------------------------------------------------------

// Upload raw RGBA8 pixels as a texture (staging buffer -> device local image).
@(private)
vk3d_upload_pixels :: proc(r: ^VK3D_Renderer, pixels: []u8, w, h: i32, repeat := false) -> VK3D_Texture {
    tex: VK3D_Texture
    img_size := vk.DeviceSize(w * h * 4)

    staging, staging_mem := vk3d_create_buffer(r, img_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
    mapped: rawptr
    vk.MapMemory(r.device, staging_mem, 0, img_size, {}, &mapped)
    dst := ([^]u8)(mapped)[:int(img_size)]
    copy(dst, pixels)
    vk.UnmapMemory(r.device, staging_mem)

    mip_levels := u32(1)
    {
        // floor(log2(max(w,h))) + 1
        m := max(w, h)
        for m > 1 { m >>= 1; mip_levels += 1 }
    }
    tex.image, tex.memory = vk3d_create_image(r, u32(w), u32(h), .R8G8B8A8_UNORM, {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED}, mip_levels)

    cmd := vk3d_begin_one_shot(r)

    to_transfer := vk.ImageMemoryBarrier{
        sType               = .IMAGE_MEMORY_BARRIER,
        srcAccessMask       = {},
        dstAccessMask       = {.TRANSFER_WRITE},
        oldLayout           = .UNDEFINED,
        newLayout           = .TRANSFER_DST_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image               = tex.image,
        subresourceRange    = {aspectMask = {.COLOR}, levelCount = mip_levels, layerCount = 1},
    }
    vk.CmdPipelineBarrier(cmd, {.TOP_OF_PIPE}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &to_transfer)

    region := vk.BufferImageCopy{
        imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
        imageExtent      = {width = u32(w), height = u32(h), depth = 1},
    }
    vk.CmdCopyBufferToImage(cmd, staging, tex.image, .TRANSFER_DST_OPTIMAL, 1, &region)

    // generate the mip chain: blit level i-1 -> i, then move i-1 to SHADER_READ
    mip_w, mip_h := w, h
    for level in u32(1) ..< mip_levels {
        to_src := vk.ImageMemoryBarrier{
            sType               = .IMAGE_MEMORY_BARRIER,
            srcAccessMask       = {.TRANSFER_WRITE},
            dstAccessMask       = {.TRANSFER_READ},
            oldLayout           = .TRANSFER_DST_OPTIMAL,
            newLayout           = .TRANSFER_SRC_OPTIMAL,
            srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            image               = tex.image,
            subresourceRange    = {aspectMask = {.COLOR}, baseMipLevel = level - 1, levelCount = 1, layerCount = 1},
        }
        vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &to_src)

        next_w := max(mip_w / 2, 1)
        next_h := max(mip_h / 2, 1)
        blit := vk.ImageBlit{
            srcSubresource = {aspectMask = {.COLOR}, mipLevel = level - 1, baseArrayLayer = 0, layerCount = 1},
            srcOffsets     = {{0, 0, 0}, {mip_w, mip_h, 1}},
            dstSubresource = {aspectMask = {.COLOR}, mipLevel = level, baseArrayLayer = 0, layerCount = 1},
            dstOffsets     = {{0, 0, 0}, {next_w, next_h, 1}},
        }
        vk.CmdBlitImage(cmd, tex.image, .TRANSFER_SRC_OPTIMAL, tex.image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

        to_read := vk.ImageMemoryBarrier{
            sType               = .IMAGE_MEMORY_BARRIER,
            srcAccessMask       = {.TRANSFER_READ},
            dstAccessMask       = {.SHADER_READ},
            oldLayout           = .TRANSFER_SRC_OPTIMAL,
            newLayout           = .SHADER_READ_ONLY_OPTIMAL,
            srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
            image               = tex.image,
            subresourceRange    = {aspectMask = {.COLOR}, baseMipLevel = level - 1, levelCount = 1, layerCount = 1},
        }
        vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &to_read)

        mip_w, mip_h = next_w, next_h
    }

    // last level: TRANSFER_DST -> SHADER_READ
    to_shader := vk.ImageMemoryBarrier{
        sType               = .IMAGE_MEMORY_BARRIER,
        srcAccessMask       = {.TRANSFER_WRITE},
        dstAccessMask       = {.SHADER_READ},
        oldLayout           = .TRANSFER_DST_OPTIMAL,
        newLayout           = .SHADER_READ_ONLY_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image               = tex.image,
        subresourceRange    = {aspectMask = {.COLOR}, baseMipLevel = mip_levels - 1, levelCount = 1, layerCount = 1},
    }
    vk.CmdPipelineBarrier(cmd, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &to_shader)

    vk3d_end_one_shot(r, cmd)

    vk.DestroyBuffer(r.device, staging, nil)
    vk.FreeMemory(r.device, staging_mem, nil)

    tex.view    = vk3d_create_image_view(r, tex.image, .R8G8B8A8_UNORM, {.COLOR}, mip_levels)
    tex.sampler = repeat ? r.sampler_repeat : r.sampler_clamp
    return tex
}

// Load a PNG (or other image format) from disk as an RGBA8 texture.
// Same loading path as gl3d_load_texture (core:image, 3->4 channel expand).
vk3d_load_texture :: proc(r: ^VK3D_Renderer, path: string, repeat := false) -> (tex: VK3D_Texture, w, h: i32, ok: bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("vk3d: cannot read texture file:", path)
        return {}, 0, 0, false
    }
    defer delete(data)

    img, err := image.load_from_bytes(data)
    if err != nil || img == nil {
        fmt.eprintln("vk3d: cannot decode texture:", path)
        return {}, 0, 0, false
    }
    w = i32(img.width)
    h = i32(img.height)
    src := img.pixels.buf[:]

    rgba: []u8
    if img.channels == 4 {
        rgba = src
    } else if img.channels == 3 {
        rgba = make([]u8, w * h * 4)
        for i in 0 ..< int(w * h) {
            rgba[i * 4 + 0] = src[i * 3 + 0]
            rgba[i * 4 + 1] = src[i * 3 + 1]
            rgba[i * 4 + 2] = src[i * 3 + 2]
            rgba[i * 4 + 3] = 255
        }
        defer delete(rgba)
    } else {
        fmt.eprintln("vk3d: unsupported channel count in:", path)
        return {}, 0, 0, false
    }

    tex = vk3d_upload_pixels(r, rgba, w, h, repeat)
    return tex, w, h, true
}

vk3d_destroy_texture :: proc(r: ^VK3D_Renderer, tex: VK3D_Texture) {
    if r == nil || tex.image == 0 { return }
    vk.DeviceWaitIdle(r.device)

    // drop cached sprite descriptor sets referencing this texture
    doomed := make([dynamic]VK3D_Tex_Key, context.temp_allocator)
    for k, v in r.desc_cache {
        if k.diffuse == tex.view || k.normal == tex.view {
            append(&doomed, k)
            set := v
            vk.FreeDescriptorSets(r.device, r.desc_pool, 1, &set)
        }
    }
    for k in doomed {
        delete_key(&r.desc_cache, k)
    }

    if tex.view != 0 {
        vk.DestroyImageView(r.device, tex.view, nil)
    }
    vk.DestroyImage(r.device, tex.image, nil)
    vk.FreeMemory(r.device, tex.memory, nil)
}

// ----------------------------------------------------------------------------
// Frame API
// ----------------------------------------------------------------------------

vk3d_set_camera :: proc(r: ^VK3D_Renderer, cam: ^R3D_Camera) {
    r.camera = cam^
}

vk3d_set_ambient :: proc(r: ^VK3D_Renderer, ambient: linalg.Vector3f32) {
    r.ambient = ambient
}

vk3d_clear_lights :: proc(r: ^VK3D_Renderer) {
    clear(&r.lights)
}

vk3d_add_light :: proc(r: ^VK3D_Renderer, light: R3D_Light) {
    if len(r.lights) < R3D_MAX_LIGHTS {
        append(&r.lights, light)
    }
}

// Grow the per-frame instance buffer if needed. The old buffer is retired
// and destroyed after this frame's fence next waits (it may be referenced
// by commands already recorded this frame).
@(private)
vk3d_ensure_inst_capacity :: proc(r: ^VK3D_Renderer, f: ^VK3D_Frame, needed: int) {
    if needed <= f.inst_capacity { return }
    new_cap := max(f.inst_capacity * 2, needed)
    if f.inst_buf != 0 {
        append(&f.retired, VK3D_Retired_Buffer{buf = f.inst_buf, mem = f.inst_memory})
    }
    f.inst_buf, f.inst_memory = vk3d_create_buffer(
        r, vk.DeviceSize(new_cap * R3D_INSTANCE_STRIDE), {.VERTEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
    )
    vk.MapMemory(r.device, f.inst_memory, 0, vk.DeviceSize(vk.WHOLE_SIZE), {}, &f.inst_mapped)
    f.inst_capacity = new_cap
}

@(private)
vk3d_set_viewport :: proc(cmd: vk.CommandBuffer, w, h: i32) {
    // Positive viewport height: r3d_perspective_vk already flips Y and
    // maps z to [0, 1] for Vulkan clip conventions.
    viewport := vk.Viewport{x = 0, y = 0, width = f32(w), height = f32(h), minDepth = 0, maxDepth = 1}
    scissor  := vk.Rect2D{offset = {x = 0, y = 0}, extent = {width = u32(w), height = u32(h)}}
    vk.CmdSetViewport(cmd, 0, 1, &viewport)
    vk.CmdSetScissor(cmd, 0, 1, &scissor)
}

// Acquire a swapchain image and open the scene render pass.
// Returns false when the swapchain is out of date — skip the frame.
vk3d_begin_frame :: proc(r: ^VK3D_Renderer) -> bool {
    frame := &r.frames[r.frame_index]
    vk.WaitForFences(r.device, 1, &frame.in_flight, true, ~u64(0))

    // safe to destroy buffers retired by this frame's previous submission
    for rb in frame.retired {
        vk.DestroyBuffer(r.device, rb.buf, nil)
        vk.FreeMemory(r.device, rb.mem, nil)
    }
    clear(&frame.retired)

    res := vk.AcquireNextImageKHR(r.device, r.swapchain, ~u64(0), frame.image_available, 0, &r.swap_image_index)
    if res == .ERROR_OUT_OF_DATE_KHR {
        vk3d_recreate_swapchain(r)
        return false
    }

    vk.ResetFences(r.device, 1, &frame.in_flight)
    vk.ResetCommandBuffer(frame.cmd, {})
    bi := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    }
    vk.BeginCommandBuffer(frame.cmd, &bi)

    // sun shadow pass (queued casters) renders before the scene
    vk3d_record_shadow_pass(r, frame)

    clears := [2]vk.ClearValue{
        {color = {float32 = {0.02, 0.01, 0.05, 1.0}}},
        {depthStencil = {depth = 1.0, stencil = 0}},
    }
    rpbi := vk.RenderPassBeginInfo{
        sType           = .RENDER_PASS_BEGIN_INFO,
        renderPass      = r.scene_pass,
        framebuffer     = r.scene.framebuffer,
        renderArea      = {offset = {x = 0, y = 0}, extent = {width = u32(r.width), height = u32(r.height)}},
        clearValueCount = 2,
        pClearValues    = &clears[0],
    }
    vk.CmdBeginRenderPass(frame.cmd, &rpbi, .INLINE)
    vk.CmdBindPipeline(frame.cmd, .GRAPHICS, r.sprite_pipeline)
    vk3d_set_viewport(frame.cmd, r.width, r.height)

    clear(&r.instances)
    r.inst_frame_base = 0
    r.cur_diffuse = 0
    r.cur_normal  = 0
    return true
}

// Queue a sprite for rendering. normal may be the zero VK3D_Texture (flat).
vk3d_draw_sprite_opts :: proc(
    r:       ^VK3D_Renderer,
    diffuse: VK3D_Texture,
    normal:  VK3D_Texture,
    pos:     linalg.Vector3f32,
    size:    linalg.Vector2f32,
    opts:    R3D_Sprite_Options,
) {
    if diffuse.view == 0 { return }
    eff_normal := normal.view != 0 ? normal : r.flat_normal
    if diffuse.view != r.cur_diffuse || eff_normal.view != r.cur_normal {
        vk3d_flush(r)
        r.cur_diffuse     = diffuse.view
        r.cur_normal      = eff_normal.view
        r.cur_diffuse_tex = diffuse
        r.cur_normal_tex  = eff_normal
        r.cur_use_normal  = normal.view != 0 ? 1 : 0
    }
    append(&r.instances, r3d_make_instance(&r.camera, pos, size, opts))
}

// Queue a sprite with default options.
vk3d_draw_sprite :: proc(r: ^VK3D_Renderer, diffuse, normal: VK3D_Texture, pos: linalg.Vector3f32, size: linalg.Vector2f32) {
    vk3d_draw_sprite_opts(r, diffuse, normal, pos, size, r3d_default_sprite_options())
}

// Record the queued instance batch (called automatically on texture switch
// and at end_frame).
vk3d_flush :: proc(r: ^VK3D_Renderer) {
    n := len(r.instances)
    if n == 0 || r.cur_diffuse == 0 { return }

    frame := &r.frames[r.frame_index]
    cmd := frame.cmd

    // rebind: mesh draws switch pipelines, so sprite batches must restore
    vk.CmdBindPipeline(cmd, .GRAPHICS, r.sprite_pipeline)

    // frame uniforms — note: with deferred command recording the last write
    // of the frame applies to all batches, so set camera/lights before drawing
    // (same as typical gl3d usage).
    aspect := f32(r.width) / f32(max(r.height, 1))
    uniforms := r3d_make_frame_uniforms(&r.camera, aspect, true, r.ambient, r.lights[:], &r.sun)
    (^R3D_Frame_Uniforms)(frame.ubo_mapped)^ = uniforms

    // stream instances into the per-frame buffer AFTER previously flushed
    // batches — recorded draws read this buffer at draw-execution time, so
    // each batch must occupy its own region (never overwrite offset 0).
    vk3d_ensure_inst_capacity(r, frame, r.inst_frame_base + n)
    dst := ([^]R3D_Instance)(frame.inst_mapped)[r.inst_frame_base:r.inst_frame_base + n]
    copy(dst, r.instances[:])

    tex_set, ok := vk3d_get_tex_set(r, r.cur_diffuse_tex, r.cur_normal_tex)
    if !ok {
        clear(&r.instances)
        return
    }
    sets := [2]vk.DescriptorSet{frame.ubo_set, tex_set}
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, r.sprite_layout, 0, 2, &sets[0], 0, nil)

    use_normal := r.cur_use_normal
    vk.CmdPushConstants(cmd, r.sprite_layout, {.FRAGMENT}, 0, 4, &use_normal)

    vbos    := [2]vk.Buffer{r.quad_vbo, frame.inst_buf}
    offsets := [2]vk.DeviceSize{0, vk.DeviceSize(r.inst_frame_base * R3D_INSTANCE_STRIDE)}
    vk.CmdBindVertexBuffers(cmd, 0, 2, &vbos[0], &offsets[0])
    vk.CmdBindIndexBuffer(cmd, r.quad_ebo, 0, .UINT16)
    vk.CmdDrawIndexed(cmd, 6, u32(n), 0, 0, 0)

    r.inst_frame_base += n
    clear(&r.instances)
}

// Transition a post target into COLOR_ATTACHMENT_OPTIMAL and begin the post
// render pass on it. The pass's final layout is SHADER_READ_ONLY_OPTIMAL.
@(private)
vk3d_begin_post_pass :: proc(r: ^VK3D_Renderer, cmd: vk.CommandBuffer, dst: ^VK3D_Target) {
    src_stage:  vk.PipelineStageFlags = {.TOP_OF_PIPE}
    src_access: vk.AccessFlags        = {}
    if dst.layout == .SHADER_READ_ONLY_OPTIMAL {
        src_stage  = {.FRAGMENT_SHADER}
        src_access = {.SHADER_READ}
    }
    barrier := vk.ImageMemoryBarrier{
        sType               = .IMAGE_MEMORY_BARRIER,
        srcAccessMask       = src_access,
        dstAccessMask       = {.COLOR_ATTACHMENT_WRITE},
        oldLayout           = dst.layout,
        newLayout           = .COLOR_ATTACHMENT_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image               = dst.image,
        subresourceRange    = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
    }
    vk.CmdPipelineBarrier(cmd, src_stage, {.COLOR_ATTACHMENT_OUTPUT}, {}, 0, nil, 0, nil, 1, &barrier)

    clear := vk.ClearValue{color = {float32 = {0, 0, 0, 1}}}
    rpbi := vk.RenderPassBeginInfo{
        sType           = .RENDER_PASS_BEGIN_INFO,
        renderPass      = r.post_pass,
        framebuffer     = dst.framebuffer,
        renderArea      = {offset = {x = 0, y = 0}, extent = {width = u32(r.post_w), height = u32(r.post_h)}},
        clearValueCount = 1,
        pClearValues    = &clear,
    }
    vk.CmdBeginRenderPass(cmd, &rpbi, .INLINE)
    vk3d_set_viewport(cmd, r.post_w, r.post_h)
    dst.layout = .SHADER_READ_ONLY_OPTIMAL // final layout once the pass ends
}

// Flush batches, run the post chain (bright -> 4x blur -> composite), present.
vk3d_end_frame :: proc(r: ^VK3D_Renderer) {
    vk3d_flush(r)

    frame := &r.frames[r.frame_index]
    cmd := frame.cmd
    vk.CmdEndRenderPass(cmd) // scene pass -> scene target is SHADER_READ_ONLY

    // --- bright pass: scene -> bright_a (half res) ---
    vk3d_begin_post_pass(r, cmd, &r.bright_a)
    vk.CmdBindPipeline(cmd, .GRAPHICS, r.bright_pipeline)
    bright_push := VK3D_Post_Push{p0 = {0, 0, 0, 0}, p1 = {r.bloom_threshold, 0, 0, 0}}
    vk.CmdPushConstants(cmd, r.post_layout, {.FRAGMENT}, 0, size_of(VK3D_Post_Push), &bright_push)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, r.post_layout, 0, 1, &r.scene.post_set, 0, nil)
    vk.CmdDraw(cmd, 3, 1, 0, 0)
    vk.CmdEndRenderPass(cmd)

    // --- separable blur: 4 passes ping-ponging the two half-res targets ---
    src := &r.bright_a
    for i in 0 ..< 4 {
        dst_t := &r.blur[i % 2]
        vk3d_begin_post_pass(r, cmd, dst_t)
        vk.CmdBindPipeline(cmd, .GRAPHICS, r.blur_pipeline)
        blur_push := VK3D_Post_Push{}
        if i % 2 == 0 {
            blur_push.p0 = {1.5 / f32(r.post_w), 0, 0, 0}
        } else {
            blur_push.p0 = {0, 1.5 / f32(r.post_h), 0, 0}
        }
        vk.CmdPushConstants(cmd, r.post_layout, {.FRAGMENT}, 0, size_of(VK3D_Post_Push), &blur_push)
        vk.CmdBindDescriptorSets(cmd, .GRAPHICS, r.post_layout, 0, 1, &src.post_set, 0, nil)
        vk.CmdDraw(cmd, 3, 1, 0, 0)
        vk.CmdEndRenderPass(cmd)
        src = dst_t
    }

    // --- composite: scene + bloom -> swapchain ---
    {
        clear := vk.ClearValue{color = {float32 = {0, 0, 0, 1}}}
        rpbi := vk.RenderPassBeginInfo{
            sType           = .RENDER_PASS_BEGIN_INFO,
            renderPass      = r.composite_pass,
            framebuffer     = r.swap_framebuffers[r.swap_image_index],
            renderArea      = {offset = {x = 0, y = 0}, extent = r.swap_extent},
            clearValueCount = 1,
            pClearValues    = &clear,
        }
        vk.CmdBeginRenderPass(cmd, &rpbi, .INLINE)
        vk3d_set_viewport(cmd, r.width, r.height)
        vk.CmdBindPipeline(cmd, .GRAPHICS, r.composite_pipeline)
        comp_push := VK3D_Post_Push{
            p0 = {0, 0, 0, 0},
            p1 = {r.bloom ? 1.0 : 0.0, r.bloom_strength, r.exposure, r.vignette},
        }
        vk.CmdPushConstants(cmd, r.composite_layout, {.FRAGMENT}, 0, size_of(VK3D_Post_Push), &comp_push)
        vk.CmdBindDescriptorSets(cmd, .GRAPHICS, r.composite_layout, 0, 1, &r.composite_set, 0, nil)
        vk.CmdDraw(cmd, 3, 1, 0, 0)
        vk.CmdEndRenderPass(cmd)
    }

    vk.EndCommandBuffer(cmd)

    // --- submit + present ---
    wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
    submit := vk.SubmitInfo{
        sType                = .SUBMIT_INFO,
        waitSemaphoreCount   = 1,
        pWaitSemaphores      = &frame.image_available,
        pWaitDstStageMask    = &wait_stage,
        commandBufferCount   = 1,
        pCommandBuffers      = &cmd,
        signalSemaphoreCount = 1,
        pSignalSemaphores    = &frame.render_finished,
    }
    vk.QueueSubmit(r.queue, 1, &submit, frame.in_flight)

    present := vk.PresentInfoKHR{
        sType              = .PRESENT_INFO_KHR,
        waitSemaphoreCount = 1,
        pWaitSemaphores    = &frame.render_finished,
        swapchainCount     = 1,
        pSwapchains        = &r.swapchain,
        pImageIndices      = &r.swap_image_index,
    }
    res := vk.QueuePresentKHR(r.queue, &present)
    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR {
        vk3d_recreate_swapchain(r)
    }

    r.frame_index = (r.frame_index + 1) % VK3D_FRAMES_IN_FLIGHT
}

// ----------------------------------------------------------------------------
// Meshes
// ----------------------------------------------------------------------------

// Upload mesh data to the GPU (host-visible; meshes are treated as static).
vk3d_upload_mesh :: proc(r: ^VK3D_Renderer, data: ^R3D_Mesh_Data) -> VK3D_Mesh {
    mesh: VK3D_Mesh
    mesh.index_count = i32(len(data.indices))
    if len(data.vertices) == 0 || len(data.indices) == 0 { return mesh }

    mesh.vbo, mesh.vbo_memory = vk3d_create_buffer(
        r, vk.DeviceSize(len(data.vertices) * R3D_VERTEX_STRIDE), {.VERTEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
    )
    vmapped: rawptr
    vk.MapMemory(r.device, mesh.vbo_memory, 0, vk.DeviceSize(vk.WHOLE_SIZE), {}, &vmapped)
    vdst := ([^]R3D_Vertex)(vmapped)[:len(data.vertices)]
    copy(vdst, data.vertices[:])
    vk.UnmapMemory(r.device, mesh.vbo_memory)

    mesh.ebo, mesh.ebo_memory = vk3d_create_buffer(
        r, vk.DeviceSize(len(data.indices) * size_of(u32)), {.INDEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT},
    )
    imapped: rawptr
    vk.MapMemory(r.device, mesh.ebo_memory, 0, vk.DeviceSize(vk.WHOLE_SIZE), {}, &imapped)
    idst := ([^]u32)(imapped)[:len(data.indices)]
    copy(idst, data.indices[:])
    vk.UnmapMemory(r.device, mesh.ebo_memory)
    return mesh
}

vk3d_destroy_mesh :: proc(r: ^VK3D_Renderer, mesh: ^VK3D_Mesh) {
    if mesh.vbo != 0 {
        vk.DestroyBuffer(r.device, mesh.vbo, nil)
        vk.FreeMemory(r.device, mesh.vbo_memory, nil)
    }
    if mesh.ebo != 0 {
        vk.DestroyBuffer(r.device, mesh.ebo, nil)
        vk.FreeMemory(r.device, mesh.ebo_memory, nil)
    }
    mesh^ = {}
}

// Single-sampler descriptor set for a mesh texture (cached per view).
@(private)
vk3d_get_mesh_tex_set :: proc(r: ^VK3D_Renderer, tex: VK3D_Texture) -> (vk.DescriptorSet, bool) {
    if set, ok := r.mesh_tex_cache[tex.view]; ok {
        return set, true
    }
    set, ok := vk3d_alloc_desc_set(r, r.post_set_layout) // set 0: 1 sampler
    if !ok { return 0, false }
    info := vk.DescriptorImageInfo{
        sampler     = tex.sampler,
        imageView   = tex.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    write := vk.WriteDescriptorSet{
        sType           = .WRITE_DESCRIPTOR_SET,
        dstSet          = set,
        dstBinding      = 0,
        descriptorCount = 1,
        descriptorType  = .COMBINED_IMAGE_SAMPLER,
        pImageInfo      = &info,
    }
    vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
    r.mesh_tex_cache[tex.view] = set
    return set, true
}

// Record a mesh draw into the current frame (texture may be the zero
// VK3D_Texture for flat color). Flushes pending sprites first to keep
// submission order; depth testing makes the rest order-independent.
vk3d_draw_mesh_opts :: proc(r: ^VK3D_Renderer, mesh: ^VK3D_Mesh, texture: VK3D_Texture, model: linalg.Matrix4f32, opts: R3D_Mesh_Options) {
    if mesh.index_count == 0 { return }
    vk3d_flush(r)

    frame := &r.frames[r.frame_index]
    cmd := frame.cmd

    // frame uniforms (same values as sprite batches this frame)
    aspect := f32(r.width) / f32(max(r.height, 1))
    uniforms := r3d_make_frame_uniforms(&r.camera, aspect, true, r.ambient, r.lights[:], &r.sun)
    (^R3D_Frame_Uniforms)(frame.ubo_mapped)^ = uniforms

    tex := texture
    has_tex := tex.view != 0
    if !has_tex {
        tex = r.flat_normal // dummy binding; shader ignores it
    }
    tex_set, ok := vk3d_get_mesh_tex_set(r, tex)
    if !ok { return }

    vk.CmdBindPipeline(cmd, .GRAPHICS, r.mesh_pipeline)
    sets := [2]vk.DescriptorSet{frame.ubo_set, tex_set}
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, r.mesh_layout, 0, 2, &sets[0], 0, nil)

    push := VK3D_Mesh_Push{
        model  = model,
        color  = opts.color,
        params = {opts.spec_strength, opts.shininess, opts.emissive, has_tex ? 1 : 0},
        misc   = {opts.uv_tiling.x, opts.uv_tiling.y, 0, 0},
    }
    vk.CmdPushConstants(cmd, r.mesh_layout, {.VERTEX, .FRAGMENT}, 0, size_of(VK3D_Mesh_Push), &push)

    vbo := mesh.vbo
    offset := vk.DeviceSize(0)
    vk.CmdBindVertexBuffers(cmd, 0, 1, &vbo, &offset)
    vk.CmdBindIndexBuffer(cmd, mesh.ebo, 0, .UINT32)
    vk.CmdDrawIndexed(cmd, u32(mesh.index_count), 1, 0, 0, 0)
}

// Draw a mesh with default options.
vk3d_draw_mesh :: proc(r: ^VK3D_Renderer, mesh: ^VK3D_Mesh, texture: VK3D_Texture, model: linalg.Matrix4f32) {
    vk3d_draw_mesh_opts(r, mesh, texture, model, r3d_default_mesh_options())
}

@(private)
vk3d_create_mesh_pipeline :: proc(r: ^VK3D_Renderer, vert, frag: vk.ShaderModule) -> bool {
    stages := [2]vk.PipelineShaderStageCreateInfo{
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX},   module = vert, pName = "main"},
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag, pName = "main"},
    }

    // binding 0: interleaved R3D_Vertex (pos@0, normal@12, uv@24, stride 32)
    binding := vk.VertexInputBindingDescription{binding = 0, stride = R3D_VERTEX_STRIDE, inputRate = .VERTEX}
    attrs := [3]vk.VertexInputAttributeDescription{
        {location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(R3D_Vertex, pos))},
        {location = 1, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(R3D_Vertex, normal))},
        {location = 2, binding = 0, format = .R32G32_SFLOAT,    offset = u32(offset_of(R3D_Vertex, uv))},
    }
    vi := vk.PipelineVertexInputStateCreateInfo{
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = 3,
        pVertexAttributeDescriptions    = &attrs[0],
    }
    ia := vk.PipelineInputAssemblyStateCreateInfo{
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }
    vp := vk.PipelineViewportStateCreateInfo{
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount  = 1,
    }
    rs := vk.PipelineRasterizationStateCreateInfo{
        sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode = .FILL,
        cullMode    = {},  // off: the Y-flipped projection inverts winding
        frontFace   = .COUNTER_CLOCKWISE,
        lineWidth   = 1.0,
    }
    ms := vk.PipelineMultisampleStateCreateInfo{
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
    }
    ds := vk.PipelineDepthStencilStateCreateInfo{
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = true,
        depthWriteEnable = true,
        depthCompareOp   = .LESS,
    }
    blend_att := vk.PipelineColorBlendAttachmentState{
        blendEnable         = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp        = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
        alphaBlendOp        = .ADD,
        colorWriteMask      = {.R, .G, .B, .A},
    }
    cb := vk.PipelineColorBlendStateCreateInfo{
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 1,
        pAttachments    = &blend_att,
    }
    dyn_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    dyn := vk.PipelineDynamicStateCreateInfo{
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = &dyn_states[0],
    }
    ci := vk.GraphicsPipelineCreateInfo{
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount          = 2,
        pStages             = &stages[0],
        pVertexInputState   = &vi,
        pInputAssemblyState = &ia,
        pViewportState      = &vp,
        pRasterizationState = &rs,
        pMultisampleState   = &ms,
        pDepthStencilState  = &ds,
        pColorBlendState    = &cb,
        pDynamicState       = &dyn,
        layout              = r.mesh_layout,
        renderPass          = r.scene_pass,
        subpass             = 0,
    }
    if vk.CreateGraphicsPipelines(r.device, 0, 1, &ci, nil, &r.mesh_pipeline) != .SUCCESS {
        fmt.eprintln("vk3d: mesh pipeline creation failed")
        return false
    }
    return true
}

// ----------------------------------------------------------------------------
// Shadow pass (sun): depth-only rendering of queued casters from the sun's
// orthographic view. Queue casters with vk3d_draw_mesh_shadow BEFORE
// vk3d_begin_frame; the pass is recorded at the top of the frame.
// ----------------------------------------------------------------------------

@(private)
vk3d_create_shadow_sampler :: proc(r: ^VK3D_Renderer) -> vk.Sampler {
    sci := vk.SamplerCreateInfo{
        sType        = .SAMPLER_CREATE_INFO,
        magFilter    = .NEAREST,
        minFilter    = .NEAREST,
        mipmapMode   = .NEAREST,
        addressModeU = .CLAMP_TO_EDGE,
        addressModeV = .CLAMP_TO_EDGE,
        addressModeW = .CLAMP_TO_EDGE,
        minLod       = 0,
        maxLod       = 0,
    }
    sampler: vk.Sampler
    vk.CreateSampler(r.device, &sci, nil, &sampler)
    return sampler
}

@(private)
vk3d_create_shadow_target :: proc(r: ^VK3D_Renderer) {
    r.shadow_res = 2048
    r.shadow_image, r.shadow_memory = vk3d_create_image(
        r, u32(r.shadow_res), u32(r.shadow_res), .D32_SFLOAT, {.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
    )
    r.shadow_view = vk3d_create_image_view(r, r.shadow_image, .D32_SFLOAT, {.DEPTH})
    fbci := vk.FramebufferCreateInfo{
        sType           = .FRAMEBUFFER_CREATE_INFO,
        renderPass      = r.shadow_pass,
        attachmentCount = 1,
        pAttachments    = &r.shadow_view,
        width           = u32(r.shadow_res),
        height          = u32(r.shadow_res),
        layers          = 1,
    }
    vk.CreateFramebuffer(r.device, &fbci, nil, &r.shadow_fb)
}

vk3d_set_sun :: proc(r: ^VK3D_Renderer, sun: R3D_Sun) {
    r.sun = sun
    if r.sun.shadow_bias == 0 { r.sun.shadow_bias = 0.0025 }
    if r.sun.shadow_radius == 0 { r.sun.shadow_radius = 12 }
}

vk3d_shadow_pass_begin :: proc(r: ^VK3D_Renderer, center: linalg.Vector3f32) {
    if !r.sun.enabled || !r.sun.cast_shadows { return }
    r3d_sun_view_proj(&r.sun, center, true)
    r.sun.shadow_texel = 1.0 / f32(r.shadow_res)
    clear(&r.shadow_draws)
}

// Queue a mesh as a shadow caster this frame.
vk3d_draw_mesh_shadow :: proc(r: ^VK3D_Renderer, mesh: ^VK3D_Mesh, model: linalg.Matrix4f32) {
    if !r.sun.enabled || !r.sun.cast_shadows || mesh.index_count == 0 { return }
    append(&r.shadow_draws, VK3D_Shadow_Draw{mesh = mesh^, model = model})
}

vk3d_shadow_pass_end :: proc(r: ^VK3D_Renderer) {
    // no-op: the pass is recorded in vk3d_begin_frame from the queued draws
}

// Record the queued shadow pass (called from vk3d_begin_frame).
@(private)
vk3d_record_shadow_pass :: proc(r: ^VK3D_Renderer, frame: ^VK3D_Frame) {
    if !r.sun.enabled || !r.sun.cast_shadows || len(r.shadow_draws) == 0 { return }
    cmd := frame.cmd

    clear := vk.ClearValue{depthStencil = {depth = 1.0, stencil = 0}}
    rpbi := vk.RenderPassBeginInfo{
        sType           = .RENDER_PASS_BEGIN_INFO,
        renderPass      = r.shadow_pass,
        framebuffer     = r.shadow_fb,
        renderArea      = {offset = {x = 0, y = 0}, extent = {width = u32(r.shadow_res), height = u32(r.shadow_res)}},
        clearValueCount = 1,
        pClearValues    = &clear,
    }
    vk.CmdBeginRenderPass(cmd, &rpbi, .INLINE)
    vk3d_set_viewport(cmd, r.shadow_res, r.shadow_res)
    vk.CmdBindPipeline(cmd, .GRAPHICS, r.shadow_pipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, r.shadow_layout, 0, 1, &frame.ubo_set, 0, nil)

    for d in r.shadow_draws {
        model := d.model
        vk.CmdPushConstants(cmd, r.shadow_layout, {.VERTEX}, 0, 64, &model)
        vbo := d.mesh.vbo
        offset := vk.DeviceSize(0)
        vk.CmdBindVertexBuffers(cmd, 0, 1, &vbo, &offset)
        vk.CmdBindIndexBuffer(cmd, d.mesh.ebo, 0, .UINT32)
        vk.CmdDrawIndexed(cmd, u32(d.mesh.index_count), 1, 0, 0, 0)
    }
    vk.CmdEndRenderPass(cmd)
}

@(private)
vk3d_create_shadow_pipeline :: proc(r: ^VK3D_Renderer, vert: vk.ShaderModule) -> bool {
    stages := [1]vk.PipelineShaderStageCreateInfo{
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = vert, pName = "main"},
    }
    binding := vk.VertexInputBindingDescription{binding = 0, stride = R3D_VERTEX_STRIDE, inputRate = .VERTEX}
    attrs := [1]vk.VertexInputAttributeDescription{
        {location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(R3D_Vertex, pos))},
    }
    vi := vk.PipelineVertexInputStateCreateInfo{
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = 1,
        pVertexAttributeDescriptions    = &attrs[0],
    }
    ia := vk.PipelineInputAssemblyStateCreateInfo{
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }
    vp := vk.PipelineViewportStateCreateInfo{
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount  = 1,
    }
    rs := vk.PipelineRasterizationStateCreateInfo{
        sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode             = .FILL,
        cullMode                = {},
        frontFace               = .COUNTER_CLOCKWISE,
        lineWidth               = 1.0,
        depthBiasEnable         = true,
        depthBiasConstantFactor = 2.0,
        depthBiasSlopeFactor    = 2.5,
    }
    ms := vk.PipelineMultisampleStateCreateInfo{
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
    }
    ds := vk.PipelineDepthStencilStateCreateInfo{
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = true,
        depthWriteEnable = true,
        depthCompareOp   = .LESS,
    }
    cb := vk.PipelineColorBlendStateCreateInfo{
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 0,
    }
    dyn_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    dyn := vk.PipelineDynamicStateCreateInfo{
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = &dyn_states[0],
    }
    ci := vk.GraphicsPipelineCreateInfo{
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount          = 1,
        pStages             = &stages[0],
        pVertexInputState   = &vi,
        pInputAssemblyState = &ia,
        pViewportState      = &vp,
        pRasterizationState = &rs,
        pMultisampleState   = &ms,
        pDepthStencilState  = &ds,
        pColorBlendState    = &cb,
        pDynamicState       = &dyn,
        layout              = r.shadow_layout,
        renderPass          = r.shadow_pass,
        subpass             = 0,
    }
    if vk.CreateGraphicsPipelines(r.device, 0, 1, &ci, nil, &r.shadow_pipeline) != .SUCCESS {
        fmt.eprintln("vk3d: shadow pipeline creation failed")
        return false
    }
    return true
}
