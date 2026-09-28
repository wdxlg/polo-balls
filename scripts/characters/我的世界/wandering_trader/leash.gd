extends Node2D
## One 缰绳 between the trader's hand and a llama's neck. Purely visual, drawn in world
## coordinates (top_level). Colours are the two texels of Bedrock textures/entity/lead_rope.png,
## alternating per segment like the vanilla lead renderer. Sags when slack, straight + trembling
## when taut; snaps into two falling halves on break and "grows" from the hand on reconnect.
const LIGHT := Color8(127,102,76)
const DARK := Color8(89,71,53)
enum Mode { CONNECTED, BREAKING, HIDDEN, CONNECTING }

var mode:int = Mode.HIDDEN
var from_point:Vector2
var to_point:Vector2
var slack_length:float = 42.0
var taut:bool = false
var width:float = 1.15
var _anim:float = 0.0
var _break_from:Vector2
var _break_to:Vector2
var _time:float = 0.0
const BREAK_TIME:float = 0.42
const CONNECT_TIME:float = 0.2
const MAX_SAG:float = 7.0

func _ready() -> void:
	top_level = true
	z_index = 2
	global_position = Vector2.ZERO
	global_rotation = 0.0
	global_scale = Vector2.ONE

func set_points(from:Vector2,to:Vector2,slack:float,is_taut:bool) -> void:
	from_point = from
	to_point = to
	slack_length = slack
	taut = is_taut
	queue_redraw()

func is_connected_visual() -> bool:
	return mode == Mode.CONNECTED or mode == Mode.CONNECTING

func snap() -> void:
	if mode == Mode.HIDDEN or mode == Mode.BREAKING: return
	mode = Mode.BREAKING
	_anim = 0.0
	_break_from = from_point
	_break_to = to_point
	queue_redraw()

func connect_visual() -> void:
	mode = Mode.CONNECTING
	_anim = 0.0
	queue_redraw()

func hide_now() -> void:
	mode = Mode.HIDDEN
	queue_redraw()

func _process(delta:float) -> void:
	_time += delta
	if mode == Mode.BREAKING:
		_anim += delta
		if _anim >= BREAK_TIME: mode = Mode.HIDDEN
	elif mode == Mode.CONNECTING:
		_anim += delta
		if _anim >= CONNECT_TIME: mode = Mode.CONNECTED
	if mode != Mode.HIDDEN or _anim < BREAK_TIME + 0.05: queue_redraw()

static func rope_points(a:Vector2,b:Vector2,slack:float,is_taut:bool,wobble:float = 0.0) -> PackedVector2Array:
	var distance:float = a.distance_to(b)
	var count:int = clampi(int(distance/2.0),8,48)
	# Parabola approximating a catenary: sag grows as the rope is shorter than its length.
	# Capped at MAX_SAG: the hand is only ~12 world px above the feet, so a deeper curve would
	# visibly hang through the floor when the llama stands right beside the trader.
	var sag:float = 0.0 if is_taut else clampf(sqrt(maxf(slack*slack - distance*distance,0.0))*0.5,1.2,minf(slack*0.45,MAX_SAG))
	var normal:Vector2 = (b-a).orthogonal().normalized() if distance > 0.001 else Vector2.ZERO
	var points := PackedVector2Array()
	for i:int in range(count + 1):
		var s:float = float(i)/float(count)
		var p:Vector2 = a.lerp(b,s) + Vector2(0.0,sag*4.0*s*(1.0-s))
		if is_taut and wobble != 0.0: p += normal*sin(s*PI)*wobble
		points.append(p)
	return points

func _draw() -> void:
	match mode:
		Mode.HIDDEN: return
		Mode.CONNECTED:
			_draw_rope(rope_points(from_point,to_point,slack_length,taut,sin(_time*55.0)*0.45 if taut else 0.0),1.0)
		Mode.CONNECTING:
			var k:float = clampf(_anim/CONNECT_TIME,0.0,1.0)
			var tip:Vector2 = from_point.lerp(to_point,k)
			_draw_rope(rope_points(from_point,tip,slack_length*k,taut),1.0)
		Mode.BREAKING:
			var k:float = clampf(_anim/BREAK_TIME,0.0,1.0)
			var middle:Vector2 = _break_from.lerp(_break_to,0.5)
			var fall:Vector2 = Vector2(0.0,6.0 + 26.0*k*k)
			var alpha:float = 1.0 - k
			_draw_rope(rope_points(_break_from,middle.lerp(_break_from,0.25) + fall,slack_length*0.5,false),alpha)
			_draw_rope(rope_points(_break_to,middle.lerp(_break_to,0.25) + fall,slack_length*0.5,false),alpha)
	var knot:Color = DARK
	if mode != Mode.BREAKING:
		draw_rect(Rect2(from_point - Vector2(1.0,1.0),Vector2(2.0,2.0)),knot)
		draw_rect(Rect2(to_point - Vector2(1.0,1.0),Vector2(2.0,2.0)),knot)

func _draw_rope(points:PackedVector2Array,alpha:float) -> void:
	for i:int in range(points.size() - 1):
		var color:Color = LIGHT if i % 2 == 0 else DARK
		color.a *= alpha
		draw_line(points[i],points[i + 1],color,width,false)
