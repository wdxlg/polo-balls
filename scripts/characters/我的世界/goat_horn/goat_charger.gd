extends Node2D
## 山羊角召来的山羊：瞬时技能实体（无生命、不可选中、不计存续），全程穿过墙体与障碍。
## 权威端真实移动与结算：从屏幕外加速冲向目标，首次冲撞按速度结算伤害与击退，
## 持续重叠时周期推撞；撞到目标或错过后不再转向，加速冲出屏幕后释放。
## 客户端只按山羊角下发的状态外推显示。伤害与击退来源始终是山羊角本体。
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const AUDIO = preload("res://scripts/characters/我的世界/goat_horn/goat_horn_audio.gd")
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/goat_horn/goat/goat_frames.tres")

enum Phase { CHARGE, EXIT }

# 以下两项是角色根缩放为 1 时的尺寸，实际按山羊角本体的根缩放换算。
# 原版山羊与羊碰撞箱相同（0.9×1.3 格），显示尺寸对齐本项目的羊角色（约 20×26 世界像素 @0.2）。
const BODY_RADIUS_UNIT:float = 48.0
const SPRITE_SCALE:float = 1.1
# 帧画布 176×176，身体包围盒中心在 (85.5,103)：偏移后节点原点就是身体中心（判定圆心）。
const SPRITE_OFFSET:Vector2 = Vector2(2.5,-15.0)
const ENTER_SPEED:float = 150.0
const CHARGE_ACCEL:float = 220.0
const CHARGE_MAX_SPEED:float = 360.0
const TURN_RATE:float = 3.0
const EXIT_ACCEL:float = 500.0
const EXIT_MAX_SPEED:float = 760.0
const IMPACT_REFERENCE_SPEED:float = 400.0
const IMPACT_RATIO_MAX:float = 1.3
const RAM_SPEED_KEEP:float = 0.72
const PUSH_INTERVAL:float = 0.16
const CONTACT_RELEASE_MARGIN:float = 6.0
const BOW_LEAD_TIME:float = 0.12
const MAX_LIFE:float = 16.0
# 世界的地图外遮罩在绝对 z=90 用背景快照盖住越界视觉；山羊从屏幕外进出，必须画在它之上。
const DRAW_Z:int = 91
const OFFSCREEN_MARGIN:float = 140.0
const PRE_RAM_CHANCE:float = 0.38
const STEP_STRIDE_AT_500:float = 0.2

var goat_id:int = 0
var heading:Vector2 = Vector2.LEFT
var speed:float = ENTER_SPEED
var phase:int = Phase.CHARGE
var bowed:bool = false
var life:float = 0.0
var unit_scale:float = 1.0
var body_radius:float = BODY_RADIUS_UNIT

var _horn_ref:WeakRef
var _target_ref:WeakRef
var _authority:bool = false
var _contacts:Dictionary = {}
var _rammed_target:bool = false
var _seen_on_screen:bool = false
var _step_wait:float = 0.0
var _sprite:AnimatedSprite2D
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()
# 客户端外推：最近一次网络位置与其之后经过的时间。
var _net_position:Vector2 = Vector2.ZERO
var _net_age:float = 0.0


func setup_authority(horn:Node2D,id:int,target:Node2D,start:Vector2,seed_value:int) -> void:
	_authority = true
	goat_id = id
	_horn_ref = weakref(horn)
	_adopt_scale(horn)
	_target_ref = weakref(target) if is_instance_valid(target) else null
	position = start
	_net_position = start
	_rng.seed = seed_value
	var aim:Vector2 = (U.point(target,start) - start) if is_instance_valid(target) else Vector2.ZERO
	heading = aim.normalized() if aim.length_squared() > 0.01 else Vector2.LEFT
	speed = ENTER_SPEED
	name = "GoatHornGoat_%d" % id
	add_to_group("GoatHornGoat")
	add_to_group("AI_Hazard")


