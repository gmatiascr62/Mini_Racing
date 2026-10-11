class_name RaceServer
extends Node
## Authoritative Mini Racing server. Run headless:
##   godot --headless --path . -- --server [--port=9080]
## It hosts any number of private rooms. Each room runs its own RaceSim with
## 2 human players and 4 CPU cars and streams snapshots to both players.

const WAIT_ROOM_TTL := 900.0
const RESULTS_ROOM_TTL := 300.0
const MAX_INPUT_QUEUE := 30
const MAX_PEERS := 400

class Peer:
	var id := 0
	var ws: WebSocketPeer
	var room_code := ""
	var slot := -1
	var inputs: Array = []
	var steer := 0.0
	var ack := 0
	var again := false


class Room:
	var code := ""
	var sim: RaceSim
	var players := [0, 0]   # peer ids per human slot (0 = empty)
	var state := "waiting"   # waiting, racing, results
	var tick := 0
	var laps := RaceSim.DEFAULT_LAPS
	var track_id := "gp"
	var level := RaceSim.DEFAULT_LEVEL
	var idle_time := 0.0
	var ended_sent := false


var port := NetConfig.DEFAULT_PORT
var tcp := TCPServer.new()
var peers: Dictionary = {}
var rooms: Dictionary = {}
var tracks: Dictionary = {}
var _next_peer := 1
var _rng := RandomNumberGenerator.new()
var verbose := true


func _ready() -> void:
	_rng.randomize()
	for id in Track.IDS:
		tracks[id] = Track.new(id)
	var port_from_args := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
			port_from_args = true
	var env_port := OS.get_environment("PORT")
	if env_port != "" and not port_from_args:
		port = int(env_port)
	if get_tree().current_scene == self:
		Engine.max_fps = 60
		start(port)


func start(p_port: int) -> Error:
	port = p_port
	if tcp.is_listening():
		return OK
	var err := tcp.listen(port, "*")
	if err != OK:
		push_error("Mini Racing server: cannot listen on port %d (%s)" % [port, error_string(err)])
	else:
		_log("Mini Racing server listening on port %d" % port)
	return err


func _log(t: String) -> void:
	if verbose:
		print("[server] ", t)


func _physics_process(_delta: float) -> void:
	_accept()
	_poll_peers()
	for code in rooms.keys():
		_tick_room(rooms[code], RaceSim.TICK)


func _accept() -> void:
	while tcp.is_connection_available():
		var conn := tcp.take_connection()
		if peers.size() >= MAX_PEERS:
			conn.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 16
		ws.outbound_buffer_size = 1 << 18
		if ws.accept_stream(conn) != OK:
			continue
		var p := Peer.new()
		p.id = _next_peer
		_next_peer += 1
		p.ws = ws
		peers[p.id] = p


func _poll_peers() -> void:
	for id in peers.keys():
		var p: Peer = peers[id]
		p.ws.poll()
		var st := p.ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			var budget := 200
			while p.ws.get_available_packet_count() > 0 and budget > 0:
				budget -= 1
				var pkt := p.ws.get_packet()
				if pkt.size() > 2048:
					continue
				var msg = JSON.parse_string(pkt.get_string_from_utf8())
				if msg is Dictionary:
					_handle(p, msg)
		elif st == WebSocketPeer.STATE_CLOSED:
			_drop(p)


func _send(p: Peer, msg: Dictionary) -> void:
	if p.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		p.ws.send_text(JSON.stringify(msg))


