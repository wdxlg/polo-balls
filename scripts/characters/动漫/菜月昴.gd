extends ball

const DEATH_RETURN_TIMELINE = preload("res://scripts/characters/动漫/死亡回归时间轴.gd")
const WHIP_SCRIPT = preload("res://scripts/characters/动漫/菜月昴惯性鞭.gd")
const DEAD_SAVE_EFFECT = preload("res://scripts/effects/动漫/菜月昴死档效果.gd")
const NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/动漫/菜月昴/昴.png")
const RETURN_TEXTURE:Texture2D = preload("res://Images/characters/动漫/菜月昴/死亡回归.png")
const RETURN_MUSIC:AudioStream = preload("res://audio/characters/菜月昴/《re0从零开始的异世界》无损音乐集试听 P1 【4KHi-res_完整版】STYX HELIX（冥河螺旋）《Re：从零开始的异世界》ED 中日歌词 试听.mp3")
const SHADOW_HAND_TEXTURE:Texture2D = preload("res://Images/characters/动漫/菜月昴/ChatGPT_Image_2026年9月3日_04_38_31.png")
const RETURN_BY_DEATH_SFX:AudioStream = preload("res://audio/characters/菜月昴/死亡回归.mp3")
const PUNCH_SWING_SFX:AudioStream = preload("res://audio/characters/拳击手/拳击手_挥拳.mp3")
const PUNCH_HIT_SFX:AudioStream = preload("res://audio/characters/拳击手/拳击手_命中.mp3")
const RETURN_SCREAMS:Array[AudioStream] = [
	preload("res://audio/characters/菜月昴/叫1.MP3"),
	preload("res://audio/characters/菜月昴/叫2.MP3"),
	preload("res://audio/characters/菜月昴/叫3.MP3"),
	preload("res://audio/characters/菜月昴/叫4.MP3"),
	preload("res://audio/characters/菜月昴/叫5.MP3"),
	preload("res://audio/characters/菜月昴/叫6.MP3"),
	preload("res://audio/characters/菜月昴/叫7.MP3"),
	preload("res://audio/characters/菜月昴/叫8.MP3"),
	preload("res://audio/characters/菜月昴/叫9.MP3"),
	preload("res://audio/characters/菜月昴/叫10.MP3"),
	preload("res://audio/characters/菜月昴/叫11.MP3"),
	preload("res://audio/characters/菜月昴/叫12.MP3"),
	preload("res://audio/characters/菜月昴/叫13.MP3"),
	preload("res://audio/characters/菜月昴/叫14.MP3"),
]

@export_category("菜月昴 - 惯性鞭与间歇手臂")
@export var whip_damage:float = 5.0
@export var whip_interval:float = 1.1
@export var whip_reach:float = 85.0
@export var whip_swing_duration:float = 0.65
@export var whip_knockback:float = 38.0
@export var hand_hidden_duration:float = 6.0
@export var hand_active_duration:float = 3.0
var _whip:Node2D
var _hand_window_left:float = 6.0
var _hand_window_active:bool = false
var _fist_phase:float = -1.0
var _fist_locked_world:Vector2 = Vector2.ZERO
@export_category("菜月昴 - 盘旋拳")
@export_range(0.25,4.0,0.05) var fist_spawn_interval:float = 1.10
@export_range(12.0,90.0,1.0) var fist_rest_radius:float = 38.0
@export_range(20.0,320.0,1.0) var fist_trigger_radius:float = 138.0
@export_range(25.0,360.0,1.0) var fist_attack_reach:float = 178.0
@export_range(0.05,0.8,0.01) var fist_extend_time:float = 0.18
@export_range(0.05,0.8,0.01) var fist_return_time:float = 0.20
@export_range(0.0,720.0,5.0) var fist_orbit_degrees_per_second:float = 110.0
@export_range(60.0,720.0,10.0) var fist_turn_degrees_per_second:float = 300.0
@export_range(0.0,180.0,1.0) var fist_knockback_strength:float = 48.0

@export_category("菜月昴 - 手臂/手区域")
# 原图 2048x682。两块区域都引用同一张用户原图；可在 Inspector 直接重新规划，不生成第二套图片。
@export var fist_arm_source_region:Rect2 = Rect2(0.0,0.0,1580.0,682.0)
@export var fist_hand_source_region:Rect2 = Rect2(1480.0,0.0,568.0,682.0)
@export_range(8.0,90.0,1.0) var fist_arm_width:float = 34.0
@export_range(12.0,100.0,1.0) var fist_hand_visual_size:float = 48.0
@export_range(6.0,60.0,1.0) var fist_hand_hit_radius:float = 20.0
@export_range(4,40,1) var fist_arm_curve_samples:int = 14
# x=沿伸长方向的比例；y=相对手臂长度的侧向偏移比例。修改两点即可自由拉长/弯曲/扭曲手臂。
@export var fist_arm_control_points:PackedVector2Array = PackedVector2Array([
	Vector2(0.30,-0.16),
	Vector2(0.70,0.13),
])
@export_range(-1.0,1.0,0.01) var fist_dynamic_bend:float = 0.08

