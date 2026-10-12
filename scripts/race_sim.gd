class_name RaceSim
extends RefCounted
## Arcade race simulation shared by the offline game, the online client
## (for local prediction) and the authoritative online server.

const TICK := 1.0 / 60.0
const CAR_COUNT := 6
const DEFAULT_LAPS := 5

# --- Arcade physics (pixels, seconds) ---
const VMAX := 100.0
const VMAX_GRASS := 36.0
const ACCEL := 62.0
const COAST_DECEL := 55.0
const GRASS_DRAG := 170.0
const OVERSPEED_DRAG := 60.0
const TURN_RATE := 2.75
const GRIP_ROAD := 225.0
const GRIP_GRASS := 95.0
const SKID_LAT := 13.0
## Brake (both steering buttons pressed together): full speed to almost
## stopped in a bit more than a second.
const BRAKE_DECEL := 80.0
const SKID_DRAG := 24.0
## Share of the sideways speed lost while sliding that the tyres turn back
## into forward speed (arcade drift: slides cost a little, not a lot).
const DRIFT_TURN := 1.4
const SLIDE_KEEP := 0.35
const CAR_RADIUS := 3.6
const CAR_OFFSET := 3.2
const RESTITUTION := 0.45
const SPIN := 0.005
const SCREEN := Vector2(480, 270)
const BOUNDS_MARGIN := 6.0

const STATE_COUNTDOWN := 0
const STATE_RACING := 1
const STATE_FINISHED := 2

const COUNTDOWN_TIME := 3.0
## After every human finished, CPUs get this long to cross the line.
const FINISH_GRACE := 15.0
const MAX_RACE_TIME := 600.0

## The four CPU personalities.
const PERSONALITIES := [
	# Fast and risky: highest top speed, enters corners too hot.
	{"name": "RAYO", "vmax": 101.0, "corner": 1.16, "gain": 2.6, "look": 1.15, "apex": 3.0, "pass_dist": 34.0, "pass_gap": 11.0, "pass_side": 12.0},
	# Precise in corners: uses the racing line, brakes exactly.
	{"name": "PRECISO", "vmax": 98.0, "corner": 1.03, "gain": 4.2, "look": 0.95, "apex": 9.0, "pass_dist": 26.0, "pass_gap": 9.0, "pass_side": 13.0},
	# Aggressive when overtaking: dives close and is happy to bump.
	{"name": "TORO", "vmax": 99.0, "corner": 1.07, "gain": 3.3, "look": 1.0, "apex": 5.0, "pass_dist": 46.0, "pass_gap": 13.0, "pass_side": 7.0, "avoid": 0.3},
	# Balanced.
	{"name": "CALMO", "vmax": 98.5, "corner": 1.04, "gain": 3.4, "look": 1.0, "apex": 6.0, "pass_dist": 30.0, "pass_gap": 10.0, "pass_side": 12.0},
]
## Driving model used when a human car is driven by the computer
## (test races, after finishing, or when an online player disconnects).
## Difficulty levels: CPU top speed and cornering speed multipliers.
const LEVEL_NAMES := ["FACIL", "NORMAL", "DIFICIL"]
const LEVEL_SPEED := [0.78, 0.89, 1.0]
const LEVEL_CORNER := [0.8, 0.91, 1.0]
const DEFAULT_LEVEL := 1
const AUTOPILOT := {"name": "AUTO", "vmax": 97.0, "corner": 1.0, "gain": 3.4, "look": 1.0, "apex": 5.0, "pass_dist": 28.0, "pass_gap": 10.0, "pass_side": 12.0}


## Grid order (index = car id). Ids 2 and 3 are the two human players.
const GRID := [
	{"pers": 0, "color": 2},
	{"pers": 1, "color": 3},
	{"human_slot": 0, "color": 0},
	{"human_slot": 1, "color": 1},
	{"pers": 2, "color": 4},
	{"pers": 3, "color": 5},
]


## Car specs for setup(). Human slots without a player are driven by the
## computer ("BOT").
static func make_specs(human_names: Array) -> Array:
	var specs: Array = []
	for g in GRID:
		if g.has("human_slot"):
			var hs: int = g["human_slot"]
			if hs < human_names.size() and str(human_names[hs]) != "":
				specs.append({"name": human_names[hs], "human": true})
			else:
				specs.append({"name": "BOT", "human": true, "autopilot": true})
		else:
			specs.append({"pers": g["pers"]})
	return specs


static func human_car_id(slot: int) -> int:
	for i in range(GRID.size()):
		if int(GRID[i].get("human_slot", -1)) == slot:
			return i
	return 2


