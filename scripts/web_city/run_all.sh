#!/usr/bin/env bash
# Every EC2 check of the Three.js city (design/city-threejs.md §6). EC2-headless evidence only: logic and
# parity with the Godot city, never looks or device performance.
#   scripts/web_city/run_all.sh
# Needs Node 18+ and, for the browser checks, playwright-core with its Chromium headless shell
# ($PLAYWRIGHT_CORE = path to the playwright-core package).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
step() {
  local name="$1"; shift
  if "$@" >"$TMP/$name.log" 2>&1; then
    echo "PASS $name"
  else
    echo "FAIL $name (log follows)"; tail -40 "$TMP/$name.log"; fail=1
  fi
}

# 1. The export is current: a fresh export equals the checked-in data, byte for byte.
export_drift() {
  scripts/godot.sh --headless --path game --script res://tests/web_city/export.gd -- --out="$TMP/export" || return 1
  for f in city.json city.bin consts.json; do
    cmp "$TMP/export/$f" "game/web_city/data/$f" || { echo "game/web_city/data/$f differs from a fresh export"; return 1; }
  done
}
step export_drift export_drift

# 2. Parity of the ports with Godot (each test reads its fixture; the fixtures are regenerated first).
for area in world people camera; do
  if [[ -f "game/tests/web_city/parity_$area.gd" ]]; then
    step "fixture_$area" scripts/godot.sh --headless --path game --script "res://tests/web_city/parity_$area.gd"
  fi
  if [[ -f "scripts/web_city/$area.test.mjs" ]]; then
    step "parity_$area" node --test "scripts/web_city/$area.test.mjs"
  fi
done

# 3. The page in headless Chromium (software WebGL): it starts, in each weather, and its input works.
if [[ -n "${PLAYWRIGHT_CORE:-}" || -d node_modules/playwright-core ]]; then
  for q in 'harness=1' 'harness=1&weather=1' 'harness=1&weather=2'; do
    step "page_${q//[^a-z0-9]/_}" node scripts/web_city/page_check.mjs --query="$q"
  done
  [[ -f scripts/web_city/input_check.mjs ]] && step input_check node scripts/web_city/input_check.mjs
  [[ -f scripts/web_city/e2e.mjs ]] && step e2e node scripts/web_city/e2e.mjs
  [[ -f scripts/web_city/bench_check.mjs ]] && step bench_check node scripts/web_city/bench_check.mjs
  [[ -f scripts/web_city/early_post_check.mjs ]] && step early_post_check node scripts/web_city/early_post_check.mjs
else
  echo "BLOCKED browser checks: set PLAYWRIGHT_CORE to a playwright-core package"; fail=1
fi

# 4. Godot's side.
for t in city_web_tests web_city_tests; do
  [[ -f "game/tests/$t.gd" ]] && step "$t" scripts/godot.sh --headless --path game --script "res://tests/$t.gd"
done

if [[ $fail -eq 0 ]]; then echo "WEB CITY ALL PASS (EC2 headless: logic only)"; else echo "WEB CITY FAILURES"; fi
exit $fail
