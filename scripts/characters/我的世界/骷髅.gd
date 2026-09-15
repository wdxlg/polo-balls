extends ball

const NATIVE_MODEL_ANIMATION = preload("res://scripts/effects/我的世界/mc_native_batch2.gd")
var _native_mob_animation:Node

const ARROW_SCENE:PackedScene = preload("res://scenes/shooter/我的世界/骷髅箭.tscn")
const SKELETON_IDLE_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/骷髅/骷髅待机.webp")
const SKELETON_AIM_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/骷髅/骷髅瞄准.webp")
const SHOOT_SFX:AudioStream = preload("res://audio/characters/骷髅/射箭.ogg")
const HURT_SFX = [
	preload("res://audio/characters/骷髅/骷髅受伤.ogg"),
	preload("res://audio/characters/骷髅/骷髅受伤2.ogg"),
	preload("res://audio/characters/骷髅/骷髅受伤3.ogg"),
]
const WALK_SFX = [
	preload("res://audio/characters/骷髅/骷髅走路.ogg"),
	preload("res://audio/characters/骷髅/骷髅走路2.ogg"),
	preload("res://audio/characters/骷髅/骷髅走路3.ogg"),
]
const DEATH_SFX:AudioStream = preload("res://audio/characters/骷髅/骷髅死亡.ogg")
const DEATH_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")
const DEATH_POSE_DURATION:float = 0.90

@export_category("骷髅 / 弓箭")
@export_range(0.25,3.0,0.01) var starting_attack_interval:float = 1.10
@export_range(0.15,1.5,0.01) var minimum_attack_interval:float = 0.15
@export_range(0.0,0.12,0.001) var attack_speed_gain_per_second:float = 0.030
@export_range(100.0,1000.0,10.0) var arrow_speed:float = 520.0
@export_range(1.0,80.0,1.0) var arrow_direct_damage:float = 8.0
@export_range(0.0,40.0,1.0) var arrow_obstacle_pickup_damage:float = 3.0
@export_range(0.0,20.0,0.5) var arrow_knockback_distance:float = 3.0
@export_range(30.0,300.0,5.0) var arrow_knockback_speed:float = 90.0
@export_range(1.0,15.0,0.5) var obstacle_arrow_lifetime:float = 5.5

@export_category("骷髅 / 音效")
@export_range(0.0,1.0,0.01) var walk_sound_chance:float = 0.55
@export_range(0.0,1.0,0.01) var hurt_sound_chance:float = 0.70
@export_range(0.20,1.20,0.01) var walk_sound_step_interval:float = 0.44
@export_range(0.05,0.60,0.01) var aim_visual_duration:float = 0.20

var _combat_elapsed:float = 0.0
var _walk_sfx_left:float = 0.0
var _hurt_sfx_cooldown:float = 0.0
var _last_health_for_audio:float = -1.0
var _death_audio_played:bool = false
var _death_sequence_started:bool = false
var _death_visual_started_local:bool = false
var _aim_visual_serial:int = 0


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	_native_mob_animation = NATIVE_MODEL_ANIMATION.attach(self,"skeleton")
	add_to_group("MinecraftSkeleton")
	_apply_attack_interval(starting_attack_interval)
	_last_health_for_audio = float(health)
	_set_character_texture(SKELETON_IDLE_TEXTURE)


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health > 0 and is_combat_runtime_active():
		_combat_elapsed += maxf(delta,0.0)
		var interval:float = maxf(
			minimum_attack_interval,
			starting_attack_interval - _combat_elapsed * maxf(attack_speed_gain_per_second,0.0)
		)
		_apply_attack_interval(interval)
	super.tick_physics(state,delta)
	_update_character_audio(state,delta)


func _apply_attack_interval(value:float) -> void:
	Attack_Cooling = maxf(value,0.05)
	if default_properties != null:
		default_properties["Attack_Cooling"] = Attack_Cooling


