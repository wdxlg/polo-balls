extends Node2D

# ============================================================
# 猎人捕兽夹
# - 未触发：显示“捕兽夹_开.png”。
# - 触发：造成伤害，立即切换到“捕兽夹_关.png”。
# - 闭合状态会停留 root_duration 秒；这段时间只禁锢移动，不进入眩晕状态。
# - 捕兽夹消失时，会主动释放本捕兽夹创建的控制锁。
#   因此“闭合图片消失”与“这次禁锢结束”绑定在同一生命周期里。
# ============================================================

const IMAGE_DIR:String = "res://Images/characters/人物/猎人/捕兽夹"

@export var Master_name:String = ""
@export var Team:String = ""
@export var damage_amount:float = 20.0
@export var root_duration:float = 1.45
@export var trigger_radius:float = 24.0
@export var arm_delay:float = 0.45
@export var lifetime:float = 20.0

@export_category("捕兽夹 - 外观")
@export var open_texture:Texture2D
@export var closed_texture:Texture2D
@export_range(12.0,120.0,1.0) var visual_max_dimension:float = 34.0
@export var open_visual_offset:Vector2 = Vector2.ZERO
@export var closed_visual_offset:Vector2 = Vector2.ZERO

var _arm_left:float = 0.0
var _life_left:float = 0.0
var _closed_left:float = 0.0
var _triggered:bool = false
var _trapped_target:ball = null
var _root_acquired:bool = false
var _fallback_saved_speed:float = 0.0

# World 每个 physics tick 都会先把角色属性恢复到 default_properties，
# 再统一结算 Buff。因此只直接写 target.Speed = 0 会在下一帧被恢复。
# 这里使用项目原生 Speed Set Buff，并把 index 设为 3，让“禁锢=0 移速”
# 在其它速度加成/乘法之后最后结算。它不是 dizziness，不会阻止攻击/技能。
const ROOT_BUFF_NAME:String = "猎人捕兽夹禁锢"

@onready var _sprite:Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _left_jaw:Line2D = get_node_or_null("LeftJaw") as Line2D
@onready var _right_jaw:Line2D = get_node_or_null("RightJaw") as Line2D
@onready var _trigger_plate:Polygon2D = get_node_or_null("TriggerPlate") as Polygon2D


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("HunterTrap")
	_arm_left = maxf(arm_delay,0.0)
	_life_left = maxf(lifetime,0.1)
	_auto_load_textures()
	_setup_visual()
	global_rotation = 0.0
	_apply_trap_texture(false)


func _exit_tree() -> void:
	# 无论是正常计时结束、猎人死亡清理，还是“最大数量”把旧夹子移除，
	# 只要这个闭合夹子消失，就立刻释放它自己的禁锢锁。
	_release_trap_control()


func _auto_load_textures() -> void:
	if open_texture == null:
		open_texture = _load_texture(IMAGE_DIR.path_join("捕兽夹_开.png"))
	if closed_texture == null:
		closed_texture = _load_texture(IMAGE_DIR.path_join("捕兽夹_关.png"))


func _load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func _setup_visual() -> void:
	var radius:float = maxf(trigger_radius,8.0)
	if _left_jaw != null:
		_left_jaw.width = 3.0
		_left_jaw.points = PackedVector2Array([
			Vector2(-radius * 0.85,0.0),
			Vector2(-radius * 0.55,-radius * 0.42),
			Vector2(-radius * 0.18,-radius * 0.12),
			Vector2.ZERO
		])
	if _right_jaw != null:
		_right_jaw.width = 3.0
		_right_jaw.points = PackedVector2Array([
			Vector2(radius * 0.85,0.0),
			Vector2(radius * 0.55,-radius * 0.42),
			Vector2(radius * 0.18,-radius * 0.12),
			Vector2.ZERO
		])
	if _trigger_plate != null:
		_trigger_plate.polygon = PackedVector2Array([
			Vector2(-radius * 0.28,-radius * 0.11),
			Vector2(radius * 0.28,-radius * 0.11),
			Vector2(radius * 0.28,radius * 0.11),
			Vector2(-radius * 0.28,radius * 0.11)
		])


func _physics_process(delta:float) -> void:
	_update_visual()
	if not is_multiplayer_authority():
		return

	if _triggered:
		_enforce_trap_root()
		# 目标已经死亡/被移除时，不需要继续展示闭合夹子。
		if _trapped_target == null or not is_instance_valid(_trapped_target) or _trapped_target.health <= 0:
			Game.free_node(self)
			return
		_closed_left = maxf(_closed_left - delta,0.0)
		if _closed_left <= 0.0:
			# _exit_tree 中会释放这次禁锢；于是夹子消失与禁锢结束同步。
			Game.free_node(self)
		return

	var master:ball = _resolve_master()
	if master == null or not is_instance_valid(master) or master.health <= 0:
		Game.free_node(self)
		return

	_life_left -= delta
	if _life_left <= 0.0:
		Game.free_node(self)
		return

	if _arm_left > 0.0:
		_arm_left = maxf(_arm_left - delta,0.0)
		return

	# 禁伤状态期间捕兽夹不触发，避免“红牌后仍然控人”。
	if master.is_damage_output_disabled():
		return

	var target:ball = _find_trigger_target(master)
	if target != null:
		_trigger(target,master)


func _update_visual() -> void:
	# 捕兽夹本体始终保持固定大小，不再做呼吸式放大/缩小。
	scale = Vector2.ONE
	if _trigger_plate != null:
		_trigger_plate.modulate.a = 0.90 if _arm_left <= 0.0 else 0.45


