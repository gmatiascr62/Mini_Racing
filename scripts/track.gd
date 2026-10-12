class_name Track
extends RefCounted
## A Mini Racing circuit ("gp", "ovalo" or "serpentina"). The whole track fits in the 480x270 screen.
## The centerline is a closed Catmull-Rom spline resampled at a uniform step,
## so "s" (distance along the track) maps directly to a sample index.

const HALF_WIDTH := 16.0
const KERB_WIDTH := 3.0
const TARGET_STEP := 4.0
## Lateral grip used to compute the safe cornering speed (must match RaceSim).
const SAFE_GRIP := 175.0
const MAX_SAFE_SPEED := 120.0

const IDS := ["gp", "ovalo", "serpentina", "callejero"]
const TITLES := {"gp": "GRAN PREMIO", "ovalo": "OVALO", "serpentina": "SERPENTINA", "callejero": "CALLEJERO"}

## Street circuit: right-angle corners around city blocks (clockwise,
## starting in the middle of the top street).
const CALLEJERO_CORNERS := [
	Vector2(290, 36), Vector2(290, 76), Vector2(448, 76), Vector2(448, 160),
	Vector2(376, 160), Vector2(376, 236), Vector2(300, 236), Vector2(300, 190),
	Vector2(250, 190), Vector2(250, 236), Vector2(110, 236), Vector2(110, 184),
	Vector2(40, 184), Vector2(40, 120), Vector2(180, 120), Vector2(180, 80),
	Vector2(100, 80), Vector2(100, 36),
]

## Twisty walled circuit. Starts on the bottom straight heading left.
const SERPENTINA_CONTROL := [
	Vector2(236, 242), Vector2(150, 240), Vector2(108, 222),
	Vector2(84, 186), Vector2(48, 150), Vector2(38, 96), Vector2(58, 52),
	Vector2(110, 32), Vector2(190, 30), Vector2(236, 36), Vector2(258, 60),
	Vector2(238, 94), Vector2(190, 100), Vector2(140, 108), Vector2(118, 140),
	Vector2(136, 174), Vector2(190, 184), Vector2(240, 170), Vector2(274, 136),
	Vector2(306, 100), Vector2(330, 58), Vector2(370, 34), Vector2(424, 38),
	Vector2(452, 76), Vector2(446, 124), Vector2(420, 162), Vector2(384, 190),
	Vector2(370, 226), Vector2(336, 243), Vector2(290, 243),
]

## Infield barriers (drawn by the player on a screenshot of the track).
const SERPENTINA_WALLS := [
	[Vector2(200, 67), Vector2(180, 67), Vector2(150, 67), Vector2(125, 70),
	Vector2(100, 82), Vector2(82, 98), Vector2(72, 118), Vector2(73, 140),
	Vector2(85, 162), Vector2(100, 180), Vector2(125, 198), Vector2(155, 213),
	Vector2(190, 220), Vector2(225, 214), Vector2(255, 207), Vector2(280, 193),
	Vector2(300, 177), Vector2(320, 160), Vector2(345, 138), Vector2(370, 113),
	Vector2(392, 88)],
	[Vector2(167, 148), Vector2(190, 142), Vector2(213, 135), Vector2(232, 125),
	Vector2(252, 108), Vector2(272, 92), Vector2(290, 72), Vector2(305, 50),
	Vector2(320, 30), Vector2(340, 2)],
]
## Walls placed exactly as drawn (not centred): closes the gap between the
## top of the short wall and the top edge of the screen.
const SERPENTINA_FIXED_WALLS := [
	[Vector2(302, 44), Vector2(306, 33), Vector2(310, 22), Vector2(314, 11), Vector2(317, 4)],
]

## Grand Prix control points, clockwise on screen. The first point sits on the
## main straight; the start/finish line is at s = 0.
const GP_CONTROL := [
	Vector2(196, 40), Vector2(290, 40), Vector2(372, 42), Vector2(430, 62),
	Vector2(448, 104), Vector2(420, 140), Vector2(362, 146), Vector2(318, 162),
	Vector2(326, 204), Vector2(366, 222), Vector2(348, 248), Vector2(268, 250),
	Vector2(200, 238), Vector2(166, 204), Vector2(122, 176), Vector2(64, 166),
	Vector2(36, 128), Vector2(46, 72), Vector2(96, 44),
]

