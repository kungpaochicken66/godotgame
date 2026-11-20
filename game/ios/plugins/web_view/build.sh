#!/usr/bin/env bash
# Builds the WebView plugin for the Godot 4.7.2 iOS export (run on the Mac).
#
#   ios/plugins/web_view/build.sh /path/to/godot-4.7.2-stable
#
# Produces web_view.debug.xcframework and web_view.release.xcframework.
# Godot's iOS exporter picks <binary>.debug.<ext> for debug exports and
# <binary>.release.<ext> for release exports when **both exist and the plain
# <binary> does not** (the plain web_view.xcframework would be used for both
# modes, which breaks the debug link: ClassDB::bind_method differs with
# DEBUG_ENABLED). So the plain one is removed here.
#
# Engine source: the exact tag 4.7.2-stable (commit ed1daf0bf001b61586d9930840f2f1394092c079):
#   git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git godot-4.7.2
# Only the generated headers are requested from SCons (no engine objects are built);
# override the list with GODOT_GEN_TARGETS="..." if a header is reported missing.
#
# Same structure as ../photo_library/build.sh, plus two checks of this plugin: its entry
# points, and that only the debug libraries let Safari's Web Inspector attach to the page (check_inspectable.sh).
set -euo pipefail
GODOT_SRC="${1:?path to the Godot 4.7.2-stable source}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build"
# Minimum list confirmed on a clean 4.7.2 source (Mac): exactly these SCons targets.
GEN_TARGETS="${GODOT_GEN_TARGETS:-core/version_generated.gen.h core/disabled_classes.gen.h core/object/gdvirtual.gen.h core/extension/gdextension_interface.gen.h}"

rm -rf "$OUT" "$HERE/web_view.xcframework" "$HERE/web_view.debug.xcframework" "$HERE/web_view.release.xcframework"
mkdir -p "$OUT"

echo "Generating Godot headers: $GEN_TARGETS"
( cd "$GODOT_SRC" && scons platform=ios target=template_release arch=arm64 $GEN_TARGETS ) >"$OUT/headers.log" 2>&1 || {
	echo "SCons failed to generate the headers (see $OUT/headers.log)"; exit 1; }
for h in $GEN_TARGETS; do
	[[ -f "$GODOT_SRC/$h" ]] || { echo "Missing generated header $h (see $OUT/headers.log)"; exit 1; }
done

# $1 variant (debug|release), $2 sdk, $3 arch, $4 platform dir, $5 min version flag
compile() {
	local defs=(-DIOS_ENABLED -DUNIX_ENABLED -DCOREAUDIO_ENABLED -DTYPED_METHOD_BIND)
	if [[ "$1" == "debug" ]]; then
		defs+=(-DDEBUG_ENABLED)            # matches the template_debug export ABI
	else
		defs+=(-DNDEBUG)
	fi
	local dir="$OUT/$1/$4"
	mkdir -p "$dir"
	xcrun -sdk "$2" clang++ -c "$HERE/src/web_view.mm" -o "$dir/web_view.o" \
		-arch "$3" "$5" -std=gnu++17 -fobjc-arc -fmodules -O2 "${defs[@]}" \
		-I"$GODOT_SRC" -I"$GODOT_SRC/platform/ios" -I"$HERE/src"
	xcrun -sdk "$2" libtool -static -o "$dir/libweb_view.a" "$dir/web_view.o"
}

for variant in debug release; do
	compile "$variant" iphoneos arm64 device -miphoneos-version-min=15.0
	compile "$variant" iphonesimulator arm64 simulator -mios-simulator-version-min=15.0
	xcodebuild -create-xcframework \
		-library "$OUT/$variant/device/libweb_view.a" -headers "$HERE/src" \
		-library "$OUT/$variant/simulator/libweb_view.a" -headers "$HERE/src" \
		-output "$HERE/web_view.$variant.xcframework"
	# The debug library must reference the DEBUG_ENABLED binder (MethodDefinition) and not the release
	# one; the release library the opposite. The nm output is captured to a file first and then searched,
	# so the check never depends on a live pipe.
	nm -C "$OUT/$variant/device/libweb_view.a" > "$OUT/$variant/symbols.txt"
	DEBUG_BINDER="bind_methodfi(unsigned int, MethodBind*, bool, MethodDefinition const&"
	RELEASE_BINDER="bind_methodfi(unsigned int, MethodBind*, bool, char const*"
	if [[ "$variant" == "debug" ]]; then want="$DEBUG_BINDER"; other="$RELEASE_BINDER"; else want="$RELEASE_BINDER"; other="$DEBUG_BINDER"; fi
	grep -F -- "$want" "$OUT/$variant/symbols.txt" >/dev/null \
		|| { echo "$variant library lacks its binder: $want (see $OUT/$variant/symbols.txt)"; exit 1; }
	if grep -F -- "$other" "$OUT/$variant/symbols.txt" >/dev/null; then
		echo "$variant library references the other mode's binder: $other"; exit 1
	fi
	# The entry points named in web_view.gdip must be defined (Godot's exported project calls them).
	for entry in "web_view_init()" "web_view_deinit()"; do
		grep -F -- "$entry" "$OUT/$variant/symbols.txt" >/dev/null \
			|| { echo "$variant library lacks $entry (see $OUT/$variant/symbols.txt)"; exit 1; }
	done
	# Web Inspector access (WKWebView.inspectable) is compiled into the debug libraries only, the device one
	# and the simulator one (check_inspectable.sh: by its selector stub or its selector string).
	strings -a "$OUT/$variant/device/libweb_view.a" > "$OUT/$variant/strings.txt"
	nm -C "$OUT/$variant/simulator/libweb_view.a" > "$OUT/$variant/simulator-symbols.txt"
	strings -a "$OUT/$variant/simulator/libweb_view.a" > "$OUT/$variant/simulator-strings.txt"
	bash "$HERE/check_inspectable.sh" "$variant" "$OUT/$variant/symbols.txt" "$OUT/$variant/strings.txt" \
		"$OUT/$variant/simulator-symbols.txt" "$OUT/$variant/simulator-strings.txt"
done
[[ ! -e "$HERE/web_view.xcframework" ]] || { echo "plain web_view.xcframework must not exist"; exit 1; }
echo "built web_view.debug.xcframework and web_view.release.xcframework"
