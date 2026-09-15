extends ball

# ============================================================
# 气球
# - 一段时间没有受伤就逐渐膨胀：体型、碰撞范围与伤害增加，速度下降。
# - 受到实际生命伤害时立刻漏气并快速缩小，短时间获得移动加速。
# - 正在实际膨胀时播放充气声；真正掉血时播放爆炸声。
# ============================================================

const INFLATE_AUDIO_PATH:String = "res://audio/characters/气球/充气.mp3"
const HURT_EXPLOSION_AUDIO_PATH:String = "res://audio/characters/气球/爆炸.mp3"

@export_category("气球 - 外观（可留空）")
@export var normal_texture:Texture2D

@export_category("气球 - 膨胀")
@export_range(0.0,10.0,0.1) var grow_delay_after_hurt:float = 2.0
@export_range(0.01,2.0,0.01) var grow_per_second:float = 0.16
@export_range(1.0,3.0,0.05) var max_size_multiplier:float = 1.75
@export_range(1.0,5.0,0.05) var max_damage_multiplier:float = 2.1
@export_range(0.1,1.0,0.05) var min_speed_multiplier:float = 0.58
@export_range(0.55,1.0,0.01) var collision_size_multiplier:float = 0.90

@export_category("气球 - 漏气")
@export_range(0.05,3.0,0.05) var deflate_duration:float = 0.55
@export_range(1.0,4.0,0.05) var leak_speed_multiplier:float = 1.75
@export_range(0.05,3.0,0.05) var leak_speed_duration:float = 0.85

@export_category("气球 - 音效")
@export_range(-40.0,6.0,0.5) var inflate_volume_db:float = -10.0
@export_range(-40.0,6.0,0.5) var hurt_explosion_volume_db:float = -6.0
@export_range(100.0,3000.0,50.0) var audio_max_distance:float = 650.0

var _growth:float = 0.0
var _hurt_cooldown_left:float = 0.0
var _leak_speed_left:float = 0.0
var _last_health:int = 0
var _base_speed:float = 0.0
var _base_graphics_scale:Vector2 = Vector2.ONE
var _base_body_shape_scale:Vector2 = Vector2.ONE
var _base_hit_shape_scale:Vector2 = Vector2.ONE
var _base_hurt_shape_scale:Vector2 = Vector2.ONE

var _inflate_player:AudioStreamPlayer2D = null
var _hurt_explosion_player:AudioStreamPlayer2D = null
var _inflate_audio_commanded:bool = false
var _last_hurt_explosion_msec:int = -100000


func _ready() -> void:
	super._ready()
	_auto_load_texture()
	_apply_optional_normal_texture()
	_setup_balloon_audio()
	_last_health = health
	_base_speed = Speed
	_base_graphics_scale = graphics.scale
	_base_body_shape_scale = collision_shape_2d.scale
	_base_hit_shape_scale = self_hitbox.get_node("CollisionShape2D").scale
	_base_hurt_shape_scale = self_hurtbox.get_node("CollisionShape2D").scale
	_apply_balloon_stats()


func tick_physics(state:State,delta:float) -> void:
	# 兜底：如果某种特殊机制绕过 take_damage() 直接减少了生命，也触发漏气/爆炸声。
	if health < _last_health:
		_on_balloon_hurt()
	_last_health = health

	_hurt_cooldown_left = maxf(_hurt_cooldown_left - delta,0.0)
	_leak_speed_left = maxf(_leak_speed_left - delta,0.0)

	if _hurt_cooldown_left <= 0.0:
		_growth = minf(_growth + grow_per_second * delta,1.0)
	else:
		var shrink_speed:float = 1.0 / maxf(deflate_duration,0.05)
		_growth = maxf(_growth - shrink_speed * delta,0.0)

	_apply_balloon_stats()
	_update_inflate_audio(_hurt_cooldown_left <= 0.0 and _growth < 0.9995)
	super.tick_physics(state,delta)


func take_damage(damage:float,ignore_block:bool = false) -> void:
	# 在伤害发生的这一刻处理，而不是等下一物理帧，这样爆炸声与受击同步。
	var before_health:int = health
	super.take_damage(damage,ignore_block)
	if health < before_health:
		_last_health = health
		_on_balloon_hurt()


func _on_balloon_hurt() -> void:
	_hurt_cooldown_left = maxf(grow_delay_after_hurt,0.0)
	_leak_speed_left = maxf(leak_speed_duration,0.0)
	# 受击瞬间先泄掉一大截，剩余部分在 deflate_duration 内继续缩回去。
	_growth *= 0.35
	_update_inflate_audio(false)
	_request_hurt_explosion_audio()


func _apply_balloon_stats() -> void:
	var size_mul:float = lerpf(1.0,maxf(max_size_multiplier,1.0),_growth)
	var speed_mul:float = lerpf(1.0,clampf(min_speed_multiplier,0.1,1.0),_growth)
	if _leak_speed_left > 0.0:
		speed_mul *= maxf(leak_speed_multiplier,1.0)

	Speed = maxf(0.0,_base_speed * speed_mul)

	graphics.scale = _base_graphics_scale * size_mul
	# 气球原先三个碰撞形状和视觉使用完全相同的膨胀倍率，实际看起来会比图像边缘略大。
	# 单独乘一个碰撞缩放系数，让实体碰撞、攻击碰撞和受击碰撞同步收小，同时仍跟随膨胀。
	var collision_mul:float = size_mul * clampf(collision_size_multiplier,0.55,1.0)
	collision_shape_2d.scale = _base_body_shape_scale * collision_mul
	(self_hitbox.get_node("CollisionShape2D") as CollisionShape2D).scale = _base_hit_shape_scale * collision_mul
	(self_hurtbox.get_node("CollisionShape2D") as CollisionShape2D).scale = _base_hurt_shape_scale * collision_mul


