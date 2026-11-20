#!/usr/bin/env bash
# Run the standing automated checks. Rendered steps need xvfb-run (or a real display).
#   scripts/test_all.sh            all standing checks
#   scripts/test_all.sh --quick    skip packaging, the network tests and the rendered tours
# Feature tours and the other net_test.py modes are listed in README.md and run per candidate.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PY=python3; [[ -x tools/venv/bin/python ]] && PY=tools/venv/bin/python
echo "== repository checks";      $PY scripts/check.py
echo "== music loop";             python3 scripts/check_audio.py
echo "== import"
IMPORT_LOG="$(mktemp)"; trap 'rm -f "$IMPORT_LOG"' EXIT
scripts/godot.sh --headless --path game --import >"$IMPORT_LOG" 2>&1 || { tail -n 30 "$IMPORT_LOG"; echo "FAIL: import"; exit 1; }
echo "== unit + session tests";   scripts/godot.sh --headless --path game -s res://tests/run_tests.gd 2>&1 | grep -E "FAIL|checks"
echo "== puzzle rooms and rideable carts: rules, saves, scale and clearance, the authority"
scripts/godot.sh --headless --path game -s res://tests/puzzle_ride_tests.gd 2>&1 | grep -E "^FAIL|PUZZLE RIDE TESTS"
echo "== town evenings and more: rules, saves, the authority"
scripts/godot.sh --headless --path game -s res://tests/town_play_tests.gd 2>&1 | grep -E "^FAIL|TOWN PLAY TESTS"
echo "== first steps and the guide's second section"
scripts/godot.sh --headless --path game -s res://tests/first_steps_tests.gd 2>&1 | grep -E "^FAIL|FIRST STEPS TESTS"
echo "== the zoo: map, brain, models, skins, life, camera, props, saves (schema 3), protocol 16, guide and scrapbook"
for t in zoo_tests zoo_skin_tests zoo_life_tests zoo_camera_tests zoo_props_tests zoo_save_tests zoo_net_tests zoo_ui_tests; do
  scripts/godot.sh --headless --path game -s "res://tests/$t.gd" 2>&1 | grep -E "^FAIL|ZOO .*TESTS"
done
echo "== the city: navigation, walks along every route, rules, camera, art and budgets, the shared state"
for t in city_nav_tests city_walk_tests city_rules_tests city_orbit_tests city_art_tests city_people_tests city_net_tests; do
  scripts/godot.sh --headless --path game -s "res://tests/$t.gd" 2>&1 | grep -E "^FAIL|CITY .*TESTS"
done
echo "== the web city: the map city_web, its own shared state (CityWeb), the page's input, logic-only poses (without and with --web-city)"
scripts/godot.sh --headless --path game -s res://tests/city_web_tests.gd 2>&1 | grep -E "^FAIL|CITY WEB TESTS"
scripts/godot.sh --headless --path game -s res://tests/city_web_tests.gd -- --web-city 2>&1 | grep -E "^FAIL|CITY WEB TESTS"
echo "== the web city's bridge: HTTP and WebSocket servers, the protocol with a scripted page, the children's packs and poses, the export unchanged"
scripts/godot.sh --headless --path game -s res://tests/web_city_tests.gd 2>&1 | grep -E "^FAIL|WEB CITY TESTS"
echo "== Thousand Town: the map thousand, the Thousand clock and bus seats, the placeholder world, the follow camera, the HUD (protocol 20)"
scripts/godot.sh --headless --path game -s res://tests/thousand_tests.gd 2>&1 | grep -E "^FAIL|THOUSAND TESTS"
echo "== Thousand Town's interactions: residents, following, Who's here?, the bus, the wheel, the night market, the shows, TV, return"
scripts/godot.sh --headless --path game -s res://tests/thousand_play_tests.gd 2>&1 | grep -E "^FAIL|THOUSAND PLAY TESTS"
echo "== Thousand Town's whole loop through the real game (logic only, no renderer): the tram stop, arrival, exploring, four"
echo "   interactions, Day / Dusk / Night by the HUD's buttons, Ride home; by touch, then by the controller (PadInput only)"
echo "   (rendered frames: see the header of game/tests/thousand_loop_tour.gd)"
timeout 1500 scripts/godot.sh --headless --path game -- --driver=res://tests/thousand_loop_tour.gd --no-shots --window=1366x1024 2>&1 \
  | grep -E "^FAIL|THOUSAND LOOP TOUR"
timeout 1500 scripts/godot.sh --headless --path game -- --driver=res://tests/thousand_loop_tour.gd --tv --pad --pad-layout=nintendo --no-shots \
  --window=1920x1080 2>&1 | grep -E "^FAIL|THOUSAND LOOP TOUR"