@export_category("菜月昴 - 死亡回归")
@export_range(0.04,0.25,0.01) var rewind_snapshot_interval:float = 0.10
@export_range(0.0,0.95,0.01) var rewind_shrink_ratio_per_return:float = 0.5
@export_range(0.5,2.0,0.1) var rewind_min_seconds:float = 0.50
@export_range(5.0,175.0,1.0) var return_direction_step_degrees:float = 47.0
@export_range(0.25,6.0,0.05) var return_visual_duration:float = 1.80
@export_range(-40.0,18.0,0.5) var return_scream_volume_db:float = 18.0
@export_range(-40.0,18.0,0.5) var return_sound_volume_db:float = -8.0
@export_range(100.0,5000.0,50.0) var return_scream_max_distance:float = 2400.0
@export_range(1,12,1) var return_music_start_count:int = 3
@export_range(-40.0,6.0,0.5) var return_music_volume_db:float = -7.0
@export_range(1,100,1) var dead_save_trigger_deaths:int = 5

var _fist_root:Node2D = null
var _fist_arm:Line2D = null
var _fist_head:Sprite2D = null
var _fist_sfx_player:AudioStreamPlayer2D = null
var _fist_hit_area:Area2D = null
var _fist_hit_shape:CollisionShape2D = null
var _fist_strike_active:bool = false
var _fist_hit_targets:Dictionary = {}
var _fist_ready_timer:float = 0.0
var _fist_orbit_angle:float = 0.0
var _fist_visual_angle:float = 0.0
var _fist_visual_angle_initialized:bool = false
var _fist_busy:bool = false
var _fist_target_id:int = 0
var _fist_return_from:Vector2 = Vector2.ZERO
# V335：待机不可视之手使用逐段阻尼跟随。根部先响应，越靠近拳头响应越慢。
var _fist_chain_points:PackedVector2Array = PackedVector2Array()
var _fist_chain_velocities:PackedVector2Array = PackedVector2Array()
var _fist_last_owner_global_position:Vector2 = Vector2.ZERO
var _fist_chain_initialized:bool = false
var _timeline:Node = null
var _returning:bool = false
var _return_request_epoch:int = 0
var _opening_direction:Vector2 = Vector2.RIGHT
var _normal_image_scale:Vector2 = Vector2.ONE
var _normal_image_offset:Vector2 = Vector2.ZERO
var _return_image_scale:Vector2 = Vector2.ONE
var _return_visual_timer:Timer = null
var _return_scream_player:AudioStreamPlayer = null
var _return_sound_player:AudioStreamPlayer = null
var _return_music_player:AudioStreamPlayer = null
var _return_music_started:bool = false
var _return_presentation_initialized:bool = false
# 以 _return 开头，死亡回归时间轴会主动排除该字段，不会把“已死档”状态倒回 false。
var _return_dead_save_triggered:bool = false

func _ready() -> void:
	Max_health = 67
	Damage = 67
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	super._ready()
	_opening_direction = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_fist_visual_angle = _opening_direction.angle()
	_fist_visual_angle_initialized = true
	_fist_last_owner_global_position = global_position
	_setup_return_presentation()
	_ensure_fist_visual()
	_ensure_death_return_timeline()
	_whip = WHIP_SCRIPT.new()
	_whip.name = "惯性鞭"
	add_child(_whip)
	_hand_window_left = hand_hidden_duration
	_set_fist_visible(false)

func has_collision_damage() -> bool:
	return false

func _ensure_death_return_timeline() -> void:
	if _timeline != null and is_instance_valid(_timeline):
		return
	var current_world:Node = get_tree().current_scene
	if current_world == null:
		return
	var timeline_name:String = "V323死亡回归时间轴_%d" % get_instance_id()
	var timeline:Node = DEATH_RETURN_TIMELINE.new()
	timeline.name = timeline_name
	current_world.add_child(timeline)
	timeline.call("initialize",self,rewind_snapshot_interval,rewind_shrink_ratio_per_return,rewind_min_seconds)
	_timeline = timeline

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not is_multiplayer_authority() or _returning or health <= 0:
		return
	if not is_combat_runtime_active() or is_damage_output_disabled():
		_update_fist_rest_visual(delta)
		return
	if is_instance_valid(_whip): _whip.advance(delta)
	_hand_window_left -= maxf(delta,0.0)
	if _hand_window_left <= 0.0:
		_hand_window_active = not _hand_window_active
		_hand_window_left = maxf(hand_active_duration if _hand_window_active else hand_hidden_duration,0.1)
		if not _hand_window_active: _finish_fist_cycle()
	_set_fist_visible(_hand_window_active)
	if _hand_window_active: _update_fist_logic(delta)

