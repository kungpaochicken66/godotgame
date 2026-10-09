## Child character appearance. Players pick from presets only: there is no
## free-text name or chat, which keeps a children's shared space safe by design.
extends RefCounted

const Palette := preload("res://scripts/core/palette.gd")
const Wearables := preload("res://scripts/core/wearables.gd")

const NICKNAMES := ["Sunny", "Sky", "Peach", "Leaf", "Pebble", "Maple", "Clover", "Berry"]
const HAIR_STYLES := ["Bob", "Ponytail", "Curls", "Buns", "Short"]
const OUTFITS := ["Overalls", "T-shirt", "Dress"]
const EMOTES := ["wave", "cheer", "dance", "heart"]
## Story poses (design/playability-8-12.md F05): held a little longer, seen by everyone.
const POSES := ["surprised", "think", "proud", "sneak"]
const POSE_NAMES := {"surprised": "Surprised", "think": "Thinking", "proud": "Proud", "sneak": "Sneaking"}
## Dress-up (F07): head accessories, changeable in town at any time. "" = none.
## Free from the start, not tied to any role, activity or gender.
const HATS := ["", "chef", "explorer", "crown", "rain"]
const HAT_NAMES := {"": "No hat", "chef": "Chef hat", "explorer": "Explorer hat", "crown": "Paper crown", "rain": "Rain hat"}
## Handheld props (r11): held in the right hand, also changeable in town.
const PROPS := ["", "magnifier", "baton", "umbrella", "flag"]
const PROP_NAMES := {"": "Nothing in hand", "magnifier": "Magnifying glass", "baton": "Conductor's baton", "umbrella": "Umbrella", "flag": "Little flag"}

const PRESETS := [
	{"nick": "Sunny", "skin": 1, "hair": 0, "hair_color": 0, "outfit": 0, "outfit_color": 1, "hat": "", "prop": "", "wear": {}},
	{"nick": "Sky", "skin": 2, "hair": 2, "hair_color": 2, "outfit": 1, "outfit_color": 4, "hat": "", "prop": "", "wear": {}},
	{"nick": "Peach", "skin": 3, "hair": 3, "hair_color": 0, "outfit": 2, "outfit_color": 2, "hat": "", "prop": "", "wear": {}},
	{"nick": "Leaf", "skin": 0, "hair": 4, "hair_color": 3, "outfit": 1, "outfit_color": 5, "hat": "", "prop": "", "wear": {}},
]


static func sanitize(data: Variant) -> Dictionary:
	var d: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var nick := str(d.get("nick", "Sunny"))
	if not NICKNAMES.has(nick):
		nick = "Sunny"
	return resolve({
		"nick": nick,
		"skin": clampi(int(d.get("skin", 0)), 0, Palette.SKIN.size() - 1),
		"hair": clampi(int(d.get("hair", 0)), 0, HAIR_STYLES.size() - 1),
		"hair_color": clampi(int(d.get("hair_color", 0)), 0, Palette.HAIR.size() - 1),
		"outfit": clampi(int(d.get("outfit", 0)), 0, OUTFITS.size() - 1),
		"outfit_color": clampi(int(d.get("outfit_color", 0)), 0, Palette.PAINT.size() - 1),
		"hat": str(d.get("hat", "")) if HATS.has(str(d.get("hat", ""))) else "",
		"prop": str(d.get("prop", "")) if PROPS.has(str(d.get("prop", ""))) else "",
		# Worn clothing (r12): slot -> accepted wearable id; older avatars have none.
		"wear": Wearables.sanitize(d.get("wear", {})),
	})


## Worn clothing wins over the procedural hat and handheld prop it would collide with
## (EQUIP_HANDOFF 2): a head item clears the hat, a hand item clears the prop.
static func resolve(av: Dictionary) -> Dictionary:
	if av["wear"].has("head"):
		av["hat"] = ""
	if av["wear"].has("hand"):
		av["prop"] = ""
	return av


## Any emote or story pose a player may send.
static func is_emote(kind: String) -> bool:
	return EMOTES.has(kind) or POSES.has(kind)
