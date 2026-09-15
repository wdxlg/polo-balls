@tool
extends Node

# ========================================================
# CharacterAutoFit V4
#
# 目标：
# - 以“真正渲染出来的可见区域”为准统一人物大小。
# - 计算时包含 Graphics / Image 自己的 position / rotation / scale，
#   不再出现“图片已经放大/下移，但碰撞仍按旧尺寸”的情况。
# - AnimatedSprite2D 会扫描全部动画帧，碰撞按最大可见包围盒生成，
#   避免切 Attack/Skill 图片后突然跑出碰撞框。
# - 所有 RectangleShape2D 最终 scale 都保持 (1,1)，只改 Shape.size。
# ========================================================

@export_category("人物自动尺寸 / 碰撞")
@export var enabled:bool = true
@export var only_normal_characters:bool = true

# 角色根节点本地空间中的最长可见边。
# Ball 根节点默认 scale=0.2，所以 205 对应世界中约 41px。
@export_range(64.0,512.0,1.0) var visual_max_size:float = 205.0
# 个别召唤物/小型角色可以保持“真的更小”，不再被统一放大到人物尺寸。
@export_range(0.20,2.00,0.01) var visual_size_multiplier:float = 1.0

# 碰撞框按最终可见包围盒计算。
@export_range(0.10,1.50,0.01) var collision_width_ratio:float = 0.88
@export_range(0.10,1.50,0.01) var collision_height_ratio:float = 0.82
@export var collision_min_size:Vector2 = Vector2(100.0,105.0)
@export var collision_max_size:Vector2 = Vector2(180.0,180.0)

# 普通单帧 Sprite 自动去掉透明安全边距并把主体中心放回角色原点。
@export var center_visible_pixels:bool = true
# AnimatedSprite 多动画统一以所有帧的可见并集为基准，避免状态图尺寸不一致。
@export var scan_all_animated_frames:bool = true
# 某些 AnimatedSprite（例如夺舍狼）不同动画的图片尺寸差异很大。
# 开启后切换动画时会重新按“当前动画帧”拟合视觉与碰撞，而不是用所有动画的最大并集。
@export var refit_on_animation_change:bool = false

@export_category("手动碰撞保护")
# 开启后：新角色仍会自动拟合碰撞；一旦场景里保存了自己的碰撞设置，
# 或者用户修改了 AutoFit 上一次生成的结果，就不再覆盖该碰撞。
@export var preserve_manual_collision:bool = true

@export_category("调试")
@export var print_fit_result:bool = false

const _META_MANAGED := "_character_auto_fit_v3_managed"
const _META_MANUAL := "_character_auto_fit_v3_manual"
const _META_LAST_AUTO := "_character_auto_fit_v3_last_auto"

# V412：AutoFit 的透明像素包围盒只取决于纹理/Region，本来却会在每个角色实例出生时重复
# Texture2D.get_image() + get_used_rect()。同角色大量生成时这是明显的同步尖峰。
# 缓存只保存“原始纹理里的 used rect”，centered / offset 仍在每个实例上实时套用，因此结果完全一致。
static var _shared_texture_used_rect_cache:Dictionary = {}
static var _shared_region_used_rect_cache:Dictionary = {}

# V277：杀戮尖塔人物旧场景普遍保存了远大于人物图片的手动 CollisionShape2D。
# 对这个分区统一强制使用更紧的 Alpha 可见范围碰撞，且覆盖旧“手动保护”结果。
const SLAY_SPIRE_CHARACTER_SCENE_PREFIX:String = "res://scenes/characters/杀戮尖塔/"
const SLAY_SPIRE_COLLISION_WIDTH_RATIO:float = 0.62
const SLAY_SPIRE_COLLISION_HEIGHT_RATIO:float = 0.68
const SLAY_SPIRE_COLLISION_MIN_SIZE:Vector2 = Vector2(54.0,62.0)
const SLAY_SPIRE_COLLISION_MAX_SIZE:Vector2 = Vector2(128.0,142.0)

func _ready() -> void:
	# V4：编辑器里只做一次“初始自动拟合”，之后绝不持续轮询碰撞属性。
	# 这样新角色打开时仍能得到自动碰撞，但用户开始手调 CollisionShape2D 后，
	# @tool 不会在下一帧又把 position / scale / shape 写回自动值。
	if Engine.is_editor_hint():
		set_process(false)
		call_deferred("_apply_initial_editor_fit")
		return

	set_process(false)
	_connect_animation_refit_if_needed()
	apply_fit()


