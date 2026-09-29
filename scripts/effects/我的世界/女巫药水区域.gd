extends Node2D

const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")
const POTION_PARTICLE = preload("res://scripts/effects/我的世界/女巫药水粒子.gd")

var effect_type:String = ""
var source_witch:Node = null
var radius:float = 64.0
var duration:float = 5.2
var tick_interval:float = 1.0
var particle_interval:float = 0.0107
var _elapsed:float = 0.0
var _tick_left:float = 1.0
var _particle_left:float = 0.0
var _base_color:Color = Color.WHITE


func setup(new_effect_type:String,new_source:Variant = null,new_radius:float = 64.0,new_duration:float = 5.2) -> void:
	effect_type = new_effect_type
	source_witch = _valid_source_node(new_source)
	radius = maxf(new_radius,8.0)
	duration = maxf(new_duration,0.1)
	_base_color = POTION_EFFECTS.color_for(effect_type)
	_tick_left = tick_interval
	_particle_left = 0.0


func _ready() -> void:
	# 范围节点本身不再绘制圆环；只保留逻辑与不断生成的药水粒子。
	z_as_relative = false
	z_index = -3


func _physics_process(delta:float) -> void:
	_elapsed += delta
	_tick_left -= delta
	_particle_left -= delta

	while _tick_left <= 0.0 and _elapsed <= duration + 0.001:
		_tick_left += tick_interval
		_apply_to_units_in_radius()

	while _particle_left <= 0.0 and _elapsed <= duration + 0.001:
		_particle_left += particle_interval
		_spawn_area_particle()

	if _elapsed >= duration:
		queue_free()


func _apply_to_units_in_radius() -> void:
	var radius_sq:float = radius * radius
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target.Type != ball.Ball_Type.Ball and target.Type != ball.Ball_Type.Creature:
			continue
		if target.health <= 0 or target.is_queued_for_deletion():
			continue
		if ball.body_point(target,global_position).distance_squared_to(global_position) > radius_sq:
			continue
		POTION_EFFECTS.apply_stacking_effect(target,effect_type,_valid_source_node(source_witch))


func _spawn_area_particle() -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	# sqrt(randf()) 让粒子在圆形区域内按面积均匀分布，而不是都挤在圆心。
	var angle:float = randf_range(0.0,TAU)
	var dist:float = sqrt(randf()) * radius * 0.92
	var spawn_position:Vector2 = global_position + Vector2.from_angle(angle) * dist
	var particle:Sprite2D = POTION_PARTICLE.new()
	world.add_child(particle)
	particle.call(
		"setup",
		spawn_position,
		_base_color,
		Vector2(randf_range(-5.0,5.0),randf_range(-22.0,-14.0)),
		randf_range(0.022,0.034),
		randf_range(0.060,0.074),
		-3
	)


func _valid_source_node(candidate:Variant) -> Node:
	# 药水区域可能比施法女巫活得更久。女巫 queue_free 后，旧引用会变成
	# “previously freed” Object；不能再把它传给带 Node 类型约束的函数。
	if candidate == null or not is_instance_valid(candidate):
		return null
	if candidate is Node:
		return candidate as Node
	return null
