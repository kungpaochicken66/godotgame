#!/usr/bin/env bash
# Builds the PhotoLibrary plugin for the Godot 4.7.2 iOS export (run on the Mac).
#
#   ios/plugins/photo_library/build.sh /path/to/godot-4.7.2-stable
#
# Produces photo_library.debug.xcframework and photo_library.release.xcframework.
# Godot's iOS exporter picks <binary>.debug.<ext> for debug exports and
# <binary>.release.<ext> for release exports when **both exist and the plain
# <binary> does not** (the plain photo_library.xcframework would be used for both
# modes, which breaks the debug link: ClassDB::bind_method differs with
# DEBUG_ENABLED). So the plain one is removed here.
#
# Engine source: the exact tag 4.7.2-stable (commit ed1daf0bf001b61586d9930840f2f1394092c079):
#   git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git godot-4.7.2
# Only the generated headers are requested from SCons (no engine objects are built);
# override the list with GODOT_GEN_TARGETS="..." if a header is reported missing.
set -euo pipefail
GODOT_SRC="${1:?path to the Godot 4.7.2-stable source}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build"
# Minimum list confirmed on a clean 4.7.2 source (Mac): exactly these SCons targets.
GEN_TARGETS="${GODOT_GEN_TARGETS:-core/version_generated.gen.h core/disabled_classes.gen.h core/object/gdvirtual.gen.h core/extension/gdextension_interface.gen.h}"

rm -rf "$OUT" "$HERE/photo_library.xcframework" "$HERE/photo_library.debug.xcframework" "$HERE/photo_library.release.xcframework"
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
	xcrun -sdk "$2" clang++ -c "$HERE/src/photo_library.mm" -o "$dir/photo_library.o" \
		-arch "$3" "$5" -std=gnu++17 -fobjc-arc -fmodules -O2 "${defs[@]}" \
		-I"$GODOT_SRC" -I"$GODOT_SRC/platform/ios" -I"$HERE/src"
	xcrun -sdk "$2" libtool -static -o "$dir/libphoto_library.a" "$dir/photo_library.o"
}

for variant in debug release; do
	compile "$variant" iphoneos arm64 device -miphoneos-version-min=15.0
	compile "$variant" iphonesimulator arm64 simulator -mios-simulator-version-min=15.0
	xcodebuild -create-xcframework \
		-library "$OUT/$variant/device/libphoto_library.a" -headers "$HERE/src" \
		-library "$OUT/$variant/simulator/libphoto_library.a" -headers "$HERE/src" \
		-output "$HERE/photo_library.$variant.xcframework"
	# The debug library must reference the DEBUG_ENABLED binder (MethodDefinition) and not the release
	# one; the release library the opposite. The nm output is captured to a file first and then searched,
	# so the check never depends on a live pipe.
	nm -C "$OUT/$variant/device/libphoto_library.a" > "$OUT/$variant/symbols.txt"
	DEBUG_BINDER="bind_methodfi(unsigned int, MethodBind*, bool, MethodDefinition const&"
	RELEASE_BINDER="bind_methodfi(unsigned int, MethodBind*, bool, char const*"
	if [[ "$variant" == "debug" ]]; then want="$DEBUG_BINDER"; other="$RELEASE_BINDER"; else want="$RELEASE_BINDER"; other="$DEBUG_BINDER"; fi
	grep -F -- "$want" "$OUT/$variant/symbols.txt" >/dev/null \
		|| { echo "$variant library lacks its binder: $want (see $OUT/$variant/symbols.txt)"; exit 1; }
	if grep -F -- "$other" "$OUT/$variant/symbols.txt" >/dev/null; then
		echo "$variant library references the other mode's binder: $other"; exit 1
	fi
done
[[ ! -e "$HERE/photo_library.xcframework" ]] || { echo "plain photo_library.xcframework must not exist"; exit 1; }
echo "built photo_library.debug.xcframework and photo_library.release.xcframework"