func controlled_attack_action() -> void:
	# 左键惯性鞭；鞭的冷却与摆动仍由原子实体推进，不再 AI 自行找敌。
	if not is_player_controlled() or not is_multiplayer_authority() or _returning or health <= 0 or not is_combat_runtime_active() or not has_player_control_aim():
		return
	if is_instance_valid(_whip):
		_whip.call("request_manual_swing",player_control_aim_world_position())

func controlled_skill_action() -> void:
	# 右键盘旋拳：只在可见之手窗口、原出拳间隔和触发距离内出拳。
	if not is_player_controlled() or not is_multiplayer_authority() or _returning or health <= 0 or not is_combat_runtime_active() or not has_player_control_aim():
		return
	if not _hand_window_active or _fist_busy or _fist_ready_timer < fist_spawn_interval:
		return
	var aim:Vector2 = player_control_aim_world_position()
	if global_position.distance_to(aim) > fist_trigger_radius:
		return
	_fist_busy = true
	_fist_target_id = 0
	_perform_fist_attack_at_point(aim)

func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	super.on_actual_health_damage_received(actual_health_damage,health_before)
	if health <= 0 and is_multiplayer_authority():
		_trigger_return_by_death()

func _trigger_return_by_death() -> void:
	if _returning:
		return
	_ensure_death_return_timeline()
	if _timeline == null or not is_instance_valid(_timeline):
		return

	# V324：致死伤害可能发生在 Area2D/body 的物理查询回调内。V323 在这里同步
	# 重建整场节点，会让被重建 ball 的 _ready() 在 PhysicsServer2D flush query 期间
	# 修改 CollisionShape2D/Area2D，产生 flushing queries 报错。
	# 先把自己暂时保活并停掉物理处理，再把真正的整场回归延迟到安全的 deferred 阶段。
	_returning = true
	_return_request_epoch = int(get_tree().current_scene.get_meta("death_return_generation",0))
	_fist_busy = false
	_fist_target_id = 0
	set_physics_process(false)
	if health <= 0:
		# 死亡回归本身不是治疗；临时保活不能生成绿色回血跳字。
		var old_suppress:bool = false
		var can_suppress:bool = health_bar != null and is_instance_valid(health_bar)
		if can_suppress:
			old_suppress = bool(health_bar.suppress_floating_text)
			health_bar.suppress_floating_text = true
		health = 1
		if can_suppress and health_bar != null and is_instance_valid(health_bar):
			health_bar.suppress_floating_text = old_suppress
	call_deferred("_perform_death_return_deferred")

func _perform_death_return_deferred() -> void:
	if not _returning or not is_inside_tree():
		return
	if _timeline == null or not is_instance_valid(_timeline):
		_returning = false
		set_physics_process(true)
		return

	var current_world:Node = get_tree().current_scene
	while is_instance_valid(current_world) and current_world.has_meta("death_return_restoring"):
		await get_tree().process_frame
	if not is_instance_valid(current_world): return
	if int(current_world.get_meta("death_return_generation",0)) != _return_request_epoch:
		_returning = false
		set_physics_process(true)
		return # Another Subaru already removed this death from the timeline.
	# V325：时间轴恢复现在会按每帧时间预算分片；这里必须 await 完整恢复，
	# 避免角色在战场尚未恢复完时提前重新参与物理与攻击。
	var result:Dictionary = await _timeline.call("perform_death_return")
	if result.is_empty():
		_returning = false
		set_physics_process(true)
		return
	var count:int = int(result.get("return_count",1))
	set_physics_process(true)
	_returning = false
	_trigger_dead_save_if_needed(count)
	_broadcast_return_presentation(count)

func _trigger_dead_save_if_needed(return_count_value:int) -> void:
	if _return_dead_save_triggered:
		return
	if return_count_value < maxi(dead_save_trigger_deaths,1):
		return
	_return_dead_save_triggered = true
	if multiplayer.has_multiplayer_peer():
		_present_dead_save_effect.rpc()
	else:
		_present_dead_save_effect()

@rpc("authority","call_local","reliable")
func _present_dead_save_effect() -> void:
	var current_world:Node = get_tree().current_scene
	if current_world == null or not is_instance_valid(current_world):
		return
	# 全局效果只创建一次。即使同局有多个菜月昴同时达到阈值，也不会叠两层黑幕/音效。
	var existing:Node = current_world.get_node_or_null("菜月昴_死亡回归死档")
	if existing != null and is_instance_valid(existing):
		return
	var effect:Node = DEAD_SAVE_EFFECT.new()
	if effect == null:
		return
	current_world.add_child(effect)
	if effect.has_method("activate"):
		effect.call("activate",self)