func _apply_initial_editor_fit() -> void:
	if not Engine.is_editor_hint():
		return
	# SceneState 手动保护会在这里先判断；已有场景级碰撞覆盖不会被改。
	# 没有手调覆盖的新角色则在本次打开时自动拟合一次。
	apply_fit()


func _connect_animation_refit_if_needed() -> void:
	if not refit_on_animation_change:
		return
	var character := get_parent()
	if character == null:
		return
	var animated := character.get_node_or_null("Graphics/AnimatedSprite2D") as AnimatedSprite2D
	if animated != null and not animated.animation_changed.is_connected(_on_animated_animation_changed):
		animated.animation_changed.connect(_on_animated_animation_changed)


func _on_animated_animation_changed() -> void:
	# 延后一帧，确保 AnimatedSprite2D 的新动画/纹理已经生效。
	call_deferred("apply_fit")


func apply_visual_fit_only() -> void:
	# 运行时替换人物状态贴图时，只重新拟合视觉，不改变已经稳定下来的碰撞框。
	if not enabled:
		return

	var character := get_parent()
	if character == null:
		return

	if only_normal_characters:
		var type_value = character.get("Type")
		if type_value == null or int(type_value) != 0:
			return

	_fit_character_image(character)
	if character.has_method("refresh_character_ground_shadow"):
		character.call_deferred("refresh_character_ground_shadow")


func apply_fit() -> void:
	if not enabled:
		return

	var character := get_parent()
	if character == null:
		return

	if only_normal_characters:
		var type_value = character.get("Type")
		if type_value == null or int(type_value) != 0:
			return

	var metrics:Dictionary = _fit_character_image(character)
	if metrics.is_empty():
		return

	var bounds:Rect2 = metrics.get("bounds",Rect2())
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	var size_multiplier:float = maxf(visual_size_multiplier,0.01)
	var force_compact_slay_spire:bool = _is_slay_spire_character(character)
	var width_ratio:float = SLAY_SPIRE_COLLISION_WIDTH_RATIO if force_compact_slay_spire else collision_width_ratio
	var height_ratio:float = SLAY_SPIRE_COLLISION_HEIGHT_RATIO if force_compact_slay_spire else collision_height_ratio
	var configured_min:Vector2 = SLAY_SPIRE_COLLISION_MIN_SIZE if force_compact_slay_spire else collision_min_size
	var configured_max:Vector2 = SLAY_SPIRE_COLLISION_MAX_SIZE if force_compact_slay_spire else collision_max_size
	var min_size := Vector2(
		minf(configured_min.x,configured_max.x),
		minf(configured_min.y,configured_max.y)
	) * size_multiplier
	var max_size := Vector2(
		maxf(configured_min.x,configured_max.x),
		maxf(configured_min.y,configured_max.y)
	) * size_multiplier

	var collision_size := Vector2(
		clampf(bounds.size.x * width_ratio,min_size.x,max_size.x),
		clampf(bounds.size.y * height_ratio,min_size.y,max_size.y)
	)
	_apply_collision_size(character,collision_size,bounds.get_center(),force_compact_slay_spire)
	if character.has_method("refresh_character_ground_shadow"):
		character.call_deferred("refresh_character_ground_shadow")

	if print_fit_result and not Engine.is_editor_hint():
		print(
			"[CharacterAutoFitV4] ",character.name,
			" bounds=",bounds,
			" image_scale=",metrics.get("fit_scale",1.0),
			" collision=",collision_size,
			" collision_center=",bounds.get_center()
		)


func _fit_character_image(character:Node) -> Dictionary:
	var graphics := character.get_node_or_null("Graphics") as Node2D
	if graphics == null:
		return {}

	var sprite := graphics.get_node_or_null("Image") as Sprite2D
	if sprite != null and sprite.texture != null:
		return _fit_sprite2d(graphics,sprite)

	var animated := graphics.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if animated != null and animated.sprite_frames != null:
		return _fit_animated_sprite2d(graphics,animated)

	return {}


