extends "res://scripts/characters/默认/盔甲架.gd"

const ARROW_SCENE:PackedScene = preload("res://scenes/shooter/我的世界/骷髅箭.tscn")
const SHOOT_SFX:AudioStream = preload("res://audio/characters/骷髅/射箭.ogg")
const BOW_TEXTURE:Texture2D = preload("res://Images/characters/默认/盔甲架/Bow.png")
const BOW_PULL_0_TEXTURE:Texture2D = preload("res://Images/characters/默认/盔甲架/Bow_Pulling_0.png")
const BOW_PULL_1_TEXTURE:Texture2D = preload("res://Images/characters/默认/盔甲架/Bow_Pulling_1.png")
const BOW_PULL_2_TEXTURE:Texture2D = preload("res://Images/characters/默认/盔甲架/Bow_Pulling_2.png")

@export_category("弓箭盔甲架 / 弓箭")
@export_range(0.50,4.0,0.05) var bow_attack_interval:float = 1.75
@export_range(100.0,1000.0,10.0) var arrow_speed:float = 520.0
@export_range(1.0,80.0,1.0) var arrow_damage:float = 10.0
@export_range(0.0,20.0,0.5) var arrow_knockback_distance:float = 3.0
@export_range(30.0,300.0,5.0) var arrow_knockback_speed:float = 90.0
@export_range(1.0,15.0,0.5) var wall_arrow_lifetime:float = 5.5

@export_category("弓箭盔甲架 / 弓显示")
@export_range(30.0,140.0,1.0) var bow_orbit_radius:float = 72.0
@export_range(0.03,0.30,0.01) var bow_pull_frame_time:float = 0.10
@export_range(0.02,0.20,0.01) var bow_release_hold_time:float = 0.05
@export_range(0.02,0.30,0.005) var bow_visual_scale:float = 0.115
# 拉满帧里的箭头位于弓 Sprite 中心前方约 57px（按默认 0.115 缩放计算）。
# 这里取 58px，使真正生成的箭从拉弓图里箭头所在的“弓头/出箭口”位置出现。
@export_range(0.0,120.0,1.0) var bow_arrow_release_offset:float = 58.0
# Minecraft 弓原图斜向构图；+135° 后弓弧朝局部 +X（敌人方向）、弓弦在后方。
# V35 的 -45° 恰好把前后翻反了。
@export_range(-180.0,180.0,1.0) var bow_texture_angle_offset_degrees:float = 135.0

var _bow_pivot:Node2D = null
var _bow_sprite:Sprite2D = null
var _bow_muzzle:Marker2D = null
var _bow_aim_direction:Vector2 = Vector2.RIGHT
var _bow_animation_serial:int = 0


func _ready() -> void:
	super._ready()
	Max_health = 1000
	health = Max_health
	Damage = int(round(arrow_damage))
	Speed = 0.0
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Attack_Cooling = maxf(bow_attack_interval,0.05)
	Skill_Cooling = 999.0
	Health_Restore = 0
	if default_properties != null:
		default_properties["Max_health"] = Max_health
		default_properties["Damage"] = Damage
		default_properties["Speed"] = Speed
		default_properties["Attack_Cooling"] = Attack_Cooling
	_build_bow_visual()
	_update_bow_aim()


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if state != State.Die:
		_update_bow_aim()


func _build_bow_visual() -> void:
	_bow_pivot = Node2D.new()
	_bow_pivot.name = "BowPivot"
	_bow_pivot.z_index = 6
	add_child(_bow_pivot)

	_bow_sprite = Sprite2D.new()
	_bow_sprite.name = "Bow"
	_bow_sprite.texture = BOW_TEXTURE
	_bow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bow_sprite.scale = Vector2.ONE * bow_visual_scale
	_bow_sprite.position = Vector2(bow_orbit_radius,0.0)
	_bow_sprite.rotation = deg_to_rad(bow_texture_angle_offset_degrees)
	_bow_pivot.add_child(_bow_sprite)

	# 出箭点跟随 BowPivot 一起绕盔甲架中心旋转。它不依赖 Bow.png 的中心点，
	# 而是放在“弓中心 + 拉满帧箭头前端”的位置。
	_bow_muzzle = Marker2D.new()
	_bow_muzzle.name = "ArrowMuzzle"
	_bow_muzzle.position = Vector2(bow_orbit_radius + bow_arrow_release_offset,0.0)
	_bow_pivot.add_child(_bow_muzzle)


func _resolve_bow_aim_direction() -> Vector2:
	var aim:Vector2 = direction
	if has_player_control_aim():
		aim = player_control_aim_direction(direction)
	else:
		var target:Node = return_reusable_combat_target()
		if target is Node2D and is_instance_valid(target):
			aim = combat_target_position(target) - global_position
	if aim.length_squared() <= 0.000001:
		return _bow_aim_direction
	return aim.normalized()


