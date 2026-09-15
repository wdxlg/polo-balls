extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const BULLET_SCENE:PackedScene = preload("res://scenes/shooter/子弹.tscn")
const KING_GUARD_TEXTURE:Texture2D = preload("res://Images/characters/人物/国王/国王守卫.png")
const KING_GENERAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/国王/国王将军.png")
const GANG_NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮小弟_普通状态.png")
const GANG_GUN_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮小弟_持枪状态.png")
const GANG_FLEE_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮小弟_跑路状态.png")
const GANG_GUN_SHOOT_TEXTURE:Texture2D = preload("res://Images/characters/人物/黑帮老大/黑帮小弟_开枪状态.png")
const GANG_FLEE_SFX:AudioStream = preload("res://audio/characters/黑帮老大/跑路了兄弟.mp3")
const VAN_KNIFE_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/持刀小混混.png")
const VAN_BATON_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/铁棍小混混.png")
const VAN_FIST_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/拳头小混混.png")
const VAN_KNIFE_WEAPON_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/匕首.png")
const VAN_BATON_WEAPON_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/铁棍.png")
const VAN_FIST_WEAPON_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/拳头.png")
const VAN_KNIFE_SWING_SFX:AudioStream = preload("res://audio/characters/面包车/匕首刺.mp3")
const VAN_KNIFE_HIT_SFX:AudioStream = preload("res://audio/characters/面包车/匕首命中.mp3")
const VAN_BATON_SWING_SFX:AudioStream = preload("res://audio/characters/面包车/铁棍挥舞.mp3")
const VAN_BATON_HIT_SFX:AudioStream = preload("res://audio/characters/面包车/铁棍打人.mp3")
const VAN_BATON_WALL_SFX:AudioStream = preload("res://audio/characters/面包车/铁棍打墙.mp3")
const VAN_FIST_SWING_SFX:AudioStream = preload("res://audio/characters/面包车/拳头挥舞.mp3")
const VAN_FIST_HIT_SFX:AudioStream = preload("res://audio/characters/面包车/拳头命中.mp3")
const VAN_KNIFE_BLEED_SCRIPT:Script = preload("res://scripts/status/面包车_匕首流血.gd")
const VAN_KNIFE_BLEED_NODE_NAME:StringName = &"VanKnifeBleedStatus"

enum Kind {
	KING_GUARD,
	KING_GENERAL,
	GANG_NORMAL,
	GANG_ENHANCED,
	GANG_GUN,
	KUNGFU,
	VAN_KNIFE,
	VAN_BATON,
	VAN_FIST,
	NC_RIFLE,
	NC_TANK,
}

@export var kind:int = Kind.KING_GUARD
@export var standalone_selection:bool = false
@export var attack_range:float = 42.0
@export var ranged_range:float = 420.0
@export var lifetime_seconds:float = 0.0
@export var bleed_action_damage_multiplier:float = 0.0714286
@export var bleed_move_damage_multiplier:float = 0.0214286
@export var bleed_duration:float = 6.0
@export var general_execute_chance:float = 0.05
@export_range(80.0,360.0,5.0) var gang_flee_speed:float = 190.0
@export_range(100.0,1000.0,10.0) var gang_bullet_speed:float = 430.0
@export_range(0.05,0.8,0.05) var gang_shoot_pose_duration:float = 0.25
@export_range(0.1,1.0,0.05) var spawn_health_multiplier:float = 1.0

var _attack_elapsed:float = 0.0
var _life_elapsed:float = 0.0
var _next_damage_melee_reduction:bool = false
var _ammo:int = 0
var _reload_remaining:float = 0.0
var _fleeing:bool = false
var _flee_target:Vector2 = Vector2.ZERO
var _money_pending:bool = false
var _gun_pose_token:int = 0
var _van_weapon_attacking:bool = false
var _van_weapon_attack_token:int = 0

static var _van_weapon_geometry_cache:Dictionary = {}

enum VanAudioCue {
	KNIFE_SWING,
	KNIFE_HIT,
	BATON_SWING,
	BATON_HIT,
	BATON_WALL,
	FIST_SWING,
	FIST_HIT,
}

func configure(new_kind:int) -> void:
	if kind == new_kind:
		return
	var old_ratio:float = 1.0
	if is_inside_tree():
		old_ratio = float(health) / maxf(float(Max_health),1.0)
	kind = new_kind
	_apply_kind_stats()
	_apply_standalone_selection_overrides()
	_apply_spawn_health_multiplier()
	_refresh_master_attack_multiplier()
	if is_inside_tree():
		_sync_kind_defaults()
		_apply_kind_visual()
		health = maxi(1,int(round(float(Max_health) * old_ratio)))

