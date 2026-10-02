extends Node2D

# 狗叫机制：只有真实碰撞才短叫并增加进度；达到足够碰撞次数后播放持续攻击叫，只有攻击叫仍在播放时才连续造成声波伤害。
const BIG_SHORT_BARK:AudioStream = preload("res://audio/characters/meme/大狗叫/大狗大狗.MP3")
const SMALL_SHORT_BARK:AudioStream = preload("res://audio/characters/meme/大狗叫/小狗小狗.MP3")
const BIG_ATTACK_BARK:AudioStream = preload("res://audio/characters/meme/大狗叫/大狗叫.MP3")
const SMALL_ATTACK_BARK:AudioStream = preload("res://audio/characters/meme/大狗叫/小狗叫.MP3")
const WAVE_VISUAL_SCRIPT = preload("res://scripts/effects/狗叫声波.gd")

const BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
const PROGRESS_BAR_FILL_COLOR:Color = Color(1.0,1.0,1.0,1.0)
## 共享条底槽乘色：原版底槽主色 57/255 乘它后等于原来的 (0.10,0.10,0.115)。
const PROGRESS_BAR_TROUGH_TINT:Color = Color(0.4474,0.4474,0.5145,1.0)

@export_category("狗叫机制 - 碰撞蓄力")
# 只有实际碰撞才会播放短叫并增加一次进度，不再存在定时自动短叫。
@export_range(6,80,1) var collisions_before_howl:int = 20
@export_range(0.05,1.0,0.01) var contact_sound_cooldown:float = 0.24

@export_category("狗叫机制 - 碰撞蓄力条")
# 和 Sans 闪避条一致：初始隐藏；每次真实碰撞推进进度时出现，停留后渐隐。
# V176：条整体缩小并贴近大小狗脚下，避免遮挡人物和占用过多战场空间。
@export_range(0.20,2.0,0.05) var progress_bar_hold_duration:float = 0.85
@export_range(0.10,1.5,0.05) var progress_bar_fade_duration:float = 0.45
@export_range(20.0,120.0,1.0) var big_progress_bar_width:float = 44.0
@export_range(16.0,100.0,1.0) var small_progress_bar_width:float = 30.0
@export_range(3.0,18.0,0.5) var progress_bar_height:float = 5.0
@export_range(6.0,80.0,1.0) var big_progress_bar_y_offset:float = 22.0
@export_range(4.0,80.0,1.0) var small_progress_bar_y_offset:float = 14.0

@export_category("狗叫机制 - 攻击声波")
@export_range(0.05,1.5,0.01) var wave_interval:float = 0.10
@export_range(8.0,120.0,1.0) var contact_radius:float = 34.0
@export_range(24.0,320.0,1.0) var wave_radius:float = 145.0
# 大狗的 Damage（攻击力）就是大狗声波基础伤害；这里仅保留倍率。
@export_range(0.0,10.0,0.05) var wave_damage_multiplier:float = 1.0
@export_range(0.0,10.0,0.05) var small_wave_damage_multiplier:float = 0.3333333
@export_range(0.0,80.0,0.5) var wave_knockback_distance:float = 6.0
@export_range(0.0,800.0,5.0) var wave_knockback_speed:float = 180.0

@export_category("狗叫机制 - 音效")
@export_range(-48.0,12.0,0.5) var short_bark_volume_db:float = 1.5
@export_range(-48.0,12.0,0.5) var attack_bark_volume_db:float = 3.0
@export_range(100.0,4000.0,50.0) var sfx_max_distance:float = 2200.0
@export_range(0.1,4.0,0.05) var sfx_attenuation:float = 0.45

@onready var contact_area:Area2D = $ContactArea
@onready var contact_shape:CollisionShape2D = $ContactArea/CollisionShape2D
@onready var damage_area:Area2D = $DamageArea
@onready var damage_shape:CollisionShape2D = $DamageArea/CollisionShape2D
@onready var short_audio_a:AudioStreamPlayer2D = $ShortBarkAudio
@onready var short_audio_b:AudioStreamPlayer2D = $ShortBarkAudioB
@onready var attack_audio:AudioStreamPlayer2D = $HowlAudio

