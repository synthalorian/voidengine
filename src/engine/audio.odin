package engine

import "core:fmt"
import "core:strings"
import SDL "vendor:sdl2"
import SDL_Mixer "vendor:sdl2/mixer"

// Sound chunk cache: id -> chunk
Sound_Entry :: struct {
	chunk: ^SDL_Mixer.Chunk,
	path:  string,
}

// Music cache: id -> music
Music_Entry :: struct {
	music: ^SDL_Mixer.Music,
	path:  string,
}

sounds: [dynamic]Sound_Entry
music_tracks: [dynamic]Music_Entry

audio_initialized: bool

// --- Audio lifecycle (called from engine.odin) ---

audio_init :: proc() -> bool {
	if SDL_Mixer.Init(SDL_Mixer.INIT_OGG | SDL_Mixer.INIT_MP3) == 0 {
		fmt.println("[AUDIO] SDL_mixer init failed:", SDL.GetError())
		return false
	}

	if SDL_Mixer.OpenAudio(SDL_Mixer.DEFAULT_FREQUENCY, SDL_Mixer.DEFAULT_FORMAT, SDL_Mixer.DEFAULT_CHANNELS, 2048) != 0 {
		fmt.println("[AUDIO] OpenAudio failed:", SDL.GetError())
		SDL_Mixer.Quit()
		return false
	}

	SDL_Mixer.AllocateChannels(SDL_Mixer.CHANNELS)
	audio_initialized = true
	fmt.println("[AUDIO] Audio system initialized")
	return true
}

audio_shutdown :: proc() {
	for entry in sounds {
		if entry.chunk != nil {
			SDL_Mixer.FreeChunk(entry.chunk)
		}
		delete(entry.path)
	}
	delete(sounds)

	for entry in music_tracks {
		if entry.music != nil {
			SDL_Mixer.FreeMusic(entry.music)
		}
		delete(entry.path)
	}
	delete(music_tracks)

	SDL_Mixer.CloseAudio()
	SDL_Mixer.Quit()
	audio_initialized = false
}

// --- Sound API ---

load_sound :: proc(path: string) -> int {
	if !audio_initialized { return -1 }

	cstr := strings.clone_to_cstring(path)
	defer delete(cstr)

	chunk := SDL_Mixer.LoadWAV(cstr)
	if chunk == nil {
		fmt.println("[AUDIO] Failed to load sound:", path, "-", SDL.GetError())
		return -1
	}

	id := len(sounds)
	append(&sounds, Sound_Entry{
		chunk = chunk,
		path  = strings.clone(path),
	})
	return id
}

play_sound :: proc(sound_id: int) {
	if !audio_initialized { return }
	if sound_id < 0 || sound_id >= len(sounds) { return }

	entry := sounds[sound_id]
	if entry.chunk == nil { return }

	SDL_Mixer.PlayChannel(-1, entry.chunk, 0)
}

// --- Music API ---

load_music :: proc(path: string) -> int {
	if !audio_initialized { return -1 }

	cstr := strings.clone_to_cstring(path)
	defer delete(cstr)

	music := SDL_Mixer.LoadMUS(cstr)
	if music == nil {
		fmt.println("[AUDIO] Failed to load music:", path, "-", SDL.GetError())
		return -1
	}

	id := len(music_tracks)
	append(&music_tracks, Music_Entry{
		music = music,
		path  = strings.clone(path),
	})
	return id
}

play_music :: proc(music_id: int) {
	if !audio_initialized { return }
	if music_id < 0 || music_id >= len(music_tracks) { return }

	entry := music_tracks[music_id]
	if entry.music == nil { return }

	SDL_Mixer.PlayMusic(entry.music, -1)  // -1 = loop forever
}

stop_music :: proc() {
	if !audio_initialized { return }
	SDL_Mixer.HaltMusic()
}

pause_music :: proc() {
	if !audio_initialized { return }
	SDL_Mixer.PauseMusic()
}

resume_music :: proc() {
	if !audio_initialized { return }
	SDL_Mixer.ResumeMusic()
}

set_music_volume :: proc(volume: f32) {
	if !audio_initialized { return }
	// volume: 0.0 - 1.0, maps to 0 - MIX_MAX_VOLUME (128)
	v := i32(volume * f32(SDL_Mixer.MAX_VOLUME))
	if v < 0 { v = 0 }
	if v > SDL_Mixer.MAX_VOLUME { v = SDL_Mixer.MAX_VOLUME }
	SDL_Mixer.VolumeMusic(v)
}

set_sound_volume :: proc(sound_id: int, volume: f32) {
	if !audio_initialized { return }
	if sound_id < 0 || sound_id >= len(sounds) { return }
	
	entry := sounds[sound_id]
	if entry.chunk == nil { return }
	
	v := i32(volume * f32(SDL_Mixer.MAX_VOLUME))
	if v < 0 { v = 0 }
	if v > SDL_Mixer.MAX_VOLUME { v = SDL_Mixer.MAX_VOLUME }
	SDL_Mixer.VolumeChunk(entry.chunk, v)
}

// --- Audio Mixer with Channels ---

Audio_Channel :: enum {
	MASTER,
	MUSIC,
	SFX,
	UI,
}

Audio_Mixer :: struct {
	volumes: [Audio_Channel]f32,
	muted:   [Audio_Channel]bool,
}

audio_mixer: Audio_Mixer

