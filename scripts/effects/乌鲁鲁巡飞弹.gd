extends Node2D

const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const SMALL_BOMB_SCRIPT:Script = preload("res://scripts/effects/乌鲁鲁巡飞弹小炸弹.gd")
const MISSILE_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/巡飞弹.png")

var owner_ref:WeakRef = null
var target_ref:WeakRef = null
var last_target_position:Vector2 = Vector2.ZERO
var current_direction:Vector2 = Vector2.RIGHT
var speed:float = 520.0
var turn_speed_rad:float = deg_to_rad(120.0)
var lifetime:float = 5.4
var hit_radius:float = 12.0
var impact_radius:float = 76.0
var impact_damage_multiplier:float = 7.6
var elapsed:float = 0.0
var config:Dictionary = {}
var _finished:bool = false
var _exploding:bool = false
var _explosion_elapsed:float = 0.0
var _trail_world:Array[Vector2] = []
var _sprite:Sprite2D = null


func setup(owner_ball:ball,target_ball:ball,start_position:Vector2,config_value:Dictionary = {}) -> void:
	owner_ref = weakref(owner_ball)
	target_ref = weakref(target_ball)
	global_position = start_position
	config = config_value.duplicate(true)
	if target_ball != null and is_instance_valid(target_ball):
		last_target_position = target_ball.global_position
	var start_dir:Vector2 = last_target_position - start_position
	current_direction = start_dir.normalized() if start_dir.length_squared() > 0.000001 else Vector2.RIGHT
	speed = maxf(float(config.get("speed",speed)),80.0)
	turn_speed_rad = deg_to_rad(maxf(float(config.get("turn_speed_deg",rad_to_deg(turn_speed_rad))),10.0))
	lifetime = maxf(float(config.get("lifetime",lifetime)),0.5)
	hit_radius = maxf(float(config.get("hit_radius",hit_radius)),3.0)
	impact_radius = maxf(float(config.get("impact_radius",impact_radius)),10.0)
	impact_damage_multiplier = maxf(float(config.get("impact_damage_multiplier",impact_damage_multiplier)),0.0)
	_trail_world.clear()
	_trail_world.append(start_position)


func _ready() -> void:
	z_as_relative = false
	z_index = 84
	add_to_group("BattleTransient")
	_build_visual()
	queue_redraw()


func _physics_process(delta:float) -> void:
	if _finished:
		return
	var source:ball = _owner()
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	if not source.is_combat_runtime_active():
		return
	if _exploding:
		_explosion_elapsed += delta
		if _sprite != null:
			_sprite.visible = false
		queue_redraw()
		if _explosion_elapsed >= 0.28:
			_finished = true
			queue_free()
		return

	elapsed += delta
	if elapsed >= lifetime:
		_impact(source,global_position)
		return
	var target:ball = _target()
	if target != null and is_instance_valid(target):
		last_target_position = target.global_position
	var to_target:Vector2 = last_target_position - global_position
	if to_target.length_squared() > 0.000001:
		var desired_angle:float = to_target.angle()
		var current_angle:float = current_direction.angle()
		var diff:float = wrapf(desired_angle-current_angle,-PI,PI)
		var max_turn:float = turn_speed_rad * delta
		current_angle += clampf(diff,-max_turn,max_turn)
		current_direction = Vector2.RIGHT.rotated(current_angle)
	var previous:Vector2 = global_position
	var next_position:Vector2 = previous + current_direction * speed * delta
	if source.is_multiplayer_authority():
		var hit_target:ball = _sweep_enemy(source,previous,next_position)
		if hit_target != null:
			global_position = next_position
			_impact(source,global_position)
			return
	global_position = next_position
	rotation = current_direction.angle()
	if global_position.distance_squared_to(last_target_position) <= hit_radius * hit_radius:
		_impact(source,global_position)
		return
	_trail_world.append(global_position)
	if _trail_world.size() > 22:
		_trail_world.pop_front()
	queue_redraw()


func _build_visual() -> void:
	if MISSILE_TEXTURE == null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "LoiteringMunitionImage"
	_sprite.texture = MISSILE_TEXTURE
	var longest:float = maxf(MISSILE_TEXTURE.get_width(),MISSILE_TEXTURE.get_height())
	_sprite.scale = Vector2.ONE * (62.0 / maxf(longest,1.0))
	add_child(_sprite)
	rotation = current_direction.angle()


