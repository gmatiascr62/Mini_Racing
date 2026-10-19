extends Node2D
## Race screen. Offline: runs RaceSim locally. Online: the server is
## authoritative; this client predicts its own car (with reconciliation)
## and interpolates the other cars from server snapshots.

const INTERP_TICKS := 5.0
## Steering buttons in the bottom corners. Any touch on the left half of the
## screen steers left, on the right half steers right.
const LEFT_BTN := Rect2(6, 206, 64, 58)
const RIGHT_BTN := Rect2(410, 206, 64, 58)
## The camera follows the player's car and turns with it, so the car always
## points up the screen. It looks this far ahead of the car (px).
const CAM_AHEAD := 62.0
## How fast the view turns to follow the car (higher = stiffer).
const CAM_TURN := 5.0
## Minimap in the top-right corner: the whole world scaled to fit this box.
const MAP_POS := Vector2(380, 14)
const MAP_BOX := Vector2(96, 56)
const MARK_ROAD := Color(0.13, 0.13, 0.13, 0.75)
const MARK_GRASS := Color(0.2, 0.33, 0.13, 0.8)


class Layer:
	extends Node2D
	var cb: Callable

	func _draw() -> void:
		cb.call(self)


var track: Track
var sim: RaceSim
var online := false
var my_id := 2
var touches: Dictionary = {}
var ui := Ui.new()
var particles: Array = []
var results: Array = []
var show_results := false
var banner := ""
var banner_time := 0.0
var go_time := 0.0
var conn_lost := ""
var peer_left := false
var waiting_again := false
var rival_wants_again := false
var blink := 0.0

var _cars_layer: Layer
var _hud_layer: Layer
var _camera: Camera2D
var _cam_angle := 0.0
var _map_line := PackedVector2Array()
var _map_scale := 0.1
var _marks_img: Image
var _marks_tex: ImageTexture
var _marks_dirty := false
var _marks_timer := 0.0
var _last_laps := 0
var _was_finished := false
var _last_cd := 4

# Online state.
var _seq := 0
var _history: Array = []
var _snaps: Array = []
var _latest_k := -1
var _latest_recv := 0.0
var _render_offset := Vector2.ZERO
var _standings: Array = []
var _predict := true


func _ready() -> void:
	track = Game.track
	online = Game.mode == "online"
	sim = RaceSim.new(track)
	if online:
		sim.setup(RaceSim.make_specs(["J1", "J2"]), RaceSim.DEFAULT_LAPS, Game.online_level)
		my_id = Game.online_car_id
		for i in range(mini(Game.online_names.size(), sim.cars.size())):
			sim.cars[i].name = str(Game.online_names[i])
		sim.laps = Game.online_laps
		Game.net.message.connect(_on_net_message)
		Game.net.closed.connect(_on_net_closed)
	else:
		sim.setup(RaceSim.make_specs(["VOS"]), RaceSim.DEFAULT_LAPS, Game.level)
		my_id = RaceSim.human_car_id(0)
		if Game.autodrive:
			_me().autopilot = true
	_standings = sim.standings()
	add_child(TrackView.new(track))
	_marks_img = Image.create(int(track.world.x), int(track.world.y), false, Image.FORMAT_RGBA8)
	_marks_img.fill(Color(0, 0, 0, 0))
	_marks_tex = ImageTexture.create_from_image(_marks_img)
	var marks := Sprite2D.new()
	marks.texture = _marks_tex
	marks.centered = false
	add_child(marks)
	_cars_layer = Layer.new()
	_cars_layer.cb = _draw_cars
	add_child(_cars_layer)
	_camera = Camera2D.new()
	_camera.ignore_rotation = false
	add_child(_camera)
	_camera.make_current()
	_update_camera(0.0, true)
	# HUD and buttons stay fixed on screen.
	var hud := CanvasLayer.new()
	add_child(hud)
	_hud_layer = Layer.new()
	_hud_layer.cb = _draw_hud
	hud.add_child(_hud_layer)
	_map_scale = minf(MAP_BOX.x / track.world.x, MAP_BOX.y / track.world.y)
	for i in range(0, track.n, 3):
		_map_line.append(MAP_POS + track.pts[i] * _map_scale)
	_map_line.append(_map_line[0])


