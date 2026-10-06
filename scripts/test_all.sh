#!/usr/bin/env bash
# Run every automated check. Rendered steps need xvfb-run (or a real display).
#   scripts/test_all.sh            all checks
#   scripts/test_all.sh --quick    skip the rendered tour and the network test
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PY=python3; [[ -x tools/venv/bin/python ]] && PY=tools/venv/bin/python
echo "== repository checks";      $PY scripts/check.py
echo "== music loop";             python3 scripts/check_audio.py
echo "== import";                 scripts/godot.sh --headless --path game --import >/dev/null 2>&1
echo "== unit + session tests";   scripts/godot.sh --headless --path game -s res://tests/run_tests.gd 2>&1 | grep -E "FAIL|checks"
[[ "${1:-}" == "--quick" ]] && exit 0
echo "== multiplayer (real WebSocket processes on loopback)"
python3 scripts/net_test.py | grep -E "FAIL|NET TEST|save file"
echo "== rendered tour, six languages (software OpenGL)"
mkdir -p tools/shots
xvfb-run -a -s "-screen 0 1366x1024x24" scripts/godot.sh --path game -- --driver=res://tests/capture_tour.gd \
  --shots="$ROOT/tools/shots" --locales=en,zh-CN,ja,es,fr,de 2>&1 | grep -E "FAIL|TOUR"
echo "== placement tools stay clear of the item (iPad 4:3, iPad Air 5, iPhone landscape with insets)"
for spec in "ipad 1366x1024 1400x1100 0,0,0,0" "ipadair 1475x1024 1500x1100 0,0,0,32" "iphone 2208x1024 2300x1100 154,0,154,55"; do
  set -- $spec
  xvfb-run -a -s "-screen 0 $3x24" scripts/godot.sh --path game --resolution "$2" -- --driver=res://tests/dock_tour.gd \
    --shots="$ROOT/tools/shots" --tag="$1" --safe-insets="$4" 2>&1 | grep -E "FAIL|DOCK"
done
