extends Node2D

# V58：伞夫 / 堇紫泪滴的真实威胁几何兼容层。
#
# 目标：
# - 不替换项目现有 CombatThreatAnalyzer；只补它没有画到的真实碰撞几何。
# - 仅在 Game.Game_Settings["Training_Debug_Mode"] 开启时绘制。
# - 红色：攻击 Area2D / Hitbox 的真实 CollisionShape2D。
# - 蓝色：角色显式 get_debug_detection_regions()，或场景里可识别的敌人检测 Area2D。
# - 若旧角色没有专门 debug 接口，再从常见“检测半径”导出属性做兜底。
#
# 这个脚本由 ball.gd 只给“伞夫 / 堇紫泪滴”实例挂载，避免改变其他角色的调试表现。

const ATTACK_COLOR := Color(1.0,0.16,0.12,0.95)
const ATTACK_INACTIVE_COLOR := Color(1.0,0.34,0.18,0.62)
const DETECTION_COLOR := Color(0.18,0.72,1.0,0.92)
const LINE_WIDTH:float = 2.5
const CIRCLE_SEGMENTS:int = 48

var character:Node2D = null


func setup(target:Node2D) -> void:
	character = target
	z_index = 4090
	z_as_relative = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	queue_redraw()


func _process(_delta:float) -> void:
	var should_show:bool = _debug_enabled() and _character_valid()
	if visible != should_show:
		visible = should_show
	if should_show:
		queue_redraw()


func _exit_tree() -> void:
	character = null


func _draw() -> void:
	if not _debug_enabled() or not _character_valid():
		return

	var attack_areas_are_detection:bool = false
	if character.has_method("uses_attack_areas_as_detection"):
		attack_areas_are_detection = bool(character.call("uses_attack_areas_as_detection"))

	# V75：伞夫明确声明“攻击范围 = 起手检测范围”时，不再额外画蓝色检测圈/属性兜底。
	# 直接由下面的真实攻击 CollisionShape2D 红框同时表达检测与伤害几何。
	if not attack_areas_are_detection:
		var drawn_detection_keys:Dictionary = {}
		_draw_detection_areas(drawn_detection_keys)
		if drawn_detection_keys.is_empty():
			_draw_explicit_detection_regions(drawn_detection_keys)
		_draw_detection_property_fallback(drawn_detection_keys)
	_draw_attack_areas()


func _debug_enabled() -> bool:
	if not is_instance_valid(Game):
		return false
	return bool(Game.Game_Settings.get("Training_Debug_Mode",false))


func _character_valid() -> bool:
	return character != null and is_instance_valid(character) and character.is_inside_tree()


func _draw_explicit_detection_regions(drawn_keys:Dictionary) -> void:
	if not character.has_method("get_debug_detection_regions"):
		return

	var raw_regions:Variant = character.call("get_debug_detection_regions")
	if not raw_regions is Array:
		return

	for raw_region:Variant in raw_regions:
		if not raw_region is Dictionary:
			continue
		var region:Dictionary = raw_region as Dictionary
		var shape_kind:String = str(region.get("shape","")).to_lower()
		match shape_kind:
			"circle":
				var center:Vector2 = _variant_vec2(region.get("position",character.global_position),character.global_position)
				var radius:float = maxf(float(region.get("radius",0.0)),0.0)
				if radius > 0.0:
					_draw_world_circle(center,radius,DETECTION_COLOR)
					drawn_keys[_circle_key(center,radius)] = true
			"segment":
				var start_p:Vector2 = _variant_vec2(region.get("start",character.global_position),character.global_position)
				var end_p:Vector2 = _variant_vec2(region.get("end",character.global_position),character.global_position)
				var radius:float = maxf(float(region.get("radius",0.0)),0.0)
				_draw_world_capsule_segment(start_p,end_p,radius,DETECTION_COLOR)
			"rect", "rectangle":
				var center:Vector2 = _variant_vec2(region.get("position",character.global_position),character.global_position)
				var size:Vector2 = _variant_vec2(region.get("size",Vector2.ZERO),Vector2.ZERO)
				var rotation_value:float = float(region.get("rotation",0.0))
				if size.x > 0.0 and size.y > 0.0:
					_draw_world_rectangle(center,size,rotation_value,DETECTION_COLOR)