func _setup_return_presentation() -> void:
	if not _return_presentation_initialized and image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = NORMAL_TEXTURE
		_normal_image_scale = sprite.scale
		_normal_image_offset = sprite.offset
		_return_image_scale = _fit_scale_for_return_texture(sprite)
		_return_presentation_initialized = true
	if _return_visual_timer == null or not is_instance_valid(_return_visual_timer):
		_return_visual_timer = Timer.new()
		_return_visual_timer.name = "死亡回归视觉计时"
		_return_visual_timer.one_shot = true
		_return_visual_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_return_visual_timer.timeout.connect(_restore_normal_return_visual)
		add_child(_return_visual_timer)
	if _return_scream_player == null or not is_instance_valid(_return_scream_player):
		_return_scream_player = AudioStreamPlayer.new()
		_return_scream_player.name = "死亡回归叫声"
		if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
			_return_scream_player.bus = &"GameplayRecord"
		add_child(_return_scream_player)
	if _return_sound_player == null or not is_instance_valid(_return_sound_player):
		_return_sound_player = AudioStreamPlayer.new()
		_return_sound_player.name = "死亡回归"
		_return_sound_player.stream = RETURN_BY_DEATH_SFX
		_return_sound_player.volume_db = return_sound_volume_db
		if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
			_return_sound_player.bus = &"GameplayRecord"
		add_child(_return_sound_player)

func _fit_scale_for_return_texture(sprite:Sprite2D) -> Vector2:
	if NORMAL_TEXTURE == null or RETURN_TEXTURE == null:
		return sprite.scale
	var normal_size:Vector2 = NORMAL_TEXTURE.get_size()
	var return_size:Vector2 = RETURN_TEXTURE.get_size()
	var normal_longest:float = maxf(normal_size.x,normal_size.y)
	var return_longest:float = maxf(return_size.x,return_size.y)
	if normal_longest <= 0.0 or return_longest <= 0.0:
		return sprite.scale
	return sprite.scale * (normal_longest / return_longest)

func _broadcast_return_presentation(return_count_value:int) -> void:
	var scream_index:int = -1
	if not RETURN_SCREAMS.is_empty():
		scream_index = randi_range(0,RETURN_SCREAMS.size() - 1)
	if multiplayer.has_multiplayer_peer():
		_present_return_presentation.rpc(return_count_value,scream_index)
	else:
		_present_return_presentation(return_count_value,scream_index)

@rpc("authority","call_local","reliable")
func _present_return_presentation(return_count_value:int,scream_index:int) -> void:
	_setup_return_presentation()
	_show_return_visual_local()
	_play_return_sound_local()
	_play_return_scream_local(scream_index)
	# V326：音乐只允许“恰好第3次（或 Inspector 指定次数）”触发一次。
	# 后续死亡回归不再补触发/重播，即使播放器后来被停止也不会因为第4次、第5次回归重新开始。
	if return_count_value == maxi(return_music_start_count,1):
		_start_return_music_local()

func _show_return_visual_local() -> void:
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = RETURN_TEXTURE
		sprite.scale = _return_image_scale
		sprite.offset = Vector2.ZERO
	if _return_visual_timer != null and is_instance_valid(_return_visual_timer):
		_return_visual_timer.start(maxf(return_visual_duration,0.05))

func _restore_normal_return_visual() -> void:
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = NORMAL_TEXTURE
		sprite.scale = _normal_image_scale
		sprite.offset = _normal_image_offset

func _play_return_sound_local() -> void:
	_setup_return_presentation()
	if _return_sound_player == null or not is_instance_valid(_return_sound_player):
		return
	_return_sound_player.stop()
	_return_sound_player.stream = RETURN_BY_DEATH_SFX
	_return_sound_player.volume_db = return_sound_volume_db
	_return_sound_player.pitch_scale = 1.0
	_return_sound_player.play()

func _play_return_scream_local(index:int) -> void:
	if index < 0 or index >= RETURN_SCREAMS.size():
		return
	_setup_return_presentation()
	if _return_scream_player == null or not is_instance_valid(_return_scream_player):
		return
	_return_scream_player.stop()
	_return_scream_player.stream = RETURN_SCREAMS[index]
	_return_scream_player.volume_db = return_scream_volume_db
	_return_scream_player.pitch_scale = 1.0
	_return_scream_player.play()

func _start_return_music_local() -> void:
	if _return_music_started:
		return
	if _return_music_player == null or not is_instance_valid(_return_music_player):
		_return_music_player = AudioStreamPlayer.new()
		_return_music_player.name = "死亡回归三次后音乐"
		var music_stream:AudioStream = RETURN_MUSIC.duplicate() as AudioStream
		if music_stream is AudioStreamMP3:
			(music_stream as AudioStreamMP3).loop = true
		_return_music_player.stream = music_stream
		_return_music_player.volume_db = return_music_volume_db
		if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
			_return_music_player.bus = &"GameplayRecord"
		add_child(_return_music_player)
	_return_music_started = true
	_return_music_player.play()

func _update_fist_logic(delta:float) -> void:
	_ensure_fist_visual()
	_fist_orbit_angle = wrapf(_fist_orbit_angle + deg_to_rad(fist_orbit_degrees_per_second) * delta,-PI,PI)
	if _fist_busy:
		_advance_fist_attack(delta)
		return
	_fist_ready_timer += maxf(delta,0.0)
	_set_fist_visible(true)
	_update_fist_rest_visual(delta)
	if _fist_ready_timer < fist_spawn_interval or is_player_controlled():
		return
	var target:ball = _find_fist_target()
	if target != null and global_position.distance_to(target.global_position) <= fist_trigger_radius:
		_fist_busy = true
		_fist_target_id = target.get_instance_id()
		_perform_fist_attack(target)

