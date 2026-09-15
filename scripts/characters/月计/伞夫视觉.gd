@tool
extends Sprite2D

# V70：伞夫视觉改回与“殷红迷雾 / 堇紫泪滴”同构的 Graphics/Image(Sprite2D) 路线。
# Graphics/AnimatedSprite2D 只作为隐藏动画时钟，人物真正显示、左右翻转、AutoFit 与编辑器构图
# 全部由 ball.tscn 原生的 Graphics/Image 承担。
# 这样避免 AnimatedSprite2D 自己的 offset / 每帧绘制矩形 / Shader 翻转与构图工具叠加。

enum PreviewPose {
	IDLE,
	ATTACK1,
	ATTACK2,
	ATTACK3,
	DEFENSE,
}

const POSE_COUNT:int = 5
const POSE_NAMES:Array[StringName] = [&"Idle", &"Attack1", &"Attack2", &"Attack3", &"Defense"]

@export_category("伞夫 - 快速构图")
@export var animation_frames:SpriteFrames
@export var editor_preview_enabled:bool = true:
	set(value):
		editor_preview_enabled = value
		if Engine.is_editor_hint() and is_inside_tree():
			set_process(value)
			if value:
				call_deferred("_apply_editor_preview")
			else:
				call_deferred("_update_neighbor_previews")
			notify_property_list_changed()

@export_enum("Idle","Attack1","Attack2","Attack3","Defense") var editor_preview_pose:int = PreviewPose.IDLE:
	set(value):
		var next_pose:int = clampi(value,0,POSE_COUNT - 1)
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled and editor_preview_pose != next_pose:
			_capture_transform_if_changed()
		editor_preview_pose = next_pose
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled:
			call_deferred("_apply_editor_preview")
			notify_property_list_changed()

@export_range(64.0,512.0,1.0) var target_display_height:float = 205.0:
	set(value):
		target_display_height = maxf(value,1.0)
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled:
			call_deferred("_apply_editor_preview")

@export var common_position:Vector2 = Vector2.ZERO:
	set(value):
		common_position = value
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled:
			call_deferred("_apply_editor_preview")

@export var auto_capture_2d_transform:bool = true

@export_group("相邻动作参考")
@export var preview_previous_pose:bool = false:
	set(value):
		preview_previous_pose = value
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_update_neighbor_previews")
			notify_property_list_changed()
@export var preview_next_pose:bool = false:
	set(value):
		preview_next_pose = value
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_update_neighbor_previews")
			notify_property_list_changed()
@export_range(0.05,0.75,0.01) var neighbor_preview_alpha:float = 0.24:
	set(value):
		neighbor_preview_alpha = clampf(value,0.05,0.75)
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_update_neighbor_previews")

@export_group("")
@export_tool_button("◀ 上一张") var previous_pose_button:Callable = _editor_previous_pose
@export_tool_button("下一张 ▶") var next_pose_button:Callable = _editor_next_pose
@export_tool_button("复制上一张构图") var copy_previous_button:Callable = _editor_copy_previous_layout
@export_tool_button("重置当前：等高 + 居中") var reset_current_button:Callable = _editor_reset_current_layout
@export_tool_button("强制记录当前 Transform") var capture_current_button:Callable = _editor_force_capture

# 与另外两个月计角色一致：每个动作只保存自己的额外 scale / position。
@export_storage var idle_scale:float = 1.0
@export_storage var idle_position:Vector2 = Vector2.ZERO
@export_storage var attack1_scale:float = 1.0
@export_storage var attack1_position:Vector2 = Vector2.ZERO
@export_storage var attack2_scale:float = 1.0
@export_storage var attack2_position:Vector2 = Vector2.ZERO
@export_storage var attack3_scale:float = 1.0
@export_storage var attack3_position:Vector2 = Vector2.ZERO
@export_storage var defense_scale:float = 1.0
@export_storage var defense_position:Vector2 = Vector2.ZERO

# 动画角色额外记录一个“构图参考帧”；只用于编辑器主预览和相邻参考。
@export_storage var idle_anchor_frame:int = 0
@export_storage var attack1_anchor_frame:int = 0
@export_storage var attack2_anchor_frame:int = 0
@export_storage var attack3_anchor_frame:int = 0
@export_storage var defense_anchor_frame:int = 0

var _runtime_pose:StringName = &"Idle"
var _runtime_flipped_h:bool = false
var _runtime_frame:int = 0
var _last_editor_pose:int = -1
var _last_target_height:float = -1.0
var _last_common_position:Vector2 = Vector2(INF,INF)
var _last_applied_position:Vector2 = Vector2.ZERO
var _last_applied_scale:Vector2 = Vector2.ONE
var _suppress_capture:bool = false
var _previous_preview_sprite:Sprite2D = null
var _next_preview_sprite:Sprite2D = null