mixer_init :: proc() {
	audio_mixer.volumes[.MASTER] = 1.0
	audio_mixer.volumes[.MUSIC] = 0.8
	audio_mixer.volumes[.SFX] = 1.0
	audio_mixer.volumes[.UI] = 1.0
}

mixer_set_volume :: proc(channel: Audio_Channel, volume: f32) {
	audio_mixer.volumes[channel] = clamp(volume, 0.0, 1.0)
	mixer_apply_volumes()
}

mixer_get_volume :: proc(channel: Audio_Channel) -> f32 {
	return audio_mixer.volumes[channel]
}

mixer_mute :: proc(channel: Audio_Channel) {
	audio_mixer.muted[channel] = true
	mixer_apply_volumes()
}

mixer_unmute :: proc(channel: Audio_Channel) {
	audio_mixer.muted[channel] = false
	mixer_apply_volumes()
}

mixer_toggle_mute :: proc(channel: Audio_Channel) {
	audio_mixer.muted[channel] = !audio_mixer.muted[channel]
	mixer_apply_volumes()
}

mixer_is_muted :: proc(channel: Audio_Channel) -> bool {
	return audio_mixer.muted[channel]
}

mixer_apply_volumes :: proc() {
	if !audio_initialized { return }

	// Apply master * music volume to music
	music_vol := audio_mixer.volumes[.MASTER] * audio_mixer.volumes[.MUSIC]
	if audio_mixer.muted[.MASTER] || audio_mixer.muted[.MUSIC] {
		music_vol = 0
	}
	set_music_volume(music_vol)

	// Apply master * sfx volume to all sounds
	sfx_vol := audio_mixer.volumes[.MASTER] * audio_mixer.volumes[.SFX]
	if audio_mixer.muted[.MASTER] || audio_mixer.muted[.SFX] {
		sfx_vol = 0
	}
	for i in 0..<len(sounds) {
		set_sound_volume(i, sfx_vol)
	}
}

// --- Spatial Audio ---

Audio_Listener :: struct {
	position: Vec2,
	max_dist: f32,     // Maximum distance for hearing
}

audio_listener: Audio_Listener = {
	position = Vec2{0, 0},
	max_dist = 500.0,
}

set_audio_listener :: proc(pos: Vec2) {
	audio_listener.position = pos
}

set_audio_listener_max_dist :: proc(dist: f32) {
	audio_listener.max_dist = dist
}

play_sound_spatial :: proc(sound_id: int, world_pos: Vec2) {
	if !audio_initialized { return }
	if sound_id < 0 || sound_id >= len(sounds) { return }

	entry := sounds[sound_id]
	if entry.chunk == nil { return }

	// Calculate distance and pan
	diff := vec2_sub(world_pos, audio_listener.position)
	dist := vec2_len(diff)

	if dist > audio_listener.max_dist {
		return // Too far to hear
	}

	// Volume attenuation based on distance
	volume := 1.0 - (dist / audio_listener.max_dist)
	volume = clamp(volume, 0.0, 1.0)

	// Apply mixer volumes
	volume *= audio_mixer.volumes[.MASTER] * audio_mixer.volumes[.SFX]
	if audio_mixer.muted[.MASTER] || audio_mixer.muted[.SFX] {
		volume = 0
	}

	// Pan based on horizontal position (-1 = left, 1 = right)
	pan := clamp(diff.x / audio_listener.max_dist, -1.0, 1.0)

	// Play on a specific channel so we can set pan/volume
	channel := SDL_Mixer.PlayChannel(-1, entry.chunk, 0)
	if channel >= 0 {
		SDL_Mixer.Volume(channel, i32(volume * f32(SDL_Mixer.MAX_VOLUME)))
		// SDL_mixer doesn't have direct panning, but we can simulate with stereo balance
		// For now, we just apply volume attenuation
		_ = pan // TODO: Implement stereo panning if SDL_mixer supports it
	}
}

// --- Music Transitions ---

Music_Transition :: struct {
	active:        bool,
	from_music:    int,
	to_music:      int,
	duration:      f32,
	elapsed:       f32,
	from_volume:   f32,
	to_volume:     f32,
}

music_transition: Music_Transition

music_crossfade :: proc(to_music_id: int, duration: f32 = 2.0) {
	if !audio_initialized { return }
	if to_music_id < 0 || to_music_id >= len(music_tracks) { return }

	music_transition = Music_Transition{
		active      = true,
		from_music  = -1, // Current music
		to_music    = to_music_id,
		duration    = duration,
		elapsed     = 0,
		from_volume = audio_mixer.volumes[.MUSIC],
		to_volume   = audio_mixer.volumes[.MUSIC],
	}

	// Start the new music at volume 0
	set_music_volume(0)
	SDL_Mixer.PlayMusic(music_tracks[to_music_id].music, -1)
}

music_transition_update :: proc(dt: f32) {
	if !music_transition.active { return }

	music_transition.elapsed += dt
	t := clamp(music_transition.elapsed / music_transition.duration, 0.0, 1.0)

	// Fade out old, fade in new
	current_vol := lerp(0.0, music_transition.to_volume, t)
	current_vol *= audio_mixer.volumes[.MASTER]
	if audio_mixer.muted[.MASTER] || audio_mixer.muted[.MUSIC] {
		current_vol = 0
	}

	set_music_volume(current_vol)

	if t >= 1.0 {
		music_transition.active = false
	}
}

music_is_transitioning :: proc() -> bool {
	return music_transition.active
}
