package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "core:encoding/json"

// Log level enumeration
Log_Level :: enum {
	DEBUG,
	INFO,
	WARN,
	ERROR,
}

log_level_names := [Log_Level]string{
	.DEBUG = "DEBUG",
	.INFO  = "INFO",
	.WARN  = "WARN",
	.ERROR = "ERROR",
}

log_level_colors := [Log_Level]string{
	.DEBUG = "\033[36m",  // Cyan
	.INFO  = "\033[32m",  // Green
	.WARN  = "\033[33m",  // Yellow
	.ERROR = "\033[31m",  // Red
}

LOG_COLOR_RESET :: "\033[0m"

// Logger configuration
Logger :: struct {
	min_level:     Log_Level,
	use_colors:    bool,
	show_timestamp: bool,
	prefix:        string,
}

logger: Logger

// Initialize the logging system
log_init :: proc(min_level: Log_Level = .INFO, use_colors: bool = true, show_timestamp: bool = true) {
	logger = Logger{
		min_level      = min_level,
		use_colors     = use_colors,
		show_timestamp = show_timestamp,
		prefix         = "[VOID]",
	}
}

// Shutdown logging (nothing to clean up currently, but provided for symmetry)
log_shutdown :: proc() {
	// No dynamic allocations to clean up
}

// Set minimum log level
log_set_level :: proc(level: Log_Level) {
	logger.min_level = level
}

// Internal logging function
log_message :: proc(level: Log_Level, format: string, args: ..any) {
	if level < logger.min_level {
		return
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	// Add timestamp
	if logger.show_timestamp {
		now := time.now()
		hour, min, sec := time.clock_from_time(now)
		fmt.sbprintf(&builder, "[%02d:%02d:%02d] ", hour, min, sec)
	}

	// Add prefix and level
	if logger.use_colors {
		fmt.sbprintf(&builder, "%s%s %s: ", log_level_colors[level], logger.prefix, log_level_names[level])
	} else {
		fmt.sbprintf(&builder, "%s %s: ", logger.prefix, log_level_names[level])
	}

	// Add message
	fmt.sbprintf(&builder, format, ..args)

	if logger.use_colors {
		fmt.sbprint(&builder, LOG_COLOR_RESET)
	}

	// Output to stdout for INFO/DEBUG, stderr for WARN/ERROR
	msg := strings.to_string(builder)
	if level >= .WARN {
		fmt.eprintln(msg)
	} else {
		fmt.println(msg)
	}
}

// Convenience functions for each log level
log_debug :: proc(format: string, args: ..any) {
	log_message(.DEBUG, format, ..args)
}

log_info :: proc(format: string, args: ..any) {
	log_message(.INFO, format, ..args)
}

log_warn :: proc(format: string, args: ..any) {
	log_message(.WARN, format, ..args)
}

log_error :: proc(format: string, args: ..any) {
	log_message(.ERROR, format, ..args)
}

// Legacy print wrapper for backward compatibility
print :: proc(msg: string) {
	log_info("%s", msg)
}