echo "== unified r1: the town's tram stop (zoo, city, Thousand Town, Roller Coaster Workshop, Lantern Reef) and safe returns"
echo "   (rendered frames: see the headers of game/tests/station_tour.gd, coaster_tour.gd and reef_dive_tour.gd)"
timeout 1500 scripts/godot.sh --headless --path game -- --driver=res://tests/station_tour.gd --no-shots --window=1366x1024 --tag=ipad 2>&1 \
  | grep -E "^FAIL|STATION TOUR"
timeout 1500 scripts/godot.sh --headless --path game -- --driver=res://tests/station_tour.gd --tv --pad-layout=nintendo --no-shots \
  --window=1920x1080 --tag=atv 2>&1 | grep -E "^FAIL|STATION TOUR"
echo "== unified r4: ride home from each Workshop platform; Thousand Town by controller (hints, focus, time, the wheel)"
timeout 1500 scripts/godot.sh --headless --fixed-fps 30 --path game -- --driver=res://tests/coaster_home_tour.gd --no-shots \
  --window=1366x1024 --tag=ipad 2>&1 | grep -E "^FAIL|COASTER HOME TOUR"
timeout 1500 scripts/godot.sh --headless --fixed-fps 30 --path game -- --driver=res://tests/coaster_home_tour.gd --tv \
  --pad-layout=nintendo --no-shots --window=1920x1080 --tag=atv 2>&1 | grep -E "^FAIL|COASTER HOME TOUR"
timeout 1500 scripts/godot.sh --headless --path game -- --driver=res://tests/thousand_pad_tour.gd --tv --pad-layout=nintendo \
  --no-shots --window=1920x1080 --tag=atv 2>&1 | grep -E "^FAIL|THOUSAND PAD TOUR"
timeout 1500 scripts/godot.sh --headless --path game -- --driver=res://tests/thousand_pad_tour.gd --tv --pad-layout=standard \
  --no-shots --window=1920x1080 --tag=atv-std 2>&1 | grep -E "^FAIL|THOUSAND PAD TOUR"
echo "== Workshop r4: the six coasters (tools/coaster/VERIFICATION.md)"
python3 tools/coaster/check_tracks.py | tail -3
timeout 1500 scripts/godot.sh --headless --fixed-fps 30 --path game -- --driver=res://tests/coaster_tour.gd --tv --pad-layout=nintendo \
  --no-shots --window=1920x1080 --tag=tv 2>&1 | grep -E "^FAIL|COASTER TOUR"
echo "== every script parses";    scripts/godot.sh --headless --path game -s res://tests/parse_all.gd 2>&1 | grep -E "FAIL|PARSE"
echo "== release tools";          python3 scripts/test_ios_photo_purpose.py | grep -E "FAIL|IOS PHOTO"
python3 scripts/test_check_web_view_plugin.py | grep -E "FAIL|WEB VIEW"
python3 scripts/test_model_handoff.py 2>&1 | grep -E "FAIL|ERROR|^OK|^Ran"
echo "== generated catalogs match their frozen model batches"
if [[ -d tools/nookipedia-model-production/batches ]]; then
  python3 scripts/build_furniture_r2.py --check
  python3 scripts/build_wear_catalog.py --check
else
  echo "SKIPPED: tools/nookipedia-model-production is not on this host"
fi
[[ "${1:-}" == "--quick" ]] && exit 0
echo "== packaging (private settings only in the private pack)"
python3 scripts/check_packaging.py | grep -E "FAIL|PACKAGING"
echo "== multiplayer (real WebSocket processes on loopback)"
python3 scripts/net_test.py | grep -E "FAIL|NET TEST|save file"
echo "== activities with real clients (conflicting starts, late joiner, presents, hearts, restart)"
python3 scripts/net_test.py --activities | grep -E "FAIL|ACTIVITIES TEST|roles"
echo "== contraptions and a living town with real clients (chain order, a far press, a step, a late joiner, restart)"
python3 scripts/net_test.py --contraptions | grep -E "FAIL|CONTRAPTIONS TEST"
echo "== contraptions and a living town through the real UI, by touch and by controller (logic only, no renderer)"
scripts/godot.sh --headless --path game -- --driver=res://tests/contraption_tour.gd --no-shots --window=2208x1024 --tag=iphone \
  --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de 2>&1 | grep -E "^FAIL|CONTRAPTION .*(PASS|FAIL)"
