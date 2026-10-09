## Toy box queries (pure, unit-tested): which kinds to show for a tab, a
## placement filter and a search text. Filters are derived from the catalog's
## existing metadata (anchor, size class, seats, support surface); nothing here
## edits the catalog. See design/item-browser-ux.md.
extends RefCounted

## Placement filters in display order: id -> English label (translated by the UI).
const PLACEMENTS := {
	"floor": "Floor",
	"small": "Small things",
	"wall": "On the wall",
	"ceiling": "Ceiling",
	"seats": "Seats",
	"tables": "Tables",
}
const RECENT_MAX := 10

## Latin letters with accents -> plain letters, so "cafe" finds "Café".
const FOLD := {
	"à": "a", "á": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "ç": "c",
	"è": "e", "é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i",
	"ñ": "n", "ò": "o", "ó": "o", "ô": "o", "ö": "o", "õ": "o", "ù": "u", "ú": "u",
	"û": "u", "ü": "u", "ý": "y", "ÿ": "y", "ß": "ss", "œ": "oe", "æ": "ae",
}


static var _norm_cache := {}


## Lowercase, accents folded, full-width ASCII made half-width, spaces collapsed.
## Names are normalized once and cached (the toy box asks on every keystroke).
static func normalize(text: String) -> String:
	if _norm_cache.has(text):
		return _norm_cache[text]
	var out := ""
	for ch in text.to_lower():
		var c := ch.unicode_at(0)
		if c >= 0xFF01 and c <= 0xFF5E:
			ch = char(c - 0xFEE0).to_lower()
		elif c == 0x3000:
			ch = " "
		out += FOLD.get(ch, ch)
	out = " ".join(out.split(" ", false))
	if _norm_cache.size() > 20000:
		_norm_cache.clear()
	_norm_cache[text] = out
	return out


static func in_placement(def: Dictionary, placement: String) -> bool:
	var anchor: String = def.get("anchor", "ground")
	var small: bool = def.get("size_class", "") == "small" or def.get("tabletop_eligible", false)
	match placement:
		"floor": return anchor == "ground" and not small
		"small": return anchor == "ground" and small
		"wall": return anchor == "wall"
		"ceiling": return anchor == "ceiling"
		"seats": return def.get("seats", 0) > 0
		"tables": return not def.get("support_surface", {}).is_empty()
	return true


## Placement filters worth offering for these kinds: those that hold at least
## one but not all of them. Returns [{id, count}] in display order.
static func placement_chips(items: Dictionary, kinds: Array) -> Array:
	var out := []
	for p in PLACEMENTS:
		var n := 0
		for k in kinds:
			if in_placement(items[k], p):
				n += 1
		if n > 0 and n < kinds.size():
			out.append({"id": p, "count": n})
	return out


## How well a search matches a name: 0 whole name, 1 start, 2 start of a word,
## 3 anywhere, -1 no match. Both arguments are already normalized.
static func match_rank(name: String, q: String) -> int:
	if q == "":
		return 3
	if name == q:
		return 0
	if name.begins_with(q):
		return 1
	var at := name.find(q)
	if at < 0:
		return -1
	var before := name[at - 1]
	return 2 if before in [" ", "-", "'", "(", "/"] else 3


## Kinds for the toy box. `tab` is a category, "All" or "Recent" (a theme tab
## also lists the existing kinds in `extra`); `allowed` says
## whether a kind belongs in the current space; `label` translates a name.
## A search looks across every tab. Results are sorted by match rank, then by
## the shown name; Recent keeps its own order.
static func query(items: Dictionary, allowed: Callable, tab: String, placement: String, text: String,
		label: Callable, recent: Array = [], extra: Array = []) -> Array:
	var q := normalize(text)
	var pool: Array = []
	if q == "" and tab == "Recent":
		pool = recent.filter(func(k): return items.has(k))
	else:
		for k in items:
			if q != "" or tab == "All" or items[k].get("category", "") == tab or extra.has(k):
				pool.append(k)
	var scored := []
	for k in pool:
		var def: Dictionary = items[k]
		if not allowed.call(k) or (placement != "" and not in_placement(def, placement)):
			continue
		var shown := normalize(label.call(def["name"]))
		var rank := match_rank(shown, q)
		if rank < 0 and q != "":
			# The English name also counts, a little lower than the shown language.
			var en := match_rank(normalize(def["name"]), q)
			rank = 4 if en >= 0 else -1
		if rank >= 0:
			scored.append([rank, shown, k])
	if q == "" and tab == "Recent":
		return scored.map(func(s): return s[2])
	scored.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	return scored.map(func(s): return s[2])


## The recent list with `kind` moved to the front, capped.
static func remember(recent: Array, kind: String) -> Array:
	var out := [kind]
	for k in recent:
		if k != kind and out.size() < RECENT_MAX:
			out.append(k)
	return out


## Tap disambiguation: candidates are [{id, score}] with lower score = closer
## (distance over projected radius). One clear hit picks directly; otherwise
## the closest few are offered. Returns the ids to offer (one id = pick it).
static func tap_choices(candidates: Array, limit := 4) -> Array:
	var c := candidates.duplicate()
	c.sort_custom(func(a, b): return a["score"] < b["score"])
	if c.is_empty():
		return []
	if c.size() == 1 or c[0]["score"] < 0.3 or c[1]["score"] > c[0]["score"] * 1.8 + 0.15:
		return [c[0]["id"]]
	return c.slice(0, limit).map(func(x): return x["id"])
