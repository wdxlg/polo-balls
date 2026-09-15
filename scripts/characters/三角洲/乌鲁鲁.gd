extends ball

# 乌鲁鲁（Delta Force / 三角洲行动）
# 本实现接入用户提供的角色、发射器、巡飞弹、子炸弹和燃烧弹图片。
# 巡飞弹命中后散出 4 枚炸弹；燃烧弹落地后生成持续火焰区域。
const LOITER_MISSILE_SCRIPT:Script = preload("res://scripts/effects/乌鲁鲁巡飞弹.gd")
const FIRE_BOMB_SCRIPT:Script = preload("res://scripts/effects/乌鲁鲁火焰弹.gd")
const LAUNCHER_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/大炮.png")
const EXPLOSION_SFX:AudioStream = preload("res://audio/characters/炸弹客/爆炸.mp3")
const BURN_TICK_SFX:AudioStream = preload("res://audio/status/debuff/烫伤.wav")

@export_category("乌鲁鲁 - 巡飞弹")
@export_range(2.0,40.0,0.1) var missile_cooldown:float = 12.5
@export_range(0.0,30.0,0.1) var missile_first_delay:float = 5.4
@export_range(120.0,1200.0,5.0) var missile_speed:float = 520.0
@export_range(20.0,360.0,1.0) var missile_turn_speed_deg:float = 120.0
@export_range(0.8,10.0,0.1) var missile_lifetime:float = 5.4
@export_range(3.0,40.0,0.5) var missile_hit_radius:float = 12.0
@export_range(20.0,220.0,1.0) var missile_impact_radius:float = 76.0
@export_range(0.0,30.0,0.1) var missile_impact_damage_multiplier:float = 7.6
@export_range(0.2,3.0,0.05) var missile_bomb_fuse:float = 0.82
@export_range(10.0,160.0,1.0) var missile_bomb_radius:float = 46.0
@export_range(0.0,15.0,0.1) var missile_bomb_damage_multiplier:float = 3.1

@export_category("乌鲁鲁 - 复合型燃烧弹")
@export_range(1.0,30.0,0.1) var fire_cooldown:float = 7.6
@export_range(0.0,20.0,0.1) var fire_first_delay:float = 2.2
@export_range(0.15,2.0,0.01) var fire_throw_duration:float = 0.64
@export_range(8.0,180.0,1.0) var fire_arc_height:float = 74.0
@export_range(10.0,100.0,1.0) var fire_impact_radius:float = 36.0
@export_range(0.0,12.0,0.1) var fire_impact_damage_multiplier:float = 2.2
@export_range(20.0,220.0,1.0) var fire_area_radius:float = 82.0
@export_range(0.5,12.0,0.1) var fire_area_duration:float = 5.6
@export_range(0.1,2.0,0.05) var fire_tick_interval:float = 0.65
@export_range(0.0,8.0,0.05) var fire_tick_damage_multiplier:float = 1.45
@export_range(0.2,12.0,0.1) var fire_burn_duration:float = 3.5
@export_range(0.1,2.0,0.05) var fire_burn_tick_interval:float = 0.5
@export_range(0.0,8.0,0.05) var fire_burn_tick_damage_multiplier:float = 0.55
@export_range(0.012,0.12,0.002) var fire_particle_interval:float = 0.038

@export_category("乌鲁鲁 - 发射器视觉")
@export_range(40.0,180.0,2.0) var launcher_visual_length:float = 104.0
@export var launcher_local_offset:Vector2 = Vector2(6.0,-12.0)

var _missile_cooldown_left:float = 0.0
var _fire_cooldown_left:float = 0.0
var _missile_active:bool = false
var _missile_target_ref:WeakRef = null
var _launcher_sprite:Sprite2D = null
var _special_audio_serial:int = 0


func _ready() -> void:
	Can_Attack = false
	Can_Skill = true
	Has_Collision_Damage = false
	dir_left = false
	super._ready()
	_missile_cooldown_left = maxf(missile_first_delay,0.0)
	_fire_cooldown_left = maxf(fire_first_delay,0.0)
	_setup_launcher_visual()


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority():
		_tick_uluru_skills(maxf(delta,0.0))
	_update_launcher_aim()
	super.tick_physics(state,delta)


func move(speed_value:float,delta:float):
	if _missile_active:
		# 图像制导期间角色原地操作发射器，和巡飞弹的“站桩制导”表现一致。
		velocity = Vector2.ZERO
		direction = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.move(speed_value,delta)


