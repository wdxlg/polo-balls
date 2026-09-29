extends ball

const RAIN_DROP_SCRIPT = preload("res://scripts/effects/投稿雨滴.gd")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const SAD_GUY_UMBRELLA_HIT_BURST_SCRIPT = preload("res://scripts/effects/umbrella_hit_burst.gd")
const RAIN_AMBIENCE_SFX:AudioStream = preload("res://audio/characters/伤心的男人/下雨.mp3")
const UMBRELLA_HIT_SFX_1:AudioStream = preload("res://audio/characters/伤心的男人/雨滴撞伞1.mp3")
const UMBRELLA_HIT_SFX_2:AudioStream = preload("res://audio/characters/伤心的男人/雨滴撞伞2.mp3")

const RAIN_AMBIENCE_NODE_NAME:StringName = &"SadGuyRainAmbience"

static var _rain_ambience_player:AudioStreamPlayer = null
static var _rain_ambience_users:int = 0

@export_category("Sad Guy - 雨伞")
@export_range(20.0,180.0,2.0) var umbrella_half_width:float = 58.0
@export_range(10.0,140.0,1.0) var umbrella_height:float = 39.0
@export_range(0.0,100.0,1.0) var umbrella_curve:float = 61.0
@export_range(0.0,80.0,1.0) var block_from_above_margin:float = 8.0
@export_range(1.0,30.0,1.0) var umbrella_defense_arc_thickness:float = 7.0

@export_category("Sad Guy - 下雨")
@export_range(0.01,1.0,0.01) var rain_interval:float = 0.04
@export_range(1,12,1) var rain_drops_per_wave:int = 3
@export_range(80.0,1200.0,10.0) var rain_speed:float = 760.0
@export_range(4.0,60.0,1.0) var rain_length_min:float = 8.0
@export_range(4.0,80.0,1.0) var rain_length_max:float = 17.0
# Damage（攻击力）就是雨滴基础伤害。
@export_range(0.0,10.0,0.05) var rain_damage_multiplier:float = 1.0

@export_category("Sad Guy - 音效")
@export_range(-40.0,6.0,0.5) var rain_ambience_volume_db:float = -22.0
@export_range(-40.0,6.0,0.5) var umbrella_hit_sfx_1_volume_db:float = -20.0
@export_range(-40.0,18.0,0.5) var umbrella_hit_sfx_2_volume_db:float = 0.0

var _rain_elapsed:float = 0.0
var _umbrella_visual:Node2D
var _umbrella_hit_audio_1:AudioStreamPlayer2D = null
var _umbrella_hit_audio_2:AudioStreamPlayer2D = null
var _registered_rain_ambience:bool = false

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	super._ready()
	if self_hitbox != null:
		self_hitbox.monitoring = false
	_setup_umbrella_audio()
	_register_rain_ambience()
	# 伞已经包含在人物贴图中；这里不再额外画一把线框伞。

func _exit_tree() -> void:
	_unregister_rain_ambience()

func _process(delta:float) -> void:
	if health <= 0:
		return
	if not is_multiplayer_authority():
		return

	# 用减法累计而不是每次清零，避免 60 FPS 下 0.04 秒被量化成明显更慢的节奏。
	# 单帧最多补 4 波，防止卡顿恢复后一次生成过多雨滴。
	_rain_elapsed += delta
	var interval:float = maxf(rain_interval,0.01)
	if is_player_controlled():
		_rain_elapsed = minf(_rain_elapsed,interval)
		return
	var spawned_waves:int = 0
	while _rain_elapsed >= interval and spawned_waves < 4:
		_rain_elapsed -= interval
		_spawn_rain_wave()
		spawned_waves += 1
	if spawned_waves >= 4:
		_rain_elapsed = minf(_rain_elapsed,interval)

func controlled_attack_action() -> void:
	# 左键：按原雨滴节奏降下一波雨，雨伞格挡仍是被动。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	var interval:float = maxf(rain_interval,0.01)
	if _rain_elapsed < interval:
		return
	_rain_elapsed -= interval
	_spawn_rain_wave()

