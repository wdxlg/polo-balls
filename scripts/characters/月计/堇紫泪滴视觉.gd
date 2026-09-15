@tool
extends Sprite2D

# 堇紫泪滴快速构图工具。
# 与殷红迷雾一致：所有图片先按原图高度等比例缩放到统一高度，
# 再为每张图单独保存额外缩放和位置。编辑器里可直接拖/缩当前图片。

const TEX_STAND:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/站立.png")
const TEX_BLUNT_STANCE:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/打击姿态.png")
const TEX_BLUNT_ATTACK:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/打击.png")
const TEX_GUARD:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/防御.png")
const TEX_PIERCE_STANCE:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/突刺姿态.png")
const TEX_PIERCE_1:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/突刺1.png")
const TEX_PIERCE_2:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/突刺2.png")
const TEX_SLASH_STANCE:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/斩击姿态.png")
const TEX_SLASH_1:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/斩击1.png")
const TEX_SLASH_2:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/斩击2.png")

enum PreviewPose {
	STAND,
	BLUNT_STANCE,
	BLUNT_ATTACK,
	GUARD,
	PIERCE_STANCE,
	PIERCE_1,
	PIERCE_2,
	SLASH_STANCE,
	SLASH_1,
	SLASH_2,
}

const POSE_COUNT:int = 10

@export_category("堇紫泪滴 - 快速构图")
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

@export_enum("站立","打击姿态","打击","防御姿态","突刺姿态","突刺 1","突刺 2","斩击姿态","斩击 1","斩击 2") var editor_preview_pose:int = PreviewPose.STAND:
	set(value):
		var next_pose:int = clampi(value,0,POSE_COUNT - 1)
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled and editor_preview_pose != next_pose:
			_capture_transform_if_changed()
		editor_preview_pose = next_pose
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled:
			call_deferred("_apply_editor_preview")
			notify_property_list_changed()

@export_range(64.0,512.0,1.0) var target_display_height:float = 205.0
@export var common_position:Vector2 = Vector2.ZERO
@export var auto_capture_2d_transform:bool = true

@export_group("相邻动作参考")
@export var preview_previous_pose:bool = false:
	set(value):
		preview_previous_pose = value
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_update_neighbor_previews")
@export var preview_next_pose:bool = false:
	set(value):
		preview_next_pose = value
		if Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_update_neighbor_previews")
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

@export_storage var stand_scale:float = 1.0
@export_storage var stand_position:Vector2 = Vector2.ZERO
@export_storage var blunt_stance_scale:float = 1.0
@export_storage var blunt_stance_position:Vector2 = Vector2.ZERO
@export_storage var blunt_attack_scale:float = 1.0
@export_storage var blunt_attack_position:Vector2 = Vector2.ZERO
@export_storage var guard_scale:float = 1.0
@export_storage var guard_position:Vector2 = Vector2.ZERO
@export_storage var pierce_stance_scale:float = 1.0
@export_storage var pierce_stance_position:Vector2 = Vector2.ZERO
@export_storage var pierce1_scale:float = 1.0
@export_storage var pierce1_position:Vector2 = Vector2.ZERO
@export_storage var pierce2_scale:float = 1.0
@export_storage var pierce2_position:Vector2 = Vector2.ZERO
@export_storage var slash_stance_scale:float = 1.0
@export_storage var slash_stance_position:Vector2 = Vector2.ZERO
@export_storage var slash1_scale:float = 1.0
@export_storage var slash1_position:Vector2 = Vector2.ZERO
@export_storage var slash2_scale:float = 1.0
@export_storage var slash2_position:Vector2 = Vector2.ZERO

var _runtime_pose:StringName = &"stand"
var _runtime_flipped_h:bool = false
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
	if Engine.is_editor_hint():
		set_process(editor_preview_enabled)
		if editor_preview_enabled:
			call_deferred("_apply_editor_preview")
	else:
		set_process(false)
		_apply_pose(&"stand",false)

func _process(_delta:float) -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return
	var clamped_pose:int = clampi(editor_preview_pose,0,POSE_COUNT - 1)
	if editor_preview_pose != clamped_pose:
		editor_preview_pose = clamped_pose
	if _last_editor_pose != editor_preview_pose or not is_equal_approx(_last_target_height,target_display_height) or not _last_common_position.is_equal_approx(common_position):
		_apply_editor_preview()
		return
	if auto_capture_2d_transform and not _suppress_capture:
		_capture_transform_if_changed()

func apply_runtime_pose(pose:StringName) -> void:
	_runtime_pose = pose
	_apply_pose(pose,false)

