## Thousand Town's map (design/thousand-town.md, sections 1-3): the one source of layout data.
##
## Pure data, no nodes. Everything comes from res://thousand_town/data/town.json, which
## scripts/thousand_town/extract.mjs writes from upstream's own planners ("Qianren Xiaozhen (Thousand Town)" by
## Yihuishi / YiHuiShiBY, CC BY 4.0) with the construction frozen at its end state. The file is loaded once and
## cached. 1 unit = 1 m (upstream x 0.5); +x east, +z south, y up, the same axes as upstream and city_map.gd.
## A Vector2 here is (x, z) on the ground. A Rect2 is (x, z) position and (w, d) size.
##
## The GLBs beside town.json are plain files (importer="keep"); load them at run time with glb_scene() or
## glb_state(), never with load().
extends RefCounted

const DATA_DIR := "res://thousand_town/data/"
const DATA_PATH := DATA_DIR + "town.json"
const SCALE := 0.5                       # metres per upstream unit

## The board: x +-95 m, z +-129 m.
const HALF := Vector2(95.0, 129.0)
const BOARD := Rect2(-95.0, -129.0, 190.0, 258.0)

## Section 1 sizes. Doors are the one architectural size Lantern Lane changes (upstream 1.8 m).
const STOREY := 3.0
const PLINTH := 0.7
const DOOR_HEIGHT := 2.1
const PAVEMENT_Y := 0.125
const CROSS_STREET_WIDTH := 6.0
const AVENUE_WIDTH := 5.0
const CANAL_HALF := 7.5

## The station (upstream lot 12, cell A4) and the arrival on its forecourt: the forecourt's south-east
## corner, facing east along the z = 0 pedestrian street toward the canal (design section 3). The arrival's
## -Z axis (Godot's forward) points to +x. town.json carries the same numbers (places.station.arrival).
const STATION := Vector2(-66.0, 20.0)
const ARRIVAL_POS := Vector3(-52.0, 0.125, 3.6)
const ARRIVAL_FACING := Vector2(1.0, 0.0)
const ARRIVAL := Transform3D(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0), ARRIVAL_POS)

static var _data: Dictionary = {}
static var _buildings: Array = []
static var _by_id: Dictionary = {}


## The parsed town.json (cached). Empty if the file is missing or broken.
static func data() -> Dictionary:
	if _data.is_empty():
		if not FileAccess.file_exists(DATA_PATH):
			push_error("thousand_map: missing " + DATA_PATH)
			return _data
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(DATA_PATH)) != OK or not j.data is Dictionary:
			push_error("thousand_map: cannot parse " + DATA_PATH)
			return _data
		_data = j.data
	return _data


static func rect_of(d: Dictionary) -> Rect2:
	return Rect2(float(d.x) - float(d.w) * 0.5, float(d.z) - float(d.d) * 0.5, float(d.w), float(d.d))


static func v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _door(d: Dictionary) -> Dictionary:
	return {"pos": Vector2(float(d.x), float(d.z)), "facing": v2(d.facing), "kind": d.kind,
		"width": 0.0 if d.width == null else float(d.width), "source": d.source}


## The 18 buildings: id, kind ("tower", "housing", "facility"), programme, name_en, cell, lot,
## center, rect (the solid footprint), record (upstream's envelope), floors, storey, height, roof, palette,
## frontage ("shops", "wall" or null), doors (where people come and go from the street) and facade_doors
## (the building's own door leaves, inside its compound where it has one). A door is {pos, facing, kind,
## width, source}; pos stands 0.5 m outside its wall or opening, facing points away from the building.
static func buildings() -> Array:
	if _buildings.is_empty() and not data().is_empty():
		for b in data().buildings:
			var out := {
				"id": b.id, "kind": b.kind, "programme": b.programme, "name_en": b.name_en, "cell": b.cell,
				"lot": int(b.lot), "center": Vector2(float(b.x), float(b.z)), "rect": rect_of(b.rect),
				"record": rect_of(b), "floors": int(b.floors), "storey": float(b.storey), "height": float(b.height),
				"roof": b.roof, "palette": b.palette, "frontage": b.frontage,
				"doors": b.doors.map(func(d): return _door(d)), "facade_doors": b.facade_doors.map(func(d): return _door(d)),
			}
			if b.has("volumes"):
				out["volumes"] = b.volumes.map(func(v): return {"rect": rect_of(v), "floors": int(v.floors)})
			if b.has("modules"):
				out["modules"] = b.modules
			_buildings.append(out)
			_by_id[b.id] = out
	return _buildings


static func building(id: String) -> Dictionary:
	buildings()
	return _by_id.get(id, {})


## The building's main door: {pos: Vector2, facing: Vector2}. Empty for an unknown id.
static func door(id: String) -> Dictionary:
	var b := building(id)
	if b.is_empty() or b.doors.is_empty():
		return {}
	return {"pos": b.doors[0].pos, "facing": b.doors[0].facing}


