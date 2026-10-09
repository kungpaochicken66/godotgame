## A companion pet: the modeled, rigged actor from batch p001-pets-room (cat,
## dog, bird or butterfly variants) animated through its joint hooks, within the
## ranges in the model handoff (design/pets-rooms-assets.md):
##   cats, dogs: Head (look), Tail (wag about +y +-0.5), LegFL/FR/BL/BR (swing about
##   +x +-0.5, diagonal pairs in phase); birds: WingL/WingR (flap about +z 0..1.2,
##   mirrored), Head, Tail; butterflies: WingL/WingR (about +z -0.4..1.1).
extends Node3D

const Kit := preload("res://scripts/art/mesh_kit.gd")
const PetRules := preload("res://scripts/core/pets.gd")

var family := ""
var model_id := ""
var owner_pid := ""
var pet_id := ""
var pet_name := ""
var speed := 0.0           # set by whoever moves the pet, drives the walk cycle
var model_loaded := false
var _t := 0.0
var _joints := {}          # hook name -> Node3D
var _hearts: CPUParticles3D
var _label: Label3D
var _happy := 0.0


func setup(fam: String, variant: int, name: String) -> void:
	family = fam
	pet_name = name
	var variants: Array = PetRules.FAMILIES[fam]["variants"]
	model_id = variants[clampi(variant, 0, variants.size() - 1)]["model"]
	var scene: PackedScene = load("res://assets/models/%s.glb" % model_id)
	if scene:
		var model := scene.instantiate() as Node3D
		model.name = "Model"
		add_child(model)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var m := mesh.surface_get_material(si) as BaseMaterial3D
				if m:
					m = m.duplicate()
					m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
					(mi as MeshInstance3D).set_surface_override_material(si, m)
		for hook in ["Head", "Tail", "LegFL", "LegFR", "LegBL", "LegBR", "WingL", "WingR"]:
			var j := model.find_child(hook, true, false) as Node3D
			if j:
				_joints[hook] = j
		model_loaded = true
	else:
		push_warning("Pet model missing: %s" % model_id)
		Kit.ball(self, 0.12, Color("#c9b6e4"), Vector3(0, 0.12, 0))
	if not flying():
		Kit.blob_shadow(self, 0.18, 0.2)
	_hearts = CPUParticles3D.new()
	_hearts.emitting = false
	_hearts.one_shot = true
	_hearts.amount = 6
	_hearts.lifetime = 1.0
	_hearts.position.y = 0.45
	_hearts.direction = Vector3.UP
	_hearts.initial_velocity_min = 0.4
	_hearts.initial_velocity_max = 0.8
	_hearts.gravity = Vector3(0, 0.2, 0)
	var hm := SphereMesh.new()
	hm.radius = 0.035
	hm.height = 0.07
	hm.material = Kit.mat(Color("#ec6f8a"))
	_hearts.mesh = hm
	add_child(_hearts)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.003
	_label.font_size = 36
	_label.outline_size = 10
	_label.modulate = Color("#7a5a3a")
	_label.outline_modulate = Color("#fffdf6")
	_label.position.y = 0.55 if not flying() else 0.25
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_label)
	refresh_label()


func joints() -> Array:
	return _joints.keys()


func refresh_label() -> void:
	_label.text = tr(pet_name)
	_label.font = I18n.ui_font()


func show_name(on: bool) -> void:
	_label.visible = on


func flying() -> bool:
	return family in ["bird", "butterfly"]


func happy() -> void:
	_happy = 1.2
	_hearts.restart()
	_hearts.emitting = true


func _rot(hook: String, axis: String, value: float) -> void:
	var j: Node3D = _joints.get(hook)
	if j:
		j.rotation[axis] = value


func _process(delta: float) -> void:
	_t += delta
	_happy = maxf(0.0, _happy - delta)
	var moving := speed > 0.2
	match family:
		"cat", "dog":
			var swing := sin(_t * 11.0) * 0.5 if moving else 0.0
			_rot("LegFL", "x", swing)
			_rot("LegBR", "x", swing)
			_rot("LegFR", "x", -swing)
			_rot("LegBL", "x", -swing)
			var wag_hz := 4.0 if _happy > 0.0 or family == "dog" else 1.2
			_rot("Tail", "y", sin(_t * TAU * wag_hz * 0.5) * (0.5 if _happy > 0.0 else 0.3))
			_rot("Head", "y", sin(_t * 0.7) * 0.25)
			_rot("Head", "x", (0.3 if _happy > 0.0 else 0.0) * sin(_t * 9.0) - 0.05)
		"bird":
			var flap := (0.6 + 0.6 * sin(_t * 24.0)) if moving else (0.1 + 0.1 * sin(_t * 3.0))
			_rot("WingL", "z", flap)
			_rot("WingR", "z", -flap)
			_rot("Head", "y", sin(_t * 1.3) * 0.4)
			_rot("Tail", "x", sin(_t * 2.0) * 0.1)
		"butterfly":
			var f := 0.35 + 0.75 * sin(_t * (16.0 if moving else 9.0))
			_rot("WingL", "z", f)
			_rot("WingR", "z", -f)