func _fit_sprite2d(graphics:Node2D,sprite:Sprite2D) -> Dictionary:
	var texture:Texture2D = sprite.texture
	if texture == null:
		return {}

	# 某些角色（例如殷红迷雾）由独立的 @tool 视觉脚本管理多张动作图。
	# 这种情况下 CharacterAutoFit 仍然读取最终可见范围来算碰撞，但绝不能再修改
	# Sprite2D 的 centered / offset / scale / position，否则编辑器里的逐动作微调会被覆盖。
	var preserve_external_visual:bool = bool(sprite.get_meta("character_auto_fit_preserve_visual", false))

	var local_visible_rect:Rect2
	var used_alpha:bool = false

	# Region 必须继续保持裁切构图（军官就是这种情况），
	# 但尺寸计算只看 region 内真正非透明的人物像素，避免透明留白把角色缩得过小。
	if sprite.region_enabled:
		var region_used:Dictionary = _texture_used_rect_in_region(
			texture,
			sprite.region_rect,
			sprite.centered,
			sprite.offset
		)
		local_visible_rect = region_used.get("rect",sprite.get_rect())
		used_alpha = bool(region_used.get("used_alpha",false))
	elif sprite.hframes > 1 or sprite.vframes > 1:
		local_visible_rect = sprite.get_rect()
	else:
		var used:Dictionary = _texture_used_rect(texture,sprite.centered,sprite.offset)
		local_visible_rect = used.get("rect",Rect2())
		used_alpha = bool(used.get("used_alpha",false))

		if center_visible_pixels and used_alpha and sprite.centered and not preserve_external_visual:
			# 普通单帧图可以按 Alpha 主体重新居中。
			# Region 图不在这里改 offset，确保设计好的裁切构图不会被移动。
			var center_delta:Vector2 = local_visible_rect.get_center()
			sprite.offset -= center_delta
			local_visible_rect.position -= center_delta

	if local_visible_rect.size.x <= 0.0 or local_visible_rect.size.y <= 0.0:
		return {}

	if preserve_external_visual:
		# 多动作角色可提供一个固定的“碰撞参考构图”。这样编辑器预览攻击/斩杀图片时，
		# CharacterAutoFit 不会把碰撞框跟着当前预览图的位置和超长特效一起拖走。
		if sprite.has_method("get_autofit_reference_visual"):
			var reference:Variant = sprite.call("get_autofit_reference_visual")
			if reference is Dictionary:
				var reference_data:Dictionary = reference
				var reference_texture:Texture2D = reference_data.get("texture") as Texture2D
				if reference_texture != null:
					var reference_centered:bool = bool(reference_data.get("centered",true))
					var reference_offset:Vector2 = reference_data.get("offset",Vector2.ZERO)
					var reference_used:Dictionary = _texture_used_rect(reference_texture,reference_centered,reference_offset)
					var reference_rect:Rect2 = reference_used.get("rect",Rect2())
					if reference_rect.size.x > 0.0 and reference_rect.size.y > 0.0:
						var reference_position:Vector2 = reference_data.get("position",Vector2.ZERO)
						var reference_scale:Vector2 = reference_data.get("scale",Vector2.ONE)
						var reference_transform := Transform2D(
							Vector2(reference_scale.x,0.0),
							Vector2(0.0,reference_scale.y),
							reference_position
						)
						var reference_bounds:Rect2 = _transform_rect(graphics.transform * reference_transform,reference_rect)
						return {
							"bounds": reference_bounds,
							"fit_scale": reference_scale.x,
						}

		var preserved_bounds:Rect2 = _transform_rect(graphics.transform * sprite.transform,local_visible_rect)
		return {
			"bounds": preserved_bounds,
			"fit_scale": sprite.scale.x,
		}

	# 先用 scale=1 计算 Graphics / Image 现有 transform 对最终视觉大小的影响。
	sprite.scale = Vector2.ONE
	var base_bounds:Rect2 = _transform_rect(graphics.transform * sprite.transform,local_visible_rect)
	var longest:float = maxf(base_bounds.size.x,base_bounds.size.y)
	if longest <= 0.0001:
		return {}

	var target_visual_size:float = maxf(visual_max_size * maxf(visual_size_multiplier,0.01),1.0)
	var fit_scale:float = target_visual_size / longest
	sprite.scale = Vector2(fit_scale,fit_scale)
	var final_bounds:Rect2 = _transform_rect(graphics.transform * sprite.transform,local_visible_rect)

	return {
		"bounds": final_bounds,
		"fit_scale": fit_scale,
	}


