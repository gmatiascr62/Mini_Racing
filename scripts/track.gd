class_name Track
extends RefCounted
## A Mini Racing circuit ("indy", "monza" or "hockenheim"). Each circuit has
## its own world size, bigger than the screen; the camera follows the car.
## The centerline is a closed Catmull-Rom spline resampled at a uniform step,
## so "s" (distance along the track) maps directly to a sample index.

const HALF_WIDTH := 20.0
const KERB_WIDTH := 3.0
const TARGET_STEP := 4.0
## Lateral grip used to compute the safe cornering speed (must match RaceSim).
const SAFE_GRIP := 215.0
const MAX_SAFE_SPEED := 120.0
## Default size of the playing area (twice the 480x270 screen).
const WORLD := Vector2(960, 540)

const IDS := ["indy", "monza", "hockenheim"]
const TITLES := {"indy": "INDIANAPOLIS", "monza": "MONZA", "hockenheim": "HOCKENHEIM"}

## Indianapolis-style oval (proportions of the real one): two long straights,
## two short chutes and four 90-degree turns of equal radius. Driven
## counter-clockwise, starting on the front straight (bottom).
const INDY_CENTRE := Vector2(480, 270)
const INDY_STRAIGHT := 560.0
const INDY_CHUTE := 110.0
const INDY_RADIUS := 150.0

## Monza without the chicanes, clockwise: main straight (heading left),
## Curva Grande, Lesmo, Serraglio, Ascari, back straight and Parabolica.
## Traced on a 480x270 map; scaled 2x (plus MONZA_SHIFT) when built.
const MONZA_MAP := [
	Vector2(309, 200), Vector2(220, 200), Vector2(152, 199), Vector2(116, 191),
	Vector2(96, 171), Vector2(85, 136), Vector2(74, 98), Vector2(60, 65),
	Vector2(50, 44), Vector2(63, 33), Vector2(105, 32), Vector2(124, 44),
	Vector2(150, 68), Vector2(184, 94), Vector2(214, 112), Vector2(242, 121),
	Vector2(281, 124), Vector2(360, 124), Vector2(412, 126), Vector2(442, 138),
	Vector2(458, 162), Vector2(452, 186), Vector2(428, 199), Vector2(395, 201),
	Vector2(352, 200),
]
const MONZA_SHIFT := Vector2(0, 40)

## Old Hockenheim (before 2002), clockwise, traced from the circuit map:
## start straight in the stadium, Nordkurve, the long straight through the
## forest, Bremsschikane 1, Ostkurve chicane and Ostkurve, the straight back
## with Bremsschikane 2, then Agip, Sachs and Sudkurve in the stadium.
## Map coordinates; built as (p - HOCK_ORIGIN) * HOCK_SCALE.
const HOCKENHEIM_MAP := [
	Vector2(88, 296), Vector2(81, 274), Vector2(75, 255), Vector2(69, 240),
	Vector2(71, 229), Vector2(82, 216), Vector2(102, 195), Vector2(124, 172),
	Vector2(147, 149), Vector2(170, 128), Vector2(194, 108), Vector2(218, 90),
	Vector2(240, 77), Vector2(252, 71), Vector2(262, 68), Vector2(270, 73),
	Vector2(278, 73), Vector2(287, 66), Vector2(304, 60),
	Vector2(330, 57), Vector2(360, 57), Vector2(390, 61), Vector2(414, 69),
	Vector2(426, 76), Vector2(434, 84), Vector2(442, 88), Vector2(450, 89),
	Vector2(458, 95), Vector2(466, 104), Vector2(472, 120), Vector2(469, 134),
	Vector2(455, 143), Vector2(430, 153), Vector2(406, 163), Vector2(380, 173),
	Vector2(352, 185), Vector2(326, 196), Vector2(307, 204), Vector2(299, 211),
	Vector2(293, 218), Vector2(286, 222), Vector2(278, 224), Vector2(258, 234),
	Vector2(232, 250), Vector2(204, 267), Vector2(178, 284), Vector2(158, 299),
	Vector2(146, 302), Vector2(137, 296), Vector2(129, 286), Vector2(121, 275),
	Vector2(111, 269), Vector2(102, 274), Vector2(101, 287), Vector2(109, 299),
	Vector2(121, 308), Vector2(128, 318), Vector2(122, 329), Vector2(108, 331),
	Vector2(96, 321), Vector2(91, 308),
]
const HOCK_ORIGIN := Vector2(40, 40)
const HOCK_SCALE := 3.2

