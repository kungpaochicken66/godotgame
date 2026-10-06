#!/usr/bin/env bash
# Fetch project-local development tools into tools/ (git-ignored). No root needed.
#   scripts/setup_tools.sh            Godot editor + Python venv for font subsetting
#   scripts/setup_tools.sh --ios      also the iOS export template (1.3 GB download)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER=4.7.2-stable
BASE=https://github.com/godotengine/godot/releases/download/$VER
mkdir -p "$ROOT/tools/godot" "$ROOT/tools/downloads" "$ROOT/tools/fonts-src"
cd "$ROOT/tools/godot"
if [[ ! -x Godot_v${VER}_linux.x86_64 ]]; then
  curl -sSLO "$BASE/Godot_v${VER}_linux.x86_64.zip"
  curl -sSLO "$BASE/SHA512-SUMS.txt"
  grep "Godot_v${VER}_linux.x86_64.zip" SHA512-SUMS.txt | sha512sum -c -
  python3 -c "import zipfile; zipfile.ZipFile('Godot_v${VER}_linux.x86_64.zip').extractall('.')"
  chmod +x Godot_v${VER}_linux.x86_64
fi
touch ._sc_   # self-contained mode: editor data stays in tools/godot/editor_data/
if [[ ! -x "$ROOT/tools/venv/bin/python" ]]; then
  python3 -m venv "$ROOT/tools/venv"
  "$ROOT/tools/venv/bin/pip" -q install fonttools brotli
fi
cd "$ROOT/tools/fonts-src"
R=https://github.com/google/fonts/raw/main/ofl
[[ -f nunito_OFL.txt ]] || curl -sSL -o nunito_OFL.txt "$R/nunito/OFL.txt"
[[ -f "nunito_Nunito[wght].ttf" ]] || curl -sSL -o "nunito_Nunito[wght].ttf" "$R/nunito/Nunito%5Bwght%5D.ttf"
[[ -f mplusrounded1c_MPLUSRounded1c-Bold.ttf ]] || curl -sSL -o mplusrounded1c_MPLUSRounded1c-Bold.ttf "$R/mplusrounded1c/MPLUSRounded1c-Bold.ttf"
[[ -f notosanssc_OFL.txt ]] || curl -sSL -o notosanssc_OFL.txt "$R/notosanssc/OFL.txt"
[[ -f "notosanssc_NotoSansSC[wght].ttf" ]] || curl -sSL -o "notosanssc_NotoSansSC[wght].ttf" "$R/notosanssc/NotoSansSC%5Bwght%5D.ttf"
if [[ "${1:-}" == "--ios" ]]; then
  cd "$ROOT/tools/downloads"
  [[ -f Godot_v${VER}_export_templates.tpz ]] || curl -sSLO "$BASE/Godot_v${VER}_export_templates.tpz"
  grep "Godot_v${VER}_export_templates.tpz" "$ROOT/tools/godot/SHA512-SUMS.txt" | sha512sum -c -
  DEST="$ROOT/tools/godot/editor_data/export_templates/${VER/-/.}"
  mkdir -p "$DEST"
  python3 - "$DEST" <<'PY'
import sys, zipfile, os
z = zipfile.ZipFile(f'Godot_v4.7.2-stable_export_templates.tpz')
for n in z.namelist():
    if n.endswith(('ios.zip', 'version.txt')):
        open(os.path.join(sys.argv[1], os.path.basename(n)), 'wb').write(z.read(n))
PY
fi
echo "Tools ready: $("$ROOT/scripts/godot.sh" --version)"
