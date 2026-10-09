## Companion pets: families, colors, names and the rules the authority applies
## (pure, unit-tested). Pets belong to a device player id and are saved in the
## town; they never block walking or placement.
extends RefCounted

## Family -> display name, its modeled variants (frozen batch p001-pets-room)
## and friendly names to choose from. Only cats, dogs, birds and butterflies.
## A saved pet's "color" is the index of its variant.
const FAMILIES := {
	"cat": {"name": "Cat", "names": ["Mochi", "Tiger", "Pumpkin", "Sesame"], "variants": [
		{"model": "pet_cat_tabby", "name": "Tabby cat", "swatch": Color("#d59a5c")},
		{"model": "pet_cat_tuxedo", "name": "Tuxedo cat", "swatch": Color("#3d3836")},
		{"model": "pet_kitten_cream", "name": "Cream kitten", "swatch": Color("#f3e3c6")}]},
	"dog": {"name": "Dog", "names": ["Noodle", "Pepper", "Waffle", "Buddy"], "variants": [
		{"model": "pet_dog_ginger", "name": "Ginger dog", "swatch": Color("#d9894a")},
		{"model": "pet_dog_spotted", "name": "Spotted dog", "swatch": Color("#f4efe6")},
		{"model": "pet_puppy_brown", "name": "Brown puppy", "swatch": Color("#8a5a3a")}]},
	"bird": {"name": "Bird", "names": ["Kiwi", "Sunny", "Poppy", "Blue"], "variants": [
		{"model": "pet_bird_blue", "name": "Blue budgie", "swatch": Color("#6fb2e0")},
		{"model": "pet_bird_yellow", "name": "Yellow canary", "swatch": Color("#f2cf4a")}]},
	"butterfly": {"name": "Butterfly", "names": ["Flutter", "Petal", "Sky", "Daisy"], "variants": [
		{"model": "pet_butterfly_blue", "name": "Blue butterfly", "swatch": Color("#6fa8e6")},
		{"model": "pet_butterfly_orange", "name": "Orange butterfly", "swatch": Color("#f39a45")}]},
}
## Hover heights from the model handoff (perching birds and butterflies).
const HOVER := {"cat": 0.0, "dog": 0.0, "bird": 0.4, "butterfly": 0.6}
const ORDER := ["cat", "dog", "bird", "butterfly"]
## Names used by r7/r8 that belong to town animals (Biscuit the dog, Pip the pig).
const RENAMED := {"Biscuit": "Noodle", "Pip": "Poppy"}
const MAX_PETS := 4
const MODES := ["follow", "home"]
## Feeding needs a food bowl this close to the child (pets stay near their owner).
const FEED_REACH := 2.0


## A player's pets: {"pets": [{id, family, color, name, pats, meals}], "active": id, "mode": "follow"|"home", "home": cottage id}
static func entry(model, pid: String) -> Dictionary:
	return model.pets.get(pid, {"pets": [], "active": "", "mode": "follow", "home": ""})


static func find_pet(model, pid: String, pet_id: String) -> Dictionary:
	for p in entry(model, pid)["pets"]:
		if p["id"] == pet_id:
			return p
	return {}


## Adopts a pet. home: the cottage whose Pet room it rests in.
static func adopt(model, pid: String, family: String, color: int, name_index: int, home: String) -> Dictionary:
	if not FAMILIES.has(family):
		return {"ok": false, "error": "That pet is not here."}
	if color < 0 or color >= FAMILIES[family]["variants"].size() or name_index < 0 or name_index >= FAMILIES[family]["names"].size():
		return {"ok": false, "error": "That pet is not here."}
	var e := entry(model, pid).duplicate(true)
	if e["pets"].size() >= MAX_PETS:
		return {"ok": false, "error": "You already have four pets. That is a lot of love!"}
	var n := 1
	for p in e["pets"]:
		n = maxi(n, int(str(p["id"]).trim_prefix("p")) + 1)
	var pet := {"id": "p%d" % n, "family": family, "color": color, "name": FAMILIES[family]["names"][name_index], "pats": 0, "meals": 0}
	e["pets"].append(pet)
	e["active"] = pet["id"]
	e["mode"] = "follow"
	if home != "":
		e["home"] = home
	model.pets[pid] = e
	return {"ok": true, "pet": pet}