func _find_fist_target() -> ball:
	var best:ball = null
	var best_distance:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if candidate == self or not is_instance_valid(candidate) or candidate.health <= 0:
			continue
		if not candidate.is_combat_targetable():
			continue
		if (
			Team != ""
			and candidate.Team != ""
			and candidate.Team == Team
		):
			continue
		var distance:float = global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _perform_fist_attack(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not _hand_window_active:
		_finish_fist_cycle()
		return
	_perform_fist_attack_at_point(target.global_position)

func _perform_fist_attack_at_point(point:Vector2) -> void:
	_fist_locked_world = global_position+global_position.direction_to(point)*minf(global_position.distance_to(point),fist_attack_reach)
	_fist_phase = 0.0
	_fist_hit_targets.clear()
	_set_fist_strike_active(true)
	_set_fist_visible(true)
	_play_fist_sfx(PUNCH_SWING_SFX)

func _advance_fist_attack(delta:float) -> void:
	_fist_phase += maxf(delta,0.0)
	var rest:PackedVector2Array = _rest_arm_controls()
	_ensure_fist_chain_state(rest)
	var old_tip:Vector2 = to_global(_fist_chain_points[-1])
	var out_time:float = maxf(fist_extend_time,0.05)+0.12
	var back_time:float = maxf(fist_return_time,0.05)+0.15
	var weight:float = 1.0 if _fist_phase <= out_time else clampf(1.0-(_fist_phase-out_time)/back_time,0.0,1.0)
	var tip:Vector2 = to_local(_fist_locked_world)
	var dt:float = minf(maxf(delta,0.0),0.05)
	for i:int in range(rest.size()):
		var ratio:float = float(i)/float(maxi(rest.size()-1,1))
		var desired:Vector2 = rest[i].lerp(rest[0].lerp(tip,ratio),weight)
		# Distal joints react later; the arm stays curved instead of snapping straight.
		var k:float = lerpf(1600.0,850.0,ratio)
		_fist_chain_velocities[i] += (desired-_fist_chain_points[i])*k*dt
		_fist_chain_velocities[i] *= exp(-lerpf(60.0,40.0,ratio)*dt)
		_fist_chain_points[i] += _fist_chain_velocities[i]*dt
	_apply_fist_geometry(_fist_chain_points[-1],_fist_chain_points)
	if _fist_strike_active: _sweep_fist(old_tip,to_global(_fist_chain_points[-1]))
	if _fist_phase > out_time: _set_fist_strike_active(false)
	if _fist_phase >= out_time+back_time: _finish_fist_cycle()

func _sweep_fist(start:Vector2,end:Vector2) -> void:
	var ray := PhysicsRayQueryParameters2D.create(global_position,end,1,[get_rid()])
	if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return
	var shape := CapsuleShape2D.new()
	shape.radius = maxf(fist_hand_hit_radius*global_scale.x,1.0)
	shape.height = start.distance_to(end)+shape.radius*2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D((end-start).angle()-PI*0.5,(start+end)*0.5)
	query.collision_mask = 2
	query.exclude = [get_rid()]
	for result:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,32):
		if result.collider is ball: _on_fist_area_entered(result.collider.self_hurtbox)

func _begin_fist_return(attack_local:Vector2) -> void:
	_set_fist_strike_active(false)
	_fist_return_from = attack_local

func _on_fist_area_entered(area:Area2D) -> void:
	if not _hand_window_active or _returning or not is_combat_runtime_active() or not _fist_strike_active or not is_multiplayer_authority() or is_damage_output_disabled():
		return
	if not area is hurtbox:
		return
	var target_node:Node = area.get_parent()
	if not target_node is ball:
		return
	var target:ball = target_node as ball
	if target == self or target.health <= 0 or not target.is_combat_targetable():
		return
	if (
		Team != ""
		and target.Team != ""
		and target.Team == Team
	):
		return
	var sight := PhysicsRayQueryParameters2D.create(global_position,target.global_position,1,[get_rid()])
	if not get_world_2d().direct_space_state.intersect_ray(sight).is_empty(): return
	var target_id:int = target.get_instance_id()
	if _fist_hit_targets.has(target_id):
		return
	_fist_hit_targets[target_id] = true
	var impact_world:Vector2 = _fist_hit_area.global_position if _fist_hit_area != null else target.global_position
	var damage_value:float = attack_damage(1.0)
	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	if target.receive_spatial_damage(damage_value,{"point":impact_world,"source":self}):
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		if health_loss > 0.0 or block_loss > 0.0:
			var knock_dir:Vector2 = target.global_position - global_position
			if knock_dir.length_squared() <= 0.000001:
				knock_dir = direction
			target.Repel += knock_dir.normalized() * maxf(fist_knockback_strength,0.0)
			_play_fist_sfx(PUNCH_HIT_SFX)
			target.notify_hit_burst_feedback(
				impact_world,damage_value,health_loss,block_loss,fist_hand_hit_radius * 2.0,
				Game.battle_rng_seed_or("scripts/characters/动漫/菜月昴.gd:fist_hit_seed",int(Time.get_ticks_usec()) ^ get_instance_id() ^ target_id),knock_dir.normalized()
			)