static func car_color(car_id: int) -> Color:
	return Pal.CAR_COLORS[int(GRID[car_id % GRID.size()]["color"])]


class Car:
	var id := 0
	var name := ""
	var human := false
	var autopilot := false
	var pers: Dictionary = {}
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var heading := 0.0
	var steer := 0.0
	var throttle := 1.0
	var brake := false
	var vmax := 100.0
	## Cornering speed multiplier for computer drivers (difficulty level).
	var corner_skill := 1.0
	var on_road := true
	var skidding := false
	var track_idx := -1
	var s := 0.0
	var lateral := 0.0
	var progress := 0.0
	var laps_done := 0
	var lap_start := 0.0
	var best_lap := 0.0
	var finished := false
	var finish_time := 0.0
	var wrong_way_time := 0.0
	var check_time := 0.0
	var check_progress := 0.0
	var stuck_secs := 0
	var ai_lane := 0.0
	var ai_pass_lane := 0.0
	var ai_pass_timer := 0.0

	func forward() -> Vector2:
		return Vector2.from_angle(heading)

	func speed() -> float:
		return vel.dot(forward())


var track: Track
var cars: Array = []
var laps := DEFAULT_LAPS
var level := DEFAULT_LEVEL
var state := STATE_COUNTDOWN
var countdown := COUNTDOWN_TIME
var time := 0.0
var finish_order: Array = []
var last_human_finish := -1.0
## Events produced in the last step: {"type": "crash"/"lap"/"finish"/"go", ...}
var events: Array = []


func _init(p_track: Track = null) -> void:
	track = p_track if p_track != null else Track.new()


## specs: Array of {"name": String, "human": bool, "pers": int (CPU only)}
## in grid order (index 0 = pole position). The car id is its index in specs.
func setup(specs: Array, p_laps: int = DEFAULT_LAPS, p_level: int = DEFAULT_LEVEL) -> void:
	laps = p_laps
	level = clampi(p_level, 0, LEVEL_NAMES.size() - 1)
	cars.clear()
	finish_order.clear()
	events.clear()
	state = STATE_COUNTDOWN
	countdown = COUNTDOWN_TIME
	time = 0.0
	last_human_finish = -1.0
	for i in range(specs.size()):
		var spec: Dictionary = specs[i]
		var c := Car.new()
		c.id = i
		c.human = spec.get("human", false)
		c.autopilot = spec.get("autopilot", false)
		if c.human:
			c.pers = AUTOPILOT
			c.vmax = VMAX
		else:
			c.pers = PERSONALITIES[int(spec.get("pers", 3)) % PERSONALITIES.size()]
			c.vmax = c.pers["vmax"]
		# The difficulty level only slows down computer drivers (CPUs and the
		# offline "BOT" that fills the second player's slot).
		if not c.human or c.autopilot:
			c.vmax *= LEVEL_SPEED[level]
			c.corner_skill = LEVEL_CORNER[level]
		c.name = spec.get("name", c.pers["name"])
		var slot := track.grid_slot(i)
		c.pos = slot[0]
		c.heading = slot[1]
		c.progress = slot[2]
		var loc := track.locate(c.pos)
		c.s = loc.x
		c.lateral = loc.y
		c.track_idx = int(loc.z)
		c.check_progress = c.progress
		cars.append(c)


## Advances the race one fixed tick. inputs: car id -> steer (-1..1).
func step(inputs: Dictionary = {}) -> void:
	var dt := TICK
	events.clear()
	if state == STATE_COUNTDOWN:
		var before := ceili(countdown)
		countdown -= dt
		if ceili(countdown) != before and countdown > 0.0:
			events.append({"type": "beep", "n": ceili(countdown)})
		if countdown <= 0.0:
			countdown = 0.0
			state = STATE_RACING
			for c in cars:
				c.lap_start = 0.0
			events.append({"type": "go"})
		return
	if state == STATE_FINISHED:
		return
	time += dt
	for c in cars:
		if c.human and not c.autopilot and not c.finished:
			# Input: steer (-1..1) or Vector2(steer, brake).
			var inp = inputs.get(c.id, 0.0)
			if inp is Vector2:
				c.steer = clampf(inp.x, -1.0, 1.0)
				c.brake = inp.y > 0.5
			else:
				c.steer = clampf(float(inp), -1.0, 1.0)
				c.brake = false
			c.throttle = 1.0
		else:
			ai_drive(c, dt)
		step_car(c, dt)
	_collide()
	for c in cars:
		_update_progress(c, dt)
	_check_race_end()