var id := "gp"
## "grass" (countryside circuit) or "city" (street circuit).
var style := "grass"
var title := "GRAN PREMIO"
var half_width := HALF_WIDTH
## Barrier walls in the infield (polylines). Cars bounce off them, so they
## cannot cut across from one part of the circuit to another.
var walls: Array = []
## Wall segments as [a, b] pairs (for collisions).
var wall_segments: Array = []
## Corners sharper than this get red/white kerbs.
var kerb_curv := 0.012
## Decoration: {"stand": Rect2, "pit": Rect2, "trees": Array[Vector2]}
var scenery: Dictionary = {}
var control: Array = []
var wall_lines: Array = []
var fixed_wall_lines: Array = []
var pts := PackedVector2Array()
var tangents := PackedVector2Array()
var normals := PackedVector2Array()
var curv := PackedFloat32Array()
var safe_speed := PackedFloat32Array()
var n := 0
var step := TARGET_STEP
var length := 0.0


func _init(p_id: String = "gp") -> void:
	id = p_id if p_id in IDS else "gp"
	title = TITLES[id]
	if id == "ovalo":
		half_width = 20.0
		kerb_curv = 0.009
		control = _oval_control(Vector2(150, 135), Vector2(330, 135), 85.0)
		scenery = {
			"stand": Rect2(196, 92, 88, 14), "pit": Rect2(196, 160, 88, 10),
			"trees": [Vector2(160, 118), Vector2(320, 118), Vector2(160, 158), Vector2(320, 158), Vector2(24, 30), Vector2(456, 30), Vector2(24, 230), Vector2(456, 240), Vector2(240, 258)],
		}
	elif id == "callejero":
		style = "city"
		half_width = 15.0
		kerb_curv = 0.02
		control = _rounded_path(Vector2(230, 36), CALLEJERO_CORNERS, 20.0)
		scenery = {"stand": Rect2(0, 0, 0, 0), "pit": Rect2(0, 0, 0, 0), "trees": []}
	elif id == "serpentina":
		half_width = 13.0
		kerb_curv = 0.014
		control = SERPENTINA_CONTROL
		wall_lines = SERPENTINA_WALLS
		fixed_wall_lines = SERPENTINA_FIXED_WALLS
		scenery = {
			"stand": Rect2(284, 205, 60, 9), "pit": Rect2(0, 0, 0, 0),
			"trees": [Vector2(90, 80), Vector2(110, 64), Vector2(200, 135), Vector2(220, 140), Vector2(330, 130), Vector2(360, 100), Vector2(400, 92), Vector2(20, 240), Vector2(460, 250)],
		}
	else:
		control = GP_CONTROL
		scenery = {
			"stand": Rect2(212, 64, 96, 14), "pit": Rect2(110, 64, 60, 10),
			"trees": [Vector2(80, 110), Vector2(96, 128), Vector2(260, 120), Vector2(280, 140), Vector2(240, 205), Vector2(395, 105), Vector2(140, 236), Vector2(420, 190), Vector2(24, 230), Vector2(460, 30)],
		}
	_build()
	_build_walls()