func Attack() -> void:
	if state_machine == null or state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	super()
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return

	var shoot_dir:Vector2 = direction
	if has_player_control_aim():
		shoot_dir = player_control_aim_direction(direction)
	else:
		var target:Node = return_reusable_combat_target()
		if target is Node2D and is_instance_valid(target):
			shoot_dir = combat_target_position(target) - global_position
	if shoot_dir.length_squared() <= 0.000001:
		Attacking = false
		return
	shoot_dir = shoot_dir.normalized()
	# 攻击只锁定本次射箭朝向，不覆盖角色的 AI 移动 direction。
	# 否则每次 Attack() 都会把移动方向强制改成“朝向目标”，造成攻击时转向/追敌。
	Attacking = true
	_show_aim_visual()
	_play_world_sfx(SHOOT_SFX,global_position,2.0,randf_range(0.98,1.02),1450.0)
	_spawn_arrow(shoot_dir)
	Attacking = false


func _spawn_arrow(shoot_dir:Vector2) -> void:
	var arrow:Area2D = ARROW_SCENE.instantiate() as Area2D
	if arrow == null or get_tree() == null or get_tree().current_scene == null:
		return
	var world:Node = get_tree().current_scene
	world.add_child(arrow,true)
	arrow.global_position = global_position + shoot_dir * 28.0
	if arrow.has_method("configure"):
		arrow.call(
			"configure",
			self,
			Team,
			shoot_dir,
			maxf(arrow_speed,1.0),
			maxf(arrow_direct_damage,0.0),
			maxf(arrow_obstacle_pickup_damage,0.0),
			maxf(arrow_knockback_distance,0.0),
			maxf(arrow_knockback_speed,1.0),
			maxf(obstacle_arrow_lifetime,0.25)
		)


func _show_aim_visual() -> void:
	if is_instance_valid(_native_mob_animation): _native_mob_animation.call("trigger_shot",aim_visual_duration)
	_aim_visual_serial += 1
	var ticket:int = _aim_visual_serial
	_set_character_texture(SKELETON_AIM_TEXTURE)
	if get_tree() == null:
		return
	var timer:SceneTreeTimer = get_tree().create_timer(maxf(aim_visual_duration,0.05),false)
	timer.timeout.connect(Callable(self,"_restore_idle_visual").bind(ticket),CONNECT_ONE_SHOT)


func _restore_idle_visual(ticket:int) -> void:
	if ticket != _aim_visual_serial or not is_instance_valid(self):
		return
	if state_machine != null and state_machine.current_state == State.Die:
		return
	_set_character_texture(SKELETON_IDLE_TEXTURE)


func _set_character_texture(texture:Texture2D) -> void:
	# 帧驱动接管后，旧瞄准计时器和死亡回调不能覆盖回静态图。
	if is_instance_valid(_native_mob_animation) and _native_mob_animation.ready_visual: return
	if texture == null:
		return
	if image is Sprite2D:
		(image as Sprite2D).texture = texture


func _update_character_audio(state:State,delta:float) -> void:
	_hurt_sfx_cooldown = maxf(_hurt_sfx_cooldown - maxf(delta,0.0),0.0)
	var current_health:float = float(health)
	if _last_health_for_audio < 0.0:
		_last_health_for_audio = current_health
	if current_health < _last_health_for_audio - 0.01 and current_health > 0.0 and _hurt_sfx_cooldown <= 0.0:
		if not HURT_SFX.is_empty() and randf() < clampf(hurt_sound_chance,0.0,1.0):
			_play_world_sfx(HURT_SFX.pick_random(),global_position,1.5,randf_range(0.96,1.04),1250.0)
		_hurt_sfx_cooldown = 0.16
	_last_health_for_audio = current_health

	if health <= 0 or state == State.Die:
		return
	var moving:bool = velocity.length_squared() >= 144.0 and is_combat_runtime_active()
	if not moving:
		_walk_sfx_left = minf(_walk_sfx_left,0.08)
		return
	_walk_sfx_left -= maxf(delta,0.0)
	if _walk_sfx_left > 0.0:
		return
	_walk_sfx_left = maxf(walk_sound_step_interval,0.20) * randf_range(0.86,1.14)
	if not WALK_SFX.is_empty() and randf() < clampf(walk_sound_chance,0.0,1.0):
		_play_world_sfx(WALK_SFX.pick_random(),global_position,-0.2,randf_range(0.96,1.04),1050.0)


