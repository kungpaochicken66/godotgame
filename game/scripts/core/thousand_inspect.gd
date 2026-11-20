## Thousand Town's "Who's here?" data (design/thousand-town.md section 5): turns the simulation's present
## sample into the inspect panel's answer (ui/thousand_panel.gd, header). Read only: it asks the world for the
## roster (world.sim), today's plans (world.plans()) and the last occupancy sample (world.town_sample()), the
## same ones the windows and the residents use, so the panel, the lit windows and the figures agree.
extends RefCounted

const Data := preload("res://scripts/core/thousand_sim_data.gd")

## Upstream's role keys (Data.CENSUS) -> the panel's ROLES ids.
const ROLE_IDS := {
	"preschooler": "preschooler", "student-p": "primary_student", "student-m": "middle_student",
	"student-u": "university_student", "office": "office_worker", "worker": "worker", "shopkeeper": "shopkeeper",
	"driver": "driver", "teacher": "teacher", "school-admin": "school_staff", "medical-doc": "doctor",
	"medical-nurse": "nurse", "hosp-admin": "hospital_staff", "officer": "police", "clerk": "clerk",
	"sanitation": "sanitation", "unemployed": "job_seeker", "patient": "patient", "retiree": "retiree",
	"senior": "senior",
}
## Data.STATES (by index) -> the panel's STATES ids.
const STATE_IDS := ["home", "commuting", "work", "out", "doctor", "shopping", "eating", "asleep"]
## A list longer than this shows its first LIST_MAX entries (the count line still gives the whole number).
const LIST_MAX := 60
## The English place name of "on the street" (translated by the panel).
const STREET_NAME := "On the way"


## The panel's answer for a building (ledger id), or {} when the town has no sample yet or the id is unknown.
static func provide(world: Node3D, id: String, locale := "") -> Dictionary:
	if world == null or world.sim == null:
		return {}
	var sample: Dictionary = world.town_sample()
	var plans = world.plans()
	if sample.is_empty() or plans == null:
		return {}
	var b := -1
	for i in Data.BUILDINGS.size():
		if str(Data.BUILDINGS[i]["id"]) == id:
			b = i
	if b < 0:
		return {}
	if locale == "":
		locale = TranslationServer.get_locale()
	var row: Dictionary = sample["buildings"][b]
	var minute := float(sample["minute"])
	var counts := {}
	var by_state: PackedInt32Array = row["by_state"]
	for s in by_state.size():
		if by_state[s] > 0:
			counts[STATE_IDS[s]] = by_state[s]
	var here: Array = []
	var present: PackedInt32Array = row["present"]
	for k in mini(present.size(), LIST_MAX):
		here.append(resident(world, present[k], minute, locale))
	var lives: Array = []
	var homes: PackedInt32Array = world.sim.homes[b]
	for k in mini(homes.size(), LIST_MAX):
		lives.append(resident(world, homes[k], minute, locale))
	return {"id": id, "name": place_name(world, b), "open": bool(row["open"]), "count": int(row["count"]),
		"counts": counts, "here": here, "lives": lives, "lives_count": homes.size(), "minute": minute}


## One resident for the panel: who, what now, and today's plan with the current part marked.
static func resident(world: Node3D, i: int, minute: float, locale := "en") -> Dictionary:
	var sim = world.sim
	var plans = world.plans()
	var st: Dictionary = sim.state_at(plans, i, minute)
	var plan: Array = []
	var now_k: int = sim.segment_index_at(plans, i, minute)
	var segs: Array = sim.plan(plans, i)
	for k in segs.size():
		var seg: Dictionary = segs[k]
		plan.append({"from": seg["start"], "to": seg["end"], "state": STATE_IDS[int(seg["state"])],
			"where": place_name(world, int(seg["location"])), "now": k == now_k})
	return {"id": str(sim.ids[i]), "index": i, "name": sim.name_of(i, locale),
		"role": str(ROLE_IDS.get(sim.role_name(i), sim.role_name(i))), "age": int(sim.age[i]),
		"state": STATE_IDS[int(st.get("state", 0))], "where": place_name(world, int(st.get("location", Data.STREET))),
		"location": int(st.get("location", Data.STREET)), "plan": plan}


## The English name (the catalogs translate it) of a sim location: a building index or Data.STREET.
static func place_name(world: Node3D, location: int) -> String:
	if location < 0 or location >= Data.BUILDINGS.size():
		return STREET_NAME
	var id := str(Data.BUILDINGS[location]["id"])
	return str(world.NAMES.get(id, id))