func _ready() -> void:
	set_meta("character_auto_fit_preserve_visual",true)
	centered = true
	offset = Vector2.ZERO
	if Engine.is_editor_hint():
		set_process(editor_preview_enabled)
		if editor_preview_enabled:
			call_deferred("_apply_editor_preview")
		else:
			call_deferred("_update_neighbor_previews")
	else:
		set_process(false)
		apply_runtime_pose(_runtime_pose)


func _process(_delta:float) -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return
	var clamped_pose:int = clampi(editor_preview_pose,0,POSE_COUNT - 1)
	if editor_preview_pose != clamped_pose:
		editor_preview_pose = clamped_pose
	if (
		_last_editor_pose != editor_preview_pose
		or not is_equal_approx(_last_target_height,target_display_height)
		or not _last_common_position.is_equal_approx(common_position)
	):
		_apply_editor_preview()
		return
	if auto_capture_2d_transform and not _suppress_capture:
		_capture_transform_if_changed()


# 运行时由伞夫.gd 的隐藏 AnimatedSprite2D 动画时钟调用。
func sync_from_animation(pose:StringName,frame_index:int,flipped:bool) -> void:
	_runtime_pose = _normalize_pose(pose)
	_runtime_frame = _clamped_frame(_runtime_pose,frame_index)
	_runtime_flipped_h = flipped
	_apply_runtime_texture()
	_apply_runtime_transform()


func apply_runtime_pose(pose:StringName) -> void:
	_runtime_pose = _normalize_pose(pose)
	_runtime_frame = _clamped_frame(_runtime_pose,_runtime_frame)
	_apply_runtime_texture()
	_apply_runtime_transform()


# V76：与殷红迷雾 / 堇紫泪滴保持同一套“绕角色中心翻转”逻辑。
# 用户在右向构图时保存的 pose_position.x 同时承担了素材透明留白/人物中心的对齐补偿。
# 因此左向必须把这份构图补偿一起镜像；只翻纹理却保持 position.x 不变，
# 会让人物可见中心在左右朝向之间跳动。
func apply_runtime_flip(flipped:bool) -> void:
	_runtime_flipped_h = flipped
	if Engine.is_editor_hint():
		return
	var tweak:Dictionary = _layout_for_pose(_runtime_pose)
	var pose_position:Vector2 = tweak.get("position",Vector2.ZERO)
	position = _runtime_position_for_pose(pose_position)
	_last_applied_position = position


func get_autofit_reference_visual() -> Dictionary:
	var tex:Texture2D = _reference_texture_for_pose(&"Idle")
	var auto_scale:float = _auto_scale_for_texture(tex)
	return {
		"texture":tex,
		"position":common_position + idle_position,
		"scale":Vector2.ONE * auto_scale * maxf(idle_scale,0.01),
		"centered":true,
		"offset":Vector2.ZERO,
	}


func _apply_runtime_texture() -> void:
	if Engine.is_editor_hint():
		return
	var tex:Texture2D = _texture_for_frame(_runtime_pose,_runtime_frame)
	if tex != null:
		texture = tex
	centered = true
	offset = Vector2.ZERO


func _apply_runtime_transform() -> void:
	if Engine.is_editor_hint():
		return
	var tweak:Dictionary = _layout_for_pose(_runtime_pose)
	var reference_tex:Texture2D = _reference_texture_for_pose(_runtime_pose)
	var final_scale:float = _auto_scale_for_texture(reference_tex) * maxf(float(tweak.get("scale",1.0)),0.01)
	var pose_position:Vector2 = tweak.get("position",Vector2.ZERO)
	scale = Vector2.ONE * final_scale
	position = _runtime_position_for_pose(pose_position)
	rotation = 0.0
	_last_applied_position = position
	_last_applied_scale = scale


func _runtime_position_for_pose(pose_position:Vector2) -> Vector2:
	# 与另外两个月计角色一致：把动作构图的 X 偏移绕 common_position 镜像。
	# 右向保持用户在编辑器里调好的位置；左向使用相反 X，配合 Shader 纹理翻转，
	# 使“人物可见中心”而不是 PNG 画布中心围绕角色根节点翻转。
	var mirrored_x:float = -pose_position.x if _runtime_flipped_h else pose_position.x
	return common_position + Vector2(mirrored_x,pose_position.y)