var id := "indy"
var title := "INDIANAPOLIS"
var half_width := HALF_WIDTH
## Size of the fenced playing area.
var world := WORLD
## Corners sharper than this get red/white kerbs.
var kerb_curv := 0.005
## Decoration: {"stands": Array[Rect2], "pit": Rect2, "trees": Array[Vector2],
## "greens": Array[Rect2]}
var scenery: Dictionary = {}
var control: Array = []
var pts := PackedVector2Array()
var tangents := PackedVector2Array()
var normals := PackedVector2Array()
var curv := PackedFloat32Array()
var safe_speed := PackedFloat32Array()
var n := 0
var step := TARGET_STEP
var length := 0.0


func _init(p_id: String = "indy") -> void:
	id = p_id if p_id in IDS else "indy"
	title = TITLES[id]
	if id == "monza":
		half_width = 18.0
		kerb_curv = 0.008
		for p in MONZA_MAP:
			control.append(p * 2.0 + MONZA_SHIFT)
	elif id == "hockenheim":
		half_width = 17.0
		kerb_curv = 0.012
		world = Vector2(1480, 990)
		for p in HOCKENHEIM_MAP:
			control.append((p - HOCK_ORIGIN) * HOCK_SCALE)
	else:
		control = _rounded_rect_control(INDY_CENTRE, INDY_STRAIGHT, INDY_CHUTE, INDY_RADIUS)
	_build()
	if id == "monza":
		_build_monza_scenery()
	elif id == "hockenheim":
		_build_hockenheim_scenery()
	else:
		_build_scenery()


## Closed counter-clockwise path around a rectangle with rounded corners,
## sampled every ~25 px, starting in the middle of the bottom straight.
static func _rounded_rect_control(c: Vector2, straight: float, chute: float, r: float) -> Array:
	var out: Array = []
	var hx := straight / 2.0
	var hy := chute / 2.0
	# Each section: [start, end] for straights, [corner centre, angle from] for turns.
	var corners := [Vector2(c.x + hx, c.y + hy), Vector2(c.x + hx, c.y - hy), Vector2(c.x - hx, c.y - hy), Vector2(c.x - hx, c.y + hy)]
	var starts := [PI / 2.0, 0.0, -PI / 2.0, PI]
	var lines := [
		[Vector2(c.x, c.y + hy + r), Vector2(c.x + hx, c.y + hy + r)],
		[Vector2(c.x + hx + r, c.y + hy), Vector2(c.x + hx + r, c.y - hy)],
		[Vector2(c.x + hx, c.y - hy - r), Vector2(c.x - hx, c.y - hy - r)],
		[Vector2(c.x - hx - r, c.y - hy), Vector2(c.x - hx - r, c.y + hy)],
	]
	for i in range(4):
		var a: Vector2 = lines[i][0]
		var b: Vector2 = lines[i][1]
		var steps := maxi(1, int(round(a.distance_to(b) / 25.0)))
		for k in range(steps):
			out.append(a.lerp(b, float(k) / steps))
		var arc_steps := maxi(2, int(round(r * PI / 2.0 / 25.0)))
		for k in range(arc_steps):
			var ang: float = starts[i] - PI / 2.0 * k / arc_steps
			out.append(corners[i] + Vector2(cos(ang), sin(ang)) * r)
	# Back to the start on the bottom straight.
	var last: Vector2 = lines[0][0]
	var from := Vector2(c.x - hx, c.y + hy + r)
	var steps2 := maxi(1, int(round(from.distance_to(last) / 25.0)))
	for k in range(steps2):
		out.append(from.lerp(last, float(k) / steps2))
	return out


