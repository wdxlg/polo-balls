extends ball

const ARMOR_STAND_TEXTURE:Texture2D = preload("res://Images/characters/默认/盔甲架/盔甲架.png")
const DEATH_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")
const HURT_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/盔甲架/受伤1.ogg"),
	preload("res://audio/characters/盔甲架/受伤2.ogg"),
	preload("res://audio/characters/盔甲架/受伤3.ogg"),
	preload("res://audio/characters/盔甲架/受伤4.ogg"),
]

const DEATH_POSE_DURATION:float = 0.90
const DEATH_BRIDGE_ACTIVE_META:StringName = &"battle_death_bridge_active"
const DEATH_BRIDGE_VICTORY_META:StringName = &"battle_death_bridge_victory_side_key"
const DEATH_BRIDGE_PRESENTATION_META:StringName = &"battle_death_bridge_presentation_side_key"
const DEATH_BRIDGE_DISPLAY_META:StringName = &"battle_death_bridge_display_name"

@export_category("盔甲架 / 受伤音效")
@export_range(0.0,1.0,0.01) var hurt_sound_chance:float = 0.62
@export_range(0.0,1.0,0.01) var hurt_sound_cooldown:float = 0.10
@export_range(-30.0,12.0,0.5) var hurt_volume_db:float = 2.5
@export_range(0.80,1.20,0.01) var hurt_pitch_min:float = 0.96
@export_range(0.80,1.20,0.01) var hurt_pitch_max:float = 1.04

@onready var hurt_audio:AudioStreamPlayer2D = $HurtAudio

var _rng := RandomNumberGenerator.new()
var _hurt_audio_cooldown_left:float = 0.0
var _death_sequence_started:bool = false
var _death_visual_started_local:bool = false


func armor_stand_initial_max_health() -> int:
	# 派生盔甲架可覆写自己的出生生命。必须在第一次 health 写入前就决定，
	# 避免初始化时先写 1000 再写子类生命，导致血条误弹 +N / -N。
	return 1000


func _ready() -> void:
	# 盔甲架本身没有移动、攻击或接触伤害；Speed=0 仍允许外部击退/重力等效果推动它。
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Speed = 0.0
	Damage = 0
	Health_Restore = 0
	Max_health = maxi(armor_stand_initial_max_health(),1)
	if image is Sprite2D:
		var sprite := image as Sprite2D
		sprite.texture = ARMOR_STAND_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.flip_h = false

	super._ready()
	health = Max_health
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/默认/盔甲架.gd:_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1))


func get_preview_texture() -> Texture2D:
	return ARMOR_STAND_TEXTURE


func tick_physics(state:State,delta:float) -> void:
	_hurt_audio_cooldown_left = maxf(_hurt_audio_cooldown_left - maxf(delta,0.0),0.0)
	if _death_visual_started_local:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.tick_physics(state,delta)


func on_actual_health_damage_received(actual_health_damage:float,_health_before:float) -> void:
	if actual_health_damage <= 0.0 or not is_multiplayer_authority() or HURT_SOUNDS.is_empty():
		return
	if _hurt_audio_cooldown_left > 0.0:
		return
	if _rng.randf() > clampf(hurt_sound_chance,0.0,1.0):
		return
	_hurt_audio_cooldown_left = maxf(hurt_sound_cooldown,0.0)
	var index:int = _rng.randi_range(0,HURT_SOUNDS.size() - 1)
	var low_pitch:float = minf(hurt_pitch_min,hurt_pitch_max)
	var high_pitch:float = maxf(hurt_pitch_min,hurt_pitch_max)
	var pitch:float = _rng.randf_range(low_pitch,high_pitch)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_hurt.rpc(index,pitch)
	else:
		_rpc_play_hurt(index,pitch)


@rpc("authority","call_local","unreliable")
func _rpc_play_hurt(index:int,pitch:float) -> void:
	if hurt_audio == null or HURT_SOUNDS.is_empty():
		return
	hurt_audio.stream = HURT_SOUNDS[clampi(index,0,HURT_SOUNDS.size() - 1)]
	hurt_audio.volume_db = hurt_volume_db
	hurt_audio.pitch_scale = clampf(pitch,0.50,2.00)
	hurt_audio.play()


func _has_death_animation() -> bool:
	return true


func Die() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true
	_arm_death_bridge()
	super.Die()
	var death_position:Vector2 = global_position
	if multiplayer.has_multiplayer_peer():
		_rpc_start_death_visual.rpc(death_position)
	else:
		_rpc_start_death_visual(death_position)
	await get_tree().create_timer(DEATH_POSE_DURATION).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