func _handle(p: Peer, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"ping":
			_send(p, {"t": "pong", "c": msg.get("c", 0)})
		"create":
			if p.room_code != "":
				_leave_room(p)
			var room := Room.new()
			room.code = _new_code()
			var tid := str(msg.get("track", "gp"))
			room.track_id = tid if tracks.has(tid) else "gp"
			room.level = clampi(int(msg.get("level", RaceSim.DEFAULT_LEVEL)), 0, RaceSim.LEVEL_NAMES.size() - 1)
			room.laps = clampi(int(msg.get("laps", RaceSim.DEFAULT_LAPS)), 1, RaceSim.DEFAULT_LAPS)
			room.players[0] = p.id
			rooms[room.code] = room
			p.room_code = room.code
			p.slot = 0
			_send(p, {"t": "room", "code": room.code, "slot": 0})
			_log("room %s created by peer %d" % [room.code, p.id])
		"join":
			var code := str(msg.get("code", "")).strip_edges()
			if not rooms.has(code):
				_send(p, {"t": "error", "msg": "SALA NO ENCONTRADA"})
				return
			var room: Room = rooms[code]
			if room.state != "waiting" or room.players[1] != 0:
				_send(p, {"t": "error", "msg": "LA SALA ESTA LLENA"})
				return
			if p.room_code != "":
				_leave_room(p)
			room.players[1] = p.id
			p.room_code = code
			p.slot = 1
			_send(p, {"t": "room", "code": code, "slot": 1})
			_log("peer %d joined room %s" % [p.id, code])
			_start_race(room)
		"in":
			if p.room_code == "" or p.inputs.size() >= MAX_INPUT_QUEUE:
				return
			p.inputs.append([int(msg.get("q", 0)), clampf(float(msg.get("s", 0.0)), -1.0, 1.0)])
		"again":
			if not rooms.has(p.room_code):
				return
			var room: Room = rooms[p.room_code]
			if room.state != "results":
				return
			p.again = true
			var ready := true
			for pid in room.players:
				if pid != 0 and not (peers[pid] as Peer).again:
					ready = false
			if ready:
				_start_race(room)
			else:
				for pid in room.players:
					if pid != 0 and pid != p.id:
						_send(peers[pid], {"t": "again_req"})
		"leave":
			_leave_room(p)


func _new_code() -> String:
	for i in range(1000):
		var code := str(_rng.randi_range(1000, 9999))
		if not rooms.has(code):
			return code
	return str(_rng.randi_range(10000, 99999))


func _start_race(room: Room) -> void:
	var names: Array = []
	for slot in range(2):
		names.append(("J%d" % (slot + 1)) if room.players[slot] != 0 else "")
	room.sim = RaceSim.new(tracks[room.track_id])
	room.sim.setup(RaceSim.make_specs(names), room.laps, room.level)
	room.state = "racing"
	room.tick = 0
	room.idle_time = 0.0
	room.ended_sent = false
	var all_names: Array = []
	for c in room.sim.cars:
		all_names.append(c.name)
	for slot in range(2):
		var pid: int = room.players[slot]
		if pid == 0:
			continue
		var p: Peer = peers[pid]
		p.inputs.clear()
		p.steer = 0.0
		p.ack = 0
		p.again = false
		_send(p, {"t": "start", "code": room.code, "slot": slot, "car": RaceSim.human_car_id(slot), "names": all_names, "laps": room.laps, "track": room.track_id, "level": room.level})
	_log("room %s race started" % room.code)


func _tick_room(room: Room, dt: float) -> void:
	room.idle_time += dt
	if room.state == "waiting":
		if room.idle_time > WAIT_ROOM_TTL:
			_close_room(room)
		return
	if room.state == "results":
		if room.idle_time > RESULTS_ROOM_TTL:
			_close_room(room)
		return
	var sim := room.sim
	var inputs := {}
	for slot in range(2):
		var pid: int = room.players[slot]
		if pid == 0:
			continue
		var p: Peer = peers[pid]
		# Small jitter buffer: consume one input per tick, catch up if late.
		while p.inputs.size() > 6:
			p.inputs.pop_front()
		if sim.state == RaceSim.STATE_RACING and not p.inputs.is_empty():
			var inp: Array = p.inputs.pop_front()
			p.ack = inp[0]
			p.steer = inp[1]
		elif sim.state != RaceSim.STATE_RACING:
			p.inputs.clear()
		inputs[RaceSim.human_car_id(slot)] = p.steer
	sim.step(inputs)
	room.tick += 1
	var crashes: Array = []
	for e in sim.events:
		if e["type"] == "crash":
			var cp: Vector2 = e["pos"]
			crashes.append([int(cp.x), int(cp.y)])
	if room.tick % NetConfig.SNAPSHOT_EVERY == 0 or not crashes.is_empty():
		_broadcast_snapshot(room, crashes)
	if sim.state == RaceSim.STATE_FINISHED and not room.ended_sent:
		room.ended_sent = true
		room.state = "results"
		room.idle_time = 0.0
		var res := sim.results()
		for pid in room.players:
			if pid != 0:
				_send(peers[pid], {"t": "end", "res": res})
		_log("room %s race finished" % room.code)


static func encode_cars(sim: RaceSim) -> Array:
	var out: Array = []
	for c in sim.cars:
		var flags := (1 if c.skidding else 0) | (2 if c.on_road else 0) | (4 if c.finished else 0)
		out.append([
			int(round(c.pos.x * 10.0)), int(round(c.pos.y * 10.0)),
			int(round(c.heading * 1000.0)),
			int(round(c.vel.x * 10.0)), int(round(c.vel.y * 10.0)),
			int(round(c.progress * 10.0)), flags, c.laps_done,
			int(round(c.best_lap * 100.0)),
		])
	return out


func _broadcast_snapshot(room: Room, crashes: Array) -> void:
	var sim := room.sim
	var base := {
		"t": "s", "k": room.tick, "st": sim.state,
		"cd": int(round(sim.countdown * 100.0)), "tm": int(round(sim.time * 100.0)),
		"c": encode_cars(sim), "r": sim.standings(),
	}
	if not crashes.is_empty():
		base["ev"] = crashes
	for pid in room.players:
		if pid == 0:
			continue
		var p: Peer = peers[pid]
		base["a"] = p.ack
		_send(p, base)


func _leave_room(p: Peer) -> void:
	if not rooms.has(p.room_code):
		p.room_code = ""
		p.slot = -1
		return
	var room: Room = rooms[p.room_code]
	var slot := p.slot
	p.room_code = ""
	p.slot = -1
	if slot >= 0 and room.players[slot] == p.id:
		room.players[slot] = 0
	if room.players[0] == 0 and room.players[1] == 0:
		_close_room(room)
		return
	if room.state == "waiting":
		# The creator left before anyone joined.
		_close_room(room)
		return
	if room.state == "racing" and room.sim != null:
		var car: RaceSim.Car = room.sim.cars[RaceSim.human_car_id(slot)]
		car.autopilot = true
	for pid in room.players:
		if pid != 0:
			_send(peers[pid], {"t": "peer_left"})
	_log("peer %d left room %s" % [p.id, room.code])


func _close_room(room: Room) -> void:
	for pid in room.players:
		if pid != 0 and peers.has(pid):
			var p: Peer = peers[pid]
			p.room_code = ""
			p.slot = -1
			_send(p, {"t": "error", "msg": "LA SALA SE CERRO"})
	rooms.erase(room.code)
	_log("room %s closed" % room.code)


func _drop(p: Peer) -> void:
	_leave_room(p)
	peers.erase(p.id)
