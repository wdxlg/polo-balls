extends ball
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")

const PIG_NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/meme/寸头没事沙漠溜达猪/沙漠寸头没事瞎溜达猪.png")
const PIG_POUNCE_TEXTURE:Texture2D = preload("res://Images/characters/meme/寸头没事沙漠溜达猪/猪飞扑.png")
const PIG_GRUNT_SFX:AudioStream = preload("res://audio/characters/meme/寸头没事沙漠溜达猪/猪哼.mp3")
const PIG_SHOUT_SFX:AudioStream = preload("res://audio/characters/meme/寸头没事沙漠溜达猪/猪大叫.mp3")

enum PigSfx { GRUNT, SHOUT }

@export_category("寸头没事沙漠溜达猪 - 闪避")
@export_range(160.0,900.0,5.0) var projectile_detect_radius:float = 560.0
@export_range(0.30,2.50,0.05) var projectile_prediction_time:float = 1.45
@export_range(0.0,48.0,1.0) var projectile_safety_margin:float = 12.0
@export_range(1.0,2.5,0.05) var dodge_speed_multiplier:float = 1.65
@export_range(0.12,0.65,0.01) var dodge_duration:float = 0.34
@export_range(12.0,100.0,2.0) var dodge_wall_probe:float = 42.0
@export_range(0.05,0.30,0.01) var jump_reaction_buffer:float = 0.10
@export_range(0.12,0.70,0.01) var jump_force_time:float = 0.28
@export_range(1,5,1) var jump_multi_projectile_count:int = 2

@export_category("寸头没事沙漠溜达猪 - 跳跃")
@export_range(1.0,15.0,0.1) var jump_cooldown:float = 5.5
@export_range(120.0,700.0,5.0) var jump_initial_speed:float = 320.0
@export_range(20.0,260.0,5.0) var jump_end_speed:float = 70.0
@export_range(0.16,0.90,0.01) var jump_move_time:float = 0.48
@export_range(0.08,0.80,0.01) var jump_recovery_time:float = 0.28
@export_range(0.10,0.80,0.01) var hard_attack_jump_time:float = 0.32

@export_category("寸头猪 - 视觉 / 声音")
@export_range(180.0,520.0,2.0) var normal_visual_height:float = 218.0
@export_range(180.0,560.0,2.0) var pounce_visual_height:float = 232.0
@export_range(2.0,20.0,0.25) var grunt_interval_min:float = 4.75
@export_range(2.0,30.0,0.25) var grunt_interval_max:float = 9.25
@export_range(-24.0,12.0,0.5) var grunt_volume_db:float = -3.0
@export_range(-24.0,12.0,0.5) var pounce_shout_volume_db:float = 0.0

@export_category("地图外随机袭击者")
@export var outside_attacker_interval_min:float = 3.25
@export var outside_attacker_interval_max:float = 5.25
@export var outside_attacker_scene_paths:PackedStringArray = PackedStringArray([
	# 当前项目中确认拥有可飞行投射物、并适合从地图外向猪发起远程攻击的角色。
	# 不再只固定猎人/键盘侠；新列表覆盖人物、三角洲、杀戮尖塔、游戏、乐队与 meme 远程角色。
	"res://scenes/characters/人物/占卜师.tscn",
	"res://scenes/characters/人物/收债人.tscn",
	"res://scenes/characters/人物/数学老师.tscn",
	"res://scenes/characters/人物/时光客.tscn",
	"res://scenes/characters/人物/猎人.tscn",
	"res://scenes/characters/人物/科学家.tscn",
	"res://scenes/characters/人物/背刺者.tscn",
	"res://scenes/characters/人物/赌徒.tscn",
	"res://scenes/characters/人物/醉汉.tscn",
	"res://scenes/characters/人物/键盘侠.tscn",
	"res://scenes/characters/人物/领导.tscn",
	"res://scenes/characters/人物/黑帮老大.tscn",
	"res://scenes/characters/三角洲/背刺鼠.tscn",
	"res://scenes/characters/三角洲/夺舍狼.tscn",
	"res://scenes/characters/三角洲/跑刀仔.tscn",
	"res://scenes/characters/杀戮尖塔/小刀猎.tscn",
	"res://scenes/characters/杀戮尖塔/蛇咬相生猎.tscn",
	"res://scenes/characters/杀戮尖塔/蜂群术士.tscn",
	"res://scenes/characters/游戏/战争女神.tscn",
	"res://scenes/characters/游戏/魔角猎人.tscn",
	"res://scenes/characters/乐队/薇欧拉.tscn",
	"res://scenes/characters/meme/不坏煎饼.tscn",
	"res://scenes/characters/meme/凑企鹅.tscn",
	"res://scenes/characters/meme/菊花茶.tscn",
])
@export_range(18.0,120.0,1.0) var outside_spawn_margin:float = 54.0
@export_range(2.0,24.0,1.0) var outside_boundary_inset:float = 4.0
@export_range(70.0,360.0,5.0) var outside_walk_speed:float = 145.0
@export_range(0.20,2.50,0.05) var outside_attack_hold_time:float = 1.15
@export_range(2.0,18.0,0.25) var outside_attack_duration_min:float = 5.0
@export_range(2.0,24.0,0.25) var outside_attack_duration_max:float = 8.0
@export_range(1.0,80.0,1.0) var outside_projectile_entry_inset:float = 18.0
@export_range(24.0,180.0,2.0) var outside_projectile_entry_max_depth:float = 118.0
@export_range(2.0,24.0,1.0) var outside_projectile_entry_step:float = 8.0
@export_range(2.0,24.0,1.0) var outside_projectile_clearance_radius:float = 9.0
@export_range(12.0,120.0,1.0) var outside_exit_extra_distance:float = 28.0

var _outside_timer:float = 4.0
var _rng:=RandomNumberGenerator.new()
var _grunt_timer:float = 3.0
var _pounce_visual_active:bool = false
var _active_outside_guests:Array[Node] = []
var _guest_cleanup_running:bool = false

var _projectile_last_positions:Dictionary = {}
var _projectile_measured_velocity:Dictionary = {}

var _dodge_time_left:float = 0.0
var _dodge_direction:Vector2 = Vector2.ZERO
var _jump_motion_left:float = 0.0
var _jump_recovery_left:float = 0.0
var _jump_cooldown_left:float = 0.0
var _jump_direction:Vector2 = Vector2.ZERO


func _ready() -> void:
	Can_Attack = false
	Has_Collision_Damage = false
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/meme/寸头没事沙漠溜达猪.gd:_rng.seed",int(Time.get_ticks_usec()) ^ get_instance_id())
	_outside_timer = _rng.randf_range(outside_attacker_interval_min,outside_attacker_interval_max)
	_grunt_timer = _rng.randf_range(grunt_interval_min,maxf(grunt_interval_max,grunt_interval_min + 0.1))
	super._ready()
	_set_pig_visual(false)
	var node_added_cb:=Callable(self,"_on_scene_node_added")
	if not get_tree().node_added.is_connected(node_added_cb):
		get_tree().node_added.connect(node_added_cb)
	call_deferred("_seed_projectile_registry")


