extends Node2D

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

var master:ball = null
var velocity:Vector2 = Vector2.ZERO
var damage:float = 10.0
var lifetime_left:float = 2.4
var hit_radius:float = 7.0
var _last_position:Vector2 = Vector2.ZERO
var _finished:bool = false
var _label:Label = null

func setup(p_master:ball,start:Vector2,p_velocity:Vector2,p_damage:float,p_lifetime:float = 2.4,p_hit_radius:float = 7.0) -> void:
	master = p_master
	global_position = start
	_last_position = start
	velocity = p_velocity
	damage = p_damage
	lifetime_left = maxf(p_lifetime,0.1)
	hit_radius = maxf(p_hit_radius,0.0)

func _ready() -> void:
	_label = Label.new()
	_label.text = "Z"
	_label.position = Vector2(-6.0,-10.0)
	_label.z_index = 36
	_label.add_theme_font_size_override("font_size",20)
	_label.add_theme_color_override("font_color",Color(0.78,0.9,1.0,1.0))
	_label.add_theme_color_override("font_shadow_color",Color(0.02,0.05,0.14,0.9))
	_label.add_theme_constant_override("shadow_offset_x",1)
	_label.add_theme_constant_override("shadow_offset_y",1)
	add_child(_label)

func _physics_process(delta:float) -> void:
	if _finished:
		return
	lifetime_left -= delta
	if lifetime_left <= 0.0:
		_finish()
		return
	_last_position = global_position
	global_position += velocity * delta
	var hit:Dictionary = _first_physics_hit()
	if hit.is_empty():
		return
	var target:ball = _resolve_hit_ball(hit.get("collider"))
	if target != null and master != null and is_instance_valid(master) and TOOLS.is_enemy(master,target):
		var impact:Vector2 = hit.get("position",global_position)
		if target.receive_positional_damage(damage,impact,false,master):
			_play_collision_damage_sound()
	_finish()

func _first_physics_hit() -> Dictionary:
	var world_2d:World2D = get_world_2d()
	if world_2d == null:
		return {}
	var travel:Vector2 = global_position - _last_position
	if travel.length_squared() <= 0.000001:
		return {}

	var space_state:PhysicsDirectSpaceState2D = world_2d.direct_space_state
	# V402：瞄准/飞行方向完全不变，只修“视觉碰到但零宽射线没触发”。
	# 先用地图层中心射线找本帧最早墙点，再把敌人查询限制在墙前；因此宽判定不会穿墙。
	var wall_query := PhysicsRayQueryParameters2D.create(_last_position,global_position,1)
	wall_query.collide_with_areas = false
	wall_query.collide_with_bodies = true
	var wall_hit:Dictionary = space_state.intersect_ray(wall_query)
	var sweep_end:Vector2 = global_position
	if not wall_hit.is_empty():
		var wall_point:Vector2 = wall_hit.get("position",global_position)
		var wall_direction:Vector2 = travel.normalized()
		sweep_end = wall_point - wall_direction * 0.25

	var enemy_hit:Dictionary = _first_enemy_in_swept_width(space_state,_last_position,sweep_end)
	if not enemy_hit.is_empty():
		return enemy_hit
	if not wall_hit.is_empty():
		return wall_hit
	return {}

func _first_enemy_in_swept_width(space_state:PhysicsDirectSpaceState2D,from:Vector2,to:Vector2) -> Dictionary:
	var sweep:Vector2 = to - from
	var sweep_length:float = sweep.length()
	if sweep_length <= 0.0001:
		return {}
	var direction:Vector2 = sweep / sweep_length

	# 用一条沿本帧位移铺开的窄矩形代表 Z 的可见宽度。intersect_shape 会同时覆盖
	# 起点、终点和中间整段区域，因此目标即使只被 Z 字形边缘擦到也能进入结果。
	var sweep_shape := RectangleShape2D.new()
	sweep_shape.size = Vector2(maxf(sweep_length,1.0),maxf(hit_radius * 2.0,1.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = sweep_shape
	query.transform = Transform2D(direction.angle(),(from + to) * 0.5)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _friendly_collision_rids()

	var results:Array[Dictionary] = space_state.intersect_shape(query,32)
	var best_target:ball = null
	var best_progress:float = INF
	for result:Dictionary in results:
		var target:ball = _resolve_hit_ball(result.get("collider"))
		if target == null or master == null or not is_instance_valid(master) or not TOOLS.is_enemy(master,target):
			continue
		var progress:float = clampf((target.global_position - from).dot(direction),0.0,sweep_length)
		if progress < best_progress:
			best_progress = progress
			best_target = target
	if best_target == null:
		return {}
	return {
		"collider": best_target,
		"position": from + direction * best_progress,
	}

func _resolve_hit_ball(collider:Variant) -> ball:
	if collider is ball:
		return collider as ball
	if not collider is Node:
		return null
	var current:Node = collider as Node
	for _step:int in range(4):
		current = current.get_parent()
		if current == null:
			break
		if current is ball:
			return current as ball
	return null

func _friendly_collision_rids() -> Array[RID]:
	var out:Array[RID] = []
	if master != null and is_instance_valid(master):
		_append_ball_collision_rids(out,master)
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if master == null or not is_instance_valid(master) or not TOOLS.is_enemy(master,candidate):
			_append_ball_collision_rids(out,candidate)
	return out

func _append_ball_collision_rids(out:Array[RID],candidate:ball) -> void:
	if candidate == null or not is_instance_valid(candidate):
		return
	var body_rid:RID = candidate.get_rid()
	if body_rid.is_valid() and not out.has(body_rid):
		out.append(body_rid)
	if candidate.self_hurtbox != null and is_instance_valid(candidate.self_hurtbox):
		var hurtbox_rid:RID = candidate.self_hurtbox.get_rid()
		if hurtbox_rid.is_valid() and not out.has(hurtbox_rid):
			out.append(hurtbox_rid)

func _play_collision_damage_sound() -> void:
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",{},true,true)
	else:
		Audios.play_sfx("balls_hit1",{},true,true)

func _finish() -> void:
	_finished = true
	queue_free()