func _enter_tree() -> void:
	_apply_kind_stats()
	_apply_standalone_selection_overrides()
	_apply_spawn_health_multiplier()
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null:
		fitter.set("only_normal_characters",false)
	_apply_kind_visual_early()

func _ready() -> void:
	Type = Ball_Type.Ball
	Has_Collision_Damage = (kind == Kind.GANG_NORMAL)
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	_apply_kind_stats()
	_apply_standalone_selection_overrides()
	_apply_spawn_health_multiplier()
	_refresh_master_attack_multiplier()
	super._ready()
	_apply_kind_visual()
	_sync_kind_defaults()
	health = Max_health
	if kind == Kind.NC_RIFLE:
		add_to_group("SubmissionNCUnit")
		_ammo = 25
	elif kind == Kind.NC_TANK:
		_ammo = 6
	if self_hitbox != null:
		# 普通黑帮小弟必须使用 ball.gd 的标准身体碰撞伤害，因此保留 Hitbox 监听。
		self_hitbox.monitoring = Has_Collision_Damage

func _texture_for_kind() -> Texture2D:
	match kind:
		Kind.KING_GUARD:
			return KING_GUARD_TEXTURE
		Kind.KING_GENERAL:
			return KING_GENERAL_TEXTURE
		Kind.GANG_NORMAL, Kind.GANG_ENHANCED, Kind.KUNGFU:
			return GANG_NORMAL_TEXTURE
		Kind.GANG_GUN:
			return GANG_GUN_TEXTURE
		Kind.VAN_KNIFE:
			return VAN_KNIFE_TEXTURE
		Kind.VAN_BATON:
			return VAN_BATON_TEXTURE
		Kind.VAN_FIST:
			return VAN_FIST_TEXTURE
	return null

func _set_sprite_texture(texture:Texture2D) -> void:
	if texture == null:
		return
	var sprite:Sprite2D = get_node_or_null("Graphics/Image") as Sprite2D
	if sprite == null:
		return
	sprite.texture = texture
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		fitter.call_deferred("apply_visual_fit_only")

func _apply_kind_visual_early() -> void:
	var texture:Texture2D = _texture_for_kind()
	if texture == null:
		return
	var sprite:Sprite2D = get_node_or_null("Graphics/Image") as Sprite2D
	if sprite != null:
		sprite.texture = texture

func _apply_kind_visual() -> void:
	_set_sprite_texture(_texture_for_kind())

func _apply_kind_stats() -> void:
	attack_range = 42.0
	ranged_range = 420.0
	lifetime_seconds = 0.0
	match kind:
		Kind.KING_GUARD:
			Max_health = 70; Damage = 18; Speed = 128.0; Attack_Cooling = 1.4; attack_range = 40.0
		Kind.KING_GENERAL:
			Max_health = 240; Damage = 44; Speed = 102.0; Attack_Cooling = 1.7; attack_range = 46.0
		Kind.GANG_NORMAL:
			Max_health = 100; Damage = 15; Speed = 122.0; Attack_Cooling = 1.0; attack_range = 45.0; lifetime_seconds = 10.0
		Kind.GANG_ENHANCED:
			# 旧版本兼容种类；黑帮老大新逻辑不会再生成这种小弟。
			Max_health = 100; Damage = 15; Speed = 122.0; Attack_Cooling = 1.0; attack_range = 45.0; lifetime_seconds = 0.0
		Kind.GANG_GUN:
			Max_health = 200; Damage = 30; Speed = 112.0; Attack_Cooling = 1.15; ranged_range = 470.0; lifetime_seconds = 0.0
		Kind.KUNGFU:
			Max_health = 700; Damage = 70; Speed = 122.0; Attack_Cooling = 5.0; attack_range = 48.0; lifetime_seconds = 0.0
		Kind.VAN_KNIFE:
			# 削弱后：中等攻速 / 中等偏低伤害；判定严格跟随 0.8 倍后的匕首图片。
			Max_health = 100; Damage = 28; Speed = 118.0; Attack_Cooling = 1.70; attack_range = 46.4; lifetime_seconds = 0.0
		Kind.VAN_BATON:
			# 削弱后：慢攻速 / 较高伤害，并附带中等偏小击退。
			Max_health = 140; Damage = 48; Speed = 105.0; Attack_Cooling = 3.20; attack_range = 52.8; lifetime_seconds = 0.0
		Kind.VAN_FIST:
			# 削弱后：快攻速 / 低伤害，并附带很小的击退。
			Max_health = 160; Damage = 12; Speed = 128.0; Attack_Cooling = 0.78; attack_range = 41.6; lifetime_seconds = 0.0
		Kind.NC_RIFLE:
			Max_health = 225; Damage = 3; Speed = 104.0; Attack_Cooling = 0.22; ranged_range = 500.0; lifetime_seconds = 120.0
		Kind.NC_TANK:
			Max_health = 1000; Damage = 40; Speed = 64.0; Attack_Cooling = 1.0; ranged_range = 560.0; lifetime_seconds = 0.0

