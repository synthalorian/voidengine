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

.PHONY: all check engine main demo clean build-standalone build-linux build-windows build-macos

all: check

# Check all packages for compilation errors
check: check-engine check-main check-demo
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

# Clean build artifacts
clean:
	rm -f voidengine voidengine-linux voidengine-windows.exe voidengine-macos
	rm -f examples/demo/game.dll
	rm -rf examples/demo/.voidengine_build

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
