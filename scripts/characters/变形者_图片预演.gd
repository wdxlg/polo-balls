extends RefCounted

# 变形者视觉工具：
# 1. 主预览仍复用 Graphics/Image；过渡期间临时叠一张目标 Sprite2D。
# 2. 所有候选图与真正变形后的图，按“原始变形者 Image 最终屏幕尺寸”做等比限制。
# 3. 旧形态和目标形态同时存在并做有机溶解/生长，因此不再是“扭一下 -> 隐藏 -> 偷换贴图”。

const MORPH_SHADER:Shader = preload("res://shaders/变形者_扭曲变形.gdshader")

static var _descriptor_cache:Dictionary = {}


static func play_shuffle(
	host:ball,
	candidates:Array[String],
	final_path:String,
	duration:float,
	step_time:float,
	reference_world_size:Vector2,
	min_ratio:float,
	max_ratio:float,
	distortion_strength:float
) -> void:
	if host == null or not is_instance_valid(host):
		return
	if duration <= 0.0 or candidates.is_empty():
		return
	if host.graphics == null:
		return

	var preview_sprite := host.get_node_or_null("Graphics/Image") as Sprite2D
	if preview_sprite == null:
		return

	var active_visual:Node2D = _get_active_visual(host)
	if active_visual == null:
		return

	var animated_sprite := host.get_node_or_null("Graphics/AnimatedSprite2D") as AnimatedSprite2D
	var saved_state:Dictionary = _capture_sprite_state(preview_sprite)
	var saved_animated_visible:bool = animated_sprite.visible if animated_sprite != null else false
	var saved_active_visible:bool = active_visual.visible

	var ref_size:Vector2 = reference_world_size
	if ref_size.x <= 0.01 or ref_size.y <= 0.01:
		ref_size = _get_visual_world_size(active_visual)
	if ref_size.x <= 0.01 or ref_size.y <= 0.01:
		return

	var current_descriptor:Dictionary = _capture_runtime_visual_descriptor(host,active_visual)
	if current_descriptor.is_empty():
		return

	# 预演只复用现有 Graphics/Image。把真正活动的 AnimatedSprite2D 暂时隐藏，
	# 并把 Image 提到角色视觉最上层，避免候选图被其它视觉节点盖住。
	var preview_z:int = maxi(
		int(saved_state.get("z_index",preview_sprite.z_index)) + 20,
		active_visual.z_index + 20
	)
	preview_sprite.visible = true
	preview_sprite.z_index = preview_z
	if animated_sprite != null and animated_sprite != preview_sprite:
		animated_sprite.visible = false
	if active_visual != preview_sprite and active_visual != animated_sprite:
		active_visual.visible = false

	var current_transform:Transform2D = _calculate_preview_transform(
		host,
		preview_sprite,
		current_descriptor,
		ref_size,
		min_ratio,
		max_ratio
	)
	_apply_descriptor_plain(preview_sprite,current_descriptor,current_transform)
	preview_sprite.z_index = preview_z

	# 变形量改为 ShaderMaterial 普通 uniform。
	# 这样不依赖 RenderingServer 在“刚替换材质的同一帧”就刷新 instance uniform 列表。
	# ball 自己持续写入的染色/白闪参数仍然保留为 instance uniform。
	var morph_material := ShaderMaterial.new()
	morph_material.shader = MORPH_SHADER
	morph_material.set_shader_parameter("morph_amount",0.0)
	morph_material.set_shader_parameter("morph_role",0.0)
	morph_material.set_shader_parameter("morph_strength",maxf(distortion_strength,0.0))
	preview_sprite.material = morph_material

	# 至少等一帧让新材质真正挂到 CanvasItem 后再开始 Tween。
	await host.get_tree().process_frame
	if host == null or not is_instance_valid(host):
		return

	var safe_step:float = maxf(step_time,0.16)
	var steps:int = maxi(4,int(round(duration / safe_step)))
	var sequence:Array[String] = _build_shuffle_sequence(candidates,final_path,steps)

	for scene_path:String in sequence:
		if host == null or not is_instance_valid(host):
			return

		if animated_sprite != null and is_instance_valid(animated_sprite):
			animated_sprite.visible = false
		preview_sprite.visible = true
		preview_sprite.z_index = preview_z

		var next_descriptor:Dictionary = _load_visual_descriptor(scene_path)
		if next_descriptor.is_empty():
			continue

		var next_transform:Transform2D = _calculate_preview_transform(
			host,
			preview_sprite,
			next_descriptor,
			ref_size,
			min_ratio,
			max_ratio
		)

		await _morph_between(
			host,
			preview_sprite,
			morph_material,
			next_descriptor,
			next_transform,
			safe_step,
			distortion_strength,
			preview_z
		)

		current_descriptor = next_descriptor
		current_transform = next_transform

	if host == null or not is_instance_valid(host):
		return

	morph_material.set_shader_parameter("morph_amount",0.0)
	await host.get_tree().create_timer(minf(maxf(safe_step * 0.22,0.025),0.07)).timeout

	if host == null or not is_instance_valid(host):
		return

	preview_sprite.material = saved_state.get("material",null)
	preview_sprite.visible = true
	preview_sprite.z_index = preview_z

	if animated_sprite != null and is_instance_valid(animated_sprite):
		animated_sprite.visible = false
	if active_visual != null and is_instance_valid(active_visual) and active_visual != preview_sprite:
		active_visual.visible = false

	var _unused_saved_animated_visible:bool = saved_animated_visible
	var _unused_saved_active_visible:bool = saved_active_visible


