## Thousand Town's inspect panel (design/thousand-town.md section 5, "Inspecting"): the building's name, open or
## closed, how many are here now and by activity, two tabs ("Here now", "Lives here") with a list of residents,
## and the picked resident's details with today's plan, the current part highlighted. UI shell only: the HUD
## puts it in a dialog (Close; B on a controller) and fills it from hud.inspect_provider, which the lead connects
## to ThousandSim. Nothing here knows the simulation.
##
## Data (the provider's answer for a building id):
##   {"id", "name" (English; translated here), "open": bool, "count": int (here now),
##    "counts": {state id: n}, "here": [resident], "lives": [resident]}
## A resident: {"id", "name" (already in the reader's language), "role" (a ROLES id), "age": int,
##   "state" (a STATES id), "where" (English place name), "plan": [{"from": minute, "to": minute, "state",
##   "where", "now": bool}]}
extends VBoxContainer

const UI := preload("res://scripts/ui/ui_kit.gd")

## The 20 roles of upstream's roster (ids for the provider; English names for the catalogs).
## TODO(lead): map upstream's role keys (core/thousand_sim.gd) onto these ids.
const ROLES := {
	"preschooler": "Preschooler", "primary_student": "Primary student", "middle_student": "Middle-school student",
	"university_student": "University student", "office_worker": "Office worker", "worker": "Worker",
	"shopkeeper": "Shopkeeper", "driver": "Driver", "teacher": "Teacher", "school_staff": "School staff",
	"doctor": "Doctor", "nurse": "Nurse", "hospital_staff": "Hospital staff", "police": "Police officer",
	"clerk": "Clerk", "sanitation": "Sanitation worker", "job_seeker": "Job seeker", "patient": "Patient",
	"retiree": "Retiree", "senior": "Senior",
}
## The 8 states a resident can be in.
const STATES := {
	"home": "At home", "commuting": "Commuting", "work": "At work", "out": "Out and about",
	"doctor": "At the doctor", "shopping": "Shopping", "eating": "Eating out", "asleep": "Asleep",
}

signal resident_picked(id: String)

var data: Dictionary = {}
var tab := "here"
var picked := ""
var _status: Label
var _counts: Label
var _tab_btns := {}
var _list: VBoxContainer
var _scroll: ScrollContainer
var _detail: VBoxContainer


func _init() -> void:
	name = "ThousandInspect"
	add_theme_constant_override("separation", 12)
	_status = UI.label("", 22, UI.ACCENT, true)
	_status.name = "Status"
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_status)
	_counts = UI.label("", 18, UI.MUTED, true)
	_counts.name = "Counts"
	_counts.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_counts)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 10)
	add_child(tabs)
	for spec in [["here", "Here now"], ["lives", "Lives here"]]:
		var b := UI.button(spec[1], "", false, 180)
		b.name = "Tab_" + spec[0]
		var key: String = spec[0]
		b.pressed.connect(func(): show_tab(key))
		tabs.add_child(b)
		_tab_btns[key] = b
	_scroll = ScrollContainer.new()
	_scroll.name = "ListScroll"
	_scroll.custom_minimum_size = Vector2(520, 220)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_detail = VBoxContainer.new()
	_detail.name = "Detail"
	_detail.add_theme_constant_override("separation", 4)
	add_child(_detail)


## Shows a provider's answer (see the header), on the "Here now" tab.
func set_data(d: Dictionary) -> void:
	data = d
	var open := bool(d.get("open", true))
	_status.text = "%s · %s" % [tr("Open") if open else tr("Closed"), tr("%d here now") % int(d.get("count", 0))]
	var parts: Array = []
	var counts: Dictionary = d.get("counts", {})
	for st in STATES:
		if int(counts.get(st, 0)) > 0:
			parts.append("%s %d" % [tr(STATES[st]), int(counts[st])])
	_counts.text = ", ".join(parts)
	_counts.visible = not parts.is_empty()
	show_tab("here")


func show_tab(which: String) -> void:
	tab = which
	for k in _tab_btns:
		(_tab_btns[k] as Button).modulate = Color.WHITE if k == which else Color(1, 1, 1, 0.6)
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	var people: Array = data.get("here" if which == "here" else "lives", [])
	if people.is_empty():
		var none := UI.label("Nobody is here right now." if which == "here" else "Nobody lives here.", 20, UI.MUTED, true)
		none.name = "Empty"
		_list.add_child(none)
	for r: Dictionary in people:
		var b := UI.button("%s · %s" % [str(r.get("name", "")), tr(role_name(str(r.get("role", ""))))], "", false, 0)
		b.name = "Resident_" + str(r.get("id", ""))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 56
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rid := str(r.get("id", ""))
		b.pressed.connect(func(): pick(rid))
		_list.add_child(b)
	pick("")


## Shows a resident's details (from the current tab's list); "" clears the detail area.
func pick(id: String) -> void:
	picked = id
	for ch in _detail.get_children():
		_detail.remove_child(ch)
		ch.queue_free()
	if id == "":
		return
	var r := {}
	for list_key in ([tab, "lives" if tab == "here" else "here"]):   # the shown list's entry first
		for p: Dictionary in data.get(list_key, []):
			if r.is_empty() and str(p.get("id", "")) == id:
				r = p
	if r.is_empty():
		return
	var head := UI.label(str(r.get("name", "")), 24, UI.ACCENT, true)
	head.name = "Name"
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_detail.add_child(head)
	var who := UI.label("%s · %s" % [tr(role_name(str(r.get("role", "")))), tr("%d years old") % int(r.get("age", 0))], 18, UI.TEXT, true)
	who.name = "Who"
	who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_detail.add_child(who)
	var now := UI.label("%s · %s" % [tr(state_name(str(r.get("state", "")))), tr(str(r.get("where", "")))], 18, UI.TEXT, true)
	now.name = "Now"
	now.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_detail.add_child(now)
	var plan: Array = r.get("plan", [])
	if not plan.is_empty():
		_detail.add_child(UI.label("Today's plan", 18, UI.MUTED))
		for i in plan.size():
			var part: Dictionary = plan[i]
			var line := "%s-%s  %s · %s" % [_hhmm(float(part.get("from", 0))), _hhmm(float(part.get("to", 0))),
				tr(state_name(str(part.get("state", "")))), tr(str(part.get("where", "")))]
			var l := UI.label(line, 17, UI.ACCENT if bool(part.get("now", false)) else UI.MUTED, true)
			l.name = "Plan%d" % i
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			if bool(part.get("now", false)):
				l.set_meta("now", true)
			_detail.add_child(l)
	resident_picked.emit(id)


static func role_name(id: String) -> String:
	return str(ROLES.get(id, id))


static func state_name(id: String) -> String:
	return str(STATES.get(id, id))


static func _hhmm(minute: float) -> String:
	var m := int(floor(fposmod(minute, 1440.0)))
	return "%02d:%02d" % [m / 60, m % 60]
