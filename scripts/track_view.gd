class_name TrackView
extends Node2D
## Draws the static circuit: grass, kerbs, asphalt, start line and scenery.

var track: Track


func _init(p_track: Track = null) -> void:
	track = p_track


func _ready() -> void:
	if track == null:
		track = Track.new()
	queue_redraw()


func _draw() -> void:
	var n := track.n
	var hw := track.half_width
	var kw := Track.KERB_WIDTH
	if track.style == "city":
		_draw_city()
		return
	# Grass with mown stripes and tufts.
	draw_rect(Rect2(0, 0, 480, 270), Pal.GRASS)
	for x in range(0, 480, 32):
		draw_rect(Rect2(x, 0, 16, 270), Pal.GRASS_DARK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	for i in range(260):
		var p := Vector2(rng.randi_range(0, 479), rng.randi_range(12, 269))
		draw_rect(Rect2(p, Vector2(1, 1)), Pal.LIGHT_GREEN)
	# Run-off shadow around the road.
	for i in range(n):
		var j := (i + 1) % n
		_quad(track.pts[i], track.pts[j], track.normals[i], track.normals[j], -hw - kw - 2.0, hw + kw + 2.0, Color("#3d7a35"))
	# Kerbs: red/white stripes in the corners, white edge line elsewhere.
	for i in range(n):
		var j := (i + 1) % n
		var k := absf(track.curv[i])
		var col := Pal.WHITE
		if k > track.kerb_curv:
			col = Pal.KERB_RED if (i / 2) % 2 == 0 else Pal.WHITE
		else:
			col = Pal.LIGHT_GREY
		_quad(track.pts[i], track.pts[j], track.normals[i], track.normals[j], -hw - kw, hw + kw, col)
	# Asphalt.
	for i in range(n):
		var j := (i + 1) % n
		_quad(track.pts[i], track.pts[j], track.normals[i], track.normals[j], -hw, hw, Pal.ASPHALT)
	# Subtle asphalt texture.
	rng.seed = 64
	for i in range(0, n, 2):
		var off := rng.randf_range(-hw + 2.0, hw - 2.0)
		var p := track.pts[i] + track.normals[i] * off
		draw_rect(Rect2(p.floor(), Vector2(1, 1)), Color("#5a5a5a"))
	# Grid boxes.
	for g in range(RaceSim.CAR_COUNT):
		var slot := track.grid_slot(g)
		var pos: Vector2 = slot[0]
		var t := Vector2.from_angle(slot[1])
		var nr := Vector2(-t.y, t.x)
		var front := pos + t * 7.0
		draw_line((front - nr * 5.0).floor(), (front + nr * 5.0).floor(), Pal.WHITE, 1.0)
	# Chequered start/finish line at s = 0.
	var p0 := track.pts[0]
	var t0 := track.tangents[0]
	var n0 := track.normals[0]
	var cells := int(hw * 2.0 / 2.0)
	for row in range(2):
		for c in range(cells):
			var col := Pal.WHITE if (c + row) % 2 == 0 else Pal.BLACK
			var base := p0 + n0 * (-hw + c * 2.0) + t0 * (row * 2.0 - 2.0)
			draw_primitive(PackedVector2Array([base, base + n0 * 2.0, base + n0 * 2.0 + t0 * 2.0, base + t0 * 2.0]), PackedColorArray([col, col, col, col]), PackedVector2Array())
	_draw_scenery()
	# Concrete barrier walls in the infield.
	for w in track.walls:
		draw_polyline(w, Pal.BLACK, 4.0)
		for k in range(w.size() - 1):
			draw_line(w[k], w[k + 1], Pal.WHITE if (k / 3) % 2 == 0 else Pal.LIGHT_GREY, 2.0)


## Street circuit: pavement, city blocks with buildings and parks, concrete
## barriers along the streets and tyre walls in the corners.
func _draw_city() -> void:
	var n := track.n
	var hw := track.half_width
	# Pavement.
	draw_rect(Rect2(0, 0, 480, 270), Color("#8c8c8c"))
	for y in range(0, 270, 8):
		draw_rect(Rect2(0, y, 480, 1), Color("#828282"))
	# Harbour (top right) with a quay and moored boats.
	var harbour := Rect2(312, 12, 168, 44)
	draw_rect(harbour, Color("#3a5fb0"))
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 99
	for k in range(90):
		var wp := harbour.position + Vector2(wrng.randi_range(0, int(harbour.size.x) - 3), wrng.randi_range(0, int(harbour.size.y) - 2))
		draw_rect(Rect2(wp, Vector2(3, 1)), Color("#5f86d6"))
	draw_rect(Rect2(harbour.position.x, harbour.end.y, harbour.size.x, 3), Pal.LIGHT_GREY)
	for bx in [340, 366, 392, 418, 444]:
		draw_rect(Rect2(bx, 36, 7, 14), Pal.WHITE)
		draw_rect(Rect2(bx + 1, 41, 5, 5), Pal.CYAN)
		draw_rect(Rect2(bx + 3, 50, 1, 6), Pal.LIGHT_GREY)
	# City blocks: buildings and small parks, kept clear of the circuit.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var roofs := [Pal.BROWN, Pal.LIGHT_RED, Pal.ORANGE, Pal.PURPLE, Pal.BLUE, Pal.LIGHT_BLUE, Color("#5a5a5a"), Pal.RED]
	var clear := hw + Track.KERB_WIDTH + 6.0
	for gy in range(14, 266, 22):
		for gx in range(4, 476, 26):
			var r := Rect2(gx, gy, 22, 18)
			var ok := not r.intersects(harbour.grow(2))
			for p in [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y), r.get_center()]:
				if absf(track.locate(p).y) < clear:
					ok = false
					break
			if not ok:
				continue
			if rng.randf() < 0.18:
				# Park with trees.
				draw_rect(r, Pal.GREEN)
				draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), Pal.GRASS_DARK)
				_tree(r.position + Vector2(7, 7))
				_tree(r.position + Vector2(15, 11))
				continue
			var roof: Color = roofs[rng.randi_range(0, roofs.size() - 1)]
			draw_rect(r, Pal.BLACK)
			draw_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)), roof)
			draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 2)), roof.lightened(0.3))
			# Rooftop details: AC units / skylights.
			for k in range(rng.randi_range(1, 3)):
				var p := r.position + Vector2(rng.randi_range(3, 15), rng.randi_range(5, 12))
				draw_rect(Rect2(p, Vector2(3, 2)), roof.darkened(0.4))
	# Barrier band (concrete, red/white tyre walls in the corners), then asphalt.
	for i in range(n):
		var j := (i + 1) % n
		var col := Pal.LIGHT_GREY
		if absf(track.curv[i]) > track.kerb_curv:
			col = Pal.KERB_RED if (i / 2) % 2 == 0 else Pal.WHITE
		_quad(track.pts[i], track.pts[j], track.normals[i], track.normals[j], -hw - 3.0, hw + 3.0, Pal.BLACK)
		_quad(track.pts[i], track.pts[j], track.normals[i], track.normals[j], -hw - 2.0, hw + 2.0, col)
	for i in range(n):
		var j := (i + 1) % n
		_quad(track.pts[i], track.pts[j], track.normals[i], track.normals[j], -hw, hw, Color("#444444"))
	# Dashed lane line on the straights.
	for i in range(0, n, 4):
		if absf(track.curv[i]) < 0.005 and absf(track.curv[(i + 2) % n]) < 0.005:
			draw_line(track.pts[i], track.pts[(i + 1) % n], Pal.YELLOW.darkened(0.2), 1.0)
	# Start/finish line.
	var p0 := track.pts[0]
	var t0 := track.tangents[0]
	var n0 := track.normals[0]
	for row in range(2):
		for c in range(int(hw)):
			var col := Pal.WHITE if (c + row) % 2 == 0 else Pal.BLACK
			var base := p0 + n0 * (-hw + c * 2.0) + t0 * (row * 2.0 - 2.0)
			draw_primitive(PackedVector2Array([base, base + n0 * 2.0, base + n0 * 2.0 + t0 * 2.0, base + t0 * 2.0]), PackedColorArray([col, col, col, col]), PackedVector2Array())
	# Grid boxes.
	for g in range(RaceSim.CAR_COUNT):
		var slot := track.grid_slot(g)
		var pos: Vector2 = slot[0]
		var t := Vector2.from_angle(slot[1])
		var nr := Vector2(-t.y, t.x)
		var front := pos + t * 7.0
		draw_line((front - nr * 5.0).floor(), (front + nr * 5.0).floor(), Pal.WHITE, 1.0)


