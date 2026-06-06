package engine

import "core:fmt"
import "core:os"
import "core:strings"

// --- Error Handling System ---
// v0.7.0: Graceful failures with clear error messages

// Error code enumeration for categorizing failures
Error_Code :: enum {
	NONE,           // No error
	FILE_NOT_FOUND, // File or path not found
	PARSE_ERROR,    // Failed to parse data
	INIT_FAILED,    // System initialization failed
	INVALID_STATE,  // Invalid engine state
	MEMORY_ERROR,   // Memory allocation failure
	IO_ERROR,       // Input/output error
	CONFIG_ERROR,   // Configuration error
	BUILD_ERROR,    // Build system error
	UNKNOWN,        // Uncategorized error
}

// Error context provides detailed failure information
Error_Context :: struct {
	code:      Error_Code,
	message:   string,
	file:      string,
	line:      int,
	recoverable: bool,  // Whether the engine can continue
}

// Current error state
last_error: Error_Context

// Initialize error handling
error_init :: proc() {
	last_error = Error_Context{
		code = .NONE,
		message = "",
		file = "",
		line = 0,
		recoverable = true,
	}
}

// Set an error with context
// Usage: error_set(.FILE_NOT_FOUND, "Could not load texture", #file, #line)
error_set :: proc(code: Error_Code, message: string, file: string = "", line: int = 0) {
	last_error = Error_Context{
		code = code,
		message = strings.clone(message),
		file = file,
		line = line,
		recoverable = false,
	}
	
	// Log the error immediately
	log_error("[%s] %s", error_code_string(code), message)
	if file != "" {
		log_error("  at %s:%d", file, line)
	}
}

// Set a recoverable warning
error_warn :: proc(code: Error_Code, message: string, file: string = "", line: int = 0) {
	last_error = Error_Context{
		code = code,
		message = strings.clone(message),
		file = file,
		line = line,
		recoverable = true,
	}
	
	log_warn("[%s] %s", error_code_string(code), message)
}

// Clear the current error
error_clear :: proc() {
	last_error = Error_Context{
		code = .NONE,
		message = "",
		file = "",
		line = 0,
		recoverable = true,
	}
}

// Check if there's an active error
error_occurred :: proc() -> bool {
	return last_error.code != .NONE
}

// Get the current error code
error_get_code :: proc() -> Error_Code {
	return last_error.code
}

// Get a human-readable error message
error_get_message :: proc() -> string {
	if last_error.code == .NONE {
		return "No error"
	}
	return last_error.message
}

// Convert error code to string
error_code_string :: proc(code: Error_Code) -> string {
	switch code {
	case .NONE:           return "NONE"
	case .FILE_NOT_FOUND: return "FILE_NOT_FOUND"
	case .PARSE_ERROR:    return "PARSE_ERROR"
	case .INIT_FAILED:    return "INIT_FAILED"
	case .INVALID_STATE:  return "INVALID_STATE"
	case .MEMORY_ERROR:   return "MEMORY_ERROR"
	case .IO_ERROR:       return "IO_ERROR"
	case .CONFIG_ERROR:   return "CONFIG_ERROR"
	case .BUILD_ERROR:    return "BUILD_ERROR"
	case .UNKNOWN:        return "UNKNOWN"
	}
	return "UNKNOWN"
}

// Check if the last error was recoverable
error_is_recoverable :: proc() -> bool {
	return last_error.recoverable
}

// --- Graceful failure helpers ---

// Try to open a file, returns nil on failure with error set
try_open_file :: proc(path: string) -> (^os.File, bool) {
	if !os.exists(path) {
		error_set(.FILE_NOT_FOUND, fmt.tprintf("File not found: %s", path), #file, #line)
		return nil, false
	}
	
	fd, err := os.open(path, os.O_RDONLY)
	if err != os.ERROR_NONE {
		error_set(.IO_ERROR, fmt.tprintf("Cannot open file: %s (error: %d)", path, err), #file, #line)
		return nil, false
	}
	
	error_clear()
	return fd, true
}

// Try to read entire file, returns nil on failure with error set
try_read_file :: proc(path: string) -> ([]u8, bool) {
	if !os.exists(path) {
		error_set(.FILE_NOT_FOUND, fmt.tprintf("File not found: %s", path), #file, #line)
		return nil, false
	}
	
	data, err := os.read_entire_file(path, context.allocator)
	if err != os.ERROR_NONE {
		error_set(.IO_ERROR, fmt.tprintf("Cannot read file: %s (error: %d)", path, err), #file, #line)
		return nil, false
	}
	
	error_clear()
	return data, true
}

// Try to write file, returns false on failure with error set
try_write_file :: proc(path: string, data: []u8) -> bool {
	err := os.write_entire_file(path, data)
	if err != os.ERROR_NONE {
		error_set(.IO_ERROR, fmt.tprintf("Cannot write file: %s (error: %d)", path, err), #file, #line)
		return false
	}
	
	error_clear()
	return true
}

// Assert with graceful error message instead of crashing
assert_with_error :: proc(condition: bool, message: string, file: string = #file, line: int = #line) -> bool {
	if !condition {
		error_set(.INVALID_STATE, fmt.tprintf("Assertion failed: %s", message), file, line)
		return false
	}
	return true
}

// --- User-friendly error messages ---

// Get a user-friendly message for common errors
error_get_user_message :: proc() -> string {
	switch last_error.code {
	case .NONE:
		return "Everything is working correctly."
	case .FILE_NOT_FOUND:
		return fmt.tprintf("Could not find file: %s\nPlease check that the file exists and the path is correct.", last_error.message)
	case .PARSE_ERROR:
		return fmt.tprintf("Failed to parse data: %s\nPlease check the file format.", last_error.message)
	case .INIT_FAILED:
		return fmt.tprintf("Failed to initialize: %s\nPlease check your system configuration and try again.", last_error.message)
	case .INVALID_STATE:
		return fmt.tprintf("Invalid operation: %s\nThe engine is in an unexpected state.", last_error.message)
	case .MEMORY_ERROR:
		return fmt.tprintf("Memory error: %s\nPlease free up system memory and try again.", last_error.message)
	case .IO_ERROR:
		return fmt.tprintf("I/O error: %s\nPlease check file permissions and disk space.", last_error.message)
	case .CONFIG_ERROR:
		return fmt.tprintf("Configuration error: %s\nPlease check your config.json file.", last_error.message)
	case .BUILD_ERROR:
		return fmt.tprintf("Build error: %s\nPlease check your project structure and try again.", last_error.message)
	case .UNKNOWN:
		return fmt.tprintf("An unexpected error occurred: %s", last_error.message)
	}
	return "An unknown error occurred."
}

// Print a formatted error report to the console
error_print_report :: proc() {
	fmt.println("\n=== ERROR REPORT ===")
	fmt.println("Code:", error_code_string(last_error.code))
	fmt.println("Message:", last_error.message)
	if last_error.file != "" {
		fmt.println("Location:", last_error.file, ":", last_error.line)
	}
	fmt.println("Recoverable:", last_error.recoverable)
	fmt.println("===================\n")
}