func setup_puppet(horn:Node2D,id:int,start:Vector2,direction:Vector2,speed_value:float,flags:int) -> void:
	_authority = false
	goat_id = id
	_horn_ref = weakref(horn)
	_adopt_scale(horn)
	position = start
	_net_position = start
	heading = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.LEFT
	speed = speed_value
	_apply_flags(flags)
	name = "GoatHornGoat_%d" % id
	add_to_group("GoatHornGoat")
	add_to_group("AI_Hazard")


func _adopt_scale(horn:Node2D) -> void:
	unit_scale = absf(horn.global_scale.x) if is_instance_valid(horn) and horn.global_scale.x != 0.0 else 1.0
	body_radius = BODY_RADIUS_UNIT * unit_scale


func _ready() -> void:
	z_as_relative = false
	z_index = DRAW_Z
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = FRAMES
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * SPRITE_SCALE * unit_scale
	_sprite.offset = SPRITE_OFFSET
	add_child(_sprite)
	_sprite.play(&"run")
	_sprite.frame = goat_id % FRAMES.get_frame_count(&"run")
	_update_visual()
	set_physics_process(_authority)


func horn() -> Node2D:
	var node:Variant = _horn_ref.get_ref() if _horn_ref != null else null
	return node as Node2D if is_instance_valid(node) and node.is_inside_tree() else null


func network_flags() -> int:
	return (1 if bowed else 0) | (2 if phase == Phase.EXIT else 0)


func _apply_flags(flags:int) -> void:
	bowed = (flags & 1) != 0
	phase = Phase.EXIT if (flags & 2) != 0 else Phase.CHARGE


func _runtime_active(owner_horn:Node2D) -> bool:
	return owner_horn != null and bool(owner_horn.call(&"is_combat_runtime_active"))


func _hostile(owner_horn:Node2D) -> bool:
	return owner_horn != null and float(owner_horn.get("health")) > 0.0 and not bool(owner_horn.call(&"is_damage_output_disabled"))


func impact_ratio(speed_value:float = -1.0) -> float:
	return clampf((speed if speed_value < 0.0 else speed_value) / IMPACT_REFERENCE_SPEED,0.0,IMPACT_RATIO_MAX)


func _physics_process(delta:float) -> void:
	if not _authority: return
	var owner_horn:Node2D = horn()
	if owner_horn == null:
		queue_free()
		return
	if not _runtime_active(owner_horn): return
	life += delta
	if not _hostile(owner_horn) and phase == Phase.CHARGE: begin_exit()
	if phase == Phase.CHARGE: _steer(owner_horn,delta)
	if phase == Phase.CHARGE: speed = minf(speed + CHARGE_ACCEL * delta,CHARGE_MAX_SPEED)
	else: speed = minf(speed + EXIT_ACCEL * delta,EXIT_MAX_SPEED)
	var from:Vector2 = global_position
	var to:Vector2 = from + heading * speed * delta
	global_position = to
	if _hostile(owner_horn): _resolve_contacts(owner_horn,from,to,delta)
	else: _contacts.clear()
	if phase == Phase.CHARGE and _rammed_target and _contacts.is_empty(): begin_exit()
	_update_bow()
	_step_sounds(owner_horn,delta)
	var view:Rect2 = view_rect(self)
	if phase == Phase.EXIT and view.size.x > 1.0 and not view.grow(OFFSCREEN_MARGIN).has_point(global_position):
		queue_free()
	elif life >= MAX_LIFE:
		queue_free()


func _target() -> ball:
	var node:Variant = _target_ref.get_ref() if _target_ref != null else null
	return node as ball if is_instance_valid(node) else null