func _finish_fist_cycle() -> void:
	_fist_phase = -1.0
	_set_fist_strike_active(false)
	_fist_busy = false
	_fist_target_id = 0
	_fist_ready_timer = 0.0
	_fist_hit_targets.clear()
	var rest:PackedVector2Array = _rest_arm_controls()
	_ensure_fist_chain_state(rest)
	if not _fist_chain_points.is_empty():
		_apply_fist_geometry(_fist_chain_points[_fist_chain_points.size() - 1],_fist_chain_points)
	_set_fist_visible(_hand_window_active)

func _reset_fist_after_return() -> void:
	_set_fist_strike_active(false)
	_fist_busy = false
	_fist_target_id = 0
	_fist_ready_timer = 0.0
	_fist_orbit_angle = 0.0
	_fist_hit_targets.clear()
	var rest:PackedVector2Array = _rest_arm_controls()
	_ensure_fist_chain_state(rest)
	if not _fist_chain_points.is_empty():
		_apply_fist_geometry(_fist_chain_points[_fist_chain_points.size() - 1],_fist_chain_points)
	_set_fist_visible(true)

func _update_fist_visual_facing(delta:float) -> void:
	var desired_facing:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var desired_angle:float = desired_facing.angle()
	if not _fist_visual_angle_initialized:
		_fist_visual_angle = desired_angle
		_fist_visual_angle_initialized = true
		return
	var turn_step:float = deg_to_rad(maxf(fist_turn_degrees_per_second,1.0)) * maxf(delta,0.0)
	_fist_visual_angle = rotate_toward(_fist_visual_angle,desired_angle,turn_step)

func _rest_arm_controls() -> PackedVector2Array:
	# V335：按用户示意图改成“悬垂后回钩”的 J/U 形。这里返回的是目标骨架；
	# 真正显示的骨架由 _update_fist_chain_inertia() 逐段追随，因此不会所有节点同步硬切。
	var facing:Vector2 = Vector2.RIGHT.rotated(_fist_visual_angle)
	var down:Vector2 = facing.rotated(PI * 0.5)
	var up:Vector2 = -down
	var s:float = maxf(fist_rest_radius,38.0)
	var wave_slow:float = sin(_fist_orbit_angle * 0.56) * 2.2
	var wave_mid:float = sin(_fist_orbit_angle * 0.83 + 1.3) * 1.7
	var wave_tip:float = sin(_fist_orbit_angle * 1.07 + 2.1) * 2.6

	# 根部固定在人物身体前侧略偏上；随后长距离下垂，在底部转弯，再向前上方回钩，拳头接末端。
	var p0:Vector2 = facing * (s * 0.34) + up * (s * 0.12)
	var p1:Vector2 = p0 + down * (s * 0.78) + facing * (wave_slow * 0.25)
	var p2:Vector2 = p0 + down * (s * 1.65) + facing * (s * 0.06 + wave_mid * 0.35)
	var p3:Vector2 = p0 + down * (s * 2.02) + facing * (s * 0.48 + wave_mid)
	var p4:Vector2 = p0 + down * (s * 1.50) + facing * (s * 1.02 + wave_tip * 0.45)
	var p5:Vector2 = p0 + down * (s * 0.18 + wave_slow * 0.30) + facing * (s * 1.72 + wave_tip)
	return PackedVector2Array([p0,p1,p2,p3,p4,p5])

func _ensure_fist_chain_state(target:PackedVector2Array) -> void:
	if target.is_empty():
		return
	if not _fist_chain_initialized or _fist_chain_points.size() != target.size():
		_fist_chain_points = target.duplicate()
		_fist_chain_velocities = PackedVector2Array()
		for _i in range(target.size()):
			_fist_chain_velocities.append(Vector2.ZERO)
		_fist_last_owner_global_position = global_position
		_fist_chain_initialized = true

