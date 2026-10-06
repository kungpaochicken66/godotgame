#!/usr/bin/env bash
# Run the project-local Godot 4.7.2. A "._sc_" file next to the binary enables Godot's
# self-contained mode, so editor settings, export templates and user:// data all
# live in tools/godot/editor_data/ instead of the home directory.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
if [[ ! -x "$GODOT" ]]; then
  echo "Godot not found at $GODOT. Run scripts/setup_tools.sh or set GODOT=/path/to/godot." >&2
  exit 2
fi
exec "$GODOT" "$@"