## Physics for one car. Used by the simulation and by client prediction.
func step_car(c: Car, dt: float) -> void:
	var loc := track.locate(c.pos, c.track_idx)
	c.track_idx = int(loc.z)
	c.s = loc.x
	c.lateral = loc.y
	c.on_road = track.is_on_road(loc.y)
	var vmax := c.vmax if c.on_road else VMAX_GRASS
	var grip := GRIP_ROAD if c.on_road else GRIP_GRASS
	var fwd := c.speed()
	# Steering: weaker at very low speed, but cars can always rotate a bit
	# so they never get stuck against a wall.
	var tf := clampf(0.35 + absf(fwd) / 45.0, 0.35, 1.0)
	# While sliding the car rotates a little more (drift), so keeping speed in
	# a slide does not make it run wide.
	var drift := DRIFT_TURN if c.skidding else 1.0
	c.heading = wrapf(c.heading + c.steer * TURN_RATE * tf * drift * dt, -PI, PI)
	var dir := Vector2.from_angle(c.heading)
	var right := Vector2(-dir.y, dir.x)
	fwd = c.vel.dot(dir)
	var lat := c.vel.dot(right)
	# Engine (automatic throttle for humans), brake and drag.
	if c.brake:
		fwd = move_toward(fwd, 0.0, BRAKE_DECEL * dt)
	elif fwd < vmax:
		if c.throttle > 0.0:
			var a := ACCEL * (1.0 - 0.55 * clampf(fwd / vmax, 0.0, 1.0)) * c.throttle
			fwd = minf(fwd + a * dt, vmax)
		else:
			fwd = move_toward(fwd, 0.0, COAST_DECEL * dt)
	else:
		fwd = move_toward(fwd, vmax, (OVERSPEED_DRAG if c.on_road else GRASS_DRAG) * dt)
	# Tyre grip: lateral velocity is removed up to the grip limit. Whatever
	# remains is a slide, which scrubs a little speed.
	c.skidding = absf(lat) > SKID_LAT
	var corr := minf(grip * dt, absf(lat))
	lat -= signf(lat) * corr
	if c.skidding:
		fwd = move_toward(fwd, 0.0, SKID_DRAG * dt)
		if c.throttle > 0.0 and fwd < vmax:
			fwd = minf(fwd + corr * SLIDE_KEEP, vmax)
	c.vel = dir * fwd + right * lat
	c.pos += c.vel * dt
	# Screen edges act as walls.
	var hit := false
	if c.pos.x < BOUNDS_MARGIN:
		c.pos.x = BOUNDS_MARGIN
		if c.vel.x < 0.0:
			c.vel.x *= -0.4
			hit = true
	elif c.pos.x > SCREEN.x - BOUNDS_MARGIN:
		c.pos.x = SCREEN.x - BOUNDS_MARGIN
		if c.vel.x > 0.0:
			c.vel.x *= -0.4
			hit = true
	if c.pos.y < BOUNDS_MARGIN + 10.0:
		c.pos.y = BOUNDS_MARGIN + 10.0
		if c.vel.y < 0.0:
			c.vel.y *= -0.4
			hit = true
	elif c.pos.y > SCREEN.y - BOUNDS_MARGIN:
		c.pos.y = SCREEN.y - BOUNDS_MARGIN
		if c.vel.y > 0.0:
			c.vel.y *= -0.4
			hit = true
	if hit:
		c.vel *= 0.7
		events.append({"type": "crash", "pos": c.pos, "power": 30.0})
	# Street circuits: barriers along both edges of the road.
	if track.edge_wall > 0.0:
		var wl := track.locate(c.pos, c.track_idx)
		var limit := track.edge_wall - CAR_RADIUS
		if absf(wl.y) > limit:
			var nrm := track.normal_at(wl.x) * signf(wl.y)
			c.pos -= nrm * (absf(wl.y) - limit)
			var vn := c.vel.dot(nrm)
			if vn > 0.0:
				c.vel -= nrm * vn * 1.4
				c.vel *= 0.92
				if vn > 15.0:
					events.append({"type": "crash", "pos": c.pos + nrm * CAR_RADIUS, "power": vn})
	# Infield barrier walls: bounce off them (no cutting across).
	if not track.wall_segments.is_empty():
		_collide_walls(c)


const WALL_RADIUS := CAR_RADIUS + 1.5


