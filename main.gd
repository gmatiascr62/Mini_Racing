extends Node2D

const W := 960.0
const H := 540.0
const CENTER := Vector2(480,270)
const OUTER := Vector2(402,224)
const INNER := Vector2(245,92)
const ROAD_HALF := 73.0
const COLORS := [Color("#f34b49"),Color("#4dabf7"),Color("#ffe067"),Color("#9ee870"),Color("#f7f7f7"),Color("#d38cf6")]
var cars: Array = []
var race_time := 0.0
var countdown := 3.0
var finished := false
var touch_left := false
var touch_right := false
var lap_goal := 5
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	_reset()
	queue_redraw()

func _reset() -> void:
	cars.clear()
	race_time = 0
	countdown = 3
	finished = false
	for i in range(6):
		var a = -PI/2.0 - 0.09 * (i % 3)
		var r = 1.0 + (i / 3) * 0.10
		var pos = CENTER + Vector2(cos(a) * (323 - (i / 3) * 19), sin(a) * (158 - (i / 3) * 15))
		# Place cars on upper straight, heading right
		pos = Vector2(345 + (i % 3) * 30, 132 + (i / 3) * 23)
		cars.append({"pos":pos,"angle":0.0,"speed":0.0,"laps":0,"progress":0.0,"last_progress":0.0,"name":("YOU" if i==0 else ("RIVAL" if i==1 else "CPU %d" % (i-1))),"done":false})
	queue_redraw()

func _process(delta: float) -> void:
	delta = min(delta,0.05)
	if countdown > 0:
		countdown -= delta
		queue_redraw()
		return
	if finished:
		return
	race_time += delta
	for i in range(cars.size()):
		_move_car(i,delta)
	_collisions()
	var all_finished = true
	for c in cars:
		if not c["done"]:
			all_finished = false
	finished = all_finished
	queue_redraw()

func _steer() -> float:
	var left = Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or touch_left
	var right = Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or touch_right
	return float(right) - float(left)

func _track_value(p:Vector2) -> float:
	# Signed distance to an elliptical circuit centerline; approximated in normalized coordinates.
	var q = p - CENTER
	var nx = q.x / 323.0
	var ny = q.y / 158.0
	return sqrt(nx*nx + ny*ny)

func _track_angle(p:Vector2) -> float:
	var v = p - CENTER
	var t = atan2(v.y/158.0,v.x/323.0)
	var tangent = Vector2(-323.0*sin(t),158.0*cos(t))
	return tangent.angle()

func _move_car(i:int,dt:float) -> void:
	var c:Dictionary = cars[i]
	if c["done"]:
		return
	var p:Vector2 = c["pos"]
	var on_road = abs(_track_value(p)-1.0) < 0.29
	var target_speed = 168.0 if on_road else 65.0
	if i >= 1:
		target_speed *= 0.86 + float(i)*0.018
	var control = _steer() if i == 0 else 0.0
	if i != 0:
		var ideal = _track_angle(p)
		var diff = wrapf(ideal-float(c["angle"]),-PI,PI)
		control = clamp(diff*2.2,-1.0,1.0)
		# CPU follows the road; challenge comes from different speeds and collisions.
	var velocity:float = c["speed"]
	velocity = move_toward(velocity,target_speed,94.0*dt)
	var turn_amount = control * 2.35 * dt
	c["angle"] = float(c["angle"]) + turn_amount
	if abs(control)>0.7 and velocity>130:
		velocity -= 28.0*dt
	c["speed"] = velocity
	c["pos"] = p + Vector2.RIGHT.rotated(c["angle"]) * velocity * dt
	var np:Vector2 = c["pos"]
	# Loop progress, clockwise positive according to the parameter angle in screen coordinates.
	var phase = fposmod(atan2((np.y-CENTER.y)/158.0,(np.x-CENTER.x)/323.0)+PI/2.0,TAU)/TAU
	if phase < 0.15 and c["last_progress"] > 0.85 and race_time>5:
		c["laps"] += 1
		if c["laps"] >= lap_goal:
			c["done"]=true
	c["last_progress"] = phase
	c["progress"] = phase
	cars[i]=c

