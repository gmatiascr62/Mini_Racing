extends SceneTree
## Headless test suite. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Covers the track, physics/AI over full races and the online
## client/server flow over real WebSocket connections on localhost.

const PORT := 19080

var failures: Array = []
var server: RaceServer
var c1: NetClient
var c2: NetClient
var log1: Array = []
var log2: Array = []
var phase := "init"
var elapsed := 0.0
var phase_time := 0.0
var code := ""
var last_snap1: Dictionary = {}
var last_snap2: Dictionary = {}
var seq1 := 0
var seq2 := 0
var end1: Array = []
var end2: Array = []
var races_done := 0
var track: Track


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


func _initialize() -> void:
	for id in Track.IDS:
		track = Track.new(id)
		print("######## track: %s ########" % id)
		test_track()
		test_offline_race(false)
		test_offline_race(true)
	test_levels()
	# The online test races on Monza to cover track selection over the network.
	track = Track.new("monza")
	print("== online (server + 2 clients over WebSocket) ==")
	server = RaceServer.new()
	server.verbose = false
	root.add_child(server)
	check(server.start(PORT) == OK, "server listens on port %d" % PORT)
	c1 = NetClient.new()
	c2 = NetClient.new()
	root.add_child(c1)
	root.add_child(c2)
	c1.message.connect(func(m: Dictionary) -> void: _on_msg(1, m))
	c2.message.connect(func(m: Dictionary) -> void: _on_msg(2, m))
	c1.open("ws://127.0.0.1:%d" % PORT)
	c1.send({"t": "create", "v": NetConfig.PROTOCOL, "laps": 1, "track": "monza", "level": 0})
	_set_phase("wait_room")


func test_track() -> void:
	print("== track ==")
	check(track.length > 1800.0 and track.length < 3000.0, "track length %.0f px" % track.length)
	var inside := true
	for p in track.pts:
		if p.x < 30 or p.x > Track.WORLD.x - 30 or p.y < 30 or p.y > Track.WORLD.y - 30:
			inside = false
	check(inside, "whole circuit fits inside the fenced world")
	var grid_ok := true
	for k in range(RaceSim.CAR_COUNT):
		var slot := track.grid_slot(k)
		var loc := track.locate(slot[0])
		if not track.is_on_road(loc.y):
			grid_ok = false
	check(grid_ok, "all grid slots on asphalt")
	var clear := true
	for p in track.scenery["trees"]:
		if absf(track.locate(p).y) < track.half_width + Track.KERB_WIDTH + 4.0:
			clear = false
	for r in track.scenery["stands"] + [track.scenery["pit"]]:
		var rect: Rect2 = r
		for q in [rect.position, rect.end, rect.get_center(), Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y)]:
			if absf(track.locate(q).y) < track.half_width + Track.KERB_WIDTH:
				clear = false
	check(clear, "trees, grandstands and pits stay off the road")


func test_offline_race(human_bots: bool) -> void:
	var laps := RaceSim.DEFAULT_LAPS
	print("== full %d-lap race (%s) ==" % [laps, "2 steering bots + 4 CPU" if human_bots else "6 computer drivers"])
	var sim := RaceSim.new(track)
	sim.setup(RaceSim.make_specs(["J1", "J2"]), laps)
	if not human_bots:
		for c in sim.cars:
			c.autopilot = true
	var offroad := {}
	var respawns := 0
	var crashes := 0
	var ticks := 0
	while sim.state != RaceSim.STATE_FINISHED and ticks < 60 * 300:
		var inputs := {}
		for c in sim.cars:
			if c.human and not c.autopilot:
				inputs[c.id] = bot_steer(c.pos, c.heading, c.speed(), c.s, -5.0 if c.id % 2 == 0 else 5.0)
		sim.step(inputs)
		ticks += 1
		for c in sim.cars:
			if not c.on_road:
				offroad[c.id] = offroad.get(c.id, 0) + 1
		for e in sim.events:
			if e["type"] == "respawn":
				respawns += 1
			elif e["type"] == "crash":
				crashes += 1
	check(sim.state == RaceSim.STATE_FINISHED, "race finished in %.1f s" % sim.time)
	var all_fin := true
	for r in sim.results():
		print("     %d %-8s %s best %s off-track %.1fs" % [r["pos"], r["name"], ft(r["time"]), ft(r["best"]), offroad.get(r["id"], 0) / 60.0])
		if not r["finished"]:
			all_fin = false
	check(all_fin, "all six cars completed %d laps" % laps)
	check(respawns <= 2, "cars do not get stuck (respawns: %d)" % respawns)
	var max_time := track.length * laps / 45.0
	check(sim.time < max_time, "no traffic jams (race %.0f s, limit %.0f s)" % [sim.time, max_time])
	var max_off := 0.0
	for id in offroad:
		max_off = maxf(max_off, offroad[id] / 60.0)
	check(max_off < 4.0, "no car spends long on the grass (max %.1fs)" % max_off)
	check(crashes > 0, "cars touch each other (%d contacts)" % crashes)