func _update_fist_chain_inertia(delta:float,target:PackedVector2Array) -> void:
	_ensure_fist_chain_state(target)
	if not _fist_chain_initialized or target.size() != _fist_chain_points.size():
		return
	var dt:float = clampf(delta,0.0,0.05)
	if dt <= 0.0:
		return

	# 人物平移时，根部立即跟随人物；越靠末端越保留上一帧世界位置，形成真正的“拖尾惯性”。
	# to_local(上一帧世界原点) 得到的就是人物本帧移动在当前局部空间里的反向位移。
	var owner_trail_local:Vector2 = to_local(_fist_last_owner_global_position)
	_fist_last_owner_global_position = global_position
	var count:int = _fist_chain_points.size()
	if owner_trail_local.length_squared() < 1000000.0:
		for i in range(1,count):
			var tail_ratio:float = float(i) / float(maxi(count - 1,1))
			_fist_chain_points[i] += owner_trail_local * tail_ratio

	# 第一个点就是手臂根部，直接贴目标；后续各节弹簧常数逐级降低，拳头最后跟上。
	_fist_chain_points[0] = target[0]
	_fist_chain_velocities[0] = Vector2.ZERO
	for i in range(1,count):
		var ratio:float = float(i) / float(maxi(count - 1,1))
		var stiffness:float = lerpf(46.0,13.0,ratio)
		var damping:float = lerpf(11.0,5.2,ratio)
		var pos:Vector2 = _fist_chain_points[i]
		var vel:Vector2 = _fist_chain_velocities[i]
		var acceleration:Vector2 = (target[i] - pos) * stiffness
		vel += acceleration * dt
		vel *= exp(-damping * dt)
		pos += vel * dt
		_fist_chain_points[i] = pos
		_fist_chain_velocities[i] = vel

func _current_fist_rest_position() -> Vector2:
	if _fist_chain_initialized and not _fist_chain_points.is_empty():
		return _fist_chain_points[_fist_chain_points.size() - 1]
	var controls:PackedVector2Array = _rest_arm_controls()
	return controls[controls.size() - 1] if not controls.is_empty() else Vector2.RIGHT * fist_rest_radius

func _update_fist_rest_visual(delta:float) -> void:
	if _fist_root == null or not is_instance_valid(_fist_root) or _fist_busy:
		return
	# 朝向目标本身先平滑转动，再由每一节自己的弹簧继续制造“根部先、拳头后”的二级惯性。
	_update_fist_visual_facing(delta)
	var target:PackedVector2Array = _rest_arm_controls()
	if target.is_empty():
		return
	_update_fist_chain_inertia(delta,target)
	if _fist_chain_points.is_empty():
		return
	_apply_fist_geometry(_fist_chain_points[_fist_chain_points.size() - 1],_fist_chain_points)

func _ensure_fist_visual() -> void:
	if _fist_root != null and is_instance_valid(_fist_root):
		return
	_fist_root = Node2D.new()
	_fist_root.name = "不可视之手"
	_fist_root.z_index = 34
	add_child(_fist_root)

	var arm_atlas := AtlasTexture.new()
	arm_atlas.atlas = SHADOW_HAND_TEXTURE
	arm_atlas.region = fist_arm_source_region
	_fist_arm = Line2D.new()
	_fist_arm.name = "手臂_仅视觉"
	_fist_arm.width = fist_arm_width
	_fist_arm.default_color = Color.WHITE
	_fist_arm.texture = arm_atlas
	_fist_arm.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	_fist_arm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_fist_arm.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_fist_arm.end_cap_mode = Line2D.LINE_CAP_ROUND
	_fist_arm.joint_mode = Line2D.LINE_JOINT_ROUND
	_fist_root.add_child(_fist_arm)

	var hand_atlas := AtlasTexture.new()
	hand_atlas.atlas = SHADOW_HAND_TEXTURE
	hand_atlas.region = fist_hand_source_region
	_fist_head = Sprite2D.new()
	_fist_head.name = "拳头"
	_fist_head.texture = hand_atlas
	_fist_head.centered = true
	_fist_root.add_child(_fist_head)
	_apply_fist_hand_visual_scale()

	# 只有拳头拥有真实碰撞区；手臂 Line2D 完全没有碰撞。
	_fist_hit_area = Area2D.new()
	_fist_hit_area.name = "拳头命中区"
	_fist_hit_area.collision_layer = 0
	_fist_hit_area.collision_mask = 2
	_fist_hit_area.monitorable = false
	_fist_hit_area.monitoring = false
	_fist_hit_area.area_entered.connect(_on_fist_area_entered)
	_fist_root.add_child(_fist_hit_area)
	_fist_hit_shape = CollisionShape2D.new()
	_fist_hit_shape.name = "拳头碰撞形状"
	var fist_circle := CircleShape2D.new()
	fist_circle.radius = maxf(fist_hand_hit_radius,1.0)
	_fist_hit_shape.shape = fist_circle
	_fist_hit_shape.disabled = true
	_fist_hit_area.add_child(_fist_hit_shape)

	_fist_sfx_player = AudioStreamPlayer2D.new()
	_fist_sfx_player.name = "盘旋拳音效"
	_fist_sfx_player.max_distance = 1400.0
	_fist_sfx_player.attenuation = 1.0
	_fist_sfx_player.volume_db = -1.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_fist_sfx_player.bus = &"GameplayRecord"
	add_child(_fist_sfx_player)

	_set_fist_local_position(_current_fist_rest_position())
	_set_fist_visible(true)

func _set_fist_strike_active(value:bool) -> void:
	_fist_strike_active = value
	if _fist_hit_area != null and is_instance_valid(_fist_hit_area):
		_fist_hit_area.set_deferred("monitoring",value)
	if _fist_hit_shape != null and is_instance_valid(_fist_hit_shape):
		_fist_hit_shape.set_deferred("disabled",not value)