## Grandstands along the outside of the front straight and the back straight,
## pits and pagoda on the inside of the front straight, golf course and trees
## in the infield.
func _build_scenery() -> void:
	var outer := half_width + KERB_WIDTH + 6.0
	var bottom := INDY_CENTRE.y + INDY_CHUTE / 2.0 + INDY_RADIUS
	var top := INDY_CENTRE.y - INDY_CHUTE / 2.0 - INDY_RADIUS
	var stands: Array = [
		Rect2(250, bottom + outer, 460, world.y - 8.0 - bottom - outer),
		Rect2(330, 8, 300, top - outer - 8.0),
	]
	var pit := Rect2(300, bottom - outer - 14.0, 280, 12)
	var greens: Array = [Rect2(360, 200, 70, 40), Rect2(560, 300, 80, 36), Rect2(230, 250, 60, 50)]
	var trees := _plant_trees(stands, pit, greens, 0.45)
	scenery = {"stands": stands, "pit": pit, "trees": trees, "greens": greens}


## Monza: grandstand outside the main straight, pits on the inside of it and
## the royal park's woods everywhere else.
func _build_monza_scenery() -> void:
	var straight_y := pts[0].y
	var outer := half_width + KERB_WIDTH + 6.0
	var stands: Array = [Rect2(340, straight_y + outer, 300, 24)]
	var pit := Rect2(440, straight_y - outer - 12.0, 240, 12)
	scenery = {"stands": stands, "pit": pit, "trees": _plant_trees(stands, pit, [], 0.4), "greens": []}


## Hockenheim: grandstands of the Motodrom around the stadium and a thick
## forest everywhere else.
func _build_hockenheim_scenery() -> void:
	var stands: Array = [Rect2(20, 600, 44, 250), Rect2(160, 1020 - 70, 260, 26)]
	scenery = {"stands": stands, "pit": Rect2(), "trees": _plant_trees(stands, Rect2(), [], 0.62), "greens": []}


