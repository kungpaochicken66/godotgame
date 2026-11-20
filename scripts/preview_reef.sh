#!/usr/bin/env bash
# Open the local native reef directly using the project's compatibility renderer.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
engine="${GODOT:-godot}"
exec "$engine" --path "$root/game" --rendering-method gl_compatibility --resolution 1280x720 -- --reef-preview