func Attack() -> void:
	Attacking = false


func Die() -> void:
	_cancel_jump()
	_cleanup_outside_guests()
	super()


func _exit_tree() -> void:
	_cleanup_outside_guests()
	if get_tree() != null:
		var node_added_cb:=Callable(self,"_on_scene_node_added")
		if get_tree().node_added.is_connected(node_added_cb):
			get_tree().node_added.disconnect(node_added_cb)
	_projectile_last_positions.clear()
	_projectile_measured_velocity.clear()


func get_next_state(state:State) -> int:
	if is_player_controlled():
		return super.get_next_state(state)
	var previous_can_skill:bool = Can_Skill
	Can_Skill = false
	var result:int = super.get_next_state(state)
	Can_Skill = previous_can_skill
	return result


func Skill() -> void:
	if not is_multiplayer_authority():
		return
	if _jump_is_active():
		return
	if _jump_cooldown_left > 0.0:
		Using_Skill = false
		return
	var wanted:Vector2 = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	var projectiles:Array[Dictionary] = _collect_projectile_threats()
	if not projectiles.is_empty():
		wanted = _choose_dodge_direction(projectiles[0],projectiles)
	_start_jump(wanted)


func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return

	_update_projectile_registry(delta)
	_jump_cooldown_left = maxf(_jump_cooldown_left-delta,0.0)
	_outside_timer -= delta
	if _outside_timer <= 0.0:
		_outside_timer = _rng.randf_range(outside_attacker_interval_min,outside_attacker_interval_max)
		_spawn_outside_attacker()

	_grunt_timer -= delta
	if _grunt_timer <= 0.0:
		_grunt_timer = _rng.randf_range(grunt_interval_min,maxf(grunt_interval_max,grunt_interval_min + 0.1))
		_play_pig_sfx_everywhere(PigSfx.GRUNT,global_position,grunt_volume_db,randf_range(0.94,1.06))

	if health <= 0 or dizziness or state == State.Die:
		_dodge_time_left = 0.0
		_dodge_direction = Vector2.ZERO
		_cancel_jump()
		super.tick_physics(state,delta)
		return

	if _jump_is_active():
		_tick_jump(delta)
		return

	if _dodge_time_left > 0.0 and _dodge_direction.length_squared() > 0.001:
		_tick_dodge(delta)
		return

	var projectile_threats:Array[Dictionary] = _collect_projectile_threats()
	if not projectile_threats.is_empty():
		var primary:Dictionary = projectile_threats[0]
		var dodge_dir:Vector2 = _choose_dodge_direction(primary,projectile_threats)
		if dodge_dir.length_squared() > 0.001:
			if _jump_cooldown_left <= 0.0 and _projectile_attack_is_hard(primary,projectile_threats,dodge_dir):
				_start_jump(_choose_jump_direction(primary,projectile_threats,dodge_dir))
				_tick_jump(delta)
				return
			_begin_dodge(dodge_dir)
			_tick_dodge(delta)
			return

	if _jump_cooldown_left <= 0.0:
		var hard_dir:Vector2 = _hard_attack_jump_direction()
		if hard_dir.length_squared() > 0.001:
			_start_jump(hard_dir)
			_tick_jump(delta)
			return

	super.tick_physics(state,delta)


func _begin_dodge(wanted:Vector2) -> void:
	if wanted.length_squared() <= 0.001:
		return
	_dodge_direction = wanted.normalized()
	direction = _dodge_direction
	_dodge_time_left = maxf(dodge_duration,0.12)


func _tick_dodge(delta:float) -> void:
	if _dodge_direction.length_squared() <= 0.001:
		_dodge_time_left = 0.0
		return
	direction = _dodge_direction.normalized()
	var base_speed:float = maxf(Speed,0.0) * CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	var wanted_speed:float = base_speed * maxf(dodge_speed_multiplier,1.0)
	Repel += direction * maxf(wanted_speed-base_speed,0.0)
	super.tick_physics(State.Move,delta)
	if direction.length_squared() > 0.001:
		_dodge_direction = direction.normalized()
	_dodge_time_left = maxf(_dodge_time_left-delta,0.0)
	if _dodge_time_left <= 0.0:
		_dodge_direction = Vector2.ZERO


func _start_jump(wanted:Vector2) -> void:
	if wanted.length_squared() <= 0.001 or _jump_is_active() or _jump_cooldown_left > 0.0:
		return
	_jump_direction = wanted.normalized()
	direction = _jump_direction
	_jump_motion_left = maxf(jump_move_time,0.12)
	_jump_recovery_left = maxf(jump_recovery_time,0.0)
	_jump_cooldown_left = maxf(jump_cooldown,0.1)
	_dodge_time_left = 0.0
	_dodge_direction = Vector2.ZERO
	Using_Skill = true
	_set_pounce_visual_everywhere(true)
	_play_pig_sfx_everywhere(PigSfx.SHOUT,global_position,pounce_shout_volume_db,randf_range(0.97,1.03))


func _tick_jump(delta:float) -> void:
	if _jump_motion_left > 0.0:
		var duration:float = maxf(jump_move_time,0.001)
		var progress:float = clampf(1.0-_jump_motion_left/duration,0.0,1.0)
		var eased:float = 1.0-pow(1.0-progress,2.0)
		var jump_speed:float = lerpf(maxf(jump_initial_speed,jump_end_speed),maxf(jump_end_speed,0.0),eased)
		if _jump_direction.length_squared() <= 0.001:
			_jump_direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
		direction = _jump_direction.normalized()
		var base_speed:float = maxf(Speed,0.0) * CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
		Repel += direction * maxf(jump_speed-base_speed,0.0)
		super.tick_physics(State.Move,delta)
		if direction.length_squared() > 0.001:
			_jump_direction = direction.normalized()
		_jump_motion_left = maxf(_jump_motion_left-delta,0.0)
		return

	if _jump_recovery_left > 0.0:
		super.tick_physics(State.Stand,delta)
		_jump_recovery_left = maxf(_jump_recovery_left-delta,0.0)
		if _jump_recovery_left > 0.0:
			return

	Using_Skill = false
	_set_pounce_visual_everywhere(false)
	_jump_direction = Vector2.ZERO


func _jump_is_active() -> bool:
	return _jump_motion_left > 0.0 or _jump_recovery_left > 0.0