func _setup_umbrella_audio() -> void:
	_umbrella_hit_audio_1 = AudioStreamPlayer2D.new()
	_umbrella_hit_audio_1.name = "UmbrellaHitAudio1"
	_umbrella_hit_audio_1.stream = UMBRELLA_HIT_SFX_1
	_umbrella_hit_audio_1.max_polyphony = 12
	# 两个投稿音频本身响度差距很大：第一段稍压低，第二段补偿响度。
	_umbrella_hit_audio_1.volume_db = umbrella_hit_sfx_1_volume_db
	_umbrella_hit_audio_1.max_distance = 2200.0
	add_child(_umbrella_hit_audio_1)

	_umbrella_hit_audio_2 = AudioStreamPlayer2D.new()
	_umbrella_hit_audio_2.name = "UmbrellaHitAudio2"
	_umbrella_hit_audio_2.stream = UMBRELLA_HIT_SFX_2
	_umbrella_hit_audio_2.max_polyphony = 12
	_umbrella_hit_audio_2.volume_db = umbrella_hit_sfx_2_volume_db
	_umbrella_hit_audio_2.max_distance = 2200.0
	add_child(_umbrella_hit_audio_2)

func _register_rain_ambience() -> void:
	if _registered_rain_ambience:
		return
	_registered_rain_ambience = true
	_rain_ambience_users += 1
	_ensure_rain_ambience_player()

func _unregister_rain_ambience() -> void:
	if not _registered_rain_ambience:
		return
	_registered_rain_ambience = false
	_rain_ambience_users = maxi(_rain_ambience_users - 1,0)
	if _rain_ambience_users <= 0 and _rain_ambience_player != null and is_instance_valid(_rain_ambience_player):
		_rain_ambience_player.stop()
		_rain_ambience_player.queue_free()
		_rain_ambience_player = null

func _ensure_rain_ambience_player() -> void:
	if _rain_ambience_player != null and is_instance_valid(_rain_ambience_player):
		_rain_ambience_player.volume_db = rain_ambience_volume_db
		if not _rain_ambience_player.playing:
			_rain_ambience_player.play()
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var existing:Node = world.get_node_or_null(NodePath(String(RAIN_AMBIENCE_NODE_NAME)))
	if existing is AudioStreamPlayer:
		_rain_ambience_player = existing as AudioStreamPlayer
		_rain_ambience_player.volume_db = rain_ambience_volume_db
		if not _rain_ambience_player.playing:
			_rain_ambience_player.play()
		return
	var player := AudioStreamPlayer.new()
	player.name = String(RAIN_AMBIENCE_NODE_NAME)
	var stream:AudioStream = RAIN_AMBIENCE_SFX.duplicate()
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	player.stream = stream
	player.volume_db = rain_ambience_volume_db
	player.max_polyphony = 1
	world.add_child(player)
	_rain_ambience_player = player
	player.play()

func _play_umbrella_hit_sfx() -> void:
	# 每次真实挡住雨滴/子弹/攻击都随机选一个投稿音效。
	# 两个播放器各自允许多声部，所以高频雨滴不会每次都截断上一声。
	if randf() < 0.5:
		if _umbrella_hit_audio_1 != null and is_instance_valid(_umbrella_hit_audio_1):
			_umbrella_hit_audio_1.play()
	else:
		if _umbrella_hit_audio_2 != null and is_instance_valid(_umbrella_hit_audio_2):
			_umbrella_hit_audio_2.play()

func _build_umbrella_visual() -> void:
	_umbrella_visual = Node2D.new()
	_umbrella_visual.name = "SadGuyUmbrella"
	_umbrella_visual.z_index = 12
	add_child(_umbrella_visual)
	for i:int in range(7):
		var line := Line2D.new()
		line.name = "UmbrellaLine_%d" % i
		line.width = 2.2
		line.default_color = Color(0.12,0.12,0.16,0.98)
		line.antialiased = true
		_umbrella_visual.add_child(line)
	_update_umbrella_visual()

func _update_umbrella_visual() -> void:
	if _umbrella_visual == null or not is_instance_valid(_umbrella_visual):
		return
	var y:float = -umbrella_height
	var points:Array[Vector2] = []
	for i:int in range(7):
		var t:float = float(i) / 6.0
		var x:float = lerpf(-umbrella_half_width,umbrella_half_width,t)
		var arch:float = sin(t * PI) * umbrella_curve
		points.append(Vector2(x,y - arch))
	for i:int in range(6):
		var line:Line2D = _umbrella_visual.get_child(i) as Line2D
		line.points = PackedVector2Array([points[i],points[i + 1]])
	var handle:Line2D = _umbrella_visual.get_child(6) as Line2D
	handle.points = PackedVector2Array([Vector2(0.0,y - umbrella_curve),Vector2(0.0,y + 22.0)])