## Trees on a jittered grid over the whole world, kept clear of the road,
## the buildings and the given areas. keep is the share of grid spots used.
func _plant_trees(stands: Array, pit: Rect2, greens: Array, keep: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1911
	var trees: Array = []
	for y in range(12, int(world.y) - 6, 15):
		for x in range(10, int(world.x) - 6, 15):
			var p := Vector2(x + rng.randi_range(-5, 5), y + rng.randi_range(-5, 5))
			if rng.randf() >= keep:
				continue
			if absf(locate(p).y) < half_width + KERB_WIDTH + 10.0:
				continue
			# Pits plus the pagoda above them.
			var blocked := pit.size.x > 0.0 and Rect2(pit.position - Vector2(10, 34), pit.size + Vector2(20, 44)).has_point(p)
			for r in stands + greens:
				if (r as Rect2).grow(8).has_point(p):
					blocked = true
			if not blocked:
				trees.append(p)
	return trees


func _build() -> void:
	# 1. Dense Catmull-Rom polyline.
	var dense := PackedVector2Array()
	var cn := control.size()
	for i in range(cn):
		var p0: Vector2 = control[(i - 1 + cn) % cn]
		var p1: Vector2 = control[i]
		var p2: Vector2 = control[(i + 1) % cn]
		var p3: Vector2 = control[(i + 2) % cn]
		for k in range(24):
			var t := k / 24.0
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	# 2. Arc length of the dense polyline.
	var dn := dense.size()
	var cum := PackedFloat32Array()
	cum.resize(dn + 1)
	cum[0] = 0.0
	for i in range(dn):
		cum[i + 1] = cum[i] + dense[i].distance_to(dense[(i + 1) % dn])
	length = cum[dn]
	n = int(round(length / TARGET_STEP))
	step = length / n
	# 3. Uniform resampling.
	pts.resize(n)
	var j := 0
	for i in range(n):
		var d := i * step
		while j < dn - 1 and cum[j + 1] < d:
			j += 1
		var seg := cum[j + 1] - cum[j]
		var f := 0.0 if seg <= 0.0 else (d - cum[j]) / seg
		pts[i] = dense[j].lerp(dense[(j + 1) % dn], f)
	# 4. Tangents, normals (pointing to the right of the driving direction).
	tangents.resize(n)
	normals.resize(n)
	for i in range(n):
		var t := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		tangents[i] = t
		normals[i] = Vector2(-t.y, t.x)
	# 5. Signed curvature (positive = turning right) and safe speed.
	curv.resize(n)
	safe_speed.resize(n)
	for i in range(n):
		var a := tangents[(i - 2 + n) % n]
		var b := tangents[(i + 2) % n]
		var ang := atan2(a.cross(b), a.dot(b))
		curv[i] = ang / (4.0 * step)
	for i in range(n):
		var k := absf(curv[i])
		var v := MAX_SAFE_SPEED if k < 0.0001 else sqrt(SAFE_GRIP / k)
		safe_speed[i] = minf(v, MAX_SAFE_SPEED)


func wrap_s(s: float) -> float:
	return fposmod(s, length)


func index_at(s: float) -> int:
	return int(floor(wrap_s(s) / step)) % n


func point_at(s: float) -> Vector2:
	var ws := wrap_s(s) / step
	var i := int(floor(ws)) % n
	return pts[i].lerp(pts[(i + 1) % n], ws - floor(ws))


func tangent_at(s: float) -> Vector2:
	return tangents[index_at(s)]


func normal_at(s: float) -> Vector2:
	return normals[index_at(s)]


func curvature_at(s: float) -> float:
	return curv[index_at(s)]


## Lowest safe speed in [s_from, s_to].
func min_safe_speed(s_from: float, s_to: float) -> float:
	var i := index_at(s_from)
	var count := int(ceil((s_to - s_from) / step)) + 1
	var v := MAX_SAFE_SPEED
	for k in range(maxi(count, 1)):
		v = minf(v, safe_speed[(i + k) % n])
	return v


## Locates a position on the track. Returns Vector3(s, lateral, index).
## lateral > 0 means right of the centerline (relative to driving direction).
## hint is the previous index (-1 for a full search).
func locate(pos: Vector2, hint: int = -1) -> Vector3:
	var best := -1
	var best_d := INF
	if hint >= 0 and hint < n:
		for k in range(-14, 15):
			var i := (hint + k + n) % n
			var d := pos.distance_squared_to(pts[i])
			if d < best_d:
				best_d = d
				best = i
	if best < 0 or best_d > 45.0 * 45.0:
		best_d = INF
		for i in range(n):
			var d := pos.distance_squared_to(pts[i])
			if d < best_d:
				best_d = d
				best = i
	# Refine by projecting onto the neighbouring segments.
	var best_s := best * step
	var best_lat := (pos - pts[best]).dot(normals[best])
	var best_seg_d := INF
	for i0 in [(best - 1 + n) % n, best]:
		var a: Vector2 = pts[i0]
		var b: Vector2 = pts[(i0 + 1) % n]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 <= 0.0 else clampf((pos - a).dot(ab) / l2, 0.0, 1.0)
		var proj := a + ab * t
		var d := pos.distance_squared_to(proj)
		if d < best_seg_d:
			best_seg_d = d
			best_s = (i0 + t) * step
			var nrm := Vector2(-ab.y, ab.x).normalized()
			best_lat = (pos - proj).dot(nrm)
	return Vector3(wrap_s(best_s), best_lat, best)


func is_on_road(lateral: float) -> bool:
	return absf(lateral) <= half_width + KERB_WIDTH


## Grid slot k (0 = pole). Returns [position, heading, s_behind_line].
func grid_slot(k: int) -> Array:
	var back := 14.0 + k * 15.0
	var s := wrap_s(-back)
	var side := -7.0 if k % 2 == 0 else 7.0
	var p := point_at(s) + normal_at(s) * side
	return [p, tangent_at(s).angle(), -back]