func _draw_detection_areas(drawn_keys:Dictionary) -> void:
	for node:Node in character.find_children("*","Area2D",true,false):
		if not node is Area2D:
			continue
		var area:Area2D = node as Area2D
		if not _is_detection_area(area):
			continue
		for child:Node in area.find_children("*","CollisionShape2D",true,false):
			if not child is CollisionShape2D:
				continue
			var collision:CollisionShape2D = child as CollisionShape2D
			if collision.disabled or collision.shape == null:
				continue
			var key:String = "%d" % collision.get_instance_id()
			if drawn_keys.has(key):
				continue
			_draw_collision_shape(collision,DETECTION_COLOR)
			drawn_keys[key] = true


func _draw_detection_property_fallback(drawn_keys:Dictionary) -> void:
	# 已经有角色显式 debug 区或真实检测 Area 时，不再猜属性，避免把追敌范围也叠上去。
	if not drawn_keys.is_empty():
		return
	# 老角色可能只在脚本里保存“检测半径”，并没有专用 Area2D。
	# 只识别名字明确带 detect/search/target/enemy/检测/索敌/搜索/感知 的数值属性。
	# 如果角色已有显式 debug 圆，key 会去重，不重复画。
	var found_named_radius:bool = false
	for info:Dictionary in character.get_property_list():
		var property_name:String = str(info.get("name",""))
		if property_name.is_empty():
			continue
		var lower:String = property_name.to_lower()
		if not _looks_like_detection_property(lower,property_name):
			continue
		var value:Variant = character.get(property_name)
		if not (value is float or value is int):
			continue
		var radius:float = float(value)
		if radius <= 1.0 or radius > 5000.0:
			continue
		var key:String = _circle_key(character.global_position,radius)
		if drawn_keys.has(key):
			continue
		_draw_world_circle(character.global_position,radius,DETECTION_COLOR)
		drawn_keys[key] = true
		found_named_radius = true

	# 最后兜底：一些旧月计角色只有 target_search_range。
	# 只有前面完全没找到检测数据时才画，避免把追敌范围和攻击检测范围同时堆出来。
	if not found_named_radius and drawn_keys.is_empty() and _has_property(character,"target_search_range"):
		var fallback:float = float(character.get("target_search_range"))
		if fallback > 1.0 and fallback <= 5000.0:
			_draw_world_circle(character.global_position,fallback,DETECTION_COLOR)


func _draw_attack_areas() -> void:
	for node:Node in character.find_children("*","Area2D",true,false):
		if not node is Area2D:
			continue
		var area:Area2D = node as Area2D
		if not _is_attack_area(area):
			continue

		var physics_active:bool = area.monitoring
		var debug_damage_active:bool = false
		if area.has_meta("threat_debug_damage"):
			debug_damage_active = float(area.get_meta("threat_debug_damage",0.0)) > 0.0
		var owner_attacking:bool = false
		if _has_property(character,"Attacking"):
			owner_attacking = bool(character.get("Attacking"))
		var tuning_visible:bool = bool(area.get_meta("threat_debug_tuning",false))
		if not physics_active and not debug_damage_active and not owner_attacking and not tuning_visible:
			continue

		var color:Color = ATTACK_COLOR if (physics_active or debug_damage_active) else ATTACK_INACTIVE_COLOR
		for child:Node in area.find_children("*","CollisionShape2D",true,false):
			if not child is CollisionShape2D:
				continue
			var collision:CollisionShape2D = child as CollisionShape2D
			if collision.disabled or collision.shape == null:
				continue
			_draw_collision_shape(collision,color)