func _apply_editor_preview() -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return
	var pose:StringName = _pose_name_for_preview(editor_preview_pose)
	var tex:Texture2D = _anchor_texture_for_pose(pose)
	if tex == null:
		return
	_suppress_capture = true
	texture = tex
	centered = true
	offset = Vector2.ZERO
	var tweak:Dictionary = _layout_for_pose(pose)
	var final_scale:float = _auto_scale_for_texture(_reference_texture_for_pose(pose)) * maxf(float(tweak.get("scale",1.0)),0.01)
	var preview_position:Vector2 = tweak.get("position",Vector2.ZERO)
	position = common_position + preview_position
	scale = Vector2.ONE * final_scale
	rotation = 0.0
	flip_h = false
	flip_v = false
	_last_applied_position = position
	_last_applied_scale = scale
	_last_editor_pose = editor_preview_pose
	_last_target_height = target_display_height
	_last_common_position = common_position
	_suppress_capture = false
	_update_neighbor_previews()
	notify_property_list_changed()


func _update_neighbor_previews() -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_neighbor_preview_sprites()
	if _previous_preview_sprite == null or _next_preview_sprite == null:
		return
	var can_show:bool = editor_preview_enabled and is_visible_in_tree()
	_previous_preview_sprite.visible = can_show and preview_previous_pose
	_next_preview_sprite.visible = can_show and preview_next_pose
	if not can_show:
		return
	if preview_previous_pose:
		_apply_neighbor_preview(
			_previous_preview_sprite,
			posmod(editor_preview_pose - 1,POSE_COUNT),
			Color(0.68,0.84,1.0,neighbor_preview_alpha)
		)
	if preview_next_pose:
		_apply_neighbor_preview(
			_next_preview_sprite,
			posmod(editor_preview_pose + 1,POSE_COUNT),
			Color(1.0,0.72,0.82,neighbor_preview_alpha)
		)


func _ensure_neighbor_preview_sprites() -> void:
	var parent_node:Node = get_parent()
	if parent_node == null:
		return
	if not is_instance_valid(_previous_preview_sprite):
		_previous_preview_sprite = parent_node.get_node_or_null("__SunshowerPreviousPosePreview") as Sprite2D
	if not is_instance_valid(_next_preview_sprite):
		_next_preview_sprite = parent_node.get_node_or_null("__SunshowerNextPosePreview") as Sprite2D
	if _previous_preview_sprite == null:
		_previous_preview_sprite = Sprite2D.new()
		_previous_preview_sprite.name = "__SunshowerPreviousPosePreview"
		_previous_preview_sprite.owner = null
		_previous_preview_sprite.z_index = z_index + 1
		parent_node.add_child(_previous_preview_sprite,false,Node.INTERNAL_MODE_BACK)
	if _next_preview_sprite == null:
		_next_preview_sprite = Sprite2D.new()
		_next_preview_sprite.name = "__SunshowerNextPosePreview"
		_next_preview_sprite.owner = null
		_next_preview_sprite.z_index = z_index + 2
		parent_node.add_child(_next_preview_sprite,false,Node.INTERNAL_MODE_BACK)


func _apply_neighbor_preview(sprite:Sprite2D,pose_index:int,tint:Color) -> void:
	if sprite == null:
		return
	var pose:StringName = _pose_name_for_preview(pose_index)
	var tex:Texture2D = _anchor_texture_for_pose(pose)
	if tex == null:
		sprite.visible = false
		return
	var tweak:Dictionary = _layout_for_pose(pose)
	sprite.texture = tex
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	var preview_position:Vector2 = tweak.get("position",Vector2.ZERO)
	sprite.position = common_position + preview_position
	sprite.scale = Vector2.ONE * _auto_scale_for_texture(_reference_texture_for_pose(pose)) * maxf(float(tweak.get("scale",1.0)),0.01)
	sprite.rotation = 0.0
	sprite.flip_h = false
	sprite.flip_v = false
	sprite.modulate = tint


func _capture_transform_if_changed(force:bool = false) -> void:
	var position_changed:bool = not position.is_equal_approx(_last_applied_position)
	var scale_changed:bool = not scale.is_equal_approx(_last_applied_scale)
	if not force and not position_changed and not scale_changed:
		return
	var pose:StringName = _pose_name_for_preview(editor_preview_pose)
	var tex:Texture2D = _reference_texture_for_pose(pose)
	if tex == null:
		return
	var uniform_scale:float = maxf((absf(scale.x) + absf(scale.y)) * 0.5,0.0001)
	var auto_scale:float = maxf(_auto_scale_for_texture(tex),0.0001)
	var tweak_scale:float = uniform_scale / auto_scale
	var tweak_position:Vector2 = position - common_position
	_set_layout_for_preview(editor_preview_pose,tweak_scale,tweak_position)
	_suppress_capture = true
	scale = Vector2.ONE * uniform_scale
	rotation = 0.0
	flip_h = false
	flip_v = false
	_last_applied_position = position
	_last_applied_scale = scale
	_suppress_capture = false
	_mark_scene_unsaved()


func _editor_previous_pose() -> void:
	if not Engine.is_editor_hint():
		return
	if not editor_preview_enabled:
		editor_preview_enabled = true
	else:
		_capture_transform_if_changed()
	editor_preview_pose = posmod(editor_preview_pose - 1,POSE_COUNT)
	_apply_editor_preview()
	notify_property_list_changed()