func apply_runtime_flip(flipped:bool) -> void:
	_runtime_flipped_h = flipped
	if Engine.is_editor_hint():
		return
	var tweak:Dictionary = _layout_for_pose(_runtime_pose)
	var pose_position:Vector2 = tweak.get("position",Vector2.ZERO)
	position = _runtime_position_for_pose(pose_position)
	_last_applied_position = position

func _runtime_position_for_pose(pose_position:Vector2) -> Vector2:
	var mirrored_x:float = -pose_position.x if _runtime_flipped_h else pose_position.x
	return common_position + Vector2(mirrored_x,pose_position.y)

func get_autofit_reference_visual() -> Dictionary:
	var auto_scale:float = _auto_scale_for_texture(TEX_STAND)
	return {
		"texture":TEX_STAND,
		"position":common_position + stand_position,
		"scale":Vector2.ONE * auto_scale * maxf(stand_scale,0.01),
		"centered":true,
		"offset":Vector2.ZERO,
	}

func _apply_pose(pose:StringName,editor_preview:bool) -> void:
	var tex:Texture2D = _texture_for_pose(pose)
	if tex == null:
		return
	_suppress_capture = true
	texture = tex
	centered = true
	offset = Vector2.ZERO
	var tweak:Dictionary = _layout_for_pose(pose)
	var final_scale:float = _auto_scale_for_texture(tex) * maxf(float(tweak.get("scale",1.0)),0.01)
	var pose_position:Vector2 = tweak.get("position",Vector2.ZERO)
	scale = Vector2.ONE * final_scale
	position = common_position + pose_position if editor_preview else _runtime_position_for_pose(pose_position)
	if editor_preview:
		rotation = 0.0
		flip_h = false
	_last_applied_position = position
	_last_applied_scale = scale
	_suppress_capture = false

func _apply_editor_preview() -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return
	_apply_pose(_pose_name_for_preview(editor_preview_pose),true)
	_last_editor_pose = editor_preview_pose
	_last_target_height = target_display_height
	_last_common_position = common_position
	_update_neighbor_previews()
	notify_property_list_changed()

func _capture_transform_if_changed(force:bool = false) -> void:
	var position_changed:bool = not position.is_equal_approx(_last_applied_position)
	var scale_changed:bool = not scale.is_equal_approx(_last_applied_scale)
	if not force and not position_changed and not scale_changed:
		return
	var tex:Texture2D = _texture_for_preview(editor_preview_pose)
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

func _editor_next_pose() -> void:
	if not Engine.is_editor_hint():
		return
	if not editor_preview_enabled:
		editor_preview_enabled = true
	else:
		_capture_transform_if_changed()
	editor_preview_pose = posmod(editor_preview_pose + 1,POSE_COUNT)
	_apply_editor_preview()

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
		_apply_neighbor_preview(_previous_preview_sprite,posmod(editor_preview_pose - 1,POSE_COUNT),Color(0.68,0.84,1.0,neighbor_preview_alpha))
	if preview_next_pose:
		_apply_neighbor_preview(_next_preview_sprite,posmod(editor_preview_pose + 1,POSE_COUNT),Color(1.0,0.72,0.82,neighbor_preview_alpha))

func _ensure_neighbor_preview_sprites() -> void:
	var parent_node:Node = get_parent()
	if parent_node == null:
		return
	if not is_instance_valid(_previous_preview_sprite):
		_previous_preview_sprite = parent_node.get_node_or_null("__PurpleTearPreviousPosePreview") as Sprite2D
	if not is_instance_valid(_next_preview_sprite):
		_next_preview_sprite = parent_node.get_node_or_null("__PurpleTearNextPosePreview") as Sprite2D
	if _previous_preview_sprite == null:
		_previous_preview_sprite = Sprite2D.new()
		_previous_preview_sprite.name = "__PurpleTearPreviousPosePreview"
		_previous_preview_sprite.owner = null
		_previous_preview_sprite.z_index = z_index + 1
		parent_node.add_child(_previous_preview_sprite,false,Node.INTERNAL_MODE_BACK)
	if _next_preview_sprite == null:
		_next_preview_sprite = Sprite2D.new()
		_next_preview_sprite.name = "__PurpleTearNextPosePreview"
		_next_preview_sprite.owner = null
		_next_preview_sprite.z_index = z_index + 2
		parent_node.add_child(_next_preview_sprite,false,Node.INTERNAL_MODE_BACK)