var _actor:Node2D = null
var _damage_source:ball = null
var _team:String = ""
var _small_variant:bool = false
var _enabled:bool = true
var _sound_count:int = 0
var _contact_cooldown_left:float = 0.0
var _wave_left:float = 0.0
var _howling:bool = false
var _pending_howl:bool = false
var _manual_howl_requested:bool = false
var _ready_configured:bool = false
var _wave_visual_manager:Node2D = null
var _short_audio_turn:int = 0
var _progress_visual_count:int = 0
var _progress_bar_alpha:float = 0.0
var _progress_bar_hold_left:float = 0.0
var _progress_bar_fade_left:float = 0.0


# 初始化狗叫组件；大狗自己结算伤害，小狗把大狗作为伤害归属与阵营来源。
func setup(actor:Node2D,damage_source:ball,team_value:String,small_variant:bool) -> void:
	_actor = actor
	_damage_source = damage_source
	_team = team_value
	_small_variant = small_variant
	if _damage_source != null and is_instance_valid(_damage_source):
		set_multiplayer_authority(_damage_source.get_multiplayer_authority(),true)
	_apply_variant_defaults()
	_configure_runtime_nodes()
	_progress_visual_count = clampi(_sound_count,0,maxi(collisions_before_howl,1))
	_ready_configured = true


# 创建后自动识别直接挂在大狗下面的机制；小狗由自己的脚本显式 setup。
func _ready() -> void:
	add_to_group("AI_Hazard")
	if get_parent() is ball:
		var parent_ball:ball = get_parent() as ball
		setup(parent_ball,parent_ball,parent_ball.Team,false)
	else:
		_configure_runtime_nodes()


# 小狗保持同一套“碰撞推进→持续叫”流程，但范围、伤害和击退仍明显弱于大狗。
func _apply_variant_defaults() -> void:
	if not _small_variant:
		return
	contact_radius = 18.0
	wave_radius = 32.0
	wave_knockback_distance = 1.2
	wave_knockback_speed = 65.0
	wave_interval = 0.16
	short_bark_volume_db = 0.0
	attack_bark_volume_db = 1.5
	sfx_max_distance = 1400.0
	sfx_attenuation = 0.55


func _current_wave_damage_multiplier() -> float:
	return maxf(small_wave_damage_multiplier if _small_variant else wave_damage_multiplier,0.0)


func _current_wave_damage() -> float:
	if _damage_source == null or not is_instance_valid(_damage_source):
		return 0.0
	return _damage_source.attack_damage(_current_wave_damage_multiplier())


# 配置真实碰撞圆和音频节点；所有新音频直接按原始 MP3 播放，运行时 pitch_scale 永远为 1。
func _configure_runtime_nodes() -> void:
	if contact_shape != null and contact_shape.shape is CircleShape2D:
		var contact_circle:CircleShape2D = contact_shape.shape.duplicate() as CircleShape2D
		if contact_circle != null:
			contact_shape.shape = contact_circle
			contact_circle.radius = _world_radius_to_local(contact_radius)

	if damage_shape != null and damage_shape.shape is CircleShape2D:
		var damage_circle:CircleShape2D = damage_shape.shape.duplicate() as CircleShape2D
		if damage_circle != null:
			damage_shape.shape = damage_circle
			damage_circle.radius = _world_radius_to_local(wave_radius)
			damage_shape.set_deferred("disabled",true)

	if contact_area != null:
		contact_area.collision_layer = 0
		contact_area.collision_mask = 3
		contact_area.monitoring = true
		contact_area.monitorable = false
		if not contact_area.body_entered.is_connected(_on_contact_body_entered):
			contact_area.body_entered.connect(_on_contact_body_entered)

	if damage_area != null:
		damage_area.collision_layer = 0
		damage_area.collision_mask = 2
		damage_area.monitoring = false
		damage_area.monitorable = false

	var short_stream:AudioStream = _get_short_bark_stream()
	for player:AudioStreamPlayer2D in [short_audio_a,short_audio_b]:
		if player == null:
			continue
		player.stream = short_stream
		player.pitch_scale = 1.0 # 蓄力后期只缩短“叫声间隔”，不改变每一声本身的速度/音高。
		player.volume_db = short_bark_volume_db
		player.max_distance = maxf(sfx_max_distance,100.0)
		player.attenuation = clampf(sfx_attenuation,0.1,4.0)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		if not player.finished.is_connected(_on_short_bark_finished):
			player.finished.connect(_on_short_bark_finished)

	if attack_audio != null:
		attack_audio.stream = _get_attack_bark_stream()
		attack_audio.pitch_scale = 1.0 # 新攻击叫本身约 4 秒且连续，直接原速播放，彻底去掉旧版极端 time-stretch 的颤抖。
		attack_audio.volume_db = attack_bark_volume_db
		attack_audio.max_distance = maxf(sfx_max_distance,100.0)
		attack_audio.attenuation = clampf(sfx_attenuation,0.1,4.0)
		attack_audio.process_mode = Node.PROCESS_MODE_ALWAYS
		if not attack_audio.finished.is_connected(_on_attack_bark_finished):
			attack_audio.finished.connect(_on_attack_bark_finished)


