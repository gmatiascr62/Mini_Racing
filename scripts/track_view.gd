class_name TrackView
extends Node2D
## Draws the static circuit: grass, kerbs, asphalt, start line and scenery.

## Scenery drawn around the fenced world, so the rotating race camera never
## shows empty space near the edges.
const OUTSIDE := 420.0

var track: Track


func _init(p_track: Track = null) -> void:
	track = p_track


## The whole circuit scaled down to fill the 480x270 screen (menus).
static func overview(p_track: Track) -> TrackView:
	var v := TrackView.new(p_track)
	v.transform = overview_transform(p_track)
	return v


## Scale and centring that fit the whole world on the 480x270 screen.
static func overview_transform(p_track: Track) -> Transform2D:
	var screen := Vector2(480, 270)
	var k := minf(screen.x / p_track.world.x, screen.y / p_track.world.y)
	return Transform2D(0.0, Vector2(k, k), 0.0, (screen - p_track.world * k) / 2.0)


func _ready() -> void:
	if track == null:
		track = Track.new()
	queue_redraw()


func _draw() -> void:
	var n := track.n
	var hw := track.half_width
	var kw := Track.KERB_WIDTH
	var world := track.world
	# Land outside the fence: car park and fields.
	draw_rect(Rect2(-OUTSIDE, -OUTSIDE, world.x + OUTSIDE * 2.0, world.y + OUTSIDE * 2.0), Color("#3f7f37"))
	for y in range(int(-OUTSIDE) + 20, int(world.y + OUTSIDE), 24):
		draw_rect(Rect2(-OUTSIDE, y, world.x + OUTSIDE * 2.0, 1), Color("#3a7533"))
	# Grass with mown stripes and tufts.
	draw_rect(Rect2(Vector2.ZERO, world), Pal.GRASS)
	for x in range(0, int(world.x), 32):
		draw_rect(Rect2(x, 0, 16, world.y), Pal.GRASS_DARK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	for i in range(1000):
		var p := Vector2(rng.randi_range(0, int(world.x) - 1), rng.randi_range(0, int(world.y) - 1))
		draw_rect(Rect2(p, Vector2(1, 1)), Pal.LIGHT_GREEN)
	_draw_greens()
	_draw_lakes()
	# Run-off shadow around the road.
	for i in range(n):
		var j := (i + 1) % n
		_quad(track.pts[i], track.pts[j], track.normals[i], track.normals[j], -hw - kw - 2.0, hw + kw + 2.0, Color("#3d7a35"))
	# Kerbs: red/white stripes in the corners, white edge line elsewhere.
	for i in range(n):
		var j := (i + 1) % n
		var col := Pal.LIGHT_GREY
		if absf(track.curv[i]) > track.kerb_curv:
			col = track.kerb_colors[0] if (i / 2) % 2 == 0 else track.kerb_colors[1]
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
	# Chequered start/finish line (on a strip of bricks at Indianapolis).
	var p0 := track.pts[0]
	var t0 := track.tangents[0]
	var n0 := track.normals[0]
	if track.id == "indy":
		_quad(p0 - t0 * 3.0, p0 + t0 * 3.0, n0, n0, -hw, hw, Color("#a0522d"))
	var cells := int(hw * 2.0 / 2.0)
	for row in range(2):
		for c in range(cells):
			var col := Pal.WHITE if (c + row) % 2 == 0 else Pal.BLACK
			var base := p0 + n0 * (-hw + c * 2.0) + t0 * (row * 2.0 - 2.0)
			draw_primitive(PackedVector2Array([base, base + n0 * 2.0, base + n0 * 2.0 + t0 * 2.0, base + t0 * 2.0]), PackedColorArray([col, col, col, col]), PackedVector2Array())
	_draw_scenery()
	# Fence around the world.
	draw_rect(Rect2(Vector2(1, 1), world - Vector2(2, 2)), Pal.BLACK, false, 3.0)
	draw_rect(Rect2(Vector2(1, 1), world - Vector2(2, 2)), Pal.LIGHT_GREY, false, 1.0)


## Water with a muddy shore and a few ripples.
func _draw_lakes() -> void:
	for l in track.scenery.get("lakes", []):
		var lake: PackedVector2Array = l
		var c := Vector2.ZERO
		for p in lake:
			c += p
		c /= lake.size()
		var shore := PackedVector2Array()
		for p in lake:
			shore.append(c + (p - c) * 1.08)
		draw_colored_polygon(shore, Pal.SAND.darkened(0.25))
		draw_colored_polygon(lake, Color("#3a5fb0"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for k in range(40):
			var q := c + Vector2(rng.randf_range(-60, 60), rng.randf_range(-26, 26))
			if Geometry2D.is_point_in_polygon(q, lake):
				draw_rect(Rect2(q.floor(), Vector2(4, 1)), Color("#5f86d6"))


## Golf course in the infield.
func _draw_greens() -> void:
	for r in track.scenery.get("greens", []):
		var g: Rect2 = r
		draw_rect(g.grow(2), Color("#4a9140"))
		draw_rect(g, Pal.LIGHT_GREEN.darkened(0.15))
		draw_rect(Rect2(g.position + Vector2(g.size.x * 0.65, g.size.y * 0.55), Vector2(9, 6)), Pal.SAND)
		var hole := g.get_center() - Vector2(g.size.x * 0.15, 0)
		draw_rect(Rect2(hole, Vector2(2, 2)), Pal.BLACK)
		draw_rect(Rect2(hole + Vector2(1, -7), Vector2(1, 7)), Pal.WHITE)
		draw_rect(Rect2(hole + Vector2(2, -7), Vector2(3, 2)), Pal.RED)


func _quad(a: Vector2, b: Vector2, na: Vector2, nb: Vector2, from: float, to: float, col: Color) -> void:
	var poly := PackedVector2Array([a + na * from, b + nb * from, b + nb * to, a + na * to])
	draw_primitive(poly, PackedColorArray([col, col, col, col]), PackedVector2Array())


func _draw_scenery() -> void:
	# Grandstands with a pixel crowd.
	var crowd := [Pal.RED, Pal.YELLOW, Pal.WHITE, Pal.CYAN, Pal.PURPLE, Pal.ORANGE]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for r in track.scenery.get("stands", []):
		var gs: Rect2 = r
		draw_rect(gs.grow(1), Pal.BLACK)
		draw_rect(gs, Pal.LIGHT_BLUE)
		for y in range(int(gs.position.y) + 2, int(gs.end.y) - 1, 3):
			for x in range(int(gs.position.x) + 2, int(gs.end.x) - 2, 2):
				draw_rect(Rect2(x, y, 1, 1), crowd[rng.randi_range(0, crowd.size() - 1)])
	# Pit building with garages and the pagoda (timing tower) at the line.
	var pit: Rect2 = track.scenery.get("pit", Rect2())
	if pit.size.x > 0.0:
		draw_rect(pit, Pal.BLACK)
		draw_rect(pit.grow(-1), Pal.LIGHT_GREY)
		for x in range(int(pit.position.x) + 4, int(pit.end.x) - 4, 8):
			draw_rect(Rect2(x, pit.position.y + 4, 4, pit.size.y - 5), Pal.DARK_GREY)
		var px := clampf(track.pts[0].x, pit.position.x + 9.0, pit.end.x - 9.0)
		var pagoda := Rect2(px - 9, pit.position.y - 22, 18, 20)
		# Only where there is room between the pits and the road.
		if absf(track.locate(pagoda.position).y) > track.half_width + Track.KERB_WIDTH + 2.0:
			draw_rect(pagoda.grow(1), Pal.BLACK)
			draw_rect(pagoda, Pal.WHITE)
			for k in range(3):
				draw_rect(Rect2(pagoda.position.x - 2, pagoda.position.y + k * 7, pagoda.size.x + 4, 2), Pal.BLACK)
	for p in track.scenery.get("trees", []):
		_tree(p)


func _tree(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 1, p.y + 3, 2, 3), Pal.BROWN)
	draw_rect(Rect2(p.x - 4, p.y - 2, 8, 5), Color("#2e6b28"))
	draw_rect(Rect2(p.x - 3, p.y - 4, 6, 8), Color("#2e6b28"))
	draw_rect(Rect2(p.x - 2, p.y - 3, 2, 2), Pal.LIGHT_GREEN)