func _play_world_sfx(stream:AudioStream,at_position:Vector2,volume_db:float = 0.0,pitch:float = 1.0,max_distance:float = 1300.0) -> void:
	if stream == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = maxf(max_distance,1.0)
	player.attenuation = 0.72
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = at_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _has_death_animation() -> bool:
	# 与蠹虫/苦力怕一致：死亡时先保留角色节点完成 Minecraft 风格死亡姿势，
	# 再在原地播放死亡烟雾，最后由 authority 真正释放角色。
	return true


func Die() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true
	var death_position:Vector2 = global_position

	# 公共死亡入口仍保留；骷髅自己的死亡音和视觉由下面的可靠 RPC 同步。
	super()
	_broadcast_death_visual(death_position)

	if get_tree() == null:
		if is_multiplayer_authority() and is_instance_valid(self):
			Game.free_node(self)
		return
	await get_tree().create_timer(DEATH_POSE_DURATION).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


func _broadcast_death_visual(death_position:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_start_death_visual.rpc(death_position)
	else:
		_rpc_start_death_visual(death_position)


@rpc("authority","call_local","reliable")
func _rpc_start_death_visual(death_position:Vector2) -> void:
	if _death_visual_started_local:
		return
	_death_visual_started_local = true
	_aim_visual_serial += 1
	_set_character_texture(SKELETON_IDLE_TEXTURE)

	if not _death_audio_played:
		_death_audio_played = true
		_play_world_sfx(DEATH_SFX,death_position,2.0,randf_range(0.98,1.02),1500.0)

	if health_bar != null and is_instance_valid(health_bar):
		health_bar.hide()

	var graphics:Node2D = get_node_or_null("Graphics") as Node2D
	if graphics != null:
		# 复用项目其它 Minecraft 生物的死亡姿势：快速染红，随后横向倒下约 90°。
		var rotate_sign:float = -1.0 if direction.x >= 0.0 else 1.0
		var tween:Tween = graphics.create_tween()
		tween.set_parallel(true)
		tween.tween_property(graphics,"modulate",Color(1.0,0.22,0.22,1.0),0.10)
		tween.tween_property(
			graphics,
			"rotation",
			graphics.rotation + rotate_sign * PI * 0.5,
			DEATH_POSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_create_delayed_death_smoke(death_position)


func _create_delayed_death_smoke(death_position:Vector2) -> void:
	var visual_parent:Node = _get_runtime_visual_parent()
	if visual_parent == null:
		return

	var smoke := AnimatedSprite2D.new()
	smoke.name = "骷髅死亡烟雾_%d" % smoke.get_instance_id()
	smoke.sprite_frames = DEATH_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 8
	smoke.scale = Vector2.ONE * 0.56
	smoke.visible = false
	visual_parent.add_child(smoke,true)
	smoke.global_position = death_position
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)

	# 烟雾独立挂到运行时视觉容器：骷髅节点在死亡姿势结束后被释放，
	# 烟雾仍能把整段动画自然播放完。
	var delayed:Tween = smoke.create_tween()
	delayed.tween_interval(DEATH_POSE_DURATION)
	delayed.tween_callback(Callable(smoke,"show"))
	delayed.tween_callback(Callable(smoke,"play").bind(&"死亡烟雾"))


func _get_runtime_visual_parent() -> Node:
	if get_tree() == null:
		return null
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func get_preview_texture() -> Texture2D:
	return SKELETON_IDLE_TEXTURE