# 返回当前大小狗对应的原始短叫音频。
func _get_short_bark_stream() -> AudioStream:
	return SMALL_SHORT_BARK if _small_variant else BIG_SHORT_BARK


# 返回当前大小狗对应的原始持续攻击叫音频。
func _get_attack_bark_stream() -> AudioStream:
	return SMALL_ATTACK_BARK if _small_variant else BIG_ATTACK_BARK


# 把期望世界半径换算为当前节点的局部圆半径，兼容大狗根节点缩放。
func _world_radius_to_local(world_radius:float) -> float:
	var scale_value:Vector2 = global_scale.abs()
	var max_scale:float = maxf(maxf(scale_value.x,scale_value.y),0.0001)
	return maxf(world_radius,1.0) / max_scale


# 碰撞进度条只负责视觉渐隐；不推进任何蓄力逻辑。
func _process(delta:float) -> void:
	_update_collision_progress_bar(maxf(delta,0.0))


func _show_collision_progress_bar(progress_count:int) -> void:
	_progress_visual_count = clampi(progress_count,0,maxi(collisions_before_howl,1))
	_progress_bar_alpha = 1.0
	_progress_bar_hold_left = maxf(progress_bar_hold_duration,0.0)
	_progress_bar_fade_left = maxf(progress_bar_fade_duration,0.05)
	queue_redraw()


func _update_collision_progress_bar(delta:float) -> void:
	if _progress_bar_alpha <= 0.0:
		return
	if _progress_bar_hold_left > 0.0:
		_progress_bar_hold_left = maxf(_progress_bar_hold_left - delta,0.0)
	else:
		_progress_bar_fade_left = maxf(_progress_bar_fade_left - delta,0.0)
		_progress_bar_alpha = clampf(
			_progress_bar_fade_left / maxf(progress_bar_fade_duration,0.05),
			0.0,1.0
		)
	queue_redraw()


# BarkMechanic 会继承大小狗根节点不同的缩放；这里用 global_scale 反算局部尺寸，
# 确保大小狗脚下的条在世界空间里保持清楚、接近一致的像素粗细。
func _progress_bar_world_rect() -> Rect2:
	var scale_value:Vector2 = global_scale.abs()
	var inv_scale:=Vector2(
		1.0 / maxf(scale_value.x,0.0001),
		1.0 / maxf(scale_value.y,0.0001)
	)
	var world_width:float = small_progress_bar_width if _small_variant else big_progress_bar_width
	var world_y:float = small_progress_bar_y_offset if _small_variant else big_progress_bar_y_offset
	return Rect2(
		Vector2(-world_width * 0.5 * inv_scale.x,world_y * inv_scale.y),
		Vector2(world_width * inv_scale.x,progress_bar_height * inv_scale.y)
	)


func _draw() -> void:
	if _progress_bar_alpha <= 0.001 or not _enabled:
		return
	var max_count:int = maxi(collisions_before_howl,1)
	var count:int = clampi(_progress_visual_count,0,max_count)
	var rect:Rect2 = _progress_bar_world_rect()
	BAR.paint(self,rect,float(count) / float(max_count),0.0,PROGRESS_BAR_FILL_COLOR,PROGRESS_BAR_TROUGH_TINT,clampf(_progress_bar_alpha,0.0,1.0),max_count)


