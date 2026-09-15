@tool
extends Sprite2D

# 殷红迷雾快速构图工具。
# - 所有图片先按原图高度等比例缩放到 target_display_height。
# - 每个动作只保存自己的额外 scale / position 微调。
# - 编辑器里选中 Graphics/Image 后，直接用 Godot 自带 2D Transform 拖动/缩放；
#   本脚本会把最终 Transform 自动换算回当前动作的微调数据。
# - 单动作数据用 @export_storage 保存但隐藏，Inspector 不再塞满几十个字段。
# - 上一张/下一张、复制、重置都可直接点 Inspector 按钮。

const TEX_NORMAL_STAND:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通站立.png")
const TEX_NORMAL_THRUST:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通刺.png")
const TEX_NORMAL_SLASH1:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通斩.png")
const TEX_NORMAL_SLASH2:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通斩2.png")
const TEX_NORMAL_DASH:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通冲刺.png")
const TEX_NORMAL_GUARD:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通防御.png")

const TEX_EGO_STAND:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego站立.png")
const TEX_EGO_BACKSTEP:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego后退.png")
const TEX_EGO_THRUST:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego突刺.png")
const TEX_EGO_SLASH1:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego斩.png")
const TEX_EGO_SLASH2:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego斩.png")
const TEX_EGO_HORIZONTAL:Texture2D = preload("res://Images/characters/月计/殷红迷雾/尸横遍野.png")
const TEX_EGO_DASH:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego冲刺.png")
const TEX_EGO_GUARD:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego防御.png")
const TEX_EXECUTE_1:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego斩杀1.png")
const TEX_EXECUTE_2:Texture2D = preload("res://Images/characters/月计/殷红迷雾/斩杀2.png")
const TEX_EXECUTE_3:Texture2D = preload("res://Images/characters/月计/殷红迷雾/斩杀3.png")
const TEX_EXECUTE_4:Texture2D = preload("res://Images/characters/月计/殷红迷雾/斩杀4.png")
const TEX_EXECUTE_5:Texture2D = preload("res://Images/characters/月计/殷红迷雾/斩杀5.png")
const TEX_EXECUTE_6:Texture2D = preload("res://Images/characters/月计/殷红迷雾/斩杀6.png")

enum PreviewPose {
	NORMAL_STAND,
	NORMAL_THRUST,
	NORMAL_SLASH_1,
	NORMAL_SLASH_2,
	NORMAL_DASH,
	NORMAL_GUARD,
	EGO_STAND,
	EGO_BACKSTEP,
	EGO_THRUST,
	EGO_SLASH_1,
	EGO_SLASH_2,
	EGO_DASH,
	EGO_GUARD,
	EXECUTE_1,
	EXECUTE_2,
	EXECUTE_3,
	EXECUTE_4,
	EXECUTE_5,
	EXECUTE_6,
	EGO_HORIZONTAL,
}

const POSE_COUNT:int = 20

@export_category("殷红迷雾 - 快速构图")
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

@export_enum("普通站立","普通刺","普通斩 1","普通斩 2","普通冲刺","普通防御","E.G.O 站立","E.G.O 后退","E.G.O 突刺","E.G.O 斩 1","E.G.O 斩 2","E.G.O 冲刺","E.G.O 防御","斩杀 1","斩杀 2","斩杀 3","斩杀 4","斩杀 5","斩杀 6","尸横遍野") var editor_preview_pose:int = PreviewPose.NORMAL_STAND:
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

# 这些字段继续沿用 v10 的属性名，因此你刚刚手调过的 .tscn 可以直接读取。
# 改成 export_storage 后仍会写入场景，但不会再把 Inspector 塞满。
@export_storage var normal_stand_scale:float = 1.0
@export_storage var normal_stand_position:Vector2 = Vector2.ZERO
@export_storage var normal_thrust_scale:float = 1.0
@export_storage var normal_thrust_position:Vector2 = Vector2.ZERO
@export_storage var normal_slash1_scale:float = 1.0
@export_storage var normal_slash1_position:Vector2 = Vector2.ZERO
@export_storage var normal_slash2_scale:float = 1.0
@export_storage var normal_slash2_position:Vector2 = Vector2.ZERO
@export_storage var normal_dash_scale:float = 1.0
@export_storage var normal_dash_position:Vector2 = Vector2.ZERO
@export_storage var normal_guard_scale:float = 1.0
@export_storage var normal_guard_position:Vector2 = Vector2.ZERO

