#!/bin/bash
# Runs a Godot script in a project with a private self-contained Godot binary.
# Usage: GODOT=<binary next to a ._sc_ file> godot_run.sh <project_dir> [--gl] <script> -- args...
# --gl uses xvfb + OpenGL (needed for rendering); otherwise headless.
set -e
proj="$1"; shift
gl=0; if [ "$1" == "--gl" ]; then gl=1; shift; fi
script="$1"; shift
cd "$proj"
if [ $gl == 1 ]; then
  timeout 900 xvfb-run -a -s "-screen 0 1280x1024x24" "$GODOT" --audio-driver Dummy --rendering-driver opengl3 --path . --script "$script" "$@" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR:|^\[|tris" | grep -v "leaked\|PagedAllocator\|Pages in use" || true
else
  timeout 600 "$GODOT" --headless --audio-driver Dummy --path . --script "$script" "$@" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR:|^\[|tris|ok=" | grep -v "leaked\|PagedAllocator\|Pages in use" || true
fi
