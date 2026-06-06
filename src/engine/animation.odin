package engine

import "core:fmt"

// --- Animation Frame ---

Animation_Frame :: struct {
	sprite_id: int,     // Source sprite/texture ID
	duration:  f32,     // Frame duration in seconds
	src_rect:  Rect,    // Source rectangle within sprite (optional, for atlas)
}

// --- Animation Definition ---

Animation :: struct {
	name:      string,
	frames:    []Animation_Frame,
	looping:   bool,
}

// --- Animation Player ---

Animation_Player :: struct {
	animation:    ^Animation,
	current_frame: int,
	elapsed:       f32,
	playing:       bool,
	finished:      bool,
}

// Animation registry
animations: [dynamic]Animation
animation_players: [dynamic]Animation_Player

// --- Animation Management ---

animation_init :: proc() {
	animations = make([dynamic]Animation)
	animation_players = make([dynamic]Animation_Player)
}

animation_shutdown :: proc() {
	// Clean up animation definitions
	for &anim in animations {
		delete(anim.frames)
	}
	delete(animations)
	delete(animation_players)
}

// Register a new animation definition
animation_register :: proc(name: string, frames: []Animation_Frame, looping: bool = true) -> int {
	id := len(animations)

	// Copy frames
	frames_copy := make([]Animation_Frame, len(frames))
	copy(frames_copy, frames)

	append(&animations, Animation{
		name    = name,
		frames  = frames_copy,
		looping = looping,
	})
	return id
}

// Create an animation from sprite IDs (each frame uses full sprite)
animation_register_from_sprites :: proc(name: string, sprite_ids: []int, frame_duration: f32, looping: bool = true) -> int {
	frames := make([]Animation_Frame, len(sprite_ids))
	for i in 0..<len(sprite_ids) {
		frames[i] = Animation_Frame{
			sprite_id = sprite_ids[i],
			duration  = frame_duration,
		}
	}

	id := len(animations)
	append(&animations, Animation{
		name    = name,
		frames  = frames,
		looping = looping,
	})
	return id
}

// Create an animation player instance
animation_player_create :: proc(animation_id: int) -> int {
	if animation_id < 0 || animation_id >= len(animations) {
		return -1
	}

	player_id := len(animation_players)
	append(&animation_players, Animation_Player{
		animation     = &animations[animation_id],
		current_frame = 0,
		elapsed       = 0,
		playing       = true,
		finished      = false,
	})
	return player_id
}

animation_player_destroy :: proc(player_id: int) {
	if player_id < 0 || player_id >= len(animation_players) {
		return
	}
	ordered_remove(&animation_players, player_id)
}

// --- Playback Control ---

animation_player_play :: proc(player_id: int) {
	if player_id < 0 || player_id >= len(animation_players) {
		return
	}
	animation_players[player_id].playing = true
}

animation_player_pause :: proc(player_id: int) {
	if player_id < 0 || player_id >= len(animation_players) {
		return
	}
	animation_players[player_id].playing = false
}

animation_player_stop :: proc(player_id: int) {
	if player_id < 0 || player_id >= len(animation_players) {
		return
	}
	player := &animation_players[player_id]
	player.playing = false
	player.current_frame = 0
	player.elapsed = 0
	player.finished = false
}

animation_player_set_frame :: proc(player_id: int, frame: int) {
	if player_id < 0 || player_id >= len(animation_players) {
		return
	}
	player := &animation_players[player_id]
	if player.animation == nil { return }
	if frame >= 0 && frame < len(player.animation.frames) {
		player.current_frame = frame
		player.elapsed = 0
	}
}

animation_player_set_animation :: proc(player_id: int, animation_id: int) -> bool {
	if player_id < 0 || player_id >= len(animation_players) {
		return false
	}
	if animation_id < 0 || animation_id >= len(animations) {
		return false
	}
	animation_players[player_id].animation = &animations[animation_id]
	animation_players[player_id].current_frame = 0
	animation_players[player_id].elapsed = 0
	animation_players[player_id].finished = false
	return true
}

// --- Update ---

animation_update :: proc(dt: f32) {
	for &player in animation_players {
		if !player.playing { continue }
		if player.animation == nil { continue }
		if len(player.animation.frames) == 0 { continue }

		player.elapsed += dt

		// Advance frames
		frame := &player.animation.frames[player.current_frame]
		for player.elapsed >= frame.duration {
			player.elapsed -= frame.duration
			player.current_frame += 1

			if player.current_frame >= len(player.animation.frames) {
				if player.animation.looping {
					player.current_frame = 0
				} else {
					player.current_frame = len(player.animation.frames) - 1
					player.finished = true
					player.playing = false
				}
			}
		}
	}
}

// --- Query ---

animation_player_get_current_sprite :: proc(player_id: int) -> int {
	if player_id < 0 || player_id >= len(animation_players) {
		return -1
	}
	player := &animation_players[player_id]
	if player.animation == nil { return -1 }
	if len(player.animation.frames) == 0 { return -1 }
	return player.animation.frames[player.current_frame].sprite_id
}

animation_player_is_playing :: proc(player_id: int) -> bool {
	if player_id < 0 || player_id >= len(animation_players) {
		return false
	}
	return animation_players[player_id].playing
}

animation_player_is_finished :: proc(player_id: int) -> bool {
	if player_id < 0 || player_id >= len(animation_players) {
		return false
	}
	return animation_players[player_id].finished
}

animation_player_get_current_frame :: proc(player_id: int) -> int {
	if player_id < 0 || player_id >= len(animation_players) {
		return -1
	}
	return animation_players[player_id].current_frame
}

// --- Draw helper ---

animation_player_draw :: proc(player_id: int, x, y: f32) {
	sprite_id := animation_player_get_current_sprite(player_id)
	if sprite_id >= 0 {
		draw_sprite(x, y, sprite_id)
	}
}

// --- Convenience: One-shot animations ---

animation_play_once :: proc(animation_id: int, x, y: f32) -> int {
	player_id := animation_player_create(animation_id)
	if player_id >= 0 {
		player := &animation_players[player_id]
		if player.animation != nil {
			player.animation.looping = false
		}
	}
	return player_id
}