## The six shared functions on other lots (clinics, police post, waste station, bank podium).
static func annexes() -> Array:
	return data().get("annexes", []).map(func(a): return {
		"id": a.id, "facility": a.facility, "host": a.host, "name_en": a.name_en, "rect": rect_of(a),
		"footprint": rect_of(a.footprint), "floors": int(a.floors), "height": float(a.height),
		"doors": a.doors.map(func(d): return _door(d)), "facade_doors": a.facade_doors.map(func(d): return _door(d))})


## Bus stops: {id, pos, rect, facing (toward the road), shelter}.
static func stops() -> Array:
	return data().transit.bus_stops.map(func(s): return {
		"id": s.id, "pos": Vector2(float(s.x), float(s.z)), "rect": rect_of(s), "facing": v2(s.facing),
		"shelter": bool(s.shelter)})


static func taxi_rank() -> Dictionary:
	var t: Dictionary = data().transit.taxi_rank
	return {"id": t.id, "pos": Vector2(float(t.x), float(t.z)), "rect": rect_of(t), "facing": v2(t.facing)}


## The station: pos, rect, forecourt, platform, vehicle gates and the arrival {pos: Vector3, facing}.
static func station() -> Dictionary:
	var s: Dictionary = data().places.station
	return {"pos": Vector2(float(s.x), float(s.z)), "rect": rect_of(s), "forecourt": rect_of(s.forecourt),
		"platform": rect_of(s.platform), "canopy": rect_of(s.canopy), "taxi_platform": rect_of(s.taxi_platform),
		"gates": s.gates.map(func(d): return _door(d)),
		"arrival": {"pos": Vector3(float(s.arrival.x), float(s.arrival.y), float(s.arrival.z)), "facing": v2(s.arrival.facing)}}


static func arrival() -> Transform3D:
	return ARRIVAL


## The canal's water: |x| < 7.5 the whole length of the board.
static func canal() -> Rect2:
	return rect_of(data().canal)


## Road bridges (z = +-40 m) and footbridges (z = +-20 m): {id, kind, rect}.
static func bridges() -> Array:
	return data().bridges.map(func(b): return {"id": b.id, "kind": b.kind, "rect": rect_of(b)})


## Roads: {id, role ("cross_street", "avenue", "ring_road", "expressway_stub"), axis, rect, walk_only_to}.
## A cross street with walk_only_to is pedestrian where |x| <= walk_only_to.
static func roads() -> Array:
	return data().roads.map(func(r): return {"id": r.id, "role": r.role, "axis": r.axis, "rect": rect_of(r),
		"walk_only_to": float(r.get("walk_only_to", 0.0)), "through": bool(r.through)})


## Junction zebras: Array of Rect2.
static func zebras() -> Array:
	var out := []
	for c in data().crossings:
		for z in c.zebras:
			out.append(rect_of(z))
	return out


## Places: station, amusement, plaza, the parks and the sports ground: {id, kind, name_en, rect}.
static func places() -> Array:
	var p: Dictionary = data().places
	var out := []
	for key in ["station", "amusement", "plaza"]:
		out.append({"id": key, "kind": key, "name_en": p[key].name_en, "rect": rect_of(p[key])})
	for park in p.parks:
		out.append({"id": park.id, "kind": "sports" if park.use == "sports" else "park", "name_en": "", "rect": rect_of(park)})
	return out


## Vehicle loops as polylines (PackedVector2Array): "station" (3 buses, 4 taxis, each with id and kind),
## "traffic" (the four street-traffic loops) and "rider" (the bicycle loop).
static func loops() -> Dictionary:
	var t: Dictionary = data().transit
	var pts := func(list) -> PackedVector2Array:
		var a := PackedVector2Array()
		for p in list:
			a.append(Vector2(float(p[0]), float(p[1])))
		return a
	return {
		"station": t.station_loop.vehicles.map(func(v): return {"id": v.id, "kind": v.kind, "points": pts.call(v.points),
			"departure": float(v.departure), "length": float(v.length)}),
		"traffic": t.street_loops.map(func(l): return {"id": l.id, "points": pts.call(l.points), "length": float(l.length)}),
		"rider": {"points": pts.call(t.rider_loop.points), "length": float(t.rider_loop.length)},
	}


static func trees() -> Array:
	return data().trees


static func lots() -> Array:
	return data().lots


## res:// path of one of the GLBs listed in town.json "meshes" (district, housing, amusement, civic,
## hospital_room, landscape).
static func glb_path(key: String) -> String:
	return DATA_DIR + String(data().meshes[key].file)


## Parse one GLB at run time. Returns null on failure.
static func glb_state(key: String) -> GLTFState:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(glb_path(key), state) != OK:
		return null
	return state


static func glb_scene(key: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(glb_path(key), state) != OK:
		return null
	return doc.generate_scene(state)
