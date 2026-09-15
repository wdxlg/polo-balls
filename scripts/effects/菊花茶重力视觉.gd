extends Node2D

# V288：菊花茶重力速度线按实机反馈继续收敛。
# 这次不再把速度线当作“屏幕上随机铺一批平行线”，而是把每一条线绑定到一个真实主体：
# 1. 先在主体本身选起点；人物/投射物优先选 Sprite2D 的真实不透明像素，地图选当前地图边界上的点；
# 2. 起点颜色就是该像素颜色；
# 3. 每条线沿重力轴从主体向外延伸，允许向主体内部反向回拖一小截；
# 4. 起点保存为主体局部坐标，主体移动后每帧重新换算世界坐标，因此线会真正跟着主体；
# 5. 地图只画真实边界上的纯黑速度线；人物/小投射物强制使用更短更细的独立上限，不能再接近地图线尺寸；
# 6. 图案仍会周期重抽，但重抽的是“主体上的锚点/长度/宽度”，不会重新变成漂在空气里的屏幕线。
# 该节点只负责视觉，不参与伤害、碰撞和重力数值。
# V295：World 的 MapOutsideVisualMask 最终 Z 位于普通世界内容上方，用来恢复地图外背景；
# 速度线必须绘制在该遮罩上方、地图黑边框下方，否则伸出边界的速度线会被“地图外背景”重新盖掉。

var _source:Node2D = null
var _duration:float = 3.0
var _elapsed:float = 0.0
var _direction:Vector2 = Vector2.RIGHT
var _pattern_left:float = 0.0
var _map_lines:Array[Dictionary] = []
var _target_lines:Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

var _viewport_snapshot:Image = null
var _snapshot_canvas_transform:Transform2D = Transform2D.IDENTITY
var _snapshot_viewport_size:Vector2 = Vector2.ONE
var _texture_image_cache:Dictionary = {}

const PATTERN_CHANGE_MIN:float = 0.22
const PATTERN_CHANGE_MAX:float = 0.36

const MAP_LINE_COUNT_MIN:int = 28
const MAP_LINE_COUNT_MAX:int = 48
const MAP_FORWARD_RATIO_MIN:float = 0.08
const MAP_FORWARD_RATIO_MAX:float = 0.24
const MAP_BACKWARD_RATIO_MIN:float = 0.0
const MAP_BACKWARD_RATIO_MAX:float = 0.06
const MAP_WIDTH_RATIO_MIN:float = 0.0018
const MAP_WIDTH_RATIO_MAX:float = 0.0042

# V303：速度线密度提高，尤其人物。
# Ball（人物/战斗角色）使用更高密度；BattleTransient（投射物/临时主体）仍保持较轻密度，
# 避免单纯提高人物观感时把所有小投射物也堆成同等数量。
const CHARACTER_LINES_PER_OBJECT_MIN:int = 8
const CHARACTER_LINES_PER_OBJECT_MAX:int = 14
const TRANSIENT_LINES_PER_OBJECT_MIN:int = 3
const TRANSIENT_LINES_PER_OBJECT_MAX:int = 7
# V288：人物/投射物速度线必须明显小于地图边界线。
# 不再允许角色视觉尺寸放大后把线拉到接近地图线的量级。
const TARGET_FORWARD_RATIO_MIN:float = 0.08
const TARGET_FORWARD_RATIO_MAX:float = 0.18
const TARGET_BACKWARD_RATIO_MIN:float = 0.0
const TARGET_BACKWARD_RATIO_MAX:float = 0.04
const TARGET_WIDTH_RATIO_MIN:float = 0.0025
const TARGET_WIDTH_RATIO_MAX:float = 0.0050
const MAX_TARGET_OBJECTS:int = 220

const PIXEL_ALPHA_THRESHOLD:float = 0.10
const SAMPLE_ATTEMPTS:int = 72


func configure(source_node:Node2D,active_duration:float,initial_direction:Vector2) -> void:
	_source = source_node
	_duration = maxf(active_duration,0.2)
	if initial_direction.length_squared() > 0.000001:
		_direction = initial_direction.normalized()


func _ready() -> void:
	# 先隐藏一帧抓取“没有速度线自身”的画面。
	# V295 当前 World：MapOutsideVisualMask 最终 Z≈88，地图黑边框最终 Z≈98。
	# 使用绝对 Z=97：速度线可在地图外继续可见，同时仍让真正的黑色地图边框压在速度线之上。
	z_as_relative = false
	z_index = 97
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/菊花茶重力视觉.gd:_rng.seed",int(Time.get_ticks_usec()) ^ get_instance_id())
	visible = false
	set_process(false)
	_capture_clean_viewport_snapshot()