static func set_active(model, pid: String, pet_id: String) -> Dictionary:
	if pet_id != "" and find_pet(model, pid, pet_id).is_empty():
		return {"ok": false, "error": "That pet is not here."}
	var e := entry(model, pid).duplicate(true)
	e["active"] = pet_id
	model.pets[pid] = e
	return {"ok": true}


static func set_mode(model, pid: String, mode: String) -> Dictionary:
	if not MODES.has(mode) or entry(model, pid)["pets"].is_empty():
		return {"ok": false, "error": "That pet is not here."}
	var e := entry(model, pid).duplicate(true)
	e["mode"] = mode
	model.pets[pid] = e
	return {"ok": true}


## The cottage whose Pet room a player's resting pets live in (falls back to the first cottage).
static func home_of(model, pid: String) -> String:
	var h: String = entry(model, pid).get("home", "")
	if model.items.has(h) and model.items[h]["kind"] == "cottage":
		return h
	var houses: Array = model.items.values().filter(func(i): return i["kind"] == "cottage")
	houses.sort_custom(func(a, b): return int(a["id"].substr(1)) < int(b["id"].substr(1)))
	return houses[0]["id"] if not houses.is_empty() else ""


static func pet_room(model, pid: String) -> String:
	var h := home_of(model, pid)
	return model.room_space(h, 2, 0) if h != "" else ""


## Where a pet is: the owner's space while following (owner_space), else its Pet room.
static func space_of(model, pid: String, pet_id: String, owner_space: String) -> String:
	var e := entry(model, pid)
	if e["active"] == pet_id and e["mode"] == "follow" and owner_space != "":
		return owner_space
	return pet_room(model, pid)


## Pat or feed a pet. actor_space/actor_pos: where the child doing it stands.
static func care(model, owner: String, pet_id: String, action: String, actor_space: String, actor_pos: Vector2, owner_space: String) -> Dictionary:
	var pet := find_pet(model, owner, pet_id)
	if pet.is_empty() or not action in ["pat", "feed"]:
		return {"ok": false, "error": "That pet is not here."}
	if space_of(model, owner, pet_id, owner_space) != actor_space:
		return {"ok": false, "error": "That pet is not here."}
	if action == "feed":
		var bowl := false
		for it in model.items_in(actor_space):
			if it["kind"] == "petroom_food_bowl" and Vector2(it["x"], it["z"]).distance_to(actor_pos) <= FEED_REACH:
				bowl = true
		if not bowl:
			return {"ok": false, "error": "Bring your pet to a food bowl, then feed it."}
	var e := entry(model, owner).duplicate(true)
	for p in e["pets"]:
		if p["id"] == pet_id:
			p["pats" if action == "pat" else "meals"] = int(p.get("pats" if action == "pat" else "meals", 0)) + 1
	model.pets[owner] = e
	return {"ok": true, "action": action}


## Cleans saved pet data: unknown families, colors or names are dropped.
static func sanitize(data) -> Dictionary:
	var out := {}
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for pid in data:
		var e = data[pid]
		if typeof(e) != TYPE_DICTIONARY or typeof(e.get("pets")) != TYPE_ARRAY:
			continue
		var pets := []
		for p in e["pets"]:
			if typeof(p) != TYPE_DICTIONARY or not FAMILIES.has(str(p.get("family", ""))):
				continue
			var fam := str(p["family"])
			var name := str(p.get("name", ""))
			name = RENAMED.get(name, name)
			if not FAMILIES[fam]["names"].has(name):
				name = FAMILIES[fam]["names"][0]
			pets.append({"id": str(p.get("id", "p%d" % (pets.size() + 1))).left(8), "family": fam, "color": clampi(int(p.get("color", 0)), 0, FAMILIES[fam]["variants"].size() - 1),
				"name": name, "pats": maxi(0, int(p.get("pats", 0))), "meals": maxi(0, int(p.get("meals", 0)))})
			if pets.size() >= MAX_PETS:
				break
		var active := str(e.get("active", ""))
		if not pets.any(func(p): return p["id"] == active):
			active = pets[0]["id"] if not pets.is_empty() else ""
		var mode := str(e.get("mode", "follow"))
		out[str(pid).left(64)] = {"pets": pets, "active": active, "mode": mode if MODES.has(mode) else "follow", "home": str(e.get("home", "")).left(16)}
	return out
