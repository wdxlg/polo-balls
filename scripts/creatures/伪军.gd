extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const BULLET_SCENE:PackedScene = preload("res://scenes/shooter/军火商_子弹.tscn")
# 头子死亡时复用黑帮老大普通小弟的跑路语音。
const GANG_FLEE_SFX:AudioStream = preload("res://audio/characters/黑帮老大/跑路了兄弟.mp3")

@export var standalone_selection:bool = false
@export_category("伪军 - 视觉")
@export var normal_texture:Texture2D
@export var firing_texture:Texture2D
@export_range(80.0,320.0,5.0) var visual_local_max_size:float = 205.0

@export_category("伪军 - 固定弹着点")
@export_range(80.0,900.0,10.0) var attack_range:float = 430.0
@export_range(1,12,1) var shots_per_burst:int = 5
@export_range(0.5,20.0,0.5) var shot_rate_hz:float = 5.0
@export_range(0.1,8.0,0.1) var burst_cooldown:float = 2.0
@export_range(100.0,1600.0,20.0) var bullet_speed:float = 720.0
@export_range(4.0,80.0,2.0) var muzzle_offset:float = 24.0
@export_range(0.0,10.0,0.05) var enemy_bullet_damage_multiplier:float = 1.0
@export_range(0.0,10.0,0.05) var friendly_bullet_damage_multiplier:float = 1.6666667

@export_category("伪军 - 头子死亡逃跑")
@export_range(80.0,360.0,5.0) var head_death_flee_speed:float = 190.0

var owner_head:ball = null
var _cooldown_left:float = 0.0
var _firing:bool = false
var _locked_aim_point:Vector2 = Vector2.ZERO
var _saved_speed:float = 0.0
var _surrendered:bool = false
var _flee_target:Vector2 = Vector2.ZERO
var _manual_burst_pending:bool = false

@onready var character_image:Sprite2D = $Graphics/Image

func _ready() -> void:
	Type = Ball_Type.Creature
	manual_controllable_subentity = true
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	super._ready()
	if standalone_selection:
		Type = Ball_Type.Ball
		Type_Tags = PackedStringArray(["小弟","独立人物","射手"])
	add_to_group("FakeArmySoldier")
	_set_soldier_texture(normal_texture)
	if owner_head != null and is_instance_valid(owner_head):
		Master = owner_head
		Team = owner_head.Team

func _set_soldier_texture(texture_value:Texture2D) -> void:
	if texture_value == null or character_image == null:
		return
	character_image.texture = texture_value
	var texture_size:Vector2 = texture_value.get_size()
	var longest:float = maxf(texture_size.x,texture_size.y)
	if longest > 0.001:
		var fitted:float = maxf(visual_local_max_size,1.0) / longest
		character_image.scale = Vector2(fitted,fitted)

func is_fake_army_soldier() -> bool:
	return true

func get_debug_detection_regions() -> Array[Dictionary]:
	return [{"shape":"circle","center":global_position,"radius":attack_range}]

func _physics_process(delta:float) -> void:
	if health <= 0:
		_free_creature()
		return
	if not is_multiplayer_authority():
		return
	if _surrendered:
		_update_head_death_flee()
		return
	if not standalone_selection and (owner_head == null or not is_instance_valid(owner_head) or owner_head.health <= 0):
		begin_fake_army_flee_from_head_death()
		return
	if not is_combat_runtime_active():
		return
	if _firing:
		return
	_cooldown_left = maxf(_cooldown_left - delta,0.0)
	if _cooldown_left > 0.0:
		return
	if is_player_controlled(): return
	var target:ball = TOOLS.nearest_enemy(self,attack_range)
	if target == null:
		return
	_locked_aim_point = target.global_position
	var aim_direction:Vector2 = _locked_aim_point - global_position
	if aim_direction.length_squared() > 0.000001:
		direction = aim_direction.normalized()
	call_deferred("_run_burst")

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or _surrendered: return
	if not is_combat_runtime_active() or dizziness or is_damage_output_disabled(): return
	if _firing or _manual_burst_pending or _cooldown_left > 0.0: return
	_locked_aim_point = player_control_aim_world_position(global_position+direction*attack_range)
	var aim_direction:Vector2 = _locked_aim_point - global_position
	if aim_direction.length_squared() > 0.000001: direction = aim_direction.normalized()
	_manual_burst_pending = true
	call_deferred("_run_burst")

func set_player_control_peer(peer_id:int) -> void:
	if peer_id != player_control_peer_id: _manual_burst_pending = false
	super.set_player_control_peer(peer_id)

