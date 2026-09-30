extends ball

# ============================================================
# 猎人
# - 霰弹枪：攻击频率低、单次爆发高，一次发射多颗弹丸。
# - 永远瞄准当前最近敌人；即使目标超出霰弹有效距离，也照样开枪。
# - 弹丸有严格的最大飞行距离，飞到距离后立刻消失。
# - 周期性在附近布置捕兽夹，踩中的敌人受伤并暂时无法移动。
# - 外观状态：瞄准 / 装填 / 放夹子。
# ============================================================

const PELLET_SCENE:PackedScene = preload("res://scenes/shooter/猎人_霰弹.tscn")
const TRAP_SCENE:PackedScene = preload("res://scenes/creatures/猎人_捕兽夹.tscn")
const IMAGE_DIR:String = "res://Images/characters/人物/猎人"

const VISUAL_AIM:int = 0
const VISUAL_RELOAD:int = 1
const VISUAL_TRAP:int = 2

@export_category("猎人 - 外观")
# 为了兼容上一版字段，normal_texture/attack_texture 都可继续在场景里设置。
# 当前默认：瞄准图既是常态，也是开枪前的攻击姿态。
@export var normal_texture:Texture2D
@export var attack_texture:Texture2D
@export var reload_texture:Texture2D
@export var trap_texture:Texture2D
@export_range(0.05,1.0,0.01) var attack_windup:float = 0.18
@export_range(0.05,1.0,0.01) var attack_recovery:float = 0.24
@export_range(0.10,2.5,0.05) var reload_visual_duration:float = 0.85
@export_range(0.10,2.0,0.05) var trap_pose_duration:float = 0.62

@export_category("猎人 - 霰弹枪")
@export_range(1,24,1) var pellet_count:int = 9
@export_range(0.0,60.0,0.5) var pellet_spread_degrees:float = 28.0
@export_range(0.0,10.0,0.05) var pellet_damage_multiplier:float = 1.1
@export_range(50.0,1800.0,10.0) var pellet_speed:float = 780.0
@export_range(20.0,800.0,5.0) var pellet_max_distance:float = 150.0
@export_range(0.0,120.0,1.0) var pellet_knockback_distance:float = 10.0
@export_range(0.0,1200.0,10.0) var pellet_knockback_speed:float = 360.0
@export_range(1.0,12.0,0.5) var pellet_visual_size:float = 4.0
@export_range(0.0,24.0,0.5) var muzzle_offset:float = 15.0

@export_category("猎人 - 捕兽夹")
@export_range(0.5,30.0,0.1) var trap_place_interval:float = 5.5
@export_range(0.0,10.0,0.1) var first_trap_delay:float = 2.4
@export_range(0,12,1) var max_active_traps:int = 3
@export_range(0.0,120.0,1.0) var trap_place_min_radius:float = 18.0
@export_range(0.0,160.0,1.0) var trap_place_max_radius:float = 42.0
@export_range(1.0,100.0,1.0) var trap_trigger_radius:float = 24.0
@export_range(0.0,10.0,0.05) var trap_damage_multiplier:float = 1.0
# 这个值同时就是“夹子闭合并留在场上的时长”；效果为禁锢（移速=0），不是眩晕。
@export_range(0.05,5.0,0.05) var trap_root_duration:float = 1.45
@export_range(0.0,3.0,0.05) var trap_arm_delay:float = 0.45
@export_range(1.0,60.0,0.5) var trap_lifetime:float = 20.0

var _default_texture:Texture2D = null
var _base_image_scale:Vector2 = Vector2.ONE
var _visual_token:int = 0
var _trap_loop_running:bool = false
var _cleanup_started:bool = false
var _last_aim_direction:Vector2 = Vector2.RIGHT
var _last_controlled_trap_msec:int = -1000000000


func _ready() -> void:
	Can_Skill = false
	Has_Collision_Damage = false
	super._ready()
	_auto_load_textures()
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
		_base_image_scale = (image as Sprite2D).scale
	_apply_normal_texture()
	if is_multiplayer_authority():
		call_deferred("_trap_loop")


func _exit_tree() -> void:
	_cleanup_owned_assets()


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled():
		Attacking = false
		return

	var target:ball = _acquire_nearest_enemy()
	if target == null and not has_player_control_aim():
		Attacking = false
		return

	Attacking = true
	_last_aim_direction = player_control_aim_direction(_last_aim_direction) if has_player_control_aim() else _direction_to_target(target)
	# 开枪前显示“猎人瞄准”。目标无论多远都会进入这次攻击。
	_show_visual_everywhere(VISUAL_AIM,0.0)

	if not (await wait_for_combat_time(maxf(attack_windup,0.01))):
		Attacking = false
		return
	if not is_instance_valid(self) or health <= 0 or state_machine.current_state == State.Die:
		return
	if is_damage_output_disabled():
		Attacking = false
		return

	# AI 继续在开枪前重新选最近敌人；手动控制则在真正开火帧读取当前鼠标方向。
	if has_player_control_aim():
		_last_aim_direction = player_control_aim_direction(_last_aim_direction)
		_fire_shotgun(_last_aim_direction)
	else:
		target = _acquire_nearest_enemy()
		if target != null:
			_last_aim_direction = _direction_to_target(target)
			_fire_shotgun(_last_aim_direction)
	# 射击后切到装填图，持续一段时间再回到瞄准图。
	_show_visual_everywhere(VISUAL_RELOAD,maxf(reload_visual_duration,attack_recovery))
	# 上膛声稍微晚于枪响进入，避免两个完整音频从同一采样点同时起播。
	_play_reload_sfx_after(0.12)

	await wait_for_combat_time(maxf(attack_recovery,0.01))
	if is_instance_valid(self):
		Attacking = false


