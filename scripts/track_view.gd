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
	var hw := Track.HALF_WIDTH
	var kw := Track.KERB_WIDTH
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
		if k > 0.012:
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


func _quad(a: Vector2, b: Vector2, na: Vector2, nb: Vector2, from: float, to: float, col: Color) -> void:
	var poly := PackedVector2Array([a + na * from, b + nb * from, b + nb * to, a + na * to])
	draw_primitive(poly, PackedColorArray([col, col, col, col]), PackedVector2Array())


func _draw_scenery() -> void:
	# Grandstand inside the first straight, with a pixel crowd.
	var gs := Rect2(212, 64, 96, 14)
	draw_rect(gs.grow(1), Pal.BLACK)
	draw_rect(gs, Pal.LIGHT_BLUE)
	var crowd := [Pal.RED, Pal.YELLOW, Pal.WHITE, Pal.CYAN, Pal.PURPLE, Pal.ORANGE]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(66, 77, 3):
		for x in range(214, 306, 2):
			draw_rect(Rect2(x, y, 1, 1), crowd[rng.randi_range(0, crowd.size() - 1)])
	draw_rect(Rect2(210, 60, 100, 4), Pal.BLUE)
	# Pit building near the start.
	draw_rect(Rect2(110, 64, 60, 10), Pal.BLACK)
	draw_rect(Rect2(111, 65, 58, 8), Pal.LIGHT_GREY)
	for x in range(114, 166, 8):
		draw_rect(Rect2(x, 68, 4, 5), Pal.DARK_GREY)
	# Trees.
	for p in [Vector2(80, 110), Vector2(96, 128), Vector2(260, 120), Vector2(280, 140), Vector2(240, 205), Vector2(395, 105), Vector2(140, 236), Vector2(420, 190), Vector2(24, 230), Vector2(460, 30)]:
		_tree(p)


func _tree(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 1, p.y + 3, 2, 3), Pal.BROWN)
	draw_rect(Rect2(p.x - 4, p.y - 2, 8, 5), Color("#2e6b28"))
	draw_rect(Rect2(p.x - 3, p.y - 4, 6, 8), Color("#2e6b28"))
	draw_rect(Rect2(p.x - 2, p.y - 3, 2, 2), Pal.LIGHT_GREEN)
