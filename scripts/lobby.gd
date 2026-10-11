extends Node2D
## Online lobby: create a room (shows its code) or join one by typing the code.

var ui := Ui.new()
var state := ""          # keypad, connecting, waiting, joined, error
var code := ""
var info := ""
var t := 0.0
var _layer: Node2D


func _ready() -> void:
	var bg := TrackView.new(Game.track)
	add_child(bg)
	_layer = Node2D.new()
	_layer.draw.connect(_draw_layer)
	add_child(_layer)
	Game.net.message.connect(_on_message)
	Game.net.closed.connect(_on_closed)
	if Game.lobby_action == "create":
		_connect_and_send({"t": "create", "v": NetConfig.PROTOCOL, "laps": RaceSim.DEFAULT_LAPS, "track": Game.track_id})
	else:
		_set_state("keypad")
		if Game.debug_code != "":
			code = Game.debug_code
			_on_button("ok")


func _exit_tree() -> void:
	if Game.net.message.is_connected(_on_message):
		Game.net.message.disconnect(_on_message)
	if Game.net.closed.is_connected(_on_closed):
		Game.net.closed.disconnect(_on_closed)


func _connect_and_send(msg: Dictionary) -> void:
	var err := Game.net.open(Game.server_url)
	if err != OK:
		_fail("URL DE SERVIDOR INVALIDA")
		return
	Game.net.send(msg)
	_set_state("connecting")


func _set_state(s: String) -> void:
	state = s
	ui.clear()
	match s:
		"keypad":
			for i in range(10):
				var d := (i + 1) % 10
				var col := i % 3
				var row := i / 3
				var r := Rect2(176 + col * 44, 96 + row * 26, 38, 20)
				if d == 0:
					r = Rect2(176 + 44, 96 + 3 * 26, 38, 20)
				ui.add(str(d), r, str(d), Pal.CYAN)
			ui.add("del", Rect2(176, 96 + 3 * 26, 38, 20), "<", Pal.LIGHT_RED)
			ui.add("ok", Rect2(176 + 88, 96 + 3 * 26, 38, 20), "OK", Pal.LIGHT_GREEN)
			ui.add("back", Rect2(190, 210, 100, 18), "VOLVER", Pal.LIGHT_GREY)
		"error":
			ui.add("retry", Rect2(132, 190, 100, 18), "REINTENTAR", Pal.LIGHT_GREEN)
			ui.add("back", Rect2(248, 190, 100, 18), "VOLVER", Pal.LIGHT_GREY)
		_:
			ui.add("back", Rect2(190, 210, 100, 18), "CANCELAR", Pal.LIGHT_RED)


func _fail(msg: String) -> void:
	info = msg
	Game.net.close()
	_set_state("error")


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"room":
			code = str(msg.get("code", ""))
			Game.online_code = code
			_set_state("waiting" if int(msg.get("slot", 0)) == 0 else "joined")
		"start":
			Game.apply_start(msg)
			Game.goto("race")
		"error":
			_fail(str(msg.get("msg", "ERROR")))


func _on_closed(reason: String) -> void:
	if state != "error":
		_fail(reason)


func _input(event: InputEvent) -> void:
	var id := ui.handle(event)
	if id == "" and event is InputEventKey and event.pressed and not event.echo and state == "keypad":
		var k: int = event.keycode
		if k >= KEY_0 and k <= KEY_9:
			id = str(k - KEY_0)
		elif k == KEY_BACKSPACE:
			id = "del"
		elif k == KEY_ENTER:
			id = "ok"
	if id != "":
		_on_button(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_button("back")


func _on_button(id: String) -> void:
	match id:
		"back":
			Game.net.send({"t": "leave"})
			Game.net.close()
			Game.goto("menu")
		"retry":
			if Game.lobby_action == "create":
				_connect_and_send({"t": "create", "v": NetConfig.PROTOCOL, "laps": RaceSim.DEFAULT_LAPS, "track": Game.track_id})
			else:
				_set_state("keypad")
		"del":
			code = code.substr(0, maxi(code.length() - 1, 0))
		"ok":
			if code.length() == 4:
				_connect_and_send({"t": "join", "v": NetConfig.PROTOCOL, "code": code})
		_:
			if state == "keypad" and id.is_valid_int() and code.length() < 4:
				code += id


func _process(delta: float) -> void:
	t += delta
	_layer.queue_redraw()


func _draw_layer() -> void:
	var ci := _layer
	ci.draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.55))
	Ui.draw_panel(ci, Rect2(70, 20, 340, 230), Color(0, 0, 0, 0.88), Pal.LIGHT_BLUE)
	var title := "CREAR PARTIDA" if Game.lobby_action == "create" else "UNIRSE A PARTIDA"
	PixelFont.draw_text_centered(ci, title, 240, 30, 2, Pal.YELLOW)
	var dots := ".".repeat(int(t * 3.0) % 4)
	match state:
		"keypad":
			PixelFont.draw_text_centered(ci, "INGRESA EL CODIGO DE SALA", 240, 52, 1, Pal.WHITE)
			var shown := ""
			for i in range(4):
				shown += code[i] if i < code.length() else "_"
			PixelFont.draw_text_centered(ci, shown, 240, 66, 3, Pal.CYAN)
		"connecting":
			PixelFont.draw_text_centered(ci, "CONECTANDO" + dots, 240, 90, 2, Pal.WHITE)
			PixelFont.draw_text_centered(ci, Game.server_url, 240, 120, 1, Pal.LIGHT_GREY)
			PixelFont.draw_text_centered(ci, "SI EL SERVIDOR ESTABA DORMIDO", 240, 150, 1, Pal.LIGHT_GREY)
			PixelFont.draw_text_centered(ci, "PUEDE TARDAR HASTA UN MINUTO", 240, 160, 1, Pal.LIGHT_GREY)
		"waiting":
			PixelFont.draw_text_centered(ci, "CODIGO DE SALA", 240, 60, 1, Pal.WHITE)
			PixelFont.draw_text_centered(ci, code, 240, 76, 6, Pal.YELLOW, Pal.RED)
			PixelFont.draw_text_centered(ci, "PASALE ESTE CODIGO A TU RIVAL", 240, 134, 1, Pal.WHITE)
			PixelFont.draw_text_centered(ci, "ESPERANDO AL OTRO JUGADOR" + dots, 240, 154, 1, Pal.CYAN)
			PixelFont.draw_text_centered(ci, "LA CARRERA EMPIEZA SOLA AL UNIRSE", 240, 174, 1, Pal.LIGHT_GREY)
		"joined":
			PixelFont.draw_text_centered(ci, "SALA " + code, 240, 80, 3, Pal.YELLOW)
			PixelFont.draw_text_centered(ci, "CONECTADO! PREPARANDO LA LARGADA" + dots, 240, 130, 1, Pal.CYAN)
		"error":
			PixelFont.draw_text_centered(ci, "ERROR", 240, 80, 3, Pal.LIGHT_RED)
			PixelFont.draw_text_centered(ci, info, 240, 120, 1, Pal.WHITE)
			PixelFont.draw_text_centered(ci, "REVISA LA URL EN MENU > SERVIDOR ONLINE", 240, 140, 1, Pal.LIGHT_GREY)
	ui.draw(ci)