func controlled_skill_action() -> void:
	# V131：直接控制时右键手动放夹子；后台 trap loop 只服务 AI。
	if not is_player_controlled() or not is_multiplayer_authority():
		return
	if health <= 0 or state_machine.current_state == State.Die or dizziness or is_damage_output_disabled():
		return
	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(trap_place_interval,0.0) * 1000.0))
	if now_msec - _last_controlled_trap_msec < cooldown_msec:
		return
	_last_controlled_trap_msec = now_msec
	_place_trap()


func _direction_to_target(target:ball) -> Vector2:
	if target == null or not is_instance_valid(target):
		return _last_aim_direction
	var point:Vector2 = combat_target_position(target)
	var aim:Vector2 = point - global_position
	if aim.length_squared() <= 0.000001:
		aim = direction
	if aim.length_squared() <= 0.000001:
		aim = Vector2.RIGHT
	return aim.normalized()


func _fire_shotgun(base_direction:Vector2) -> void:
	if base_direction.length_squared() <= 0.000001:
		base_direction = Vector2.RIGHT
	base_direction = base_direction.normalized()

	var count:int = maxi(pellet_count,1)
	var total_spread:float = maxf(pellet_spread_degrees,0.0)
	for index:int in range(count):
		var t:float = 0.5 if count <= 1 else float(index) / float(count - 1)
		var ordered_angle:float = lerpf(-total_spread * 0.5,total_spread * 0.5,t)
		# 轻微随机扰动让每枪不会完全形成固定扇形，但仍保持整体覆盖稳定。
		var jitter:float = randf_range(-0.9,0.9)
		var pellet_direction:Vector2 = base_direction.rotated(deg_to_rad(ordered_angle + jitter)).normalized()
		_spawn_pellet(pellet_direction)

	_play_named_sfx_everywhere("霰弹枪攻击",-5.0,randf_range(0.97,1.03))


func _spawn_pellet(pellet_direction:Vector2) -> void:
	var pellet:Area2D = PELLET_SCENE.instantiate() as Area2D
	if pellet == null:
		return

	pellet.set("Master_name",str(name))
	pellet.set("Team",Team)
	pellet.set("damage_amount",attack_damage(pellet_damage_multiplier))
	pellet.set("speed",pellet_speed)
	pellet.set("max_distance",pellet_max_distance)
	pellet.set("direction",pellet_direction)
	pellet.set("knockback_distance",pellet_knockback_distance)
	pellet.set("knockback_speed",pellet_knockback_speed)
	pellet.set("visual_size",pellet_visual_size)
	pellet.global_position = global_position + pellet_direction * maxf(muzzle_offset,0.0)
	pellet.global_rotation = pellet_direction.angle()
	pellet.name = Game.return_random_name(pellet)
	get_tree().current_scene.add_child(pellet,true)


func _trap_loop() -> void:
	if _trap_loop_running:
		return
	_trap_loop_running = true

	if first_trap_delay > 0.0:
		if not (await wait_for_combat_time(first_trap_delay)):
			_trap_loop_running = false
			return

	while is_instance_valid(self) and is_inside_tree() and health > 0:
		# V131：玩家直接控制时，捕兽夹绝不后台自动释放；右键 controlled_skill_action() 才放置。
		if is_combat_runtime_active() and not is_player_controlled():
			_place_trap()
		if not (await wait_for_combat_time(maxf(trap_place_interval,0.5))):
			break

	_trap_loop_running = false


func _place_trap() -> void:
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return

	_trim_owned_traps_if_needed()
	var trap:Node2D = TRAP_SCENE.instantiate() as Node2D
	if trap == null:
		return

	# 捕兽夹直接放在猎人脚下，不再随机偏移到周围。
	var point:Vector2 = global_position

	trap.set("Master_name",str(name))
	trap.set("Team",Team)
	trap.set("damage_amount",attack_damage(trap_damage_multiplier))
	trap.set("root_duration",trap_root_duration)
	trap.set("trigger_radius",trap_trigger_radius)
	trap.set("arm_delay",trap_arm_delay)
	trap.set("lifetime",trap_lifetime)
	trap.global_position = point
	trap.global_rotation = 0.0
	trap.name = Game.return_random_name(trap)
	get_tree().current_scene.add_child(trap,true)
	# 再写一次全局坐标，确保父节点存在变换时也严格落在猎人当前位置。
	trap.global_position = point
	trap.global_rotation = 0.0

	# 放下夹子时短暂显示用户提供的“猎人放夹子”图片。
	_show_visual_everywhere(VISUAL_TRAP,trap_pose_duration)
	_play_named_sfx_everywhere("捕兽夹放置",0.0,randf_range(0.98,1.03))


