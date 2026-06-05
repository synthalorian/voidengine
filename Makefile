# VoidEngine Build System
# https://github.com/voidengine/voidengine

ODIN_ROOT := /tmp/odin-linux-amd64-nightly+2026-05-03
ODIN := ODIN_ROOT=$(ODIN_ROOT) $(ODIN_ROOT)/odin
ENGINE_COLLECTION := -collection:engine=src

.PHONY: all check engine main demo clean

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
	$(ODIN) build src/ -out:voidengine

# Build the demo game as a DLL
build-demo:
	@echo "Building demo game DLL..."
	$(ODIN) build examples/demo/src/ $(ENGINE_COLLECTION) -build-mode:dll -no-entry-point -out:examples/demo/game.dll

# Clean build artifacts
clean:
	rm -f voidengine
	rm -f examples/demo/game.dll

# Run the demo
run-demo: build build-demo
	./voidengine run examples/demo/