func _cancel_jump() -> void:
	_jump_motion_left = 0.0
	_jump_recovery_left = 0.0
	_jump_direction = Vector2.ZERO
	Using_Skill = false
	if _pounce_visual_active:
		_set_pounce_visual_everywhere(false)


func _collect_projectile_threats() -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	var seen:Dictionary = {}

	for projectile:Node2D in _projectile_candidates():
		if projectile == null or not is_instance_valid(projectile) or _projectile_is_friendly(projectile):
			continue
		var id:int = projectile.get_instance_id()
		var motion:Vector2 = _projectile_motion(projectile)
		var info:Dictionary = _build_projectile_prediction(projectile.global_position,motion,_node_collision_radius(projectile),id,projectile)
		if info.is_empty():
			continue
		seen[id] = true
		result.append(info)

	var analyzer:Node = _combat_threat_analyzer()
	if analyzer != null and analyzer.has_method("get_threats_for"):
		var raw:Variant = analyzer.call("get_threats_for",self)
		if raw is Array:
			for value:Variant in raw:
				if not value is Dictionary:
					continue
				var threat:Dictionary = value as Dictionary
				if not _analyzer_threat_is_projectile(threat):
					continue
				var source_id:int = int(threat.get("source_id",0))
				if source_id > 0 and seen.has(source_id):
					continue
				var source:Node2D = _node_from_instance_id(source_id) as Node2D
				if source != null and _projectile_is_friendly(source):
					continue
				var position_value:Variant = threat.get("position",Vector2.ZERO)
				if not position_value is Vector2:
					continue
				var motion:Vector2 = Vector2.ZERO
				var velocity_value:Variant = threat.get("velocity",Vector2.ZERO)
				if velocity_value is Vector2:
					motion = velocity_value as Vector2
				if motion.length_squared() <= 1.0 and source != null:
					motion = _projectile_motion(source)
				var radius:float = maxf(float(threat.get("radius",0.0)),0.0)
				if radius <= 0.0:
					var extent_value:Variant = threat.get("extent",Vector2.ZERO)
					if extent_value is Vector2:
						radius = maxf((extent_value as Vector2).x,(extent_value as Vector2).y)
				if source != null:
					radius = maxf(radius,_node_collision_radius(source))
				var info:Dictionary = _build_projectile_prediction(position_value as Vector2,motion,radius,source_id,source)
				if info.is_empty():
					continue
				if source_id > 0:
					seen[source_id] = true
				result.append(info)

	result.sort_custom(func(a:Dictionary,b:Dictionary) -> bool:
		var ta:float = float(a.get("time",999.0))
		var tb:float = float(b.get("time",999.0))
		if absf(ta-tb) > 0.001:
			return ta < tb
		return float(a.get("miss",9999.0)) < float(b.get("miss",9999.0))
	)
	return result


func _build_projectile_prediction(position_value:Vector2,motion:Vector2,radius:float,source_id:int,source:Node2D) -> Dictionary:
	if motion.length_squared() <= 16.0:
		return {}
	var relative:Vector2 = position_value-global_position
	if relative.length() > maxf(projectile_detect_radius,80.0):
		return {}
	var speed_sq:float = motion.length_squared()
	var raw_time:float = -relative.dot(motion)/speed_sq
	var horizon:float = maxf(projectile_prediction_time,0.30)
	if raw_time < -0.03 or raw_time > horizon:
		return {}
	var time_to_closest:float = clampf(raw_time,0.0,horizon)
	var closest:Vector2 = relative + motion*time_to_closest
	var self_radius:float = _node_collision_radius(self)
	var clearance:float = maxf(self_radius+maxf(radius,2.0)+maxf(projectile_safety_margin,0.0),10.0)
	var miss:float = closest.length()
	if miss > clearance:
		return {}
	return {
		"source_id":source_id,
		"node":source,
		"position":position_value,
		"motion":motion,
		"radius":radius,
		"clearance":clearance,
		"miss":miss,
		"time":time_to_closest,
	}


func _choose_dodge_direction(primary:Dictionary,all_threats:Array[Dictionary]) -> Vector2:
	var motion:Vector2 = primary.get("motion",Vector2.ZERO) as Vector2
	if motion.length_squared() <= 0.001:
		return Vector2.ZERO
	var normal:Vector2 = motion.normalized().orthogonal().normalized()
	var projectile_pos:Vector2 = primary.get("position",global_position) as Vector2
	var signed_offset:float = (global_position-projectile_pos).dot(normal)
	if absf(signed_offset) > 2.0:
		var outward:Vector2 = normal * signf(signed_offset)
		if not _direction_blocked(outward,dodge_wall_probe):
			return outward
	var a:Vector2 = normal
	var b:Vector2 = -normal
	return a if _dodge_side_score(a,all_threats) >= _dodge_side_score(b,all_threats) else b


func _dodge_side_score(candidate:Vector2,threats:Array[Dictionary]) -> float:
	if candidate.length_squared() <= 0.001:
		return -1.0e20
	var dir:Vector2 = candidate.normalized()
	var base_speed:float = maxf(Speed,0.0) * CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	var travel_speed:float = base_speed * maxf(dodge_speed_multiplier,1.0)
	var score:float = 0.0
	if _direction_blocked(dir,dodge_wall_probe):
		score -= 1000.0
	var map_rect:Rect2 = _world_map_rect().grow(-12.0)
	var future_self:Vector2 = global_position + dir*travel_speed*maxf(dodge_duration,0.12)
	if not map_rect.has_point(future_self):
		score -= 1000.0
	for threat:Dictionary in threats:
		var motion:Vector2 = threat.get("motion",Vector2.ZERO) as Vector2
		var pos:Vector2 = threat.get("position",global_position) as Vector2
		var t:float = minf(float(threat.get("time",0.0)),maxf(dodge_duration,0.12))
		var predicted_projectile:Vector2 = pos + motion*t
		var predicted_self:Vector2 = global_position + dir*travel_speed*t
		score += predicted_self.distance_to(predicted_projectile) * 0.02
	if direction.length_squared() > 0.001:
		score += dir.dot(direction.normalized())*0.4
	return score


func _projectile_attack_is_hard(primary:Dictionary,threats:Array[Dictionary],dodge_dir:Vector2) -> bool:
	var time_to_hit:float = maxf(float(primary.get("time",0.0)),0.0)
	if time_to_hit <= maxf(jump_force_time,0.12):
		return true
	var motion:Vector2 = primary.get("motion",Vector2.ZERO) as Vector2
	if motion.length_squared() <= 0.001:
		return false
	var normal:Vector2 = motion.normalized().orthogonal().normalized()
	var projectile_pos:Vector2 = primary.get("position",global_position) as Vector2
	var offset:float = absf((global_position-projectile_pos).dot(normal))
	var clearance:float = maxf(float(primary.get("clearance",16.0)),16.0)
	var needed:float = maxf(clearance-offset+4.0,0.0)
	var base_speed:float = maxf(Speed,0.0) * CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	var dodge_speed:float = base_speed * maxf(dodge_speed_multiplier,1.0)
	var available:float = maxf(time_to_hit-maxf(jump_reaction_buffer,0.0),0.01)
	if needed > dodge_speed*available:
		return true
	var imminent:int = 0
	for threat:Dictionary in threats:
		if float(threat.get("time",999.0)) <= maxf(jump_force_time,0.12)+0.15:
			imminent += 1
	if imminent >= maxi(jump_multi_projectile_count,2):
		return true
	return _direction_blocked(dodge_dir,minf(dodge_wall_probe,32.0)) and time_to_hit < 0.55