@export_storage var ego_stand_scale:float = 1.0
@export_storage var ego_stand_position:Vector2 = Vector2.ZERO
@export_storage var ego_backstep_scale:float = 1.0
@export_storage var ego_backstep_position:Vector2 = Vector2.ZERO
@export_storage var ego_thrust_scale:float = 1.0
@export_storage var ego_thrust_position:Vector2 = Vector2.ZERO
@export_storage var ego_slash1_scale:float = 1.0
@export_storage var ego_slash1_position:Vector2 = Vector2.ZERO
@export_storage var ego_slash2_scale:float = 1.0
@export_storage var ego_slash2_position:Vector2 = Vector2.ZERO
@export_storage var ego_dash_scale:float = 1.0
@export_storage var ego_dash_position:Vector2 = Vector2.ZERO
@export_storage var ego_guard_scale:float = 1.0
@export_storage var ego_guard_position:Vector2 = Vector2.ZERO

@export_storage var execute1_scale:float = 1.0
@export_storage var execute1_position:Vector2 = Vector2.ZERO
@export_storage var execute2_scale:float = 1.0
@export_storage var execute2_position:Vector2 = Vector2.ZERO
@export_storage var execute3_scale:float = 1.0
@export_storage var execute3_position:Vector2 = Vector2.ZERO
@export_storage var execute4_scale:float = 1.0
@export_storage var execute4_position:Vector2 = Vector2.ZERO
@export_storage var execute5_scale:float = 1.0
@export_storage var execute5_position:Vector2 = Vector2.ZERO
@export_storage var execute6_scale:float = 1.46
@export_storage var execute6_position:Vector2 = Vector2(-90,-30)
@export_storage var ego_horizontal_scale:float = 1.0
@export_storage var ego_horizontal_position:Vector2 = Vector2.ZERO

var _runtime_pose:StringName = &"stand"
var _runtime_ego_active:bool = false
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
		_apply_pose(&"stand",false,false)


func _process(_delta:float) -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return

	var clamped_pose:int = clampi(editor_preview_pose,0,POSE_COUNT - 1)
	if editor_preview_pose != clamped_pose:
		editor_preview_pose = clamped_pose

	# 切动作或改变统一高度/公共偏移时，先加载这一动作已经保存的构图。
	if (
		_last_editor_pose != editor_preview_pose
		or not is_equal_approx(_last_target_height,target_display_height)
		or not _last_common_position.is_equal_approx(common_position)
	):
		_apply_editor_preview()
		return

	# 之后不再每帧把 Transform 覆盖回去，而是反过来监听用户在 2D 视口中的拖动/缩放。
	if auto_capture_2d_transform and not _suppress_capture:
		_capture_transform_if_changed()


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
		_previous_preview_sprite = parent_node.get_node_or_null("__GeburaPreviousPosePreview") as Sprite2D
	if not is_instance_valid(_next_preview_sprite):
		_next_preview_sprite = parent_node.get_node_or_null("__GeburaNextPosePreview") as Sprite2D

	if _previous_preview_sprite == null:
		_previous_preview_sprite = Sprite2D.new()
		_previous_preview_sprite.name = "__GeburaPreviousPosePreview"
		_previous_preview_sprite.owner = null
		_previous_preview_sprite.z_index = z_index + 1
		parent_node.add_child(_previous_preview_sprite,false,Node.INTERNAL_MODE_BACK)
	if _next_preview_sprite == null:
		_next_preview_sprite = Sprite2D.new()
		_next_preview_sprite.name = "__GeburaNextPosePreview"
		_next_preview_sprite.owner = null
		_next_preview_sprite.z_index = z_index + 2
		parent_node.add_child(_next_preview_sprite,false,Node.INTERNAL_MODE_BACK)


func _apply_neighbor_preview(sprite:Sprite2D,pose_index:int,tint:Color) -> void:
	if sprite == null:
		return
	var tex:Texture2D = _texture_for_preview(pose_index)
	if tex == null:
		sprite.visible = false
		return
	var tweak:Dictionary = _layout_for_preview(pose_index)
	var auto_scale:float = _auto_scale_for_texture(tex)
	var layout_scale:float = maxf(float(tweak.get("scale",1.0)),0.01)
	var layout_position:Vector2 = tweak.get("position",Vector2.ZERO)
	sprite.texture = tex
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	sprite.position = common_position + layout_position
	sprite.scale = Vector2.ONE * auto_scale * layout_scale
	sprite.rotation = 0.0
	sprite.flip_h = false
	sprite.modulate = tint


