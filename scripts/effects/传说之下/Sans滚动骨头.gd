extends Node2D
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")

# Sans Boss 特殊化：墙面滚动骨头（V49）
# - 骨头根部始终插在地图墙线上；骨头本体朝场内伸出。
# - 整根骨头只沿墙的切线方向移动，从地图外滚入，再从另一端离开。
# - 不再使用“完整双头骨在场内自由旋转飞行”的旧实现。
# - 只由 authority 结算 1 点帧伤 + KARMA；所有端播放同一墙面滚动视觉。

const SANS_ATLAS:Texture2D = preload("res://Images/characters/传说之下/Sans/Sans_spritesheet.png")
const BONE_HEAD_REGION:Rect2 = Rect2(399,574,12,10)
const BONE_BODY_REGION:Rect2 = Rect2(401,580,6,1)
const BONE_HEAD_HEIGHT:float = 10.0
const BONE_BODY_ATTACH_Y:float = 6.0
const BONE_HEAD_LATERAL_OFFSET:float = 1.0

var source:ball = null
var source_team:String = ""
var travel_direction:Vector2 = Vector2.RIGHT
var travel_speed:float = 320.0
var travel_distance:float = 800.0
var bone_length:float = 64.0
var visual_scale:float = 1.0
var first_contact_karma:float = 5.0
var held_contact_karma:float = 1.0

var _distance_moved:float = 0.0
var _head:Sprite2D = null
var _body:Polygon2D = null
var _damage_area:Area2D = null
var _damage_shape:CollisionShape2D = null
var _contact_started:Dictionary = {}
var _damage_tick_toggle:bool = false


func configure(
	actor:ball,
	root_position:Vector2,
	inward_direction:Vector2,
	move_direction:Vector2,
	distance:float,
	speed:float,
	length:float,
	size_scale:float = 1.0,
	karma_first:float = 5.0,
	karma_held:float = 1.0
) -> void:
	source = actor
	source_team = actor.Team if actor != null else ""
	global_position = root_position
	var inward:Vector2 = inward_direction.normalized() if inward_direction.length_squared() > 0.000001 else Vector2.UP
	travel_direction = move_direction.normalized() if move_direction.length_squared() > 0.000001 else Vector2.RIGHT
	travel_distance = maxf(distance,24.0)
	travel_speed = maxf(speed,20.0)
	bone_length = maxf(length,8.0)
	visual_scale = clampf(size_scale,0.45,2.50)
	first_contact_karma = maxf(karma_first,0.0)
	held_contact_karma = maxf(karma_held,0.0)

	# 和普通 Sans 地刺骨头一致：local -Y 永远朝地图内部，因此 local 0 就是埋在墙里的根部。
	rotation = inward.angle() + PI * 0.5
	z_as_relative = false
	z_index = 92
	_build_visual()
	_build_hitbox()


func _build_visual() -> void:
	_body = Polygon2D.new()
	_body.name = "Body"
	_body.color = Color.WHITE
	_body.z_index = 1
	add_child(_body)

	_head = Sprite2D.new()
	_head.name = "Head"
	_head.texture = SANS_ATLAS
	_head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_head.centered = true
	_head.region_enabled = true
	_head.region_filter_clip_enabled = true
	_head.region_rect = BONE_HEAD_REGION
	_head.z_index = 2
	_head.scale = Vector2.ONE * visual_scale
	add_child(_head)

	var scaled_head_height:float = BONE_HEAD_HEIGHT * visual_scale
	var scaled_attach_y:float = BONE_BODY_ATTACH_Y * visual_scale
	var half_width:float = BONE_BODY_REGION.size.x * 0.5 * visual_scale
	_head.position = Vector2(BONE_HEAD_LATERAL_OFFSET * visual_scale,-bone_length + scaled_head_height * 0.5)
	var body_tip_y:float = minf(-bone_length + scaled_attach_y,-0.001)
	_body.polygon = PackedVector2Array([
		Vector2(-half_width,0.0),
		Vector2( half_width,0.0),
		Vector2( half_width,body_tip_y),
		Vector2(-half_width,body_tip_y),
	])


func _build_hitbox() -> void:
	_damage_area = Area2D.new()
	_damage_area.name = "RollingWallBoneDamageArea"
	_damage_area.collision_layer = 0
	_damage_area.collision_mask = 2
	_damage_area.monitoring = true
	_damage_area.monitorable = false
	add_child(_damage_area)

	_damage_shape = CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	# 命中框从墙根一直延伸到骨头尖端；宽度略窄于视觉，避免透明边缘误伤。
	shape.size = Vector2(maxf(7.0 * visual_scale,3.0),bone_length)
	_damage_shape.shape = shape
	_damage_shape.position = Vector2(0.0,-bone_length * 0.5)
	_damage_area.add_child(_damage_shape)


func _physics_process(delta:float) -> void:
	if Game.now_stop_state:
		return
	var safe_delta:float = maxf(delta,0.0)
	var step:float = travel_speed * safe_delta
	global_position += travel_direction * step
	_distance_moved += step

	if _should_retire():
		queue_free()
		return

	if source == null or not is_instance_valid(source) or not source.is_multiplayer_authority():
		return
	if source.health <= 0 or source.is_damage_output_disabled():
		return
	if _damage_area == null or not _damage_area.monitoring:
		return

	# 和现有 Sans 骨头/龙骨炮一致：直接接触每两个 physics tick 结算一次 1 点帧伤。
	_damage_tick_toggle = not _damage_tick_toggle
	if not _damage_tick_toggle:
		return

	for raw_body:Node2D in _damage_area.get_overlapping_bodies():
		if not raw_body is ball:
			continue
		var target:ball = raw_body as ball
		if not _is_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		var karma_amount:float = held_contact_karma
		if not _contact_started.has(target_id):
			_contact_started[target_id] = true
			karma_amount = first_contact_karma
		source.call("apply_sans_frame_hit",target,target.global_position,karma_amount)


func screen_bounds() -> Rect2:
	var transform:Transform2D=get_global_transform_with_canvas()
	var half_width:float=7.0*visual_scale
	var result:Rect2=Rect2(transform*Vector2(-half_width,-bone_length),Vector2.ZERO)
	for point:Vector2 in [Vector2(half_width,-bone_length),Vector2(-half_width,0.0),Vector2(half_width,0.0)]:
		result=result.expand(transform*point)
	return result
func _past_screen_exit() -> bool:
	var bounds:Rect2=screen_bounds()
	var screen:Rect2=get_viewport_rect().grow(2.0)
	var direction:Vector2=get_canvas_transform().basis_xform(travel_direction)
	if absf(direction.x)>=absf(direction.y):
		return bounds.position.x>screen.end.x if direction.x>0.0 else bounds.end.x<screen.position.x
	return bounds.position.y>screen.end.y if direction.y>0.0 else bounds.end.y<screen.position.y
func _should_retire() -> bool:
	# Reaching the old map-distance limit is not enough while still visible.
	return _distance_moved>=travel_distance and _past_screen_exit()

func _is_enemy(target:ball) -> bool:
	if PROJECTILE_CONTACT.ignores(target): return false
	if target == null or target == source or target.health <= 0:
		return false
	if target.has_method("is_combat_targetable") and not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and not source_team.is_empty()
		and not target.Team.is_empty()
		and source_team == target.Team
	):
		return false
	return true
