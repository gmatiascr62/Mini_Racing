class_name Ui
extends RefCounted
## Small retro UI toolkit: pixel panels and touch buttons.

var items: Array = []
var _pressed := ""
var _touch := -1


func clear() -> void:
	items.clear()
	_pressed = ""
	_touch = -1


func add(id: String, rect: Rect2, text: String, accent: Color = Pal.CYAN) -> void:
	items.append({"id": id, "rect": rect, "text": text, "accent": accent})


## Returns the id of the button that was activated by this event, or "".
func handle(event: InputEvent) -> String:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var hit := _hit(t.position)
			if hit != "":
				_pressed = hit
				_touch = t.index
		elif t.index == _touch:
			var id := _pressed
			_pressed = ""
			_touch = -1
			if id != "" and _hit(t.position) == id:
				Sfx.play("click", -10.0)
				return id
	return ""


func _hit(p: Vector2) -> String:
	for it in items:
		var r: Rect2 = it["rect"]
		if r.grow(3).has_point(p):
			return it["id"]
	return ""


func draw(ci: CanvasItem) -> void:
	for it in items:
		draw_button(ci, it["rect"], it["text"], it["id"] == _pressed, it["accent"])


static func draw_panel(ci: CanvasItem, r: Rect2, fill: Color = Color(0, 0, 0, 0.82), border: Color = Pal.LIGHT_BLUE) -> void:
	ci.draw_rect(r, fill)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), border)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)), border)
	ci.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), border)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 2, 0), Vector2(2, r.size.y)), border)


static func draw_button(ci: CanvasItem, r: Rect2, text: String, pressed: bool, accent: Color) -> void:
	var off := Vector2(1, 1) if pressed else Vector2.ZERO
	if not pressed:
		ci.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(0, 0, 0, 0.6))
	var face := accent.darkened(0.55) if not pressed else accent.darkened(0.25)
	draw_panel(ci, Rect2(r.position + off, r.size), face, accent)
	var scale := 1
	PixelFont.draw_text_centered(ci, text, r.position.x + off.x + r.size.x / 2.0, r.position.y + off.y + floorf((r.size.y - 7 * scale) / 2.0), scale, Pal.WHITE, Color(0, 0, 0, 0.8))


static func format_time(t: float) -> String:
	if t <= 0.0:
		return "--:--.-"
	var m := int(t) / 60
	var s := t - m * 60
	return "%d:%04.1f" % [m, s]
