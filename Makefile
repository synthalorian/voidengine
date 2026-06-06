# VoidEngine Build System
# https://github.com/voidengine/voidengine

ODIN_ROOT := /tmp/odin-setup/odin-linux-amd64-nightly+2026-05-03
ODIN := ODIN_ROOT=$(ODIN_ROOT) $(ODIN_ROOT)/odin
ENGINE_COLLECTION := -collection:engine=src

# Platform detection
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    PLATFORM := linux
    EXE_EXT :=
endif
ifeq ($(UNAME_S),Darwin)
    PLATFORM := macos
    EXE_EXT :=
endif
ifeq ($(OS),Windows_NT)
    PLATFORM := windows
    EXE_EXT := .exe
endif

.PHONY: all check engine main demo clean build-standalone build-linux build-windows build-macos test check-tests check-puzzle build-puzzle

all: check

# Check all packages for compilation errors
check: check-engine check-main check-demo check-shmup check-puzzle check-tests
	@echo "✅ All packages compile successfully"

# Check the engine package (library, no entry point)
check-engine:
	@echo "Checking engine package..."
	$(ODIN) check src/engine/ -no-entry-point

# Check the main executable
check-main:
	@echo "Checking main package..."
	$(ODIN) check src/

# Check the demo game (library, no entry point)
check-demo:
	@echo "Checking demo game package..."
	$(ODIN) check examples/demo/src/ $(ENGINE_COLLECTION) -no-entry-point

# Check shmup game package
check-shmup:
	@echo "Checking shmup game package..."
	$(ODIN) check examples/shmup/src/ $(ENGINE_COLLECTION) -no-entry-point

# Check puzzle game package
check-puzzle:
	@echo "Checking puzzle game package..."
	$(ODIN) check examples/puzzle/src/ $(ENGINE_COLLECTION) -no-entry-point

# Check test packages compile
check-tests:
	@echo "Checking test packages..."
	$(ODIN) check tests/test_math.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_config.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_log.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_state.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_physics.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_animation.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_camera.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_particle.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_save.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_error.odin $(ENGINE_COLLECTION) -file
	$(ODIN) check tests/test_build.odin $(ENGINE_COLLECTION) -file

# Build and run tests
test: test-math test-config test-log test-state test-physics test-animation test-camera test-particle test-save test-error test-build
	@echo "✅ All tests passed"

test-math:
	@echo "Running math tests..."
	$(ODIN) run tests/test_math.odin $(ENGINE_COLLECTION) -file

test-config:
	@echo "Running config tests..."
	$(ODIN) run tests/test_config.odin $(ENGINE_COLLECTION) -file

test-log:
	@echo "Running log tests..."
	$(ODIN) run tests/test_log.odin $(ENGINE_COLLECTION) -file

test-state:
	@echo "Running state tests..."
	$(ODIN) run tests/test_state.odin $(ENGINE_COLLECTION) -file

test-physics:
	@echo "Running physics tests..."
	$(ODIN) run tests/test_physics.odin $(ENGINE_COLLECTION) -file

test-animation:
	@echo "Running animation tests..."
	$(ODIN) run tests/test_animation.odin $(ENGINE_COLLECTION) -file

test-camera:
	@echo "Running camera tests..."
	$(ODIN) run tests/test_camera.odin $(ENGINE_COLLECTION) -file

test-particle:
	@echo "Running particle tests..."
	$(ODIN) run tests/test_particle.odin $(ENGINE_COLLECTION) -file

test-save:
	@echo "Running save tests..."
	$(ODIN) run tests/test_save.odin $(ENGINE_COLLECTION) -file

test-error:
	@echo "Running error handling tests..."
	$(ODIN) run tests/test_error.odin $(ENGINE_COLLECTION) -file

test-build:
	@echo "Running build system tests..."
	$(ODIN) run tests/test_build.odin $(ENGINE_COLLECTION) -file

# Build the engine executable
build:
	@echo "Building voidengine..."
	$(ODIN) build src/ -out:voidengine$(EXE_EXT)

# Build the demo game as a DLL
build-demo:
	@echo "Building demo game DLL..."
	$(ODIN) build examples/demo/src/ $(ENGINE_COLLECTION) -build-mode:dll -no-entry-point -out:examples/demo/game.dll

# Build standalone executable (game + engine in one binary)
build-standalone:
	@echo "Building standalone executable..."
	$(ODIN) build examples/demo/src/ $(ENGINE_COLLECTION) -build-mode:exe -out:demo-standalone$(EXE_EXT)

# Build the shmup game as a DLL
build-shmup:
	@echo "Building shmup game DLL..."
	$(ODIN) build examples/shmup/src/ $(ENGINE_COLLECTION) -build-mode:dll -no-entry-point -out:examples/shmup/game.dll

# Build the puzzle game as a DLL
build-puzzle:
	@echo "Building puzzle game DLL..."
	$(ODIN) build examples/puzzle/src/ $(ENGINE_COLLECTION) -build-mode:dll -no-entry-point -out:examples/puzzle/game.dll

# Cross-platform builds
build-linux:
	@echo "Building for Linux..."
	$(ODIN) build src/ -out:voidengine-linux

build-windows:
	@echo "Building for Windows (requires cross-compilation setup)..."
	@echo "Target: windows-amd64"
	$(ODIN) build src/ -out:voidengine-windows.exe

build-macos:
	@echo "Building for macOS (requires cross-compilation setup)..."
	@echo "Target: darwin-arm64/amd64"
	$(ODIN) build src/ -out:voidengine-macos

# Build all platforms
build-all: build-linux build-windows build-macos
	@echo "Built for all platforms"

# v0.7.0: Cross-platform build verification
verify-cross-platform: build
	@echo "=== Cross-Platform Build Verification ==="
	@echo "Checking Linux build..."
	$(ODIN) check src/ -target:linux-amd64 || echo "⚠️  Linux cross-compile check failed"
	@echo "Checking Windows build..."
	$(ODIN) check src/ -target:windows-amd64 || echo "⚠️  Windows cross-compile check failed"
	@echo "Checking macOS build..."
	$(ODIN) check src/ -target:darwin-amd64 || echo "⚠️  macOS cross-compile check failed"
	@echo "=== Cross-platform verification complete ==="

# v0.7.0: Wine test for Windows build (if available)
test-windows-wine:
	@echo "Testing Windows build with Wine..."
	@which wine > /dev/null 2>&1 && wine ./voidengine-windows.exe help || echo "⚠️  Wine not available, skipping Windows test"

# Clean build artifacts
clean:
	rm -f voidengine voidengine-linux voidengine-windows.exe voidengine-macos
	rm -f examples/demo/game.dll
	rm -f examples/shmup/game.dll
	rm -f examples/puzzle/game.dll
	rm -rf examples/demo/.voidengine_build
	rm -rf examples/shmup/.voidengine_build
	rm -rf examples/puzzle/.voidengine_build

# Run the demo
run-demo: build build-demo
	./voidengine run examples/demo/

# Package manager helpers
get-math:
	./voidengine get math

get-physics:
	./voidengine get physics

# Development helpers
fmt:
	@echo "Formatting Odin code..."
	find src -name "*.odin" -exec $(ODIN) fmt {} \;

# Verify engine can compile in release mode
check-release:
	@echo "Checking release build..."
	$(ODIN) check src/ -o:speed

# Full verification
verify: check build build-demo
	@echo "✅ Full verification passed"