func _choose_jump_direction(primary:Dictionary,threats:Array[Dictionary],fallback:Vector2) -> Vector2:
	var motion:Vector2 = primary.get("motion",Vector2.ZERO) as Vector2
	if motion.length_squared() <= 0.001:
		return fallback.normalized() if fallback.length_squared() > 0.001 else Vector2.RIGHT
	var normal:Vector2 = motion.normalized().orthogonal().normalized()
	var a:Vector2 = normal
	var b:Vector2 = -normal
	var score_a:float = _jump_side_score(a,threats)
	var score_b:float = _jump_side_score(b,threats)
	var chosen:Vector2 = a if score_a >= score_b else b
	if _direction_blocked(chosen,48.0) and not _direction_blocked(-chosen,48.0):
		chosen = -chosen
	return chosen.normalized()


func _jump_side_score(candidate:Vector2,threats:Array[Dictionary]) -> float:
	var dir:Vector2 = candidate.normalized()
	var score:float = -500.0 if _direction_blocked(dir,48.0) else 0.0
	var travel:float = (maxf(jump_initial_speed,0.0)+maxf(jump_end_speed,0.0))*0.5*maxf(jump_move_time,0.12)
	var future_self:Vector2 = global_position + dir*travel
	if not _world_map_rect().grow(-12.0).has_point(future_self):
		score -= 1000.0
	for threat:Dictionary in threats:
		var t:float = minf(float(threat.get("time",0.0)),maxf(jump_move_time,0.12))
		var pos:Vector2 = threat.get("position",global_position) as Vector2
		var motion:Vector2 = threat.get("motion",Vector2.ZERO) as Vector2
		var projectile_future:Vector2 = pos + motion*t
		var self_future:Vector2 = global_position + dir*travel*clampf(t/maxf(jump_move_time,0.12),0.0,1.0)
		score += self_future.distance_to(projectile_future)*0.02
	return score


func _hard_attack_jump_direction() -> Vector2:
	var analyzer:Node = _combat_threat_analyzer()
	if analyzer == null or not analyzer.has_method("get_threats_for"):
		return Vector2.ZERO
	var raw:Variant = analyzer.call("get_threats_for",self)
	if not raw is Array:
		return Vector2.ZERO
	var best:Dictionary = {}
	var best_time:float = 999.0
	for value:Variant in raw:
		if not value is Dictionary:
			continue
		var info:Dictionary = value as Dictionary
		if _analyzer_threat_is_projectile(info):
			continue
		if float(info.get("damage",0.0)) <= 0.0 and float(info.get("control",0.0)) <= 0.0:
			continue
		var danger_in:float = maxf(float(info.get("danger_in",999.0)),0.0)
		if danger_in <= maxf(hard_attack_jump_time,0.10) and danger_in < best_time:
			best = info
			best_time = danger_in
	if best.is_empty():
		return Vector2.ZERO
	var center_value:Variant = best.get("position",global_position)
	var center:Vector2 = center_value as Vector2 if center_value is Vector2 else global_position
	var away:Vector2 = global_position-center
	if away.length_squared() <= 0.001:
		var threat_dir_value:Variant = best.get("direction",Vector2.ZERO)
		if threat_dir_value is Vector2 and (threat_dir_value as Vector2).length_squared() > 0.001:
			away = (threat_dir_value as Vector2).normalized().orthogonal()
	if away.length_squared() <= 0.001:
		away = direction if direction.length_squared() > 0.001 else Vector2.RIGHT
	away = away.normalized()
	if _direction_blocked(away,48.0):
		var side_a:Vector2 = away.orthogonal().normalized()
		var side_b:Vector2 = -side_a
		if not _direction_blocked(side_a,48.0):
			away = side_a
		elif not _direction_blocked(side_b,48.0):
			away = side_b
	return away


func _combat_threat_analyzer() -> Node:
	if not is_inside_tree() or get_tree().current_scene == null:
		return null
	return get_tree().current_scene.get_node_or_null("CombatThreatAnalyzer")


func _analyzer_threat_is_projectile(info:Dictionary) -> bool:
	var kind:String = str(info.get("kind","")).to_lower()
	for token:String in ["projectile","bullet","shooter","pellet","missile","rocket","knife","rock"]:
		if kind.find(token) >= 0:
			return true
	var source_id:int = int(info.get("source_id",0))
	var source:Node = _node_from_instance_id(source_id)
	if source != null and _looks_like_projectile(source):
		return true
	var velocity_value:Variant = info.get("velocity",Vector2.ZERO)
	return info.get("shape","") == "circle" and velocity_value is Vector2 and (velocity_value as Vector2).length_squared() > 16.0


func _node_from_instance_id(id:int) -> Node:
	if id <= 0 or not is_instance_id_valid(id):
		return null
	var value:Variant = instance_from_id(id)
	if typeof(value) == TYPE_OBJECT and is_instance_valid(value):
		return value as Node
	return null


func _on_scene_node_added(node:Node) -> void:
	_adopt_new_guest_projectile(node)


func _seed_projectile_registry() -> void:
	if is_inside_tree(): PROJECTILE_API.ensure(get_tree())


func _register_projectile_node(_node:Node) -> void:
	# Compatibility for guest adoption; the shared weak registry owns discovery.
	if is_inside_tree(): PROJECTILE_API.ensure(get_tree())


func _looks_like_projectile(node:Node) -> bool:
	return PROJECTILE_API.live(node)

func _projectile_candidates() -> Array[Node2D]:
	var result:Array[Node2D] = []
	var present:Dictionary = {}
	for node:Node in PROJECTILE_API.candidates(get_tree()):
		if node is Node2D:
			result.append(node)
			present[node.get_instance_id()] = true
	for id:Variant in _projectile_last_positions.keys():
		if not present.has(id):
			_projectile_last_positions.erase(id)
			_projectile_measured_velocity.erase(id)
	return result