# 每个物理帧只维护待攻击和持续攻击；碰撞蓄力本身没有任何定时自动推进。
func _physics_process(delta:float) -> void:
	if not _ready_configured or not _enabled:
		return
	if _damage_source == null or not is_instance_valid(_damage_source) or _damage_source.health <= 0:
		_stop_howl(false)
		return
	if not _damage_source.is_combat_runtime_active() or not _damage_source.is_multiplayer_authority():
		return

	_contact_cooldown_left = maxf(_contact_cooldown_left - delta,0.0)

	if _howling:
		if attack_audio == null or not attack_audio.playing:
			_stop_howl(true)
			return
		_wave_left -= delta
		while _wave_left <= 0.0 and attack_audio.playing:
			_wave_left += maxf(wave_interval,0.08)
			_emit_damage_wave()
		return

	if _pending_howl:
		if not _any_short_bark_playing() and (not _manual_actor_controlled() or _manual_howl_requested):
			_start_howl()
		return

	# 蓄力阶段没有自动计时发声；只有 notify_collision() 能推进碰撞进度。


# Area2D 检测到身体进入时转给统一碰撞入口。
func _on_contact_body_entered(body:Node2D) -> void:
	notify_collision(body)


# 统一处理碰墙/碰单位短叫；小狗的真实 slide collision 也调用这里。
func notify_collision(body:Object) -> void:
	if not _enabled or _howling or _pending_howl or _contact_cooldown_left > 0.0:
		return
	if _damage_source == null or not is_instance_valid(_damage_source) or not _damage_source.is_multiplayer_authority():
		return
	if body == null or body == _actor or body == _damage_source:
		return
	if body is Node and _actor != null and _actor.is_ancestor_of(body as Node):
		return

	_contact_cooldown_left = maxf(contact_sound_cooldown,0.05)
	_emit_normal_sound()


# 每一次有效碰撞只播放一声原始短叫并增加 1 点进度；没有碰撞就绝不会自己增加。
func _emit_normal_sound() -> void:
	_sound_count += 1
	_broadcast_short_bark()

	if _sound_count >= maxi(collisions_before_howl,1):
		_pending_howl = true # 达到碰撞阈值后等待当前短叫自然播完，再进入持续攻击叫。


# 任意短叫播放器结束后检查最后一轮是否已经全部播完。
func _on_short_bark_finished() -> void:
	if not _pending_howl or _howling:
		return
	if _any_short_bark_playing():
		return
	if _damage_source == null or not is_instance_valid(_damage_source) or not _damage_source.is_multiplayer_authority():
		return
	if not _manual_actor_controlled() or _manual_howl_requested: _start_howl()

func _manual_actor_controlled() -> bool:
	return is_instance_valid(_actor) and _actor is ball and (_actor as ball).is_player_controlled()
func request_manual_howl() -> void:
	if not _manual_actor_controlled() or not _ready_configured or not _enabled or not _pending_howl or _howling: return
	if not is_instance_valid(_damage_source) or not _damage_source.is_multiplayer_authority() or not _damage_source.is_combat_runtime_active(): return
	_manual_howl_requested=true
	if not _any_short_bark_playing(): _start_howl()


# 返回当前是否仍有任意一声短叫在播放。
func _any_short_bark_playing() -> bool:
	return (
		(short_audio_a != null and short_audio_a.playing)
		or (short_audio_b != null and short_audio_b.playing)
	)


# 新的原始持续攻击叫自然播放结束时立刻停止攻击，并把蓄力节奏恢复。
func _on_attack_bark_finished() -> void:
	if not _howling:
		return
	if _damage_source != null and is_instance_valid(_damage_source) and _damage_source.is_multiplayer_authority():
		_stop_howl(true)
	else:
		_howling = false