func _stable_victory_side_key(candidate:ball) -> String:
	if candidate == null or not is_instance_valid(candidate):
		return ""
	if candidate.has_meta(&"battle_continuation_victory_side_key"):
		var continuation:String = str(candidate.get_meta(&"battle_continuation_victory_side_key","")).strip_edges()
		if not continuation.is_empty():
			return continuation
	if candidate.has_meta(DEATH_BRIDGE_VICTORY_META):
		var bridged:String = str(candidate.get_meta(DEATH_BRIDGE_VICTORY_META,"")).strip_edges()
		if not bridged.is_empty():
			return bridged
	if candidate.has_meta(&"battle_setup_id"):
		return "solo_setup:" + str(int(candidate.get_meta(&"battle_setup_id")))
	if candidate.has_meta(&"victory_side_key"):
		var cached:String = str(candidate.get_meta(&"victory_side_key","")).strip_edges()
		if not cached.is_empty():
			return cached
	var forced_team:String = ""
	if candidate.has_meta(&"forced_combat_team"):
		forced_team = str(candidate.get_meta(&"forced_combat_team","")).strip_edges()
	if not forced_team.is_empty() and forced_team != "Ball":
		return "team:" + forced_team
	var team_name:String = str(candidate.Team).strip_edges()
	if not team_name.is_empty() and team_name != "Ball":
		return "team:" + team_name
	return "solo_instance:" + str(candidate.get_instance_id())


func _stable_presentation_side_key(candidate:ball) -> String:
	if candidate == null or not is_instance_valid(candidate):
		return ""
	if candidate.has_meta(&"battle_continuation_presentation_side_key"):
		var inherited:String = str(candidate.get_meta(&"battle_continuation_presentation_side_key","")).strip_edges()
		if not inherited.is_empty():
			return inherited
	if candidate.has_meta(DEATH_BRIDGE_PRESENTATION_META):
		var bridged:String = str(candidate.get_meta(DEATH_BRIDGE_PRESENTATION_META,"")).strip_edges()
		if not bridged.is_empty():
			return bridged
	var team_name:String = str(candidate.Team).strip_edges()
	if not team_name.is_empty() and team_name != "Ball":
		return "team:" + team_name
	return "solo:" + str(candidate.get_instance_id())


func _arm_death_bridge() -> void:
	set_meta(DEATH_BRIDGE_ACTIVE_META,true)
	set_meta(DEATH_BRIDGE_VICTORY_META,_stable_victory_side_key(self))
	set_meta(DEATH_BRIDGE_PRESENTATION_META,_stable_presentation_side_key(self))
	set_meta(DEATH_BRIDGE_DISPLAY_META,"盔甲架")


@rpc("authority","call_local","reliable")
func _rpc_start_death_visual(death_position:Vector2) -> void:
	if _death_visual_started_local:
		return
	_death_visual_started_local = true
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	if hurt_audio != null:
		hurt_audio.stop()
	if health_bar != null:
		health_bar.hide()
	if self_hitbox != null:
		self_hitbox.set_deferred(&"monitoring",false)
	if self_hurtbox != null:
		self_hurtbox.set_deferred(&"monitorable",false)
	if graphics != null:
		var rotate_sign:float = -1.0 if direction.x >= 0.0 else 1.0
		var tween:Tween = graphics.create_tween().set_parallel(true)
		tween.tween_property(graphics,"modulate",Color(1.0,0.20,0.20,1.0),0.10)
		tween.tween_property(
			graphics,
			"rotation",
			graphics.rotation + rotate_sign * PI * 0.5,
			DEATH_POSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_create_delayed_death_smoke(death_position)


func _create_delayed_death_smoke(death_position:Vector2) -> void:
	var visual_parent:Node = get_tree().current_scene
	if visual_parent == null:
		return
	var smoke := AnimatedSprite2D.new()
	smoke.name = "盔甲架死亡烟雾"
	smoke.sprite_frames = DEATH_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 8
	smoke.scale = Vector2.ONE * 0.52
	smoke.visible = false
	visual_parent.add_child(smoke)
	smoke.global_position = death_position
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)
	var delayed:Tween = smoke.create_tween()
	delayed.tween_interval(DEATH_POSE_DURATION)
	delayed.tween_callback(Callable(smoke,"show"))
	delayed.tween_callback(Callable(smoke,"play").bind(&"死亡烟雾"))