func _capture_clean_viewport_snapshot() -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var viewport:Viewport = get_viewport()
	if viewport != null:
		var viewport_texture:Texture2D = viewport.get_texture()
		if viewport_texture != null:
			var captured:Image = viewport_texture.get_image()
			if captured != null and not captured.is_empty():
				_viewport_snapshot = captured
				_snapshot_canvas_transform = get_canvas_transform()
				_snapshot_viewport_size = viewport.get_visible_rect().size
	visible = true
	set_process(true)
	_regenerate_pattern()
	queue_redraw()


func _process(delta:float) -> void:
	var safe_delta:float = maxf(delta,0.0)
	_elapsed += safe_delta
	if _elapsed >= _duration:
		queue_free()
		return
	if _source == null or not is_instance_valid(_source) or not _source.is_inside_tree():
		queue_free()
		return

	var resolved:Vector2 = _resolve_source_direction()
	if resolved.length_squared() > 0.000001:
		var blend:float = 1.0 - exp(-12.0 * safe_delta)
		var mixed:Vector2 = _direction.lerp(resolved.normalized(),blend)
		if mixed.length_squared() > 0.000001:
			_direction = mixed.normalized()

	_pattern_left -= safe_delta
	if _pattern_left <= 0.0:
		_regenerate_pattern()
	queue_redraw()


func _regenerate_pattern() -> void:
	_pattern_left = _rng.randf_range(PATTERN_CHANGE_MIN,PATTERN_CHANGE_MAX)
	_map_lines.clear()
	_target_lines.clear()

	var visible_rect:Rect2 = _visible_world_rect().grow(24.0)
	_generate_map_subject_lines(visible_rect)

	# 人物/投射物等主体：每一条线的锚点都存成 Sprite2D 局部坐标。
	# 下一帧绘制时再从局部坐标换回世界坐标，所以主体移动后线仍长在它身上。
	var seen:Dictionary = {}
	var candidates:Array[Node] = []
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		candidates.append(raw)
	for raw:Node in get_tree().get_nodes_in_group("BattleTransient"):
		candidates.append(raw)

	var drawn_objects:int = 0
	for raw:Node in candidates:
		if raw == null or not is_instance_valid(raw) or not raw is Node2D or raw == _source:
			continue
		var object_id:int = raw.get_instance_id()
		if seen.has(object_id):
			continue
		seen[object_id] = true
		if not _is_gravity_visual_target(raw):
			continue
		var target_2d:Node2D = raw as Node2D
		if not visible_rect.has_point(target_2d.global_position):
			continue

		var sprite:Sprite2D = _resolve_subject_sprite(raw)
		var subject_size:float = _subject_visual_size(raw,sprite)
		# V303：人物速度线数量明显提高。Ball 是人物/战斗主体；BattleTransient 只做适度增加。
		# 只增加“条数”，不放大 V288 已收敛的长度/宽度，因此人物线仍明显小于地图边界线。
		var is_character_subject:bool = raw.is_in_group("Ball")
		var count_min:int = CHARACTER_LINES_PER_OBJECT_MIN if is_character_subject else TRANSIENT_LINES_PER_OBJECT_MIN
		var count_max:int = CHARACTER_LINES_PER_OBJECT_MAX if is_character_subject else TRANSIENT_LINES_PER_OBJECT_MAX
		var size_factor:float = clampf(subject_size / 120.0,0.0,1.0)
		var line_count:int = clampi(
			int(round(lerpf(float(count_min),float(count_max),size_factor))),
			count_min,
			count_max
		)
		for line_index:int in range(line_count):
			# 同一个主体两侧都要有“从身上向外拉”的线，而不是所有线漂向同一个屏幕方向。
			var side:float = -1.0 if line_index % 2 == 0 else 1.0
			if _rng.randf() < 0.35:
				side *= -1.0
			var sample:Dictionary = _sample_subject_anchor(raw,sprite,_direction,side)
			if sample.is_empty():
				continue
			var forward:float = subject_size * _rng.randf_range(TARGET_FORWARD_RATIO_MIN,TARGET_FORWARD_RATIO_MAX)
			var backward:float = subject_size * _rng.randf_range(TARGET_BACKWARD_RATIO_MIN,TARGET_BACKWARD_RATIO_MAX)
			var width:float = subject_size * _rng.randf_range(TARGET_WIDTH_RATIO_MIN,TARGET_WIDTH_RATIO_MAX)
			_target_lines.append({
				"target_ref": weakref(target_2d),
				"sprite_ref": weakref(sprite) if sprite != null else null,
				"local_point": sample.get("local_point",Vector2.ZERO),
				"fallback_world": sample.get("world_point",target_2d.global_position),
				"side": side,
				"forward": clampf(forward,3.0,24.0),
				"backward": clampf(backward,0.0,5.0),
				"width": clampf(width,0.22,0.95),
				"color": sample.get("color",Color.WHITE),
			})
		drawn_objects += 1
		if drawn_objects >= MAX_TARGET_OBJECTS:
			break


