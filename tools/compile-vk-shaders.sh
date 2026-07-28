#!/usr/bin/env bash
# compile-vk-shaders.sh — compile the vk3d GLSL shaders to SPIR-V.
#
# Usage: tools/compile-vk-shaders.sh [output_dir]
#   output_dir defaults to examples/void3d/assets/shaders
#
# Requires glslc (shaderc) on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src/core/shaders"
OUT="${1:-$ROOT/examples/void3d/assets/shaders}"

mkdir -p "$OUT"

SHADERS=(
    vk_sprite.vert
    vk_sprite.frag
    vk_post.vert
    vk_bright.frag
    vk_blur.frag
    vk_composite.frag
)

for s in "${SHADERS[@]}"; do
    echo "glslc $s -> $OUT/$s.spv"
    glslc "$SRC/$s" -o "$OUT/$s.spv"
done

echo "vk shaders compiled to $OUT"
