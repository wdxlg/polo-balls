extends ball

@export_category("炸弹客 - 外观（可留空）")
@export var normal_texture:Texture2D

const BOMB_SCENE:PackedScene = preload("res://scenes/shooter/炸弹客炸弹.tscn")
const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")

# ============================================================
# 炸弹客
# - 周期性在当前位置放置地雷式炸弹：不会自行爆炸，只能被其他炸弹爆炸连锁引爆。
# - 身体碰到敌人时，在敌人身上附着一颗定时炸弹。
# - 所有炸弹使用同一爆炸逻辑，因此附着炸弹 -> 地面炸弹 -> 更多地面炸弹可以连续引爆。
# ============================================================

@export_category("炸弹客 - 放置")
@export_range(0.2,15.0,0.1) var ground_bomb_interval:float = 2.8
@export_range(1,64,1) var max_ground_bombs:int = 16
@export_range(0.0,8.0,0.05) var attach_same_target_cooldown:float = 0.85

@export_category("炸弹客 - 炸弹")
@export_range(0.05,10.0,0.05) var attached_fuse_duration:float = 1.55
@export_range(10.0,600.0,5.0) var bomb_explosion_radius:float = 118.0
@export_range(0.0,10.0,0.05) var bomb_damage_multiplier:float = 1.0
@export_range(10.0,800.0,5.0) var bomb_chain_trigger_radius:float = 118.0
@export_range(0.0,300.0,5.0) var bomb_knockback_distance:float = 55.0
@export_range(50.0,1800.0,10.0) var bomb_knockback_speed:float = 620.0

var _ground_bomb_timer_left:float = 0.0
var _last_attach_msec_by_target:Dictionary = {}


func _ready() -> void:
	super._ready()
	_auto_load_texture()
	_apply_optional_normal_texture()
	_ground_bomb_timer_left = maxf(ground_bomb_interval,0.05)
func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority():
		_ground_bomb_timer_left -= delta
		if _ground_bomb_timer_left <= 0.0 and not is_player_controlled():
			_ground_bomb_timer_left += maxf(ground_bomb_interval,0.05)
			_place_ground_bomb()
	super.tick_physics(state,delta)


func controlled_attack_action() -> void:
	# 左键放置原有地面炸弹；撞上敌人时的附着炸弹仍是碰撞被动。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if _ground_bomb_timer_left > 0.0:
		return
	_ground_bomb_timer_left = maxf(ground_bomb_interval,0.05)
	_place_ground_bomb()


func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	# 保留原角色的正常物理反弹和碰撞反馈。
	super(speed,collision)
	if not is_multiplayer_authority() or collision == null:
		return

	var collider = collision.get_collider()
	if not collider is ball:
		return
	var target:ball = collider as ball
	if not _is_valid_enemy(target):
		return

	var now_msec:int = Time.get_ticks_msec()
	var target_id:int = target.get_instance_id()
	var cooldown_msec:int = int(round(maxf(attach_same_target_cooldown,0.0) * 1000.0))
	if _last_attach_msec_by_target.has(target_id):
		if now_msec - int(_last_attach_msec_by_target[target_id]) < cooldown_msec:
			return
	_last_attach_msec_by_target[target_id] = now_msec
	_place_attached_bomb(target)


func _place_ground_bomb() -> void:
	_trim_old_ground_bombs()
	_spawn_bomb(global_position,null,true)


func _place_attached_bomb(target:ball) -> void:
	if not _is_valid_enemy(target):
		return
	_spawn_bomb(target.global_position,target,false)


func _spawn_bomb(position_value:Vector2,target:ball,is_ground_bomb:bool) -> void:
	var bomb:Node2D = BOMB_SCENE.instantiate() as Node2D
	if bomb == null:
		return

	bomb.set("Master_name",name)
	bomb.set("Team",Team)
	bomb.set("attached_target_name",str(target.name) if target != null and is_instance_valid(target) else "")
	bomb.set("is_ground",is_ground_bomb)
	bomb.set("fuse_duration",attached_fuse_duration)
	bomb.set("explosion_radius",bomb_explosion_radius)
	bomb.set("damage_amount",attack_damage(bomb_damage_multiplier))
	bomb.set("chain_trigger_radius",bomb_chain_trigger_radius)
	bomb.set("explosion_knockback_distance",bomb_knockback_distance)
	bomb.set("explosion_knockback_speed",bomb_knockback_speed)
	bomb.global_position = position_value
	bomb.name = Game.return_random_name(bomb)
	get_tree().current_scene.add_child(bomb,true)
	_play_local_sfx_everywhere("click",position_value,-13.0,randf_range(0.92,1.05),460.0)


func _trim_old_ground_bombs() -> void:
	var owned:Array[Node] = []
	for node:Node in get_tree().get_nodes_in_group("BomberBomb"):
		if not is_instance_valid(node):
			continue
		if str(node.get("Master_name")) != name:
			continue
		if not bool(node.get("is_ground")):
			continue
		owned.append(node)

	while owned.size() >= maxi(max_ground_bombs,1):
		var oldest:Node = owned.pop_front()
		if oldest != null and is_instance_valid(oldest):
			Game.free_node(oldest)


func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target):
		return false
	if target == self or not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and Team != ""
		and target.Team != ""
		and Team == target.Team
	):
		return false
	return true


func _auto_load_texture() -> void:
	if normal_texture != null:
		return
	var path:String = "res://Images/characters/人物/炸弹客/炸弹客_正常.png"
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


func _play_local_sfx_everywhere(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_local_sfx.rpc(key,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_local_sfx(key,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_local_sfx(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	LOCAL_SFX.play(self,key,position_value,volume_db,pitch,max_distance)


func Die() -> void:
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
