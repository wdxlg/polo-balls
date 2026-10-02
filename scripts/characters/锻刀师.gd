extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
const BURN_SCRIPT = preload("res://scripts/status/锻刀师_燃烧.gd")
const STEAM_SCENE = preload("res://scenes/effects/锻刀师_蒸汽.tscn")
const SHOCKWAVE_SCENE = preload("res://scenes/effects/锻刀师_震荡波.tscn")

const TEX_IDLE:Texture2D = preload("res://Images/characters/人物/锻刀师/01_锻刀师_双手抱胸微笑.png")
const TEX_BLUEPRINT:Texture2D = preload("res://Images/characters/人物/锻刀师/02_锻刀师_双手查看设计图.png")
const TEX_HAMMER_READY:Texture2D = preload("res://Images/characters/人物/锻刀师/04_锻刀师_举锤待锻.png")
const TEX_HAMMER_HIT:Texture2D = preload("res://Images/characters/人物/锻刀师/05_锻刀师_锤击刀身.png")
const TEX_SHOWCASE:Texture2D = preload("res://Images/characters/人物/锻刀师/07_锻刀师_展示成型武士刀.png")
const TEX_SWORD_SWING:Texture2D = preload("res://Images/characters/人物/锻刀师/08_锻刀师_挥舞武士刀.png")
const TEX_SWORD_BODY:Texture2D = preload("res://Images/characters/人物/锻刀师/09_武士刀本体.png")
const TEX_TEMPERING:Texture2D = preload("res://Images/characters/人物/锻刀师/定型.png")
const TEX_HEATING:Texture2D = preload("res://Images/characters/人物/锻刀师/烧钢.png")

const SFX_BLUEPRINT:AudioStream = preload("res://audio/characters/锻刀师/报纸展开.mp3")
const SFX_FIRE_LOOP:AudioStream = preload("res://audio/characters/锻刀师/火焰.mp3")
const SFX_STEAM_START:AudioStream = preload("res://audio/characters/锻刀师/蒸气.mp3")
const SFX_HAMMER:AudioStream = preload("res://audio/characters/锻刀师/锻造.mp3")
const SFX_SWORD_SWING:AudioStream = preload("res://audio/characters/锻刀师/刀挥舞.mp3")
const SFX_SWORD_HIT:AudioStream = preload("res://audio/characters/锻刀师/刀砍到.mp3")
const SFX_BURN_TICK:AudioStream = preload("res://audio/status/debuff/烫伤.wav")

# 锻刀师：设计图 -> 烧钢 -> 锻造 -> 蒸汽定型 -> 成刀展示 -> 持刀 -> 刀碎 -> 循环。
# 锻刀 + 成刀展示约 15 秒；锻造阶段固定 14 锤，但每锤带小幅随机速度偏移，
# 总趋势为逐渐加速，最后三锤重新放慢。

enum ForgePhase {
	BLUEPRINT,
	HEATING,
	HAMMERING,
	TEMPERING,
	SHOWCASE,
	BLADE_READY,
}

@export_category("锻刀师 - 流程")
@export_range(0.2,3.0,0.05) var blueprint_duration:float = 1.0
@export_range(1.0,8.0,0.1) var heating_duration:float = 3.2
@export_range(1.0,8.0,0.1) var tempering_duration:float = 3.5
@export_range(0.2,2.0,0.05) var showcase_duration:float = 0.85
@export_range(0.2,1.0,0.01) var heating_move_multiplier:float = 0.65

@export_category("锻刀师 - 烧钢")
@export_range(20.0,160.0,1.0) var fire_radius:float = 72.0
@export_range(0.05,0.5,0.01) var fire_tick_interval:float = 0.18
@export_range(0.0,50.0,0.05) var fire_tick_damage_multiplier:float = 1.3333333
@export_range(0.2,8.0,0.1) var burn_duration:float = 2.5
@export_range(0.1,2.0,0.05) var burn_tick_interval:float = 0.5
@export_range(0.0,50.0,0.05) var burn_tick_damage_multiplier:float = 1.0

@export_category("锻刀师 - 锻造")
@export_range(1,30,1) var hammer_strike_count:int = 14
@export_range(0.0,0.25,0.01) var hammer_interval_randomness:float = 0.08
@export_range(0.0,50.0,0.05) var shockwave_damage_multiplier:float = 8.0

@export_category("锻刀师 - 蒸汽定型")
@export_range(0.1,1.0,0.01) var steam_spawn_interval:float = 0.38
@export_range(0.0,50.0,0.05) var steam_damage_multiplier:float = 2.6666667

@export_category("锻刀师 - 成刀")
@export_range(30.0,220.0,1.0) var sword_attack_range:float = 64.0
@export_range(0.2,2.0,0.01) var sword_attack_interval:float = 0.78
@export_range(0.1,0.8,0.01) var sword_swing_duration:float = 0.28
@export_range(0.0,50.0,0.05) var sword_damage_multiplier:float = 50.0
@export_range(1.0,100.0,1.0) var sword_durability_cost:float = 15.0