func _generate_map_subject_lines(visible_rect:Rect2) -> void:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return
	var map_group_value:Variant = _get_property_if_present(world,&"map_group")
	var map_key_value:Variant = _get_property_if_present(world,&"now_choose_map")
	if typeof(map_group_value) != TYPE_DICTIONARY:
		return
	var map_group_dict:Dictionary = map_group_value
	if not map_group_dict.has(map_key_value):
		return
	var map_variant:Variant = map_group_dict.get(map_key_value)
	if not map_variant is Node2D or not is_instance_valid(map_variant):
		return
	var map_node:Node2D = map_variant as Node2D
	var rect_value:Variant = world.call("return_map_world_rect",map_node)
	if typeof(rect_value) != TYPE_RECT2:
		return
	var map_rect:Rect2 = rect_value
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return
	if not map_rect.grow(48.0).intersects(visible_rect):
		return

	var subject_size:float = maxf(map_rect.size.x,map_rect.size.y)
	var perimeter_factor:float = clampf((map_rect.size.x + map_rect.size.y) / 1200.0,0.0,1.0)
	var line_count:int = clampi(
		int(round(lerpf(float(MAP_LINE_COUNT_MIN),float(MAP_LINE_COUNT_MAX),perimeter_factor))),
		MAP_LINE_COUNT_MIN,
		MAP_LINE_COUNT_MAX
	)
	var axis:Vector2 = _direction.normalized() if _direction.length_squared() > 0.000001 else Vector2.RIGHT
	for line_index:int in range(line_count):
		var side:float = -1.0 if line_index % 2 == 0 else 1.0
		if _rng.randf() < 0.28:
			side *= -1.0
		var anchor_world:Vector2
		# 地图是矩形主体：沿重力轴的两侧边界直接选真实起点。
		# 这样截图中会像“从地图轮廓长出去”，不会在蓝色空白内部凭空出现长线。
		if absf(axis.x) >= absf(axis.y):
			anchor_world = Vector2(
				map_rect.end.x if side > 0.0 else map_rect.position.x,
				_rng.randf_range(map_rect.position.y,map_rect.end.y)
			)
		else:
			anchor_world = Vector2(
				_rng.randf_range(map_rect.position.x,map_rect.end.x),
				map_rect.end.y if side > 0.0 else map_rect.position.y
			)

		var forward:float = subject_size * _rng.randf_range(MAP_FORWARD_RATIO_MIN,MAP_FORWARD_RATIO_MAX)
		var backward:float = subject_size * _rng.randf_range(MAP_BACKWARD_RATIO_MIN,MAP_BACKWARD_RATIO_MAX)
		var width:float = subject_size * _rng.randf_range(MAP_WIDTH_RATIO_MIN,MAP_WIDTH_RATIO_MAX)
		_map_lines.append({
			"map_ref": weakref(map_node),
			"local_point": map_node.to_local(anchor_world),
			"fallback_world": anchor_world,
			"side": side,
			"forward": clampf(forward,28.0,280.0),
			"backward": clampf(backward,0.0,54.0),
			"width": clampf(width,0.8,5.2),
			"color": Color.BLACK,
		})


func _resolve_source_direction() -> Vector2:
	if _source != null and is_instance_valid(_source):
		if _source.has_method("_resolve_gravity_direction"):
			var resolved:Variant = _source.call("_resolve_gravity_direction")
			if typeof(resolved) == TYPE_VECTOR2:
				var dir:Vector2 = resolved
				if dir.length_squared() > 0.000001:
					return dir.normalized()
		var velocity_value:Variant = _get_property_if_present(_source,&"velocity")
		if typeof(velocity_value) == TYPE_VECTOR2:
			var velocity_dir:Vector2 = velocity_value
			if velocity_dir.length_squared() > 0.000001:
				return velocity_dir.normalized()
	return _direction


