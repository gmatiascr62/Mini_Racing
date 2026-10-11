extends Node
## Global state shared between screens.

const SETTINGS_PATH := "user://settings.cfg"

var track: Track
var mode := "offline"           # "offline" or "online"
var lobby_action := "create"    # "create" or "join"
var server_url := NetConfig.DEFAULT_SERVER_URL
var net: NetClient
## Online race info received from the server.
var online_car_id := 2
var online_names: Array = []
var online_code := ""
var online_laps := RaceSim.DEFAULT_LAPS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	track = Track.new()
	_load_settings()
	net = NetClient.new()
	net.name = "NetClient"
	add_child(net)
	var args := OS.get_cmdline_user_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/server.tscn")
		return
	# Debug helpers (desktop only): --scene=race --autodrive --shot=/tmp/a.png --frames=300
	for a in args:
		if a.begins_with("--scene="):
			get_tree().change_scene_to_file.call_deferred("res://scenes/%s.tscn" % a.substr(8))
		elif a == "--autodrive":
			autodrive = true
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--lobby="):
			lobby_action = a.substr(8)
		elif a.begins_with("--code="):
			debug_code = a.substr(7)
		elif a.begins_with("--url="):
			server_url = a.substr(6)


var autodrive := false
var debug_code := ""
var _shot_path := ""
var _shot_frames := 120
var _frame := 0


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_frame += 1
	if _frame == _shot_frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("screenshot saved: ", _shot_path)
		get_tree().quit()


func apply_start(msg: Dictionary) -> void:
	mode = "online"
	online_car_id = int(msg.get("car", 2))
	online_names = msg.get("names", [])
	online_laps = int(msg.get("laps", RaceSim.DEFAULT_LAPS))
	online_code = str(msg.get("code", online_code))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		server_url = cfg.get_value("net", "server_url", NetConfig.DEFAULT_SERVER_URL)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server_url", server_url)
	cfg.save(SETTINGS_PATH)


func goto(scene: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene)
