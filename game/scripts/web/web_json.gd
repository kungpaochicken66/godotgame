## Godot values as plain JSON for the Three.js city's page (design/city-threejs.md). One convention, used by
## the data export and by the bridge, so the page reads both the same way (js/consts.js):
##   Vector2 -> [x, y]; Vector3 -> [x, y, z]; Vector2i / Vector3i -> the same, as numbers;
##   Rect2 -> {"rect": [x, y, w, h]}; Color -> {"color": [r, g, b, a]} (Godot's stored, sRGB-encoded values);
##   Transform3D -> {"xf": 12 floats (basis x, y, z columns, then origin)}; Basis -> {"basis": 9 floats};
##   Quaternion -> {"quat": [x, y, z, w]}; Dictionary keys -> strings; packed arrays -> arrays;
##   resources, scripts, callables and objects -> null (they are code, not data).
extends RefCounted


static func value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			var f := float(v)
			if is_nan(f) or is_inf(f):
				return null
			return f
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [v.x, v.y, v.z]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return [v.x, v.y, v.z, v.w]
		TYPE_RECT2, TYPE_RECT2I:
			return {"rect": [v.position.x, v.position.y, v.size.x, v.size.y]}
		TYPE_COLOR:
			return {"color": [v.r, v.g, v.b, v.a]}
		TYPE_TRANSFORM3D:
			var t: Transform3D = v
			return {"xf": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]}
		TYPE_BASIS:
			var b: Basis = v
			return {"basis": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]}
		TYPE_QUATERNION:
			return {"quat": [v.x, v.y, v.z, v.w]}
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = value(v[k])
			return out
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
				TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			var arr: Array = []
			for e in v:
				arr.append(value(e))
			return arr
	return null


## Every constant of a script (enums included, as dictionaries), as JSON values; preloaded scripts and
## resources are left out.
static func script_consts(script: Script) -> Dictionary:
	var out := {}
	var m: Dictionary = script.get_script_constant_map()
	for k in m:
		var v = m[k]
		if v is Object:
			continue
		out[str(k)] = value(v)
	return out
