extends ball

# ============================================================
# 军火商
# - 自身正常移动/反弹，但身体没有碰撞伤害。
# - 周期性播放放置攻击立绘，前摇结束后在身边留下一把随机枪。
# - 枪本体只是 Node2D：没有碰撞、不会移动；各自负责锁敌、弹匣和装填。
# ============================================================

const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")
const GUN_SCENE:PackedScene = preload("res://scenes/creatures/军火商_枪.tscn")
const IMAGE_DIR:String = "res://Images/characters/人物/军火商"

@export_category("军火商 - 外观")
@export var normal_texture:Texture2D
@export var attack_texture:Texture2D
@export_range(0.10,2.0,0.05) var place_attack_visual_duration:float = 0.90

@export_category("军火商 - 放枪")
@export_range(0.5,20.0,0.1) var gun_place_interval:float = 4.2
@export_range(0.05,2.0,0.05) var gun_place_windup:float = 0.55
@export_range(0.0,160.0,1.0) var gun_place_min_radius:float = 38.0
@export_range(0.0,220.0,1.0) var gun_place_max_radius:float = 62.0
@export_range(0.0,80.0,1.0) var gun_place_map_margin:float = 28.0
# 0 = 不限制。保留这个保险参数，但默认完全遵循“持续放枪”。
@export_range(0,64,1) var max_active_guns:int = 0
@export_range(0.0,10.0,0.1) var first_gun_delay:float = 1.6

const VISUAL_NORMAL:int = 0
const VISUAL_ATTACK:int = 1

var _visual_token:int = 0
var _default_texture:Texture2D = null
var _weapon_loop_running:bool = false
var _cleanup_started:bool = false
var _last_controlled_gun_msec:int = -1000000000


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	super._ready()
	_auto_load_textures()
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_set_visual_state_local(VISUAL_NORMAL)
	if is_multiplayer_authority():
		call_deferred("_weapon_loop")


func _exit_tree() -> void:
	# 不只死亡：Reset、重打、换场景或外部直接 queue_free 军火商时，
	# 都必须把已经脱离军火商节点、挂在 World 下的枪和子弹一起清掉。
	_cleanup_owned_weapons()


func controlled_skill_action() -> void:
	# V131：直接控制时右键在鼠标位置手动放一把随机枪；后台放枪循环暂停。
	if not is_player_controlled() or not is_multiplayer_authority():
		return
	if health <= 0 or state_machine.current_state == State.Die or dizziness or is_damage_output_disabled():
		return
	if not has_player_control_aim():
		return
	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(gun_place_interval,0.0) * 1000.0))
	if now_msec - _last_controlled_gun_msec < cooldown_msec:
		return
	_last_controlled_gun_msec = now_msec
	_place_one_gun(player_control_aim_position)


func _weapon_loop() -> void:
	if _weapon_loop_running:
		return
	_weapon_loop_running = true

	if first_gun_delay > 0.0:
		if not (await wait_for_combat_time(first_gun_delay)):
			_weapon_loop_running = false
			return

	while is_instance_valid(self) and is_inside_tree() and health > 0:
		if is_combat_runtime_active() and not is_player_controlled():
			await _place_one_gun()
		if not (await wait_for_combat_time(maxf(gun_place_interval,0.5))):
			break

	_weapon_loop_running = false


func _place_one_gun(forced_world_position:Variant = null) -> void:
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if forced_world_position == null and is_player_controlled():
		return

	_show_attack_visual_everywhere(maxf(place_attack_visual_duration,gun_place_windup + 0.10))
	var token:int = _visual_token
	if not (await wait_for_combat_time(maxf(gun_place_windup,0.05))):
		return
	if not is_instance_valid(self) or health <= 0 or token != _visual_token or not is_combat_runtime_active():
		return
	if forced_world_position == null and is_player_controlled():
		return

	_trim_owned_guns_if_needed()
	_spawn_random_gun(forced_world_position)


func _spawn_random_gun(forced_world_position:Variant = null) -> void:
	var gun:Node2D = GUN_SCENE.instantiate() as Node2D
	if gun == null:
		return

	var gun_type:int = randi_range(0,5)
	var spawn_position:Vector2
	if forced_world_position is Vector2:
		spawn_position = forced_world_position
	else:
		var min_radius:float = minf(gun_place_min_radius,gun_place_max_radius)
		var max_radius:float = maxf(gun_place_min_radius,gun_place_max_radius)
		var angle:float = randf_range(0.0,TAU)
		var radius:float = randf_range(min_radius,max_radius)
		spawn_position = global_position + Vector2.RIGHT.rotated(angle) * radius
	spawn_position = _clamp_point_to_map(spawn_position,gun_place_map_margin)

	gun.set("gun_type",gun_type)
	gun.set("Master_name",name)
	gun.set("Team",Team)
	gun.global_position = spawn_position
	gun.global_rotation = randf_range(-PI,PI)
	gun.name = Game.return_random_name(gun)
	get_tree().current_scene.add_child(gun,true)
	_play_local_sfx_everywhere("click",spawn_position,-8.0,randf_range(0.92,1.08),560.0)