func _is_detection_area(area:Area2D) -> bool:
	if area.has_meta("threat_debug_kind"):
		var meta_kind:String = str(area.get_meta("threat_debug_kind","")).to_lower()
		if "detect" in meta_kind or "search" in meta_kind or "target" in meta_kind:
			return true

	var text:String = (str(area.name)+" "+str(area.get_path())).to_lower()
	var keys:Array[String] = [
		"detect","detection","search","sense","scan","enemy","target","check","aggro",
		"检测","侦测","搜索","索敌","敌人","目标","感知","警戒","起手"
	]
	for key:String in keys:
		if key in text:
			return true
	return false


func _is_attack_area(area:Area2D) -> bool:
	if area.has_meta("threat_debug_damage"):
		return true
	if area is hurtbox:
		return false
	if area is hitbox:
		# ball 自带的身体 hitbox 在 Has_Collision_Damage=false 时不是主动攻击框。
		if area.get_parent() == character and _has_property(character,"Has_Collision_Damage"):
			return bool(character.get("Has_Collision_Damage")) or area.monitoring
		return true

	var text:String = (str(area.name)+" "+str(area.get_path())).to_lower()
	var keys:Array[String] = [
		"attack","hit","damage","strike","slash","stab","weapon","skill","hurt_enemy",
		"攻击","命中","伤害","武器","斩","刺","技能"
	]
	for key:String in keys:
		if key in text:
			return true
	return false


func _looks_like_detection_property(lower:String,original:String) -> bool:
	var semantic:bool = (
		"detect" in lower
		or "search" in lower
		or "target" in lower
		or "enemy" in lower
		or "sense" in lower
		or "aggro" in lower
		or "检测" in original
		or "搜索" in original
		or "索敌" in original
		or "敌人" in original
		or "目标" in original
		or "感知" in original
	)
	var measurement:bool = (
		"radius" in lower
		or "range" in lower
		or "distance" in lower
		or "半径" in original
		or "范围" in original
		or "距离" in original
	)
	return semantic and measurement


func _draw_collision_shape(collision:CollisionShape2D,color:Color) -> void:
	var shape:Shape2D = collision.shape
	if shape is CircleShape2D:
		var points := PackedVector2Array()
		var circle:CircleShape2D = shape as CircleShape2D
		for i:int in range(CIRCLE_SEGMENTS+1):
			var angle:float = TAU * float(i) / float(CIRCLE_SEGMENTS)
			points.append(_shape_local_to_overlay(collision,Vector2.RIGHT.rotated(angle)*circle.radius))
		draw_polyline(points,color,LINE_WIDTH,true)
		return

	if shape is RectangleShape2D:
		var rect:RectangleShape2D = shape as RectangleShape2D
		var half:Vector2 = rect.size * 0.5
		var local_points := PackedVector2Array([
			Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),
			Vector2(-half.x,half.y),Vector2(-half.x,-half.y)
		])
		var world_points := PackedVector2Array()
		for p:Vector2 in local_points:
			world_points.append(_shape_local_to_overlay(collision,p))
		draw_polyline(world_points,color,LINE_WIDTH,true)
		return

	if shape is CapsuleShape2D:
		_draw_capsule_shape(collision,shape as CapsuleShape2D,color)
		return

	if shape is ConvexPolygonShape2D:
		var polygon:ConvexPolygonShape2D = shape as ConvexPolygonShape2D
		var points := PackedVector2Array()
		for p:Vector2 in polygon.points:
			points.append(_shape_local_to_overlay(collision,p))
		if points.size() >= 2:
			points.append(points[0])
			draw_polyline(points,color,LINE_WIDTH,true)
		return

	if shape is SegmentShape2D:
		var segment:SegmentShape2D = shape as SegmentShape2D
		draw_line(
			_shape_local_to_overlay(collision,segment.a),
			_shape_local_to_overlay(collision,segment.b),
			color,
			LINE_WIDTH,
			true
		)
		return

	# 未特别支持的 Shape2D：至少画出它的本地包围盒，避免“完全看不见”。
	var fallback_rect:Rect2 = shape.get_rect()
	var corners := PackedVector2Array([
		fallback_rect.position,
		fallback_rect.position+Vector2(fallback_rect.size.x,0.0),
		fallback_rect.end,
		fallback_rect.position+Vector2(0.0,fallback_rect.size.y),
		fallback_rect.position,
	])
	var fallback_points := PackedVector2Array()
	for corner:Vector2 in corners:
		fallback_points.append(_shape_local_to_overlay(collision,corner))
	draw_polyline(fallback_points,color,LINE_WIDTH,true)