func can_receive_hit_contact(source_hitbox:hitbox,_hurt:hurtbox) -> bool:
	if source_hitbox == null:
		return true
	var hit:Dictionary = _umbrella_segment_hit(source_hitbox.global_position,global_position)
	if not hit.is_empty():
		umbrella_impact_feedback(hit["point"],hit["normal"],520.0)
		return false
	return true

func can_receive_directional_damage(source_position:Vector2,incoming_direction:Vector2) -> bool:
	var end_position:Vector2 = global_position
	if incoming_direction.length_squared() > 0.000001:
		# 使用真实入射方向朝角色方向延伸，避免只凭“攻击者在上方”就格挡。
		var dir:Vector2 = incoming_direction.normalized()
		var projected:float = maxf(source_position.distance_to(global_position),80.0)
		end_position = source_position + dir * projected
	var hit:Dictionary = _umbrella_segment_hit(source_position,end_position)
	if not hit.is_empty():
		umbrella_impact_feedback(hit["point"],hit["normal"],620.0)
		return false
	return true

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	var segment_start:Vector2 = impact_position
	if source is Node2D:
		segment_start = (source as Node2D).global_position
	var hit:Dictionary = _umbrella_segment_hit(segment_start,impact_position)
	if hit.is_empty() and source is Node2D:
		hit = _umbrella_segment_hit(segment_start,global_position)
	if not hit.is_empty():
		umbrella_impact_feedback(hit["point"],hit["normal"],620.0)
		return false
	return super(damage,impact_position,ignore_block,source)

func _umbrella_surface_y_local(local_x:float) -> float:
	var half_width:float = maxf(umbrella_half_width,1.0)
	var u:float = clampf(local_x / half_width,-1.0,1.0)
	return -umbrella_height - umbrella_curve * cos(u * PI * 0.5)

func _umbrella_surface_normal_world(local_x:float) -> Vector2:
	var half_width:float = maxf(umbrella_half_width,1.0)
	var u:float = clampf(local_x / half_width,-1.0,1.0)
	var slope:float = umbrella_curve * (PI * 0.5 / half_width) * sin(u * PI * 0.5)
	var local_normal := Vector2(slope,-1.0).normalized()
	var world_origin:Vector2 = to_global(Vector2.ZERO)
	return (to_global(local_normal) - world_origin).normalized()

func _umbrella_segment_hit(world_a:Vector2,world_b:Vector2) -> Dictionary:
	var a:Vector2 = to_local(world_a)
	var b:Vector2 = to_local(world_b)
	var half_width:float = maxf(umbrella_half_width,1.0)
	# 只接受真正从伞面外侧（上方）穿向内侧的路径。
	var best_t:float = -1.0
	var previous_t:float = 0.0
	var previous_p:Vector2 = a
	var previous_d:float = previous_p.y - _umbrella_surface_y_local(clampf(previous_p.x,-half_width,half_width))
	for i:int in range(1,25):
		var t:float = float(i) / 24.0
		var p:Vector2 = a.lerp(b,t)
		if absf(p.x) <= half_width:
			var d:float = p.y - _umbrella_surface_y_local(p.x)
			if previous_d <= umbrella_defense_arc_thickness and d >= -umbrella_defense_arc_thickness:
				var lo:float = previous_t
				var hi:float = t
				for _j:int in range(7):
					var mid:float = (lo + hi) * 0.5
					var mp:Vector2 = a.lerp(b,mid)
					var md:float = mp.y - _umbrella_surface_y_local(clampf(mp.x,-half_width,half_width))
					if md < 0.0:
						lo = mid
					else:
						hi = mid
				best_t = (lo + hi) * 0.5
				break
			previous_d = d
		previous_t = t
		previous_p = p
	if best_t < 0.0:
		return {}
	var local_hit:Vector2 = a.lerp(b,best_t)
	if absf(local_hit.x) > half_width:
		return {}
	local_hit.y = _umbrella_surface_y_local(local_hit.x)
	return {
		"point": to_global(local_hit),
		"normal": _umbrella_surface_normal_world(local_hit.x),
	}

