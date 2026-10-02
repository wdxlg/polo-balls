extends Node2D
## 火把火星：从火焰尖端沿先升后落的抛物线落到地面（纯表现，不结算伤害）。
## 地面上画一个跟随的小影子表示高度，飞行中沿途留下小火苗。
## 落点与火的种类由权威端决定并随 RPC 下发；落地后交给火把在本端生火。
const LAVA:Texture2D = preload("res://Images/characters/我的世界/torch/lava.png")
const SOUL_FLAME:Texture2D = preload("res://Images/characters/我的世界/torch/soul_fire_flame.png")
const PARTICLES = preload("res://scripts/characters/我的世界/torch/torch_particles.gd")
const DRAW_Z:int = 92 # 与火场同层：地图外遮罩之上
const WIDTH:float = 5.0
const TRAIL:int = 3
const TRAIL_GAP:float = 0.03

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
var _ground_from:Vector2 = Vector2.ZERO
var _trail_wait:float = 0.0


func setup(torch:Node2D,id:int,from:Vector2,to:Vector2,flight:float,arc:float,soul:bool,sound:bool) -> void:
	_torch = weakref(torch)
	_id = id
	_from = from
	_to = to
	_flight = maxf(flight,0.05)
	_arc = arc
	_soul = soul
	_sound = sound
	_ground_from = torch.global_position if is_instance_valid(torch) else from
	global_position = from
	z_as_relative = false
	z_index = DRAW_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("BattleTransient")
	add_to_group("MCTorchSpark")


func landing_point() -> Vector2:
	return _to


## 先升后落：在起点到落点的连线上再抬高 4·arc·t(1-t)，t=0.5 时最高。
func point_at(t:float) -> Vector2:
	return _from.lerp(_to,t) + Vector2.UP * _arc * 4.0 * t * (1.0 - t)


## 火星正下方的地面点（影子位置）：从火把脚下匀速移到落点。
func ground_at(t:float) -> Vector2:
	return _ground_from.lerp(_to,t)


func _process(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	_age += delta
	var t:float = clampf(_age / _flight,0.0,1.0)
	_trail.push_front(global_position)
	if _trail.size() > TRAIL: _trail.pop_back()
	global_position = point_at(t)
	_trail_wait -= delta
	if _trail_wait <= 0.0 and t < 1.0:
		_trail_wait = TRAIL_GAP
		var fx:Node2D = PARTICLES.find_or_create(self)
		if fx != null: fx.moving_flame(global_position,_soul,Vector2(0.0,-4.0),0.35,2.4)
	queue_redraw()
	if t >= 1.0: _land()


func _draw() -> void:
	var texture:Texture2D = SOUL_FLAME if _soul else LAVA
	var size:Vector2 = Vector2.ONE * WIDTH
	var t:float = clampf(_age / _flight,0.0,1.0)
	var shadow:Vector2 = ground_at(t) - global_position
	var height:float = clampf(shadow.length() / 40.0,0.0,1.0) # 越高影子越小越淡
	draw_set_transform(shadow,0.0,Vector2(1.0,0.5))
	draw_circle(Vector2.ZERO,WIDTH * (0.55 - 0.2 * height),Color(0,0,0,0.35 - 0.15 * height))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	for i:int in range(_trail.size()):
		var tail:Vector2 = _trail[i] - global_position
		draw_texture_rect(texture,Rect2(tail - size * 0.3,size * 0.6),false,Color(1,1,1,0.5 - 0.14 * i))
	draw_texture_rect(texture,Rect2(-size * 0.5,size),false)


func _land() -> void:
	var torch:Object = _torch.get_ref() if _torch != null else null
	if is_instance_valid(torch) and torch.has_method(&"spark_landed"):
		torch.call(&"spark_landed",_id,_to,_soul,_sound)
	queue_free()