func _update_bow_aim() -> void:
	if _bow_pivot == null or not is_instance_valid(_bow_pivot):
		return
	_bow_aim_direction = _resolve_bow_aim_direction()
	if _bow_aim_direction.length_squared() <= 0.000001:
		_bow_aim_direction = Vector2.RIGHT
	# V191：角色根节点会被 Sans 定向重力整体旋转；瞄准方向来自世界坐标，
	# 因此 BowPivot 也必须写 global_rotation，不能把世界角直接塞进局部 rotation。
	_bow_pivot.global_rotation = _bow_aim_direction.angle()
	if _bow_sprite != null and is_instance_valid(_bow_sprite):
		_bow_sprite.position = Vector2(bow_orbit_radius,0.0)
		_bow_sprite.rotation = deg_to_rad(bow_texture_angle_offset_degrees)
	if _bow_muzzle != null and is_instance_valid(_bow_muzzle):
		_bow_muzzle.position = Vector2(bow_orbit_radius + bow_arrow_release_offset,0.0)


func Attack() -> void:
	if state_machine == null or state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	super()
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return

	var shoot_dir:Vector2 = _resolve_bow_aim_direction()
	if shoot_dir.length_squared() <= 0.000001:
		Attacking = false
		return

	Attacking = true
	_bow_animation_serial += 1
	var serial:int = _bow_animation_serial
	if multiplayer.has_multiplayer_peer():
		_rpc_start_bow_pull.rpc(serial)
	else:
		_rpc_start_bow_pull(serial)

	# 0 -> 1 -> 2；拉满之后恢复 Bow.png，再真正发射箭。
	await get_tree().create_timer(maxf(bow_pull_frame_time,0.01) * 3.0).timeout
	if not is_instance_valid(self) or serial != _bow_animation_serial:
		return
	if state_machine == null or state_machine.current_state == State.Die:
		Attacking = false
		return

	shoot_dir = _resolve_bow_aim_direction()
	if shoot_dir.length_squared() <= 0.000001:
		Attacking = false
		return
	shoot_dir = shoot_dir.normalized()
	_bow_aim_direction = shoot_dir
	_update_bow_aim()
	if _bow_sprite != null and is_instance_valid(_bow_sprite):
		_bow_sprite.texture = BOW_TEXTURE
	_play_bow_sfx()
	_spawn_plain_arrow(shoot_dir)
	await get_tree().create_timer(maxf(bow_release_hold_time,0.01)).timeout
	Attacking = false


@rpc("authority","call_local","reliable")
func _rpc_start_bow_pull(serial:int) -> void:
	_bow_animation_serial = maxi(_bow_animation_serial,serial)
	_play_bow_pull_visual(serial)


func _play_bow_pull_visual(serial:int) -> void:
	if _bow_sprite == null or not is_instance_valid(_bow_sprite):
		return
	_bow_sprite.texture = BOW_PULL_0_TEXTURE
	await get_tree().create_timer(maxf(bow_pull_frame_time,0.01)).timeout
	if serial != _bow_animation_serial or not is_instance_valid(_bow_sprite):
		return
	_bow_sprite.texture = BOW_PULL_1_TEXTURE
	await get_tree().create_timer(maxf(bow_pull_frame_time,0.01)).timeout
	if serial != _bow_animation_serial or not is_instance_valid(_bow_sprite):
		return
	_bow_sprite.texture = BOW_PULL_2_TEXTURE
	await get_tree().create_timer(maxf(bow_pull_frame_time,0.01)).timeout
	if serial != _bow_animation_serial or not is_instance_valid(_bow_sprite):
		return
	_bow_sprite.texture = BOW_TEXTURE


func _spawn_plain_arrow(shoot_dir:Vector2) -> void:
	var arrow:Area2D = ARROW_SCENE.instantiate() as Area2D
	if arrow == null or get_tree() == null or get_tree().current_scene == null:
		return
	var world:Node = get_tree().current_scene
	world.add_child(arrow,true)
	# 从弓的前端/箭头位置发射。V35 只用了 bow_orbit_radius，实际上是弓 Sprite
	# 的中心，所以箭看起来会从弓身中间冒出来。
	if _bow_muzzle != null and is_instance_valid(_bow_muzzle):
		arrow.global_position = _bow_muzzle.global_position
	else:
		arrow.global_position = global_position + shoot_dir * (bow_orbit_radius + bow_arrow_release_offset)
	if arrow.has_method("configure_plain"):
		arrow.call(
			"configure_plain",
			self,
			Team,
			shoot_dir,
			maxf(arrow_speed,1.0),
			maxf(arrow_damage,0.0),
			maxf(arrow_knockback_distance,0.0),
			maxf(arrow_knockback_speed,1.0),
			maxf(wall_arrow_lifetime,0.25)
		)


func _play_bow_sfx() -> void:
	if SHOOT_SFX == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "弓箭盔甲架_射箭_%d" % get_instance_id()
	player.stream = SHOOT_SFX
	player.volume_db = 2.0
	player.pitch_scale = randf_range(0.98,1.02)
	player.max_distance = 1450.0
	player.attenuation = 0.72
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	if _bow_muzzle != null and is_instance_valid(_bow_muzzle):
		player.global_position = _bow_muzzle.global_position
	else:
		player.global_position = global_position + _bow_aim_direction * (bow_orbit_radius + bow_arrow_release_offset)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
