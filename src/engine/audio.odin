package engine

import "core:fmt"

// Stub audio - would integrate with miniaudio or similar

play_sound :: proc(sound_id: int) {
    fmt.println("[AUDIO] Play sound:", sound_id)
}

play_music :: proc(music_id: int) {
    fmt.println("[AUDIO] Play music:", music_id)
}

stop_music :: proc() {
    fmt.println("[AUDIO] Stop music")
}