func apply_runtime_pose(pose:StringName,ego_active:bool) -> void:
	_runtime_pose = pose
	_runtime_ego_active = ego_active
	_apply_pose(pose,ego_active,false)


# 运行时左右翻转不仅翻纹理，也镜像用户为每张动作图保存的 X 构图偏移。
# 这样图片内容本身不在画布正中心时，朝左/朝右仍以角色根节点为同一中心。
func apply_runtime_flip(flipped:bool) -> void:
	_runtime_flipped_h = flipped
	if Engine.is_editor_hint():
		return
	var tweak:Dictionary = _layout_for_pose(_runtime_pose,_runtime_ego_active)
	var pose_position:Vector2 = tweak.get("position",Vector2.ZERO)
	position = _runtime_position_for_pose(pose_position)
	_last_applied_position = position


func _runtime_position_for_pose(pose_position:Vector2) -> Vector2:
	var mirrored_x:float = -pose_position.x if _runtime_flipped_h else pose_position.x
	return common_position + Vector2(mirrored_x,pose_position.y)


# CharacterAutoFit 使用普通站立作为固定碰撞参考。
# 编辑器里切换到长剑、冲刺、斩杀图时，碰撞框不会跟着预览图乱跑。
func get_autofit_reference_visual() -> Dictionary:
	var tex:Texture2D = TEX_NORMAL_STAND
	var auto_scale:float = _auto_scale_for_texture(tex)
	return {
		"texture": tex,
		"position": common_position + normal_stand_position,
		"scale": Vector2.ONE * auto_scale * maxf(normal_stand_scale,0.01),
		"centered": true,
		"offset": Vector2.ZERO,
	}


func _apply_editor_preview() -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return
	var preview:Dictionary = _preview_to_pose(editor_preview_pose)
	_apply_pose(StringName(preview.get("pose",&"stand")),bool(preview.get("ego",false)),true)
	_last_editor_pose = editor_preview_pose
	_last_target_height = target_display_height
	_last_common_position = common_position
	_update_neighbor_previews()
	notify_property_list_changed()


func _apply_pose(pose:StringName,ego_active:bool,editor_preview:bool) -> void:
	var tex:Texture2D = _texture_for_pose(pose,ego_active)
	if tex == null:
		return

	_suppress_capture = true
	texture = tex
	centered = true
	offset = Vector2.ZERO
	var tweak:Dictionary = _layout_for_pose(pose,ego_active)
	var scale_adjust:float = maxf(float(tweak.get("scale",1.0)),0.01)
	var pose_position:Vector2 = tweak.get("position",Vector2.ZERO)
	var final_scale:float = _auto_scale_for_texture(tex) * scale_adjust
	scale = Vector2.ONE * final_scale
	position = common_position + pose_position if editor_preview else _runtime_position_for_pose(pose_position)
	if editor_preview:
		rotation = 0.0
		flip_h = false
	_last_applied_position = position
	_last_applied_scale = scale
	_suppress_capture = false


func _capture_transform_if_changed(force:bool = false) -> void:
	var position_changed:bool = not position.is_equal_approx(_last_applied_position)
	var scale_changed:bool = not scale.is_equal_approx(_last_applied_scale)
	if not force and not position_changed and not scale_changed:
		return

	var tex:Texture2D = _texture_for_preview(editor_preview_pose)
	if tex == null:
		return

	# 构图只允许等比缩放。即使不小心把 X/Y 拉成不同值，也会自动归一成一个比例。
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
	var source_index:int = posmod(editor_preview_pose - 1,POSE_COUNT)
	var source:Dictionary = _layout_for_preview(source_index)
	var source_position:Vector2 = source.get("position",Vector2.ZERO)
	_set_layout_for_preview(editor_preview_pose,float(source.get("scale",1.0)),source_position)
	_apply_editor_preview()
	_mark_scene_unsaved()


