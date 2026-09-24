extends Node
# 移动约束组件，不暂停状态机、不修改攻击/技能/生命与阵营。
var actor:ball
var boat:ball
var slot:int = 0
var released:bool = false
var saved:Dictionary = {}
var _prev_pose:Vector2 = Vector2.ZERO
var _prev_boat_rot:float = 0.0
var _pose_ready:bool = false

func setup(passenger:ball,carrier:ball,index:int) -> void:
	actor = passenger
	boat = carrier
	slot = index
	saved = {"layer":actor.collision_layer,"mask":actor.collision_mask,"rotation":actor.graphics.rotation,"position":actor.graphics.position,"z":actor.graphics.z_index,"relative":actor.graphics.z_as_relative,"flip":actor.is_character_visual_flipped_h()}
	actor.set_meta("mc_boat_rider",weakref(self))
	process_physics_priority = 100000
	process_priority = 100000
	apply_pose()

func apply_pose() -> bool:
	if released or not is_instance_valid(actor) or not is_instance_valid(boat): return false
	if actor.health <= 0 or boat.health <= 0:
		release()
		return false
	# 船上来源只能伤血，不能通过击退控制器锁住乘客攻击/技能。
	for effect:Node in actor.get_children():
		if effect.get_script() == actor.KNOCKBACK_EFFECT_SCRIPT and boat.source_is_onboard(effect.source): effect._finish(false)
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.global_position = boat.seat_position(slot)
	# 乘客精灵的脚底在身体中心下方约半个碰撞盒；把图形节点抬高，
	# 让脚底落到座位锚点（舱底）而不是垂在船体下方。
	var pose:Vector2 = saved.position+Vector2(0.0,-_feet_lift())
	var boat_rot:float = boat.graphics.global_rotation
	# 视觉自由乘客（如重锤砸地腾空：每帧写 graphics 的位置/旋转偏移）用增量合成：
	# 只叠加座位姿态自身的变化量，乘客动画写入的偏移完整保留；
	# 其余乘客（活塞等）保持硬覆盖，视觉严格随船。
	var freedom:bool = actor.has_method("rider_graphics_freedom") and actor.rider_graphics_freedom()
	if not _pose_ready or not freedom:
		actor.graphics.position = pose
		actor.graphics.global_rotation = boat_rot
	else:
		actor.graphics.position += pose-_prev_pose
		actor.graphics.global_rotation += boat_rot-_prev_boat_rot
	_prev_pose = pose
	_prev_boat_rot = boat_rot
	_pose_ready = true
	actor.velocity = boat.velocity
	actor.Repel = Vector2.ZERO
	actor.direction = boat.facing
	actor.graphics.z_as_relative = false
	actor.graphics.z_index = mini(boat.graphics.z_index+2,89)
	# 乘客坐在舱内、脚不落地，不该在船板上再投一个脚底影子；影子由船体自己投。
	# 影子节点是延迟创建的（换图/AutoFit 会重建），所以每帧都检查一次而不是只在登船时关。
	_set_shadow_visible(false)
	# 左右镜像交给乘客自己的视觉逻辑：direction 已跟随船头，普通角色会按它镜像；
	# 活塞这类自旋转部件在 visual_mob 里保持 flip 为 false，座位组件不再强行写镜像。
	return true

func _set_shadow_visible(visible:bool) -> void:
	if not is_instance_valid(actor): return
	var shadow:Node2D = actor.get("_character_ground_shadow") as Node2D
	if shadow != null and is_instance_valid(shadow) and shadow.visible != visible:
		shadow.visible = visible

func _physics_process(_delta:float) -> void:
	if not is_instance_valid(boat) or not is_instance_valid(actor) or boat.health <= 0 or actor.health <= 0:
		release()
	else:
		apply_pose()
func _feet_lift() -> float:
	if not is_instance_valid(actor): return 0.0
	var cs:CollisionShape2D = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var half:float = 10.0
	if cs != null and cs.shape != null:
		if cs.shape is RectangleShape2D:
			half = (cs.shape as RectangleShape2D).size.y*cs.global_scale.y*0.5
		elif cs.shape is CircleShape2D:
			half = (cs.shape as CircleShape2D).radius*cs.global_scale.y
	var sy:float = actor.scale.y if absf(actor.scale.y) > 0.0001 else 1.0
	return maxf(half-2.0,0.0)/sy
func _process(_delta:float) -> void:
	apply_pose()

func release() -> void:
	if released: return
	released = true
	if is_instance_valid(actor):
		actor.collision_layer = int(saved.get("layer",actor.collision_layer))
		actor.collision_mask = int(saved.get("mask",actor.collision_mask))
		actor.graphics.rotation = float(saved.get("rotation",0.0))
		actor.graphics.position = saved.get("position",Vector2.ZERO)
		actor.graphics.z_index = int(saved.get("z",0))
		actor.graphics.z_as_relative = bool(saved.get("relative",true))
		actor.set_character_visual_flip_h(bool(saved.get("flip",false)))
		_set_shadow_visible(true)
		actor.remove_meta("mc_boat_rider")
		actor.velocity = Vector2.ZERO
		actor.Repel = Vector2.ZERO
		if is_instance_valid(boat) and boat.is_inside_tree() and actor.is_inside_tree():
			actor.global_position = boat.disembark_position(actor,slot)
	queue_free()
func _exit_tree() -> void:
	if not released: release()