func _steer(owner_horn:Node2D,delta:float) -> void:
	var target:ball = _target()
	if target == null or not U.enemy(owner_horn as ball,target) or target.health <= 0:
		target = owner_horn.call(&"pick_goat_target") as ball
		_target_ref = weakref(target) if target != null else null
		if target == null:
			begin_exit()
			return
	var to_target:Vector2 = U.point(target,global_position) - global_position
	var reach:float = body_radius + U.radius(target)
	# 已从目标身边冲过（目标落到身后）就不再回头，直接加速离场。
	if to_target.dot(heading) < 0.0 and to_target.length() > reach:
		begin_exit()
		return
	if to_target.length_squared() < 0.01: return
	var turn:float = clampf(heading.angle_to(to_target),-TURN_RATE * delta,TURN_RATE * delta)
	heading = heading.rotated(turn).normalized()


func begin_exit() -> void:
	phase = Phase.EXIT


func _resolve_contacts(owner_horn:Node2D,from:Vector2,to:Vector2,delta:float) -> void:
	var source:ball = owner_horn as ball
	var touched:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(source,node) or U.wall_node(node): continue
		var victim:ball = node as ball
		var id:int = victim.get_instance_id()
		var reach:float = body_radius + U.radius(victim)
		if _contacts.has(id):
			if global_position.distance_to(U.point(victim,global_position)) > reach + CONTACT_RELEASE_MARGIN: continue
			touched[id] = true
			_contacts[id] = float(_contacts[id]) - delta
			if float(_contacts[id]) <= 0.0:
				_contacts[id] = PUSH_INTERVAL
				_push(source,victim)
			continue
		if U.segment_distance(ball.body_point_seg(victim,from,to),from,to) > reach: continue
		touched[id] = true
		_contacts[id] = PUSH_INTERVAL
		_ram(source,victim,to)
	for id:Variant in _contacts.keys():
		if not touched.has(id): _contacts.erase(id)


func _knockback_direction(victim:ball) -> Vector2:
	# 正面顶开为主，偏离中线的目标略向两侧分开，避免被山羊“吸”在额头上。
	var side:Vector2 = U.point(victim,global_position) - global_position
	var lateral:Vector2 = side - heading * side.dot(heading)
	var dir:Vector2 = heading + lateral.normalized() * 0.2 if lateral.length_squared() > 1.0 else heading
	return dir.normalized()


func _ram(source:ball,victim:ball,point:Vector2) -> void:
	var r:float = impact_ratio()
	var dealt:bool = U.damage(source,victim,source.attack_damage(0.35 + 1.25 * r),point)
	if dealt:
		victim.apply_knockback(_knockback_direction(victim),30.0 + 110.0 * r,160.0 + 520.0 * r,0.65,0.0,
			{"source":source,"max_wall_bounces":1,"collision_damage":source.attack_damage(0.25 + 0.8 * r),"collision_damage_wall_only":true,"redirect_blend_time":0.0})
		source.call(&"emit_goat_sound",AUDIO.KIND_IMPACT,_rng.randi_range(0,AUDIO.variant_count(AUDIO.KIND_IMPACT) - 1),point)
	speed *= RAM_SPEED_KEEP
	if victim == _target(): _rammed_target = true


func _push(source:ball,victim:ball) -> void:
	var r:float = impact_ratio()
	if not U.damage(source,victim,source.attack_damage(0.12 + 0.30 * r),U.point(victim,global_position)): return
	victim.apply_knockback(_knockback_direction(victim),16.0 + 44.0 * r,maxf(speed * 1.1,160.0 + 520.0 * r),0.65,0.0,
		{"source":source,"max_wall_bounces":1,"collision_damage":source.attack_damage(0.1 + 0.3 * r),"collision_damage_wall_only":true,"redirect_blend_time":0.0})


func _update_bow() -> void:
	var target:ball = _target()
	bowed = not _contacts.is_empty() or (phase == Phase.CHARGE and target != null and global_position.distance_to(U.point(target,global_position)) <= body_radius + U.radius(target) + speed * BOW_LEAD_TIME)