func ft(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


func test_levels() -> void:
	print("== difficulty levels (CPU-only race) ==")
	var winners: Array = []
	for lvl in range(RaceSim.LEVEL_NAMES.size()):
		var sim := RaceSim.new(Track.new())
		sim.setup(RaceSim.make_specs([]), 3, lvl)
		var ticks := 0
		while sim.state != RaceSim.STATE_FINISHED and ticks < 60 * 300:
			sim.step({})
			ticks += 1
		var best: float = sim.results()[0]["time"]
		print("     %-8s winner %s" % [RaceSim.LEVEL_NAMES[lvl], ft(best)])
		winners.append(best)
	check(winners[0] > winners[1] and winners[1] > winners[2], "CPUs are slower on easier levels")


## Bang-bang steering bot (only full left / straight / full right, like the
## touch buttons). Each bot keeps its own lane, like two players side by side.
func bot_steer(pos: Vector2, heading: float, speed: float, s: float, lane: float = 0.0) -> float:
	var look := 16.0 + maxf(speed, 0.0) * 0.3
	var t := track.point_at(s + look) + track.normal_at(s + look) * lane
	var diff := wrapf((t - pos).angle() - heading, -PI, PI)
	if diff > 0.06:
		return 1.0
	if diff < -0.06:
		return -1.0
	return 0.0


func _on_msg(who: int, m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	if t != "s":
		(log1 if who == 1 else log2).append(m)
	match t:
		"room":
			if who == 1:
				code = str(m["code"])
		"s":
			if who == 1:
				last_snap1 = m
			else:
				last_snap2 = m
		"end":
			if who == 1:
				end1 = m["res"]
			else:
				end2 = m["res"]


func _has(log: Array, t: String) -> bool:
	for m in log:
		if m.get("t", "") == t:
			return true
	return false


func _set_phase(p: String) -> void:
	phase = p
	phase_time = 0.0


func _send_input(who: int) -> void:
	var snap := last_snap1 if who == 1 else last_snap2
	if snap.is_empty() or int(snap["st"]) != RaceSim.STATE_RACING:
		return
	var car_id := RaceSim.human_car_id(who - 1)
	var row: Array = snap["c"][car_id]
	var pos := Vector2(row[0], row[1]) / 10.0
	var heading := float(row[2]) / 1000.0
	var vel := Vector2(row[3], row[4]) / 10.0
	var s := track.locate(pos).x
	var steer := bot_steer(pos, heading, vel.dot(Vector2.from_angle(heading)), s)
	if who == 1:
		seq1 += 1
		c1.send({"t": "in", "q": seq1, "s": steer})
	else:
		seq2 += 1
		c2.send({"t": "in", "q": seq2, "s": steer})


func _physics_process(delta: float) -> bool:
	elapsed += delta
	phase_time += delta
	if phase == "race1" or phase == "race2":
		_send_input(1)
		_send_input(2)
	match phase:
		"wait_room":
			if code != "":
				check(code.length() == 4 and code.is_valid_int(), "room created with 4-digit code %s" % code)
				c2.open("ws://127.0.0.1:%d" % PORT)
				c2.send({"t": "join", "code": "0000" if code != "0000" else "0001"})
				_set_phase("bad_join")
		"bad_join":
			if _has(log2, "error"):
				check(true, "joining a wrong code is rejected")
				c2.send({"t": "join", "code": code})
				_set_phase("wait_start")
		"wait_start":
			if _has(log1, "start") and _has(log2, "start"):
				check(true, "both players receive race start")
				var s1: Dictionary = log1.filter(func(m): return m["t"] == "start")[0]
				var s2: Dictionary = log2.filter(func(m): return m["t"] == "start")[0]
				check(int(s1["car"]) != int(s2["car"]), "players drive different cars (%d, %d)" % [s1["car"], s2["car"]])
				check((s1["names"] as Array).size() == 6, "6 cars in the race")
				check(str(s1.get("track", "")) == "monza" and str(s2.get("track", "")) == "monza", "both players race on the track chosen by the creator")
				check(int(s1.get("level", -1)) == 0 and int(s2.get("level", -1)) == 0, "both players get the difficulty chosen by the creator")
				_set_phase("race1")
		"race1", "race2":
			if not end1.is_empty() and not end2.is_empty():
				check(JSON.stringify(end1) == JSON.stringify(end2), "both players get the same final classification")
				var humans_fin := 0
				for r in end1:
					if r["human"] and r["finished"]:
						humans_fin += 1
				check(humans_fin == 2, "both online players finished the race")
				check(not last_snap1.is_empty() and (last_snap1["c"] as Array).size() == 6, "snapshots carry all 6 cars")
				check(int(last_snap1.get("a", 0)) > 0, "server acknowledges player inputs (ack %d)" % int(last_snap1.get("a", 0)))
				races_done += 1
				if phase == "race1":
					end1 = []
					end2 = []
					log1.clear()
					log2.clear()
					c1.send({"t": "again"})
					c2.send({"t": "again"})
					_set_phase("wait_rematch")
				else:
					c2.close()
					_set_phase("wait_peer_left")
		"wait_rematch":
			if _has(log1, "start") and _has(log2, "start"):
				check(true, "rematch starts when both ask for it")
				_set_phase("race2")
		"wait_peer_left":
			if _has(log1, "peer_left"):
				check(true, "remaining player is told when the rival disconnects")
				_finish()
				return true
	if phase_time > 90.0:
		check(false, "online phase '%s' timed out" % phase)
		_finish()
		return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
