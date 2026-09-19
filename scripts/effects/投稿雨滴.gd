extends Node2D

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const WALL_HIT_BURST_SCRIPT = preload("res://scripts/effects/wall_hit_burst.gd")

var master:ball
var velocity:Vector2 = Vector2(0.0,520.0)
var length:float = 18.0
var damage:float = 4.0
var bottom_y:float = 1000.0
var hit_radius:float = 6.0
var _last_position:Vector2
var _outline:Line2D
var _line:Line2D
var _umbrella_impact_position:Vector2 = Vector2.ZERO
var _umbrella_surface_normal:Vector2 = Vector2.UP
var _finished:bool = false
var visual_only:bool = false

func setup(p_master:ball,start:Vector2,p_length:float,p_damage:float,p_velocity:Vector2,p_bottom_y:float,p_visual_only:bool = false) -> void:
	master = p_master
	global_position = start
	_last_position = start
	length = p_length
	damage = p_damage
	velocity = p_velocity
	bottom_y = p_bottom_y
	visual_only = p_visual_only

func _ready() -> void:
	# 细雨：只保留非常薄的深色分离边 + 更细的亮蓝核心，避免和地图背景融在一起。
	_outline = Line2D.new()
	_outline.width = 1.35
	_outline.default_color = Color(0.01,0.05,0.14,0.72)
	_outline.antialiased = true
	_outline.z_index = 20
	add_child(_outline)

	_line = Line2D.new()
	_line.width = 0.68
	_line.default_color = Color(0.16,0.76,1.0,0.98)
	_line.antialiased = true
	_line.z_index = 21
	add_child(_line)
	_update_line()

func _physics_process(delta:float) -> void:
	if _finished:
		return
	if master == null or not is_instance_valid(master) or master.health <= 0:
		queue_free()
		return
	_last_position = global_position
	global_position += velocity * delta
	_update_line()
	if _hit_master_umbrella():
		_spawn_umbrella_feedback()
		_finish()
		return
	if not visual_only and _hit_enemy():
		_finish()
		return
	if global_position.y - length > bottom_y + 20.0:
		_finish()

func _update_line() -> void:
	var dir:Vector2 = velocity.normalized()
	var points := PackedVector2Array([Vector2.ZERO,-dir * length])
	if _outline != null:
		_outline.points = points
	if _line != null:
		_line.points = points

func _hit_master_umbrella() -> bool:
	if master == null or not is_instance_valid(master):
		return false
	if not master.has_method("rain_hits_umbrella_segment"):
		return false
	var hit:bool = bool(master.call("rain_hits_umbrella_segment",_last_position,global_position))
	if hit:
		_umbrella_impact_position = global_position
		_umbrella_surface_normal = Vector2.UP
		if master.has_method("rain_umbrella_impact_data"):
			var data:Dictionary = master.call("rain_umbrella_impact_data",_last_position,global_position)
			if not data.is_empty():
				_umbrella_impact_position = data.get("point",global_position)
				_umbrella_surface_normal = data.get("normal",Vector2.UP)
		elif master.has_method("rain_umbrella_impact_point"):
			_umbrella_impact_position = master.call("rain_umbrella_impact_point",_last_position,global_position)
	return hit

func _hit_enemy() -> bool:
	# V434 性能：先做最便宜的线段距离过滤，只有真正贴到雨滴轨迹的单位才走
	# TOOLS.is_enemy()（召唤链 + 阵营 metadata 判定）。两个条件都必须成立，
	# 交换顺序不改变结果；候选列表改用 World 的可索敌快照（无 World 时退回 Ball 组）。
	var hit_radius_sq:float = hit_radius * hit_radius
	for raw:Node in TOOLS.targeting_candidates(self):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if target.Type == ball.Ball_Type.Shooter or target.Type == ball.Ball_Type.Shooter_with_Health:
			continue
		var target_position:Vector2 = target.global_position
		# 线段包围盒外的单位一定不可能命中，避免对全场每滴雨做投影运算。
		if target_position.x < minf(_last_position.x,global_position.x) - hit_radius or target_position.x > maxf(_last_position.x,global_position.x) + hit_radius:
			continue
		if target_position.y < minf(_last_position.y,global_position.y) - hit_radius or target_position.y > maxf(_last_position.y,global_position.y) + hit_radius:
			continue
		if _distance_point_to_segment(target_position,_last_position,global_position) > hit_radius:
			continue
		if not TOOLS.is_enemy(master,target):
			continue
		if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): continue
		var did_damage:bool = target.receive_positional_damage(damage,global_position,false,master)
		if did_damage:
			_play_character_hit_sfx()
			return true
		return true
	return false

func _play_character_hit_sfx() -> void:
	# 与 ball.gd 的普通碰撞伤害命中声保持一致。
	# rain_damage 很低，因此沿用项目原公式 damage - 12 dB，避免高频细雨盖过其他音效。
	var hit_volume:float = clampf(maxf(damage,0.0) - 12.0,-100.0,0.0)
	if multiplayer.has_multiplayer_peer():
		# 高频雨滴允许多个命中声部重叠，避免后一滴把前一滴直接截断。
		Audios.play_sfx.rpc("balls_hit1",{volume = hit_volume},true,true)
	else:
		Audios.play_sfx("balls_hit1",{volume = hit_volume},true,true)

func _distance_point_to_segment(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t:float = clampf((point - a).dot(ab) / len_sq,0.0,1.0)
	return point.distance_to(a + ab * t)

func _spawn_umbrella_feedback() -> void:
	var impact_point:Vector2 = _umbrella_impact_position
	if impact_point == Vector2.ZERO:
		impact_point = global_position
	# 优先交给伤心男人统一处理，这样雨、子弹和普通攻击都用同一套撞墙白线 + 随机伞面音效。
	if master != null and is_instance_valid(master) and master.has_method("umbrella_impact_feedback"):
		# 雨落到伞上只保留白线动画；不播放投稿的两个格挡音。
		master.call("umbrella_impact_feedback",impact_point,_umbrella_surface_normal,velocity.length(),false)
		return
	# 兼容旧版脚本：如果主人没有新接口，至少保留撞墙白线动画。
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var incoming:Vector2 = velocity.normalized()
	var seed:int = Game.battle_rng_seed_or("scripts/effects/投稿雨滴.gd:wall_hit_seed",int(get_instance_id()) ^ int(Engine.get_physics_frames() * 1103515245))
	WALL_HIT_BURST_SCRIPT.spawn(
		world,
		impact_point,
		Vector2.UP,
		maxf(velocity.length(),1.0),
		4.0,
		seed,
		incoming
	)

func _finish() -> void:
	_finished = true
	queue_free()