@export_category("锻刀师 - 音效")
@export_range(-36.0,12.0,0.5) var blueprint_sfx_volume_db:float = 3.0
@export_range(-36.0,12.0,0.5) var fire_loop_volume_db:float = 2.0
@export_range(-36.0,12.0,0.5) var steam_start_sfx_volume_db:float = 0.0
@export_range(-36.0,12.0,0.5) var hammer_sfx_volume_db:float = 2.0
@export_range(-36.0,12.0,0.5) var sword_swing_sfx_volume_db:float = -2.0
@export_range(-36.0,12.0,0.5) var sword_hit_sfx_volume_db:float = -2.0
@export_range(-36.0,12.0,0.5) var burn_tick_sfx_volume_db:float = 1.0
@export_range(120.0,2400.0,20.0) var bladesmith_sfx_max_distance:float = 900.0
@export_range(0.05,2.0,0.05) var bladesmith_sfx_attenuation:float = 0.75

@onready var fire_area:Area2D = $ForgeFireArea
@onready var fire_collision:CollisionShape2D = $ForgeFireArea/CollisionShape2D
@onready var sword_pivot:Node2D = $SwordPivot
@onready var sword_hit_area:Area2D = $SwordPivot/SwordHitArea

var _phase:int = ForgePhase.BLUEPRINT
var _phase_elapsed:float = 0.0
var _forge_progress:float = 0.0
var _blade_durability:float = 0.0
var _base_move_speed:float = 100.0
var _fire_tick_left:float = 0.0
var _steam_spawn_left:float = 0.0

var _hammer_intervals:Array[float] = []
var _hammer_index:int = 0
var _hammer_interval_left:float = 0.0
var _hammer_visual_pulse:float = 0.0
var _hammer_visual_side:float = 1.0

var _sword_attack_elapsed:float = 0.0
var _sword_attack_clock:float = 0.0
var _sword_attack_active:bool = false
var _sword_base_angle:float = 0.0
var _sword_swing_reverse:bool = false
var _sword_hit_target_ids:Dictionary = {}
var _sword_afterimages:Array[Dictionary] = []
var _afterimage_sample_left:float = 0.0
var _break_flash_left:float = 0.0
var _visual_time:float = 0.0
var _local_effect_serial:int = 0
var _fire_loop_player:AudioStreamPlayer2D = null
var _forge_runtime_started:bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	_base_move_speed = Speed
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/锻刀师.gd:_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))

	super._ready()

	# V37：接入用户提供的正式 PNG 素材。主视觉继续复用 ball.tscn 的 Graphics/Image，
	# 不创建第二套人物 Sprite；各阶段只切换这一个 Sprite2D 的纹理。
	if image != null and is_instance_valid(image):
		image.visible = true
	var animated := $Graphics/AnimatedSprite2D as AnimatedSprite2D
	if animated != null:
		animated.visible = false

	var fire_circle:= fire_collision.shape as CircleShape2D
	if fire_circle != null:
		# fire_area 是角色子节点，会继承 ball.tscn 的 0.2 根缩放，因此换算到本地半径。
		fire_circle.radius = fire_radius / maxf(absf(global_scale.x),0.001)
	fire_area.monitoring = false
	fire_area.monitorable = false
	fire_area.collision_layer = 0
	fire_area.collision_mask = 0
	fire_area.set_meta("threat_debug_damage",0.0)

	sword_hit_area.monitoring = false
	sword_hit_area.monitorable = false
	sword_hit_area.collision_layer = 0
	sword_hit_area.collision_mask = 0
	sword_hit_area.set_meta("threat_debug_damage",0.0)
	if not sword_hit_area.area_entered.is_connected(_on_sword_area_entered):
		sword_hit_area.area_entered.connect(_on_sword_area_entered)

	_ensure_fire_loop_player()
	# V400：布阵/时间停止阶段保持 01 待机图，不提前进入看设计图，也不播放报纸声。
	# 真正允许战斗运行后的第一个物理帧才开始 BLUEPRINT 阶段。
	_prepare_forge_waiting_state()
	if is_combat_runtime_active():
		_start_forge_runtime()
	queue_redraw()


func hit_white_method(power:float) -> void:
	super.hit_white_method(power)
	queue_redraw()


func get_preview_texture() -> Texture2D:
	# 角色列表 / 放置预览使用正式立绘，不再生成程序化占位图。
	return TEX_IDLE


func _set_character_texture(texture_value:Texture2D) -> void:
	if not (image is Sprite2D) or texture_value == null:
		return
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture != texture_value:
		sprite.texture = texture_value
	sprite.visible = true


func _refresh_character_texture() -> void:
	var wanted:Texture2D = TEX_IDLE
	if not _forge_runtime_started:
		_set_character_texture(wanted)
		return
	match _phase:
		ForgePhase.BLUEPRINT:
			wanted = TEX_BLUEPRINT
		ForgePhase.HEATING:
			wanted = TEX_HEATING
		ForgePhase.HAMMERING:
			wanted = TEX_HAMMER_HIT if _hammer_visual_pulse > 0.34 else TEX_HAMMER_READY
		ForgePhase.TEMPERING:
			wanted = TEX_TEMPERING
		ForgePhase.SHOWCASE:
			wanted = TEX_SHOWCASE
		ForgePhase.BLADE_READY:
			wanted = TEX_SWORD_SWING if _sword_attack_active else TEX_SHOWCASE
	_set_character_texture(wanted)


func get_next_state(state:State) -> int:
	# 普攻完全由持刀状态自己的真实 SwordHitArea 驱动；基础 ball 攻击永远关闭。
	return super.get_next_state(state)


# ================================
# 锻刀师音效
# ================================
func _audio_parent() -> Node:
	var tree:SceneTree = get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