func _apply_standalone_selection_overrides() -> void:
	# V346：角色选择页里的“小弟”是独立人物，不依赖原召唤主人寿命。
	if not standalone_selection:
		return
	lifetime_seconds = 0.0
	Master = null
	Master_name = ""
	Type_Tags = PackedStringArray(["小弟","独立人物"])


func _apply_spawn_health_multiplier() -> void:
	if is_equal_approx(spawn_health_multiplier,1.0):
		return
	Max_health = maxi(1,int(round(float(Max_health) * clampf(spawn_health_multiplier,0.1,1.0))))


func _kind_master_damage_multiplier() -> float:
	match kind:
		Kind.KING_GUARD:
			return 1.0
		Kind.KING_GENERAL:
			return 2.4444444
		Kind.GANG_NORMAL, Kind.GANG_ENHANCED:
			return 1.0
		Kind.GANG_GUN:
			return 2.0
		Kind.VAN_KNIFE:
			return 2.3333333
		Kind.VAN_BATON:
			return 4.0
		Kind.VAN_FIST:
			return 1.0
		Kind.NC_RIFLE:
			return 1.0
		Kind.NC_TANK:
			return 13.3333333
	return 1.0

func _refresh_master_attack_multiplier() -> void:
	if inherit_master_attack_power:
		master_attack_damage_multiplier = _kind_master_damage_multiplier()

func _sync_kind_defaults() -> void:
	if default_properties == null:
		return
	default_properties["Max_health"] = Max_health
	default_properties["Damage"] = Damage
	default_properties["Speed"] = Speed
	default_properties["Attack_Cooling"] = Attack_Cooling
	default_properties["Skill_Cooling"] = Skill_Cooling
	default_properties["Health_Restore"] = Health_Restore
	default_properties["Damage_reduction"] = Damage_reduction

func set_persistent_combat_stats(new_damage:float,new_attack_cooling:float) -> void:
	Damage = int(round(new_damage))
	Attack_Cooling = maxf(new_attack_cooling,0.01)
	if default_properties != null:
		default_properties["Attack_Cooling"] = Attack_Cooling

func _physics_process(delta:float) -> void:
	if not is_multiplayer_authority():
		return
	if health <= 0:
		if not is_queued_for_deletion():
			Die()
		return

	_attack_elapsed += delta
	_life_elapsed += delta

	# 面包车死亡后，车上放下来的三种混混全部停手跑路。Master 仍存在但 health=0
	# 和 Master 已经释放两种情况都处理，避免依赖节点释放时序。
	if _is_van_minion_kind() and not standalone_selection:
		if _fleeing:
			_update_gang_flee()
			return
		if Master == null or not is_instance_valid(Master) or Master.health <= 0:
			begin_van_flee_from_master_death()
			return

	if kind == Kind.GANG_NORMAL and not standalone_selection:
		if _fleeing:
			_update_gang_flee()
			return
		if _should_gang_normal_flee():
			begin_gang_flee()
			return
		# 普通小弟只使用标准身体碰撞伤害，不再额外执行一次脚本近战攻击。
		return

	if _reload_remaining > 0.0:
		_reload_remaining = maxf(_reload_remaining - delta,0.0)
		if _reload_remaining <= 0.0:
			_ammo = 25 if kind == Kind.NC_RIFLE else 6
		return
	if lifetime_seconds > 0.0 and _life_elapsed >= lifetime_seconds:
		_flee_or_expire()
		return
	if _attack_elapsed < Attack_Cooling or _van_weapon_attacking:
		return
	var target:ball = TOOLS.nearest_enemy(self,ranged_range if _is_ranged() else attack_range)
	if target == null:
		return
	_attack_elapsed = 0.0
	_do_attack(target)


func _is_van_minion_kind() -> bool:
	return kind == Kind.VAN_KNIFE or kind == Kind.VAN_BATON or kind == Kind.VAN_FIST