func _draw() -> void:
	if _direction.length_squared() <= 0.000001:
		return
	var fade:float = _edge_fade()
	var axis:Vector2 = _direction.normalized()

	# 地图线也属于“主体线”：锚点保存在当前地图节点局部空间，所以地图若发生变换仍会跟随。
	for line_data:Dictionary in _map_lines:
		var anchor_world:Vector2 = line_data.get("fallback_world",Vector2.ZERO)
		var map_ref:WeakRef = line_data.get("map_ref",null)
		if map_ref != null:
			var raw_map:Object = map_ref.get_ref()
			if raw_map != null and is_instance_valid(raw_map) and raw_map is Node2D:
				anchor_world = (raw_map as Node2D).to_global(line_data.get("local_point",Vector2.ZERO))
		var side:float = float(line_data.get("side",1.0))
		var line_dir:Vector2 = axis * side
		var forward:float = float(line_data.get("forward",80.0))
		var backward:float = float(line_data.get("backward",0.0))
		# V288：地图只保留从真实边界长出的纯黑速度线，不再从地图像素取色。
		var color:Color = Color(0.0,0.0,0.0,fade)
		draw_line(
			to_local(anchor_world - line_dir * backward),
			to_local(anchor_world + line_dir * forward),
			color,
			float(line_data.get("width",1.4)),
			true
		)

	# 人物/投射物：锚点每帧由 Sprite2D 局部点还原，因此目标移动、翻转、旋转、缩放时线都跟着它。
	for line_data:Dictionary in _target_lines:
		var target_ref:WeakRef = line_data.get("target_ref",null)
		if target_ref == null:
			continue
		var raw_target:Object = target_ref.get_ref()
		if raw_target == null or not is_instance_valid(raw_target) or not raw_target is Node2D:
			continue

		var anchor_world:Vector2 = line_data.get("fallback_world",(raw_target as Node2D).global_position)
		var sprite_ref:WeakRef = line_data.get("sprite_ref",null)
		if sprite_ref != null:
			var raw_sprite:Object = sprite_ref.get_ref()
			if raw_sprite != null and is_instance_valid(raw_sprite) and raw_sprite is Sprite2D:
				anchor_world = (raw_sprite as Sprite2D).to_global(line_data.get("local_point",Vector2.ZERO))

		var side:float = float(line_data.get("side",1.0))
		var line_dir:Vector2 = axis * side
		var forward:float = float(line_data.get("forward",48.0))
		var backward:float = float(line_data.get("backward",0.0))
		var color:Color = line_data.get("color",Color.WHITE)
		color.a = clampf(maxf(color.a,0.82) * fade,0.0,1.0)
		draw_line(
			to_local(anchor_world - line_dir * backward),
			to_local(anchor_world + line_dir * forward),
			color,
			float(line_data.get("width",1.0)),
			true
		)


func _sample_subject_anchor(target:Node,sprite:Sprite2D,axis_world:Vector2,side:float) -> Dictionary:
	if sprite != null and is_instance_valid(sprite) and sprite.texture != null:
		var rect:Rect2 = sprite.get_rect()
		if absf(rect.size.x) > 0.001 and absf(rect.size.y) > 0.001:
			var local_axis:Vector2 = sprite.to_local(sprite.global_position + axis_world) - sprite.to_local(sprite.global_position)
			if local_axis.length_squared() <= 0.000001:
				local_axis = Vector2.RIGHT
			local_axis = local_axis.normalized() * side
			var best_score:float = -INF
			var best_point:Vector2 = Vector2.ZERO
			var found:bool = false
			# 在真实不透明像素里挑“朝该侧最外层”的候选点。
			# 这样起点更接近人物轮廓，不会从透明外框或人物中心凭空起线。
			for _attempt:int in range(SAMPLE_ATTEMPTS):
				var local_point := Vector2(
					_rng.randf_range(rect.position.x,rect.end.x),
					_rng.randf_range(rect.position.y,rect.end.y)
				)
				if not sprite.is_pixel_opaque(local_point):
					continue
				var normalized_point:Vector2 = local_point - rect.get_center()
				var score:float = normalized_point.dot(local_axis)
				# 轻微随机项避免每次都锁死在同一个最尖像素。
				score += _rng.randf_range(-1.0,1.0) * maxf(minf(absf(rect.size.x),absf(rect.size.y)) * 0.04,0.5)
				if not found or score > best_score:
					found = true
					best_score = score
					best_point = local_point
			if found:
				var sampled:Color = _sample_sprite_color(sprite,best_point)
				if sampled.a >= PIXEL_ALPHA_THRESHOLD:
					return {
						"local_point": best_point,
						"world_point": sprite.to_global(best_point),
						"color": sampled,
					}

	# 没有可读 Sprite 的程序绘制对象，只能把节点位置当作主体锚点；颜色仍取干净画面对应像素。
	if target is Node2D:
		var world_point:Vector2 = (target as Node2D).global_position
		return {
			"local_point": Vector2.ZERO,
			"world_point": world_point,
			"color": _sample_map_pixel_color(world_point),
		}
	return {}