func _apply_fist_hand_visual_scale() -> void:
	if _fist_head == null or not is_instance_valid(_fist_head):
		return
	var region_size:Vector2 = fist_hand_source_region.size
	var longest:float = maxf(region_size.x,region_size.y)
	if longest <= 0.0:
		_fist_head.scale = Vector2.ONE
		return
	var scale_value:float = maxf(fist_hand_visual_size,1.0) / longest
	_fist_head.scale = Vector2.ONE * scale_value

func _sample_fist_cubic(p0:Vector2,p1:Vector2,p2:Vector2,p3:Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var sample_count:int = maxi(fist_arm_curve_samples,4)
	for i in range(sample_count + 1):
		var t:float = float(i) / float(sample_count)
		var inv:float = 1.0 - t
		points.append(
			p0 * (inv * inv * inv)
			+ p1 * (3.0 * inv * inv * t)
			+ p2 * (3.0 * inv * t * t)
			+ p3 * (t * t * t)
		)
	return points

func _planned_arm_points(_local_position:Vector2) -> PackedVector2Array:
	if _fist_chain_initialized and _fist_chain_points.size() >= 2:
		return _fist_chain_points
	var controls:PackedVector2Array = _rest_arm_controls()
	if controls.size() < 2:
		return PackedVector2Array([Vector2.ZERO,_local_position])
	return controls


func _apply_fist_geometry(local_position:Vector2,path:PackedVector2Array) -> void:
	if _fist_root == null or not is_instance_valid(_fist_root):
		return
	_fist_root.position = Vector2.ZERO
	if _fist_arm != null and is_instance_valid(_fist_arm):
		# 宽度永远保持 V327 的数值；变化的只有 Line2D 的点，因此是“拉长/缩短”而不是放大。
		_fist_arm.width = fist_arm_width
		_fist_arm.points = path
	if _fist_head != null and is_instance_valid(_fist_head):
		_apply_fist_hand_visual_scale()
		_fist_head.position = local_position
		if _fist_hit_area != null and is_instance_valid(_fist_hit_area):
			_fist_hit_area.position = local_position
		if _fist_hit_shape != null and is_instance_valid(_fist_hit_shape) and _fist_hit_shape.shape is CircleShape2D:
			(_fist_hit_shape.shape as CircleShape2D).radius = maxf(fist_hand_hit_radius,1.0)
		if path.size() >= 2:
			var tangent:Vector2 = path[path.size() - 1] - path[path.size() - 2]
			if tangent.length_squared() > 0.000001:
				_fist_head.rotation = tangent.angle()

func _set_fist_local_position(local_position:Vector2) -> void:
	_apply_fist_geometry(local_position,_planned_arm_points(local_position))

func _set_fist_attack_local_position(local_position:Vector2) -> void:
	# 攻击阶段把悬垂链直接拉成直线。起点仍在身体前侧的真实手臂根部，拳头大小/线宽不变。
	var rest:PackedVector2Array = _rest_arm_controls()
	var root:Vector2 = rest[0] if not rest.is_empty() else Vector2.ZERO
	_apply_fist_geometry(local_position,PackedVector2Array([root,local_position]))

func _set_fist_return_progress(progress:float) -> void:
	var weight:float = clampf(progress,0.0,1.0)
	var rest:PackedVector2Array = _rest_arm_controls()
	if rest.size() < 2:
		_set_fist_local_position(_fist_return_from.lerp(_current_fist_rest_position(),weight))
		return
	var root:Vector2 = rest[0]
	var rest_end:Vector2 = rest[rest.size() - 1]
	var current_end:Vector2 = _fist_return_from.lerp(rest_end,weight)
	var path:PackedVector2Array = PackedVector2Array()
	var segment_count:int = rest.size() - 1
	for i in range(rest.size()):
		var t:float = float(i) / float(maxi(segment_count,1))
		var straight_point:Vector2 = root.lerp(current_end,t)
		path.append(straight_point.lerp(rest[i],weight))
	_apply_fist_geometry(current_end,path)
	# 把回收过程写回弹簧链，tween 结束后不会突然跳到另一套姿势。
	_fist_chain_points = path.duplicate()
	_fist_chain_velocities = PackedVector2Array()
	for _i in range(path.size()):
		_fist_chain_velocities.append(Vector2.ZERO)
	_fist_chain_initialized = true
	_fist_last_owner_global_position = global_position

func _play_fist_sfx(stream:AudioStream) -> void:
	if stream == null:
		return
	_ensure_fist_visual()
	if _fist_sfx_player == null or not is_instance_valid(_fist_sfx_player):
		return
	_fist_sfx_player.stop()
	_fist_sfx_player.stream = stream
	_fist_sfx_player.play()

func _set_fist_visible(value:bool) -> void:
	if _fist_root != null and is_instance_valid(_fist_root):
		_fist_root.visible = value