# 进入持续攻击叫：打开真实 DamageArea；持续多久完全取决于当前大小狗原始攻击 MP3 的真实播放长度。
func _start_howl() -> void:
	if _howling:
		return
	_pending_howl = false
	_manual_howl_requested = false
	_howling = true
	_wave_left = 0.06
	if damage_area != null:
		damage_area.set_deferred("monitoring",true)
	if damage_shape != null:
		damage_shape.set_deferred("disabled",false)
		damage_shape.set_meta("threat_debug_damage",_current_wave_damage())
	_broadcast_howl_start()


# 停止持续攻击叫并恢复初始短叫节奏；死亡/停用时可以不重新排程。
func _stop_howl(_reschedule:bool) -> void:
	if not _howling and not _pending_howl and (damage_shape == null or damage_shape.disabled):
		return
	_howling = false
	_pending_howl = false
	_manual_howl_requested = false
	_wave_left = 0.0
	_sound_count = 0

	if damage_area != null:
		damage_area.set_deferred("monitoring",false)
	if damage_shape != null:
		damage_shape.set_deferred("disabled",true)
		if damage_shape.has_meta("threat_debug_damage"):
			damage_shape.remove_meta("threat_debug_damage")

	if _damage_source != null and is_instance_valid(_damage_source) and _damage_source.is_multiplayer_authority():
		_broadcast_howl_stop()
	elif attack_audio != null:
		attack_audio.stop()

	# V69 起攻击结束后不再安排自动短叫；下一轮进度只能由真实碰撞重新累积。

# 对当前真实声波圆内敌人结算一次伤害和击退，并产生一个纯白描边扩散圆。
func _emit_damage_wave() -> void:
	if damage_area == null or _damage_source == null or not is_instance_valid(_damage_source):
		return

	var source_damage:float = _current_wave_damage()
	if source_damage > 0.0:
		for body:Node2D in damage_area.get_overlapping_bodies():
			if not body is ball:
				continue
			var target:ball = body as ball
			if not _can_damage_target(target):
				continue

			var accepted:bool = target.receive_spatial_damage(
				source_damage,
				{
					"shape":"circle",
					"center":global_position,
					"radius":wave_radius,
					"point":target.global_position,
					"source":_damage_source,
				},
				false,
				false
			)
			if accepted and wave_knockback_distance > 0.0 and wave_knockback_speed > 0.0:
				var push:Vector2 = target.global_position - global_position
				if push.length_squared() <= 0.000001:
					push = Vector2.RIGHT.rotated(randf_range(0.0,TAU))
				target.apply_knockback(
					push.normalized(),
					wave_knockback_distance,
					wave_knockback_speed,
					0.0,
					0.0,
					{"source":_damage_source,"stop_on_character":false}
				)

	_broadcast_wave_visual(global_position,wave_radius,_small_variant)


# 判断声波能否伤害目标，继续尊重项目友伤设置和主人关系。
func _can_damage_target(target:ball) -> bool:
	if target == null or target == _damage_source or target.health <= 0:
		return false
	if target.Master != null and is_instance_valid(target.Master) and target.Master == _damage_source:
		return false
	var target_team:String = str(target.Team).strip_edges()
	if not _team.is_empty() and target_team == _team:
		return false
	return true


# 返回当前是否正在播放持续攻击叫；大狗/小狗视觉据此切换到新的犬吠图片。
func is_howling() -> bool:
	return _howling


# 返回当前已经累计的短叫次数，便于 Inspector/调试查看蓄力进度。
func get_sound_count() -> int:
	return _sound_count


# 返回当前碰撞蓄力进度 0~1；只有实际碰撞会改变该值。
func get_collision_progress() -> float:
	return clampf(float(_sound_count) / float(maxi(collisions_before_howl,1)),0.0,1.0)


# 主人死亡等特殊情况可关闭机制；关闭时立即停止攻击并清理伤害圆。
func set_mechanic_enabled(value:bool) -> void:
	_enabled = value
	if not _enabled:
		_progress_bar_alpha = 0.0
		_progress_bar_hold_left = 0.0
		_progress_bar_fade_left = 0.0
		queue_redraw()
		_stop_howl(false)