func _editor_reset_current_layout() -> void:
	if not Engine.is_editor_hint():
		return
	_set_layout_for_preview(editor_preview_pose,1.0,Vector2.ZERO)
	_apply_editor_preview()
	_mark_scene_unsaved()


func _editor_force_capture() -> void:
	if not Engine.is_editor_hint():
		return
	_capture_transform_if_changed(true)


func _mark_scene_unsaved() -> void:
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _auto_scale_for_texture(tex:Texture2D) -> float:
	if tex == null:
		return 1.0
	return maxf(target_display_height,1.0) / maxf(float(tex.get_height()),1.0)


func _texture_for_preview(value:int) -> Texture2D:
	var preview:Dictionary = _preview_to_pose(value)
	return _texture_for_pose(StringName(preview.get("pose",&"stand")),bool(preview.get("ego",false)))


func _texture_for_pose(pose:StringName,ego_active:bool) -> Texture2D:
	if pose == &"guard":
		return TEX_EGO_GUARD if ego_active else TEX_NORMAL_GUARD
	if pose == &"dash":
		return TEX_EGO_DASH if ego_active else TEX_NORMAL_DASH
	if pose == &"backstep":
		return TEX_EGO_BACKSTEP
	if pose == &"thrust":
		return TEX_EGO_THRUST if ego_active else TEX_NORMAL_THRUST
	if pose == &"slash1":
		return TEX_EGO_SLASH1 if ego_active else TEX_NORMAL_SLASH1
	if pose == &"slash2":
		return TEX_EGO_SLASH2 if ego_active else TEX_NORMAL_SLASH2
	if pose == &"horizontal":
		return TEX_EGO_HORIZONTAL
	match pose:
		&"execute_0": return TEX_EXECUTE_1
		&"execute_1": return TEX_EXECUTE_2
		&"execute_2": return TEX_EXECUTE_3
		&"execute_3": return TEX_EXECUTE_4
		&"execute_4": return TEX_EXECUTE_5
		&"execute_5": return TEX_EXECUTE_6
	return TEX_EGO_STAND if ego_active else TEX_NORMAL_STAND


func _layout_for_pose(pose:StringName,ego_active:bool) -> Dictionary:
	if not ego_active:
		match pose:
			&"thrust": return {"scale":normal_thrust_scale,"position":normal_thrust_position}
			&"slash1": return {"scale":normal_slash1_scale,"position":normal_slash1_position}
			&"slash2": return {"scale":normal_slash2_scale,"position":normal_slash2_position}
			&"dash": return {"scale":normal_dash_scale,"position":normal_dash_position}
			&"guard": return {"scale":normal_guard_scale,"position":normal_guard_position}
			_: return {"scale":normal_stand_scale,"position":normal_stand_position}

	match pose:
		&"backstep": return {"scale":ego_backstep_scale,"position":ego_backstep_position}
		&"thrust": return {"scale":ego_thrust_scale,"position":ego_thrust_position}
		&"slash1": return {"scale":ego_slash1_scale,"position":ego_slash1_position}
		&"slash2": return {"scale":ego_slash2_scale,"position":ego_slash2_position}
		&"dash": return {"scale":ego_dash_scale,"position":ego_dash_position}
		&"guard": return {"scale":ego_guard_scale,"position":ego_guard_position}
		&"execute_0": return {"scale":execute1_scale,"position":execute1_position}
		&"execute_1": return {"scale":execute2_scale,"position":execute2_position}
		&"execute_2": return {"scale":execute3_scale,"position":execute3_position}
		&"execute_3": return {"scale":execute4_scale,"position":execute4_position}
		&"execute_4": return {"scale":execute5_scale,"position":execute5_position}
		&"execute_5": return {"scale":execute6_scale,"position":execute6_position}
		&"horizontal": return {"scale":ego_horizontal_scale,"position":ego_horizontal_position}
		_: return {"scale":ego_stand_scale,"position":ego_stand_position}


func _layout_for_preview(value:int) -> Dictionary:
	var preview:Dictionary = _preview_to_pose(value)
	return _layout_for_pose(StringName(preview.get("pose",&"stand")),bool(preview.get("ego",false)))