static func _build_shuffle_sequence(
	candidates:Array[String],
	final_path:String,
	step_count:int
) -> Array[String]:
	var result:Array[String] = []
	var pool:Array[String] = candidates.duplicate()
	pool.erase(final_path)
	pool.shuffle()

	var wanted_preview_count:int = maxi(step_count - 1,1)
	var cursor:int = 0
	var last_path:String = ""

	for _i:int in range(wanted_preview_count):
		if pool.is_empty():
			pool = candidates.duplicate()
			pool.erase(final_path)
			pool.shuffle()
		if pool.is_empty():
			break

		var selected:String = pool[cursor % pool.size()]
		cursor += 1
		if selected == last_path and pool.size() > 1:
			selected = pool[cursor % pool.size()]
			cursor += 1
		result.append(selected)
		last_path = selected

	result.append(final_path)
	return result


static func get_host_visual_world_size(host:ball) -> Vector2:
	if host == null or not is_instance_valid(host):
		return Vector2.ZERO
	var visual:Node2D = _get_active_visual(host)
	if visual == null:
		return Vector2.ZERO
	return _get_visual_world_size(visual)


# 真正变形完成后调用：只缩放目标角色的显示节点，不改碰撞体。
# 使用统一缩放，因此原图长宽比不会被破坏。
static func constrain_host_visual(
	host:ball,
	reference_world_size:Vector2,
	min_ratio:float,
	max_ratio:float
) -> void:
	if host == null or not is_instance_valid(host):
		return
	if reference_world_size.x <= 0.01 or reference_world_size.y <= 0.01:
		return

	var visual:Node2D = _get_active_visual(host)
	if visual == null:
		return

	var current_size:Vector2 = _get_visual_world_size(visual)
	if current_size.x <= 0.01 or current_size.y <= 0.01:
		return

	var factor:float = _calculate_uniform_size_factor(
		current_size,
		reference_world_size,
		min_ratio,
		max_ratio
	)
	if absf(factor - 1.0) <= 0.001:
		return

	visual.scale *= Vector2(factor,factor)

	# ball.gd 的碰撞挤压动画会回到 default_size.scale。
	# 同步这里，防止角色第一次碰撞后又突然恢复成原场景的大图/小图。
	if not host.default_size.is_empty() and visual == host.image:
		host.default_size["scale"] = visual.scale


