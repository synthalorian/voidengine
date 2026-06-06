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
