@tool
extends Sprite2D

# V88：原始人火堆三张状态图使用与殷红迷雾相同的“每张图独立构图”思路。
# - 三张图先统一到 target_display_height，再分别保存 position / scale 微调。
# - 编辑器选中 FlameVisual/Image 后，可切换预览状态并直接拖动/缩放 2D Transform；
#   本脚本会把当前 Transform 自动记录回这一张图，不影响另外两张。
# - 运行时只调用 apply_runtime_state()，不会覆盖用户在 Inspector/2D 视口里保存的构图。

const TEX_UNLIT:Texture2D = preload("res://Images/characters/人物/原始人/01_火堆_熄灭状态.png")
const TEX_LIT_1:Texture2D = preload("res://Images/characters/人物/原始人/02_火堆_燃烧状态1.png")
const TEX_LIT_2:Texture2D = preload("res://Images/characters/人物/原始人/03_火堆_燃烧状态2.png")

enum PreviewState {
	UNLIT,
	LIT_1,
	LIT_2,
}

const STATE_COUNT:int = 3

@export_category("原始人火堆 - 快速构图")
@export var editor_preview_enabled:bool = true:
	set(value):
		editor_preview_enabled = value
		if Engine.is_editor_hint() and is_inside_tree():
			set_process(value)
			if value:
				call_deferred("_apply_editor_preview")

@export_enum("熄灭","燃烧 1","燃烧 2") var editor_preview_state:int = PreviewState.LIT_1:
	set(value):
		var next_state:int = clampi(value,0,STATE_COUNT - 1)
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled and editor_preview_state != next_state:
			_capture_transform_if_changed()
		editor_preview_state = next_state
		if Engine.is_editor_hint() and is_inside_tree() and editor_preview_enabled:
			call_deferred("_apply_editor_preview")

# V87 旧图为 1254×1254、scene scale=0.052，画面直径约 65px。
# V98 默认统一高度进一步降到 32px；每张图片的独立位置/缩放仍由场景保存。
@export_range(16.0,96.0,1.0) var target_display_height:float = 32.0
@export var common_position:Vector2 = Vector2.ZERO
@export var auto_capture_2d_transform:bool = true

@export_group("每张图片独立构图")
# 默认值用三张 PNG 的非透明内容中心做了轻微预对齐；之后可直接在 2D 视口自由拖动。
@export_storage var unlit_scale:float = 1.0
@export_storage var unlit_position:Vector2 = Vector2(-0.39,-0.42)
@export_storage var lit1_scale:float = 1.0
@export_storage var lit1_position:Vector2 = Vector2(-0.81,0.51)
@export_storage var lit2_scale:float = 1.0
@export_storage var lit2_position:Vector2 = Vector2(0.84,-0.02)

@export_group("")
@export_tool_button("◀ 上一张") var previous_state_button:Callable = _editor_previous_state
@export_tool_button("下一张 ▶") var next_state_button:Callable = _editor_next_state
@export_tool_button("重置当前：等高 + 居中") var reset_current_button:Callable = _editor_reset_current_layout
@export_tool_button("强制记录当前 Transform") var capture_current_button:Callable = _editor_force_capture

var _runtime_state:int = PreviewState.LIT_1
var _last_editor_state:int = -1
var _last_target_height:float = -1.0
var _last_common_position:Vector2 = Vector2(INF,INF)
var _last_applied_position:Vector2 = Vector2.ZERO
var _last_applied_scale:Vector2 = Vector2.ONE
var _suppress_capture:bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(editor_preview_enabled)
		if editor_preview_enabled:
			call_deferred("_apply_editor_preview")
	else:
		set_process(false)
		_apply_state(_runtime_state)

func _process(_delta:float) -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return
	var clamped_state:int = clampi(editor_preview_state,0,STATE_COUNT - 1)
	if editor_preview_state != clamped_state:
		editor_preview_state = clamped_state
	if (
		_last_editor_state != editor_preview_state
		or not is_equal_approx(_last_target_height,target_display_height)
		or not _last_common_position.is_equal_approx(common_position)
	):
		_apply_editor_preview()
		return
	if auto_capture_2d_transform and not _suppress_capture:
		_capture_transform_if_changed()

