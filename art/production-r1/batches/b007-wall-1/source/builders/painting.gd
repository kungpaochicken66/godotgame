## Framed wall painting: rounded frame (one outline slab), canvas, and an ORIGINAL abstract
## composition of soft shapes (p.shapes: [[x, y, r, material], ...] in canvas units -0.5..0.5).
## Famous source artworks are not reproduced. WALL anchor: back plane z = 0.
static func build(G, p: Dictionary) -> Object:
	var b = G.Builder.new()
	var w: float = p.get("w", 0.5)
	var h: float = p.get("h", 0.6)
	var fr: String = p.get("frame", "gold")
	var bw: float = p.get("border", 0.06)
	G.bevel_slab(b, fr, G.rounded_rect(w, h, 0.03, 3), 0.05, 0.016, Transform3D(Basis(), Vector3(0, 0, 0.025)))
	var cw := w - 2.0 * bw
	var ch := h - 2.0 * bw
	G.bevel_slab(b, p.get("canvas", "paper"), G.rounded_rect(cw, ch, 0.01, 2), 0.02, 0.004, Transform3D(Basis(), Vector3(0, 0, 0.052)))
	for s in p.get("shapes", []):
		var r: float = s[2] * minf(cw, ch)
		var outline: PackedVector2Array = G.blob_outline([[0.0, 0.0, r], [r * 0.6, r * 0.2, r * 0.7]], 30.0 / r, 24) if s.size() < 5 else G.rounded_rect(s[4][0] * cw, s[4][1] * ch, minf(s[4][0] * cw, s[4][1] * ch) * 0.3, 2)
		G.bevel_slab(b, s[3], outline, 0.008, 0.003, Transform3D(Basis(), Vector3(s[0] * cw, s[1] * ch, 0.063)))
	return b