func controlled_skill_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or _missile_active:
		return
	var raw_target:Node = return_reusable_combat_target()
	if not raw_target is ball or not is_instance_valid(raw_target):
		return
	var target:ball = raw_target as ball
	if _missile_cooldown_left <= 0.0001:
		_start_missile(target)
	elif _fire_cooldown_left <= 0.0001:
		_start_fire_bomb(target)


func _tick_uluru_skills(delta:float) -> void:
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		_missile_active = false
		Using_Skill = false
		_hide_launcher_visual()
		return
	if not is_combat_runtime_active():
		return
	_missile_cooldown_left = maxf(_missile_cooldown_left-delta,0.0)
	_fire_cooldown_left = maxf(_fire_cooldown_left-delta,0.0)
	if is_player_controlled() or _missile_active:
		return
	var raw_target:Node = return_reusable_combat_target()
	if not raw_target is ball or not is_instance_valid(raw_target):
		return
	var target:ball = raw_target as ball
	# 巡飞弹优先；其制导期间禁止再扔燃烧弹。
	if _missile_cooldown_left <= 0.0001:
		_start_missile(target)
	elif _fire_cooldown_left <= 0.0001:
		_start_fire_bomb(target)


func _start_fire_bomb(target:ball) -> void:
	if target == null or not is_instance_valid(target) or health <= 0:
		return
	_fire_cooldown_left = maxf(fire_cooldown,0.2)
	var target_position:Vector2 = combat_target_position(target)
	var aim:Vector2 = target_position-global_position
	var start_position:Vector2 = global_position + (aim.normalized() * 20.0 if aim.length_squared() > 0.000001 else Vector2.RIGHT * 20.0) + Vector2(0.0,-10.0)
	var config:Dictionary = {
		"throw_duration":fire_throw_duration,
		"arc_height":fire_arc_height,
		"impact_radius":fire_impact_radius,
		"impact_damage_multiplier":fire_impact_damage_multiplier,
		"radius":fire_area_radius,
		"duration":fire_area_duration,
		"tick_interval":fire_tick_interval,
		"damage_multiplier":fire_tick_damage_multiplier,
		"burn_duration":fire_burn_duration,
		"burn_tick_interval":fire_burn_tick_interval,
		"burn_tick_damage_multiplier":fire_burn_tick_damage_multiplier,
		"particle_interval":fire_particle_interval,
	}
	_spawn_fire_bomb_local(start_position,target_position,config)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_fire_bomb.rpc(start_position,target_position,config)


@rpc("authority","call_remote","reliable")
func _remote_spawn_fire_bomb(start_position:Vector2,target_position:Vector2,config:Dictionary) -> void:
	_spawn_fire_bomb_local(start_position,target_position,config)


func _spawn_fire_bomb_local(start_position:Vector2,target_position:Vector2,config:Dictionary) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var projectile:Node2D = FIRE_BOMB_SCRIPT.new() as Node2D
	if projectile == null:
		return
	projectile.name = "乌鲁鲁火焰弹_%d" % Time.get_ticks_usec()
	world.add_child(projectile,true)
	projectile.call("setup",self,start_position,target_position,config)


func _start_missile(target:ball) -> void:
	if target == null or not is_instance_valid(target) or health <= 0 or _missile_active:
		return
	_missile_active = true
	_missile_target_ref = weakref(target)
	_missile_cooldown_left = maxf(missile_cooldown,0.5)
	Using_Skill = true
	Attacking = false
	velocity = Vector2.ZERO
	direction = Vector2.ZERO
	Repel = Vector2.ZERO
	var aim:Vector2 = combat_target_position(target)-global_position
	var aim_dir:Vector2 = aim.normalized() if aim.length_squared() > 0.000001 else Vector2.RIGHT
	var start_position:Vector2 = global_position + aim_dir * 30.0 + Vector2(0.0,-8.0)
	var target_path:NodePath = target.get_path()
	var config:Dictionary = {
		"speed":missile_speed,
		"turn_speed_deg":missile_turn_speed_deg,
		"lifetime":missile_lifetime,
		"hit_radius":missile_hit_radius,
		"impact_radius":missile_impact_radius,
		"impact_damage_multiplier":missile_impact_damage_multiplier,
		"bomb_fuse":missile_bomb_fuse,
		"bomb_radius":missile_bomb_radius,
		"bomb_damage_multiplier":missile_bomb_damage_multiplier,
	}
	_spawn_missile_local(target_path,start_position,config)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_missile.rpc(target_path,start_position,config)


