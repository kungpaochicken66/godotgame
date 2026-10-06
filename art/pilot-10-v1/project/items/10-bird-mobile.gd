## 10 bird mobile: original. CEILING anchor: origin = attachment point (y = 0), the
## mobile hangs into -y. Mount puck, drop rod, three-arm crossbar with hub, thin cream
## strings, three rounded birds (egg body, head, beak, eyes, wing). Birds are enlarged
## for readability. Not placeable in the game yet (contract v1 is ground-only).
const MANIFEST := {
	"asset_id": "10-bird-mobile", "target_name": "Bird mobile", "anchor": "ceiling",
	"size_class": "medium", "tabletop_eligible": false,
	"footprint": {"shape": "ceiling_circle", "diameter": 0.9, "collision_radius_recommendation": 0.0},
	"ceiling_mount": {"room_ceiling_height": 2.8, "hangs_below_m": 0.78},
	"integration_status": "recorded_not_placeable (contract v1 is ground-only)",
	"interaction": {},
	"notes": "strings are 0.004-radius rods: visually thin by design, not structural",
}

static func _bird(G, b, body: String, wing: String, pos: Vector3, yaw: float) -> void:
	var r := Basis(Vector3.UP, yaw)
	var t := func(p: Vector3) -> Vector3:
		return pos + r * p
	G.egg(b, body, 0.07, 0.1, 0.065, 0.15, 0.0, Transform3D(r * Basis(Vector3.BACK, -PI / 2), t.call(Vector3(-0.1, 0, 0))), 8, 12)
	b.add_mesh(body, G.sphere(0.058, 6), Transform3D(r, t.call(Vector3(0.085, 0.055, 0))))
	G.rod(b, "butter", 0.02, 0.004, 0.05, Transform3D(r * Basis(Vector3.BACK, -PI / 2), t.call(Vector3(0.13, 0.05, 0))), 8, 0.5)
	for s in [-1.0, 1.0]:
		b.add_mesh("ink", G.sphere(0.01, 4), Transform3D(r, t.call(Vector3(0.115, 0.075, s * 0.042))))
		var wb: Basis = r * Basis(Vector3.BACK, PI / 2 + 0.3) * Basis(Vector3.UP, s * 0.25)
		G.egg(b, wing, 0.05, 0.055, 0.016, 0.1, 0.0, Transform3D(wb, t.call(Vector3(0.03, 0.02, s * 0.058))), 6, 10)

static func build(G) -> Object:
	var b = G.Builder.new()
	G.puck(b, "wood", 0.08, 0.035, 0.015, Transform3D(Basis(), Vector3(0, -0.035, 0)), 20)
	G.rod_between(b, "wood", Vector3(0, -0.02, 0), Vector3(0, -0.25, 0), 0.018, 10)
	var hub := Vector3(0, -0.25, 0)
	b.add_mesh("wood", G.sphere(0.04, 6), Transform3D(Basis(), hub))
	var birds := [["sage", "cream", 0.27], ["cream", "sage", 0.4], ["butter", "rose", 0.33]]
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		var end := hub + Vector3(cos(a), 0, sin(a)) * 0.36
		G.rod_between(b, "wood", hub, end, 0.016, 10)
		b.add_mesh("wood", G.sphere(0.026, 5), Transform3D(Basis(), end))
		var drop: float = birds[k][2]
		var bird_pos := end + Vector3(0, -drop - 0.06, 0)
		G.rod_between(b, "cream", end, bird_pos + Vector3(0, 0.06, 0), 0.004, 6)
		_bird(G, b, birds[k][0], birds[k][1], bird_pos, -a + PI / 2)
	return b
