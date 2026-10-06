## Child character appearance. Players pick from presets only: there is no
## free-text name or chat, which keeps a children's shared space safe by design.
extends RefCounted

const Palette := preload("res://scripts/core/palette.gd")

const NICKNAMES := ["Sunny", "Sky", "Peach", "Leaf", "Pebble", "Maple", "Clover", "Berry"]
const HAIR_STYLES := ["Bob", "Ponytail", "Curls", "Buns", "Short"]
const OUTFITS := ["Overalls", "T-shirt", "Dress"]
const EMOTES := ["wave", "cheer", "dance", "heart"]

const PRESETS := [
	{"nick": "Sunny", "skin": 1, "hair": 0, "hair_color": 0, "outfit": 0, "outfit_color": 1},
	{"nick": "Sky", "skin": 2, "hair": 2, "hair_color": 2, "outfit": 1, "outfit_color": 4},
	{"nick": "Peach", "skin": 3, "hair": 3, "hair_color": 0, "outfit": 2, "outfit_color": 2},
	{"nick": "Leaf", "skin": 0, "hair": 4, "hair_color": 3, "outfit": 1, "outfit_color": 5},
]


static func sanitize(data: Variant) -> Dictionary:
	var d: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var nick := str(d.get("nick", "Sunny"))
	if not NICKNAMES.has(nick):
		nick = "Sunny"
	return {
		"nick": nick,
		"skin": clampi(int(d.get("skin", 0)), 0, Palette.SKIN.size() - 1),
		"hair": clampi(int(d.get("hair", 0)), 0, HAIR_STYLES.size() - 1),
		"hair_color": clampi(int(d.get("hair_color", 0)), 0, Palette.HAIR.size() - 1),
		"outfit": clampi(int(d.get("outfit", 0)), 0, OUTFITS.size() - 1),
		"outfit_color": clampi(int(d.get("outfit_color", 0)), 0, Palette.PAINT.size() - 1),
	}