@rpc("authority","call_remote","reliable")
func _remote_spawn_missile(target_path:NodePath,start_position:Vector2,config:Dictionary) -> void:
	_spawn_missile_local(target_path,start_position,config)


func _spawn_missile_local(target_path:NodePath,start_position:Vector2,config:Dictionary) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		_uluru_on_loiter_missile_finished()
		return
	var target_node:Node = get_tree().root.get_node_or_null(target_path)
	if not target_node is ball:
		_uluru_on_loiter_missile_finished()
		return
	_missile_target_ref = weakref(target_node as ball)
	_show_launcher_visual()
	var missile:Node2D = LOITER_MISSILE_SCRIPT.new() as Node2D
	if missile == null:
		_uluru_on_loiter_missile_finished()
		return
	missile.name = "乌鲁鲁巡飞弹_%d" % Time.get_ticks_usec()
	world.add_child(missile,true)
	missile.call("setup",self,target_node as ball,start_position,config)


func _uluru_on_loiter_missile_finished() -> void:
	_missile_target_ref = null
	_hide_launcher_visual()
	if is_multiplayer_authority():
		_missile_active = false
		Using_Skill = false
		Attacking = false
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO


func _setup_launcher_visual() -> void:
	if LAUNCHER_TEXTURE == null:
		return
	var graphics:Node = get_node_or_null("Graphics")
	if graphics == null:
		return
	_launcher_sprite = Sprite2D.new()
	_launcher_sprite.name = "乌鲁鲁大炮"
	_launcher_sprite.texture = LAUNCHER_TEXTURE
	var longest:float = maxf(LAUNCHER_TEXTURE.get_width(),LAUNCHER_TEXTURE.get_height())
	var scale_value:float = launcher_visual_length / maxf(longest,1.0)
	_launcher_sprite.scale = Vector2.ONE * scale_value
	_launcher_sprite.position = launcher_local_offset
	_launcher_sprite.z_index = 8
	_launcher_sprite.visible = false
	graphics.add_child(_launcher_sprite)


func _show_launcher_visual() -> void:
	if _launcher_sprite != null and is_instance_valid(_launcher_sprite):
		_launcher_sprite.visible = true
		_update_launcher_aim()


func _hide_launcher_visual() -> void:
	if _launcher_sprite != null and is_instance_valid(_launcher_sprite):
		_launcher_sprite.visible = false


func _update_launcher_aim() -> void:
	if _launcher_sprite == null or not is_instance_valid(_launcher_sprite) or not _launcher_sprite.visible:
		return
	var target:ball = _missile_target()
	if target == null:
		return
	var aim:Vector2 = combat_target_position(target)-global_position
	if aim.length_squared() <= 0.000001:
		return
	# 大炮原图炮口朝左，因此局部 LEFT 对齐目标方向。
	# V191：aim 是世界方向；使用全局角避免角色根节点的重力旋转叠加一次。
	_launcher_sprite.global_rotation = aim.angle() - PI


func _missile_target() -> ball:
	if _missile_target_ref == null:
		return null
	var raw:Variant = _missile_target_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null


# 复用项目已有的爆炸 / 烫伤声音，不新增音频目录。
func play_uluru_explosion_sfx(position_value:Vector2,volume_db_value:float = -2.0) -> void:
	_play_uluru_one_shot(EXPLOSION_SFX,position_value,volume_db_value,randf_range(0.96,1.05))


func play_war_burn_tick_sfx(position_value:Vector2) -> void:
	_play_uluru_one_shot(BURN_TICK_SFX,position_value,0.5,randf_range(0.97,1.04))


func _play_uluru_one_shot(stream_value:AudioStream,position_value:Vector2,volume_db_value:float,pitch_value:float) -> void:
	if stream_value == null or not is_inside_tree():
		return
	var player:=AudioStreamPlayer2D.new()
	_special_audio_serial += 1
	player.name = "UluruSpecialSFX_%d" % _special_audio_serial
	player.top_level = true
	player.stream = stream_value
	player.volume_db = volume_db_value
	player.pitch_scale = maxf(pitch_value,0.05)
	player.max_distance = 1300.0
	player.attenuation = 0.78
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player,true)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
