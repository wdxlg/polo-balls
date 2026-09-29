extends Node2D

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const WALL_HIT_BURST_SCRIPT = preload("res://scripts/effects/wall_hit_burst.gd")

var master:ball = null
var velocity:Vector2 = Vector2(0.0,650.0)
var damage:float = 20.0
var lifetime_left:float = 3.2
var _last_position:Vector2 = Vector2.ZERO
var _finished:bool = false
var _travel_distance:float = 0.0
var _initial_length:float = 6.0
var _initial_width:float = 0.48
var _outline:Line2D = null
var _line:Line2D = null

func setup(p_master:ball,start:Vector2,p_velocity:Vector2,p_damage:float,p_lifetime:float = 3.2,p_initial_length:float = 6.0,p_initial_width:float = 0.48) -> void:
	master = p_master
	global_position = start
	_last_position = start
	velocity = p_velocity
	damage = p_damage
	lifetime_left = maxf(p_lifetime,0.1)
	_travel_distance = 0.0
	_initial_length = maxf(p_initial_length,2.0)
	_initial_width = maxf(p_initial_width,0.10)
	_update_visual()

func _ready() -> void:
	_outline = Line2D.new()
	_outline.width = _initial_width + 0.32
	_outline.default_color = Color(0.01,0.06,0.18,0.70)
	_outline.antialiased = true
	_outline.z_index = 24
	add_child(_outline)
	_line = Line2D.new()
	_line.width = _initial_width
	_line.default_color = Color(0.25,0.82,1.0,0.98)
	_line.antialiased = true
	_line.z_index = 25
	add_child(_line)
	_update_visual()

func _physics_process(delta:float) -> void:
	if _finished:
		return
	lifetime_left -= delta
	if lifetime_left <= 0.0:
		_finish()
		return
	_last_position = global_position
	global_position += velocity * delta
	_travel_distance += _last_position.distance_to(global_position)
	_update_visual()
	var hit:Dictionary = _first_physics_hit()
	if hit.is_empty():
		return
	var collider:Variant = hit.get("collider")
	if collider is ball and master != null and is_instance_valid(master):
		var target:ball = collider as ball
		if TOOLS.is_enemy(master,target):
			var impact:Vector2 = hit.get("position",global_position)
			if target.receive_positional_damage(damage,impact,false,master):
				_play_collision_damage_sound()
			_finish()
			return
	_spawn_wall_white_lines(hit)
	_finish()

func _update_visual() -> void:
	var dir:Vector2 = velocity.normalized()
	if dir.length_squared() <= 0.000001:
		dir = Vector2.DOWN

	# V398：初始泪滴明显更短更细；随着真实飞行距离增加才逐步被拉成长线。
	# 同时持续变细，远距离形成细长泪丝，而不是出生时就像粗长光束。
	var line_length:float = minf(_initial_length + _travel_distance * 0.105,78.0)
	var inner_width:float = maxf(_initial_width - _travel_distance * 0.00115,0.14)
	var outline_width:float = inner_width + maxf(0.12,0.30 - _travel_distance * 0.00035)
	var points := PackedVector2Array([Vector2.ZERO,-dir * line_length])
	if _outline != null:
		_outline.points = points
		_outline.width = outline_width
	if _line != null:
		_line.points = points
		_line.width = inner_width

func _first_physics_hit() -> Dictionary:
	var world_2d:World2D = get_world_2d()
	if world_2d == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(_last_position,global_position,3)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _friendly_body_rids()
	for _attempt:int in range(32):
		var hit:Dictionary=world_2d.direct_space_state.intersect_ray(query)
		if hit.is_empty(): return hit
		var candidate:Node=hit.get("collider")
		if not is_instance_valid(candidate) or not candidate.has_method("try_full_projectile_dodge") or not bool(candidate.call("try_full_projectile_dodge",self)): return hit
		var excluded:Array[RID]=query.exclude
		excluded.append(candidate.get_rid())
		query.exclude=excluded
	return {}

func _friendly_body_rids() -> Array[RID]:
	var out:Array[RID] = []
	if master != null and is_instance_valid(master):
		out.append(master.get_rid())
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if master == null or not is_instance_valid(master) or not TOOLS.is_enemy(master,candidate):
			out.append(candidate.get_rid())
	return out

func _spawn_wall_white_lines(hit:Dictionary) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var point:Vector2 = hit.get("position",global_position)
	var normal:Vector2 = hit.get("normal",Vector2.UP)
	var seed:int = Game.battle_rng_seed_or("scripts/effects/投稿/悲伤眼泪.gd:wall_hit_seed",int(get_instance_id()) ^ int(Engine.get_physics_frames() * 1103515245))
	WALL_HIT_BURST_SCRIPT.spawn(world,point,normal,maxf(velocity.length(),1.0),4.0,seed,velocity.normalized())

func _play_collision_damage_sound() -> void:
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",{},true,true)
	else:
		Audios.play_sfx("balls_hit1",{},true,true)

func _finish() -> void:
	_finished = true
	queue_free()
