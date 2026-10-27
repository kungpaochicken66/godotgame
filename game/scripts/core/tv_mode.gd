## Apple TV build (atv-r20-controller, design/tv-controller.md): one switch for everything that differs on
## a TV. On a TV there is no touch screen, no on-screen keyboard and no Photos library, so text fields are
## not offered, the screen keeps clear of the TV's overscan edges, and photos stay in the scrapbook.
## Everything else (town rules, network protocol 10, save schema 2) is the same game as on iPhone and iPad.
extends RefCounted

## Tests and a desktop rehearsal force the TV behaviour with --tv (main.gd): 1 on, 0 off, -1 automatic.
static var forced := -1

## Title-safe margins of a TV picture (Apple's tvOS layout guide: 60 pt top and bottom, 80 pt at the sides of
## 1920 x 1080), as fractions of the screen.
const SAFE_X := 80.0 / 1920.0
const SAFE_Y := 60.0 / 1080.0


static func active() -> bool:
	if forced >= 0:
		return forced == 1
	# --tv also counts before main.gd reads its arguments (the autoloads restore saves first).
	return OS.get_name() == "tvOS" or OS.has_feature("tvos") or OS.get_cmdline_user_args().has("--tv")


## Text entry needs a keyboard, which the TV build does not have.
static func can_type() -> bool:
	return not active()
