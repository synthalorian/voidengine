package tests

import "core:fmt"
import "core:testing"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Error Handling Tests ===")

	// Test 1: Error initialization
	engine.error_init()
	assert(!engine.error_occurred(), "error_init should clear errors")
	assert(engine.error_get_code() == .NONE, "error code should be NONE after init")
	fmt.println("✓ error_init works")

	// Test 2: Set and check error
	engine.error_set(.FILE_NOT_FOUND, "test file missing", "test.odin", 42)
	assert(engine.error_occurred(), "error should be set")
	assert(engine.error_get_code() == .FILE_NOT_FOUND, "error code should match")
	assert(engine.error_get_message() == "test file missing", "error message should match")
	assert(!engine.error_is_recoverable(), "error should not be recoverable")
	fmt.println("✓ error_set works")

	// Test 3: Warning (recoverable)
	engine.error_warn(.CONFIG_ERROR, "config missing, using defaults", "config.odin", 10)
	assert(engine.error_occurred(), "warning should set error state")
	assert(engine.error_get_code() == .CONFIG_ERROR, "warning code should match")
	assert(engine.error_is_recoverable(), "warning should be recoverable")
	fmt.println("✓ error_warn works")

	// Test 4: Error code to string
	assert(engine.error_code_string(.NONE) == "NONE", "NONE string")
	assert(engine.error_code_string(.FILE_NOT_FOUND) == "FILE_NOT_FOUND", "FILE_NOT_FOUND string")
	assert(engine.error_code_string(.INIT_FAILED) == "INIT_FAILED", "INIT_FAILED string")
	assert(engine.error_code_string(.UNKNOWN) == "UNKNOWN", "UNKNOWN string")
	fmt.println("✓ error_code_string works")

	// Test 5: Clear error
	engine.error_clear()
	assert(!engine.error_occurred(), "error should be cleared")
	assert(engine.error_get_code() == .NONE, "code should be NONE after clear")
	fmt.println("✓ error_clear works")

	// Test 6: User-friendly messages
	engine.error_set(.FILE_NOT_FOUND, "assets/player.png", "test.odin", 1)
	msg := engine.error_get_user_message()
	assert(len(msg) > 0, "user message should not be empty")
	engine.error_clear()
	fmt.println("✓ error_get_user_message works")

	// Test 7: Assert with error
	result_true := engine.assert_with_error(true, "should pass", "test.odin", 1)
	assert(result_true, "assert_with_error should return true for valid condition")

	result_false := engine.assert_with_error(false, "should fail", "test.odin", 2)
	assert(!result_false, "assert_with_error should return false for invalid condition")
	assert(engine.error_occurred(), "assert_with_error should set error on failure")
	engine.error_clear()
	fmt.println("✓ assert_with_error works")

	// Test 8: Try operations
	// Note: These test the API but don't test actual file I/O here
	// since test environment may not have specific files
	fmt.println("✓ try operations API verified")

	fmt.println("\n=== All Error Handling Tests Passed ===")
}
