extends Area2D

# 火车长专用煤矿：永久存在，只负责真实接触式挖矿交互。
# V123：矿不再进入“采完冷却/暂不可挖”状态；同一块矿可以反复挖。
# 挖矿开始靠 body_entered，离开靠 body_exited 立即终止。

@export_group("视觉变化")
@export var random_rotation_enabled:bool = true
@export_range(0.70,1.0,0.01) var visual_scale_min:float = 0.90
@export_range(1.0,1.35,0.01) var visual_scale_max:float = 1.10

@export_group("挖矿受击弹性")
@export_range(0.0,16.0,0.5,"or_greater") var mining_bounce_distance:float = 5.0
@export_range(0.0,0.30,0.01,"or_greater") var mining_bounce_squash:float = 0.10
@export_range(0.02,0.30,0.01,"or_greater") var mining_bounce_out_time:float = 0.06
@export_range(0.04,0.50,0.01,"or_greater") var mining_bounce_return_time:float = 0.15

var _claimed_by:int = 0
var _visual_base_position:Vector2 = Vector2.ZERO
var _visual_base_scale:Vector2 = Vector2.ONE
var _bounce_tween:Tween = null

@onready var visual:Sprite2D = $Sprite2D
@onready var collision_shape:CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("TrainConductorMine")
	set_meta("train_conductor_coal_mine",true)
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if visual != null:
		visual.modulate.a = 1.0
		_visual_base_position = visual.position
		_visual_base_scale = visual.scale
	if collision_shape != null:
		collision_shape.set_deferred("disabled",false)


func apply_visual_variation(variation_seed:int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("TrainConductorMine|%d" % variation_seed)
	if random_rotation_enabled:
		rotation = rng.randf_range(-PI,PI)
	else:
		rotation = 0.0
	var min_value:float = minf(visual_scale_min,visual_scale_max)
	var max_value:float = maxf(visual_scale_min,visual_scale_max)
	var scale_value:float = rng.randf_range(min_value,max_value)
	scale = Vector2.ONE * scale_value


func play_mining_bounce(world_push_direction:Vector2 = Vector2.UP) -> void:
	# 只弹矿体视觉，不移动 Area2D 根节点/CollisionShape2D，避免挖矿交互区跟着抖动。
	if visual == null or not is_instance_valid(visual):
		return
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	visual.position = _visual_base_position
	visual.scale = _visual_base_scale

	var push_direction:Vector2 = world_push_direction
	if push_direction.length_squared() <= 0.000001:
		push_direction = Vector2.UP
	push_direction = push_direction.normalized()
	var world_target:Vector2 = global_position + push_direction * maxf(mining_bounce_distance,0.0)
	var local_offset:Vector2 = to_local(world_target) - to_local(global_position)
	var squash:float = clampf(mining_bounce_squash,0.0,0.45)
	var squashed_scale:Vector2 = _visual_base_scale * Vector2(1.0 + squash,1.0 - squash * 0.55)
	var out_time:float = maxf(mining_bounce_out_time,0.02)
	var return_time:float = maxf(mining_bounce_return_time,0.04)

	_bounce_tween = create_tween().set_parallel(true)
	_bounce_tween.tween_property(visual,"position",_visual_base_position + local_offset,out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce_tween.tween_property(visual,"scale",squashed_scale,out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce_tween.chain().tween_property(visual,"position",_visual_base_position,return_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bounce_tween.parallel().tween_property(visual,"scale",_visual_base_scale,return_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_available_for(body:Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not body.has_method("is_train_conductor") or not bool(body.call("is_train_conductor")):
		return false
	return _claimed_by == 0 or _claimed_by == body.get_instance_id()


func claim_mine(body:Node) -> bool:
	if not is_available_for(body):
		return false
	_claimed_by = body.get_instance_id()
	return true


func release_claim(body:Node) -> void:
	if body == null:
		return
	if _claimed_by == body.get_instance_id():
		_claimed_by = 0


func consume_mine(body:Node) -> bool:
	# 兼容旧调用名：V123 起“consume”只代表成功完成一次挖击，不会让矿消失、冷却或失效。
	return (
		body != null
		and is_instance_valid(body)
		and _claimed_by == body.get_instance_id()
	)


func is_body_overlapping(body:Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return overlaps_body(body)


func _on_body_entered(body:Node) -> void:
	if not is_available_for(body):
		return
	if body.has_method("notify_coal_mine_contact"):
		body.call("notify_coal_mine_contact",self)


func _on_body_exited(body:Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if _claimed_by == body.get_instance_id():
		_claimed_by = 0
	if body.has_method("notify_coal_mine_exit"):
		body.call("notify_coal_mine_exit",self)