static func _morph_between(
	host:ball,
	preview_sprite:Sprite2D,
	material:ShaderMaterial,
	to_descriptor:Dictionary,
	to_transform:Transform2D,
	morph_time:float,
	distortion_strength:float,
	preview_z:int
) -> void:
	var to_texture := to_descriptor.get("texture",null) as Texture2D
	if to_texture == null:
		return

	if material == null or material.shader == null:
		_apply_descriptor_plain(preview_sprite,to_descriptor,to_transform)
		preview_sprite.z_index = preview_z
		await host.get_tree().create_timer(maxf(morph_time,0.08)).timeout
		return

	var parent := preview_sprite.get_parent()
	if parent == null:
		return

	# 这次不是“溶解换图”：旧图和新图共用一条连续的几何轨迹。
	# 旧形态先被拧/拉向目标的 transform，新形态从完全扭曲的状态同步解开。
	# 两层都在移动，所以轮廓会明显从前一个形态扭成后一个形态，而不是只改颜色。
	var from_transform:Transform2D = preview_sprite.transform
	var target_sprite := Sprite2D.new()
	target_sprite.name = "MorphTargetPreview"
	target_sprite.texture_filter = preview_sprite.texture_filter
	target_sprite.texture_repeat = preview_sprite.texture_repeat
	target_sprite.visibility_layer = preview_sprite.visibility_layer
	parent.add_child(target_sprite)
	_apply_descriptor_plain(target_sprite,to_descriptor,from_transform)
	target_sprite.visible = true
	target_sprite.z_index = preview_z + 1

	var target_material := ShaderMaterial.new()
	target_material.shader = material.shader
	target_material.set_shader_parameter("morph_amount",0.0)
	target_material.set_shader_parameter("morph_role",1.0)
	target_material.set_shader_parameter("morph_strength",maxf(distortion_strength,0.0))
	target_sprite.material = target_material

	material.set_shader_parameter("morph_strength",maxf(distortion_strength,0.0))
	material.set_shader_parameter("morph_role",0.0)
	material.set_shader_parameter("morph_amount",0.0)
	preview_sprite.material = material
	preview_sprite.visible = true
	preview_sprite.z_index = preview_z

	var transition_time:float = maxf(morph_time * 0.94,0.08)
	var hold_time:float = maxf(morph_time - transition_time,0.01)
	var tween := host.create_tween()
	tween.tween_method(
		func(value:float) -> void:
			var t:float = clampf(value,0.0,1.0)
			# S 形插值让开始/结束不突兀，中段的扭曲速度更明显。
			var eased:float = t * t * (3.0 - 2.0 * t)
			var shared_transform:Transform2D = from_transform.interpolate_with(to_transform,eased)
			if is_instance_valid(preview_sprite):
				preview_sprite.transform = shared_transform
			if is_instance_valid(target_sprite):
				target_sprite.transform = shared_transform
			if is_instance_valid(material):
				material.set_shader_parameter("morph_amount",t)
			if is_instance_valid(target_material):
				target_material.set_shader_parameter("morph_amount",t),
		0.0,
		1.0,
		transition_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	if host == null or not is_instance_valid(host):
		return
	if preview_sprite == null or not is_instance_valid(preview_sprite):
		return

	_apply_descriptor_plain(preview_sprite,to_descriptor,to_transform)
	preview_sprite.z_index = preview_z
	preview_sprite.material = material
	material.set_shader_parameter("morph_role",0.0)
	material.set_shader_parameter("morph_amount",0.0)
	preview_sprite.visible = true

	if is_instance_valid(target_sprite):
		target_sprite.queue_free()

	await host.get_tree().create_timer(hold_time).timeout


static func _capture_sprite_state(sprite:Sprite2D) -> Dictionary:
	return {
		"visible": sprite.visible,
		"transform": sprite.transform,
		"texture": sprite.texture,
		"centered": sprite.centered,
		"offset": sprite.offset,
		"flip_h": sprite.flip_h,
		"flip_v": sprite.flip_v,
		"hframes": sprite.hframes,
		"vframes": sprite.vframes,
		"frame": sprite.frame,
		"region_enabled": sprite.region_enabled,
		"region_rect": sprite.region_rect,
		"region_filter_clip_enabled": sprite.region_filter_clip_enabled,
		"modulate": sprite.modulate,
		"self_modulate": sprite.self_modulate,
		"z_index": sprite.z_index,
		"material": sprite.material,
	}


static func _capture_runtime_visual_descriptor(host:ball,visual:Node2D) -> Dictionary:
	var texture:Texture2D = _visual_texture(visual)
	if texture == null:
		return {}

	var root_to_visual:Transform2D = host.global_transform.affine_inverse() * visual.global_transform
	return {
		"texture": texture,
		"pixel_size": _visual_pixel_size(visual,texture),
		"centered": _visual_centered(visual),
		"offset": _visual_offset(visual),
		"flip_h": _visual_flip_h(visual),
		"flip_v": _visual_flip_v(visual),
		"modulate": visual.modulate,
		"self_modulate": visual.self_modulate,
		"z_index": visual.z_index,
		"visual_transform_in_character": root_to_visual,
	}


static func _load_visual_descriptor(scene_path:String) -> Dictionary:
	if _descriptor_cache.has(scene_path):
		var cached = _descriptor_cache[scene_path]
		if cached is Dictionary:
			return cached.duplicate()

	# SceneState 专门用于“不实例化场景就读取 PackedScene 内容”。
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {}

	var state:SceneState = packed.get_state()
	if state == null:
		return {}

	var descriptor:Dictionary = _read_visual_descriptor_from_scene_state(state,{})
	if not descriptor.is_empty():
		_descriptor_cache[scene_path] = descriptor.duplicate()
	return descriptor


static func _read_visual_descriptor_from_scene_state(
	state:SceneState,
	visited:Dictionary
) -> Dictionary:
	if state == null:
		return {}

	var state_key:String = state.get_path()
	if state_key.is_empty():
		state_key = str(state.get_instance_id())
	if visited.has(state_key):
		return {}
	visited[state_key] = true

	var descriptor:Dictionary = {}
	var base_state:SceneState = state.get_base_scene_state()
	if base_state != null:
		descriptor = _read_visual_descriptor_from_scene_state(base_state,visited)

	var root_props:Dictionary = {}
	var graphics_props:Dictionary = {}
	var image_props:Dictionary = {}
	var animated_props:Dictionary = {}

	for node_index:int in range(state.get_node_count()):
		var node_name:String = str(state.get_node_name(node_index))
		var node_path:String = str(state.get_node_path(node_index))
		var props:Dictionary = _scene_state_node_properties(state,node_index)

		if node_index == 0:
			for key in props:
				root_props[key] = props[key]

		if node_name == "Graphics" and (
			node_path == "Graphics"
			or node_path.ends_with("/Graphics")
		):
			for key in props:
				graphics_props[key] = props[key]
		elif node_name == "Image" and (
			node_path == "Graphics/Image"
			or node_path.ends_with("/Graphics/Image")
		):
			for key in props:
				image_props[key] = props[key]
		elif node_name == "AnimatedSprite2D" and (
			node_path == "Graphics/AnimatedSprite2D"
			or node_path.ends_with("/Graphics/AnimatedSprite2D")
		):
			for key in props:
				animated_props[key] = props[key]

	var requested_image = root_props.get("image",null)
	var prefers_animated:bool = str(requested_image).contains("AnimatedSprite2D")

	if image_props.has("texture") and image_props["texture"] == null:
		var frames_candidate = animated_props.get("sprite_frames",null)
		if frames_candidate is SpriteFrames:
			prefers_animated = true

	var chosen_texture:Texture2D = null
	var chosen_props:Dictionary = image_props
	var visual_kind:String = str(descriptor.get("visual_kind","image"))

	var sprite_frames = animated_props.get("sprite_frames",null)
	if prefers_animated or sprite_frames is SpriteFrames:
		if sprite_frames is SpriteFrames:
			chosen_texture = _first_texture_from_sprite_frames_resource(sprite_frames as SpriteFrames)
			if chosen_texture != null:
				chosen_props = animated_props
				visual_kind = "animated"

	if chosen_texture == null:
		var image_texture = image_props.get("texture",null)
		if image_texture is Texture2D:
			chosen_texture = image_texture as Texture2D
			chosen_props = image_props
			visual_kind = "image"

	if chosen_texture != null:
		descriptor["texture"] = chosen_texture
		descriptor["pixel_size"] = chosen_texture.get_size()
		descriptor["visual_kind"] = visual_kind
	elif not descriptor.has("texture"):
		return {}
	else:
		if str(descriptor.get("visual_kind","image")) == "animated":
			chosen_props = animated_props
		else:
			chosen_props = image_props

	var base_position:Vector2 = descriptor.get("image_position",Vector2.ZERO)
	var base_scale:Vector2 = descriptor.get("image_scale",Vector2.ONE)
	var base_rotation:float = float(descriptor.get("image_rotation",0.0))
	var base_skew:float = float(descriptor.get("image_skew",0.0))
	var graphics_position:Vector2 = descriptor.get("graphics_position",Vector2.ZERO)
	var graphics_scale:Vector2 = descriptor.get("graphics_scale",Vector2.ONE)
	var graphics_rotation:float = float(descriptor.get("graphics_rotation",0.0))
	var graphics_skew:float = float(descriptor.get("graphics_skew",0.0))

	base_position = _variant_vector2(chosen_props.get("position",null),base_position)
	base_scale = _variant_vector2(chosen_props.get("scale",null),base_scale)
	base_rotation = _variant_float(chosen_props.get("rotation",null),base_rotation)
	base_skew = _variant_float(chosen_props.get("skew",null),base_skew)
	graphics_position = _variant_vector2(graphics_props.get("position",null),graphics_position)
	graphics_scale = _variant_vector2(graphics_props.get("scale",null),graphics_scale)
	graphics_rotation = _variant_float(graphics_props.get("rotation",null),graphics_rotation)
	graphics_skew = _variant_float(graphics_props.get("skew",null),graphics_skew)

	descriptor["image_position"] = base_position
	descriptor["image_scale"] = base_scale
	descriptor["image_rotation"] = base_rotation
	descriptor["image_skew"] = base_skew
	descriptor["graphics_position"] = graphics_position
	descriptor["graphics_scale"] = graphics_scale
	descriptor["graphics_rotation"] = graphics_rotation
	descriptor["graphics_skew"] = graphics_skew

	if chosen_props.has("centered"):
		descriptor["centered"] = bool(chosen_props["centered"])
	elif not descriptor.has("centered"):
		descriptor["centered"] = true

	if chosen_props.has("offset") and chosen_props["offset"] is Vector2:
		descriptor["offset"] = chosen_props["offset"]
	elif not descriptor.has("offset"):
		descriptor["offset"] = Vector2.ZERO

	if chosen_props.has("flip_h"):
		descriptor["flip_h"] = bool(chosen_props["flip_h"])
	elif not descriptor.has("flip_h"):
		descriptor["flip_h"] = false

	if chosen_props.has("flip_v"):
		descriptor["flip_v"] = bool(chosen_props["flip_v"])
	elif not descriptor.has("flip_v"):
		descriptor["flip_v"] = false

	if chosen_props.has("modulate") and chosen_props["modulate"] is Color:
		descriptor["modulate"] = chosen_props["modulate"]
	elif not descriptor.has("modulate"):
		descriptor["modulate"] = Color.WHITE

	if chosen_props.has("self_modulate") and chosen_props["self_modulate"] is Color:
		descriptor["self_modulate"] = chosen_props["self_modulate"]
	elif not descriptor.has("self_modulate"):
		descriptor["self_modulate"] = Color.WHITE

	if chosen_props.has("z_index"):
		descriptor["z_index"] = int(chosen_props["z_index"])
	elif not descriptor.has("z_index"):
		descriptor["z_index"] = 0

	var graphics_transform := Transform2D(
		graphics_rotation,
		graphics_scale,
		graphics_skew,
		graphics_position
	)
	var image_transform := Transform2D(
		base_rotation,
		base_scale,
		base_skew,
		base_position
	)
	descriptor["visual_transform_in_character"] = graphics_transform * image_transform
	return descriptor


static func _scene_state_node_properties(
	state:SceneState,
	node_index:int
) -> Dictionary:
	var result:Dictionary = {}
	for prop_index:int in range(state.get_node_property_count(node_index)):
		var prop_name:StringName = state.get_node_property_name(node_index,prop_index)
		result[prop_name] = state.get_node_property_value(node_index,prop_index)
	return result


static func _first_texture_from_sprite_frames_resource(frames:SpriteFrames) -> Texture2D:
	if frames == null:
		return null

	var animation_names:PackedStringArray = frames.get_animation_names()
	if animation_names.is_empty():
		return null

	var preferred:PackedStringArray = PackedStringArray([
		"default","Default","idle","Idle","stand","Stand","Move","move","站立","正常"
	])
	var ordered:Array[StringName] = []

	for wanted:String in preferred:
		if frames.has_animation(StringName(wanted)):
			ordered.append(StringName(wanted))

	for raw_name:String in animation_names:
		var name := StringName(raw_name)
		if not ordered.has(name):
			ordered.append(name)

	for animation_name:StringName in ordered:
		var count:int = frames.get_frame_count(animation_name)
		for frame_index:int in range(count):
			var texture:Texture2D = frames.get_frame_texture(animation_name,frame_index)
			if texture != null:
				return texture
	return null


static func _variant_vector2(value,default_value:Vector2) -> Vector2:
	if value is Vector2:
		return value
	return default_value


static func _variant_float(value,default_value:float) -> float:
	if value is float or value is int:
		return float(value)
	return default_value


static func _calculate_preview_transform(
	host:ball,
	_preview_sprite:Sprite2D,
	descriptor:Dictionary,
	reference_world_size:Vector2,
	min_ratio:float,
	max_ratio:float
) -> Transform2D:
	var desired_in_character:Transform2D = descriptor.get(
		"visual_transform_in_character",
		Transform2D.IDENTITY
	)

	# preview_sprite 是 host.graphics 的子节点，因此先把“角色根局部变换”转回 Graphics 局部。
	var result:Transform2D = host.graphics.transform.affine_inverse() * desired_in_character

	# 预览 Sprite 始终使用完整 texture 作为几何。
	# region/动画帧的实际视觉尺寸通过 pixel_size / texture_size 烘进 Transform，避免换图时尺寸爆炸。
	var texture := descriptor.get("texture",null) as Texture2D
	var texture_size:Vector2 = _texture_size_safe(texture)
	var pixel_size:Vector2 = descriptor.get("pixel_size",texture_size)
	if texture_size.x > 0.01 and texture_size.y > 0.01:
		result.x *= pixel_size.x / texture_size.x
		result.y *= pixel_size.y / texture_size.y

	var world_size:Vector2 = _descriptor_world_size(host,descriptor,result)
	var factor:float = _calculate_uniform_size_factor(
		world_size,
		reference_world_size,
		min_ratio,
		max_ratio
	)
	result.x *= factor
	result.y *= factor
	return result


static func _apply_descriptor_plain(
	preview_sprite:Sprite2D,
	descriptor:Dictionary,
	new_transform:Transform2D
) -> void:
	var texture := descriptor.get("texture",null) as Texture2D
	if texture == null:
		return

	preview_sprite.texture = texture
	preview_sprite.centered = bool(descriptor.get("centered",true))
	preview_sprite.offset = descriptor.get("offset",Vector2.ZERO)
	preview_sprite.flip_h = bool(descriptor.get("flip_h",false))
	preview_sprite.flip_v = bool(descriptor.get("flip_v",false))
	preview_sprite.hframes = 1
	preview_sprite.vframes = 1
	preview_sprite.frame = 0
	preview_sprite.region_enabled = false
	preview_sprite.transform = new_transform
	preview_sprite.modulate = descriptor.get("modulate",Color.WHITE)
	preview_sprite.self_modulate = descriptor.get("self_modulate",Color.WHITE)
	preview_sprite.z_index = int(descriptor.get("z_index",preview_sprite.z_index))
	preview_sprite.visible = true


static func _descriptor_world_size(
	host:ball,
	descriptor:Dictionary,
	preview_local_transform:Transform2D
) -> Vector2:
	var texture := descriptor.get("texture",null) as Texture2D
	if texture == null:
		return Vector2.ZERO

	var texture_size:Vector2 = _texture_size_safe(texture)
	var centered:bool = bool(descriptor.get("centered",true))
	var offset:Vector2 = descriptor.get("offset",Vector2.ZERO)
	var rect := Rect2(offset - texture_size * 0.5 if centered else offset,texture_size)
	var world_transform:Transform2D = host.graphics.global_transform * preview_local_transform
	return _rect_size_after_transform(rect,world_transform)


static func _calculate_uniform_size_factor(
	current_size:Vector2,
	reference_size:Vector2,
	min_ratio:float,
	max_ratio:float
) -> float:
	if current_size.x <= 0.01 or current_size.y <= 0.01:
		return 1.0
	if reference_size.x <= 0.01 or reference_size.y <= 0.01:
		return 1.0

	var safe_min:float = maxf(min_ratio,0.05)
	var safe_max:float = maxf(max_ratio,safe_min)
	var ref_diag:float = reference_size.length()
	var cur_diag:float = current_size.length()
	if ref_diag <= 0.01 or cur_diag <= 0.01:
		return 1.0

	# 先按“视觉整体大小（对角线）”限制到 min~max 区间。
	var target_diag:float = clampf(
		cur_diag,
		ref_diag * safe_min,
		ref_diag * safe_max
	)
	var factor:float = target_diag / cur_diag

	# 再保证任何一边都不会超过变形者对应边界。
	var max_box:Vector2 = reference_size * safe_max
	factor = minf(factor,max_box.x / current_size.x)
	factor = minf(factor,max_box.y / current_size.y)
	return maxf(factor,0.001)


static func _get_active_visual(host:ball) -> Node2D:
	if host.image is Sprite2D:
		var sprite := host.image as Sprite2D
		if sprite.texture != null:
			return sprite
	elif host.image is AnimatedSprite2D:
		var animated := host.image as AnimatedSprite2D
		if _visual_texture(animated) != null:
			return animated

	var image_sprite := host.get_node_or_null("Graphics/Image") as Sprite2D
	if image_sprite != null and image_sprite.texture != null:
		return image_sprite
	var animated_sprite := host.get_node_or_null("Graphics/AnimatedSprite2D") as AnimatedSprite2D
	if animated_sprite != null and _visual_texture(animated_sprite) != null:
		return animated_sprite
	return null


static func _visual_texture(visual:Node2D) -> Texture2D:
	if visual is Sprite2D:
		return (visual as Sprite2D).texture
	if visual is AnimatedSprite2D:
		var animated := visual as AnimatedSprite2D
		if animated.sprite_frames == null:
			return null
		var animation_name:StringName = animated.animation
		if not animated.sprite_frames.has_animation(animation_name):
			var names:PackedStringArray = animated.sprite_frames.get_animation_names()
			if names.is_empty():
				return null
			animation_name = StringName(names[0])
		var frame_count:int = animated.sprite_frames.get_frame_count(animation_name)
		if frame_count <= 0:
			return null
		var frame_index:int = clampi(animated.frame,0,frame_count - 1)
		return animated.sprite_frames.get_frame_texture(animation_name,frame_index)
	return null


static func _visual_pixel_size(visual:Node2D,texture:Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	if visual is Sprite2D:
		var sprite := visual as Sprite2D
		if sprite.region_enabled and sprite.region_rect.size.length_squared() > 0.01:
			return sprite.region_rect.size.abs()
		var frames_x:int = maxi(sprite.hframes,1)
		var frames_y:int = maxi(sprite.vframes,1)
		return texture.get_size() / Vector2(float(frames_x),float(frames_y))
	return texture.get_size()


static func _visual_centered(visual:Node2D) -> bool:
	if visual is Sprite2D:
		return (visual as Sprite2D).centered
	if visual is AnimatedSprite2D:
		return (visual as AnimatedSprite2D).centered
	return true


static func _visual_offset(visual:Node2D) -> Vector2:
	if visual is Sprite2D:
		return (visual as Sprite2D).offset
	if visual is AnimatedSprite2D:
		return (visual as AnimatedSprite2D).offset
	return Vector2.ZERO


static func _visual_flip_h(visual:Node2D) -> bool:
	if visual is Sprite2D:
		return (visual as Sprite2D).flip_h
	if visual is AnimatedSprite2D:
		return (visual as AnimatedSprite2D).flip_h
	return false


static func _visual_flip_v(visual:Node2D) -> bool:
	if visual is Sprite2D:
		return (visual as Sprite2D).flip_v
	if visual is AnimatedSprite2D:
		return (visual as AnimatedSprite2D).flip_v
	return false


static func _get_visual_world_size(visual:Node2D) -> Vector2:
	var rect:Rect2 = _visual_local_rect(visual)
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return Vector2.ZERO
	return _rect_size_after_transform(rect,visual.global_transform)


static func _visual_local_rect(visual:Node2D) -> Rect2:
	if visual is Sprite2D:
		return (visual as Sprite2D).get_rect()
	if visual is AnimatedSprite2D:
		var texture:Texture2D = _visual_texture(visual)
		if texture == null:
			return Rect2()
		var animated := visual as AnimatedSprite2D
		var size:Vector2 = texture.get_size()
		var origin:Vector2 = animated.offset
		if animated.centered:
			origin -= size * 0.5
		return Rect2(origin,size)
	return Rect2()


static func _rect_size_after_transform(rect:Rect2,xform:Transform2D) -> Vector2:
	var points:Array[Vector2] = [
		xform * rect.position,
		xform * (rect.position + Vector2(rect.size.x,0.0)),
		xform * (rect.position + Vector2(0.0,rect.size.y)),
		xform * (rect.position + rect.size),
	]
	var min_point:Vector2 = points[0]
	var max_point:Vector2 = points[0]
	for point:Vector2 in points:
		min_point.x = minf(min_point.x,point.x)
		min_point.y = minf(min_point.y,point.y)
		max_point.x = maxf(max_point.x,point.x)
		max_point.y = maxf(max_point.y,point.y)
	return max_point - min_point


static func _texture_size_safe(texture:Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ONE
	var size:Vector2 = texture.get_size()
	return Vector2(maxf(size.x,1.0),maxf(size.y,1.0))