func _step_sounds(owner_horn:Node2D,delta:float) -> void:
	var view:Rect2 = view_rect(self)
	var visible_now:bool = view.size.x > 1.0 and view.has_point(global_position)
	if visible_now and not _seen_on_screen:
		_seen_on_screen = true
		if phase == Phase.CHARGE and _rng.randf() < PRE_RAM_CHANCE:
			owner_horn.call(&"emit_goat_sound",AUDIO.KIND_PRE_RAM,_rng.randi_range(0,AUDIO.variant_count(AUDIO.KIND_PRE_RAM) - 1),global_position)
	_step_wait = maxf(_step_wait - delta,0.0)
	if not visible_now or _step_wait > 0.0 or speed <= 1.0: return
	var index:int = _rng.randi_range(0,AUDIO.variant_count(AUDIO.KIND_STEP) - 1)
	if not bool(owner_horn.call(&"emit_goat_sound",AUDIO.KIND_STEP,index,global_position)):
		_step_wait = 0.05
		return
	# 跑得越快步点越密，但同一只羊两次脚步开始的间隔不短于上一声实际时长。
	_step_wait = maxf(AUDIO.length(AUDIO.KIND_STEP,index),STEP_STRIDE_AT_500 * 500.0 / maxf(speed,1.0))


## 客户端：收到权威状态。
func apply_network_state(point:Vector2,direction:Vector2,speed_value:float,flags:int) -> void:
	_net_position = point
	_net_age = 0.0
	if direction.length_squared() > 0.0001: heading = direction.normalized()
	speed = speed_value
	_apply_flags(flags)


func _process(delta:float) -> void:
	var owner_horn:Node2D = horn()
	var running:bool = _runtime_active(owner_horn)
	if not _authority and running:
		_net_age = minf(_net_age + delta,0.25)
		var predicted:Vector2 = _net_position + heading * speed * _net_age
		global_position = global_position.lerp(predicted,1.0 - exp(-18.0 * delta))
	_update_visual(running)


func _update_visual(running:bool = true) -> void:
	if _sprite == null: return
	var clip:StringName = &"ram" if bowed else &"run"
	if _sprite.animation != clip:
		var keep:int = _sprite.frame
		_sprite.play(clip)
		_sprite.frame = keep % FRAMES.get_frame_count(clip)
	_sprite.speed_scale = clampf(speed / 500.0,0.5,2.2) if running else 0.0
	# 原图朝左；向右跑时镜像。按竖直分量轻微低头/抬头，表达斜向冲刺。
	var flip:bool = heading.x > 0.0
	_sprite.flip_h = flip
	var tilt:float = atan2(heading.y,absf(heading.x)) * 0.3
	_sprite.rotation = tilt if flip else -tilt


func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	var owner_horn:Node2D = horn()
	if owner_horn == null or not _hostile(owner_horn): return {}
	return {"shape":"circle","position":global_position,"velocity":heading * speed,"radius":body_radius,
		"damage":(owner_horn as ball).attack_damage(0.35 + 1.25 * impact_ratio()),"source":owner_horn,"danger_duration":0.1,"kind":"goat_ram"}


## 权威端视角（镜头可见世界矩形）；无镜头/无视口时退回当前地图矩形。
static func view_rect(node:Node) -> Rect2:
	if node == null or not node.is_inside_tree(): return Rect2()
	var viewport:Viewport = node.get_viewport()
	if viewport != null:
		var screen:Rect2 = viewport.get_visible_rect()
		if screen.size.x > 1.0 and screen.size.y > 1.0:
			var inverse:Transform2D = viewport.get_canvas_transform().affine_inverse()
			var result:Rect2 = Rect2(inverse * screen.position,Vector2.ZERO)
			for corner:Vector2 in [Vector2(screen.end.x,screen.position.y),screen.end,Vector2(screen.position.x,screen.end.y)]:
				result = result.expand(inverse * corner)
			return result
	return SubmissionCharacterTools.map_rect(node)