## Builds the infield walls from rough hand-drawn lines: every point is moved
## to the middle of the grass between the two nearest parts of the circuit,
## then the line is smoothed, cut open wherever it would touch the road and
## simplified to ~8 px segments.
func _build_walls() -> void:
	walls.clear()
	wall_segments.clear()
	var clear_dist := half_width + KERB_WIDTH + 3.0
	var all_lines: Array = []
	for line in wall_lines:
		all_lines.append([line, true])
	for line in fixed_wall_lines:
		all_lines.append([line, false])
	for entry in all_lines:
		var line: Array = entry[0]
		var centre: bool = entry[1]
		# 1. Densify the drawn line (2 px steps) and centre every point.
		var dense := PackedVector2Array()
		for k in range(line.size() - 1):
			var a: Vector2 = line[k]
			var b: Vector2 = line[k + 1]
			var steps := maxi(1, int(ceil(a.distance_to(b) / 2.0)))
			for t in range(steps + (1 if k == line.size() - 2 else 0)):
				var q := a.lerp(b, float(t) / steps)
				dense.append(_centre_between_sections(q) if centre else q)
		# 2. Smooth out the jitter from switching between nearest samples.
		var smooth := PackedVector2Array()
		smooth.resize(dense.size())
		for i in range(dense.size()):
			var acc := Vector2.ZERO
			var cnt := 0
			var r := 6 if centre else 0
			for j in range(maxi(0, i - r), mini(dense.size(), i + r + 1)):
				acc += dense[j]
				cnt += 1
			smooth[i] = acc / cnt
		# 3. Cut the line open wherever it touches the road.
		var piece := PackedVector2Array()
		for p in smooth:
			if absf(locate(p).y) < clear_dist:
				if piece.size() >= 2:
					walls.append(piece)
				piece = PackedVector2Array()
			else:
				piece.append(p)
		if piece.size() >= 2:
			walls.append(piece)
	# 4. Simplify the 2 px samples to ~8 px segments.
	for i in range(walls.size()):
		var w: PackedVector2Array = walls[i]
		var simple := PackedVector2Array([w[0]])
		for k in range(4, w.size() - 1, 4):
			simple.append(w[k])
		simple.append(w[w.size() - 1])
		walls[i] = simple
	for w in walls:
		for k in range(w.size() - 1):
			wall_segments.append([w[k], w[k + 1]])


## Midpoint between the nearest part of the circuit and the nearest part on the
## opposite side of p that is far away along the lap. Points with no circuit
## on the other side (open grass) are left where they are.
func _centre_between_sections(p: Vector2) -> Vector2:
	var i1 := 0
	var d1 := INF
	for i in range(n):
		var d := p.distance_squared_to(pts[i])
		if d < d1:
			d1 = d
			i1 = i
	var q1 := pts[i1]
	var min_gap := int(100.0 / step)
	var i2 := -1
	var d2 := INF
	for i in range(n):
		var gap := absi(i - i1)
		if mini(gap, n - gap) < min_gap:
			continue
		if (pts[i] - p).dot(q1 - p) >= 0.0:
			continue
		var d := p.distance_squared_to(pts[i])
		if d < d2:
			d2 = d
			i2 = i
	if i2 < 0 or d2 > 130.0 * 130.0:
		return p
	return (q1 + pts[i2]) * 0.5


## Closed path through right-angle corners, each rounded with radius r.
## Starts at start (on the segment from the last corner to the first).
static func _rounded_path(start: Vector2, corners: Array, r: float) -> Array:
	var out: Array = [start]
	var cn := corners.size()
	var prev := start
	for i in range(cn):
		var c: Vector2 = corners[i]
		var nxt: Vector2 = corners[(i + 1) % cn] if i < cn - 1 else corners[0]
		if i == cn - 1:
			nxt = start
		var a := c + (prev - c).normalized() * r
		var b := c + (nxt - c).normalized() * r
		# Straight part up to the corner.
		var d := prev.distance_to(a)
		var steps := int(d / 30.0)
		for k in range(1, steps + 1):
			out.append(prev.lerp(a, float(k) / (steps + 1)))
		# Rounded corner (quadratic Bezier a -> c -> b).
		for k in range(5):
			var t := k / 4.0
			out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
		prev = b
	var d2 := prev.distance_to(start)
	var steps2 := int(d2 / 30.0)
	for k in range(1, steps2 + 1):
		out.append(prev.lerp(start, float(k) / (steps2 + 1)))
	return out


## Stadium-shaped oval: two straights joined by half circles, clockwise,
## starting in the middle of the top straight.
static func _oval_control(left_c: Vector2, right_c: Vector2, r: float) -> Array:
	var out: Array = []
	var mid_x := (left_c.x + right_c.x) / 2.0
	var x := mid_x
	while x < right_c.x:
		out.append(Vector2(x, right_c.y - r))
		x += 30.0
	for k in range(9):
		var a := -PI / 2.0 + PI * k / 9.0
		out.append(right_c + Vector2(cos(a), sin(a)) * r)
	x = right_c.x
	while x > left_c.x:
		out.append(Vector2(x, left_c.y + r))
		x -= 30.0
	for k in range(9):
		var a := PI / 2.0 + PI * k / 9.0
		out.append(left_c + Vector2(cos(a), sin(a)) * r)
	x = left_c.x
	while x < mid_x - 1.0:
		out.append(Vector2(x, left_c.y - r))
		x += 30.0
	return out


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