func _exit_tree() -> void:
	Sfx.stop_all()
	if online:
		if Game.net.message.is_connected(_on_net_message):
			Game.net.message.disconnect(_on_net_message)
		if Game.net.closed.is_connected(_on_net_closed):
			Game.net.closed.disconnect(_on_net_closed)


func _me() -> RaceSim.Car:
	return sim.cars[my_id]


# ---------------------------------------------------------------- input

func _steer_input() -> float:
	var l := Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
	var r := Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
	for idx in touches:
		if touches[idx] < 0:
			l = true
		elif touches[idx] > 0:
			r = true
	return float(r) - float(l)


func _side_for(p: Vector2) -> int:
	if p.y < 20.0:
		return 0
	return -1 if p.x < 240.0 else 1


func _input(event: InputEvent) -> void:
	if show_results or conn_lost != "":
		var id := ui.handle(event)
		if id != "":
			_on_button(id)
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			touches[t.index] = _side_for(t.position)
		else:
			touches.erase(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		touches[d.index] = _side_for(d.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back_to_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back_to_menu()


func _back_to_menu() -> void:
	if online:
		Game.net.send({"t": "leave"})
		Game.net.close()
	Game.goto("menu")


func _on_button(id: String) -> void:
	match id:
		"again":
			if online:
				if conn_lost == "":
					Game.net.send({"t": "again"})
					waiting_again = true
					_build_results_ui()
			else:
				get_tree().reload_current_scene()
		"menu":
			_back_to_menu()


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	blink += delta
	if online:
		_online_tick()
	else:
		sim.step({my_id: _steer_input()})
		_handle_sim_events(sim.events)
		_standings = sim.standings()
		if sim.state == RaceSim.STATE_FINISHED and not show_results:
			results = sim.results()
			_show_results()
	_stamp_marks()
	_update_particles(delta)
	_update_camera(delta)
	var me := _me()
	var racing := sim.state == RaceSim.STATE_RACING and not show_results
	Sfx.set_engine(racing or sim.state == RaceSim.STATE_COUNTDOWN, maxf(me.speed(), 0.0) / RaceSim.VMAX)
	Sfx.set_skid(racing and me.skidding)
	if banner_time > 0.0:
		banner_time -= delta
	_marks_timer += delta
	if _marks_dirty and _marks_timer > 0.1:
		_marks_tex.update(_marks_img)
		_marks_dirty = false
		_marks_timer = 0.0
	_cars_layer.queue_redraw()
	_hud_layer.queue_redraw()


func _handle_sim_events(events: Array) -> void:
	for e in events:
		match e["type"]:
			"beep":
				Sfx.play("beep", -8.0)
			"go":
				Sfx.play("go", -6.0)
				go_time = 1.0
			"crash":
				_on_crash(e["pos"], float(e["power"]))
			"lap":
				if e["car"] == my_id:
					_announce_lap(int(e["lap"]))
			"finish":
				if e["car"] == my_id:
					_announce_finish()


func _announce_lap(done: int) -> void:
	Sfx.play("lap", -8.0)
	if done == sim.laps - 1:
		_show_banner("ULTIMA VUELTA!")
	else:
		_show_banner("VUELTA %d" % (done + 1))


func _announce_finish() -> void:
	Sfx.play("finish", -6.0)
	var pos := _standings.find(my_id) + 1
	_show_banner("LLEGASTE %d DE %d" % [pos, sim.cars.size()])
	banner_time = 4.0


func _show_banner(t: String) -> void:
	banner = t
	banner_time = 1.6


func _on_crash(p: Vector2, power: float) -> void:
	if power > 14.0:
		Sfx.play("crash", clampf(-22.0 + power * 0.3, -22.0, -4.0))
	var rng := RandomNumberGenerator.new()
	for i in range(int(clampf(power / 6.0, 2.0, 8.0))):
		particles.append({
			"pos": p, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(15.0, 45.0),
			"life": rng.randf_range(0.2, 0.45), "col": Pal.YELLOW if i % 2 == 0 else Pal.WHITE,
		})


func _update_particles(dt: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p["life"] -= dt
		p["pos"] += p["vel"] * dt
		if p["life"] <= 0.0:
			particles.remove_at(i)


func _stamp_marks() -> void:
	for c in sim.cars:
		if not c.skidding and c.on_road:
			continue
		if not c.on_road and c.speed() < 20.0:
			continue
		var p: Vector2 = c.pos
		if c.id == my_id:
			p += _render_offset
		var dir := Vector2.from_angle(c.heading)
		var right := Vector2(-dir.y, dir.x)
		var col := MARK_ROAD if c.on_road else MARK_GRASS
		for side in [-3.0, 3.0]:
			var q: Vector2 = (p - dir * 4.0 + right * side).floor()
			if q.x >= 0 and q.y >= 0 and q.x < track.world.x and q.y < track.world.y:
				_marks_img.set_pixelv(Vector2i(q), col)
				_marks_dirty = true


func _update_camera(dt: float, snap: bool = false) -> void:
	var me := _me()
	var target := me.heading
	# Follow the direction the car is moving in rather than where its nose
	# points, so a skid or a spin after a crash does not whip the view around.
	if me.vel.dot(me.forward()) > 25.0:
		target = me.vel.angle()
	if snap:
		_cam_angle = target
	else:
		_cam_angle = lerp_angle(_cam_angle, target, 1.0 - exp(-CAM_TURN * dt))
	_camera.position = me.pos + _render_offset + Vector2.from_angle(_cam_angle) * CAM_AHEAD
	_camera.rotation = _cam_angle + PI / 2.0


# ---------------------------------------------------------------- online

func _online_tick() -> void:
	var me := _me()
	if Game.net.is_open() and sim.state == RaceSim.STATE_RACING and not me.finished and not show_results:
		_seq += 1
		var steer := _steer_input()
		if Game.autodrive:
			sim.ai_drive(me, RaceSim.TICK)
			steer = signf(me.steer) if absf(me.steer) > 0.3 else 0.0
		_history.append([_seq, steer])
		if _history.size() > 180:
			_history.pop_front()
		Game.net.send({"t": "in", "q": _seq, "s": steer})
		if _predict:
			me.steer = steer
			me.throttle = 1.0
			sim.step_car(me, RaceSim.TICK)
	_render_offset *= 0.82
	_interpolate_others()


func _interpolate_others() -> void:
	if _snaps.size() < 1:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var rk := _latest_k + (now - _latest_recv) * 60.0 - INTERP_TICKS
	var a: Dictionary = _snaps[0]
	var b: Dictionary = _snaps[0]
	for i in range(_snaps.size()):
		var s: Dictionary = _snaps[i]
		if float(s["k"]) <= rk:
			a = s
			b = _snaps[mini(i + 1, _snaps.size() - 1)]
	var span := float(b["k"]) - float(a["k"])
	var f := 0.0 if span <= 0.0 else clampf((rk - float(a["k"])) / span, 0.0, 1.0)
	var ca: Array = a["c"]
	var cb: Array = b["c"]
	for i in range(mini(ca.size(), sim.cars.size())):
		if i == my_id and _predict and sim.state == RaceSim.STATE_RACING:
			continue
		var c: RaceSim.Car = sim.cars[i]
		var ra: Array = ca[i]
		var rb: Array = cb[i]
		c.pos = Vector2(ra[0], ra[1]).lerp(Vector2(rb[0], rb[1]), f) / 10.0
		c.heading = lerp_angle(float(ra[2]) / 1000.0, float(rb[2]) / 1000.0, f)
		c.vel = Vector2(ra[3], ra[4]).lerp(Vector2(rb[3], rb[4]), f) / 10.0


func _on_net_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"s":
			_on_snapshot(msg)
		"end":
			results = msg.get("res", [])
			sim.state = RaceSim.STATE_FINISHED
			_show_results()
		"start":
			# Rematch: reload the race with the new data.
			Game.apply_start(msg)
			get_tree().reload_current_scene()
		"again_req":
			rival_wants_again = true
			if show_results:
				_build_results_ui()
		"peer_left":
			peer_left = true
			_show_banner("EL RIVAL SE DESCONECTO")
			banner_time = 3.0
			if show_results:
				_build_results_ui()
		"error":
			conn_lost = str(msg.get("msg", "ERROR"))
			_build_results_ui()


func _on_net_closed(reason: String) -> void:
	if conn_lost == "":
		conn_lost = reason
		_build_results_ui()


func _on_snapshot(msg: Dictionary) -> void:
	var k := int(msg.get("k", 0))
	var cars: Array = msg.get("c", [])
	if cars.size() != sim.cars.size():
		return
	_latest_k = k
	_latest_recv = Time.get_ticks_msec() / 1000.0
	_snaps.append({"k": k, "c": cars})
	while _snaps.size() > 40:
		_snaps.pop_front()
	var prev_state := sim.state
	sim.state = int(msg.get("st", 0))
	sim.countdown = float(msg.get("cd", 0)) / 100.0
	sim.time = float(msg.get("tm", 0)) / 100.0
	var order: Array = msg.get("r", [])
	if order.size() == sim.cars.size():
		_standings = order.map(func(v) -> int: return int(v))
	for i in range(cars.size()):
		var c: RaceSim.Car = sim.cars[i]
		var row: Array = cars[i]
		var flags := int(row[6])
		c.skidding = flags & 1 != 0
		c.on_road = flags & 2 != 0
		c.finished = flags & 4 != 0
		c.progress = float(row[5]) / 10.0
		c.best_lap = float(row[8]) / 100.0
		var laps := int(row[7])
		if i == my_id and laps > c.laps_done and not c.finished:
			c.laps_done = laps
			_announce_lap(laps)
		c.laps_done = laps
	# Countdown / start sounds.
	if sim.state == RaceSim.STATE_COUNTDOWN:
		var n := ceili(sim.countdown)
		if n < _last_cd and n > 0:
			Sfx.play("beep", -8.0)
		_last_cd = n
	elif prev_state == RaceSim.STATE_COUNTDOWN and sim.state == RaceSim.STATE_RACING:
		Sfx.play("go", -6.0)
		go_time = 1.0
	var me := _me()
	if me.finished and not _was_finished:
		_was_finished = true
		_announce_finish()
	# Own car: take the authoritative state, then replay unacknowledged inputs.
	_predict = not me.finished and sim.state == RaceSim.STATE_RACING
	var row: Array = cars[my_id]
	var old_pos := me.pos + _render_offset
	me.pos = Vector2(row[0], row[1]) / 10.0
	me.heading = float(row[2]) / 1000.0
	me.vel = Vector2(row[3], row[4]) / 10.0
	if _predict:
		var ack := int(msg.get("a", 0))
		while not _history.is_empty() and int(_history[0][0]) <= ack:
			_history.pop_front()
		for h in _history:
			me.steer = h[1]
			sim.step_car(me, RaceSim.TICK)
		_render_offset = old_pos - me.pos
		if _render_offset.length() > 24.0:
			_render_offset = Vector2.ZERO
	else:
		_render_offset = Vector2.ZERO
	for ev in msg.get("ev", []):
		_on_crash(Vector2(ev[0], ev[1]), 25.0)


# ---------------------------------------------------------------- results

func _show_results() -> void:
	show_results = true
	touches.clear()
	Sfx.stop_all()
	_build_results_ui()


func _build_results_ui() -> void:
	ui.clear()
	if conn_lost != "":
		ui.add("menu", Rect2(190, 226, 100, 18), "MENU", Pal.LIGHT_RED)
		return
	var again_text := "OTRA VEZ"
	if online and waiting_again:
		again_text = "ESPERANDO..."
	ui.add("again", Rect2(132, 226, 100, 18), again_text, Pal.LIGHT_GREEN)
	ui.add("menu", Rect2(248, 226, 100, 18), "MENU", Pal.LIGHT_RED)


# ---------------------------------------------------------------- drawing

func _draw_cars(ci: CanvasItem) -> void:
	# Cars are drawn rotated (not with the pre-rotated frames) so they turn
	# smoothly with the camera. Shadows first, offset down-right on screen.
	var shadow := Vector2(1, 2).rotated(_camera.rotation)
	for pass_i in range(2):
		for c in sim.cars:
			var tex: Texture2D = CarSprites.frames_for(RaceSim.car_color(c.id))[0]
			var p: Vector2 = c.pos
			if c.id == my_id:
				p += _render_offset
			if pass_i == 0:
				ci.draw_set_transform(p + shadow, c.heading)
				ci.draw_texture(tex, Vector2(-8, -8), Color(0, 0, 0, 0.35))
			else:
				ci.draw_set_transform(p, c.heading)
				ci.draw_texture(tex, Vector2(-8, -8))
	ci.draw_set_transform(Vector2.ZERO)
	for pt in particles:
		ci.draw_rect(Rect2((pt["pos"] as Vector2).floor(), Vector2(1, 1)), pt["col"])


## The whole oval at 1/10 scale with a dot per car.
func _draw_minimap(ci: CanvasItem) -> void:
	var size := track.world * _map_scale
	ci.draw_rect(Rect2(MAP_POS - Vector2(2, 2), size + Vector2(4, 4)), Color(0, 0, 0, 0.55))
	ci.draw_polyline(_map_line, Pal.LIGHT_GREY, 3.0)
	var p0 := MAP_POS + track.pts[0] * _map_scale
	ci.draw_rect(Rect2(p0 - Vector2(0, 2), Vector2(1, 5)), Pal.WHITE)
	for c in sim.cars:
		if c.id == my_id:
			continue
		var p: Vector2 = (MAP_POS + c.pos * _map_scale).round()
		ci.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), RaceSim.car_color(c.id))
	var mp: Vector2 = (MAP_POS + (_me().pos + _render_offset) * _map_scale).round()
	ci.draw_rect(Rect2(mp - Vector2(2, 2), Vector2(5, 5)), Pal.WHITE if fmod(blink, 0.5) < 0.3 else Pal.BLACK)
	ci.draw_rect(Rect2(mp - Vector2(1, 1), Vector2(3, 3)), RaceSim.car_color(my_id))


func _draw_hud(ci: CanvasItem) -> void:
	var me := _me()
	# Top bar.
	ci.draw_rect(Rect2(0, 0, 480, 11), Color(0, 0, 0, 0.85))
	var lap := clampi(me.laps_done + 1, 1, sim.laps)
	PixelFont.draw_text(ci, "VUELTA %d/%d" % [lap, sim.laps], Vector2(4, 2), 1, Pal.YELLOW)
	var pos := _standings.find(my_id) + 1
	PixelFont.draw_text(ci, "POS %d/%d" % [pos, sim.cars.size()], Vector2(92, 2), 1, Pal.WHITE)
	PixelFont.draw_text(ci, Ui.format_time(sim.time if sim.time > 0.0 else 0.001), Vector2(162, 2), 1, Pal.CYAN)
	if online:
		PixelFont.draw_text(ci, "PING %d" % int(Game.net.rtt_ms), Vector2(222, 2), 1, Pal.LIGHT_GREY)
	# Standings as coloured blocks.
	var x := 298.0
	PixelFont.draw_text(ci, "ORDEN", Vector2(x, 2), 1, Pal.LIGHT_GREY)
	x += 34.0
	for id in _standings:
		var col := RaceSim.car_color(int(id))
		ci.draw_rect(Rect2(x, 2, 10, 7), col)
		if int(id) == my_id:
			ci.draw_rect(Rect2(x, 9, 10, 1), Pal.WHITE)
		PixelFont.draw_text(ci, str(_standings.find(id) + 1), Vector2(x + 3, 2), 1, Pal.BLACK)
		x += 12.0
	_draw_minimap(ci)
	if not show_results:
		_draw_controls(ci)
	# Marker over the player's car before and just after the start.
	if sim.state == RaceSim.STATE_COUNTDOWN or (sim.time < 3.0 and fmod(blink, 0.4) < 0.25):
		var sp := (get_viewport().get_canvas_transform() * (me.pos + _render_offset)).round()
		var col := RaceSim.car_color(my_id)
		for k in range(4):
			ci.draw_rect(Rect2(sp.x - 3 + k, sp.y - 16 + k, 7 - k * 2, 1), col)
	# Countdown lights.
	if sim.state == RaceSim.STATE_COUNTDOWN:
		var lit := clampi(3 - ceili(sim.countdown) + 1, 0, 3)
		Ui.draw_panel(ci, Rect2(204, 100, 72, 30), Color(0, 0, 0, 0.85), Pal.GREY)
		for i in range(3):
			var col := Pal.RED.lightened(0.2) if i < lit else Color("#301010")
			ci.draw_rect(Rect2(214 + i * 20, 108, 12, 14), col)
		PixelFont.draw_text_centered(ci, str(ceili(sim.countdown)), 240, 136, 4, Pal.WHITE, Pal.BLACK)
	elif go_time > 0.0:
		go_time -= get_physics_process_delta_time()
		PixelFont.draw_text_centered(ci, "YA!", 240, 112, 6, Pal.LIGHT_GREEN, Pal.BLACK)
	if banner_time > 0.0 and banner != "" and not show_results:
		var w := PixelFont.text_width(banner, 2) + 16
		Ui.draw_panel(ci, Rect2(240 - w / 2.0, 120, w, 24), Color(0, 0, 0, 0.8), Pal.YELLOW)
		PixelFont.draw_text_centered(ci, banner, 240, 125, 2, Pal.YELLOW)
	if me.wrong_way_time > 1.0 and not me.finished and fmod(blink, 0.6) < 0.4 and not show_results:
		PixelFont.draw_text_centered(ci, "CONTRAMANO!", 240, 150, 2, Pal.LIGHT_RED, Pal.BLACK)
	if me.finished and not show_results:
		PixelFont.draw_text_centered(ci, "ESPERANDO A LOS DEMAS...", 240, 160, 1, Pal.WHITE, Pal.BLACK)
	if show_results:
		_draw_results(ci)
	elif conn_lost != "":
		Ui.draw_panel(ci, Rect2(90, 96, 300, 60), Color(0, 0, 0, 0.9), Pal.LIGHT_RED)
		PixelFont.draw_text_centered(ci, conn_lost, 240, 112, 1, Pal.WHITE)
		ui.draw(ci)


func _draw_controls(ci: CanvasItem) -> void:
	var s := _steer_input()
	for i in range(2):
		var r := LEFT_BTN if i == 0 else RIGHT_BTN
		var active := (s < 0.0 and i == 0) or (s > 0.0 and i == 1)
		ci.draw_rect(r, Color(1, 1, 1, 0.28) if active else Color(0, 0, 0, 0.32))
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.5))
		ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Color(1, 1, 1, 0.5))
		ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), Color(1, 1, 1, 0.5))
		ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), Color(1, 1, 1, 0.5))
		# Pixel arrow.
		var cx := r.position.x + r.size.x / 2.0
		var cy := r.position.y + r.size.y / 2.0
		var col := Color(1, 1, 1, 0.85)
		# Simple triangle drawn row by row.
		for row in range(-8, 9):
			var len := 9 - absi(row)
			if i == 0:
				ci.draw_rect(Rect2(cx - 6 + (9 - len), cy + row, len + 3, 1), col)
			else:
				ci.draw_rect(Rect2(cx - 6, cy + row, len + 3, 1), col)