func _run_burst() -> void:
	# A queued AI start may have been deferred just before C selected the soldier.
	if is_player_controlled() and not _manual_burst_pending: return
	_manual_burst_pending = false
	if _firing or health <= 0 or not is_inside_tree():
		return
	_firing = true
	_set_soldier_texture(firing_texture)
	_saved_speed = Speed
	Speed = 0.0
	for shot_index:int in range(maxi(shots_per_burst,1)):
		if health <= 0 or _surrendered or not is_inside_tree():
			break
		_spawn_bullet_to_locked_point()
		if shot_index + 1 < maxi(shots_per_burst,1):
			await get_tree().create_timer(1.0 / maxf(shot_rate_hz,0.01)).timeout
	if is_instance_valid(self):
		_set_soldier_texture(normal_texture)
		# 头子在连射期间死亡时，跑路逻辑已经接管 Speed；不能在协程收尾时恢复旧速度。
		if not _surrendered:
			Speed = _saved_speed
			_cooldown_left = maxf(burst_cooldown,0.0)
		_firing = false

func _spawn_bullet_to_locked_point() -> void:
	var world:Node = get_tree().current_scene
	if world == null or BULLET_SCENE == null:
		return
	var shot_dir:Vector2 = _locked_aim_point - global_position
	if shot_dir.length_squared() <= 0.000001:
		shot_dir = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	shot_dir = shot_dir.normalized()
	var bullet:Area2D = BULLET_SCENE.instantiate() as Area2D
	if bullet == null:
		return
	# 直接复用军火商的 raycast 子弹；以下只是该实例的伪军规则参数。
	bullet.set("Master_name",str(get_path()))
	bullet.set("Team",Team)
	bullet.set("projectile_kind",0)
	bullet.set("damage_amount",attack_damage(enemy_bullet_damage_multiplier))
	bullet.set("speed",bullet_speed)
	bullet.set("max_speed",bullet_speed)
	bullet.set("direction",shot_dir)
	bullet.set("lifetime",3.0)
	bullet.set("force_friendly_fire",true)
	bullet.set("friendly_damage_amount",attack_damage(friendly_bullet_damage_multiplier))
	bullet.set("max_travel_distance",attack_range)
	if owner_head != null and is_instance_valid(owner_head):
		bullet.set("protected_target_path",str(owner_head.get_path()))
		bullet.set("friendly_root_path",str(owner_head.get_path()))
	bullet.global_position = global_position + shot_dir * muzzle_offset
	bullet.global_rotation = shot_dir.angle()
	bullet.name = Game.return_random_name(bullet)
	world.add_child(bullet,true)

func begin_fake_army_flee_from_head_death() -> void:
	# 与黑帮老大普通小弟跑路保持同一语义：头子死亡后不瞬间自杀，
	# 而是停止攻击、播放“跑路了兄弟”，穿出最近地图边界后再删除。
	if _surrendered or health <= 0 or not is_multiplayer_authority():
		return
	_surrendered = true
	_set_soldier_texture(normal_texture)
	_firing = false
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Speed = maxf(head_death_flee_speed,1.0)
	if default_properties != null:
		default_properties["Speed"] = Speed
	if self_hitbox != null:
		# 头子可能恰好死在 Area2D 伤害回调内，避免在 physics flush 时直接切 monitoring。
		self_hitbox.set_deferred("monitoring",false)
	# CharacterBody2D 的碰撞过滤也延后一拍切换，避免头子恰好死在物理 in/out 回调时改 PhysicsServer2D 状态。
	set_deferred("collision_layer",0)
	set_deferred("collision_mask",0)
	set_meta(&"submission_allow_map_escape",true)
	_pick_nearest_map_exit_for_flee()
	_play_head_death_flee_audio()


# 保留旧入口兼容伪军头子/旧场景调用；V137 起“投降”实际表现为跑路。
func force_surrender() -> void:
	begin_fake_army_flee_from_head_death()


func _pick_nearest_map_exit_for_flee() -> void:
	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_flee_target = global_position + Vector2.RIGHT * 500.0
		direction = (_flee_target - global_position).normalized()
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


func _update_head_death_flee() -> void:
	var to_exit:Vector2 = _flee_target - global_position
	if to_exit.length_squared() > 0.001:
		direction = to_exit.normalized()
	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		if not rect.grow(18.0).has_point(global_position):
			queue_free()
	elif global_position.distance_to(_flee_target) <= 12.0:
		queue_free()


func _play_head_death_flee_audio() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_head_death_flee_sfx.rpc(global_position)
	else:
		_rpc_play_head_death_flee_sfx(global_position)


@rpc("authority","call_local","unreliable")
func _rpc_play_head_death_flee_sfx(position_value:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null or GANG_FLEE_SFX == null:
		return
	# 和黑帮普通小弟一样，多个小弟同帧跑路时只播一次人声，避免三层叠音。
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


func _free_creature() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		Game.free_node(self)