func _configure_positional_audio(player:AudioStreamPlayer2D,volume_db_value:float) -> void:
	if player == null:
		return
	player.volume_db = volume_db_value
	player.max_distance = maxf(bladesmith_sfx_max_distance,50.0)
	player.attenuation = maxf(bladesmith_sfx_attenuation,0.05)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"


func _play_one_shot_local(
	stream_value:AudioStream,
	position_value:Vector2,
	volume_db_value:float,
	pitch_value:float = 1.0
) -> void:
	if stream_value == null:
		return
	var player := AudioStreamPlayer2D.new()
	_local_effect_serial += 1
	player.name = "BladesmithOneShotSfx_%d" % _local_effect_serial
	player.top_level = true
	player.stream = stream_value
	_configure_positional_audio(player,volume_db_value)
	player.pitch_scale = maxf(pitch_value,0.05)
	# 不再把一次性声音直接加到 World 根节点，避免触发 World 的 MultiplayerSpawner。
	add_child(player,true)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _ensure_fire_loop_player() -> void:
	if _fire_loop_player != null and is_instance_valid(_fire_loop_player):
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "BladesmithFireLoop"
	var loop_stream:AudioStream = SFX_FIRE_LOOP.duplicate() as AudioStream
	if loop_stream is AudioStreamMP3:
		(loop_stream as AudioStreamMP3).loop = true
	player.stream = loop_stream
	_configure_positional_audio(player,fire_loop_volume_db)
	add_child(player)
	_fire_loop_player = player


func _start_fire_loop_local() -> void:
	_ensure_fire_loop_player()
	if _fire_loop_player == null or not is_instance_valid(_fire_loop_player):
		return
	_fire_loop_player.volume_db = fire_loop_volume_db
	if not _fire_loop_player.playing:
		_fire_loop_player.play()


func _stop_fire_loop_local() -> void:
	if _fire_loop_player != null and is_instance_valid(_fire_loop_player) and _fire_loop_player.playing:
		_fire_loop_player.stop()


func _apply_phase_audio_local(phase_value:int) -> void:
	if not _forge_runtime_started:
		return
	# 烧钢循环只允许存在于 HEATING；任何阶段切换先停旧循环。
	_stop_fire_loop_local()
	match phase_value:
		ForgePhase.BLUEPRINT:
			_play_one_shot_local(SFX_BLUEPRINT,global_position,blueprint_sfx_volume_db,1.0)
		ForgePhase.HEATING:
			_start_fire_loop_local()
		ForgePhase.TEMPERING:
			_play_one_shot_local(SFX_STEAM_START,global_position,steam_start_sfx_volume_db,1.0)


func _play_hammer_sfx_local() -> void:
	_play_one_shot_local(
		SFX_HAMMER,
		global_position,
		hammer_sfx_volume_db,
		_rng.randf_range(0.96,1.04)
	)


func _play_sword_swing_sfx_local() -> void:
	_play_one_shot_local(
		SFX_SWORD_SWING,
		global_position,
		sword_swing_sfx_volume_db,
		_rng.randf_range(0.98,1.02)
	)