func _draw_results(ci: CanvasItem) -> void:
	Ui.draw_panel(ci, Rect2(100, 30, 280, 220), Color(0, 0, 0, 0.9), Pal.LIGHT_BLUE)
	PixelFont.draw_text_centered(ci, "CLASIFICACION FINAL", 240, 40, 2, Pal.YELLOW)
	PixelFont.draw_text(ci, "POS", Vector2(118, 64), 1, Pal.LIGHT_GREY)
	PixelFont.draw_text(ci, "PILOTO", Vector2(146, 64), 1, Pal.LIGHT_GREY)
	PixelFont.draw_text(ci, "TIEMPO", Vector2(250, 64), 1, Pal.LIGHT_GREY)
	PixelFont.draw_text(ci, "MEJOR V.", Vector2(316, 64), 1, Pal.LIGHT_GREY)
	var y := 78.0
	for r in results:
		var id := int(r["id"])
		var is_me := id == my_id
		var col := Pal.YELLOW if is_me else Pal.WHITE
		ci.draw_rect(Rect2(118, y, 8, 7), RaceSim.car_color(id))
		var name := str(r["name"])
		if is_me and name != "VOS":
			name += " (VOS)"
		var t := Ui.format_time(float(r["time"])) if r["finished"] else ("%d VUELTAS" % int(r["laps"]))
		PixelFont.draw_text(ci, str(int(r["pos"])), Vector2(130, y), 1, col)
		PixelFont.draw_text(ci, name, Vector2(146, y), 1, col)
		PixelFont.draw_text(ci, t, Vector2(250, y), 1, col)
		PixelFont.draw_text(ci, Ui.format_time(float(r["best"])), Vector2(316, y), 1, col)
		y += 14.0
	var note := ""
	if conn_lost != "":
		note = conn_lost
	elif peer_left:
		note = "EL RIVAL SE FUE"
	elif rival_wants_again and not waiting_again:
		note = "EL RIVAL QUIERE LA REVANCHA!"
	elif waiting_again:
		note = "ESPERANDO AL RIVAL..."
	if note != "":
		PixelFont.draw_text_centered(ci, note, 240, 208, 1, Pal.CYAN)
	ui.draw(ci)