func _fit_animated_sprite2d(graphics:Node2D,animated:AnimatedSprite2D) -> Dictionary:
	if animated.sprite_frames == null:
		return {}

	# V68：AnimatedSprite2D 也支持与 Sprite2D 相同的“外部视觉脚本接管”。
	# 伞夫的快速构图脚本直接挂在 AnimatedSprite2D 上，编辑器里拖/缩后的逐动作构图
	# 不能再被 CharacterAutoFit 覆盖。若视觉脚本提供固定参考构图，就只用它计算碰撞参考范围。
	var preserve_external_visual:bool = bool(animated.get_meta("character_auto_fit_preserve_visual",false))
	if preserve_external_visual and animated.has_method("get_autofit_reference_visual"):
		var reference:Variant = animated.call("get_autofit_reference_visual")
		if reference is Dictionary:
			var reference_data:Dictionary = reference
			var reference_texture:Texture2D = reference_data.get("texture") as Texture2D
			if reference_texture != null:
				var reference_centered:bool = bool(reference_data.get("centered",true))
				var reference_offset:Vector2 = reference_data.get("offset",Vector2.ZERO)
				var reference_used:Dictionary = _texture_used_rect(reference_texture,reference_centered,reference_offset)
				var reference_rect:Rect2 = reference_used.get("rect",Rect2())
				if reference_rect.size.x > 0.0 and reference_rect.size.y > 0.0:
					var reference_position:Vector2 = reference_data.get("position",Vector2.ZERO)
					var reference_scale:Vector2 = reference_data.get("scale",Vector2.ONE)
					var reference_transform := Transform2D(
						Vector2(reference_scale.x,0.0),
						Vector2(0.0,reference_scale.y),
						reference_position
					)
					var reference_bounds:Rect2 = _transform_rect(graphics.transform * reference_transform,reference_rect)
					return {
						"bounds":reference_bounds,
						"fit_scale":reference_scale.x,
					}

	var union_rect:Rect2 = Rect2()
	var has_rect:bool = false
	var animation_names:PackedStringArray = animated.sprite_frames.get_animation_names()

	if not scan_all_animated_frames or refit_on_animation_change:
		animation_names = PackedStringArray([str(animated.animation)])

	for animation_name in animation_names:
		if not animated.sprite_frames.has_animation(animation_name):
			continue
		var frame_count:int = animated.sprite_frames.get_frame_count(animation_name)
		for frame_index in range(frame_count):
			var texture:Texture2D = animated.sprite_frames.get_frame_texture(animation_name,frame_index)
			if texture == null:
				continue
			var used:Dictionary = _texture_used_rect(texture,animated.centered,animated.offset)
			var rect:Rect2 = used.get("rect",Rect2())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			if not has_rect:
				union_rect = rect
				has_rect = true
			else:
				union_rect = union_rect.merge(rect)

	if not has_rect:
		return {}

	# AnimatedSprite 的 offset 是所有帧共享的，所以只移动“所有帧并集”的中心。
	if center_visible_pixels and animated.centered:
		var center_delta:Vector2 = union_rect.get_center()
		animated.offset -= center_delta
		union_rect.position -= center_delta

	animated.scale = Vector2.ONE
	var base_bounds:Rect2 = _transform_rect(graphics.transform * animated.transform,union_rect)
	var longest:float = maxf(base_bounds.size.x,base_bounds.size.y)
	if longest <= 0.0001:
		return {}

	var target_visual_size:float = maxf(visual_max_size * maxf(visual_size_multiplier,0.01),1.0)
	var fit_scale:float = target_visual_size / longest
	animated.scale = Vector2(fit_scale,fit_scale)
	var final_bounds:Rect2 = _transform_rect(graphics.transform * animated.transform,union_rect)

	return {
		"bounds": final_bounds,
		"fit_scale": fit_scale,
	}