func begin_van_flee_from_master_death() -> void:
	if not _is_van_minion_kind() or _fleeing or health <= 0:
		return
	_fleeing = true
	_money_pending = false
	_van_weapon_attack_token += 1
	_van_weapon_attacking = false
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Speed = gang_flee_speed
	if default_properties != null:
		default_properties["Speed"] = Speed
	if self_hitbox != null:
		self_hitbox.monitoring = false
	# 逃跑阶段不再和人物/墙发生实体碰撞，也允许越过地图安全边界后删除。
	collision_layer = 0
	collision_mask = 0
	set_meta(&"submission_allow_map_escape",true)
	_pick_nearest_map_exit()
	_play_flee_audio_if_available()

func _should_gang_normal_flee() -> bool:
	# 普通小弟自己的生命降到一半时跑路；这不是老大的半血阶段。
	if health <= int(round(float(Max_health) * 0.5)):
		return true
	if _life_elapsed >= 10.0:
		return true
	if Master == null or not is_instance_valid(Master):
		return true
	return Master.health <= 0

func can_receive_gang_money() -> bool:
	return kind == Kind.GANG_NORMAL and health > 0 and not _fleeing

func is_gang_normal_available_for_money() -> bool:
	return can_receive_gang_money() and not _money_pending

func set_money_pending(value:bool) -> void:
	_money_pending = value

func begin_gang_flee() -> void:
	if kind != Kind.GANG_NORMAL or _fleeing or health <= 0:
		return
	_fleeing = true
	_money_pending = false
	Has_Collision_Damage = false
	Speed = gang_flee_speed
	if default_properties != null:
		default_properties["Speed"] = Speed
	if self_hitbox != null:
		self_hitbox.monitoring = false
	# 跑路时完全退出实体碰撞，并显式告诉 World 不要执行“越界救回”。
	# 之前只清 collision_mask，虽然能穿过安全墙，但 World 的地图保护仍会
	# 在小弟刚越界时把它拉回去，表现成反复撞墙。
	collision_layer = 0
	collision_mask = 0
	set_meta(&"submission_allow_map_escape",true)
	_set_sprite_texture(GANG_FLEE_TEXTURE)
	_pick_nearest_map_exit()
	_play_flee_audio_if_available()

func _pick_nearest_map_exit() -> void:
	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_flee_target = global_position + Vector2.RIGHT * 500.0
		return
	var p:Vector2 = global_position
	var distances := PackedFloat32Array([
		absf(p.x - rect.position.x),
		absf(rect.end.x - p.x),
		absf(p.y - rect.position.y),
		absf(rect.end.y - p.y),
	])
	var best_index:int = 0
	var best_value:float = distances[0]
	for i:int in range(1,distances.size()):
		if distances[i] < best_value:
			best_index = i
			best_value = distances[i]
	match best_index:
		0:
			_flee_target = Vector2(rect.position.x - 80.0,p.y)
		1:
			_flee_target = Vector2(rect.end.x + 80.0,p.y)
		2:
			_flee_target = Vector2(p.x,rect.position.y - 80.0)
		_:
			_flee_target = Vector2(p.x,rect.end.y + 80.0)
	direction = (_flee_target - global_position).normalized()

func _update_gang_flee() -> void:
	var to_exit:Vector2 = _flee_target - global_position
	if to_exit.length_squared() > 0.001:
		direction = to_exit.normalized()
	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		if not rect.grow(18.0).has_point(global_position):
			queue_free()
	elif global_position.distance_to(_flee_target) <= 12.0:
		queue_free()

func _play_flee_audio_if_available() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_gang_flee_sfx.rpc(global_position)
	else:
		_rpc_play_gang_flee_sfx(global_position)