func _collide_walls(c: Car) -> void:
	var dir := Vector2.from_angle(c.heading) * CAR_OFFSET
	for seg in track.wall_segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		for off in [dir, -dir]:
			var p: Vector2 = c.pos + off
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d := p.distance_to(q)
			if d >= WALL_RADIUS:
				continue
			var nrm := (p - q) / d if d > 0.001 else (c.pos - (a + b) * 0.5).normalized()
			c.pos += nrm * (WALL_RADIUS - d)
			var vn := c.vel.dot(nrm)
			if vn < 0.0:
				c.vel -= nrm * vn * 1.4
				c.vel *= 0.92
				if -vn > 15.0:
					events.append({"type": "crash", "pos": q, "power": -vn})


func ai_drive(c: Car, dt: float) -> void:
	c.brake = false
	var p: Dictionary = c.pers
	var dir := c.forward()
	var right := Vector2(-dir.y, dir.x)
	var fwd := maxf(c.vel.dot(dir), 0.0)
	var hw := track.half_width
	# Racing line: drift toward the inside of the next corner.
	var look := (14.0 + fwd * 0.32) * float(p["look"])
	var k := track.curvature_at(c.s + look * 1.6)
	var lane := clampf(k * 900.0, -1.0, 1.0) * float(p["apex"])
	# Overtaking: if a slower car is right ahead, move to one side of it.
	c.ai_pass_timer -= dt
	for oc in cars:
		var o: Car = oc
		if o == c:
			continue
		var rel: Vector2 = o.pos - c.pos
		var ahead := rel.dot(dir)
		if ahead <= 0.0 or ahead > float(p["pass_dist"]):
			continue
		var side := rel.dot(right)
		if absf(side) > float(p["pass_gap"]):
			continue
		if o.vel.dot(dir) > fwd + 4.0:
			continue
		# Pass on the side we are already on, unless there is no room there.
		var need := float(p["pass_side"]) + 4.0
		var room_right := hw - o.lateral
		var room_left := o.lateral + hw
		var go_right := c.lateral >= o.lateral
		if go_right and room_right < need:
			go_right = false
		elif not go_right and room_left < need:
			go_right = true
		var target := o.lateral + (float(p["pass_side"]) if go_right else -float(p["pass_side"]))
		c.ai_pass_lane = clampf(target, -hw + 4.0, hw - 4.0)
		c.ai_pass_timer = 0.8
		break
	if c.ai_pass_timer > 0.0:
		lane = c.ai_pass_lane
	# Side-by-side: leave room for the car alongside (TORO barely cares).
	var avoid := float(p.get("avoid", 1.0))
	for oc in cars:
		var o: Car = oc
		if o == c:
			continue
		var rel: Vector2 = o.pos - c.pos
		var ahead := rel.dot(dir)
		var side := rel.dot(right)
		if absf(ahead) < 10.0 and absf(side) < 12.0:
			var push := (12.0 - absf(side)) * avoid
			lane -= push if side >= 0.0 else -push
	lane = clampf(lane, -hw + 4.0, hw - 4.0)
	if not c.on_road:
		lane = 0.0
		look *= 0.7
	c.ai_lane = move_toward(c.ai_lane, lane, 30.0 * dt)
	var ts := c.s + look
	var target_pt := track.point_at(ts) + track.normal_at(ts) * c.ai_lane
	var desired := (target_pt - c.pos).angle()
	var diff := wrapf(desired - c.heading, -PI, PI)
	c.steer = clampf(diff * float(p["gain"]), -1.0, 1.0)
	# Speed: lift off before corners that are too fast for us.
	var horizon := fwd * 0.75 + 22.0
	var vt := track.min_safe_speed(c.s, c.s + horizon) * float(p["corner"]) * c.corner_skill * track.cpu_corner
	if absf(diff) > 0.9:
		vt = minf(vt, 45.0)
	c.throttle = 1.0 if fwd < minf(vt, c.vmax) else 0.0



