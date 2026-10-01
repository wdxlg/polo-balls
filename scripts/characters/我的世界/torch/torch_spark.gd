extends Node2D
## 火把火星：从火焰尖端沿抛物线落到地面（纯表现，不结算伤害）。
## 落点与火的种类由权威端决定并随 RPC 下发；落地后交给火把在本端生火。
const LAVA:Texture2D = preload("res://Images/characters/我的世界/torch/lava.png")
const SOUL_FLAME:Texture2D = preload("res://Images/characters/我的世界/torch/soul_fire_flame.png")
const DRAW_Z:int = 92 # 与火场同层：地图外遮罩之上
const WIDTH:float = 5.0
const TRAIL:int = 3

var _torch:WeakRef
var _id:int = 0
var _from:Vector2 = Vector2.ZERO
var _to:Vector2 = Vector2.ZERO
var _flight:float = 0.45
var _arc:float = 7.0
var _age:float = 0.0
var _soul:bool = false
var _sound:bool = false
var _trail:Array[Vector2] = []


func setup(torch:Node2D,id:int,from:Vector2,to:Vector2,flight:float,arc:float,soul:bool,sound:bool) -> void:
	_torch = weakref(torch)
	_id = id
	_from = from
	_to = to
	_flight = maxf(flight,0.05)
	_arc = arc
	_soul = soul
	_sound = sound
	global_position = from
	z_as_relative = false
	z_index = DRAW_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("BattleTransient")
	add_to_group("MCTorchSpark")


func landing_point() -> Vector2:
	return _to


func point_at(t:float) -> Vector2:
	return _from.lerp(_to,t) + Vector2.UP * _arc * 4.0 * t * (1.0 - t)


func _process(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	_age += delta
	var t:float = clampf(_age / _flight,0.0,1.0)
	_trail.push_front(global_position)
	if _trail.size() > TRAIL: _trail.pop_back()
	global_position = point_at(t)
	queue_redraw()
	if t >= 1.0: _land()


func _draw() -> void:
	var texture:Texture2D = SOUL_FLAME if _soul else LAVA
	var size:Vector2 = Vector2.ONE * WIDTH
	for i:int in range(_trail.size()):
		var tail:Vector2 = _trail[i] - global_position
		draw_texture_rect(texture,Rect2(tail - size * 0.3,size * 0.6),false,Color(1,1,1,0.5 - 0.14 * i))
	draw_texture_rect(texture,Rect2(-size * 0.5,size),false)


func _land() -> void:
	var torch:Object = _torch.get_ref() if _torch != null else null
	if is_instance_valid(torch) and torch.has_method(&"spark_landed"):
		torch.call(&"spark_landed",_id,_to,_soul,_sound)
	queue_free()