func _texture_used_rect_in_region(
	texture:Texture2D,
	region_rect:Rect2,
	centered:bool,
	offset:Vector2
) -> Dictionary:
	var texture_size:Vector2 = texture.get_size()
	var region_size:Vector2 = region_rect.size.abs()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return {}
	if region_size.x <= 0.0 or region_size.y <= 0.0:
		return {}

	var requested := Rect2i(
		Vector2i(floori(region_rect.position.x),floori(region_rect.position.y)),
		Vector2i(ceili(region_size.x),ceili(region_size.y))
	)
	var image_bounds := Rect2i(Vector2i.ZERO,Vector2i(texture_size))
	var clipped:Rect2i = requested.intersection(image_bounds)

	var used_position:Vector2 = Vector2.ZERO
	var used_size:Vector2 = region_size
	var used_alpha:bool = false

	var cache_key:String = "%s|%d,%d,%d,%d|%d,%d,%d,%d" % [
		str(texture.get_rid()),
		requested.position.x,requested.position.y,requested.size.x,requested.size.y,
		clipped.position.x,clipped.position.y,clipped.size.x,clipped.size.y,
	]
	if _shared_region_used_rect_cache.has(cache_key):
		var cached:Dictionary = _shared_region_used_rect_cache[cache_key]
		used_position = cached.get("position",Vector2.ZERO)
		used_size = cached.get("size",region_size)
		used_alpha = bool(cached.get("used_alpha",false))
	else:
		var image:Image = texture.get_image()
		if (
			image != null
			and not image.is_empty()
			and clipped.size.x > 0
			and clipped.size.y > 0
		):
			var region_image:Image = image.get_region(clipped)
			if region_image != null and not region_image.is_empty():
				var used_rect:Rect2i = region_image.get_used_rect()
				if used_rect.size.x > 0 and used_rect.size.y > 0:
					# 转回以“请求的 region 左上角”为原点的局部坐标。
					used_position = Vector2(clipped.position - requested.position + used_rect.position)
					used_size = Vector2(used_rect.size)
					used_alpha = true
		_shared_region_used_rect_cache[cache_key] = {
			"position":used_position,
			"size":used_size,
			"used_alpha":used_alpha,
		}

	var origin:Vector2 = offset + used_position
	if centered:
		origin -= region_size * 0.5

	return {
		"rect": Rect2(origin,used_size),
		"used_alpha": used_alpha,
	}


func _texture_used_rect(texture:Texture2D,centered:bool,offset:Vector2) -> Dictionary:
	var texture_size:Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return {}

	var used_position:Vector2 = Vector2.ZERO
	var used_size:Vector2 = texture_size
	var used_alpha:bool = false

	var cache_key:String = str(texture.get_rid())
	if _shared_texture_used_rect_cache.has(cache_key):
		var cached:Dictionary = _shared_texture_used_rect_cache[cache_key]
		used_position = cached.get("position",Vector2.ZERO)
		used_size = cached.get("size",texture_size)
		used_alpha = bool(cached.get("used_alpha",false))
	else:
		var image:Image = texture.get_image()
		if image != null and not image.is_empty():
			var used_rect:Rect2i = image.get_used_rect()
			if used_rect.size.x > 0 and used_rect.size.y > 0:
				used_position = Vector2(used_rect.position)
				used_size = Vector2(used_rect.size)
				used_alpha = true
		_shared_texture_used_rect_cache[cache_key] = {
			"position":used_position,
			"size":used_size,
			"used_alpha":used_alpha,
		}

	var origin:Vector2 = offset + used_position
	if centered:
		origin -= texture_size * 0.5

	return {
		"rect": Rect2(origin,used_size),
		"used_alpha": used_alpha,
	}


func _transform_rect(xform:Transform2D,rect:Rect2) -> Rect2:
	var points:Array[Vector2] = [
		xform * rect.position,
		xform * Vector2(rect.end.x,rect.position.y),
		xform * rect.end,
		xform * Vector2(rect.position.x,rect.end.y),
	]
	var min_p:Vector2 = points[0]
	var max_p:Vector2 = points[0]
	for point in points:
		min_p.x = minf(min_p.x,point.x)
		min_p.y = minf(min_p.y,point.y)
		max_p.x = maxf(max_p.x,point.x)
		max_p.y = maxf(max_p.y,point.y)
	return Rect2(min_p,max_p - min_p)


func _is_slay_spire_character(character:Node) -> bool:
	if character == null:
		return false
	return character.scene_file_path.begins_with(SLAY_SPIRE_CHARACTER_SCENE_PREFIX)