func _update_projectile_registry(delta:float) -> void:
	var safe_delta:float = maxf(delta,0.0001)
	for projectile:Node2D in _projectile_candidates():
		var id:int = projectile.get_instance_id()
		var now_pos:Vector2 = projectile.global_position
		if _projectile_last_positions.has(id):
			var last_pos:Vector2 = _projectile_last_positions[id] as Vector2
			var measured:Vector2 = (now_pos-last_pos)/safe_delta
			if measured.length_squared() > 16.0 and measured.length() < 6000.0:
				_projectile_measured_velocity[id] = measured
		_projectile_last_positions[id] = now_pos


func _projectile_motion(node:Node) -> Vector2:
	var motion:Vector2 = PROJECTILE_API.velocity_of(node)
	if not motion.is_zero_approx(): return motion
	return _projectile_measured_velocity.get(node.get_instance_id(),Vector2.ZERO) if is_instance_valid(node) else Vector2.ZERO

func _projectile_is_friendly(projectile:Node2D) -> bool:
	return not PROJECTILE_API.hostile(self,projectile)

func _node_collision_radius(node:Node) -> float:
	if node == null or not is_instance_valid(node):
		return 12.0
	var shape_node:CollisionShape2D = _first_collision_shape(node)
	if shape_node == null or shape_node.shape == null:
		return 12.0
	var shape:Shape2D = shape_node.shape
	var scale_value:Vector2 = shape_node.global_scale.abs()
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius*maxf(scale_value.x,scale_value.y)
	if shape is RectangleShape2D:
		return ((shape as RectangleShape2D).size*scale_value).length()*0.5
	if shape is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape as CapsuleShape2D
		return maxf(capsule.height*scale_value.y*0.5,capsule.radius*scale_value.x)
	return 12.0


func _first_collision_shape(root:Node) -> CollisionShape2D:
	for child:Node in root.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
		var nested:CollisionShape2D = _first_collision_shape(child)
		if nested != null:
			return nested
	return null


func _direction_blocked(dir:Vector2,distance:float) -> bool:
	if dir.length_squared() <= 0.001 or not is_inside_tree():
		return false
	var query:=PhysicsRayQueryParameters2D.create(global_position,global_position+dir.normalized()*maxf(distance,4.0),1)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _spawn_outside_attacker() -> void:
	if outside_attacker_scene_paths.is_empty() or get_tree().current_scene == null:
		return
	var path:String = outside_attacker_scene_paths[_rng.randi_range(0,outside_attacker_scene_paths.size()-1)]
	if not ResourceLoader.exists(path):
		return
	var packed:PackedScene = load(path) as PackedScene
	if packed == null:
		return
	var attacker:Node = packed.instantiate()
	if not attacker is ball:
		attacker.queue_free()
		return
	var rect:Rect2 = _world_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		attacker.queue_free()
		return

	var a:ball = attacker as ball
	a.Team = "PigOutsideAttacker_%d_%d" % [get_instance_id(),Time.get_ticks_msec()]
	a.Target_Enemy = self
	a.Nearest_Enemy = self
	a.Can_Attack = false
	a.Can_Skill = false
	a.Has_Collision_Damage = false
	# 来客只是一段地图外演出，不是第三方参战者。World 会据此排除 VS、血条和胜利阵营统计。
	a.set_meta(&"pig_outside_guest_exempt",true)
	a.set_meta(&"pig_outside_guest_hide_ui",true)
	a.set_meta(&"ignore_combat_targeting",true)
	a.set_meta(&"submission_allow_map_escape",true)
	a.set_meta(&"pig_outside_guest_owner_id",get_instance_id())
	a.set_meta(&"pig_outside_guest_scene_path",path)
	# 接近/离场阶段仍停掉来客 AI；真正开火窗口会临时恢复 StateMachine，
	# 让那些不是通过标准 Attack()（而是 tick/Skill 驱动）的远程角色也能生成自己的原生投射物。
	a.set_process(false)
	a.set_physics_process(false)
	a.collision_layer = 0
	a.collision_mask = 0
	get_tree().current_scene.add_child(a,true)
	# 来客不是参战角色：除了公共 is_combat_targetable=false，再从 Ball group 移除。
	# 这样少数仍直接 get_nodes_in_group("Ball")、没有调用公共契约的旧角色也绝不会锁到它。
	if a.is_in_group("Ball"):
		a.remove_from_group("Ball")
	_active_outside_guests.append(a)
	if a.state_machine != null:
		a.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if a.health_bar != null and is_instance_valid(a.health_bar):
		a.health_bar.visible = false
		a.health_bar.process_mode = Node.PROCESS_MODE_DISABLED
	a.add_to_group("PigOutsideGuest")
	# 少数旧远程脚本（例如收债人）会在自己的 continue_attack() 里再次检查私有 attack_range。
	# 地图外来客只用于向猪发射投射物，因此把这类私有射程临时扩到足以跨越地图；节点离场即销毁，不污染原角色场景。
	if "attack_range" in a:
		a.set("attack_range",maxf(float(a.get("attack_range")),10000.0))
	a.z_as_relative = false
	a.z_index = 91

	var side:int = _rng.randi_range(0,3)
	a.set_meta(&"pig_outside_guest_side",side)
	var route:Dictionary = _build_guest_route(rect,side,a)
	var start_pos:Vector2 = route.get("start",rect.get_center())
	var stage_pos:Vector2 = route.get("stage",rect.get_center())
	var exit_pos:Vector2 = route.get("exit",start_pos)
	var projectile_entry:Vector2 = route.get("projectile_entry",rect.get_center())
	a.global_position = start_pos
	_drive_guest_attack_sequence(a,stage_pos,exit_pos,projectile_entry)


func _guest_visual_half_extent(a:ball,side:int) -> float:
	# 让人物“走到边界”时是图片内缘碰到边界，而不是角色中心走到边界后整张图压进地图。
	var fallback:float = 24.0
	if a == null or not is_instance_valid(a) or not (a.image is Sprite2D):
		return fallback
	var sprite:Sprite2D = a.image as Sprite2D
	if sprite.texture == null:
		return fallback
	var tex_size:Vector2 = sprite.texture.get_size()
	var world_scale_x:float = sprite.global_transform.x.length()
	var world_scale_y:float = sprite.global_transform.y.length()
	var extent:float = tex_size.x * world_scale_x * 0.5 if side <= 1 else tex_size.y * world_scale_y * 0.5
	return clampf(extent,18.0,96.0)