func apply_runtime_state(is_lit:bool,frame_index:int) -> void:
	_runtime_state = PreviewState.UNLIT
	if is_lit:
		_runtime_state = PreviewState.LIT_1 if posmod(frame_index,2) == 0 else PreviewState.LIT_2
	_apply_state(_runtime_state)

func _apply_editor_preview() -> void:
	if not Engine.is_editor_hint() or not editor_preview_enabled:
		return
	_apply_state(clampi(editor_preview_state,0,STATE_COUNT - 1))
	_last_editor_state = editor_preview_state
	_last_target_height = target_display_height
	_last_common_position = common_position

func _apply_state(state:int) -> void:
	var tex:Texture2D = _texture_for_state(state)
	if tex == null:
		return
	var layout:Dictionary = _layout_for_state(state)
	var auto_scale:float = _auto_scale_for_texture(tex)
	var layout_scale:float = maxf(float(layout.get("scale",1.0)),0.01)
	var layout_position:Vector2 = layout.get("position",Vector2.ZERO)
	_suppress_capture = true
	texture = tex
	centered = true
	offset = Vector2.ZERO
	position = common_position + layout_position
	scale = Vector2.ONE * auto_scale * layout_scale
	rotation = 0.0
	_last_applied_position = position
	_last_applied_scale = scale
	_suppress_capture = false

func _texture_for_state(state:int) -> Texture2D:
	match state:
		PreviewState.UNLIT:
			return TEX_UNLIT
		PreviewState.LIT_2:
			return TEX_LIT_2
		_:
			return TEX_LIT_1

func _layout_for_state(state:int) -> Dictionary:
	match state:
		PreviewState.UNLIT:
			return {"scale":unlit_scale,"position":unlit_position}
		PreviewState.LIT_2:
			return {"scale":lit2_scale,"position":lit2_position}
		_:
			return {"scale":lit1_scale,"position":lit1_position}

func _set_layout_for_state(state:int,new_scale:float,new_position:Vector2) -> void:
	match state:
		PreviewState.UNLIT:
			unlit_scale = new_scale
			unlit_position = new_position
		PreviewState.LIT_2:
			lit2_scale = new_scale
			lit2_position = new_position
		_:
			lit1_scale = new_scale
			lit1_position = new_position

func _auto_scale_for_texture(tex:Texture2D) -> float:
	if tex == null:
		return 1.0
	var tex_size:Vector2 = tex.get_size()
	if tex_size.y <= 0.001:
		return 1.0
	return maxf(target_display_height,1.0) / tex_size.y

func _capture_transform_if_changed(force:bool = false) -> void:
	if not Engine.is_editor_hint() or _suppress_capture:
		return
	if not force and position.is_equal_approx(_last_applied_position) and scale.is_equal_approx(_last_applied_scale):
		return
	var state:int = clampi(editor_preview_state,0,STATE_COUNT - 1)
	var tex:Texture2D = _texture_for_state(state)
	var auto_scale:float = maxf(_auto_scale_for_texture(tex),0.00001)
	var uniform_scale:float = maxf((absf(scale.x) + absf(scale.y)) * 0.5 / auto_scale,0.01)
	var local_position:Vector2 = position - common_position
	_set_layout_for_state(state,uniform_scale,local_position)
	# 保持火堆统一等比缩放；如果在 2D 视口拉成非等比，会自动折算成平均等比值。
	_suppress_capture = true
	scale = Vector2.ONE * auto_scale * uniform_scale
	_last_applied_position = position
	_last_applied_scale = scale
	_suppress_capture = false

func _editor_previous_state() -> void:
	_capture_transform_if_changed()
	editor_preview_state = posmod(editor_preview_state - 1,STATE_COUNT)

func _editor_next_state() -> void:
	_capture_transform_if_changed()
	editor_preview_state = posmod(editor_preview_state + 1,STATE_COUNT)

func _editor_reset_current_layout() -> void:
	var state:int = clampi(editor_preview_state,0,STATE_COUNT - 1)
	_set_layout_for_state(state,1.0,Vector2.ZERO)
	_apply_editor_preview()

func _editor_force_capture() -> void:
	_capture_transform_if_changed(true)
