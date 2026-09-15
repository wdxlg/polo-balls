extends Node2D

const MONEY_TEXTURE_PATH:String = "res://Images/characters/人物/收债人/收债人_一沓钱.png"

var owner_ref:WeakRef
var target_ref:WeakRef
var start_position:Vector2 = Vector2.ZERO
var control_position:Vector2 = Vector2.ZERO
var duration:float = 0.70
var elapsed:float = 0.0
var spin_speed:float = 0.0
var _sprite:Sprite2D

func setup(owner_node:Node,target_node:Node2D,from_position:Vector2,flight_time:float,arc_height:float) -> void:
	owner_ref = weakref(owner_node)
	target_ref = weakref(target_node)
	start_position = from_position
	global_position = from_position
	duration = maxf(flight_time,0.15)
	var to_position:Vector2 = target_node.global_position
	var horizontal_sign:float = 1.0 if to_position.x >= from_position.x else -1.0
	spin_speed = horizontal_sign * TAU * 2.0
	control_position = (from_position + to_position) * 0.5 + Vector2(0.0,-absf(arc_height))
	z_as_relative = false
	z_index = 80
	_create_visual()

func _physics_process(delta:float) -> void:
	elapsed += delta
	var raw_target:Variant = target_ref.get_ref() if target_ref != null else null
	if not (raw_target is Node2D) or not is_instance_valid(raw_target):
		queue_free()
		return
	var target:Node2D = raw_target as Node2D
	if target.has_method("can_receive_gang_money") and not bool(target.call("can_receive_gang_money")):
		if target.has_method("set_money_pending"):
			target.call("set_money_pending",false)
		queue_free()
		return
	var t:float = clampf(elapsed / duration,0.0,1.0)
	var end_position:Vector2 = target.global_position
	# 二次贝塞尔抛物线：起点和目标会保持准确，中间控制点提供向上的抛物线高度。
	var a:Vector2 = start_position.lerp(control_position,t)
	var b:Vector2 = control_position.lerp(end_position,t)
	global_position = a.lerp(b,t)
	rotation += spin_speed * delta
	if t >= 1.0:
		var raw_owner:Variant = owner_ref.get_ref() if owner_ref != null else null
		if raw_owner is Node:
			var owner_node:Node = raw_owner as Node
			if is_instance_valid(owner_node) and owner_node.has_method("_on_gang_money_arrived"):
				owner_node.call("_on_gang_money_arrived",target)
		queue_free()

func _create_visual() -> void:
	if ResourceLoader.exists(MONEY_TEXTURE_PATH):
		var resource:Resource = ResourceLoader.load(MONEY_TEXTURE_PATH)
		if resource is Texture2D:
			_sprite = Sprite2D.new()
			_sprite.texture = resource as Texture2D
			_sprite.centered = true
			var size:Vector2 = _sprite.texture.get_size()
			var longest:float = maxf(size.x,size.y)
			if longest > 0.0:
				_sprite.scale = Vector2.ONE * (22.0 / longest)
			add_child(_sprite)
			return
	queue_redraw()

func _draw() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	var rect := Rect2(Vector2(-7.5,-4.5),Vector2(15.0,9.0))
	draw_rect(rect,Color(0.20,0.88,0.42,0.96),true)
	draw_rect(rect,Color(0.05,0.28,0.12,1.0),false,1.0,true)