func _apply_trap_texture(closed:bool) -> void:
	var wanted:Texture2D = closed_texture if closed else open_texture
	var has_sprite_visual:bool = _sprite != null and wanted != null
	if _sprite != null:
		_sprite.visible = has_sprite_visual
		if has_sprite_visual:
			_sprite.texture = wanted
			_sprite.position = closed_visual_offset if closed else open_visual_offset
			var texture_size:Vector2 = wanted.get_size()
			var max_dim:float = maxf(texture_size.x,texture_size.y)
			if max_dim > 0.0:
				_sprite.scale = Vector2.ONE * (maxf(visual_max_dimension,1.0) / max_dim)
	# 图片存在时隐藏旧的几何占位图；图片缺失时仍能回退到旧视觉。
	if _left_jaw != null:
		_left_jaw.visible = not has_sprite_visual
	if _right_jaw != null:
		_right_jaw.visible = not has_sprite_visual
	if _trigger_plate != null:
		_trigger_plate.visible = not has_sprite_visual


func _find_trigger_target(master:ball) -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = trigger_radius * trigger_radius
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _can_affect_target(target,master):
			continue
		var distance_sq:float = global_position.distance_squared_to(target.global_position)
		if distance_sq <= nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = target
	return nearest


func _can_affect_target(target:ball,master:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if not target.is_combat_targetable() or target == master:
		return false
	if not Game.Game_Settings.Have_Team_Damage and Team != "" and target.Team != "" and target.Team == Team:
		return false
	return true


func _trigger(target:ball,master:ball) -> void:
	if _triggered:
		return
	_triggered = true
	_closed_left = maxf(root_duration,0.05)
	_trapped_target = target

	var outgoing:float = master.effective_outgoing_damage(damage_amount) if master != null else damage_amount
	if outgoing > 0.0:
		target.receive_spatial_damage(
			outgoing,
			{"shape":"circle","center":global_position,"radius":maxf(trigger_radius,1.0),"source":self},
			false
		)

	if target.health > 0:
		# 捕兽夹是“禁锢”，不是眩晕：只把移动速度压到 0。
		# 不设置 dizziness，也不创建 stun_visual，因此目标仍可攻击/施法/受击。
		_acquire_trap_root(target)

	_show_trigger_everywhere(_closed_left)
	_play_named_sfx_everywhere("捕兽夹触发",0.0,randf_range(0.98,1.03))


func _acquire_trap_root(target:ball) -> void:
	if target == null or not is_instance_valid(target) or _root_acquired:
		return

	_trapped_target = target
	_root_acquired = true
	_fallback_saved_speed = maxf(target.Speed,0.0)
	_apply_root_buff(maxf(root_duration,0.05))

	# 触发当帧立即停下；持续禁锢则由 Speed Set Buff 保证。
	target.Speed = 0.0
	target.velocity = Vector2.ZERO


func _enforce_trap_root() -> void:
	if not _root_acquired or _trapped_target == null or not is_instance_valid(_trapped_target):
		return

	# 刷新同一个来源的 Set Buff，避免 World 的“每帧恢复默认属性”把 Speed 抬回去。
	# 使用当前夹子剩余闭合时间，使 Buff 与夹子的生命周期保持一致。
	_apply_root_buff(maxf(_closed_left + 0.10,0.10))
	_trapped_target.Speed = 0.0
	_trapped_target.velocity = Vector2.ZERO


func _apply_root_buff(duration:float) -> void:
	if _trapped_target == null or not is_instance_valid(_trapped_target):
		return
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("new_buff"):
		world.call(
			"new_buff",
			_trapped_target,
			self,
			ROOT_BUFF_NAME,
			Buff.new(3,duration,Buff.Buff_types.Speed,0.0,Buff.Algorithms.Set),
			"cover"
		)


func _release_trap_control() -> void:
	var target:ball = _trapped_target
	_trapped_target = null
	if not _root_acquired:
		return
	_root_acquired = false

	if target == null or not is_instance_valid(target):
		return

	var world:Node = get_tree().current_scene
	if world != null and world.has_method("new_buff"):
		# 只删除“这个捕兽夹实例”作为来源的 Buff；多个夹子同时禁锢时互不误删。
		world.call("new_buff",target,self,ROOT_BUFF_NAME,Buff.new(),"delete")
	else:
		# 极端兼容路径：若当前场景没有 World.new_buff，至少恢复触发前速度。
		target.Speed = _fallback_saved_speed

	# 解除瞬间清掉残留 velocity；下一 physics tick 会按正常 Speed 重新计算移动。
	target.velocity = Vector2.ZERO


func _show_trigger_everywhere(hold_duration:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_trigger.rpc(hold_duration)
	else:
		_rpc_show_trigger(hold_duration)


@rpc("authority","call_local","reliable")
func _rpc_show_trigger(hold_duration:float) -> void:
	# 触发时只切换为闭合图片，不再生成白圈、连线等命中特效。
	_triggered = true
	_closed_left = maxf(hold_duration,0.05)
	_apply_trap_texture(true)


func _play_named_sfx_everywhere(sfx_name:String,volume_db:float,pitch:float) -> void:
	var params:Dictionary = {
		"volume": volume_db,
		"pitch": pitch,
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,false,true)
	else:
		Audios.play_sfx(sfx_name,params,false,true)


func _resolve_master() -> ball:
	if Master_name.is_empty():
		return null
	var world:Node = get_tree().current_scene
	if world != null:
		var direct:Node = world.get_node_or_null(NodePath(Master_name))
		if direct is ball:
			return direct as ball
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and str(node.name) == Master_name:
			return node as ball
	return null
