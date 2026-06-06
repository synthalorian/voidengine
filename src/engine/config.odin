package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/json"
import "core:path/filepath"
import SDL "vendor:sdl2"

// Game configuration loaded from JSON
Game_Config :: struct {
	// Window settings
	window: struct {
		title:  string `json:"title"`,
		width:  i32    `json:"width"`,
		height: i32    `json:"height"`,
		vsync:  bool   `json:"vsync"`,
	},

	// Audio settings
	audio: struct {
		enabled:       bool  `json:"enabled"`,
		master_volume: f32   `json:"master_volume"`,
		music_volume:  f32   `json:"music_volume"`,
		sfx_volume:    f32   `json:"sfx_volume"`,
	},

	// Input settings
	input: struct {
		keybindings: map[string]string `json:"keybindings"`,
	},

	// Debug settings
	debug: struct {
		show_overlay: bool `json:"show_overlay"`,
		log_level:    string `json:"log_level"`,
	},
}

// Default configuration values
default_config :: proc() -> Game_Config {
	cfg := Game_Config{}
	cfg.window.title = "VoidEngine Game"
	cfg.window.width = 800
	cfg.window.height = 600
	cfg.window.vsync = true

	cfg.audio.enabled = true
	cfg.audio.master_volume = 1.0
	cfg.audio.music_volume = 0.8
	cfg.audio.sfx_volume = 1.0

	cfg.input.keybindings = make(map[string]string)
	cfg.input.keybindings["left"] = "LEFT"
	cfg.input.keybindings["right"] = "RIGHT"
	cfg.input.keybindings["up"] = "UP"
	cfg.input.keybindings["down"] = "DOWN"
	cfg.input.keybindings["action_a"] = "Z"
	cfg.input.keybindings["action_b"] = "X"
	cfg.input.keybindings["start"] = "RETURN"
	cfg.input.keybindings["select"] = "TAB"

	cfg.debug.show_overlay = false
	cfg.debug.log_level = "INFO"

	return cfg
}

// Load configuration from a JSON file
config_load :: proc(path: string) -> (Game_Config, bool) {
	cfg := default_config()

	if !os.exists(path) {
		log_warn("Config file not found: %s, using defaults", path)
		return cfg, false
	}

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != os.ERROR_NONE {
		log_error("Failed to read config file: %s", path)
		return cfg, false
	}
	defer delete(data)

	json_err := json.unmarshal(data, &cfg, json.DEFAULT_SPECIFICATION, context.allocator)
	if json_err != nil {
		log_error("Failed to parse config file: %s - %v", path, json_err)
		return cfg, false
	}

	log_info("Loaded config from: %s", path)
	return cfg, true
}

// Save configuration to a JSON file (manual JSON generation to avoid marshal limitations)
config_save :: proc(path: string, cfg: ^Game_Config) -> bool {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	indent :: proc(b: ^strings.Builder, level: int) {
		for i in 0..<level {
			strings.write_string(b, "    ")
		}
	}

	strings.write_string(&builder, "{\n")

	// Window section
	indent(&builder, 1); strings.write_string(&builder, "\"window\": {\n")
	indent(&builder, 2); fmt.sbprintf(&builder, "\"title\": \"%s\",\n", cfg.window.title)
	indent(&builder, 2); fmt.sbprintf(&builder, "\"width\": %d,\n", cfg.window.width)
	indent(&builder, 2); fmt.sbprintf(&builder, "\"height\": %d,\n", cfg.window.height)
	indent(&builder, 2); fmt.sbprintf(&builder, "\"vsync\": %t\n", cfg.window.vsync)
	indent(&builder, 1); strings.write_string(&builder, "},\n")

	// Audio section
	indent(&builder, 1); strings.write_string(&builder, "\"audio\": {\n")
	indent(&builder, 2); fmt.sbprintf(&builder, "\"enabled\": %t,\n", cfg.audio.enabled)
	indent(&builder, 2); fmt.sbprintf(&builder, "\"master_volume\": %.1f,\n", cfg.audio.master_volume)
	indent(&builder, 2); fmt.sbprintf(&builder, "\"music_volume\": %.1f,\n", cfg.audio.music_volume)
	indent(&builder, 2); fmt.sbprintf(&builder, "\"sfx_volume\": %.1f\n", cfg.audio.sfx_volume)
	indent(&builder, 1); strings.write_string(&builder, "},\n")

	// Input section
	indent(&builder, 1); strings.write_string(&builder, "\"input\": {\n")
	indent(&builder, 2); strings.write_string(&builder, "\"keybindings\": {\n")
	first := true
	for action, key in cfg.input.keybindings {
		if !first {
			strings.write_string(&builder, ",\n")
		}
		indent(&builder, 3); fmt.sbprintf(&builder, "\"%s\": \"%s\"", action, key)
		first = false
	}
	strings.write_string(&builder, "\n")
	indent(&builder, 2); strings.write_string(&builder, "}\n")
	indent(&builder, 1); strings.write_string(&builder, "},\n")

	// Debug section
	indent(&builder, 1); strings.write_string(&builder, "\"debug\": {\n")
	indent(&builder, 2); fmt.sbprintf(&builder, "\"show_overlay\": %t,\n", cfg.debug.show_overlay)
	indent(&builder, 2); fmt.sbprintf(&builder, "\"log_level\": \"%s\"\n", cfg.debug.log_level)
	indent(&builder, 1); strings.write_string(&builder, "}\n")

	strings.write_string(&builder, "}\n")

	data := transmute([]u8)strings.to_string(builder)
	write_err := os.write_entire_file(path, data)
	if write_err != os.ERROR_NONE {
		log_error("Failed to write config file: %s", path)
		return false
	}

	log_info("Saved config to: %s", path)
	return true
}

// Generate a default config file for a new project
generate_default_config :: proc() -> string {
	return `{
	"window": {
		"title": "My VoidEngine Game",
		"width": 800,
		"height": 600,
		"vsync": true
	},
	"audio": {
		"enabled": true,
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 1.0
	},
	"input": {
		"keybindings": {
			"left": "LEFT",
			"right": "RIGHT",
			"up": "UP",
			"down": "DOWN",
			"action_a": "Z",
			"action_b": "X",
			"start": "RETURN",
			"select": "TAB"
		}
	},
	"debug": {
		"show_overlay": false,
		"log_level": "INFO"
	}
}
`
}

// Apply config log level to the logging system
config_apply_log_level :: proc(cfg: ^Game_Config) {
	switch strings.to_upper(cfg.debug.log_level) {
	case "DEBUG":
		log_set_level(.DEBUG)
	case "INFO":
		log_set_level(.INFO)
	case "WARN":
		log_set_level(.WARN)
	case "ERROR":
		log_set_level(.ERROR)
	case:
		log_warn("Unknown log level: %s, using INFO", cfg.debug.log_level)
		log_set_level(.INFO)
	}
}

// Apply config audio volumes to the audio system
config_apply_audio :: proc(cfg: ^Game_Config) {
	if !cfg.audio.enabled {
		log_info("Audio disabled in config")
		return
	}
	// Volume is applied per-sound/music, but we could add master volume support
	log_info("Audio config - master: %.1f, music: %.1f, sfx: %.1f",
		cfg.audio.master_volume, cfg.audio.music_volume, cfg.audio.sfx_volume)
}

// Get the expected config file path for a project
get_project_config_path :: proc(project_path: string) -> string {
	return fmt.tprintf("%s/config.json", project_path)
}
