extends Node2D
## 只用游戏物理 delta 推进：1 游戏秒 = 1 分钟；不读墙钟，不随渲染/录制抓帧次数加速。
## 昼夜只影响画面，不修改任何角色属性或地图碰撞。
const DAY_MINUTES:float = 1440.0
const START_MINUTES:float = 720.0
const MINUTES_PER_SECOND:float = 1.0
const NIGHT_TINT:Color = Color(0.48,0.54,0.68,1.0)
const CLOCK_FONT:Font = preload("res://fonts/Mojangles.ttf")
## 设置里的“时间与昼夜”开关。关闭后隐藏右上角时间，固定正午，不再有昼夜变化。
const SETTING:String = "Day_Night_Cycle"

var world:Node
var minutes:float = START_MINUTES
var advancing:bool = true
var enabled:bool = true
var daylight:float = 1.0
var tint:Polygon2D
var clock_layer:CanvasLayer
var clock_label:Label
var _clock_root:Control
var _shown_minute:int = -1

func _init(owner_world:Node = null) -> void:
	world = owner_world

func _ready() -> void:
	# CanvasModulate 会被地图/角色的 unshaded shader 忽略。世界画布顶层乘色
	# 同时覆盖普通和 unshaded 内容；独立 CanvasLayer 的菜单/标题不被压暗。
	# 大范围世界多边形也会进入共享 World2D 的录制/总览视口，不依赖主相机。
	top_level = true
	global_position = Vector2.ZERO
	tint = Polygon2D.new()
	tint.name = "WorldDayNightTint"
	tint.polygon = PackedVector2Array([Vector2(-1000000,-1000000),Vector2(1000000,-1000000),Vector2(1000000,1000000),Vector2(-1000000,1000000)])
	tint.z_as_relative = false
	tint.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	tint.visibility_layer = 1
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	multiply.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	tint.material = multiply
	add_child(tint)
	_create_clock()
	refresh_enabled()
	_apply_state()

func _create_clock() -> void:
	clock_layer = CanvasLayer.new()
	clock_layer.name = "WorldTimeHUD"
	clock_layer.layer = 2 # 1 is reserved for motion blur
	add_child(clock_layer)
	_clock_root = Control.new()
	_clock_root.name = "ClockAnchor"
	_clock_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_layer.add_child(_clock_root)
	_clock_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clock_label = Label.new()
	clock_label.name = "Time"
	clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_label.add_theme_font_override("font",CLOCK_FONT)
	clock_label.add_theme_font_size_override("font_size",32)
	clock_label.add_theme_color_override("font_color",Color.WHITE)
	clock_label.add_theme_color_override("font_outline_color",Color(0.04,0.06,0.10,1))
	clock_label.add_theme_constant_override("outline_size",6)
	_clock_root.add_child(clock_label)
	clock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	clock_label.offset_left = -184.0
	clock_label.offset_top = 24.0 # 固定在屏幕右上角，与右侧留白一致。
	clock_label.offset_right = -24.0
	clock_label.offset_bottom = 72.0

static func daylight_at(value:float) -> float:
	var hour:float = fposmod(value,DAY_MINUTES)/60.0
	if hour<5.0 or hour>=20.0: return 0.0
	if hour<8.0: return smoothstep(5.0,8.0,hour)
	if hour<=16.0: return 1.0
	return 1.0-smoothstep(16.0,20.0,hour)

static func sun_direction_at(value:float) -> Vector2:
	# 屏幕 Y 向下，正角度为顺时针：12右上 -> 18右下 -> 00左下 -> 06左上。
	return Vector2(1.0,-1.0).normalized().rotated(TAU*(fposmod(value,DAY_MINUTES)-START_MINUTES)/DAY_MINUTES)

func time_text() -> String:
	var whole:int = int(floor(minutes+0.000001)) % int(DAY_MINUTES)
	return "%02d:%02d" % [whole/60,whole%60]

func refresh_enabled() -> void:
	var game:Node = get_node_or_null("/root/Game")
	enabled = game == null or bool(game.Game_Settings.get(SETTING,true))
	if is_instance_valid(clock_layer): clock_layer.visible = enabled
	if not enabled: set_minutes(START_MINUTES)

func set_minutes(value:float) -> void:
	if not is_finite(value): return
	minutes = fposmod(value,DAY_MINUTES) if enabled else START_MINUTES
	_apply_state()

func reset_to_noon() -> void:
	set_minutes(START_MINUTES)

func advance(delta:float) -> void:
	if not enabled or not advancing or not is_finite(delta) or delta<=0.0: return
	if not is_inside_tree() or get_tree().paused or Engine.time_scale<=0.000001: return
	var game:Node = get_node_or_null("/root/Game")
	if game == null or game.now_stop_state: return
	# Engine 传来的 delta 已含倍速，只乘一次。没有按现实时间补算暂停期间。
	set_minutes(minutes+delta*MINUTES_PER_SECOND)

func _apply_state() -> void:
	daylight = daylight_at(minutes)
	if is_instance_valid(world): world.map_wall_light_direction = sun_direction_at(minutes)
	apply_lighting()
	var whole:int = int(floor(minutes+0.000001)) % int(DAY_MINUTES)
	if is_instance_valid(clock_label) and whole!=_shown_minute:
		clock_label.text = time_text()
		_shown_minute = whole

func apply_lighting() -> void:
	# 换主题/开门时可重用当前状态；不会重置时间，也不会重建墙网格。
	if is_instance_valid(tint):
		tint.color = NIGHT_TINT.lerp(Color.WHITE,daylight)
		tint.visible = daylight<0.999999
	if is_instance_valid(world) and is_instance_valid(world.map_wall_volume):
		world.map_wall_volume.update_time_lighting(world.map_wall_light_direction,daylight)