func current_hit_damage_multiplier() -> float:
	# 膨胀只改变攻击倍率；当前 Damage 始终保留为整体基础攻击力。
	return lerpf(1.0,maxf(max_damage_multiplier,1.0),clampf(_growth,0.0,1.0))


func _auto_load_texture() -> void:
	if normal_texture != null:
		return
	var path:String = "res://Images/characters/人物/气球/气球_正常.png"
	if ResourceLoader.exists(path):
		var resource:Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			normal_texture = resource as Texture2D


func _apply_optional_normal_texture() -> void:
	if image is Sprite2D and normal_texture != null:
		(image as Sprite2D).texture = normal_texture
		var auto_fit:Node = get_node_or_null("CharacterAutoFit")
		if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
			auto_fit.call_deferred("apply_visual_fit_only")


func _setup_balloon_audio() -> void:
	_inflate_player = AudioStreamPlayer2D.new()
	_inflate_player.name = "InflateAudio"
	_inflate_player.volume_db = inflate_volume_db
	_inflate_player.max_distance = audio_max_distance
	_inflate_player.max_polyphony = 1
	add_child(_inflate_player)

	var inflate_stream:AudioStream = _load_audio_stream(INFLATE_AUDIO_PATH)
	if inflate_stream != null:
		# duplicate() 避免修改 ResourceLoader 共享资源的 loop 属性。
		var local_stream:Resource = inflate_stream.duplicate()
		if local_stream is AudioStream:
			inflate_stream = local_stream as AudioStream
		if inflate_stream is AudioStreamMP3:
			(inflate_stream as AudioStreamMP3).loop = true
		_inflate_player.stream = inflate_stream

	_hurt_explosion_player = AudioStreamPlayer2D.new()
	_hurt_explosion_player.name = "HurtExplosionAudio"
	_hurt_explosion_player.volume_db = hurt_explosion_volume_db
	_hurt_explosion_player.max_distance = audio_max_distance
	# 短时间连续受击允许少量重叠，不让后一发把前一发硬切掉。
	_hurt_explosion_player.max_polyphony = 4
	add_child(_hurt_explosion_player)

	var explosion_stream:AudioStream = _load_audio_stream(HURT_EXPLOSION_AUDIO_PATH)
	if explosion_stream != null:
		var local_explosion:Resource = explosion_stream.duplicate()
		if local_explosion is AudioStream:
			explosion_stream = local_explosion as AudioStream
		if explosion_stream is AudioStreamMP3:
			(explosion_stream as AudioStreamMP3).loop = false
		_hurt_explosion_player.stream = explosion_stream


func _load_audio_stream(path:String) -> AudioStream:
	# 正常情况优先走 ResourceLoader，让 Godot 使用导入缓存。
	if ResourceLoader.exists(path):
		var imported:Resource = ResourceLoader.load(path)
		if imported is AudioStream:
			return imported as AudioStream

	# 刚把补丁复制进项目、导入尚未完成时，也可直接读取 MP3 源文件。
	if FileAccess.file_exists(path):
		var runtime_mp3:AudioStreamMP3 = AudioStreamMP3.load_from_file(path)
		if runtime_mp3 != null:
			return runtime_mp3
	return null


func _update_inflate_audio(should_play:bool) -> void:
	# 联机时只由权威端发布开始/停止命令，避免每个客户端各自重复触发。
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if should_play == _inflate_audio_commanded:
		return
	_inflate_audio_commanded = should_play

	if multiplayer.has_multiplayer_peer():
		_rpc_set_inflate_audio.rpc(should_play)
	else:
		_rpc_set_inflate_audio(should_play)


@rpc("authority","call_local","reliable")
func _rpc_set_inflate_audio(should_play:bool) -> void:
	if _inflate_player == null or _inflate_player.stream == null:
		return
	if should_play:
		if not _inflate_player.playing:
			_inflate_player.play()
	else:
		if _inflate_player.playing:
			_inflate_player.stop()


func _request_hurt_explosion_audio() -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_play_hurt_explosion.rpc()
	else:
		_rpc_play_hurt_explosion()


@rpc("authority","call_local","unreliable")
func _rpc_play_hurt_explosion() -> void:
	_last_hurt_explosion_msec = Time.get_ticks_msec()
	if _hurt_explosion_player != null and _hurt_explosion_player.stream != null:
		_hurt_explosion_player.pitch_scale = randf_range(0.97,1.03)
		_hurt_explosion_player.play()


func Die() -> void:
	_update_inflate_audio(false)
	# 正常致死伤害已经在 take_damage() 中播放。若是某种直接设为死亡的机制，补一次爆炸声。
	if Time.get_ticks_msec() - _last_hurt_explosion_msec > 120:
		_request_hurt_explosion_audio()
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