func _draw_capsule_shape(collision:CollisionShape2D,capsule:CapsuleShape2D,color:Color) -> void:
	var radius:float = capsule.radius
	var straight_half:float = maxf(capsule.height * 0.5-radius,0.0)
	var points := PackedVector2Array()
	var steps:int = 20
	for i:int in range(steps+1):
		var angle:float = PI + PI * float(i)/float(steps)
		points.append(_shape_local_to_overlay(collision,Vector2(cos(angle)*radius,-straight_half+sin(angle)*radius)))
	for i:int in range(steps+1):
		var angle:float = PI * float(i)/float(steps)
		points.append(_shape_local_to_overlay(collision,Vector2(cos(angle)*radius,straight_half+sin(angle)*radius)))
	if not points.is_empty():
		points.append(points[0])
		draw_polyline(points,color,LINE_WIDTH,true)


func _shape_local_to_overlay(collision:CollisionShape2D,local_point:Vector2) -> Vector2:
	var world_point:Vector2 = collision.global_transform * local_point
	return to_local(world_point)


func _draw_world_circle(center:Vector2,radius:float,color:Color) -> void:
	var points := PackedVector2Array()
	for i:int in range(CIRCLE_SEGMENTS+1):
		var angle:float = TAU * float(i)/float(CIRCLE_SEGMENTS)
		points.append(to_local(center+Vector2.RIGHT.rotated(angle)*radius))
	draw_polyline(points,color,LINE_WIDTH,true)


func _draw_world_rectangle(center:Vector2,size:Vector2,rotation_value:float,color:Color) -> void:
	var half:Vector2 = size*0.5
	var local_points := PackedVector2Array([
		Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),
		Vector2(-half.x,half.y),Vector2(-half.x,-half.y)
	])
	var points := PackedVector2Array()
	for p:Vector2 in local_points:
		points.append(to_local(center+p.rotated(rotation_value)))
	draw_polyline(points,color,LINE_WIDTH,true)


func _draw_world_capsule_segment(start_p:Vector2,end_p:Vector2,radius:float,color:Color) -> void:
	var axis:Vector2 = end_p-start_p
	if axis.length_squared() <= 0.000001:
		_draw_world_circle(start_p,maxf(radius,1.0),color)
		return
	var dir:Vector2 = axis.normalized()
	var normal:Vector2 = Vector2(-dir.y,dir.x)
	var points := PackedVector2Array([
		to_local(start_p+normal*radius),
		to_local(end_p+normal*radius),
		to_local(end_p-normal*radius),
		to_local(start_p-normal*radius),
		to_local(start_p+normal*radius),
	])
	draw_polyline(points,color,LINE_WIDTH,true)
	_draw_world_circle(start_p,radius,color)
	_draw_world_circle(end_p,radius,color)


func _circle_key(center:Vector2,radius:float) -> String:
	return "circle:%.2f:%.2f:%.2f" % [center.x,center.y,radius]


func _variant_vec2(value:Variant,fallback:Vector2) -> Vector2:
	return value as Vector2 if value is Vector2 else fallback


func _has_property(object:Object,property_name:String) -> bool:
	# V431 性能：按脚本缓存属性名集合（classes/property_index.gd），不再逐次 get_property_list()。
	return PROPERTY_INDEX.has_property(object,property_name)


const PROPERTY_INDEX = preload("res://classes/property_index.gd")
