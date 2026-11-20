## The world worker's extra tables for the Three.js city (tests/web_city/export.gd puts them in
## consts.json as extra.world). Everything is read from the Godot objects the city really builds, never
## retyped, so the page cannot drift from the Godot city:
##   town_light   town_world.gd's sun (rotation, Euler order) and the colour adjustment _city_light sets
##   rain         city_world.gd _build_rain's emitter (GPUParticles3D + ParticleProcessMaterial + streak)
##   shading      per material role: diffuse mode (the mesh pack does not carry it) and specular
## Called at run time (after the autoloads exist), so town_world.gd is loaded, not preloaded.
extends RefCounted

const CityWorld := preload("res://scripts/world/city_world.gd")


static func extra() -> Dictionary:
	return {"town_light": town_light(), "rain": rain(), "shading": shading()}


## TownWorld's environment as the city sets it (_build_environment, then _city_light).
static func town_light() -> Dictionary:
	var ts := load("res://scripts/world/town_world.gd") as GDScript
	var tw: Node3D = ts.new()
	tw.call("_build_environment")
	tw.call("_city_light", {"sunny": 1.0})
	var env: Environment = tw.get("_env")
	var sun: DirectionalLight3D = tw.get("_sun")
	var out := {
		"contrast": env.adjustment_contrast,
		"brightness": env.adjustment_brightness,
		"adjustment": env.adjustment_enabled,
		"fog": env.fog_enabled,
		"tonemap": env.tonemap_mode,
		"tonemap_exposure": env.tonemap_exposure,
		"ambient_source": env.ambient_light_source,
		"background_mode": env.background_mode,
		"sun_rotation_degrees": sun.rotation_degrees,
		"sun_rotation_order": sun.rotation_order,
		"sun_shadow": sun.shadow_enabled,
	}
	tw.free()
	return out


## The rain's emitter, read from the particles node city_world builds.
static func rain() -> Dictionary:
	var cw = CityWorld.new()
	cw.call("_make_materials")
	var holder := Node3D.new()
	cw.call("_build_rain", holder)
	var gp := holder.get_node("Rain") as GPUParticles3D
	var pm := gp.process_material as ParticleProcessMaterial
	var streak := gp.draw_pass_1 as BoxMesh
	var mat := streak.material as StandardMaterial3D
	var out := {
		"amount": gp.amount,
		"lifetime": gp.lifetime,
		"local_coords": gp.local_coords,
		"explosiveness": gp.explosiveness,
		"randomness": gp.randomness,
		"box": pm.emission_box_extents,
		"box_y": pm.emission_box_extents.y,
		"direction": pm.direction,
		"spread": pm.spread,
		"velocity_min": pm.initial_velocity_min,
		"velocity_max": pm.initial_velocity_max,
		"gravity": pm.gravity,
		"align_y": pm.particle_flag_align_y,
		"size": streak.size,
		"color": Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 1.0),
		"unshaded": mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
	}
	holder.free()
	cw.free()
	return out


## Per material role: Godot's diffuse mode (BaseMaterial3D.DiffuseMode: 0 burley, 1 lambert, 2 lambert wrap,
## 3 toon) and specular, which the page's shading needs and the mesh pack does not carry.
static func shading() -> Dictionary:
	var cw = CityWorld.new()
	cw.call("_make_materials")
	var mats := {"base": load("res://scripts/art/props_city.gd").material(), "glow": cw.get("_glow_mat"), "cabin": cw.get("_cabin_mat"),
		"ground": cw.get("_ground_mat"), "puddle": cw.get("_puddle_mat"), "pool": cw.get("_pool_mat"), "rain": cw.get("_rain_mat")}
	var out := {}
	for role: String in mats:
		var m := mats[role] as StandardMaterial3D
		out[role] = {"diffuse_mode": m.diffuse_mode, "specular_mode": m.specular_mode, "specular": m.metallic_specular,
			"unshaded": m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED}
	cw.free()
	return out
