## Post-import for the Everything Library animals (set for every scene in project.godot).
## Their colour is in COLOR_0. Godot 4.7.2's glTF import keeps those colours linear but leaves
## "vertex colour as albedo" off, so the models would show grey (measured with this pack's self-test).
## This turns it on in the imported scene itself, so a loaded .glb is coloured with no further code:
##   vertex_color_use_as_albedo = true
##   vertex_color_is_srgb = false        (glTF colours are linear and stay linear on import)
##   diffuse_mode = LAMBERT_WRAP         (the game's soft matte look, as Props._modeled sets)
## It changes nothing else: metallic, roughness, textures and culling stay as the file says, so the
## checker still sees the file's own values.
@tool
extends EditorScenePostImport


func _post_import(scene: Node) -> Object:
	var changed := 0
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = false
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			changed += 1
	scene.set_meta("everything_post_import", changed)
	return scene