func rain_hits_umbrella_segment(a:Vector2,b:Vector2) -> bool:
	return not _umbrella_segment_hit(a,b).is_empty()

func rain_umbrella_impact_data(a:Vector2,b:Vector2) -> Dictionary:
	return _umbrella_segment_hit(a,b)

func rain_umbrella_impact_point(a:Vector2,b:Vector2) -> Vector2:
	var hit:Dictionary = _umbrella_segment_hit(a,b)
	if hit.is_empty():
		return b
	return hit["point"]

func umbrella_impact_feedback(
	impact_position:Vector2,
	surface_normal:Vector2 = Vector2.UP,
	impact_speed:float = 600.0,
	play_hit_sfx:bool = true
) -> void:
	# 雨滴落在伞面时只播放白线反馈，不播放“格挡”音效。
	# 子弹/普通攻击等真正被伞挡下时仍使用两个投稿格挡音随机播放。
	if play_hit_sfx:
		_play_umbrella_hit_sfx()
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var seed:int = (
		int(Time.get_ticks_usec())
		^ int(get_instance_id())
		^ int(round(impact_position.x * 31.0 + impact_position.y * 17.0))
	)
	SAD_GUY_UMBRELLA_HIT_BURST_SCRIPT.spawn(
		world,
		self,
		impact_position,
		surface_normal,
		maxf(impact_speed,1.0),
		seed
	)

func _umbrella_world_x_bounds() -> Vector2:
	var left:Vector2 = to_global(Vector2(-umbrella_half_width,_umbrella_surface_y_local(-umbrella_half_width)))
	var right:Vector2 = to_global(Vector2(umbrella_half_width,_umbrella_surface_y_local(umbrella_half_width)))
	return Vector2(minf(left.x,right.x),maxf(left.x,right.x))

func _umbrella_world_top_y() -> float:
	var center_top:Vector2 = to_global(Vector2(0.0,_umbrella_surface_y_local(0.0)))
	return center_top.y

func _spawn_rain_wave() -> void:
	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return

	var umbrella_bounds:Vector2 = _umbrella_world_x_bounds()
	var left:float = maxf(rect.position.x + 4.0,umbrella_bounds.x)
	var right:float = minf(rect.end.x - 4.0,umbrella_bounds.y)
	if right <= left:
		left = clampf(global_position.x - 1.0,rect.position.x + 4.0,rect.end.x - 4.0)
		right = clampf(global_position.x + 1.0,rect.position.x + 4.0,rect.end.x - 4.0)

	var spawn_y:float = rect.position.y + 3.0
	var bottom_y:float = rect.end.y - 4.0
	# V276：雨滴是 script.new() 的运行时节点，不属于 MultiplayerSpawner 的 PackedScene 白名单。
	# authority 每一波只同步一个 seed + 几何边界；所有 peer 用同一 RNG 重建完全一致的雨线。
	var wave_seed:int = randi()
	_spawn_rain_wave_from_seed(wave_seed,left,right,spawn_y,bottom_y,false)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_rain_wave.rpc(wave_seed,left,right,spawn_y,bottom_y)


@rpc("authority","call_remote","unreliable")
func _rpc_spawn_rain_wave(wave_seed:int,left:float,right:float,spawn_y:float,bottom_y:float) -> void:
	_spawn_rain_wave_from_seed(wave_seed,left,right,spawn_y,bottom_y,true)


func _spawn_rain_wave_from_seed(
	wave_seed:int,
	left:float,
	right:float,
	spawn_y:float,
	bottom_y:float,
	visual_only:bool
) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = wave_seed
	var min_length:float = minf(rain_length_min,rain_length_max)
	var max_length:float = maxf(rain_length_min,rain_length_max)
	for i:int in range(maxi(rain_drops_per_wave,1)):
		var drop:Node2D = RAIN_DROP_SCRIPT.new()
		var start := Vector2(rng.randf_range(left,right),spawn_y)
		var length_value:float = rng.randf_range(min_length,max_length)
		var drop_velocity := Vector2(
			rng.randf_range(-7.0,7.0),
			rng.randf_range(rain_speed * 0.9,rain_speed * 1.1)
		)
		drop.call(
			"setup",
			self,
			start,
			length_value,
			0.0 if visual_only else attack_damage(rain_damage_multiplier),
			drop_velocity,
			bottom_y,
			visual_only
		)
		world.add_child(drop)