func _subject_visual_size(target:Node,sprite:Sprite2D) -> float:
	if sprite != null and is_instance_valid(sprite) and sprite.texture != null:
		var rect:Rect2 = sprite.get_rect()
		var corners:Array[Vector2] = [
			sprite.to_global(rect.position),
			sprite.to_global(rect.position + Vector2(rect.size.x,0.0)),
			sprite.to_global(rect.end),
			sprite.to_global(rect.position + Vector2(0.0,rect.size.y)),
		]
		var min_point:Vector2 = corners[0]
		var max_point:Vector2 = corners[0]
		for point:Vector2 in corners:
			min_point.x = minf(min_point.x,point.x)
			min_point.y = minf(min_point.y,point.y)
			max_point.x = maxf(max_point.x,point.x)
			max_point.y = maxf(max_point.y,point.y)
		var size:Vector2 = max_point - min_point
		return clampf(maxf(size.x,size.y),8.0,260.0)
	if target is Node2D:
		var node_scale:Vector2 = (target as Node2D).global_scale
		return clampf(18.0 * maxf(absf(node_scale.x),absf(node_scale.y)),8.0,90.0)
	return 18.0


func _resolve_subject_sprite(target:Node) -> Sprite2D:
	if target is Sprite2D:
		var direct_sprite:Sprite2D = target as Sprite2D
		if direct_sprite.visible and direct_sprite.texture != null:
			return direct_sprite

	if target.has_node("Graphics/Image"):
		var image_node:Node = target.get_node("Graphics/Image")
		if image_node is Sprite2D:
			var image_sprite:Sprite2D = image_node as Sprite2D
			if image_sprite.visible and image_sprite.texture != null:
				return image_sprite

	var named_image:Node = target.find_child("Image",true,false)
	if named_image is Sprite2D:
		var named_sprite:Sprite2D = named_image as Sprite2D
		if named_sprite.visible and named_sprite.texture != null:
			return named_sprite

	for raw_child:Node in target.find_children("*","Sprite2D",true,false):
		if raw_child is Sprite2D:
			var candidate:Sprite2D = raw_child as Sprite2D
			if candidate.visible and candidate.texture != null:
				return candidate
	return null


func _sample_sprite_color(sprite:Sprite2D,local_point:Vector2) -> Color:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return Color.WHITE
	var image:Image = _texture_image(sprite.texture)
	if image == null or image.is_empty():
		return Color.WHITE

	var local_rect:Rect2 = sprite.get_rect()
	if absf(local_rect.size.x) <= 0.001 or absf(local_rect.size.y) <= 0.001:
		return Color.WHITE
	var uv := Vector2(
		(local_point.x - local_rect.position.x) / local_rect.size.x,
		(local_point.y - local_rect.position.y) / local_rect.size.y
	)
	uv.x = clampf(uv.x,0.0,0.999999)
	uv.y = clampf(uv.y,0.0,0.999999)
	if sprite.flip_h:
		uv.x = 1.0 - uv.x
	if sprite.flip_v:
		uv.y = 1.0 - uv.y

	var texture_size:Vector2 = Vector2(sprite.texture.get_size())
	var source_rect := Rect2(Vector2.ZERO,texture_size)
	if sprite.region_enabled and sprite.region_rect.size.x > 0.0 and sprite.region_rect.size.y > 0.0:
		source_rect = sprite.region_rect
	else:
		var hframes:int = maxi(sprite.hframes,1)
		var vframes:int = maxi(sprite.vframes,1)
		if hframes > 1 or vframes > 1:
			var frame_size := Vector2(texture_size.x / float(hframes),texture_size.y / float(vframes))
			var coords:Vector2i = sprite.frame_coords
			source_rect = Rect2(Vector2(coords.x * frame_size.x,coords.y * frame_size.y),frame_size)

	var pixel_position:Vector2 = source_rect.position + uv * source_rect.size
	var px:int = clampi(int(floor(pixel_position.x)),0,maxi(image.get_width() - 1,0))
	var py:int = clampi(int(floor(pixel_position.y)),0,maxi(image.get_height() - 1,0))
	var sampled:Color = image.get_pixel(px,py)
	# 把 Sprite 自己的 tint 叠进去，使中毒/受伤变色后的速度线仍与起点屏幕颜色接近。
	var tint:Color = sprite.modulate * sprite.self_modulate
	sampled = Color(sampled.r * tint.r,sampled.g * tint.g,sampled.b * tint.b,sampled.a * tint.a)
	return sampled


