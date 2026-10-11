extends Node2D
## Main menu with an attract-mode race running in the background.

var sim: RaceSim
var ui := Ui.new()
var t := 0.0
var _layer: Node2D


func _ready() -> void:
	Sfx.stop_all()
	add_child(TrackView.new(Game.track))
	sim = RaceSim.new(Game.track)
	sim.setup(RaceSim.make_specs([]), 99)
	sim.countdown = 0.01
	var y := 112
	ui.add("cpu", Rect2(150, y, 180, 20), "CARRERA VS CPU", Pal.LIGHT_GREEN)
	ui.add("create", Rect2(150, y + 26, 180, 20), "CREAR PARTIDA ONLINE", Pal.CYAN)
	ui.add("join", Rect2(150, y + 52, 180, 20), "UNIRSE A PARTIDA", Pal.CYAN)
	ui.add("server", Rect2(150, y + 78, 180, 20), "SERVIDOR ONLINE", Pal.LIGHT_GREY)
	_layer = Node2D.new()
	_layer.draw.connect(_draw_layer)
	add_child(_layer)


func _physics_process(delta: float) -> void:
	t += delta
	sim.step()
	_layer.queue_redraw()


func _input(event: InputEvent) -> void:
	var id := ui.handle(event)
	if id != "":
		_on_button(id)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		_on_button("cpu")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _on_button(id: String) -> void:
	match id:
		"cpu":
			Game.mode = "offline"
			Game.goto("race")
		"create":
			Game.lobby_action = "create"
			Game.goto("lobby")
		"join":
			Game.lobby_action = "join"
			Game.goto("lobby")
		"server":
			Game.goto("settings")


func _draw_layer() -> void:
	var ci := _layer
	for c in sim.cars:
		var frames := CarSprites.frames_for(RaceSim.car_color(c.id))
		var at: Vector2 = (c.pos - Vector2(8, 8)).round()
		ci.draw_texture(frames[CarSprites.frame_index(c.heading)], at + Vector2(1, 2), Color(0, 0, 0, 0.35))
		ci.draw_texture(frames[CarSprites.frame_index(c.heading)], at)
	ci.draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.45))
	# Title with a C64-style raster bar behind it.
	var bars := [Pal.BLUE, Pal.LIGHT_BLUE, Pal.CYAN, Pal.WHITE, Pal.CYAN, Pal.LIGHT_BLUE, Pal.BLUE]
	for i in range(bars.size()):
		ci.draw_rect(Rect2(0, 22 + i * 3 + int(sin(t * 2.0) * 2.0), 480, 3), bars[i])
	ci.draw_rect(Rect2(0, 44, 480, 42), Color(0, 0, 0, 0.75))
	PixelFont.draw_text_centered(ci, "MINI RACING", 240, 48, 5, Pal.YELLOW, Pal.RED)
	PixelFont.draw_text_centered(ci, "GRAN PREMIO RETRO - 5 VUELTAS", 240, 90, 1, Pal.WHITE, Pal.BLACK)
	ui.draw(ci)
	if fmod(t, 1.2) < 0.8:
		PixelFont.draw_text_centered(ci, "2 JUGADORES ONLINE + 4 CPU", 240, 222, 1, Pal.LIGHT_GREEN, Pal.BLACK)
	PixelFont.draw_text_centered(ci, "DOBLA CON LOS BOTONES DE LAS ESQUINAS", 240, 236, 1, Pal.LIGHT_GREY, Pal.BLACK)
	PixelFont.draw_text(ci, "V1.0", Vector2(450, 258), 1, Pal.GREY)