func _editor_next_pose() -> void:
	if not Engine.is_editor_hint():
		return
	if not editor_preview_enabled:
		editor_preview_enabled = true
	else:
		_capture_transform_if_changed()
	editor_preview_pose = posmod(editor_preview_pose + 1,POSE_COUNT)
	_apply_editor_preview()
	notify_property_list_changed()


func _editor_copy_previous_layout() -> void:
	if not Engine.is_editor_hint():
		return
	var source:Dictionary = _layout_for_preview(posmod(editor_preview_pose - 1,POSE_COUNT))
	_set_layout_for_preview(editor_preview_pose,float(source.get("scale",1.0)),source.get("position",Vector2.ZERO))
	_apply_editor_preview()
	_mark_scene_unsaved()


func _editor_reset_current_layout() -> void:
	if not Engine.is_editor_hint():
		return
	_set_layout_for_preview(editor_preview_pose,1.0,Vector2.ZERO)
	_apply_editor_preview()
	_mark_scene_unsaved()


func _editor_force_capture() -> void:
	if Engine.is_editor_hint():
		_capture_transform_if_changed(true)


func _mark_scene_unsaved() -> void:
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _auto_scale_for_texture(tex:Texture2D) -> float:
	if tex == null:
		return 1.0
	return maxf(target_display_height,1.0) / maxf(float(tex.get_height()),1.0)


func _texture_for_frame(pose:StringName,frame_index:int) -> Texture2D:
	pose = _normalize_pose(pose)
	if animation_frames == null or not animation_frames.has_animation(pose):
		return null
	var count:int = animation_frames.get_frame_count(pose)
	if count <= 0:
		return null
	return animation_frames.get_frame_texture(pose,clampi(frame_index,0,count - 1))


func _reference_texture_for_pose(pose:StringName) -> Texture2D:
	pose = _normalize_pose(pose)
	if animation_frames == null or not animation_frames.has_animation(pose):
		return null
	var count:int = animation_frames.get_frame_count(pose)
	for frame_index:int in range(count):
		var tex:Texture2D = animation_frames.get_frame_texture(pose,frame_index)
		if tex != null:
			return tex
	return null


func _anchor_texture_for_pose(pose:StringName) -> Texture2D:
	return _texture_for_frame(pose,_anchor_frame_for_pose(pose))


func _clamped_frame(pose:StringName,value:int) -> int:
	pose = _normalize_pose(pose)
	if animation_frames == null or not animation_frames.has_animation(pose):
		return 0
	return clampi(value,0,maxi(animation_frames.get_frame_count(pose) - 1,0))


func _anchor_frame_for_pose(pose:StringName) -> int:
	match _normalize_pose(pose):
		&"Attack1": return _clamped_frame(&"Attack1",attack1_anchor_frame)
		&"Attack2": return _clamped_frame(&"Attack2",attack2_anchor_frame)
		&"Attack3": return _clamped_frame(&"Attack3",attack3_anchor_frame)
		&"Defense": return _clamped_frame(&"Defense",defense_anchor_frame)
		_: return _clamped_frame(&"Idle",idle_anchor_frame)


func _pose_name_for_preview(value:int) -> StringName:
	return POSE_NAMES[clampi(value,0,POSE_COUNT - 1)]


func _normalize_pose(pose:StringName) -> StringName:
	for known:StringName in POSE_NAMES:
		if pose == known:
			return known
	return &"Idle"


func _layout_for_preview(value:int) -> Dictionary:
	return _layout_for_pose(_pose_name_for_preview(value))


func _layout_for_pose(pose:StringName) -> Dictionary:
	match _normalize_pose(pose):
		&"Attack1": return {"scale":attack1_scale,"position":attack1_position}
		&"Attack2": return {"scale":attack2_scale,"position":attack2_position}
		&"Attack3": return {"scale":attack3_scale,"position":attack3_position}
		&"Defense": return {"scale":defense_scale,"position":defense_position}
		_: return {"scale":idle_scale,"position":idle_position}


func _set_layout_for_preview(value:int,new_scale:float,new_position:Vector2) -> void:
	var safe_scale:float = clampf(new_scale,0.05,8.0)
	match clampi(value,0,POSE_COUNT - 1):
		PreviewPose.ATTACK1:
			attack1_scale = safe_scale
			attack1_position = new_position
		PreviewPose.ATTACK2:
			attack2_scale = safe_scale
			attack2_position = new_position
		PreviewPose.ATTACK3:
			attack3_scale = safe_scale
			attack3_position = new_position
		PreviewPose.DEFENSE:
			defense_scale = safe_scale
			defense_position = new_position
		_:
			idle_scale = safe_scale
			idle_position = new_position