func _build_guest_route(rect:Rect2,side:int,a:ball) -> Dictionary:
	var margin:float = maxf(outside_spawn_margin,18.0)
	var visual_extent:float = _guest_visual_half_extent(a,side)
	# outside_boundary_inset 从 V192 起表示“图片内缘与地图边界的安全空隙”。
	var edge_gap:float = maxf(outside_boundary_inset,2.0)
	var center_offset:float = visual_extent + edge_gap
	var corner_pad:float = minf(32.0,minf(rect.size.x,rect.size.y) * 0.16)
	var min_x:float = rect.position.x + corner_pad
	var max_x:float = rect.end.x - corner_pad
	var min_y:float = rect.position.y + corner_pad
	var max_y:float = rect.end.y - corner_pad
	if min_x > max_x:
		min_x = rect.get_center().x
		max_x = min_x
	if min_y > max_y:
		min_y = rect.get_center().y
		max_y = min_y
	var start:=rect.get_center()
	var stage:=rect.get_center()
	var entry:=rect.get_center()
	var outward:=Vector2.RIGHT
	var projectile_inset:float = maxf(outside_projectile_entry_inset,1.0)
	match side:
		0:
			var y0:float = _rng.randf_range(min_y,max_y)
			outward = Vector2.LEFT
			stage = Vector2(rect.position.x-center_offset,y0)
			start = stage + outward*margin
			entry = Vector2(rect.position.x+projectile_inset,y0)
		1:
			var y1:float = _rng.randf_range(min_y,max_y)
			outward = Vector2.RIGHT
			stage = Vector2(rect.end.x+center_offset,y1)
			start = stage + outward*margin
			entry = Vector2(rect.end.x-projectile_inset,y1)
		2:
			var x0:float = _rng.randf_range(min_x,max_x)
			outward = Vector2.UP
			stage = Vector2(x0,rect.position.y-center_offset)
			start = stage + outward*margin
			entry = Vector2(x0,rect.position.y+projectile_inset)
		_:
			var x1:float = _rng.randf_range(min_x,max_x)
			outward = Vector2.DOWN
			stage = Vector2(x1,rect.end.y+center_offset)
			start = stage + outward*margin
			entry = Vector2(x1,rect.end.y-projectile_inset)
	return {
		"start":start,
		"stage":stage,
		"projectile_entry":entry,
		"exit":start+outward*maxf(outside_exit_extra_distance,12.0),
	}


func _drive_guest_attack_sequence(a:ball,stage_pos:Vector2,exit_pos:Vector2,projectile_entry:Vector2) -> void:
	if a == null or not is_instance_valid(a):
		return
	var inward:Vector2 = stage_pos-a.global_position
	if inward.length_squared() <= 0.001:
		inward = _world_map_rect().get_center()-a.global_position
	if inward.length_squared() <= 0.001:
		inward = Vector2.RIGHT
	a.direction = inward.normalized()
	var walk_speed:float = maxf(outside_walk_speed,70.0)
	var approach_duration:float = clampf(a.global_position.distance_to(stage_pos)/walk_speed,0.20,1.75)
	var approach:=create_tween()
	approach.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	approach.tween_property(a,"global_position",stage_pos,approach_duration)
	await approach.finished
	if not is_instance_valid(a) or not is_instance_valid(self) or health <= 0:
		if is_instance_valid(a):
			_active_outside_guests.erase(a)
			a.queue_free()
		return

	# 人物自身始终停在地图外，只有它生成的投射物会被送到边界内侧几像素，避免地图边界碰撞把子弹挡在外面。
	a.z_as_relative = false
	a.z_index = 91
	a.global_position = stage_pos
	a.Can_Attack = true
	a.Can_Skill = false
	a.set_meta(&"pig_outside_guest_attack_active",true)

	# 开火窗口临时恢复角色自己的 StateMachine。这样数学老师、赌徒、科学家等
	# “投射物逻辑写在 tick/自定义循环里”的角色也会正常工作，而不再只支持覆写 Attack() 的角色。
	a.set_process(true)
	if a.state_machine != null:
		a.state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		a.state_machine.last_state_dis["Attack"] = maxf(float(a.state_machine.last_state_dis.get("Attack",0.0)),a.Attack_Cooling)

	# 某些角色的远程攻击入口不是标准 Attack()；这些适配只负责触发其原生投射物函数，
	# 不复制伤害/速度数值，也不自造替代子弹。
	_prepare_special_outside_guest(a)

	var duration_low:float = minf(outside_attack_duration_min,outside_attack_duration_max)
	var duration_high:float = maxf(outside_attack_duration_min,outside_attack_duration_max)
	var attack_left:float = _rng.randf_range(maxf(duration_low,2.0),maxf(duration_high,2.0))
	var adapter_cooldown_left:float = 0.0
	_escort_guest_projectiles(a,projectile_entry,attack_left+maxf(outside_attack_hold_time,0.35)+0.80)
	while attack_left > 0.0:
		if not is_instance_valid(a) or not is_instance_valid(self) or health <= 0:
			break
		# StateMachine 可以正常跑角色原生攻击，但人物根位置每帧重新钉在边界外，
		# 防止来客自己的移动 AI 与演出 Tween 抢位置。
		a.global_position = stage_pos
		var aim:Vector2 = global_position-a.global_position
		if aim.length_squared() <= 0.001:
			aim = _world_map_rect().get_center()-a.global_position
		if aim.length_squared() <= 0.001:
			aim = Vector2.RIGHT
		a.direction = aim.normalized()
		a.Target_Enemy = self
		a.Nearest_Enemy = self
		if adapter_cooldown_left <= 0.0:
			if _trigger_special_outside_guest_attack(a,aim.normalized()):
				adapter_cooldown_left = maxf(a.Attack_Cooling,0.18)
		await get_tree().physics_frame
		if is_instance_valid(a):
			a.global_position = stage_pos
		var frame_delta:float = get_physics_process_delta_time()
		attack_left -= frame_delta
		adapter_cooldown_left = maxf(adapter_cooldown_left-frame_delta,0.0)

	if not is_instance_valid(a):
		return

	# 停留时间到以后先停止发起新攻击；若最后一次普攻还在前摇/恢复，短暂等它按原逻辑收尾再走。
	a.Can_Attack = false
	a.set_meta(&"pig_outside_guest_attack_active",false)
	var finish_wait:float = maxf(outside_attack_hold_time,0.20)
	while is_instance_valid(a) and a.Attacking and finish_wait > 0.0 and is_instance_valid(self) and health > 0:
		await get_tree().physics_frame
		finish_wait -= get_physics_process_delta_time()
	a.Can_Skill = false
	a.set_process(false)
	if a.state_machine != null:
		a.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	a.Target_Enemy = null
	a.Nearest_Enemy = null
	var out_dir:Vector2 = exit_pos-a.global_position
	if out_dir.length_squared() <= 0.001:
		out_dir = a.global_position-_world_map_rect().get_center()
	if out_dir.length_squared() <= 0.001:
		out_dir = Vector2.RIGHT
	a.direction = out_dir.normalized()
	a.z_as_relative = false
	a.z_index = 91
	var exit_duration:float = clampf(a.global_position.distance_to(exit_pos)/walk_speed,0.22,1.75)
	var leave:=create_tween()
	leave.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	leave.tween_property(a,"global_position",exit_pos,exit_duration)
	await leave.finished
	if is_instance_valid(a):
		_active_outside_guests.erase(a)
		a.queue_free()