@rpc("authority","call_local","unreliable")
func _rpc_play_gang_flee_sfx(position_value:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null or GANG_FLEE_SFX == null:
		return
	# 半血时可能多个普通小弟在同一帧同时跑路，避免同一段人声叠四层。
	var now_msec:int = Time.get_ticks_msec()
	var last_msec:int = int(world.get_meta("_gang_flee_sfx_last_msec",-100000))
	if now_msec - last_msec < 650:
		return
	world.set_meta("_gang_flee_sfx_last_msec",now_msec)
	var player := AudioStreamPlayer2D.new()
	player.stream = GANG_FLEE_SFX
	player.volume_db = -4.0
	player.max_distance = 1500.0
	player.attenuation = 0.45
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()

func _is_ranged() -> bool:
	return kind == Kind.GANG_GUN or kind == Kind.NC_RIFLE or kind == Kind.NC_TANK

func _do_attack(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not TOOLS.is_enemy(self,target):
		return
	if kind == Kind.GANG_GUN:
		_fire_gang_bullet(target)
		return
	if _is_ranged():
		if kind == Kind.NC_RIFLE or kind == Kind.NC_TANK:
			if _ammo <= 0:
				_reload_remaining = 5.0 if kind == Kind.NC_RIFLE else 10.0
				return
			_ammo -= 1
		_show_tracer(target.global_position)
		target.receive_positional_damage(attack_damage(),target.global_position,false,self)
		if (kind == Kind.NC_RIFLE or kind == Kind.NC_TANK) and _ammo <= 0:
			_reload_remaining = 5.0 if kind == Kind.NC_RIFLE else 10.0
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return
	if kind == Kind.VAN_KNIFE or kind == Kind.VAN_BATON or kind == Kind.VAN_FIST:
		_start_van_weapon_attack(target)
		return
	if kind == Kind.KING_GENERAL and randf() < general_execute_chance and target.health <= int(round(target.Max_health * 0.5)):
		target.receive_spatial_raw_health_damage(float(target.health),global_position)
		return
	target.receive_positional_damage(attack_damage(),target.global_position,false,self)

func _fire_gang_bullet(target:ball) -> void:
	var world:Node = get_tree().current_scene
	if world == null or target == null or not is_instance_valid(target):
		return
	_show_gang_gun_shoot_pose()
	var projectile:ball = BULLET_SCENE.instantiate() as ball
	if projectile == null:
		return
	var dir:Vector2 = combat_target_position(target) - global_position
	if dir.length_squared() <= 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	projectile.set_collision_layer_value(2,false)
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Damage = maxi(int(round(attack_damage())),1)
	projectile.Speed = gang_bullet_speed
	projectile.global_position = global_position + dir * 22.0
	projectile.global_rotation = projectile.Default_Rotation + dir.angle()
	projectile.direction = dir
	projectile.name = Game.return_random_name(projectile)
	world.add_child(projectile,true)
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("G18单发",{"volume":-3.0},true,true)
	else:
		Audios.play_sfx("G18单发",{"volume":-3.0},true,true)

func _show_gang_gun_shoot_pose() -> void:
	_gun_pose_token += 1
	var token:int = _gun_pose_token
	_set_sprite_texture(GANG_GUN_SHOOT_TEXTURE)
	_restore_gang_gun_pose(token)

func _restore_gang_gun_pose(token:int) -> void:
	await get_tree().create_timer(gang_shoot_pose_duration).timeout
	if not is_instance_valid(self) or health <= 0 or token != _gun_pose_token:
		return
	if kind == Kind.GANG_GUN:
		_set_sprite_texture(GANG_GUN_TEXTURE)

func _show_tracer(end_point:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var line := Line2D.new()
	line.width = 1.6 if kind != Kind.NC_TANK else 2.8
	line.default_color = Color(1.0,0.92,0.55,0.9)
	line.points = PackedVector2Array([global_position,end_point])
	line.z_index = 7
	world.add_child(line)
	var tween:Tween = line.create_tween()
	tween.tween_property(line,"modulate:a",0.0,0.10)
	tween.finished.connect(line.queue_free)

func _apply_van_knife_bleed(target:ball) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	var existing:Node = target.get_node_or_null(NodePath(str(VAN_KNIFE_BLEED_NODE_NAME)))
	if existing != null and is_instance_valid(existing):
		if existing.has_method("refresh"):
			existing.call("refresh",self,attack_damage(bleed_action_damage_multiplier),attack_damage(bleed_move_damage_multiplier))
		return
	var status:Node = VAN_KNIFE_BLEED_SCRIPT.new()
	status.name = VAN_KNIFE_BLEED_NODE_NAME
	target.add_child(status)
	status.call("setup",target,self,bleed_duration,attack_damage(bleed_action_damage_multiplier),attack_damage(bleed_move_damage_multiplier))

# -----------------------------------------------------------------------------
# 面包车三种混混：独立武器动画 + 与 PNG alpha 轮廓一致的攻击区域。
# 武器 Area2D 放在世界坐标中，不继承 ball 根节点缩放；每个物理帧按实际
# 武器位置读取重叠，因此“看见武器扫到哪里，伤害区域就在哪里”。
# -----------------------------------------------------------------------------
func _start_van_weapon_attack(target:ball) -> void:
	if _van_weapon_attacking or target == null or not is_instance_valid(target):
		return
	_van_weapon_attacking = true
	_van_weapon_attack_token += 1
	_run_van_weapon_attack(target,_van_weapon_attack_token)

func _run_van_weapon_attack(target:ball,token:int) -> void:
	match kind:
		Kind.VAN_KNIFE:
			await _animate_van_knife_attack(target,token)
		Kind.VAN_BATON:
			await _animate_van_baton_attack(target,token)
		Kind.VAN_FIST:
			await _animate_van_fist_attack(target,token)
	if is_instance_valid(self) and token == _van_weapon_attack_token:
		_van_weapon_attacking = false

func _animate_van_knife_attack(target:ball,token:int) -> void:
	if target == null or not is_instance_valid(target):
		return
	# 匕首只能向左/右刺；纵向偏差必须真的进入刀刃区域才会命中。
	var side:float = 1.0 if target.global_position.x >= global_position.x else -1.0
	var attack_dir := Vector2(side,0.0)
	var weapon:Area2D = _create_van_weapon_area(VAN_KNIFE_WEAPON_TEXTURE,deg_to_rad(-42.7),38.4)
	if weapon == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		weapon.queue_free()
		return
	world.add_child(weapon)
	weapon.global_rotation = 0.0 if side > 0.0 else PI
	_play_van_audio(VanAudioCue.KNIFE_SWING,global_position)
	var hit_ids:Dictionary = {}
	var steps:int = 18
	for i:int in range(steps):
		if not _van_attack_still_valid(token):
			break
		var t:float = float(i) / float(maxi(steps - 1,1))
		var smooth_t:float = t * t * (3.0 - 2.0 * t)
		weapon.global_position = global_position + attack_dir * lerpf(3.2,16.0,smooth_t) + Vector2(0.0,-1.2)
		weapon.modulate.a = lerpf(1.0,0.0,t)
		await get_tree().physics_frame
		_damage_van_weapon_overlaps(weapon,hit_ids)
	weapon.queue_free()

func _animate_van_baton_attack(target:ball,token:int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var attack_dir:Vector2 = target.global_position - global_position
	if attack_dir.length_squared() <= 0.0001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()
	var weapon:Area2D = _create_van_weapon_area(VAN_BATON_WEAPON_TEXTURE,deg_to_rad(-44.0),46.4)
	if weapon == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		weapon.queue_free()
		return
	world.add_child(weapon)
	_play_van_audio(VanAudioCue.BATON_SWING,global_position)
	var hit_ids:Dictionary = {}
	var wall_sound_played:bool = false
	var target_angle:float = attack_dir.angle()
	var start_angle:float = target_angle - deg_to_rad(58.0)
	var end_angle:float = target_angle + deg_to_rad(62.0)
	var steps:int = 25
	for i:int in range(steps):
		if not _van_attack_still_valid(token):
			break
		var t:float = float(i) / float(maxi(steps - 1,1))
		var smooth_t:float = t * t * (3.0 - 2.0 * t)
		weapon.global_position = global_position + attack_dir * 4.0
		weapon.global_rotation = lerp_angle(start_angle,end_angle,smooth_t)
		await get_tree().physics_frame
		_damage_van_weapon_overlaps(weapon,hit_ids)
		if not wall_sound_played and _van_weapon_overlaps_wall(weapon):
			wall_sound_played = true
			_play_van_audio(VanAudioCue.BATON_WALL,weapon.global_position)
	weapon.queue_free()

func _animate_van_fist_attack(target:ball,token:int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var attack_dir:Vector2 = target.global_position - global_position
	if attack_dir.length_squared() <= 0.0001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()
	var weapon:Area2D = _create_van_weapon_area(VAN_FIST_WEAPON_TEXTURE,deg_to_rad(-90.0),30.4)
	if weapon == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		weapon.queue_free()
		return
	world.add_child(weapon)
	weapon.global_rotation = attack_dir.angle()
	_play_van_audio(VanAudioCue.FIST_SWING,global_position)
	var hit_ids:Dictionary = {}
	var steps:int = 12
	for i:int in range(steps):
		if not _van_attack_still_valid(token):
			break
		var t:float = float(i) / float(maxi(steps - 1,1))
		# 一拳伸出再快速收回；碰撞区域始终就是拳头图片本身。
		var extension:float = sin(t * PI) * 12.8
		weapon.global_position = global_position + attack_dir * (3.2 + extension)
		weapon.global_rotation = attack_dir.angle()
		await get_tree().physics_frame
		_damage_van_weapon_overlaps(weapon,hit_ids)
	weapon.queue_free()

func _van_attack_still_valid(token:int) -> bool:
	return (
		is_instance_valid(self)
		and not is_queued_for_deletion()
		and health > 0
		and token == _van_weapon_attack_token
	)

func _create_van_weapon_area(texture:Texture2D,source_tip_angle:float,target_length:float) -> Area2D:
	if texture == null:
		return null
	var geometry:Dictionary = _van_weapon_geometry(texture,source_tip_angle,target_length)
	if geometry.is_empty():
		return null
	var area := Area2D.new()
	area.name = "VanWeaponAttack"
	area.collision_layer = 0
	area.collision_mask = 0xFFFFFFFF
	area.monitoring = true
	area.monitorable = false
	area.z_index = 25

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.position = geometry.get("sprite_position",Vector2.ZERO)
	sprite.rotation = float(geometry.get("sprite_rotation",0.0))
	var sprite_scale:float = float(geometry.get("sprite_scale",1.0))
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.z_index = 1
	area.add_child(sprite)

	var polygons:Array = geometry.get("polygons",[])
	for raw_polygon:Variant in polygons:
		if not (raw_polygon is PackedVector2Array):
			continue
		var polygon:PackedVector2Array = PackedVector2Array(raw_polygon)
		if polygon.size() < 3:
			continue
		var collision := CollisionPolygon2D.new()
		collision.polygon = polygon
		area.add_child(collision)
	return area

func _van_weapon_geometry(texture:Texture2D,source_tip_angle:float,target_length:float) -> Dictionary:
	var key:String = "%s|%.4f|%.2f" % [texture.resource_path,source_tip_angle,target_length]
	if _van_weapon_geometry_cache.has(key):
		return _van_weapon_geometry_cache[key]
	var image:Image = texture.get_image()
	if image == null or image.is_empty():
		return {}
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image,0.08)
	var source_polygons:Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO,image.get_size()),
		3.0
	)
	if source_polygons.is_empty():
		return {}

	# 原素材中的“手柄 -> 武器前端”方向校正到本地 +X；之后整个 Area2D
	# 只需旋转一次即可朝向攻击方向。
	var correction:float = -source_tip_angle
	var image_center := Vector2(image.get_width() * 0.5,image.get_height() * 0.5)
	var min_x:float = INF
	var max_x:float = -INF
	var min_y:float = INF
	var max_y:float = -INF
	for polygon:PackedVector2Array in source_polygons:
		for p:Vector2 in polygon:
			var aligned:Vector2 = (p - image_center).rotated(correction)
			min_x = minf(min_x,aligned.x)
			max_x = maxf(max_x,aligned.x)
			min_y = minf(min_y,aligned.y)
			max_y = maxf(max_y,aligned.y)
	var raw_length:float = maxf(max_x - min_x,1.0)
	var uniform_scale:float = target_length / raw_length
	var shift := Vector2(-min_x * uniform_scale,-(min_y + max_y) * 0.5 * uniform_scale)
	var final_polygons:Array[PackedVector2Array] = []
	for polygon:PackedVector2Array in source_polygons:
		var transformed := PackedVector2Array()
		transformed.resize(polygon.size())
		for i:int in range(polygon.size()):
			transformed[i] = (polygon[i] - image_center).rotated(correction) * uniform_scale + shift
		final_polygons.append(transformed)
	var result:Dictionary = {
		"polygons":final_polygons,
		"sprite_position":shift,
		"sprite_rotation":correction,
		"sprite_scale":uniform_scale,
	}
	_van_weapon_geometry_cache[key] = result
	return result

func _damage_van_weapon_overlaps(weapon:Area2D,hit_ids:Dictionary) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	for area:Area2D in weapon.get_overlapping_areas():
		var target:ball = _van_collision_owner_ball(area)
		_try_damage_van_weapon_target(target,hit_ids)
	for body:Node2D in weapon.get_overlapping_bodies():
		var target:ball = _van_collision_owner_ball(body)
		_try_damage_van_weapon_target(target,hit_ids)

func _van_weapon_overlaps_wall(weapon:Area2D) -> bool:
	if weapon == null or not is_instance_valid(weapon):
		return false
	for body:Node2D in weapon.get_overlapping_bodies():
		if _van_node_is_wall_collision(body):
			return true
	for area:Area2D in weapon.get_overlapping_areas():
		if _van_node_is_wall_collision(area):
			return true
	return false

func _van_node_is_wall_collision(node:Node) -> bool:
	if node == null or _van_collision_owner_ball(node) != null:
		return false
	var collision_object:CollisionObject2D = node as CollisionObject2D
	if collision_object == null:
		return false
	# 项目地图/安全墙使用 physics layer 1；武器碰到这一层时只播一次铁棒撞墙声。
	return collision_object.get_collision_layer_value(1)

func _van_collision_owner_ball(node:Node) -> ball:
	var current:Node = node
	for _i:int in range(8):
		if current == null:
			break
		if current is ball:
			return current as ball
		current = current.get_parent()
	return null

func _try_damage_van_weapon_target(target:ball,hit_ids:Dictionary) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	if not TOOLS.is_enemy(self,target):
		return
	var target_id:int = target.get_instance_id()
	if hit_ids.has(target_id):
		return
	# 一次挥击对同一目标只结算一次；是否受伤由目标自己的格挡/特殊机制决定。
	hit_ids[target_id] = true
	var impact_position:Vector2 = target.global_position
	var outgoing_damage:float = attack_damage()
	var before_health:float = float(target.health)
	var dealt:bool = target.receive_positional_damage(outgoing_damage,impact_position,false,self)
	if not dealt:
		return
	var health_loss:float = maxf(before_health - float(target.health),0.0)
	if health_loss > 0.0 and Game.has_method("report_training_damage"):
		Game.report_training_damage(self,target,health_loss)

	match kind:
		Kind.VAN_KNIFE:
			_play_van_audio(VanAudioCue.KNIFE_HIT,impact_position)
			if health_loss > 0.0:
				_apply_van_knife_bleed(target)
		Kind.VAN_BATON:
			_play_van_audio(VanAudioCue.BATON_HIT,impact_position)
			var baton_push_dir:Vector2 = target.global_position - global_position
			if baton_push_dir.length_squared() <= 0.0001:
				baton_push_dir = Vector2.RIGHT
			target.apply_knockback(
				baton_push_dir.normalized(),
				42.0,
				460.0,
				0.0,
				0.0,
				{"source":self,"lock_control":true,"stop_on_character":true}
			)
		Kind.VAN_FIST:
			_play_van_audio(VanAudioCue.FIST_HIT,impact_position)
			var fist_push_dir:Vector2 = target.global_position - global_position
			if fist_push_dir.length_squared() <= 0.0001:
				fist_push_dir = Vector2.RIGHT
			target.apply_knockback(
				fist_push_dir.normalized(),
				14.0,
				230.0,
				0.0,
				0.0,
				{"source":self,"lock_control":true,"stop_on_character":true}
			)

func _play_van_collision_hit_audio(volume_db:float) -> void:
	if not is_multiplayer_authority():
		return
	var params:Dictionary = {"volume":volume_db}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)

func _play_van_audio(cue:int,position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_van_audio.rpc(cue,position_value)
	else:
		_rpc_play_van_audio(cue,position_value)

@rpc("authority","call_local","unreliable")
func _rpc_play_van_audio(cue:int,position_value:Vector2) -> void:
	var stream:AudioStream = null
	var volume_db:float = -2.0
	match cue:
		VanAudioCue.KNIFE_SWING:
			stream = VAN_KNIFE_SWING_SFX
			volume_db = -2.0
		VanAudioCue.KNIFE_HIT:
			stream = VAN_KNIFE_HIT_SFX
			# 这段源音频本身明显偏轻，播放端做小幅补偿，不改原文件。
			volume_db = 5.0
		VanAudioCue.BATON_SWING:
			stream = VAN_BATON_SWING_SFX
			volume_db = -4.0
		VanAudioCue.BATON_HIT:
			stream = VAN_BATON_HIT_SFX
			volume_db = 2.0
		VanAudioCue.BATON_WALL:
			stream = VAN_BATON_WALL_SFX
			volume_db = -3.0
		VanAudioCue.FIST_SWING:
			stream = VAN_FIST_SWING_SFX
			volume_db = -2.0
		VanAudioCue.FIST_HIT:
			stream = VAN_FIST_HIT_SFX
			volume_db = 0.0
	if stream == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 1350.0
	player.attenuation = 0.48
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()

func can_receive_hit_contact(source_hitbox:hitbox,_hurt:hurtbox) -> bool:
	_next_damage_melee_reduction = false
	if kind != Kind.KING_GENERAL:
		return true
	if source_hitbox == null:
		return true
	var source = source_hitbox.get_parent()
	if source is ball and TOOLS.source_is_melee(source as ball):
		_next_damage_melee_reduction = true
	return true

func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _next_damage_melee_reduction:
		damage *= 0.75
	_next_damage_melee_reduction = false
	super(damage,ignore_block)

func upgrade_to(new_kind:int) -> void:
	var old_ratio:float = float(health) / maxf(float(Max_health),1.0)
	kind = new_kind
	_fleeing = false
	_money_pending = false
	_apply_kind_stats()
	_refresh_master_attack_multiplier()
	Has_Collision_Damage = (kind == Kind.GANG_NORMAL)
	_sync_kind_defaults()
	_apply_kind_visual()
	if self_hitbox != null:
		self_hitbox.monitoring = Has_Collision_Damage
	health = maxi(1,int(round(float(Max_health) * old_ratio)))

func _flee_or_expire() -> void:
	if kind == Kind.GANG_NORMAL:
		begin_gang_flee()
		return
	queue_free()

func Die() -> void:
	super()
	queue_free()
