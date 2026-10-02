extends Node2D
const DIR:String = "res://Images/characters/我的世界/bucket/"
const SPLASH:Array[Texture2D] = [preload(DIR + "splash_0.png"),preload(DIR + "splash_1.png"),preload(DIR + "splash_2.png"),preload(DIR + "splash_3.png")]
const BUBBLE:Texture2D = preload(DIR + "bubble.png")
const LAVA:Texture2D = preload("res://Images/characters/我的世界/torch/lava.png")
const MAX_PARTICLES:int = 320
const KIND_SPLASH:int = 0
const KIND_BUBBLE:int = 1
const KIND_LAVA:int = 2

var _items:Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "MCFluidParticles"
	top_level = true
	z_as_relative = false
	z_index = 93
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	global_position = Vector2.ZERO
	_rng.randomize()


func count() -> int:
	return _items.size()


func _add(item:Dictionary) -> void:
	if _items.size() >= MAX_PARTICLES: _items.pop_front()
	_items.append(item)


func splash(point:Vector2,amount:int = 10,spread:float = 10.0) -> void:
	for i:int in range(amount):
		var angle:float = _rng.randf_range(-PI,0.0)
		_add({"kind":KIND_SPLASH,"pos":point + Vector2(_rng.randf_range(-spread,spread),_rng.randf_range(-spread * 0.4,spread * 0.4)),
			"vel":Vector2.from_angle(angle) * _rng.randf_range(20.0,60.0) + Vector2(0.0,-30.0),"gravity":160.0,
			"life":0.0,"max":_rng.randf_range(0.35,0.6),"size":_rng.randf_range(4.0,6.0)})


func bubble(point:Vector2) -> void:
	_add({"kind":KIND_BUBBLE,"pos":point + Vector2(_rng.randf_range(-5.0,5.0),0.0),"vel":Vector2(_rng.randf_range(-6.0,6.0),_rng.randf_range(-34.0,-22.0)),
		"gravity":0.0,"life":0.0,"max":_rng.randf_range(0.6,1.0),"size":_rng.randf_range(3.0,4.5)})


func lava_pop(point:Vector2) -> void:
	_add({"kind":KIND_LAVA,"pos":point,"vel":Vector2(_rng.randf_range(-24.0,24.0),_rng.randf_range(-70.0,-40.0)),
		"gravity":150.0,"life":0.0,"max":_rng.randf_range(0.6,1.0),"size":_rng.randf_range(3.0,5.0)})


func _process(delta:float) -> void:
	if _items.is_empty():
		return
	var kept:Array[Dictionary] = []
	for item:Dictionary in _items:
		item.life = float(item.life) + delta
		if float(item.life) >= float(item.max): continue
		item.vel = Vector2(item.vel) + Vector2(0.0,float(item.gravity) * delta)
		item.pos = Vector2(item.pos) + Vector2(item.vel) * delta
		kept.append(item)
	_items = kept
	queue_redraw()


func _draw() -> void:
	for item:Dictionary in _items:
		var t:float = float(item.life) / maxf(float(item.max),0.001)
		var size:float = float(item.size)
		var texture:Texture2D = BUBBLE
		var tint := Color(1,1,1,1)
		match int(item.kind):
			KIND_SPLASH:
				texture = SPLASH[mini(int(t * 4.0),3)]
				tint = Color(0.45,0.62,1.0,1.0 - t * 0.5)
			KIND_LAVA:
				texture = LAVA
				size *= 1.0 - t * 0.6
			_:
				tint.a = 1.0 - t * 0.4
		draw_texture_rect(texture,Rect2(Vector2(item.pos) - Vector2.ONE * size * 0.5,Vector2.ONE * size),false,tint)