func _texture_image(texture:Texture2D) -> Image:
	if texture == null:
		return null
	var key:int = texture.get_instance_id()
	if _texture_image_cache.has(key):
		var cached:Variant = _texture_image_cache.get(key)
		if cached is Image:
			return cached as Image
	var image:Image = texture.get_image()
	if image != null and not image.is_empty():
		_texture_image_cache[key] = image
		return image
	return null


func _sample_map_pixel_color(world_point:Vector2) -> Color:
	if _viewport_snapshot == null or _viewport_snapshot.is_empty():
		return Color(0.80,0.88,0.92,0.86)
	var viewport_point:Vector2 = _snapshot_canvas_transform * world_point
	var image_size := Vector2(float(_viewport_snapshot.get_width()),float(_viewport_snapshot.get_height()))
	if _snapshot_viewport_size.x <= 0.001 or _snapshot_viewport_size.y <= 0.001:
		return Color(0.80,0.88,0.92,0.86)
	var pixel := Vector2(
		viewport_point.x * image_size.x / _snapshot_viewport_size.x,
		viewport_point.y * image_size.y / _snapshot_viewport_size.y
	)
	if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x >= image_size.x or pixel.y >= image_size.y:
		return Color(0.80,0.88,0.92,0.86)
	var color:Color = _viewport_snapshot.get_pixel(
		clampi(int(pixel.x),0,_viewport_snapshot.get_width() - 1),
		clampi(int(pixel.y),0,_viewport_snapshot.get_height() - 1)
	)
	if color.a < PIXEL_ALPHA_THRESHOLD:
		color = Color(0.80,0.88,0.92,0.86)
	return color


func _edge_fade() -> float:
	var fade_in:float = clampf(_elapsed / 0.10,0.0,1.0)
	var fade_out:float = clampf((_duration - _elapsed) / 0.18,0.0,1.0)
	return minf(fade_in,fade_out)


func _visible_world_rect() -> Rect2:
	var viewport:Viewport = get_viewport()
	if viewport == null:
		return Rect2(Vector2(-320.0,-180.0),Vector2(640.0,360.0))
	var camera:Camera2D = viewport.get_camera_2d()
	var viewport_size:Vector2 = viewport.get_visible_rect().size
	if camera == null:
		return Rect2(Vector2.ZERO,viewport_size)
	var zoom:Vector2 = camera.zoom
	var world_size := Vector2(
		viewport_size.x / maxf(absf(zoom.x),0.001),
		viewport_size.y / maxf(absf(zoom.y),0.001)
	)
	return Rect2(camera.get_screen_center_position() - world_size * 0.5,world_size)


func _effect_world_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("return_map_world_rect"):
		var map_group_value:Variant = _get_property_if_present(world,&"map_group")
		var map_key_value:Variant = _get_property_if_present(world,&"now_choose_map")
		if typeof(map_group_value) == TYPE_DICTIONARY:
			var map_group_dict:Dictionary = map_group_value
			if map_group_dict.has(map_key_value):
				var map_node:Variant = map_group_dict.get(map_key_value)
				if map_node is Node and is_instance_valid(map_node):
					var rect_value:Variant = world.call("return_map_world_rect",map_node)
					if typeof(rect_value) == TYPE_RECT2:
						var map_rect:Rect2 = rect_value
						if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
							return map_rect
	return _visible_world_rect()


func _is_gravity_visual_target(node:Node) -> bool:
	if node is ball:
		return true
	if not node.is_in_group("BattleTransient"):
		return false
	var script_value:Variant = node.get_script()
	if not script_value is Script:
		return false
	return (script_value as Script).resource_path.begins_with("res://scripts/shooter/")


func _get_property_if_present(object:Object,property_name:StringName) -> Variant:
	if object == null:
		return null
	for entry:Dictionary in object.get_property_list():
		if StringName(str(entry.get("name",""))) == property_name:
			return object.get(property_name)
	return null
