package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/json"

// --- Save System ---
// Simple key-value save/load system using JSON

Save_Data :: struct {
	values: map[string]Save_Value,
}

Save_Value :: union {
	bool,
	int,
	f32,
	string,
	[]int,
	[]f32,
}

save_data: Save_Data

save_init :: proc() {
	save_data.values = make(map[string]Save_Value)
}

save_shutdown :: proc() {
	delete(save_data.values)
}

// --- Setters ---

save_set_bool :: proc(key: string, value: bool) {
	save_data.values[key] = value
}

save_set_int :: proc(key: string, value: int) {
	save_data.values[key] = value
}

save_set_float :: proc(key: string, value: f32) {
	save_data.values[key] = value
}

save_set_string :: proc(key: string, value: string) {
	save_data.values[key] = value
}

save_set_int_array :: proc(key: string, value: []int) {
	copy_val := make([]int, len(value))
	copy(copy_val, value)
	save_data.values[key] = copy_val
}

save_set_float_array :: proc(key: string, value: []f32) {
	copy_val := make([]f32, len(value))
	copy(copy_val, value)
	save_data.values[key] = copy_val
}

// --- Getters ---

save_get_bool :: proc(key: string, default: bool = false) -> bool {
	if val, ok := save_data.values[key]; ok {
		if b, ok := val.(bool); ok {
			return b
		}
	}
	return default
}

save_get_int :: proc(key: string, default: int = 0) -> int {
	if val, ok := save_data.values[key]; ok {
		#partial switch v in val {
		case int:
			return v
		case f32:
			return int(v)
		}
	}
	return default
}

save_get_float :: proc(key: string, default: f32 = 0.0) -> f32 {
	if val, ok := save_data.values[key]; ok {
		#partial switch v in val {
		case f32:
			return v
		case int:
			return f32(v)
		}
	}
	return default
}

save_get_string :: proc(key: string, default: string = "") -> string {
	if val, ok := save_data.values[key]; ok {
		if s, ok := val.(string); ok {
			return s
		}
	}
	return default
}

save_has_key :: proc(key: string) -> bool {
	_, ok := save_data.values[key]
	return ok
}

save_remove :: proc(key: string) {
	delete_key(&save_data.values, key)
}

save_clear :: proc() {
	clear_map(&save_data.values)
}

// --- Serialization ---

save_to_file :: proc(path: string) -> bool {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "{\n")

	first := true
	for key, val in save_data.values {
		if !first {
			strings.write_string(&builder, ",\n")
		}
		first = false

		strings.write_string(&builder, "  \"")
		strings.write_string(&builder, key)
		strings.write_string(&builder, "\": ")

		switch v in val {
		case bool:
			fmt.sbprintf(&builder, "%t", v)
		case int:
			fmt.sbprintf(&builder, "%d", v)
		case f32:
			fmt.sbprintf(&builder, "%.6f", v)
		case string:
			fmt.sbprintf(&builder, "\"%s\"", v)
		case []int:
			strings.write_string(&builder, "[")
			for item, i in v {
				if i > 0 { strings.write_string(&builder, ", ") }
				fmt.sbprintf(&builder, "%d", item)
			}
			strings.write_string(&builder, "]")
		case []f32:
			strings.write_string(&builder, "[")
			for item, i in v {
				if i > 0 { strings.write_string(&builder, ", ") }
				fmt.sbprintf(&builder, "%.6f", item)
			}
			strings.write_string(&builder, "]")
		}
	}

	strings.write_string(&builder, "\n}\n")

	data := transmute([]u8)strings.to_string(builder)
	write_err := os.write_entire_file(path, data)
	if write_err != os.ERROR_NONE {
		log_error("Failed to write save file: %s", path)
		return false
	}

	log_info("Saved game data to: %s (%d entries)", path, len(save_data.values))
	return true
}

save_from_file :: proc(path: string) -> bool {
	if !os.exists(path) {
		log_warn("Save file not found: %s", path)
		return false
	}

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != os.ERROR_NONE {
		log_error("Failed to read save file: %s", path)
		return false
	}
	defer delete(data)

	// Parse JSON
	raw_json, parse_err := json.parse(data, json.DEFAULT_SPECIFICATION)
	if parse_err != nil {
		log_error("Failed to parse save file: %s - %v", path, parse_err)
		return false
	}
	defer json.destroy_value(raw_json)

	root, ok := raw_json.(json.Object)
	if !ok {
		log_error("Save file root is not an object: %s", path)
		return false
	}

	// Clear existing data
	save_clear()

	for key, val in root {
		// Clone the key since JSON parser strings may be temp-allocated
		key_clone := fmt.tprintf("%s", key)
		#partial switch v in val {
		case json.Boolean:
			save_data.values[key_clone] = bool(v)
		case json.Integer:
			save_data.values[key_clone] = int(v)
		case json.Float:
			// JSON numbers may be parsed as floats; try to store as int if whole number
			if v == f64(int(v)) {
				save_data.values[key_clone] = int(v)
			} else {
				save_data.values[key_clone] = f32(v)
			}
		case json.String:
			save_data.values[key_clone] = fmt.tprintf("%s", v)
		case json.Array:
			if len(v) > 0 {
				#partial switch item in v[0] {
				case json.Integer:
					arr := make([]int, len(v))
					for item, i in v {
						if iv, ok := item.(json.Integer); ok {
							arr[i] = int(iv)
						}
					}
					save_data.values[key_clone] = arr
				case json.Float:
					// Check if all values are whole numbers
					all_int := true
					for item in v {
						if fv, ok := item.(json.Float); ok {
							if fv != f64(int(fv)) {
								all_int = false
								break
							}
						}
					}
					if all_int {
						arr := make([]int, len(v))
						for item, i in v {
							if fv, ok := item.(json.Float); ok {
								arr[i] = int(fv)
							}
						}
						save_data.values[key_clone] = arr
					} else {
						arr := make([]f32, len(v))
						for item, i in v {
							if fv, ok := item.(json.Float); ok {
								arr[i] = f32(fv)
							}
						}
						save_data.values[key_clone] = arr
					}
				}
			}
		}
	}

	log_info("Loaded save data from: %s (%d entries)", path, len(save_data.values))
	return true
}

// --- Convenience ---

save_get_path :: proc(project_path: string) -> string {
	return fmt.tprintf("%s/save.json", project_path)
}

save_exists :: proc(project_path: string) -> bool {
	return os.exists(save_get_path(project_path))
}