func _sweep_enemy(source:ball,from_pos:Vector2,to_pos:Vector2) -> ball:
	var motion:Vector2 = to_pos - from_pos
	var length_value:float = motion.length()
	if length_value <= 0.001:
		return null
	var shape:=RectangleShape2D.new()
	shape.size = Vector2(length_value + hit_radius * 2.0,hit_radius * 2.0)
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(motion.angle(),(from_pos + to_pos) * 0.5)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var excludes:Array[RID] = []
	if source is CollisionObject2D:
		excludes.append((source as CollisionObject2D).get_rid())
	if source.self_hurtbox != null and is_instance_valid(source.self_hurtbox):
		excludes.append(source.self_hurtbox.get_rid())
	query.exclude = excludes
	for result:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,64):
		var candidate:ball = _collider_ball(result.get("collider",null))
		if candidate != null and SUBMISSION_TOOLS.is_enemy(source,candidate):
			return candidate
	return null


func _collider_ball(collider:Variant) -> ball:
	if collider is ball:
		return collider as ball
	if collider is Node:
		var node:Node = collider as Node
		var cursor:Node = node
		for _i:int in range(5):
			if cursor is ball:
				return cursor as ball
			cursor = cursor.get_parent()
			if cursor == null:
				break
		if node.owner is ball:
			return node.owner as ball
	return null


func _impact(source:ball,position_value:Vector2) -> void:
	if _exploding or _finished:
		return
	_exploding = true
	_explosion_elapsed = 0.0
	global_position = position_value
	if source.is_multiplayer_authority():
		var damage:float = source.attack_damage(impact_damage_multiplier)
		for target:ball in SUBMISSION_TOOLS.enemies_in_radius(source,position_value,impact_radius):
			target.receive_positional_damage(damage,position_value,false,source)
	_spawn_four_bombs(source,position_value)
	if source.has_method("play_uluru_explosion_sfx"):
		source.call("play_uluru_explosion_sfx",position_value,-1.5)
	if source.has_method("_uluru_on_loiter_missile_finished"):
		source.call_deferred("_uluru_on_loiter_missile_finished")
	queue_redraw()


func _spawn_four_bombs(source:ball,position_value:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var offset:float = randf_range(0.0,TAU)
	for i:int in range(4):
		var bomb:Node2D = SMALL_BOMB_SCRIPT.new() as Node2D
		if bomb == null:
			continue
		bomb.name = "乌鲁鲁巡飞弹炸弹_%d_%d" % [Time.get_ticks_usec(),i]
		world.add_child(bomb,true)
		var dir:Vector2 = Vector2.RIGHT.rotated(offset + TAU * float(i) / 4.0)
		var bomb_config:Dictionary = config.duplicate(true)
		bomb_config["bomb_fuse"] = maxf(float(config.get("bomb_fuse",0.82)) + float(i) * 0.07,0.15)
		bomb.call("setup",source,position_value,dir,bomb_config)


func _target() -> ball:
	if target_ref == null:
		return null
	var raw:Variant = target_ref.get_ref()
	if raw is ball and is_instance_valid(raw) and (raw as ball).health > 0:
		return raw as ball
	return null


func _owner() -> ball:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null


func _exit_tree() -> void:
	var source:ball = _owner()
	if source != null and is_instance_valid(source) and source.has_method("_uluru_on_loiter_missile_finished"):
		source.call_deferred("_uluru_on_loiter_missile_finished")


func _draw() -> void:
	if _trail_world.size() >= 2 and not _exploding:
		var pts:=PackedVector2Array()
		for p:Vector2 in _trail_world:
			pts.append(p-global_position)
		draw_polyline(pts,Color(0.82,0.88,0.92,0.36),2.0,true)
	if _exploding:
		var t:float = clampf(_explosion_elapsed / 0.28,0.0,1.0)
		var r:float = impact_radius * smoothstep(0.0,1.0,t)
		draw_circle(Vector2.ZERO,r,Color(1.0,0.20,0.015,0.30 * (1.0-t)))
		draw_arc(Vector2.ZERO,r,0.0,TAU,36,Color(1.0,0.82,0.25,0.86 * (1.0-t)),4.0,true)