func _prepare_special_outside_guest(a:ball) -> void:
	if a == null or not is_instance_valid(a):
		return
	var scene_path:String = str(a.get_meta(&"pig_outside_guest_scene_path",""))
	match scene_path:
		"res://scenes/characters/人物/科学家.tscn":
			# 科学家普通攻击要求先有自己的门；地图外来客入场时先放一扇，随后仍由原脚本决定射击。
			if a.has_method("_place_or_move_next_portal"):
				a.call("_place_or_move_next_portal")
		"res://scenes/characters/人物/赌徒.tscn":
			# 让轮盘循环在本次短暂来客窗口内尽快开始，而不是把整段时间耗在初始等待。
			if "_cycle_left" in a:
				a.set("_cycle_left",0.0)
		"res://scenes/characters/人物/黑帮老大.tscn":
			# 地图外来客只取黑帮老大的远程手枪攻击，不生成其常驻小弟，避免临时来客把召唤物留在战场。
			if "_initial_spawn_done" in a:
				a.set("_initial_spawn_done",true)


func _trigger_special_outside_guest_attack(a:ball,aim:Vector2) -> bool:
	if a == null or not is_instance_valid(a):
		return false
	var scene_path:String = str(a.get_meta(&"pig_outside_guest_scene_path",""))
	var continue_attack_scenes:PackedStringArray = PackedStringArray([
		"res://scenes/characters/三角洲/背刺鼠.tscn",
		"res://scenes/characters/三角洲/夺舍狼.tscn",
		"res://scenes/characters/人物/收债人.tscn",
		"res://scenes/characters/人物/背刺者.tscn",
	])
	if scene_path in continue_attack_scenes:
		# 这些旧角色的 Attack() 只给直接控制入口使用，AI 连射实际写在 continue_attack()。
		if a.has_method("continue_attack"):
			a.call("continue_attack")
			return true
	elif scene_path == "res://scenes/characters/游戏/战争女神.tscn":
		# 地图外不会进入她的近距离检测 Area；直接调用她自己的火焰剑气生成函数。
		if a.has_method("_spawn_war_projectile_everywhere"):
			a.call("_spawn_war_projectile_everywhere",aim)
			return true
	elif scene_path == "res://scenes/characters/乐队/薇欧拉.tscn":
		# 薇欧拉的文字弹平时来自录制结算；来客窗口直接触发一发她自己的文字弹幕。
		if a.has_method("_spawn_text_barrage"):
			a.call("_spawn_text_barrage",1)
			return true
	elif scene_path == "res://scenes/characters/人物/黑帮老大.tscn":
		if a.has_method("_begin_ranged_attack"):
			a.call("_begin_ranged_attack",self)
			return true
	return false


func _escort_guest_projectiles(a:ball,entry_pos:Vector2,duration:float) -> void:
	# Attack() 有同步生成和延迟 windup 后生成两类实现；短时间逐 physics frame 扫描，确保两类都能穿过地图边界。
	var remaining:float = maxf(duration,0.20)
	while remaining > 0.0 and is_instance_valid(a) and is_inside_tree():
		_push_existing_guest_projectiles_inside(a,entry_pos)
		await get_tree().physics_frame
		remaining -= get_physics_process_delta_time()


func _push_existing_guest_projectiles_inside(a:ball,_entry_pos:Vector2) -> void:
	if a == null or not is_instance_valid(a) or get_tree().current_scene == null:
		return
	# node_added 已负责“出生即入场”；这里保留扫描作为旧投射物/延迟初始化的保险。
	var candidates:Array[Node2D] = _projectile_candidates()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is Node2D and not candidates.has(node as Node2D):
			candidates.append(node as Node2D)
	for node:Node in get_tree().get_nodes_in_group("Shooter"):
		if node is Node2D and not candidates.has(node as Node2D):
			candidates.append(node as Node2D)
	for visual:Node2D in candidates:
		if visual == a or not _node_belongs_to_guest_attack(visual,a):
			continue
		_adopt_guest_projectile(visual,a)


func _adopt_new_guest_projectile(node:Node) -> void:
	if node == null or not node is Node2D or _active_outside_guests.is_empty():
		return
	for guest:Node in _active_outside_guests.duplicate():
		if guest == null or not is_instance_valid(guest) or not guest is ball:
			continue
		if _node_belongs_to_guest_attack(node,guest as ball):
			_adopt_guest_projectile(node as Node2D,guest as ball)
			return


func _guest_projectile_entry_position(raw_position:Vector2,side:int,projectile:Node2D = null,guest:ball = null) -> Vector2:
	var rect:Rect2 = _world_map_rect()
	var pad:float = 4.0
	var inward:=Vector2.RIGHT
	var boundary:=raw_position
	match side:
		0:
			inward = Vector2.RIGHT
			boundary = Vector2(rect.position.x,clampf(raw_position.y,rect.position.y+pad,rect.end.y-pad))
		1:
			inward = Vector2.LEFT
			boundary = Vector2(rect.end.x,clampf(raw_position.y,rect.position.y+pad,rect.end.y-pad))
		2:
			inward = Vector2.DOWN
			boundary = Vector2(clampf(raw_position.x,rect.position.x+pad,rect.end.x-pad),rect.position.y)
		_:
			inward = Vector2.UP
			boundary = Vector2(clampf(raw_position.x,rect.position.x+pad,rect.end.x-pad),rect.end.y)

	# V195：固定 5px inset 对厚边界碰撞体不可靠。
	# 从边界向地图内逐步探测，找到第一个“周围没有非角色物理体”的安全点，
	# 相当于把来客子弹直接放到边界墙的内侧，而不是赌墙只有几像素厚。
	var start_depth:float = maxf(outside_projectile_entry_inset,2.0)
	var max_depth:float = maxf(outside_projectile_entry_max_depth,start_depth)
	var step:float = maxf(outside_projectile_entry_step,2.0)
	var depth:float = start_depth
	while depth <= max_depth + 0.001:
		var candidate:Vector2 = boundary + inward * depth
		if _guest_projectile_entry_is_clear(candidate,projectile,guest):
			return candidate
		depth += step
	return boundary + inward * max_depth


func _guest_projectile_entry_is_clear(position_value:Vector2,projectile:Node2D,guest:ball) -> bool:
	if not is_inside_tree():
		return true
	var shape:=CircleShape2D.new()
	shape.radius = maxf(outside_projectile_clearance_radius,2.0)
	var params:=PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0,position_value)
	params.collision_mask = 3
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var exclude:Array[RID] = [get_rid()]
	if guest != null and is_instance_valid(guest):
		exclude.append(guest.get_rid())
	if projectile is CollisionObject2D:
		exclude.append((projectile as CollisionObject2D).get_rid())
	params.exclude = exclude
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(params,32):
		var collider:Variant = hit.get("collider",null)
		if collider == null or collider is ball:
			continue
		return false
	return true

