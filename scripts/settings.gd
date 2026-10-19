extends Node2D
## Online server settings: lets the player type the server URL and test it.

var ui := Ui.new()
var edit: LineEdit
var status := ""
var status_col := Pal.WHITE
var _layer: Node2D
var _testing := false


func _ready() -> void:
	add_child(TrackView.overview(Game.track))
	_layer = Node2D.new()
	_layer.draw.connect(_draw_layer)
	add_child(_layer)
	var cl := CanvasLayer.new()
	add_child(cl)
	edit = LineEdit.new()
	edit.position = Vector2(84, 92)
	edit.size = Vector2(312, 18)
	edit.text = Game.server_url
	edit.placeholder_text = "wss://tu-servidor.onrender.com"
	edit.add_theme_font_size_override("font_size", 9)
	edit.select_all_on_focus = true
	cl.add_child(edit)
	ui.add("test", Rect2(84, 124, 150, 18), "GUARDAR Y PROBAR", Pal.LIGHT_GREEN)
	ui.add("reset", Rect2(246, 124, 150, 18), "POR DEFECTO", Pal.LIGHT_GREY)
	ui.add("back", Rect2(190, 214, 100, 18), "VOLVER", Pal.LIGHT_RED)
	Game.net.opened.connect(_on_opened)
	Game.net.closed.connect(_on_closed)


func _exit_tree() -> void:
	Game.net.opened.disconnect(_on_opened)
	Game.net.closed.disconnect(_on_closed)


func _save() -> void:
	Game.server_url = edit.text.strip_edges()
	Game.save_settings()


func _input(event: InputEvent) -> void:
	var id := ui.handle(event)
	if id != "":
		_on_button(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_button("back")


func _on_button(id: String) -> void:
	match id:
		"test":
			_save()
			edit.release_focus()
			if Game.net.open(Game.server_url) != OK:
				status = "URL INVALIDA (USA WS:// O WSS://)"
				status_col = Pal.LIGHT_RED
			else:
				_testing = true
				status = "PROBANDO CONEXION..."
				status_col = Pal.WHITE
		"reset":
			edit.text = NetConfig.DEFAULT_SERVER_URL
			_save()
			status = "URL POR DEFECTO GUARDADA"
			status_col = Pal.WHITE
		"back":
			_save()
			Game.net.close()
			Game.goto("menu")


func _on_opened() -> void:
	if _testing:
		_testing = false
		status = "CONEXION OK! SERVIDOR ACTIVO"
		status_col = Pal.LIGHT_GREEN
		Game.net.close()


func _on_closed(reason: String) -> void:
	if _testing:
		_testing = false
		status = reason
		status_col = Pal.LIGHT_RED


func _process(_delta: float) -> void:
	_layer.queue_redraw()


func _draw_layer() -> void:
	var ci := _layer
	ci.draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.55))
	Ui.draw_panel(ci, Rect2(70, 20, 340, 230), Color(0, 0, 0, 0.88), Pal.LIGHT_BLUE)
	PixelFont.draw_text_centered(ci, "SERVIDOR ONLINE", 240, 30, 2, Pal.YELLOW)
	PixelFont.draw_text_centered(ci, "DIRECCION DEL SERVIDOR (WEBSOCKET):", 240, 76, 1, Pal.WHITE)
	PixelFont.draw_text_centered(ci, status, 240, 156, 1, status_col)
	PixelFont.draw_text_centered(ci, "LOS DOS JUGADORES DEBEN USAR", 240, 180, 1, Pal.LIGHT_GREY)
	PixelFont.draw_text_centered(ci, "EL MISMO SERVIDOR", 240, 190, 1, Pal.LIGHT_GREY)
	ui.draw(ci)