scripts/godot.sh --headless --path game -- --driver=res://tests/contraption_tour.gd --tv --pad-layout=nintendo --no-shots \
  --window=1920x1080 --tag=atv --locales=en,ja 2>&1 | grep -E "^FAIL|CONTRAPTION .*(PASS|FAIL)"
echo "== puzzle rooms and rideable carts with real clients (a shared puzzle, a taken cart, a late joiner, a dropped connection, restart)"
python3 scripts/net_test.py --puzzles | grep -E "FAIL|PUZZLES TEST|save file"
echo "== puzzle rooms and rideable carts through the real UI, by touch and by controller (logic only, no renderer)"
scripts/godot.sh --headless --path game -- --driver=res://tests/puzzle_ride_tour.gd --no-shots --window=2208x1024 --tag=iphone \
  --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de 2>&1 | grep -E "^FAIL|PUZZLE_RIDE .*(PASS|FAIL)"
scripts/godot.sh --headless --path game -- --driver=res://tests/puzzle_ride_tour.gd --tv --pad-layout=nintendo --no-shots \
  --window=1920x1080 --tag=atv --locales=en,ja 2>&1 | grep -E "^FAIL|PUZZLE_RIDE .*(PASS|FAIL)"
echo "== town evenings and more with real clients, and through the real UI by touch and by controller (logic only, no renderer)"
python3 scripts/net_test.py --townplay | grep -E "FAIL|TOWNPLAY TEST|save file"
scripts/godot.sh --headless --path game -- --driver=res://tests/town_play_tour.gd --no-shots --window=2208x1024 --tag=iphone \
  --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de 2>&1 | grep -E "^FAIL|TOWN_PLAY .*(PASS|FAIL)"
scripts/godot.sh --headless --path game -- --driver=res://tests/town_play_tour.gd --tv --pad-layout=nintendo --no-shots \
  --window=1920x1080 --tag=atv --locales=en,ja 2>&1 | grep -E "^FAIL|TOWN_PLAY .*(PASS|FAIL)"
echo "== the zoo with real clients, and through the real UI by touch and by controller (logic only, no renderer)"
python3 scripts/net_test.py --zoo | grep -E "FAIL|ZOO TEST"
scripts/godot.sh --headless --path game -- --driver=res://tests/zoo_tour.gd --no-shots --window=2208x1024 --tag=iphone \
  --safe-insets=154,0,154,55 2>&1 | grep -E "^FAIL|ZOO TOUR"
scripts/godot.sh --headless --path game -- --driver=res://tests/zoo_tour.gd --tv --pad-layout=nintendo --no-shots \
  --window=1920x1080 --tag=atv 2>&1 | grep -E "^FAIL|ZOO TOUR"
echo "== the city with real clients, and through the real UI by touch and by controller (logic only, no renderer)"
python3 scripts/net_test.py --city | grep -E "FAIL|CITY TEST"
scripts/godot.sh --headless --path game -- --driver=res://tests/city_tour.gd --no-shots --window=2208x1024 --tag=iphone \
  --safe-insets=154,0,154,55 2>&1 | grep -E "^FAIL|CITY TOUR"
scripts/godot.sh --headless --path game -- --driver=res://tests/city_tour.gd --tv --pad-layout=nintendo --no-shots \
  --window=1920x1080 --tag=atv 2>&1 | grep -E "^FAIL|CITY TOUR"
echo "== the two city maps with real clients (no state crosses between city and city_web; protocol 20 enforced)"
python3 scripts/net_test.py --city-web | grep -E "FAIL|CITY WEB TEST"
echo "== Thousand Town with real clients (two children agree on the clock mode and share a bus; protocol 19 refused)"
python3 scripts/net_test.py --thousand | grep -E "FAIL|THOUSAND TEST"
echo "== first steps through the real UI, by touch and by controller (logic only, no renderer; each in a fresh user-data folder)"
FS1="$(mktemp -d)"; FS2="$(mktemp -d)"
XDG_DATA_HOME="$FS1" scripts/godot.sh --headless --path game -- --driver=res://tests/first_steps_tour.gd --first-steps --no-shots --window=2208x1024 --tag=iphone \
  --safe-insets=154,0,154,55 --locales=en,zh-CN,ja,es,fr,de 2>&1 | grep -E "^FAIL|FIRST_STEPS .*(PASS|FAIL)"
XDG_DATA_HOME="$FS2" scripts/godot.sh --headless --path game -- --driver=res://tests/first_steps_tour.gd --first-steps --tv --pad-layout=nintendo --no-shots \
  --window=1920x1080 --tag=atv --locales=en,ja 2>&1 | grep -E "^FAIL|FIRST_STEPS .*(PASS|FAIL)"
rm -rf "$FS1" "$FS2"
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
