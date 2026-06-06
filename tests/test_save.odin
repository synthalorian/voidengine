package tests

import "core:fmt"
import "core:testing"
import "core:os"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Save Tests ===")

	engine.save_init()
	defer engine.save_shutdown()

	// Test setting values
	engine.save_set_bool("test_bool", true)
	engine.save_set_int("test_int", 42)
	engine.save_set_float("test_float", 3.14)
	engine.save_set_string("test_string", "hello")

	int_arr := []int{1, 2, 3, 4, 5}
	engine.save_set_int_array("test_int_arr", int_arr)

	float_arr := []f32{1.1, 2.2, 3.3}
	engine.save_set_float_array("test_float_arr", float_arr)

	// Test getting values
	assert(engine.save_get_bool("test_bool") == true, "Bool value mismatch")
	assert(engine.save_get_int("test_int") == 42, "Int value mismatch")
	assert(engine.save_get_float("test_float") == 3.14, "Float value mismatch")
	assert(engine.save_get_string("test_string") == "hello", "String value mismatch")

	// Test defaults
	assert(engine.save_get_bool("missing", false) == false, "Default bool should work")
	assert(engine.save_get_int("missing", 99) == 99, "Default int should work")
	assert(engine.save_get_float("missing", 1.5) == 1.5, "Default float should work")
	assert(engine.save_get_string("missing", "default") == "default", "Default string should work")

	// Test has_key
	assert(engine.save_has_key("test_int"), "Should have key")
	assert(!engine.save_has_key("nonexistent"), "Should not have key")

	// Test save to file
	test_path := "/tmp/test_save.json"
	assert(engine.save_to_file(test_path), "Should save to file")

	// Test clear and load
	engine.save_clear()
	assert(!engine.save_has_key("test_int"), "Should be cleared")

	assert(engine.save_from_file(test_path), "Should load from file")
	assert(engine.save_get_int("test_int") == 42, "Should load int correctly")
	assert(engine.save_get_bool("test_bool") == true, "Should load bool correctly")
	assert(engine.save_get_float("test_float") == 3.14, "Should load float correctly")
	assert(engine.save_get_string("test_string") == "hello", "Should load string correctly")

	// Test remove
	engine.save_remove("test_int")
	assert(!engine.save_has_key("test_int"), "Should be removed")

	// Cleanup
	os.remove(test_path)

	fmt.println("✅ All save tests passed")
}
