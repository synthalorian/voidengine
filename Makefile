# VoidEngine Makefile
# Built with Odin + SDL2

ODIN := odin
OUT_DIR := .

.PHONY: all build check test clean run run-demo run-puzzle

all: build

build: shmup demo puzzle

shmup:
	$(ODIN) build examples/shmup -out:$(OUT_DIR)/shmup -debug

demo:
	$(ODIN) build examples/demo -out:$(OUT_DIR)/demo -debug

puzzle:
	$(ODIN) build examples/puzzle -out:$(OUT_DIR)/puzzle -debug

shared:
	$(ODIN) build src/core -build-mode:shared -out:$(OUT_DIR)/voidengine.so -debug

check:
	$(ODIN) check src/core -no-entry-point
	$(ODIN) check examples/shmup -no-entry-point
	$(ODIN) check examples/demo -no-entry-point
	$(ODIN) check examples/puzzle -no-entry-point

test:
	@echo "Running engine tests..."
	$(ODIN) test tests/ -out:$(OUT_DIR)/voidengine-test

clean:
	rm -f shmup demo puzzle voidengine.so voidengine-test

run: shmup
	./shmup

run-demo: demo
	./demo

run-puzzle: puzzle
	./puzzle
