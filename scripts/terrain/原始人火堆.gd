extends Node2D

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const WAR_GODDESS_BURN_SCRIPT:Script = preload("res://scripts/status/战争女神_灼烧.gd")
const WAR_GODDESS_BURN_NODE_NAME:StringName = &"WarGoddessBurnStatus"

@export_category("原始人火堆")
@export_range(0.0,20.0,0.05) var heat_damage_per_second_multiplier:float = 2.6666667
@export_range(0.1,2.0,0.05) var heat_tick_interval:float = 0.5
@export_range(0.0,30.0,0.05) var core_contact_damage_multiplier:float = 13.3333333
@export_range(0.2,10.0,0.1) var burn_duration:float = 3.0
@export_range(0.1,2.0,0.05) var burn_tick_interval:float = 0.5
@export_range(0.0,10.0,0.05) var burn_tick_damage_multiplier:float = 1.0

@export_category("原始人火堆 - 图片状态")
@export var unlit_texture:Texture2D
@export var lit_texture_1:Texture2D
@export var lit_texture_2:Texture2D
@export_range(0.05,1.0,0.05) var fire_frame_interval:float = 0.20

@onready var heat_area:Area2D = $HeatArea
@onready var core_area:Area2D = $CoreArea
@onready var heat_collision_shape:CollisionShape2D = $HeatArea/CollisionShape2D
@onready var core_collision_shape:CollisionShape2D = $CoreArea/CollisionShape2D
@onready var flame_visual:Node2D = $FlameVisual
@onready var fire_image:Sprite2D = $FlameVisual/Image
@onready var heat_range_ring:Line2D = $HeatRangeRing

var owner_primitive:ball = null
var lit:bool = true
var _heat_tick_left:float = 0.5
var _fire_frame_elapsed:float = 0.0
var _fire_frame_index:int = 0

func _owner_attack_damage(multiplier:float) -> float:
	if owner_primitive != null and is_instance_valid(owner_primitive):
		return owner_primitive.attack_damage(multiplier)
	return 0.0


func _ready() -> void:
	add_to_group("PrimitiveCampfire")
	# V85：Reset 的统一临时战斗节点清理会扫描这个组。
	add_to_group("BattleTransient")
	heat_area.set_meta("threat_debug_damage",_owner_attack_damage(heat_damage_per_second_multiplier))
	core_area.set_meta("threat_debug_damage",_owner_attack_damage(core_contact_damage_multiplier))
	core_area.body_entered.connect(_on_core_body_entered)
	_sync_range_ring_to_heat_shape()
	set_lit(true)


func _heat_radius() -> float:
	if heat_collision_shape != null and heat_collision_shape.shape is CircleShape2D:
		return maxf((heat_collision_shape.shape as CircleShape2D).radius,0.0)
	return 38.0

func _core_radius() -> float:
	if core_collision_shape != null and core_collision_shape.shape is CircleShape2D:
		return maxf((core_collision_shape.shape as CircleShape2D).radius,0.0)
	return 15.0

# V98：红圈直接由真实 HeatArea/CircleShape2D 半径生成。
# 以后在 Inspector 调伤害圈半径时，运行时红圈与真实判定仍保持一致。
func _sync_range_ring_to_heat_shape() -> void:
	if heat_range_ring == null:
		return
	var radius:float = _heat_radius()
	var points := PackedVector2Array()
	var segment_count:int = 40
	for index:int in range(segment_count):
		var angle:float = TAU * float(index) / float(segment_count)
		points.append(Vector2(cos(angle),sin(angle)) * radius)
	heat_range_ring.points = points
	heat_range_ring.closed = true

func set_lit(value:bool) -> void:
	lit = value
	_fire_frame_elapsed = 0.0
	_fire_frame_index = 0
	if flame_visual != null:
		# 熄灭时仍然必须显示“熄灭状态”图片，不能隐藏整个火堆视觉。
		flame_visual.visible = true
	_update_fire_texture()
	if heat_range_ring != null:
		heat_range_ring.visible = lit
	if heat_area != null:
		# set_lit(false) 可能来自 body_entered 物理回调，延迟切 monitoring 避免查询刷新期间修改监测状态。
		heat_area.set_deferred("monitoring",lit)
	if core_area != null:
		core_area.monitoring = true