func _apply_collision_size(character:Node,collision_size:Vector2,collision_center:Vector2,force_replace_manual:bool = false) -> void:
	var paths:Array[NodePath] = [
		NodePath("CollisionShape2D"),
		NodePath("hitbox/CollisionShape2D"),
		NodePath("hurtbox/CollisionShape2D"),
	]

	for path in paths:
		var collision := character.get_node_or_null(path) as CollisionShape2D
		if collision == null:
			continue

		if not force_replace_manual and preserve_manual_collision and _collision_should_be_preserved(character,collision,path):
			continue

		var shape := RectangleShape2D.new()
		shape.resource_local_to_scene = true
		shape.size = collision_size
		collision.shape = shape
		# Godot 官方建议 CollisionShape2D 的 Node2D scale 保持 (1,1)。
		collision.scale = Vector2.ONE
		collision.position = collision_center

		# 记住 AutoFit 自己最后一次生成的状态。之后用户只要手动改过任意一项，
		# 就会与这个快照不同，并自动进入“手动保护”，不会再被开局重算覆盖。
		collision.set_meta(_META_MANAGED,true)
		collision.set_meta(_META_MANUAL,false)
		collision.set_meta(_META_LAST_AUTO,_collision_state_signature(collision))


func _collision_should_be_preserved(character:Node,collision:CollisionShape2D,path:NodePath) -> bool:
	if bool(collision.get_meta(_META_MANUAL,false)):
		return true

	if bool(collision.get_meta(_META_MANAGED,false)):
		var last_auto:String = str(collision.get_meta(_META_LAST_AUTO,""))
		if not last_auto.is_empty() and not _collision_signature_matches(last_auto,_collision_state_signature(collision)):
			# AutoFit 管理过，但现在的值与上次自动结果不同：视为用户手动调整。
			collision.set_meta(_META_MANAGED,false)
			collision.set_meta(_META_MANUAL,true)
			return true
		return false

	# 兼容旧项目：旧角色没有 V3 元数据。
	# 如果当前继承场景文件已经保存了 shape / position / scale / rotation 的覆盖值，
	# 就把现有结果当作角色自己的设计值保护起来。
	# 没有任何场景级碰撞覆盖的新角色，仍会在第一次初始化时自动拟合。
	if _scene_has_saved_collision_override(character,path):
		collision.set_meta(_META_MANUAL,true)
		return true

	return false


func _scene_has_saved_collision_override(character:Node,path:NodePath) -> bool:
	var scene_path:String = character.scene_file_path
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return false

	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return false
	var state:SceneState = packed.get_state()
	if state == null:
		return false

	# 非继承的基础场景（例如 ball.tscn 自身）没有“本地覆盖”这一概念，
	# 继续允许 AutoFit 按初始化规则工作。
	if state.get_base_scene_state() == null:
		return false

	var wanted_path:String = str(path)
	for node_idx in range(state.get_node_count()):
		if str(state.get_node_path(node_idx)) != wanted_path:
			continue
		for prop_idx in range(state.get_node_property_count(node_idx)):
			var prop_name:String = str(state.get_node_property_name(node_idx,prop_idx))
			if prop_name in ["shape","position","scale","rotation","rotation_degrees"]:
				return true
	return false


func _collision_state_signature(collision:CollisionShape2D) -> String:
	var shape_type:String = "null"
	var shape_values:String = ""
	if collision.shape != null:
		shape_type = collision.shape.get_class()
		if collision.shape is RectangleShape2D:
			shape_values = str((collision.shape as RectangleShape2D).size)
		elif collision.shape is CircleShape2D:
			shape_values = str((collision.shape as CircleShape2D).radius)
		elif collision.shape is CapsuleShape2D:
			var capsule := collision.shape as CapsuleShape2D
			shape_values = "%s|%s" % [capsule.radius,capsule.height]
	return "%s|%s|%s|%s|%s" % [
		shape_type,
		shape_values,
		str(collision.position),
		str(collision.scale),
		str(collision.rotation),
	]


func _collision_signature_matches(a:String,b:String) -> bool:
	# 快照来自 Godot 自己的 Variant 字符串；正常情况下可直接精确比较。
	# 单独保留函数，后续如需要兼容旧浮点格式可在这里扩展容差逻辑。
	return a == b
