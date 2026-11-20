#!/usr/bin/env bash
# Checks that Safari's Web Inspector can attach to the page (WKWebView.inspectable = YES) in the debug
# libraries only. build.sh calls it for each library: the device one and the simulator one.
#
#   check_inspectable.sh debug|release <nm -C output> <strings -a output> [<nm -C output> <strings -a output> ...]
#
# Clang sends `view.inspectable = YES` (the message setInspectable:) in one of two forms:
# - Through a selector stub. This is Xcode's default on arm64 (-fobjc-msgsend-selector-stubs, Xcode 14 and
#   later), and it is what the Mac's first build of r1 produced. The object holds only the undefined symbol
#   _objc_msgSend$setInspectable: and no selector string; the linker makes the stub and the string when the
#   app is linked. nm shows it; strings does not.
# - Through a classic selector reference: the string "setInspectable:" in __objc_methname. strings shows it.
# A debug library must show one of the two, by its exact name. A release library must show no trace of
# setInspectable in either listing.
set -euo pipefail
variant="${1:-}"
[[ "$variant" == "debug" || "$variant" == "release" ]] || { echo "usage: check_inspectable.sh debug|release <symbols> <strings> [...]"; exit 2; }
shift
(( $# >= 2 && $# % 2 == 0 )) || { echo "usage: check_inspectable.sh debug|release <symbols> <strings> [...]"; exit 2; }
while (( $# )); do
	symbols="$1"; strings="$2"; shift 2
	[[ -s "$symbols" && -s "$strings" ]] || { echo "$variant library: missing or empty listing ($symbols, $strings)"; exit 1; }
	if [[ "$variant" == "debug" ]]; then
		if grep -E -- '(^|[[:space:]])U _objc_msgSend\$setInspectable:$' "$symbols" >/dev/null; then
			echo "debug library makes the page inspectable: the selector stub _objc_msgSend\$setInspectable: ($symbols)"
		elif grep -F -x -- "setInspectable:" "$strings" >/dev/null; then
			echo "debug library makes the page inspectable: the selector setInspectable: ($strings)"
		else
			echo "debug library does not make the page inspectable: neither the selector stub _objc_msgSend\$setInspectable: (see $symbols) nor the selector setInspectable: (see $strings)"
			exit 1
		fi
	elif grep -F -- "setInspectable" "$symbols" "$strings" >/dev/null; then
		echo "release library makes the page inspectable (see $symbols, $strings)"
		exit 1
	fi
done
