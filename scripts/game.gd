extends Node
## Global state shared between screens.

const SETTINGS_PATH := "user://settings.cfg"

var track: Track
var track_id := "indy"
## CPU difficulty: 0 FACIL, 1 NORMAL, 2 DIFICIL.
var level := RaceSim.DEFAULT_LEVEL
var _tracks: Dictionary = {}
var mode := "offline"           # "offline" or "online"
var lobby_action := "create"    # "create" or "join"
var server_url := NetConfig.DEFAULT_SERVER_URL
var net: NetClient
## Online race info received from the server.
var online_car_id := 2
var online_names: Array = []
var online_code := ""
var online_laps := RaceSim.DEFAULT_LAPS
var online_level := RaceSim.DEFAULT_LEVEL


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	set_track(track_id)
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
		elif a.begins_with("--track="):
			set_track(a.substr(8))
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
	online_level = int(msg.get("level", RaceSim.DEFAULT_LEVEL))
	online_code = str(msg.get("code", online_code))
	set_track(str(msg.get("track", Track.IDS[0])), false)


## Selects the current track (tracks are built once and cached).
func set_track(id: String, remember: bool = true) -> void:
	if not id in Track.IDS:
		id = Track.IDS[0]
	if not _tracks.has(id):
		_tracks[id] = Track.new(id)
	track = _tracks[id]
	if remember:
		track_id = id


func next_track() -> void:
	var i := Track.IDS.find(track_id)
	set_track(Track.IDS[(i + 1) % Track.IDS.size()])
	save_settings()


func next_level() -> void:
	level = (level + 1) % RaceSim.LEVEL_NAMES.size()
	save_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		server_url = cfg.get_value("net", "server_url", NetConfig.DEFAULT_SERVER_URL)
		track_id = str(cfg.get_value("game", "track", Track.IDS[0]))
		level = clampi(int(cfg.get_value("game", "level", RaceSim.DEFAULT_LEVEL)), 0, RaceSim.LEVEL_NAMES.size() - 1)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server_url", server_url)
	cfg.set_value("game", "track", track_id)
	cfg.set_value("game", "level", level)
	cfg.save(SETTINGS_PATH)


func goto(scene: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene)
