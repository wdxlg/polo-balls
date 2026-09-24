extends Sprite2D
var source_ref:WeakRef
var origin:Vector2
var launch:Vector2 = Vector2(60,-120)
var gravity:float = 260.0
var age:float = 0.0
var arena:Rect2
var finished:bool = false
func configure(source:Node2D,disc:Texture2D,point:Vector2,side:float,bounds:Rect2) -> void:
	source_ref = weakref(source)
	texture = disc
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	global_position = point
	origin = point
	scale = Vector2(0.56,0.56)
	launch = Vector2(side*65.0,-120.0)
	arena = bounds
	z_as_relative = false
	z_index = 9
	add_to_group("MCFlyingRecord")
	add_to_group("BattleTransient")
func _physics_process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	advance(delta)
func advance(delta:float) -> void:
	if finished: return
	age += delta
	global_position = origin+launch*age+Vector2(0,0.5*gravity*age*age)
	rotation = age*5.0*signf(launch.x)
	if (launch.y+gravity*age>0 and not arena.grow(16).has_point(global_position)) or age>=8.0:
		finished = true
		var source:Node = source_ref.get_ref() if source_ref != null else null
		if is_instance_valid(source) and source.is_multiplayer_authority(): source.finish_ejection()
		queue_free()
