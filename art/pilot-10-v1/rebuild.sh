#!/usr/bin/env bash
# Rebuild the pilot-10 GLBs from the versioned builders and compare them with the
# reviewed models. Uses the project's Godot (scripts/godot.sh); no private runtime.
#   art/pilot-10-v1/rebuild.sh [out_dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$(mktemp -d)}"
# The builders load res://kit/...; recreate the (git-ignored) link to the skill scripts.
[[ -e "$HERE/project/kit" ]] || ln -s ../skills/cozy-game-modeling/scripts "$HERE/project/kit"
IDS=(01-chair 02-round-table 03-bed 04-writing-bureau 05-open-shelf 06-desk-lamp 07-wall-clock 08-curved-counter 09-flower-pot 10-bird-mobile)
"$ROOT/scripts/godot.sh" --headless --path "$HERE/project" --script res://build_items.gd -- "$OUT" "${IDS[@]}" 2>&1 | grep -E "tris=|ERROR" || true
status=0
for id in "${IDS[@]}"; do
  if cmp -s "$OUT/$id.glb" "$HERE/models/$id.glb"; then echo "identical  $id"; else echo "DIFFERENT  $id"; status=1; fi
done
exit $status