func _adopt_guest_projectile(visual:Node2D,a:ball) -> void:
	if visual == null or not is_instance_valid(visual) or a == null or not is_instance_valid(a):
		return
	if visual.has_meta(&"pig_outside_guest_projectile") and int(visual.get_meta(&"pig_outside_guest_owner_id",0)) == get_instance_id():
		return
	var side:int = int(a.get_meta(&"pig_outside_guest_side",0))
	var entry_pos:Vector2 = _guest_projectile_entry_position(visual.global_position,side,visual,a)
	var rect:Rect2 = _world_map_rect()
	# 来客本体必须留在地图外。投射物只要还在地图外，或者虽然坐标已经进图但仍嵌在边界碰撞带里，
	# 都直接送到上面探测出的第一个安全点。
	if not rect.has_point(visual.global_position) or not _guest_projectile_entry_is_clear(visual.global_position,visual,a):
		visual.global_position = entry_pos
	var desired_dir:Vector2 = global_position-visual.global_position
	if desired_dir.length_squared() <= 0.001:
		desired_dir = rect.get_center()-visual.global_position
	if desired_dir.length_squared() <= 0.001:
		desired_dir = Vector2.RIGHT
	desired_dir = desired_dir.normalized()
	if "direction" in visual:
		visual.set("direction",desired_dir)
	if "velocity" in visual:
		var current_velocity:Variant = visual.get("velocity")
		if current_velocity is Vector2:
			var speed_value:float = (current_velocity as Vector2).length()
			if speed_value > 0.01:
				visual.set("velocity",desired_dir*speed_value)
	# 猎人霰弹等原角色自带很短最大射程。作为地图外来客时必须至少能够从边界飞到猪。
	if "max_distance" in visual:
		var needed_range:float = visual.global_position.distance_to(global_position)+96.0
		visual.set("max_distance",maxf(float(visual.get("max_distance")),needed_range))
	if "_travelled" in visual:
		visual.set("_travelled",0.0)
	for travel_property:String in ["travelled_distance","_distance_travelled","distance_travelled","distance_traveled"]:
		if travel_property in visual:
			visual.set(travel_property,0.0)
	if visual is CanvasItem:
		(visual as CanvasItem).z_as_relative = true
	visual.set_meta(&"pig_outside_guest_projectile",true)
	visual.set_meta(&"pig_outside_guest_owner_id",get_instance_id())
	visual.set_meta(&"submission_allow_map_escape",true)
	if not visual.is_in_group("PigOutsideGuestProjectile"):
		visual.add_to_group("PigOutsideGuestProjectile")
	_register_projectile_node(visual)


func _node_belongs_to_guest_attack(node:Node,a:ball) -> bool:
	if node == null or a == null:
		return false
	if "Master" in node:
		var master_value:Variant = node.get("Master")
		if master_value == a:
			return true
	if "Master_name" in node:
		var master_name:String = str(node.get("Master_name"))
		if master_name == str(a.name) or master_name == str(a.get_path()):
			return true
	# 兼容某些旧投射物：先 add_child，随后才填写 Master/Master_name。
	# 来客攻击窗口内，如果一个“看起来就是投射物”的新节点出生在来客身边，也视为本次来客攻击。
	if (
		node is Node2D
		and a.has_meta(&"pig_outside_guest_attack_active")
		and bool(a.get_meta(&"pig_outside_guest_attack_active"))
		and _looks_like_projectile(node)
		and (node as Node2D).global_position.distance_to(a.global_position) <= 150.0
	):
		return true
	return false


func _cleanup_outside_guests() -> void:
	if _guest_cleanup_running:
		return
	_guest_cleanup_running = true
	var owner_id:int = get_instance_id()
	for guest:Node in _active_outside_guests.duplicate():
		if guest != null and is_instance_valid(guest):
			guest.queue_free()
	_active_outside_guests.clear()
	if is_inside_tree():
		for guest:Node in get_tree().get_nodes_in_group("PigOutsideGuest"):
			if guest == null or not is_instance_valid(guest):
				continue
			if int(guest.get_meta(&"pig_outside_guest_owner_id",0)) == owner_id:
				guest.queue_free()
		for projectile:Node in get_tree().get_nodes_in_group("PigOutsideGuestProjectile"):
			if projectile == null or not is_instance_valid(projectile):
				continue
			if int(projectile.get_meta(&"pig_outside_guest_owner_id",0)) == owner_id:
				projectile.queue_free()
	_guest_cleanup_running = false


func _world_map_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world != null and "map_group" in world and "now_choose_map" in world and world.has_method("return_map_world_rect"):
		var maps:Variant = world.get("map_group")
		var key:String = str(world.get("now_choose_map"))
		if maps is Dictionary and (maps as Dictionary).has(key):
			return world.call("return_map_world_rect",(maps as Dictionary)[key]) as Rect2
	return Rect2(global_position-Vector2(360,220),Vector2(720,440))


func _set_pounce_visual_everywhere(active:bool) -> void:
	if _pounce_visual_active == active:
		return
	_pounce_visual_active = active
	if multiplayer.has_multiplayer_peer():
		_rpc_set_pig_visual.rpc(active)
	else:
		_rpc_set_pig_visual(active)


@rpc("authority","call_local","unreliable")
func _rpc_set_pig_visual(active:bool) -> void:
	_pounce_visual_active = active
	_set_pig_visual(active)


func _set_pig_visual(pounce:bool) -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D
	var texture_value:Texture2D = PIG_POUNCE_TEXTURE if pounce else PIG_NORMAL_TEXTURE
	if texture_value == null:
		return
	sprite.visible = true
	sprite.texture = texture_value
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	sprite.self_modulate = Color.WHITE
	var target_height:float = pounce_visual_height if pounce else normal_visual_height
	var scale_value:float = maxf(target_height,1.0) / maxf(float(texture_value.get_height()),1.0)
	sprite.scale = Vector2.ONE * scale_value


func _play_pig_sfx_everywhere(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_pig_sfx.rpc(kind,position_value,volume_db,pitch)
	else:
		_rpc_play_pig_sfx(kind,position_value,volume_db,pitch)


@rpc("authority","call_local","unreliable")
func _rpc_play_pig_sfx(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	var stream:AudioStream = PIG_GRUNT_SFX if kind == PigSfx.GRUNT else PIG_SHOUT_SFX
	if stream == null or get_tree().current_scene == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "PigVoice"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch,0.85,1.15)
	player.max_distance = 1250.0
	player.attenuation = 0.55
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