func _get_map_rect() -> Rect2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	if not world.map_group.has(str(world.now_choose_map)):
		return Rect2()
	var map_node = world.map_group[str(world.now_choose_map)]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.return_map_world_rect(map_node)


func _clamp_point_to_map(point:Vector2,margin_value:float) -> Vector2:
	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return point
	var margin:float = maxf(margin_value,0.0)
	var min_x:float = rect.position.x + margin
	var max_x:float = rect.end.x - margin
	var min_y:float = rect.position.y + margin
	var max_y:float = rect.end.y - margin
	if min_x > max_x:
		min_x = (rect.position.x + rect.end.x) * 0.5
		max_x = min_x
	if min_y > max_y:
		min_y = (rect.position.y + rect.end.y) * 0.5
		max_y = min_y
	return Vector2(clampf(point.x,min_x,max_x),clampf(point.y,min_y,max_y))


func _play_local_sfx_everywhere(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_local_sfx.rpc(key,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_local_sfx(key,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_local_sfx(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	LOCAL_SFX.play(self,key,position_value,volume_db,pitch,max_distance)


func _trim_owned_guns_if_needed() -> void:
	if max_active_guns <= 0:
		return
	var owned:Array[Node] = []
	for node:Node in get_tree().get_nodes_in_group("ArmsDealerGun"):
		if not is_instance_valid(node):
			continue
		if str(node.get("Master_name")) == name:
			owned.append(node)
	while owned.size() >= max_active_guns:
		var oldest:Node = owned.pop_front()
		if oldest != null and is_instance_valid(oldest):
			Game.free_node(oldest)


func _cleanup_owned_weapons() -> void:
	if _cleanup_started:
		return
	_cleanup_started = true
	_visual_token += 1

	var tree:SceneTree = get_tree()
	if tree == null:
		return
	var owner_name:String = str(name)
	for group_name:String in ["ArmsDealerGun","ArmsDealerProjectile"]:
		for node:Node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node):
				continue
			var master_value:Variant = node.get("Master_name")
			if str(master_value) != owner_name:
				continue
			# 这里直接 queue_free，避免 Reset/退出树期间再经过全局 authority 包装导致漏清。
			node.queue_free()


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _load_first_texture([
			IMAGE_DIR.path_join("军火商_正常.png"),
			IMAGE_DIR.path_join("军火商_正常.webp"),
			IMAGE_DIR.path_join("军火商_正常.svg")
		])
	if attack_texture == null:
		attack_texture = _load_first_texture([
			IMAGE_DIR.path_join("军火商_放枪.png"),
			IMAGE_DIR.path_join("军火商_部署枪.png"),
			IMAGE_DIR.path_join("军火商_攻击.png"),
			IMAGE_DIR.path_join("军火商_攻击.webp"),
			IMAGE_DIR.path_join("军火商_攻击.svg")
		])


func _load_first_texture(paths:Array[String]) -> Texture2D:
	for path:String in paths:
		if not ResourceLoader.exists(path):
			continue
		var resource:Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource as Texture2D
	return null


func _show_attack_visual_everywhere(duration:float) -> void:
	_visual_token += 1
	var token:int = _visual_token
	if multiplayer.has_multiplayer_peer():
		_rpc_show_place_visual.rpc(token,duration)
	else:
		_rpc_show_place_visual(token,duration)


@rpc("authority","call_local","reliable")
func _rpc_show_place_visual(token:int,duration:float) -> void:
	if token < _visual_token:
		return
	_visual_token = token
	_set_visual_state_local(VISUAL_ATTACK)
	_restore_normal_visual_after(duration,token)


func _restore_normal_visual_after(delay:float,token:int) -> void:
	await get_tree().create_timer(maxf(delay,0.10)).timeout
	if not is_instance_valid(self) or token != _visual_token:
		return
	_set_visual_state_local(VISUAL_NORMAL)


func _set_visual_state_local(state_value:int) -> void:
	if not (image is Sprite2D):
		return
	var normal:Texture2D = normal_texture if normal_texture != null else _default_texture
	var wanted:Texture2D = attack_texture if state_value == VISUAL_ATTACK and attack_texture != null else normal
	if wanted == null:
		return
	(image as Sprite2D).texture = wanted
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func Die() -> void:
	_cleanup_owned_weapons()
	_visual_token += 1
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