# AI Hazard：只有持续攻击叫正在播放时才报告真实 DamageArea 圆。
func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	if not _howling or attack_audio == null or not attack_audio.playing or damage_shape == null or damage_shape.disabled or _damage_source == null:
		return {}
	return {
		"shape":"circle",
		"center":global_position,
		"radius":wave_radius,
		"damage":_current_wave_damage(),
		"kind":"dog_bark_wave_small" if _small_variant else "dog_bark_wave_big",
		"source":_damage_source,
	}


# 广播一声原始短叫；所有客户端播放相同文件，不在运行时改 pitch。
func _broadcast_short_bark() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_short_bark.rpc(_sound_count)
	else:
		_rpc_play_short_bark(_sound_count)


# 使用两个 AudioStreamPlayer2D 交替播放原始短叫，蓄力后期即使间隔缩短也不会把上一声硬截断。
@rpc("authority","call_local","unreliable")
func _rpc_play_short_bark(progress_count:int) -> void:
	_show_collision_progress_bar(progress_count)
	var players:Array[AudioStreamPlayer2D] = [short_audio_a,short_audio_b]
	var chosen:AudioStreamPlayer2D = null

	for offset:int in range(players.size()):
		var index:int = (_short_audio_turn + offset) % players.size()
		var candidate:AudioStreamPlayer2D = players[index]
		if candidate != null and not candidate.playing:
			chosen = candidate
			_short_audio_turn = (index + 1) % players.size()
			break

	if chosen == null:
		chosen = players[_short_audio_turn]
		_short_audio_turn = (_short_audio_turn + 1) % players.size()

	if chosen == null:
		return

	chosen.stream = _get_short_bark_stream()
	chosen.pitch_scale = 1.0
	chosen.volume_db = short_bark_volume_db
	chosen.play()


# 广播持续攻击叫开始；直接使用用户提供的新原始 MP3，不再离线 time-stretch 或重复拼接。
func _broadcast_howl_start() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_howl.rpc()
	else:
		_rpc_play_howl()


# 播放大小狗各自的新持续攻击叫；只有播放器 playing=true 时，权威端才继续产生伤害声波。
@rpc("authority","call_local","unreliable")
func _rpc_play_howl() -> void:
	_howling = true
	if attack_audio == null:
		return
	attack_audio.stop()
	attack_audio.stream = _get_attack_bark_stream()
	attack_audio.pitch_scale = 1.0
	attack_audio.volume_db = attack_bark_volume_db
	attack_audio.play()


# 广播攻击叫结束，确保所有客户端立即清掉犬吠视觉和残余声音。
func _broadcast_howl_stop() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_stop_howl.rpc()
	else:
		_rpc_stop_howl()


# 本地停止攻击叫；已经发出的白色声波仍会把自己的渐隐动画自然播完，只是不再产生新波。
@rpc("authority","call_local","unreliable")
func _rpc_stop_howl() -> void:
	_howling = false
	_progress_visual_count = 0
	_progress_bar_alpha = 0.0
	_progress_bar_hold_left = 0.0
	_progress_bar_fade_left = 0.0
	queue_redraw()
	if attack_audio != null:
		attack_audio.stop()


# 广播一枚新的声波视觉；前一枚仍在扩散时不会被删除，因此攻击期间会连续叠加白色扩散圆。
func _broadcast_wave_visual(origin:Vector2,radius:float,small_variant:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_wave_visual.rpc(origin,radius,small_variant)
	else:
		_rpc_spawn_wave_visual(origin,radius,small_variant)


# 复用单个轻量声波管理器，让多个白圈同时扩散；避免每个圈都创建一个独立 SceneTree 节点。
@rpc("authority","call_local","unreliable")
func _rpc_spawn_wave_visual(origin:Vector2,radius:float,small_variant:bool) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	if _wave_visual_manager == null or not is_instance_valid(_wave_visual_manager):
		_wave_visual_manager = Node2D.new()
		_wave_visual_manager.name = "小狗叫连续声波" if small_variant else "大狗叫连续声波"
		_wave_visual_manager.set_script(WAVE_VISUAL_SCRIPT)
		world.add_child(_wave_visual_manager)
	_wave_visual_manager.call("emit_wave",origin,radius,small_variant)
