## Egg-shell lounge chair on a swivel base: dark shell with a soft cushion bulging from the front opening.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	G.puck(b, "steel", 0.26, 0.04, 0.015, Transform3D(Basis(), Vector3.ZERO), 28)
	G.rod(b, "steel", 0.04, 0.04, 0.2, Transform3D(Basis(), Vector3(0, 0.03, 0)), 10)
	G.pillow(b, p.get("shell", "charcoal"), Vector3(0.62, 0.86, 0.62), 0.75, 0.9, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8)), Vector3(0, 0.62, -0.03)), 12, 24)
	G.pillow(b, p.get("cushion", "red"), Vector3(0.48, 0.66, 0.2), 0.5, 0.6, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12)), Vector3(0, 0.66, 0.2)), 10, 20)
	G.pillow(b, p.get("cushion", "red"), Vector3(0.46, 0.12, 0.34), 0.45, 0.45, Transform3D(Basis(), Vector3(0, 0.44, 0.17)), 8, 20)
	b.marker("Seat0", Vector3(0, 0.5, 0.15))
	return b