func _apply_neighbor_preview(sprite:Sprite2D,pose_index:int,tint:Color) -> void:
	var tex:Texture2D = _texture_for_preview(pose_index)
	if sprite == null or tex == null:
		if sprite != null:
			sprite.visible = false
		return
	var tweak:Dictionary = _layout_for_preview(pose_index)
	sprite.texture = tex
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	var preview_position:Vector2 = tweak.get("position",Vector2.ZERO)
	sprite.position = common_position + preview_position
	sprite.scale = Vector2.ONE * _auto_scale_for_texture(tex) * maxf(float(tweak.get("scale",1.0)),0.01)
	sprite.rotation = 0.0
	sprite.flip_h = false
	sprite.modulate = tint

func _auto_scale_for_texture(tex:Texture2D) -> float:
	if tex == null:
		return 1.0
	return maxf(target_display_height,1.0) / maxf(float(tex.get_height()),1.0)

func _texture_for_preview(value:int) -> Texture2D:
	return _texture_for_pose(_pose_name_for_preview(value))

func _pose_name_for_preview(value:int) -> StringName:
	match clampi(value,0,POSE_COUNT - 1):
		PreviewPose.BLUNT_STANCE: return &"blunt_stance"
		PreviewPose.BLUNT_ATTACK: return &"blunt_attack"
		PreviewPose.GUARD: return &"guard"
		PreviewPose.PIERCE_STANCE: return &"pierce_stance"
		PreviewPose.PIERCE_1: return &"pierce1"
		PreviewPose.PIERCE_2: return &"pierce2"
		PreviewPose.SLASH_STANCE: return &"slash_stance"
		PreviewPose.SLASH_1: return &"slash1"
		PreviewPose.SLASH_2: return &"slash2"
		_: return &"stand"

func _texture_for_pose(pose:StringName) -> Texture2D:
	match pose:
		&"blunt_stance": return TEX_BLUNT_STANCE
		&"blunt_attack": return TEX_BLUNT_ATTACK
		&"guard": return TEX_GUARD
		&"pierce_stance": return TEX_PIERCE_STANCE
		&"pierce1": return TEX_PIERCE_1
		&"pierce2": return TEX_PIERCE_2
		&"slash_stance": return TEX_SLASH_STANCE
		&"slash1": return TEX_SLASH_1
		&"slash2": return TEX_SLASH_2
		_: return TEX_STAND

func _layout_for_preview(value:int) -> Dictionary:
	return _layout_for_pose(_pose_name_for_preview(value))

func _layout_for_pose(pose:StringName) -> Dictionary:
	match pose:
		&"blunt_stance": return {"scale":blunt_stance_scale,"position":blunt_stance_position}
		&"blunt_attack": return {"scale":blunt_attack_scale,"position":blunt_attack_position}
		&"guard": return {"scale":guard_scale,"position":guard_position}
		&"pierce_stance": return {"scale":pierce_stance_scale,"position":pierce_stance_position}
		&"pierce1": return {"scale":pierce1_scale,"position":pierce1_position}
		&"pierce2": return {"scale":pierce2_scale,"position":pierce2_position}
		&"slash_stance": return {"scale":slash_stance_scale,"position":slash_stance_position}
		&"slash1": return {"scale":slash1_scale,"position":slash1_position}
		&"slash2": return {"scale":slash2_scale,"position":slash2_position}
		_: return {"scale":stand_scale,"position":stand_position}

func _set_layout_for_preview(value:int,new_scale:float,new_position:Vector2) -> void:
	var safe_scale:float = clampf(new_scale,0.05,8.0)
	match clampi(value,0,POSE_COUNT - 1):
		PreviewPose.BLUNT_STANCE:
			blunt_stance_scale = safe_scale
			blunt_stance_position = new_position
		PreviewPose.BLUNT_ATTACK:
			blunt_attack_scale = safe_scale
			blunt_attack_position = new_position
		PreviewPose.GUARD:
			guard_scale = safe_scale
			guard_position = new_position
		PreviewPose.PIERCE_STANCE:
			pierce_stance_scale = safe_scale
			pierce_stance_position = new_position
		PreviewPose.PIERCE_1:
			pierce1_scale = safe_scale
			pierce1_position = new_position
		PreviewPose.PIERCE_2:
			pierce2_scale = safe_scale
			pierce2_position = new_position
		PreviewPose.SLASH_STANCE:
			slash_stance_scale = safe_scale
			slash_stance_position = new_position
		PreviewPose.SLASH_1:
			slash1_scale = safe_scale
			slash1_position = new_position
		PreviewPose.SLASH_2:
			slash2_scale = safe_scale
			slash2_position = new_position
		_:
			stand_scale = safe_scale
			stand_position = new_position
