extends SceneTree
## Connects to a running server, creates a room and joins it with a second
## client, then waits for both "start" messages. Used by CI against the
## Docker image:  godot --headless --path . --script res://tests/net_client_check.gd -- --url=ws://127.0.0.1:9080

var c1: NetClient
var c2: NetClient
var code := ""
var started := 0
var t := 0.0


func _initialize() -> void:
	var url := "ws://127.0.0.1:9080"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--url="):
			url = a.substr(6)
	print("connecting to ", url)
	c1 = NetClient.new()
	c2 = NetClient.new()
	root.add_child(c1)
	root.add_child(c2)
	c1.message.connect(func(m: Dictionary) -> void:
		if m.get("t") == "room":
			code = str(m["code"])
			print("room code ", code)
			c2.open(url)
			c2.send({"t": "join", "code": code})
		elif m.get("t") == "start":
			started += 1)
	c2.message.connect(func(m: Dictionary) -> void:
		if m.get("t") == "start":
			started += 1)
	c1.open(url)
	c1.send({"t": "create", "laps": 1})


func _process(delta: float) -> bool:
	t += delta
	if started >= 2:
		print("REMOTE SERVER OK")
		quit(0)
		return true
	if t > 60.0:
		print("REMOTE SERVER CHECK FAILED")
		quit(1)
		return true
	return false