func _play_sword_hit_networked(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_play_sword_hit_sfx_rpc.rpc(position_value)
	else:
		_play_sword_hit_sfx_rpc(position_value)


@rpc("authority","call_local","unreliable")
func _play_sword_hit_sfx_rpc(position_value:Vector2) -> void:
	_play_one_shot_local(
		SFX_SWORD_HIT,
		position_value,
		sword_hit_sfx_volume_db,
		_rng.randf_range(0.97,1.03)
	)


func play_bladesmith_ball_damage_sfx(outgoing_damage:float) -> void:
	# 火焰、燃烧 DOT、蒸汽伤害都直接复用 ball.gd 默认的碰撞伤害声 balls_hit1。
	# 高频持续伤害使用 create_new_audio=true，让每次真实 tick 都有独立 voice，不互相截断。
	var params:Dictionary = {
		"volume": clampf(outgoing_damage - 12.0,-100.0,0.0),
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)


func play_bladesmith_burn_tick_sfx(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_play_bladesmith_burn_tick_sfx_rpc.rpc(position_value)
	else:
		_play_bladesmith_burn_tick_sfx_rpc(position_value)


@rpc("authority","call_local","unreliable")
func _play_bladesmith_burn_tick_sfx_rpc(position_value:Vector2) -> void:
	_play_one_shot_local(
		SFX_BURN_TICK,
		position_value,
		burn_tick_sfx_volume_db,
		_rng.randf_range(0.97,1.04)
	)


func _process(delta:float) -> void:
	# state_machine 在非权威端不会调用 tick_physics；远端在这里单独推进纯视觉。
	if is_multiplayer_authority():
		return
	if _forge_runtime_started and is_combat_runtime_active():
		_phase_elapsed += delta
		match _phase:
			ForgePhase.HEATING:
				_forge_progress = clampf(25.0 * (_phase_elapsed / maxf(heating_duration,0.01)),0.0,25.0)
			ForgePhase.TEMPERING:
				_forge_progress = clampf(80.0 + 20.0 * (_phase_elapsed / maxf(tempering_duration,0.01)),80.0,100.0)
	_update_visual_only(delta)


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	_update_visual_only(delta)

	if not is_multiplayer_authority():
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		_disable_all_attack_areas()
		return
	if not is_combat_runtime_active():
		return
	if not _forge_runtime_started:
		_start_forge_runtime()

	_phase_elapsed += delta
	match _phase:
		ForgePhase.BLUEPRINT:
			_process_blueprint()
		ForgePhase.HEATING:
			_process_heating(delta)
		ForgePhase.HAMMERING:
			_process_hammering(delta)
		ForgePhase.TEMPERING:
			_process_tempering(delta)
		ForgePhase.SHOWCASE:
			_process_showcase()
		ForgePhase.BLADE_READY:
			_process_blade_ready(delta)

	queue_redraw()


func _update_visual_only(delta:float) -> void:
	if is_combat_runtime_active():
		_visual_time += delta
		_hammer_visual_pulse = maxf(_hammer_visual_pulse - delta * 4.8,0.0)
		_break_flash_left = maxf(_break_flash_left - delta,0.0)
		for i:int in range(_sword_afterimages.size() - 1,-1,-1):
			var data:Dictionary = _sword_afterimages[i]
			data["life"] = float(data.get("life",0.0)) - delta
			if float(data["life"]) <= 0.0:
				_sword_afterimages.remove_at(i)
			else:
				_sword_afterimages[i] = data

		# 远端只需要重放挥刀视觉，不参与命中。
		if not is_multiplayer_authority() and _sword_attack_active:
			_update_sword_swing_transform(delta,false)
	_refresh_character_texture()
	queue_redraw()


func _set_forge_move_speed(value:float) -> void:
	var speed_value:float = maxf(value,0.0)
	Speed = speed_value
	if default_properties != null:
		default_properties["Speed"] = speed_value


func _prepare_forge_waiting_state() -> void:
	_forge_runtime_started = false
	_phase = ForgePhase.BLUEPRINT
	_phase_elapsed = 0.0
	_forge_progress = 0.0
	_blade_durability = 0.0
	_set_forge_move_speed(0.0)
	direction = Vector2.ZERO
	Attacking = false
	_disable_all_attack_areas()
	_stop_fire_loop_local()
	_set_character_texture(TEX_IDLE)


func _start_forge_runtime() -> void:
	if _forge_runtime_started:
		return
	_forge_runtime_started = true
	_enter_phase(ForgePhase.BLUEPRINT,true)


func _process_blueprint() -> void:
	_forge_progress = 0.0
	if _phase_elapsed >= blueprint_duration:
		_enter_phase(ForgePhase.HEATING)


func _process_heating(delta:float) -> void:
	_forge_progress = clampf(25.0 * (_phase_elapsed / maxf(heating_duration,0.01)),0.0,25.0)
	_fire_tick_left -= delta
	while _fire_tick_left <= 0.0:
		_fire_tick_left += fire_tick_interval
		_damage_fire_overlaps()
	if _phase_elapsed >= heating_duration:
		_enter_phase(ForgePhase.HAMMERING)


func _process_hammering(delta:float) -> void:
	if _hammer_index >= _hammer_intervals.size():
		_forge_progress = 80.0
		_enter_phase(ForgePhase.TEMPERING)
		return

	_hammer_interval_left -= delta
	if _hammer_interval_left <= 0.0:
		_do_hammer_strike()
		_hammer_index += 1
		if _hammer_index >= _hammer_intervals.size():
			_forge_progress = 80.0
			_enter_phase(ForgePhase.TEMPERING)
		else:
			_hammer_interval_left += _hammer_intervals[_hammer_index]


func _process_tempering(delta:float) -> void:
	_forge_progress = clampf(
		80.0 + 20.0 * (_phase_elapsed / maxf(tempering_duration,0.01)),
		80.0,
		100.0
	)
	_steam_spawn_left -= delta
	while _steam_spawn_left <= 0.0:
		_steam_spawn_left += steam_spawn_interval
		_spawn_steam_networked()
	if _phase_elapsed >= tempering_duration:
		_forge_progress = 100.0
		_blade_durability = 100.0
		_enter_phase(ForgePhase.SHOWCASE)


func _process_showcase() -> void:
	_forge_progress = 100.0
	_blade_durability = 100.0
	if _phase_elapsed >= showcase_duration:
		_enter_phase(ForgePhase.BLADE_READY)


func _process_blade_ready(delta:float) -> void:
	_forge_progress = 100.0
	_sword_attack_clock += delta
	if _sword_attack_active:
		_update_sword_swing_transform(delta,true)
		_collect_current_sword_hits()
		return
	# V130：刀锻好以后，操控模式不再自动搜索敌人挥刀；左键由 controlled_attack_action 触发。
	if is_player_controlled():
		return
	if is_damage_output_disabled():
		return
	if _sword_attack_clock < sword_attack_interval:
		return
	var target:ball = TOOLS.nearest_enemy(self,sword_attack_range)
	if target != null:
		_start_sword_attack(target)


func _enter_phase(new_phase:int,initial:bool = false) -> void:
	_phase = new_phase
	_phase_elapsed = 0.0
	Attacking = false
	_disable_all_attack_areas()

	match _phase:
		ForgePhase.BLUEPRINT:
			_set_forge_move_speed(0.0)
			direction = Vector2.ZERO
			_forge_progress = 0.0
			_blade_durability = 0.0
		ForgePhase.HEATING:
			_set_forge_move_speed(_base_move_speed * heating_move_multiplier)
			_forge_progress = 0.0
			_fire_tick_left = 0.0
			fire_area.collision_mask = 2
			fire_area.monitoring = true
			fire_area.set_meta("threat_debug_damage",attack_damage(fire_tick_damage_multiplier))
		ForgePhase.HAMMERING:
			_set_forge_move_speed(_base_move_speed)
			_forge_progress = 25.0
			_build_hammer_intervals()
			_hammer_index = 0
			_hammer_interval_left = _hammer_intervals[0] if not _hammer_intervals.is_empty() else 0.0
		ForgePhase.TEMPERING:
			_set_forge_move_speed(_base_move_speed)
			_forge_progress = 80.0
			_steam_spawn_left = 0.0
		ForgePhase.SHOWCASE:
			# 刀做好后先停下来展示一小段时间；展示期间不移动也不攻击。
			_set_forge_move_speed(0.0)
			direction = Vector2.ZERO
			_forge_progress = 100.0
			_blade_durability = 100.0
		ForgePhase.BLADE_READY:
			_set_forge_move_speed(_base_move_speed)
			_forge_progress = 100.0
			_blade_durability = 100.0
			# 展示已经承担了出刀前停顿；展示结束后若附近有敌人即可立即起手。
			_sword_attack_clock = sword_attack_interval

	_refresh_character_texture()
	# 联机远端在 _ready() 的 initial 阶段先不播，等 authority 的可靠 phase RPC 到达后再播一次，
	# 避免首次看设计图的报纸声在远端重复两次。
	if not initial or is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		_apply_phase_audio_local(_phase)
	_broadcast_phase_visual()
	if initial:
		queue_redraw()


func _disable_all_attack_areas() -> void:
	_stop_fire_loop_local()
	if fire_area != null and is_instance_valid(fire_area):
		fire_area.monitoring = false
		fire_area.collision_mask = 0
		fire_area.set_meta("threat_debug_damage",0.0)
	if sword_hit_area != null and is_instance_valid(sword_hit_area):
		sword_hit_area.monitoring = false
		sword_hit_area.collision_mask = 0
		sword_hit_area.set_meta("threat_debug_damage",0.0)
	_sword_hit_target_ids.clear()
	_sword_attack_active = false


func _build_hammer_intervals() -> void:
	# 14 锤的基准节奏总计约 6.49 秒：逐渐加速，最后三锤重新放慢。
	var base:Array[float] = [
		0.72,0.68,0.63,0.58,0.53,0.48,0.43,
		0.38,0.33,0.29,0.27,0.31,0.38,0.48
	]
	_hammer_intervals.clear()
	var count:int = maxi(hammer_strike_count,1)
	for i:int in range(count):
		var source_index:int = clampi(
			roundi(float(i) / float(maxi(count - 1,1)) * float(base.size() - 1)),
			0,
			base.size() - 1
		)
		var jitter:float = _rng.randf_range(-hammer_interval_randomness,hammer_interval_randomness)
		_hammer_intervals.append(maxf(base[source_index] * (1.0 + jitter),0.12))


func _do_hammer_strike() -> void:
	var total:int = maxi(_hammer_intervals.size(),1)
	_forge_progress = 25.0 + 55.0 * float(_hammer_index + 1) / float(total)
	_hammer_visual_pulse = 1.0
	_hammer_visual_side *= -1.0
	_refresh_character_texture()

	# V41：白线不再是 _draw() 里的静态瞬间线，而是直接复用项目“撞墙白线”
	# 的 HitBurstEffect 动画曲线：从锻造命中点长出、向外运动、收短并淡出。
	var burst_seed:int = Game.battle_rng_seed_or("scripts/characters/锻刀师.gd:burst_seed",int(Time.get_ticks_usec()) ^ int((_hammer_index + 1) * 1103515245))
	_spawn_hammer_white_lines_local(burst_seed)

	_spawn_shockwave_networked()
	_play_hammer_sfx_local()
	_broadcast_hammer_visual(burst_seed)


func _damage_fire_overlaps() -> void:
	if not fire_area.monitoring:
		return
	var hit_ids:Dictionary = {}
	for area:Area2D in fire_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var target:ball = area.get_parent() as ball
		if target == null or not is_instance_valid(target):
			continue
		if not TOOLS.is_enemy(self,target):
			continue
		var target_id:int = target.get_instance_id()
		if hit_ids.has(target_id):
			continue
		hit_ids[target_id] = true
		var outgoing:float = attack_damage(fire_tick_damage_multiplier)
		if outgoing > 0.0:
			var applied:bool = target.receive_fire_positional_damage(outgoing,global_position,false,self)
			if applied:
				play_bladesmith_ball_damage_sfx(outgoing)
		_apply_or_refresh_burn(target)


func _apply_or_refresh_burn(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		return
	var existing:Node = target.get_node_or_null("锻刀师燃烧")
	if existing != null and is_instance_valid(existing) and existing.has_method("refresh"):
		existing.call("refresh",self,burn_duration,attack_damage(burn_tick_damage_multiplier))
		return
	var status:Node = BURN_SCRIPT.new()
	status.name = "锻刀师燃烧"
	target.add_child(status)
	status.call(
		"setup",
		target,
		self,
		burn_duration,
		burn_tick_interval,
		attack_damage(burn_tick_damage_multiplier)
	)


func _spawn_steam_networked() -> void:
	var jitter := Vector2(_rng.randf_range(-16.0,16.0),_rng.randf_range(-8.0,8.0))
	var spawn_position:Vector2 = global_position + jitter
	if multiplayer.has_multiplayer_peer():
		_spawn_steam_rpc.rpc(spawn_position,attack_damage(steam_damage_multiplier))
	else:
		_spawn_steam_rpc(spawn_position,attack_damage(steam_damage_multiplier))


@rpc("authority","call_local","unreliable")
func _spawn_steam_rpc(spawn_position:Vector2,damage_value:float) -> void:
	var steam:Area2D = STEAM_SCENE.instantiate() as Area2D
	if steam == null:
		return
	# V41：World 根节点受 MultiplayerSpawner 监听。旧版直接 world.add_child()
	# 会生成 @Area2D@... 保留名并被 Spawner 连续报错。蒸汽本来已经由本 RPC
	# 在各端显式生成，因此挂到锻刀师自身，并让蒸汽节点 top_level 独立于角色变换。
	_local_effect_serial += 1
	steam.name = "BladesmithSteam_%d" % _local_effect_serial
	steam.call("configure",self,damage_value)
	add_child(steam,true)
	steam.global_position = spawn_position


func _spawn_shockwave_networked() -> void:
	if multiplayer.has_multiplayer_peer():
		_spawn_shockwave_rpc.rpc(global_position,attack_damage(shockwave_damage_multiplier))
	else:
		_spawn_shockwave_rpc(global_position,attack_damage(shockwave_damage_multiplier))


@rpc("authority","call_local","unreliable")
func _spawn_shockwave_rpc(spawn_position:Vector2,damage_value:float) -> void:
	var wave:Area2D = SHOCKWAVE_SCENE.instantiate() as Area2D
	if wave == null:
		return
	# 与蒸汽相同：不要再把临时 Area2D 直接塞进 World/MultiplayerSpawner 的 spawn_path。
	_local_effect_serial += 1
	wave.name = "BladesmithShockwave_%d" % _local_effect_serial
	wave.call("configure",self,damage_value)
	add_child(wave,true)
	wave.global_position = spawn_position


func controlled_attack_action() -> void:
	if not is_multiplayer_authority() or not is_player_controlled():
		return
	if _phase != ForgePhase.BLADE_READY or _sword_attack_active or _blade_durability <= 0.0:
		return
	if is_damage_output_disabled() or _sword_attack_clock < sword_attack_interval:
		return
	_start_sword_attack(null)


func _start_sword_attack(target:ball) -> void:
	var manual_aim:bool = is_player_controlled() and has_player_control_aim()
	if not manual_aim and (target == null or not is_instance_valid(target)):
		return
	_sword_attack_clock = 0.0
	_sword_attack_elapsed = 0.0
	_sword_attack_active = true
	Attacking = true
	_sword_hit_target_ids.clear()
	_sword_base_angle = player_control_aim_direction(direction).angle() if manual_aim else (target.global_position - global_position).angle()
	_sword_swing_reverse = not _sword_swing_reverse
	_afterimage_sample_left = 0.0

	# 每次真正挥刀都会消耗刀条，不要求命中。
	_blade_durability = maxf(_blade_durability - sword_durability_cost,0.0)
	_refresh_character_texture()
	_begin_sword_damage_area()
	_play_sword_swing_sfx_local()
	_broadcast_sword_attack_visual()


func _begin_sword_damage_area() -> void:
	sword_hit_area.collision_mask = 2
	sword_hit_area.monitoring = true
	sword_hit_area.set_meta("threat_debug_damage",attack_damage(sword_damage_multiplier))


func _update_sword_swing_transform(delta:float,gameplay:bool) -> void:
	_sword_attack_elapsed += delta
	var ratio:float = clampf(_sword_attack_elapsed / maxf(sword_swing_duration,0.01),0.0,1.0)
	var eased:float = 1.0 - pow(1.0 - ratio,2.2)
	var start_offset:float = deg_to_rad(-68.0)
	var end_offset:float = deg_to_rad(72.0)
	if _sword_swing_reverse:
		var temp:float = start_offset
		start_offset = -end_offset
		end_offset = -temp
	var angle:float = _sword_base_angle + lerpf(start_offset,end_offset,eased)
	sword_pivot.rotation = angle

	_afterimage_sample_left -= delta
	if _afterimage_sample_left <= 0.0:
		_afterimage_sample_left += 0.045
		_sword_afterimages.append({"angle":angle,"life":0.14})

	if ratio < 1.0:
		return

	_sword_attack_active = false
	Attacking = false
	_refresh_character_texture()
	if gameplay:
		sword_hit_area.monitoring = false
		sword_hit_area.collision_mask = 0
		sword_hit_area.set_meta("threat_debug_damage",0.0)
		_sword_hit_target_ids.clear()
		if _blade_durability <= 0.001:
			_break_blade()


func _on_sword_area_entered(area:Area2D) -> void:
	_try_damage_sword_overlap(area)


func _collect_current_sword_hits() -> void:
	if not _sword_attack_active or not sword_hit_area.monitoring:
		return
	for area:Area2D in sword_hit_area.get_overlapping_areas():
		_try_damage_sword_overlap(area)


func _try_damage_sword_overlap(area:Area2D) -> void:
	if not is_multiplayer_authority() or not _sword_attack_active:
		return
	if area == null or not is_instance_valid(area) or not area is hurtbox:
		return
	var target:ball = area.get_parent() as ball
	if target == null or not is_instance_valid(target) or not TOOLS.is_enemy(self,target):
		return
	var target_id:int = target.get_instance_id()
	if _sword_hit_target_ids.has(target_id):
		return
	_sword_hit_target_ids[target_id] = true
	var outgoing:float = attack_damage(sword_damage_multiplier)
	if outgoing <= 0.0:
		return
	# 无击退：只走真实刀 Area 的空间伤害，不调用 apply_knockback。
	var applied:bool = target.receive_positional_damage(
		outgoing,
		sword_hit_area.global_position,
		false,
		self
	)
	if applied:
		_play_sword_hit_networked(target.global_position)


func _break_blade() -> void:
	_blade_durability = 0.0
	_break_flash_left = 0.34
	_sword_afterimages.clear()
	_enter_phase(ForgePhase.BLUEPRINT)


func get_debug_detection_regions() -> Array[Dictionary]:
	if _phase != ForgePhase.BLADE_READY or health <= 0 or not is_inside_tree():
		return []
	return [{
		"shape":"circle",
		"position":global_position,
		"radius":maxf(sword_attack_range,1.0),
		"kind":"bladesmith_sword_attack_detection",
	}]


# ================================
# 联机视觉同步
# ================================
func _broadcast_phase_visual() -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_sync_phase_visual.rpc(_phase,_forge_progress,_blade_durability)
	else:
		_sync_phase_visual(_phase,_forge_progress,_blade_durability)


@rpc("authority","call_local","reliable")
func _sync_phase_visual(phase_value:int,progress_value:float,durability_value:float) -> void:
	if is_multiplayer_authority():
		# 权威端已经在 _enter_phase 中完成玩法状态，不覆盖计时。
		return
	_forge_runtime_started = true
	_phase = phase_value
	_phase_elapsed = 0.0
	_forge_progress = progress_value
	_blade_durability = durability_value
	_sword_attack_active = false
	_refresh_character_texture()
	_apply_phase_audio_local(_phase)
	queue_redraw()


func _broadcast_hammer_visual(burst_seed:int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_sync_hammer_visual.rpc(_forge_progress,_hammer_visual_side,burst_seed)


@rpc("authority","call_remote","unreliable")
func _sync_hammer_visual(progress_value:float,side_value:float,burst_seed:int) -> void:
	_forge_progress = progress_value
	_hammer_visual_side = side_value
	_hammer_visual_pulse = 1.0
	_refresh_character_texture()
	_play_hammer_sfx_local()
	_spawn_hammer_white_lines_local(burst_seed)
	queue_redraw()


func _broadcast_sword_attack_visual() -> void:
	if multiplayer.has_multiplayer_peer():
		_sync_sword_attack_visual.rpc(
			_sword_base_angle,
			_sword_swing_reverse,
			_blade_durability
		)
	else:
		queue_redraw()


@rpc("authority","call_remote","unreliable")
func _sync_sword_attack_visual(base_angle:float,reverse_value:bool,durability_value:float) -> void:
	_sword_base_angle = base_angle
	_sword_swing_reverse = reverse_value
	_blade_durability = durability_value
	_sword_attack_elapsed = 0.0
	_sword_attack_active = true
	_afterimage_sample_left = 0.0
	_refresh_character_texture()
	_play_sword_swing_sfx_local()
	queue_redraw()


# ================================
# PNG 主视觉 + 程序化战斗特效
# ================================
func _draw() -> void:
	_draw_ground_shadow()
	match _phase:
		ForgePhase.HEATING:
			_draw_heating_aura()
		ForgePhase.HAMMERING:
			_draw_hammer_sparks()
		ForgePhase.SHOWCASE:
			_draw_showcase_glow()
		ForgePhase.BLADE_READY:
			_draw_blade_afterimages()
			_draw_current_blade()
	_draw_progress_bar()
	if _break_flash_left > 0.0:
		_draw_break_flash()


func _draw_ground_shadow() -> void:
	# Godot 4.7 的 CanvasItem 原生 draw_ellipse。
	draw_ellipse(Vector2(0.0,118.0),92.0,24.0,Color(0.0,0.0,0.0,0.22))


func _draw_heating_aura() -> void:
	# V40：烧钢危险区直接使用“低透明红底 + 清晰红描边”。
	# 不再画程序化火焰团，避免视觉误导；圆形视觉与 ForgeFireArea 的真实伤害范围一致。
	var local_radius:float = fire_radius / maxf(absf(global_scale.x),0.001)
	var pulse:float = 0.5 + 0.5 * sin(_visual_time * 6.0)
	draw_circle(Vector2.ZERO,local_radius,Color(0.95,0.04,0.03,0.045 + pulse * 0.018),true)
	draw_arc(
		Vector2.ZERO,
		local_radius,
		0.0,
		TAU,
		96,
		Color(1.0,0.08,0.05,0.76 + pulse * 0.16),
		8.0,
		true
	)


func _draw_hammer_sparks() -> void:
	if _hammer_visual_pulse <= 0.20:
		return
	var alpha:float = clampf(_hammer_visual_pulse,0.0,1.0)
	var impact:= Vector2(88.0,72.0)
	draw_circle(impact,22.0,Color(1.0,0.58,0.08,alpha * 0.52))

	# 暖色火星继续跟随锤击姿势；白线已经改成独立 HitBurstEffect 动画。
	for i:int in range(9):
		var a:float = -2.8 + float(i) * 0.38
		var p1:= impact + Vector2(72.0 + float(i % 3) * 12.0,0.0).rotated(a)
		draw_line(impact,p1,Color(1.0,0.72,0.16,alpha * 0.88),5.0,true)


func _spawn_hammer_white_lines_local(seed:int) -> void:
	if not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var streaks:Array = []
	var count:int = 10
	for i:int in range(count):
		var base_angle:float = TAU * float(i) / float(count)
		var direction_value:Vector2 = Vector2.RIGHT.rotated(
			base_angle + rng.randf_range(-0.16,0.16)
		).normalized()
		streaks.append({
			"spawn_offset": Vector2.ZERO,
			"direction": direction_value,
			"distance": rng.randf_range(26.0,46.0),
			"length": rng.randf_range(7.0,14.0),
			"width": rng.randf_range(0.42,0.78),
			"duration": rng.randf_range(0.24,0.31),
			"delay": rng.randf_range(0.0,0.012),
			"grow_end": 0.32,
			"fade_in_end": 0.12,
			"fade_out_start": 0.52,
			"anchored_origin_motion": true,
			"use_real_time": true,
			"color": Color.WHITE,
		})

	var effect:Node2D = HIT_BURST_EFFECT_SCRIPT.new() as Node2D
	if effect == null:
		return
	_local_effect_serial += 1
	effect.name = "BladesmithHammerBurst_%d" % _local_effect_serial
	# 锻造命中点仍使用原视觉位置；to_global 会自动包含 ball 根节点 0.2 缩放。
	effect.call("setup",to_global(Vector2(88.0,72.0)),streaks)
	add_child(effect,true)


func _draw_showcase_glow() -> void:
	# 07 图本身展示成刀；额外给 0.85 秒展示阶段一圈冷色刀光，明确告诉玩家“刀好了”。
	var duration:float = maxf(showcase_duration,0.01)
	var ratio:float = clampf(_phase_elapsed / duration,0.0,1.0)
	var pulse:float = sin(ratio * PI)
	draw_arc(Vector2.ZERO,132.0,0.0,TAU,64,Color(0.72,0.90,1.0,0.20 + pulse * 0.42),8.0,true)
	var glint:= Vector2(84.0,-72.0)
	draw_line(glint + Vector2(-28.0,0.0),glint + Vector2(28.0,0.0),Color(0.92,0.98,1.0,pulse),5.0,true)
	draw_line(glint + Vector2(0.0,-28.0),glint + Vector2(0.0,28.0),Color(0.92,0.98,1.0,pulse),5.0,true)


func _draw_blade_afterimages() -> void:
	# V41：先画短而淡的历史残影；随后 _draw_current_blade() 再画 100% 不透明当前刀。
	for data:Dictionary in _sword_afterimages:
		var life:float = clampf(float(data.get("life",0.0)) / 0.14,0.0,1.0)
		_draw_sword_texture_at_angle(
			float(data.get("angle",0.0)),
			Color(0.68,0.86,1.0,life * 0.18)
		)


func _draw_current_blade() -> void:
	if not _sword_attack_active:
		return
	# 与残影使用完全相同的刀纹理、大小和旋转轴，但最后绘制且 alpha=1。
	# 用户实际看到的当前刀因此始终压在所有残影之上。
	_draw_sword_texture_at_angle(sword_pivot.rotation,Color(1.0,1.0,1.0,1.0))


func _draw_sword_texture_at_angle(angle:float,tint:Color) -> void:
	# V277：刀图与真实 SwordHitArea 对齐；刀图可见前向约 62 世界像素，攻击 Area 前向约 60 世界像素。
	# 09 原图刀柄约占整宽 30%；现在只让极少一截刀柄落在人物中心后方，
	# 护手与刀刃主体都位于角色前方。ball 根缩放为 0.2，因此总长约 64 世界像素。
	draw_set_transform(Vector2.ZERO,angle,Vector2.ONE)
	draw_texture_rect(
		TEX_SWORD_BODY,
		Rect2(Vector2(-10.0,-53.5),Vector2(320.0,107.0)),
		false,
		tint
	)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)


func _draw_progress_bar() -> void:
	var bar_rect := Rect2(-155.0,166.0,310.0,26.0)
	var blade_phase:bool = _phase == ForgePhase.SHOWCASE or _phase == ForgePhase.BLADE_READY
	var value:float = _blade_durability if blade_phase else _forge_progress
	var ratio:float = clampf(value / 100.0,0.0,1.0)
	var fill_color:Color
	if blade_phase:
		fill_color = Color(0.76,0.88,1.0,1.0) if ratio > 0.25 else Color(1.0,0.20,0.12,1.0)
	else:
		fill_color = Color(lerpf(0.38,1.0,ratio),lerpf(0.08,0.72,ratio),lerpf(0.04,0.18,ratio),1.0)
	BAR.paint(self,bar_rect,ratio,0.0,fill_color)


func _draw_break_flash() -> void:
	var ratio:float = clampf(_break_flash_left / 0.34,0.0,1.0)
	for i:int in range(8):
		var a:float = TAU * float(i) / 8.0 + 0.25
		var p0:= Vector2(72.0,0.0).rotated(a)
		var p1:= Vector2(160.0,0.0).rotated(a)
		draw_line(p0,p1,Color(0.86,0.94,1.0,ratio),12.0,true)