func _set_layout_for_preview(value:int,new_scale:float,new_position:Vector2) -> void:
	var safe_scale:float = clampf(new_scale,0.05,8.0)
	match clampi(value,0,POSE_COUNT - 1):
		PreviewPose.NORMAL_STAND:
			normal_stand_scale = safe_scale
			normal_stand_position = new_position
		PreviewPose.NORMAL_THRUST:
			normal_thrust_scale = safe_scale
			normal_thrust_position = new_position
		PreviewPose.NORMAL_SLASH_1:
			normal_slash1_scale = safe_scale
			normal_slash1_position = new_position
		PreviewPose.NORMAL_SLASH_2:
			normal_slash2_scale = safe_scale
			normal_slash2_position = new_position
		PreviewPose.NORMAL_DASH:
			normal_dash_scale = safe_scale
			normal_dash_position = new_position
		PreviewPose.NORMAL_GUARD:
			normal_guard_scale = safe_scale
			normal_guard_position = new_position
		PreviewPose.EGO_STAND:
			ego_stand_scale = safe_scale
			ego_stand_position = new_position
		PreviewPose.EGO_BACKSTEP:
			ego_backstep_scale = safe_scale
			ego_backstep_position = new_position
		PreviewPose.EGO_THRUST:
			ego_thrust_scale = safe_scale
			ego_thrust_position = new_position
		PreviewPose.EGO_SLASH_1:
			ego_slash1_scale = safe_scale
			ego_slash1_position = new_position
		PreviewPose.EGO_SLASH_2:
			ego_slash2_scale = safe_scale
			ego_slash2_position = new_position
		PreviewPose.EGO_DASH:
			ego_dash_scale = safe_scale
			ego_dash_position = new_position
		PreviewPose.EGO_GUARD:
			ego_guard_scale = safe_scale
			ego_guard_position = new_position
		PreviewPose.EXECUTE_1:
			execute1_scale = safe_scale
			execute1_position = new_position
		PreviewPose.EXECUTE_2:
			execute2_scale = safe_scale
			execute2_position = new_position
		PreviewPose.EXECUTE_3:
			execute3_scale = safe_scale
			execute3_position = new_position
		PreviewPose.EXECUTE_4:
			execute4_scale = safe_scale
			execute4_position = new_position
		PreviewPose.EXECUTE_5:
			execute5_scale = safe_scale
			execute5_position = new_position
		PreviewPose.EXECUTE_6:
			execute6_scale = safe_scale
			execute6_position = new_position
		PreviewPose.EGO_HORIZONTAL:
			ego_horizontal_scale = safe_scale
			ego_horizontal_position = new_position


func _preview_to_pose(value:int) -> Dictionary:
	match clampi(value,0,POSE_COUNT - 1):
		PreviewPose.NORMAL_THRUST: return {"pose":&"thrust","ego":false}
		PreviewPose.NORMAL_SLASH_1: return {"pose":&"slash1","ego":false}
		PreviewPose.NORMAL_SLASH_2: return {"pose":&"slash2","ego":false}
		PreviewPose.NORMAL_DASH: return {"pose":&"dash","ego":false}
		PreviewPose.NORMAL_GUARD: return {"pose":&"guard","ego":false}
		PreviewPose.EGO_STAND: return {"pose":&"stand","ego":true}
		PreviewPose.EGO_BACKSTEP: return {"pose":&"backstep","ego":true}
		PreviewPose.EGO_THRUST: return {"pose":&"thrust","ego":true}
		PreviewPose.EGO_SLASH_1: return {"pose":&"slash1","ego":true}
		PreviewPose.EGO_SLASH_2: return {"pose":&"slash2","ego":true}
		PreviewPose.EGO_DASH: return {"pose":&"dash","ego":true}
		PreviewPose.EGO_GUARD: return {"pose":&"guard","ego":true}
		PreviewPose.EXECUTE_1: return {"pose":&"execute_0","ego":true}
		PreviewPose.EXECUTE_2: return {"pose":&"execute_1","ego":true}
		PreviewPose.EXECUTE_3: return {"pose":&"execute_2","ego":true}
		PreviewPose.EXECUTE_4: return {"pose":&"execute_3","ego":true}
		PreviewPose.EXECUTE_5: return {"pose":&"execute_4","ego":true}
		PreviewPose.EXECUTE_6: return {"pose":&"execute_5","ego":true}
		PreviewPose.EGO_HORIZONTAL: return {"pose":&"horizontal","ego":true}
		_: return {"pose":&"stand","ego":false}