func _collisions() -> void:
	for i in range(cars.size()):
		for j in range(i+1,cars.size()):
			var a:Dictionary=cars[i]
			var b:Dictionary=cars[j]
			var offset:Vector2=b["pos"]-a["pos"]
			var distance=offset.length()
			if distance>0.001 and distance<19.0:
				var normal=offset/distance
				var shift=normal*(19.0-distance)*0.5
				a["pos"]-=shift
				b["pos"]+=shift
				a["speed"]*=0.82
				b["speed"]*=0.82
				cars[i]=a
				cars[j]=b

func _input(event:InputEvent) -> void:
	if event is InputEventScreenTouch:
		var ev:InputEventScreenTouch=event
		if ev.pressed:
			if ev.position.x<W/2: touch_left=true
			else: touch_right=true
		else:
			touch_left=false
			touch_right=false
	if event is InputEventScreenDrag:
		touch_left=event.position.x<W/2
		touch_right=not touch_left
	if event is InputEventKey and event.pressed and event.keycode==KEY_R:
		_reset()
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		get_tree().quit()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,Vector2(W,H)),Color("#27733e"))
	# Pixel-style, entire racetrack visible from overhead.
	_draw_ellipse_road(CENTER,OUTER,INNER,Color("#5e626b"))
	_draw_ellipse_line(CENTER,Vector2(323,158),Color("#c9c9c9"),2.0,true)
	# Start line on upper straight.
	for k in range(8):
		draw_rect(Rect2(Vector2(318+k*4,92),Vector2(4,5)),Color.WHITE if k%2==0 else Color.BLACK)
	for k in range(6):
		draw_rect(Rect2(Vector2(318+k*4,97),Vector2(4,5)),Color.BLACK if k%2==0 else Color.WHITE)
	for i in range(cars.size()):
		_draw_car(cars[i],COLORS[i])
	draw_string(font,Vector2(20,28),"MINI RACING  |  RETRO GP",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("#fff3bc"))
	draw_string(font,Vector2(20,53),"LAP %d/%d     TIME %05.1f" % [min(cars[0]["laps"]+1,lap_goal),lap_goal,race_time],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	draw_rect(Rect2(Vector2(28,445),Vector2(112,70)),Color("#111c29aa"))
	draw_rect(Rect2(Vector2(820,445),Vector2(112,70)),Color("#111c29aa"))
	draw_string(font,Vector2(51,488),"< LEFT",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	draw_string(font,Vector2(829,488),"RIGHT >",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	if countdown>0:
		draw_string(font,Vector2(452,275),str(ceili(countdown)),HORIZONTAL_ALIGNMENT_LEFT,-1,48,Color.YELLOW)
	elif cars[0]["done"]:
		draw_string(font,Vector2(360,270),"FINISH!  PRESS R",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color.YELLOW)

func _draw_ellipse_road(center:Vector2,outer:Vector2,inner:Vector2,col:Color)->void:
	var poly=PackedVector2Array()
	for i in range(97):
		var t=float(i)/96.0*TAU
		poly.append(center+Vector2(cos(t)*outer.x,sin(t)*outer.y))
	draw_colored_polygon(poly,col)
	draw_ellipse_fill(center,inner,Color("#27733e"))
	for edge in [outer,inner]:
		_draw_ellipse_line(center,edge,Color("#e8e5d8"),4,false)

func _draw_ellipse_fill(center:Vector2,r:Vector2,col:Color)->void:
	var vertices=PackedVector2Array()
	for i in range(96):
		var t=float(i)/96*TAU
		vertices.append(center+Vector2(cos(t)*r.x,sin(t)*r.y))
	draw_colored_polygon(vertices,col)

func _draw_ellipse_line(center:Vector2,r:Vector2,col:Color,width:float,dashed:bool)->void:
	for i in range(96):
		if dashed and i%4<2:
			continue
		var a=float(i)/96*TAU
		var b=float(i+1)/96*TAU
		draw_line(center+Vector2(cos(a)*r.x,sin(a)*r.y),center+Vector2(cos(b)*r.x,sin(b)*r.y),col,width)

func _draw_car(c:Dictionary,col:Color)->void:
	var p:Vector2=c["pos"]
	var a:float=c["angle"]
	var corners=PackedVector2Array()
	for v in [Vector2(-11,-6),Vector2(11,-6),Vector2(11,6),Vector2(-11,6)]:
		corners.append(p+v.rotated(a))
	draw_colored_polygon(corners,col)
	draw_line(p+Vector2(-5,-8).rotated(a),p+Vector2(-5,8).rotated(a),Color.BLACK,3.0)
	draw_circle(p+Vector2(4,0).rotated(a),3,Color("#141414"))