func _update_fire_texture() -> void:
	if fire_image == null:
		return
	# V88：优先交给专用 @tool 视觉脚本。每张图片有独立 position/scale，
	# 运行时切帧不会再把用户在编辑器里调好的构图覆盖掉。
	if fire_image.has_method("apply_runtime_state"):
		fire_image.call("apply_runtime_state",lit,_fire_frame_index)
		return
	# 兼容旧场景/脚本未挂载时的后备路径。
	var next_texture:Texture2D = unlit_texture
	if lit:
		next_texture = lit_texture_1 if _fire_frame_index == 0 else lit_texture_2
	if next_texture != null:
		fire_image.texture = next_texture

func _animate_fire(delta:float) -> void:
	if not lit or fire_image == null:
		return
	_fire_frame_elapsed += delta
	var interval:float = maxf(fire_frame_interval,0.05)
	while _fire_frame_elapsed >= interval:
		_fire_frame_elapsed -= interval
		_fire_frame_index = 1 - _fire_frame_index
		_update_fire_texture()

func _physics_process(delta:float) -> void:
	# V85：火堆不能成为脱离主人的孤儿节点。即便角色死亡流程被某个状态打断，
	# 只要主人 0HP、离开场景树或已经排队删除，火堆都会主动删除自己。
	if owner_primitive == null or not is_instance_valid(owner_primitive):
		queue_free()
		return
	if owner_primitive.health <= 0 or owner_primitive.is_queued_for_deletion() or not owner_primitive.is_inside_tree():
		queue_free()
		return
	# 燃烧视觉在所有客户端独立播放；游戏伤害仍只由 authority 结算。
	_animate_fire(delta)
	if not lit:
		return
	if not owner_primitive.is_multiplayer_authority() or not owner_primitive.is_combat_runtime_active():
		return
	_heat_tick_left -= delta
	while _heat_tick_left <= 0.0:
		_heat_tick_left += maxf(heat_tick_interval,0.05)
		var tick_damage:float = _owner_attack_damage(heat_damage_per_second_multiplier) * maxf(heat_tick_interval,0.05)
		for raw:Node2D in heat_area.get_overlapping_bodies():
			if raw is ball and TOOLS.is_enemy(owner_primitive,raw as ball):
				var applied:bool = (raw as ball).receive_fire_spatial_damage(
					tick_damage,
					{"shape":"circle","center":global_position,"radius":_heat_radius(),"source":owner_primitive},
					false,
					false
				)
				if applied and owner_primitive.has_method("play_war_burn_tick_sfx"):
					owner_primitive.call("play_war_burn_tick_sfx",(raw as ball).global_position)

func _on_core_body_entered(body:Node2D) -> void:
	if not body is ball or owner_primitive == null or not is_instance_valid(owner_primitive):
		return
	var target:ball = body as ball
	if not lit:
		if target.has_method("is_primitive_character") and TOOLS.same_side(owner_primitive,target):
			set_lit(true)
		return
	if not TOOLS.is_enemy(owner_primitive,target):
		return
	if not owner_primitive.is_multiplayer_authority():
		return
	var applied:bool = target.receive_fire_spatial_damage(
		_owner_attack_damage(core_contact_damage_multiplier),
		{"shape":"circle","center":global_position,"radius":_core_radius(),"source":owner_primitive},
		false,
		false
	)
	if applied:
		if owner_primitive.has_method("play_war_burn_tick_sfx"):
			owner_primitive.call("play_war_burn_tick_sfx",target.global_position)
		_apply_war_goddess_burn(target)
	if owner_primitive.has_method("request_fire_dash"):
		owner_primitive.call("request_fire_dash",self)
	set_lit(false)

func _apply_war_goddess_burn(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		return
	var existing:Node = target.get_node_or_null(NodePath(String(WAR_GODDESS_BURN_NODE_NAME)))
	if existing != null and existing.has_method("refresh"):
		existing.call("refresh",owner_primitive,burn_duration,_owner_attack_damage(burn_tick_damage_multiplier))
		return
	var status:Node2D = WAR_GODDESS_BURN_SCRIPT.new() as Node2D
	if status == null:
		return
	status.name = WAR_GODDESS_BURN_NODE_NAME
	status.top_level = true
	target.add_child(status,true)
	status.global_position = target.global_position
	status.call("setup",target,owner_primitive,burn_duration,burn_tick_interval,_owner_attack_damage(burn_tick_damage_multiplier))