func _trim_owned_traps_if_needed() -> void:
	if max_active_traps <= 0:
		return
	var owned:Array[Node] = []
	for node:Node in get_tree().get_nodes_in_group("HunterTrap"):
		if node != null and is_instance_valid(node) and str(node.get("Master_name")) == str(name):
			owned.append(node)
	while owned.size() >= max_active_traps:
		var oldest:Node = owned.pop_front()
		if oldest != null and is_instance_valid(oldest):
			Game.free_node(oldest)


func _cleanup_owned_assets() -> void:
	if _cleanup_started:
		return
	_cleanup_started = true
	_visual_token += 1
	var tree:SceneTree = get_tree()
	if tree == null:
		return
	var owner_name:String = str(name)
	for group_name:String in ["HunterTrap","HunterPellet"]:
		for node:Node in tree.get_nodes_in_group(group_name):
			if node != null and is_instance_valid(node) and str(node.get("Master_name")) == owner_name:
				# 捕兽夹的 _exit_tree 会同时释放它自己的禁锢控制锁。
				node.queue_free()


func _acquire_nearest_enemy() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_valid_enemy(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	return nearest


func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if Team != "" and target.Team != "" and target.Team == Team:
		return false
	return true


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


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _load_first_texture([
			IMAGE_DIR.path_join("猎人_瞄准.png"),
			IMAGE_DIR.path_join("猎人_正常.png"),
			IMAGE_DIR.path_join("猎人_正常.webp"),
			IMAGE_DIR.path_join("猎人_正常.svg")
		])
	if attack_texture == null:
		attack_texture = _load_first_texture([
			IMAGE_DIR.path_join("猎人_瞄准.png"),
			IMAGE_DIR.path_join("猎人_攻击.png"),
			IMAGE_DIR.path_join("猎人_霰弹枪.png"),
			IMAGE_DIR.path_join("猎人_攻击.webp"),
			IMAGE_DIR.path_join("猎人_攻击.svg")
		])
	if reload_texture == null:
		reload_texture = _load_first_texture([
			IMAGE_DIR.path_join("猎人_装填.png"),
			IMAGE_DIR.path_join("猎人_装填.webp")
		])
	if trap_texture == null:
		trap_texture = _load_first_texture([
			IMAGE_DIR.path_join("猎人_放夹子.png"),
			IMAGE_DIR.path_join("猎人_放夹子.webp")
		])


func _load_first_texture(paths:Array[String]) -> Texture2D:
	for path:String in paths:
		if not ResourceLoader.exists(path):
			continue
		var resource:Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource as Texture2D
	return null


func _apply_normal_texture() -> void:
	if not (image is Sprite2D):
		return
	_set_visual_state_local(VISUAL_AIM)
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _show_visual_everywhere(state:int,duration:float) -> void:
	_visual_token += 1
	var token:int = _visual_token
	if multiplayer.has_multiplayer_peer():
		_rpc_show_visual_state.rpc(token,state,duration)
	else:
		_rpc_show_visual_state(token,state,duration)


@rpc("authority","call_local","reliable")
func _rpc_show_visual_state(token:int,state:int,duration:float) -> void:
	if token < _visual_token:
		return
	_visual_token = token
	_set_visual_state_local(state)
	if duration > 0.0:
		_restore_visual_after(duration,token)


func _set_visual_state_local(state:int) -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D
	sprite.scale = _base_image_scale
	var wanted:Texture2D = null
	match state:
		VISUAL_RELOAD:
			wanted = reload_texture
		VISUAL_TRAP:
			wanted = trap_texture
		_:
			wanted = attack_texture if attack_texture != null else normal_texture
	if wanted == null:
		wanted = normal_texture if normal_texture != null else _default_texture
	if wanted != null:
		sprite.texture = wanted


func _restore_visual_after(delay:float,token:int) -> void:
	await get_tree().create_timer(maxf(delay,0.02)).timeout
	if not is_instance_valid(self) or token != _visual_token or not (image is Sprite2D):
		return
	_set_visual_state_local(VISUAL_AIM)


func _play_named_sfx_everywhere(sfx_name:String,volume_db:float,pitch:float) -> void:
	var params:Dictionary = {
		"volume": volume_db,
		"pitch": pitch,
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,false,true)
	else:
		Audios.play_sfx(sfx_name,params,false,true)


func _play_reload_sfx_after(delay:float) -> void:
	if not (await wait_for_combat_time(maxf(delay,0.0))):
		return
	if not is_instance_valid(self) or health <= 0 or state_machine.current_state == State.Die:
		return
	_play_named_sfx_everywhere("霰弹枪上膛",0.0,randf_range(0.98,1.03))


func Die() -> void:
	_cleanup_owned_assets()
	_visual_token += 1
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