func _quad(a: Vector2, b: Vector2, na: Vector2, nb: Vector2, from: float, to: float, col: Color) -> void:
	var poly := PackedVector2Array([a + na * from, b + nb * from, b + nb * to, a + na * to])
	draw_primitive(poly, PackedColorArray([col, col, col, col]), PackedVector2Array())


func _draw_scenery() -> void:
	# Lake with ripples and a couple of ducks.
	var lake: Rect2 = track.scenery.get("lake", Rect2())
	if lake.size.x > 0.0:
		var c := lake.get_center()
		var shore := PackedVector2Array()
		var water := PackedVector2Array()
		for k in range(40):
			var a := TAU * k / 40.0
			shore.append(c + Vector2(cos(a) * (lake.size.x / 2.0 + 3.0), sin(a) * (lake.size.y / 2.0 + 3.0)))
			water.append(c + Vector2(cos(a) * lake.size.x / 2.0, sin(a) * lake.size.y / 2.0))
		draw_colored_polygon(shore, Pal.SAND)
		draw_colored_polygon(water, Color("#3a5fb0"))
		var lr := RandomNumberGenerator.new()
		lr.seed = 5
		for k in range(40):
			var a := lr.randf() * TAU
			var r := sqrt(lr.randf()) * 0.8
			var p := c + Vector2(cos(a) * lake.size.x / 2.0 * r, sin(a) * lake.size.y / 2.0 * r)
			draw_rect(Rect2(p.floor(), Vector2(3, 1)), Color("#5f86d6"))
		for d in [c + Vector2(-30, -8), c + Vector2(24, 10)]:
			draw_rect(Rect2(d, Vector2(4, 3)), Pal.WHITE)
			draw_rect(Rect2(d + Vector2(3, -2), Vector2(2, 2)), Pal.WHITE)
			draw_rect(Rect2(d + Vector2(5, -1), Vector2(1, 1)), Pal.ORANGE)
	# Grandstand with a pixel crowd.
	var gs: Rect2 = track.scenery.get("stand", Rect2())
	if gs.size.x > 0.0:
		draw_rect(gs.grow(1), Pal.BLACK)
		draw_rect(gs, Pal.LIGHT_BLUE)
		var crowd := [Pal.RED, Pal.YELLOW, Pal.WHITE, Pal.CYAN, Pal.PURPLE, Pal.ORANGE]
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in range(int(gs.position.y) + 2, int(gs.end.y) - 1, 3):
			for x in range(int(gs.position.x) + 2, int(gs.end.x) - 2, 2):
				draw_rect(Rect2(x, y, 1, 1), crowd[rng.randi_range(0, crowd.size() - 1)])
		draw_rect(Rect2(gs.position.x - 2, gs.position.y - 4, gs.size.x + 4, 4), Pal.BLUE)
	# Pit building.
	var pit: Rect2 = track.scenery.get("pit", Rect2())
	if pit.size.x > 0.0:
		draw_rect(pit, Pal.BLACK)
		draw_rect(pit.grow(-1), Pal.LIGHT_GREY)
		for x in range(int(pit.position.x) + 4, int(pit.end.x) - 4, 8):
			draw_rect(Rect2(x, pit.position.y + 4, 4, pit.size.y - 5), Pal.DARK_GREY)
	for p in track.scenery.get("trees", []):
		_tree(p)


func _tree(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 1, p.y + 3, 2, 3), Pal.BROWN)
	draw_rect(Rect2(p.x - 4, p.y - 2, 8, 5), Color("#2e6b28"))
	draw_rect(Rect2(p.x - 3, p.y - 4, 6, 8), Color("#2e6b28"))
	draw_rect(Rect2(p.x - 2, p.y - 3, 2, 2), Pal.LIGHT_GREEN)