func _collide() -> void:
	var count := cars.size()
	var min_d := CAR_RADIUS * 2.0
	for i in range(count):
		var a: Car = cars[i]
		for j in range(i + 1, count):
			var b: Car = cars[j]
			if a.pos.distance_squared_to(b.pos) > 196.0:
				continue
			var da := a.forward() * CAR_OFFSET
			var db := b.forward() * CAR_OFFSET
			var best_pen := 0.0
			var pa := Vector2.ZERO
			var pb := Vector2.ZERO
			for oa in [da, -da]:
				for ob in [db, -db]:
					var ca: Vector2 = a.pos + oa
					var cb: Vector2 = b.pos + ob
					var pen := min_d - ca.distance_to(cb)
					if pen > best_pen:
						best_pen = pen
						pa = ca
						pb = cb
			if best_pen <= 0.0:
				continue
			var nrm := pb - pa
			if nrm.length_squared() < 0.0001:
				nrm = b.pos - a.pos
				if nrm.length_squared() < 0.0001:
					nrm = Vector2.RIGHT
			nrm = nrm.normalized()
			a.pos -= nrm * best_pen * 0.5
			b.pos += nrm * best_pen * 0.5
			var rv := (b.vel - a.vel).dot(nrm)
			if rv >= 0.0:
				continue
			var jimp := -(1.0 + RESTITUTION) * rv * 0.5
			a.vel -= nrm * jimp
			b.vel += nrm * jimp
			# Off-centre hits rotate the cars.
			var ra := pa - a.pos
			var rb := pb - b.pos
			a.heading += clampf(ra.cross(-nrm * jimp) * SPIN, -0.3, 0.3)
			b.heading += clampf(rb.cross(nrm * jimp) * SPIN, -0.3, 0.3)
			# Real impacts scrub speed; cars just leaning on each other do not.
			if -rv > 8.0:
				a.vel *= 0.94
				b.vel *= 0.94
			if -rv > 10.0:
				events.append({"type": "crash", "pos": (pa + pb) * 0.5, "power": -rv})


func _update_progress(c: Car, dt: float) -> void:
	var loc := track.locate(c.pos, c.track_idx)
	c.track_idx = int(loc.z)
	var ds := loc.x - c.s
	if ds > track.length * 0.5:
		ds -= track.length
	elif ds < -track.length * 0.5:
		ds += track.length
	# Only credit plausible movement: cutting across the grass earns nothing.
	if absf(ds) < 8.0:
		c.progress += ds
	c.s = loc.x
	c.lateral = loc.y
	c.on_road = track.is_on_road(loc.y)
	# Wrong-way detection (shown in the HUD for humans).
	if c.vel.dot(track.tangent_at(c.s)) < -8.0:
		c.wrong_way_time += dt
	else:
		c.wrong_way_time = 0.0
	if c.finished:
		return
	var done := int(floor(c.progress / track.length))
	if done > c.laps_done and c.progress > 0.0:
		var lap_time := time - c.lap_start
		if c.best_lap <= 0.0 or lap_time < c.best_lap:
			c.best_lap = lap_time
		c.lap_start = time
		c.laps_done = done
		if c.laps_done >= laps:
			c.finished = true
			c.finish_time = time
			finish_order.append(c.id)
			if c.human:
				last_human_finish = time
			events.append({"type": "finish", "car": c.id})
		else:
			events.append({"type": "lap", "car": c.id, "lap": c.laps_done})
	# Stuck detection: respawn on the track if no progress for a while.
	c.check_time += dt
	if c.check_time >= 1.0:
		if c.progress - c.check_progress < 4.0:
			c.stuck_secs += 1
		else:
			c.stuck_secs = 0
		c.check_progress = c.progress
		c.check_time = 0.0
		var limit := 5 if (c.human and not c.autopilot) else 3
		if c.stuck_secs >= limit:
			_respawn(c)


func _respawn(c: Car) -> void:
	var s := c.s
	c.pos = track.point_at(s) + track.normal_at(s) * clampf(c.lateral, -6.0, 6.0)
	c.heading = track.tangent_at(s).angle()
	c.vel = Vector2.ZERO
	c.stuck_secs = 0
	events.append({"type": "respawn", "car": c.id})


func _check_race_end() -> void:
	if state != STATE_RACING:
		return
	var humans_done := true
	var all_done := true
	for c in cars:
		if not c.finished:
			all_done = false
			if c.human and not c.autopilot:
				humans_done = false
	if all_done or time >= MAX_RACE_TIME:
		state = STATE_FINISHED
	elif humans_done and last_human_finish >= 0.0 and time - last_human_finish >= FINISH_GRACE:
		state = STATE_FINISHED
	if state == STATE_FINISHED:
		events.append({"type": "race_over"})


## Car ids ordered by race position.
func standings() -> Array:
	var ids: Array = []
	for c in cars:
		ids.append(c.id)
	ids.sort_custom(func(x: int, y: int) -> bool:
		var a: Car = cars[x]
		var b: Car = cars[y]
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_time < b.finish_time
		return a.progress > b.progress)
	return ids


func position_of(car_id: int) -> int:
	return standings().find(car_id) + 1


## Final classification as plain data (also sent over the network).
func results() -> Array:
	var out: Array = []
	var pos := 1
	for id in standings():
		var c: Car = cars[id]
		out.append({
			"pos": pos, "id": c.id, "name": c.name, "human": c.human,
			"finished": c.finished, "time": c.finish_time, "best": c.best_lap,
			"laps": mini(c.laps_done, laps),
		})
		pos += 1
	return out
