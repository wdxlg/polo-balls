extends Control
## 1v1 顶部对战 HUD（2026-09-28）。
##
## 仅当场上恰好剩两名主角色、且分属两个阵营时显示（召唤物不算；比赛延续/死亡演出桥
## 沿用 return_battle_sides 的同一代表规则）。左右为原版 tooltip 面板：物品展示框头像、
## 角色名（与普通 VS 同色）、10 颗原版红心、盔甲值行（仅减伤 > 0 时）及当前/最大生命数字；
## 中间为原版药水效果背景，显示本局已过去的游戏时间与 VS。原有文字 VS 标题保留不动。
##
## 与普通 VS 文字/世界时间的配合（2026-09-28 用户要求）：本 HUD 显示期间（含结算动画与
## 成就框阶段）隐藏普通文字 VS——只把 versus_label.self_modulate 透明度置 0，不改 visible
## （本 HUD 的显示条件与避让布局都依赖它，文字仍占位；录制镜像经 battle_record_locale._style
## 同步 self_modulate，中/英录制里同样隐藏），HUD 隐藏/退出时恢复原透明度。右上角世界时间
## （day_night_cycle.clock_label）在 HUD 显示期间下移到面板下方 CLOCK_GAP 处；结算动画开始
## （HUD 上移出屏）或 HUD 隐藏时，以与 HUD 上移相同的 quart ease-out、同 0.45 秒真实时间
## 先快后慢地移回原位；出现时的下移同样用该缓动。
##
## 红心行（2026-09-28）：10 颗心 = 最大生命，全部按实时数值连续换算（不取整到半心，
## 37/420 就是 0.88 颗心，按原版心形可见 7 列像素比例裁切）：
## - 红心：当前生命，从低血量端（靠头像一侧）排起，掉血从远端往头像方向减少；
## - 护盾（block）：从低血量端起把心染成原版盔甲图标的配色；
## - 伤害吸收（原版吸收效果剩余量）：从高血量端（远离头像）起染成原版金色吸收心；
## - 盔甲值 = 实时 Damage_reduction（抗性提升、铁匠头盔、各种减伤 buff 都已汇总在内），
##   10 个原版盔甲图标 = 100% 减伤，每半个 5%，从低血量端排起；<= 0 时整行不显示。
##
## 计时按游戏时间：只在 is_combat_runtime_active() 时累加物理 delta（暂停/时间停止不走、
## 倍速同步），胜利铃响后冻结，重置/重打/新一局归零。决出胜负后保留最后一对的结果画面，
## 直到重置或出现新的对阵。
##
## 录制：CanvasLayer 只属于玩家 Viewport，battle_record_locale 会为中/英抓帧视口各调用
## make_mirror()，镜像只读取本体状态并按各自语言翻译角色名，不重复计时或扫描。
##
## 对战结束（2026-09-28）：HUD 显示中且胜利铃响时正好一方存活 → 镜头经公共
## request_cinematic_focus 推进胜利者（不慢放）；HUD 先快后慢向上移出屏幕，随后原版成就
## 提示框（挑战完成）从上方先快后慢落到 HUD 原位置，图标为胜利者头像，正文“xxx 获得了胜利”。
## 保持到重置/新对阵；动画按真实时间，镜像读取本体进度按各自语言显示。

const PORTRAITS = preload("res://scripts/ui/rotation_portraits.gd")
const FONT:Font = preload("res://fonts/Mojangles.ttf")
const TOOLTIP_BACKGROUND:Texture2D = preload("res://Images/UI/minecraft_tooltips/tooltip_background.png")
const TOOLTIP_FRAME:Texture2D = preload("res://Images/UI/minecraft_tooltips/tooltip_frame.png")
const EFFECT_BACKGROUND:Texture2D = preload("res://Images/UI/minecraft_tooltips/effect_background_large.png")
const ITEM_FRAME:Texture2D = preload("res://Images/UI/rotation_frames/item_frame.png")
# 原版 1.21.4 HUD 精灵（Images/UI/minecraft_hud/SOURCE.json）。
const HEART_CONTAINER:Texture2D = preload("res://Images/UI/minecraft_hud/heart_container.png")
const HEART_FULL:Texture2D = preload("res://Images/UI/minecraft_hud/heart_full.png")
const HEART_ABSORBING_FULL:Texture2D = preload("res://Images/UI/minecraft_hud/heart_absorbing_full.png")
const ARMOR_FULL:Texture2D = preload("res://Images/UI/minecraft_hud/armor_full.png")
const ARMOR_HALF:Texture2D = preload("res://Images/UI/minecraft_hud/armor_half.png")
const ARMOR_EMPTY:Texture2D = preload("res://Images/UI/minecraft_hud/armor_empty.png")
const TOAST_ADVANCEMENT:Texture2D = preload("res://Images/UI/minecraft_hud/toast_advancement.png")
# 原版成就提示框 160×32：图标槽 (8,8,16,16)，标题/正文从 x=30 起、y=7/18；挑战类标题色 0xFF88FF。
const TOAST_PIXEL:float = 5.0
const TOAST_SOURCE_SIZE:Vector2 = Vector2(160.0,32.0)
const TOAST_TITLE_COLOR:Color = Color("ff88ff")
const TOAST_BODY_COLOR:Color = Color("ffffff")
const TOAST_TEXT:Dictionary = {
	"zh":{"title":"挑战已完成！","body":"%s 获得了胜利"},
	"en":{"title":"Challenge Complete!","body":"%s won!"},
}
const OUTRO_HUD_TIME:float = 0.45
const OUTRO_TOAST_DELAY:float = 0.40
const OUTRO_TOAST_TIME:float = 0.60
const WINNER_FOCUS_SLOW:float = 1.0 # 不慢放
const WINNER_FOCUS_ZOOM:float = -1.0 # 用 World 默认电影镜头放大倍率
## 胜利推进时长（真实秒）。World 公共电影镜头默认 0.34 秒，胜利结算太突兀；仅本次请求临时改用
## 1.6 秒，曲线仍是 World 的 quart ease-out（先快后慢），请求后立即恢复，其他调用方不受影响。
const WINNER_FOCUS_ENTER_SECONDS:float = 1.6
# 护盾心：原版红心三色 → 原版 armor_full 三色（主色/高光/暗部）逐像素换色，不新画。
const SHIELD_PALETTE:Dictionary = {
	"ff1313":Color("b8b9c4"),
	"ffc8c8":Color("e6e7f2"),
	"bb1313":Color("696a70"),
}

# 以 1080 逻辑宽度设计；实际视口宽度不同时整体等比缩放。
const DESIGN_WIDTH:float = 1080.0
const TOP:float = 32.0
const SIDE_MARGIN:float = 24.0
const GAP:float = 12.0
const SIDE_WIDTH:float = 404.0
const PANEL_HEIGHT:float = 176.0
const PAD:float = 20.0
const PORTRAIT_SIZE:float = 96.0 # item_frame 32px × 3（与 tooltip 同为 GUI 像素 ×3）
const PORTRAIT_TOP:float = 16.0
# 原版心/盔甲 9×9 精灵、间距 8；×3 后一行 10 个宽 243，放进头像旁 254 宽的文字列。
const ICON_PIXEL:float = 3.0
const ICON_SOURCE:float = 9.0
const ICON_STEP:float = 8.0
const ICON_COUNT:int = 10
const HALF_UNITS:int = 20
const NAME_BASELINE:float = 32.0 # 相对头像顶
const HEART_ROW_TOP:float = 42.0
const ARMOR_ROW_TOP:float = 76.0
const HP_BASELINE:float = 158.0 # 相对面板顶，头像下方整行
# 与 mc_effect_tooltip.gd 相同：GUI 像素倍率 3，tooltip 背景/边框 9/10，药水框 5。
const GUI_PIXEL:float = 3.0
const TOOLTIP_BACKGROUND_BORDER:int = 9
const TOOLTIP_FRAME_BORDER:int = 10
const TOOLTIP_TRANSPARENT_EDGE:float = 8.0 # tooltip 背景贴图四周 8px 透明
const EFFECT_BORDER:int = 5
const NAME_MAX_SIZE:int = 40
const NAME_MIN_SIZE:int = 20
const HP_TEXT_SIZE:int = 30
const TIME_TEXT_SIZE:int = 40
const VS_TEXT_SIZE:int = 72
const TIME_COLOR:Color = Color("ffff55") # 原版黄色格式码 §e
const HP_TEXT_COLOR:Color = Color("ffffff")
const DEAD_TINT:Color = Color(0.38,0.38,0.38,1.0)
# 阵亡文字比头像稍亮，保证结果画面仍能读清名字与 0 血。
const DEAD_TEXT_TINT:Color = Color(0.62,0.62,0.62,1.0)
const SCAN_INTERVAL:float = 0.10
# 玩家画面顶部工具栏（游戏设置/队伍/重置…）可见时会盖住 HUD：本体改为排在工具栏下方、
# 原文字 VS 标题上方，并整体等比缩小居中。录制画面没有工具栏，镜像保持原布局。
const TOOLBAR_GAP:float = 8.0
const TITLE_GAP:float = 6.0
const DEFAULT_TITLE_TOP:float = 240.0
const MIN_FIT_SCALE:float = 0.5

var world:Node
## 录制镜像才设置：指向玩家画面上的本体 HUD。
var source:Control = null
## 空字符串 = 跟随游戏当前语言；镜像为 "zh" / "en"。
var locale:String = ""
var visibility_bit:int = 2
## 视口宽度 / 1080 的基础倍率（不含避让工具栏的缩放）；镜像沿用它而不是本体的最终 scale。
var layout_base_scale:float = 1.0
## 避让工具栏后的额外缩放（1 = 原布局）。
var layout_fit_scale:float = 1.0

## 已过去的游戏时间（秒）。
var elapsed:float = 0.0
var timed_mode:bool = false
var timed_remaining:float = 0.0
var timed_overtime:bool = false
var round_result_locked:bool = false
var round_exit:float = 0.0
## 两侧快照：{side_key, raw_name, color, texture, nodes, hp, max_hp, dead}
var sides:Array = []
## 结算动画：开始后保持到重置/新对阵。outro_elapsed 为真实秒数。
var outro_active:bool = false
var outro_elapsed:float = 0.0
var winner_index:int = -1
var victory_result:Dictionary = {}
var _victory_roster:Dictionary = {}
var _wool_cache:Dictionary = {}
const WOOL_NAMES:Array[String] = ["white","orange","magenta","light_blue","yellow","lime","pink","gray","light_gray","cyan","purple","blue","brown","green","red","black"]
const WOOL_ZH:Array[String] = ["白色","橙色","品红色","浅蓝色","黄色","黄绿色","粉色","灰色","浅灰色","青色","紫色","蓝色","棕色","绿色","红色","黑色"]
const WOOL_COLORS:Array[Color] = [Color("f9fffe"),Color("f9801d"),Color("c74ebd"),Color("3ab3da"),Color("fed83d"),Color("80c71f"),Color("f38baa"),Color("474f52"),Color("9d9d97"),Color("169c9c"),Color("8932b8"),Color("3c44aa"),Color("835432"),Color("5e7c16"),Color("b02e26"),Color("1d1d21")]
var _focus_requested:bool = false
var _panel_shift:float = 0.0

var _portraits:RefCounted = PORTRAITS.new()
var _pair_signature:String = ""
var _generation:int = -2147483648
var _serial:int = -2147483648
var _scan_elapsed:float = 999.0
var _text_layer:Control
var _tooltip_background_box:StyleBoxTexture
var _tooltip_frame_box:StyleBoxTexture
var _effect_box:StyleBoxTexture
static var _shield_full:Texture2D = null


func _ready() -> void:
	if name.is_empty() or name.begins_with("@"):
		name = "DuelTopHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 101
	# 原版 GUI 贴图按整数倍像素放大；文字放在单独的子画布保持字体自身过滤。
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visibility_layer = visibility_bit
	_tooltip_background_box = _make_box(TOOLTIP_BACKGROUND,TOOLTIP_BACKGROUND_BORDER)
	_tooltip_frame_box = _make_box(TOOLTIP_FRAME,TOOLTIP_FRAME_BORDER)
	_effect_box = _make_box(EFFECT_BACKGROUND,EFFECT_BORDER)
	_ensure_shield_textures()
	_text_layer = Control.new()
	_text_layer.name = "Text"
	_text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_text_layer.visibility_layer = visibility_bit
	_text_layer.draw.connect(_draw_text)
	add_child(_text_layer)
	visible = false
	_apply_layout()


func _make_box(texture:Texture2D,border:int) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = border
	box.texture_margin_top = border
	box.texture_margin_right = border
	box.texture_margin_bottom = border
	return box


static func _palette_swap(texture:Texture2D) -> Texture2D:
	var image:Image = texture.get_image()
	if image == null:
		return texture
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y:int in range(image.get_height()):
		for x:int in range(image.get_width()):
			var c:Color = image.get_pixel(x,y)
			if c.a <= 0.0:
				continue
			var key:String = c.to_html(false).to_lower()
			if SHIELD_PALETTE.has(key):
				var swapped:Color = SHIELD_PALETTE[key]
				swapped.a = c.a
				image.set_pixel(x,y,swapped)
	return ImageTexture.create_from_image(image)


static func _ensure_shield_textures() -> void:
	if _shield_full == null:
		_shield_full = _palette_swap(HEART_FULL)


## 数值 → 心数（0..10，连续值）：10 颗心 = full。
static func heart_amount(amount:float,full:float) -> float:
	if amount <= 0.0 or full <= 0.0:
		return 0.0
	return clampf(amount / full * float(ICON_COUNT),0.0,float(ICON_COUNT))


## 第 index 颗心（0 = 低血量端）被 amount 颗心占据的比例。
static func heart_fill(hearts:float,index:int) -> float:
	return clampf(hearts - float(index),0.0,1.0)


## 从高血量端排起的 amount 颗心，覆盖第 index 颗心的比例。
static func heart_fill_from_high(hearts:float,index:int) -> float:
	return clampf(float(index + 1) - (float(ICON_COUNT) - hearts),0.0,1.0)


## 减伤比例 → 半盔甲数：10 个 = 100%，每半个 5%，四舍五入；正值至少半个。
static func armor_half_units(reduction:float) -> int:
	if reduction <= 0.0:
		return 0
	return clampi(roundi(reduction * float(HALF_UNITS)),1,HALF_UNITS)


## 为录制抓帧视口生成一个只读镜像。
func make_mirror(target_locale:String,layer_bit:int) -> Control:
	var mirror:Control = get_script().new()
	mirror.world = world
	mirror.source = self
	mirror.locale = target_locale
	mirror.visibility_bit = layer_bit
	mirror.name = "DuelTopHud_" + target_locale
	mirror.set_meta("recording_copy",true)
	return mirror


func is_mirror() -> bool:
	return source != null


func _data():
	return source if is_mirror() else self


#========================================================
# 计时（只在本体上运行）
#========================================================
func _physics_process(delta:float) -> void:
	if is_mirror() or not is_instance_valid(world):
		return
	_update_clock(delta)


func _update_clock(delta:float) -> void:
	timed_mode=Game.is_timed_training_mode()
	if timed_mode:
		timed_remaining=maxf(float(world.get("_timed_time_left")),0.0)
		timed_overtime=bool(world.get("_timed_overtime"))
	if round_result_locked: return
	var generation:int = int(world.get("_victory_bell_sequence_generation"))
	var serial:int = int(world.call("get_character_dialogue_battle_serial")) if world.has_method("get_character_dialogue_battle_serial") else 0
	if generation != _generation or serial != _serial:
		# 重置/重打/新一局：计时归零，旧对阵结果不再保留。
		_generation = generation
		_serial = serial
		elapsed = 0.0
		_clear_pair()
	if bool(world.get("_victory_bell_played")):
		return
	if bool(world.call("is_combat_runtime_active")):
		elapsed += maxf(delta,0.0)


static func format_elapsed(seconds:float) -> String:
	var total:int = maxi(0,floori(seconds))
	var hours:int = total / 3600
	var minutes:int = (total / 60) % 60
	var secs:int = total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours,minutes,secs]
	return "%02d:%02d" % [minutes,secs]


#========================================================
# 对阵识别（只在本体上运行）
#========================================================
func _process(delta:float) -> void:
	if is_mirror():
		var shown:bool = is_instance_valid(source) and source.visible
		visible = shown
		if shown:
			# 录制视口没有工具栏：只跟随基础倍率，不继承本体为避让工具栏做的下移/缩小。
			position = Vector2.ZERO
			scale = Vector2.ONE * source.layout_base_scale
			size = source.size
			queue_redraw()
			_text_layer.queue_redraw()
		return
	if not is_instance_valid(world):
		visible = false
		return
	_scan_elapsed += delta
	if _scan_elapsed >= SCAN_INTERVAL and not round_result_locked:
		_scan_elapsed = 0.0
		for unit:Node in world._battle_units_cache: remember_victory_participant(unit)
		_refresh_pair()
	if not round_result_locked: _refresh_values()
	_apply_layout()
	_update_outro(delta)
	var shown_now:bool = _should_show()
	if visible != shown_now:
		visible = shown_now
	_sync_versus_title(visible)
	_update_world_clock(delta)
	if visible:
		queue_redraw()
		_text_layer.queue_redraw()


func _should_show() -> bool:
	if round_result_locked: return true
	if bool(world.get("_dead_save_ui_override_active")):
		return false
	if bool(world.get("_armor_stand_test_hud_active")):
		return false
	if not victory_result.is_empty() and outro_active: return true
	if sides.size()!=2:
		return timed_mode and (bool(world.get("_timed_running")) or bool(world.get("_timed_finished")))
	# 普通 VS 标题因布阵/盔甲架/Boss 车轮战等模式主动隐藏时，本 HUD 同样不出现。
	var title:Variant = world.get("versus_label")
	return title is CanvasItem and is_instance_valid(title) and (title as CanvasItem).visible


func _apply_layout() -> void:
	var viewport_size:Vector2 = get_viewport_rect().size
	var factor:float = maxf(viewport_size.x,1.0) / DESIGN_WIDTH
	layout_base_scale = factor
	size = Vector2(DESIGN_WIDTH,TOP + PANEL_HEIGHT + 8.0)
	var fit:float = 1.0
	var offset:Vector2 = Vector2.ZERO
	if not is_mirror():
		var toolbar_bottom:float = _toolbar_bottom_design(factor)
		if toolbar_bottom + TOOLBAR_GAP > TOP:
			var top_limit:float = toolbar_bottom + TOOLBAR_GAP
			var bottom_limit:float = _title_top_design(factor) - TITLE_GAP
			fit = clampf((bottom_limit - top_limit) / PANEL_HEIGHT,MIN_FIT_SCALE,1.0)
			offset = Vector2(DESIGN_WIDTH * (1.0 - fit) * 0.5,top_limit - TOP * fit)
	layout_fit_scale = fit
	position = offset * factor
	scale = Vector2.ONE * factor * fit
	if is_instance_valid(_text_layer):
		_text_layer.position = Vector2.ZERO
		_text_layer.size = size


## 屏幕坐标 → 本 HUD 父级画布的设计坐标（1080 宽）。
func _screen_to_design(point:Vector2,factor:float) -> Vector2:
	var parent_canvas:Transform2D = get_global_transform_with_canvas() * get_transform().affine_inverse()
	return (parent_canvas.affine_inverse() * point) / maxf(factor,0.0001)


## 顶部工具栏可见时返回其底边（设计坐标），否则返回 -INF。
func _toolbar_bottom_design(factor:float) -> float:
	var control:Variant = world.get("control") if is_instance_valid(world) else null
	if not (control is Control) or not is_instance_valid(control):
		return -INF
	var bar:Control = (control as Control).get_node_or_null("Settings") as Control
	if bar == null or not bar.is_visible_in_tree():
		return -INF
	var bar_layer:CanvasLayer = bar.get_canvas_layer_node()
	if bar_layer != null and not bar_layer.visible:
		return -INF
	var bar_canvas:Transform2D = bar.get_global_transform_with_canvas()
	var bottom:float = maxf(_screen_to_design(bar_canvas * Vector2(0.0,bar.size.y),factor).y,_screen_to_design(bar_canvas * bar.size,factor).y)
	# 工具栏滑出屏幕顶部（底边 ≤ 0）时视为不可见。
	return bottom if bottom > 0.0 else -INF


func _title_top_design(factor:float) -> float:
	var title:Variant = world.get("versus_label") if is_instance_valid(world) else null
	if title is Control and is_instance_valid(title):
		return _screen_to_design((title as Control).get_global_transform_with_canvas() * Vector2.ZERO,factor).y
	return DEFAULT_TITLE_TOP


func _clear_pair() -> void:
	_reset_outro()
	sides = []
	_pair_signature = ""


func _exit_tree() -> void:
	if not is_mirror():
		_reset_outro()
		_sync_versus_title(false)
		_restore_world_clock()


#========================================================
# 普通 VS 文字 / 世界时间配合（只在本体上运行，2026-09-28）
#========================================================
const TITLE_ALPHA_META:StringName = &"duel_top_hud_title_alpha"
## 时间文字顶边与 HUD 面板底边（屏幕坐标）的间距。
const CLOCK_GAP:float = 8.0
const CLOCK_MOVE_TIME:float = OUTRO_HUD_TIME
## 世界时间当前相对原位置的下移量（时钟所在画布坐标）。
var clock_shift:float = 0.0
var _clock_label:Control = null
var _clock_base:Vector2 = Vector2.ZERO # 原 offset_top / offset_bottom
var _clock_down:bool = false
var _clock_from:float = 0.0
var _clock_t:float = 1.0


## conceal=true：普通 VS 文字透明度置 0（记住原值）；false：恢复。绝不改 visible。
func _sync_versus_title(conceal:bool) -> void:
	if not is_instance_valid(world):
		return
	var title:Variant = world.get("versus_label")
	if not (title is CanvasItem) or not is_instance_valid(title):
		return
	var item:CanvasItem = title
	var color:Color = item.self_modulate
	if conceal:
		if not item.has_meta(TITLE_ALPHA_META):
			item.set_meta(TITLE_ALPHA_META,color.a)
		if color.a != 0.0:
			color.a = 0.0
			item.self_modulate = color
	elif item.has_meta(TITLE_ALPHA_META):
		color.a = float(item.get_meta(TITLE_ALPHA_META))
		item.remove_meta(TITLE_ALPHA_META)
		item.self_modulate = color


func world_clock_label() -> Control:
	if not is_instance_valid(world):
		return null
	var cycle:Variant = world.get("day_night_cycle")
	if not (cycle is Object) or not is_instance_valid(cycle):
		return null
	var label:Variant = cycle.get("clock_label")
	if label is Control and is_instance_valid(label):
		return label
	return null


## 让时间文字顶边落到 HUD 面板底边下方 CLOCK_GAP 所需的下移量（不上移，最少为 0）。
func _clock_target_shift(label:Control) -> float:
	var panel_bottom:float = (get_global_transform_with_canvas() * Vector2(0.0,TOP + PANEL_HEIGHT)).y
	var parent_xf:Transform2D = label.get_global_transform_with_canvas() * label.get_transform().affine_inverse()
	var base_top:float = (parent_xf * Vector2(0.0,label.position.y - clock_shift)).y
	var unit:float = maxf(absf(parent_xf.get_scale().y),0.0001)
	return maxf((panel_bottom + CLOCK_GAP - base_top) / unit,0.0)


func _update_world_clock(delta:float) -> void:
	var label:Control = world_clock_label()
	if label != _clock_label:
		_restore_world_clock()
		if label == null:
			return
		_clock_label = label
		_clock_base = Vector2(label.offset_top,label.offset_bottom)
	var down:bool = visible and not outro_active
	var target:float = _clock_target_shift(label) if down else 0.0
	if down != _clock_down:
		_clock_down = down
		_clock_from = clock_shift
		_clock_t = 0.0
	if _clock_t < 1.0:
		# 与结算动画一致按真实时间推进，不受慢动作/倍速影响。
		_clock_t = minf(_clock_t + delta / maxf(Engine.time_scale,0.0001) / CLOCK_MOVE_TIME,1.0)
		clock_shift = lerpf(_clock_from,target,ease_out(_clock_t))
	else:
		clock_shift = target # 静止时直接跟随（工具栏避让等布局变化）。
	label.offset_top = _clock_base.x + clock_shift
	label.offset_bottom = _clock_base.y + clock_shift


func _restore_world_clock() -> void:
	if is_instance_valid(_clock_label):
		_clock_label.offset_top = _clock_base.x
		_clock_label.offset_bottom = _clock_base.y
	_clock_label = null
	clock_shift = 0.0
	_clock_down = false
	_clock_t = 1.0


## 先快后慢（quart ease-out）。
static func ease_out(t:float) -> float:
	var x:float = clampf(t,0.0,1.0)
	return 1.0 - pow(1.0 - x,4.0)


func reset_victory_roster() -> void:
	_victory_roster.clear()
	_clear_pair() # Do not let a stale one-survivor pair recreate the old achievement.
	elapsed=0.0
	_scan_elapsed=999.0
	visible=false
	_sync_versus_title(false)

func remember_victory_participant(unit:Node) -> void:
	if Game.is_rotation_training_mode() or not is_instance_valid(unit) or not unit is ball: return
	if not world._is_primary_battle_character(unit) or world._is_runtime_summon(unit) or unit.has_meta("development_reserve"): return
	if unit.is_queued_for_deletion() or unit.health<=0 or bool(unit.get_meta("battle_lifecycle_exiting",false)): return
	var identity:Dictionary=unit.get_meta("battle_lifecycle_identity",{})
	if not identity.is_empty() and (int(identity.get("generation",-1))!=world._battle_lifecycle_generation or int(identity.get("round",-1))!=world._battle_lifecycle_round): return
	var setup_id:int=int(identity.get("setup",unit.get_meta("battle_setup_id",-1)))
	if not world.is_victory_setup_current(setup_id): return
	var id:String="setup:"+str(setup_id) if setup_id>=0 else "root:"+str(identity.get("root",unit.get_instance_id()))
	_victory_roster[id]={"key":world._victory_side_key_for_character(unit),"name":world.return_ball_display_name(unit),
		"scene_path":unit.scene_file_path,"node":weakref(unit),"setup":setup_id}

func _build_victory_result() -> Dictionary:
	if Game.is_rotation_training_mode(): return {}
	var alive:Dictionary=world._collect_alive_victory_sides()
	var key:String=""
	if Game.is_timed_training_mode() and world._timed_finished:
		for record:Dictionary in _victory_roster.values():
			if int(record.setup)==int(world._timed_winner_setup): key=str(record.key);break
	elif alive.size()==1: key=str(alive.keys()[0])
	if key.is_empty(): return {}
	var members:Dictionary={}
	var team_order:Array[String]=[]
	# Configured roots retain original membership even if they died before the first HUD scan.
	for entry:Dictionary in world._battle_setup:
		if str(entry.get("kind",""))=="obstacle": continue
		if not world.is_victory_setup_current(int(entry.get("id",-1))): continue
		var team:String=str(entry.get("team",""))
		var entry_key:String="team:"+team if not team.is_empty() else "solo_setup:"+str(entry.get("id",-1))
		if world._versus_is_named_team(entry_key) and not team_order.has(entry_key): team_order.append(entry_key)
		if entry_key==key: members["setup:"+str(entry.id)]={"name":str(entry.get("char","")),"scene_path":str(entry.get("scene_path",""))}
	for id:String in _victory_roster:
		var record:Dictionary=_victory_roster[id]
		if world._versus_is_named_team(record.key) and not team_order.has(record.key): team_order.append(record.key)
		if record.key==key: members[id]=record
	if members.is_empty(): return {}
	var nodes:Array=[]
	for unit:Node in world._battle_units_cache:
		if is_instance_valid(unit) and world._battle_unit_keeps_family_alive(unit) and world._victory_side_key_for_character(unit)==key: nodes.append(unit)
	var first:Dictionary=members.values()[0]
	var is_team:bool=key.begins_with("team:") and members.size()>1
	var color:Color=world._versus_side_color(key,team_order.size(),team_order.find(key))
	return {"key":key,"is_team":is_team,"member_count":members.size(),"raw_name":first.name,
		"scene_path":first.scene_path,"color":color,"wool":_wool_for_color(color),"nodes":nodes}

func _wool_for_color(color:Color) -> String:
	if color.is_equal_approx(Color(0.25,0.65,1.0)): return "blue"
	if color.is_equal_approx(Color(1.0,0.26,0.26)): return "red"
	var best:int=0
	var distance:float=INF
	for i:int in range(WOOL_COLORS.size()):
		var c:Color=WOOL_COLORS[i]
		var gap:float=Vector3(color.r,color.g,color.b).distance_squared_to(Vector3(c.r,c.g,c.b))
		if gap<distance: distance=gap;best=i
	return WOOL_NAMES[best]

func _victory_texture() -> Texture2D:
	var result:Dictionary=_data().victory_result
	if bool(result.get("is_team",false)):
		var wool:String=str(result.wool)
		if not _wool_cache.has(wool): _wool_cache[wool]=load("res://Images/UI/team_victory/"+wool+"_wool.png")
		return _wool_cache[wool]
	return _portraits.resolve(world,{"char":str(result.get("raw_name","")),"scene_path":str(result.get("scene_path",""))})

func victory_body_text() -> String:
	var data=_data()
	var result:Dictionary=data.victory_result
	var display:String=""
	if not result.is_empty():
		if bool(result.is_team):
			var index:int=WOOL_NAMES.find(str(result.wool))
			display=WOOL_ZH[index]+"队伍" if _toast_locale()=="zh" else str(result.wool).replace("_"," ").capitalize()+" Team"
		else: display=_display_name(str(result.raw_name))
	elif data.winner_index>=0 and data.winner_index<data.sides.size(): display=_display_name(str(data.sides[data.winner_index].raw_name))
	else: return "双方战败" if _toast_locale()=="zh" else "Double knockout"
	return str(TOAST_TEXT[_toast_locale()].body)%display

func _draw_wool_cube(texture:Texture2D,rect:Rect2,tint:Color=Color.WHITE) -> void:
	var uv:=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	var faces:Array=[ [Vector2(0.5,0),Vector2(1,0.25),Vector2(0.5,0.5),Vector2(0,0.25)],
		[Vector2(0,0.25),Vector2(0.5,0.5),Vector2(0.5,1),Vector2(0,0.75)],
		[Vector2(0.5,0.5),Vector2(1,0.25),Vector2(1,0.75),Vector2(0.5,1)] ]
	for i:int in range(3):
		var points:=PackedVector2Array()
		for point:Vector2 in faces[i]: points.append(rect.position+point*rect.size)
		var shade:float=[1.0,0.8,0.6][i]
		draw_polygon(points,PackedColorArray([Color(shade,shade,shade)*tint]),uv,texture)

func _update_outro(delta:float) -> void:
	if outro_active:
		# 真实时间：不受倍速/训练加速影响；暂停时 _process 不跑，自然冻结。
		outro_elapsed = minf(outro_elapsed + delta / maxf(Engine.time_scale,0.0001),30.0)
		return
	if not bool(world.get("_victory_bell_played")): return
	if not Game.is_rotation_training_mode(): victory_result=_build_victory_result()
	if victory_result.is_empty() and (not visible or sides.size()!=2): return
	var alive:Array[int] = []
	for i:int in range(sides.size()):
		if not bool(sides[i].dead):
			alive.append(i)
	if victory_result.is_empty() and alive.size()!=1:
		return # 同归于尽等无唯一胜者时不播放
	outro_active = true
	outro_elapsed = 0.0
	winner_index = alive[0] if alive.size()==1 else -1
	var winner:Node2D = null
	var focus_nodes:Array=victory_result.get("nodes",[]) if not victory_result.is_empty() else sides[winner_index].nodes
	for raw:Variant in focus_nodes:
		if raw is Node2D and is_instance_valid(raw) and not (raw as Node).is_queued_for_deletion():
			winner = raw
			break
	if winner != null and world.has_method("request_cinematic_focus"):
		var has_duration:bool = "cinematic_focus_enter_duration" in world
		var previous_duration:Variant = world.get("cinematic_focus_enter_duration") if has_duration else null
		if has_duration: world.set("cinematic_focus_enter_duration",WINNER_FOCUS_ENTER_SECONDS)
		world.call("request_cinematic_focus",self,winner,WINNER_FOCUS_SLOW,WINNER_FOCUS_ZOOM)
		if has_duration: world.set("cinematic_focus_enter_duration",previous_duration)
		_focus_requested = true


func _reset_outro() -> void:
	if _focus_requested and is_instance_valid(world) and world.has_method("release_cinematic_focus"):
		world.call("release_cinematic_focus",self)
	_focus_requested = false
	victory_result.clear()
	outro_active = false
	outro_elapsed = 0.0
	winner_index = -1


## 本实例坐标里“完全移出视口顶部”所需的位移（镜像与本体各按自己的变换计算）。
func _offscreen_top_local() -> float:
	return -(position.y / maxf(scale.y,0.0001))


func _outro_panel_shift(data) -> float:
	if not bool(data.outro_active):
		return 0.0
	var distance:float = TOP + PANEL_HEIGHT + TOOLTIP_TRANSPARENT_EDGE * GUI_PIXEL + 16.0 - _offscreen_top_local()
	return -distance * ease_out(float(data.outro_elapsed) / OUTRO_HUD_TIME)


## 成就框矩形；未到出场时间返回空矩形。
func begin_round_result(winner_side:String) -> void:
	# Snapshot real roster identities before the old units are cleared, even if a summon finished the round.
	var entries:Dictionary={}
	var order:Array=["Team0","Team1"]
	for i:int in range(2):
		var side:String="left" if i==0 else "right"
		var roster:Array=world._rotation_rosters[side]
		var index:int=int(world._rotation_next_index[side])-1
		if index<0 or index>=roster.size(): return
		var record:Dictionary=roster[index]
		var actor:Node=world._find_character_by_setup_id_any(int(record.id))
		var row:Dictionary={"side_key":order[i],"raw_name":str(record.char),"color":Color("5599ff") if i==0 else Color("ff5555"),
			"texture":_portraits.resolve(world,record),"nodes":[actor] if is_instance_valid(actor) else [],
			"hp":float(actor.health) if is_instance_valid(actor) else 0.0,"max_hp":float(actor.Max_health) if is_instance_valid(actor) else 1.0,
			"block":0.0,"absorption":0.0,"reduction":0.0,"damage":0.0,"setup_id":int(record.id),"dead":side!=winner_side}
		entries[side]=row
	_reset_outro()
	sides=[entries.left,entries.right]
	round_result_locked=true
	round_exit=0.0
	winner_index=0 if winner_side=="left" else 1 if winner_side=="right" else -1
	outro_active=true
	outro_elapsed=0.0
	visible=true
func end_round_result() -> void:
	round_result_locked=false
	round_exit=0.0
	_clear_pair()
	_scan_elapsed=999.0

func _toast_rect(data) -> Rect2:
	if not bool(data.outro_active) or float(data.outro_elapsed) < OUTRO_TOAST_DELAY:
		return Rect2()
	var size_px:Vector2 = TOAST_SOURCE_SIZE * TOAST_PIXEL
	var final_y:float = TOP + (PANEL_HEIGHT - size_px.y) * 0.5
	var start_y:float = _offscreen_top_local() - size_px.y - 16.0
	var t:float = ease_out((float(data.outro_elapsed) - OUTRO_TOAST_DELAY) / OUTRO_TOAST_TIME)
	var y:float=lerpf(lerpf(start_y,final_y,t),start_y,ease_out(float(data.round_exit)))
	return Rect2((DESIGN_WIDTH - size_px.x) * 0.5,y,size_px.x,size_px.y)


func _toast_locale() -> String:
	var code:String = locale
	if code.is_empty():
		code = str(Game.get("current_locale"))
	return "zh" if code.begins_with("zh") else "en"


## 与 World.return_battle_sides() 相同的代表规则，但保留真实节点以读取生命。
func _collect_battle_sides() -> Dictionary:
	var order:Array[String] = []
	var entries:Dictionary = {} # side_key -> Array[{name, nodes}]
	var cache:Variant = world.get("_battle_units_cache")
	if not cache is Array:
		return {"order":order,"entries":entries}
	for node:Variant in cache:
		if not node is ball or not is_instance_valid(node):
			continue
		var b:ball = node
		if b.is_queued_for_deletion():
			continue
		var is_death_bridge:bool = bool(world.call("_is_battle_death_bridge_unit",b))
		if b.health <= 0 and not is_death_bridge:
			continue
		var is_primary:bool = bool(world.call("_is_primary_battle_character",b))
		var is_continuation:bool = bool(world.call("_is_battle_continuation_unit",b))
		if not is_primary and not is_continuation and not is_death_bridge:
			continue
		var side_key:String = str(world.call("return_ball_side_key",b))
		if is_continuation:
			var continuation_side:String = str(world.call("_battle_continuation_presentation_side_key",b))
			if not continuation_side.is_empty():
				side_key = continuation_side
		if is_death_bridge:
			var bridge_side:String = str(world.call("_battle_death_bridge_presentation_side_key",b))
			if not bridge_side.is_empty():
				side_key = bridge_side
		if not entries.has(side_key):
			order.append(side_key)
			entries[side_key] = []
		var display_name:String = str(world.call("return_ball_display_name",b))
		if is_continuation:
			var continuation_name:String = str(b.get_meta(&"battle_continuation_display_name","")).strip_edges()
			if not continuation_name.is_empty():
				display_name = continuation_name
		if is_death_bridge:
			var bridge_name:String = str(b.get_meta(&"battle_death_bridge_display_name","")).strip_edges()
			if not bridge_name.is_empty():
				display_name = bridge_name
		var side_entries:Array = entries[side_key]
		if is_continuation or is_death_bridge:
			# 一窝蠹虫等延续单位仍代表一名角色，生命合并显示。
			var merged:bool = false
			for entry:Dictionary in side_entries:
				if str(entry.name) == display_name:
					(entry.nodes as Array).append(b)
					merged = true
					break
			if merged:
				continue
		side_entries.append({"name":display_name,"nodes":[b]})
	return {"order":order,"entries":entries}


func _refresh_pair() -> void:
	if not victory_result.is_empty() and bool(world.get("_victory_bell_played")): return
	var collected:Dictionary = _collect_battle_sides()
	var order:Array = collected.order
	var entries:Dictionary = collected.entries
	if timed_mode:
		# 计时模式按队伍组对：本局正好 2 个队伍才显示对战面板（多于 2 队只显示计时器）。
		_refresh_timed_team_pair(order,entries)
		return
	var is_duel:bool = order.size() == 2
	if is_duel:
		for side_key:String in order:
			if (entries[side_key] as Array).size() != 1:
				is_duel = false
				break
	if is_duel:
		var signature_parts:PackedStringArray = PackedStringArray()
		for side_key:String in order:
			var entry:Dictionary = (entries[side_key] as Array)[0]
			var ids:PackedStringArray = PackedStringArray()
			for n:Node in entry.nodes:
				ids.append(str(n.get_instance_id()))
			signature_parts.append(side_key + "|" + str(entry.name) + "|" + ",".join(ids))
		var signature:String = "||".join(signature_parts)
		if signature != _pair_signature:
			_pair_signature = signature
			_build_sides(order,entries)
		else:
			# 同一对阵：只刷新颜色（布阵换队时蓝红重排）。
			_refresh_colors(order)
		return
	# 已决出胜负：场上不足两方时保留最后一对的结果，直到重置或出现新对阵。
	if order.size() <= 1 and _holds_result():
		return
	_clear_pair()


func _holds_result() -> bool:
	if sides.size() != 2:
		return false
	var alive_count:int = 0
	for side:Dictionary in sides:
		if not bool(side.dead):
			alive_count += 1
	return alive_count == 1


func _side_colors(order:Array) -> Array:
	var active_team_count:int = 0
	for side_key:String in order:
		if bool(world.call("_versus_is_named_team",side_key)):
			active_team_count += 1
	var colors:Array = []
	var team_index:int = 0
	for side_key:String in order:
		colors.append(world.call("_versus_side_color",side_key,active_team_count,team_index))
		if bool(world.call("_versus_is_named_team",side_key)):
			team_index += 1
	return colors


func _refresh_colors(order:Array) -> void:
	var colors:Array = _side_colors(order)
	for i:int in range(mini(colors.size(),sides.size())):
		sides[i].color = colors[i]


func _build_sides(order:Array,entries:Dictionary) -> void:
	var colors:Array = _side_colors(order)
	var built:Array = []
	for i:int in range(order.size()):
		var entry:Dictionary = (entries[order[i]] as Array)[0]
		var raw_name:String = str(entry.name)
		var first:Node = (entry.nodes as Array)[0]
		built.append({
			"side_key":order[i],
			"raw_name":raw_name,
			"color":colors[i],
			"texture":_resolve_portrait(raw_name,first),
			"nodes":(entry.nodes as Array).duplicate(),
			"setup_id":int(first.get_meta("battle_setup_id",first.get_meta("battle_lifecycle_identity",{}).get("setup",-1))),
			"damage":0.0,
			"hp":0.0,
			"max_hp":1.0,
			"block":0.0,
			"absorption":0.0,
			"reduction":0.0,
			"dead":false,
		})
	sides = built
	_reset_outro()
	_refresh_values()


## 计时模式的队伍对阵。队伍来自 World.timed_team_map()（布阵名单，队员阵亡也不会让队伍消失）；
## 人数超过 1 的队伍显示为队伍：羊毛方块 + “X色队伍”，数值为队伍总受伤。
## 签名只含队伍组成，不含节点：队员阵亡/复活只更新节点列表，不会重建面板打断结算动画。
func _refresh_timed_team_pair(order:Array,entries:Dictionary) -> void:
	var team_map:Dictionary = world.timed_team_map()
	var team_keys:Array = []
	var team_nodes:Dictionary = {}
	var team_names:Dictionary = {}
	for side_key:Variant in order:
		for entry:Dictionary in entries[side_key]:
			var entry_nodes:Array = entry.nodes
			if entry_nodes.is_empty(): continue
			var key:String = str(team_map.get(int(world._resolve_timed_source_setup_id(entry_nodes[0])),""))
			if key.is_empty(): continue
			if not team_keys.has(key):
				team_keys.append(key)
				team_nodes[key] = []
				team_names[key] = str(entry.name)
			(team_nodes[key] as Array).append_array(entry_nodes)
	var members:Dictionary = {}
	var setup_ids:Array = team_map.keys()
	setup_ids.sort()
	for raw_id:Variant in setup_ids:
		var key:String = str(team_map[raw_id])
		if not members.has(key): members[key] = []
		(members[key] as Array).append(int(raw_id))
		if not team_keys.has(key):
			team_keys.append(key)
			team_nodes[key] = []
			team_names[key] = str(world._timed_name_by_setup.get(int(raw_id),""))
	if team_keys.size() != 2:
		_clear_pair()
		return
	var signature_parts:PackedStringArray = PackedStringArray()
	for key:Variant in team_keys:
		signature_parts.append(str(key) + "|" + str(members.get(key,[])) + "|" + str(team_names[key]))
	var signature:String = "timed||" + "||".join(signature_parts)
	if signature != _pair_signature or sides.size() != 2:
		_pair_signature = signature
		var colors:Array = _side_colors(team_keys)
		var built:Array = []
		for i:int in range(2):
			var key:String = str(team_keys[i])
			var ids:Array = members.get(key,[])
			var nodes:Array = team_nodes[key]
			var raw_name:String = str(team_names[key])
			var is_team:bool = ids.size() > 1
			built.append({"side_key":key,"team_key":key,"is_team":is_team,"raw_name":raw_name,"color":colors[i],
				"texture":null if is_team else _resolve_portrait(raw_name,nodes[0] if not nodes.is_empty() else null),
				"nodes":nodes.duplicate(),"setup_id":int(ids[0]) if not ids.is_empty() else -1,
				"damage":0.0,"value_color":HP_TEXT_COLOR,"hp":0.0,"max_hp":1.0,"block":0.0,"absorption":0.0,"reduction":0.0,"dead":false})
		sides = built
		_reset_outro()
	else:
		_refresh_colors(team_keys)
		for i:int in range(2):
			var live_nodes:Array = team_nodes[str(team_keys[i])]
			sides[i].nodes = live_nodes.duplicate()
	_refresh_values()
func _resolve_portrait(raw_name:String,node:Node) -> Texture2D:
	# 变形者等身份名与场景不同的角色，按身份名查场景，与轮换头像框一致。
	var scene_path:String = ""
	if is_instance_valid(node) and node.scene_file_path.get_file().get_basename() == raw_name:
		scene_path = node.scene_file_path
	return _portraits.resolve(world,{"char":raw_name,"scene_path":scene_path})


func _refresh_values() -> void:
	var timed_teams:Dictionary = world.timed_team_map() if timed_mode and world.has_method("timed_team_map") else {}
	var timed_scores:Dictionary = world.timed_team_scores(timed_teams) if not timed_teams.is_empty() else {}
	for side:Dictionary in sides:
		# 计时模式：队伍总受伤（单人队伍即本人受伤），颜色按队伍受伤排名由白到红，与头顶数字同一份权威分数。
		var setup_id:int = int(side.get("setup_id",-1))
		var team_key:String = str(side.get("team_key",timed_teams.get(setup_id,"")))
		side.damage = float(timed_scores[team_key]) if timed_scores.has(team_key) else float(world._timed_damage_by_setup.get(setup_id,0.0))
		side.value_color = world.timed_heat_color(world.timed_team_heat(team_key,timed_scores)) if timed_scores.has(team_key) else HP_TEXT_COLOR
		var hp:float = 0.0
		var max_hp:float = 0.0
		var block:float = 0.0
		var absorption:float = 0.0
		var reduction:float = 0.0
		var any_valid:bool = false
		for raw:Variant in side.nodes:
			if not is_instance_valid(raw) or not raw is ball:
				continue
			var b:ball = raw
			if b.is_queued_for_deletion():
				continue
			any_valid = true
			hp += maxf(float(b.health),0.0)
			max_hp += maxf(float(b.Max_health),1.0)
			block += maxf(float(b.block),0.0)
			absorption += _absorption_of(b)
			# 合并显示的延续单位取最高减伤；负值（易伤）不显示盔甲。
			reduction = maxf(reduction,clampf(float(b.Damage_reduction),0.0,1.0))
		if any_valid:
			side.max_hp = max_hp
		side.hp = hp
		side.block = block if any_valid and hp > 0.0 else 0.0
		side.absorption = absorption if any_valid and hp > 0.0 else 0.0
		side.reduction = reduction if any_valid and hp > 0.0 else 0.0
		side.dead = hp <= 0.0


## 原版伤害吸收效果的剩余吸收量（与 ball._consume_minecraft_absorption 读同一节点）。
func _absorption_of(b:ball) -> float:
	var status:Node = b.get_node_or_null("MinecraftStatus_absorption")
	if status == null or status.is_queued_for_deletion():
		return 0.0
	return maxf(float(status.get("absorption_remaining")),0.0)


#========================================================
# 绘制（本体与镜像共用，数据取自本体）
#========================================================
func _panel_rects() -> Array:
	var center_x:float = SIDE_MARGIN + SIDE_WIDTH + GAP
	var top:float = TOP + _panel_shift
	return [
		Rect2(SIDE_MARGIN,top,SIDE_WIDTH,PANEL_HEIGHT),
		Rect2(center_x,top,DESIGN_WIDTH - center_x * 2.0,PANEL_HEIGHT),
		Rect2(DESIGN_WIDTH - SIDE_MARGIN - SIDE_WIDTH,top,SIDE_WIDTH,PANEL_HEIGHT),
	]


func _portrait_rect(panel:Rect2,mirrored:bool) -> Rect2:
	var x:float = panel.end.x - PAD - PORTRAIT_SIZE if mirrored else panel.position.x + PAD
	return Rect2(x,panel.position.y + PORTRAIT_TOP,PORTRAIT_SIZE,PORTRAIT_SIZE)


func _text_rect(panel:Rect2,mirrored:bool) -> Rect2:
	var portrait:Rect2 = _portrait_rect(panel,mirrored)
	var width:float = SIDE_WIDTH - PAD * 2.0 - PORTRAIT_SIZE - 14.0
	var x:float = panel.position.x + PAD if mirrored else portrait.end.x + 14.0
	return Rect2(x,portrait.position.y,width,PORTRAIT_SIZE)


## 第 index 个图标（0 = 低血量端，靠头像一侧）的位置。
func _icon_rect(panel:Rect2,mirrored:bool,row_top:float,index:int) -> Rect2:
	var area:Rect2 = _text_rect(panel,mirrored)
	var icon_size:float = ICON_SOURCE * ICON_PIXEL
	var step:float = ICON_STEP * ICON_PIXEL
	var x:float = area.end.x - icon_size - step * index if mirrored else area.position.x + step * index
	return Rect2(x,area.position.y + row_top,icon_size,icon_size)


## 按比例只画心的一部分：from_left=true 时从屏幕左侧开始占 fraction。原版心形实心部分
## 在第 1–7 列（共 7 列），比例映射到这 7 列上，0.5 正好是左右各半。
func _draw_heart_part(texture:Texture2D,rect:Rect2,fraction:float,from_left:bool,tint:Color) -> void:
	if texture == null or fraction <= 0.0:
		return
	if fraction >= 1.0:
		draw_texture_rect(texture,rect,false,tint)
		return
	var source_width:float = minf(1.0 + 7.0 * fraction,ICON_SOURCE)
	var pixel:float = rect.size.x / ICON_SOURCE
	if from_left:
		draw_texture_rect_region(texture,Rect2(rect.position,Vector2(source_width * pixel,rect.size.y)),
			Rect2(0.0,0.0,source_width,ICON_SOURCE),tint)
	else:
		draw_texture_rect_region(texture,Rect2(rect.end.x - source_width * pixel,rect.position.y,source_width * pixel,rect.size.y),
			Rect2(ICON_SOURCE - source_width,0.0,source_width,ICON_SOURCE),tint)


## flip=true 时水平翻转（右侧面板的半盔甲朝向镜像）。
func _draw_icon(texture:Texture2D,rect:Rect2,flip:bool,tint:Color) -> void:
	if texture == null:
		return
	if flip:
		draw_set_transform(Vector2(rect.end.x,rect.position.y),0.0,Vector2(-1.0,1.0))
		draw_texture_rect(texture,Rect2(Vector2.ZERO,rect.size),false,tint)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	else:
		draw_texture_rect(texture,rect,false,tint)


func _draw_hearts(panel:Rect2,side:Dictionary,mirrored:bool,tint:Color) -> void:
	var max_hp:float = maxf(float(side.max_hp),1.0)
	var hp_hearts:float = heart_amount(float(side.hp),max_hp)
	var shield_hearts:float = heart_amount(float(side.get("block",0.0)),max_hp)
	var absorb_hearts:float = heart_amount(float(side.get("absorption",0.0)),max_hp)
	# 左面板低血量端在左，右面板低血量端在右（镜像）。
	var low_from_left:bool = not mirrored
	for i:int in range(ICON_COUNT):
		var rect:Rect2 = _icon_rect(panel,mirrored,HEART_ROW_TOP,i)
		_draw_icon(HEART_CONTAINER,rect,false,tint)
		_draw_heart_part(HEART_FULL,rect,heart_fill(hp_hearts,i),low_from_left,tint)
		_draw_heart_part(_shield_full,rect,heart_fill(shield_hearts,i),low_from_left,tint)
		# 金色从高血量端排起：这颗心只从远离头像的一侧按比例染色。
		_draw_heart_part(HEART_ABSORBING_FULL,rect,heart_fill_from_high(absorb_hearts,i),not low_from_left,tint)


func _draw_armor(panel:Rect2,side:Dictionary,mirrored:bool,tint:Color) -> void:
	var units:int = armor_half_units(float(side.get("reduction",0.0)))
	if units <= 0:
		return
	for i:int in range(ICON_COUNT):
		var rect:Rect2 = _icon_rect(panel,mirrored,ARMOR_ROW_TOP,i)
		if units > i * 2 + 1:
			_draw_icon(ARMOR_FULL,rect,false,tint)
		elif units > i * 2:
			_draw_icon(ARMOR_HALF,rect,mirrored,tint)
		else:
			_draw_icon(ARMOR_EMPTY,rect,false,tint)


func _draw_patch(box:StyleBoxTexture,rect:Rect2,pixel:float) -> void:
	draw_set_transform(rect.position,0.0,Vector2.ONE * pixel)
	draw_style_box(box,Rect2(Vector2.ZERO,rect.size / pixel))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)


func _draw() -> void:
	var data = _data()
	if not is_instance_valid(data): return
	if data.sides.size()!=2:
		if bool(data.timed_mode) and not data.outro_active:
			_panel_shift=0.0
			_draw_patch(_effect_box,_panel_rects()[1],GUI_PIXEL)
		_draw_toast_graphics()
		return
	_panel_shift = _outro_panel_shift(data)
	var rects:Array = _panel_rects()
	for i:int in [0,2]:
		var panel:Rect2 = rects[i]
		# tooltip 背景四周有 8px 透明边：外扩后可见的深色区域正好对齐布局框。
		var outer:Rect2 = panel.grow(TOOLTIP_TRANSPARENT_EDGE * GUI_PIXEL)
		_draw_patch(_tooltip_background_box,outer,GUI_PIXEL)
		_draw_patch(_tooltip_frame_box,outer,GUI_PIXEL)
		_draw_side_graphics(panel,data.sides[0 if i == 0 else 1],i == 2)
	_draw_patch(_effect_box,rects[1],GUI_PIXEL)
	_draw_toast_graphics()

func _draw_toast_graphics() -> void:
	var data=_data()
	var toast:Rect2 = _toast_rect(data)
	if toast.has_area():
		draw_texture_rect(TOAST_ADVANCEMENT,toast,false)
		var winner_side:int = int(data.winner_index)
		if not data.victory_result.is_empty() or (winner_side >= 0 and winner_side < data.sides.size()):
			var texture:Texture2D = _victory_texture() if not data.victory_result.is_empty() else data.sides[winner_side].texture
			if texture != null:
				var slot:Rect2 = Rect2(toast.position + Vector2(8.0,8.0) * TOAST_PIXEL,Vector2(16.0,16.0) * TOAST_PIXEL)
				if bool(data.victory_result.get("is_team",false)):
					draw_texture_rect(ITEM_FRAME,slot,false)
					_draw_wool_cube(texture,slot.grow(-slot.size.x*0.18))
					return
				var texture_size:Vector2 = texture.get_size()
				var fitted:Vector2 = texture_size * minf(slot.size.x / maxf(texture_size.x,1.0),slot.size.y / maxf(texture_size.y,1.0))
				draw_texture_rect(texture,Rect2(slot.get_center() - fitted * 0.5,fitted),false)


func _draw_side_graphics(panel:Rect2,side:Dictionary,mirrored:bool) -> void:
	var dead:bool = bool(side.dead)
	var tint:Color = DEAD_TINT if dead else Color.WHITE
	var slot:Rect2 = _portrait_rect(panel,mirrored)
	draw_texture_rect(ITEM_FRAME,slot,false,tint)
	if bool(side.get("is_team",false)):
		# 多人队伍：与胜利 toast 相同的羊毛方块，颜色跟随队伍色。
		_draw_wool_cube(_team_wool_texture(side),slot.grow(-slot.size.x*0.18),tint)
		if not bool(_data().timed_mode): _draw_hearts(panel,side,mirrored,tint)
		_draw_armor(panel,side,mirrored,tint)
		return
	var texture:Texture2D = side.texture
	if texture != null:
		var area:Rect2 = slot.grow(-slot.size.x * 0.15)
		var texture_size:Vector2 = texture.get_size()
		var fitted:Vector2 = texture_size * minf(area.size.x / maxf(texture_size.x,1.0),area.size.y / maxf(texture_size.y,1.0))
		draw_texture_rect(texture,Rect2(area.get_center() - fitted * 0.5,fitted),false,tint)
	if not bool(_data().timed_mode): _draw_hearts(panel,side,mirrored,tint)
	_draw_armor(panel,side,mirrored,tint)


func _display_name(raw_name:String) -> String:
	var text:String = raw_name
	if locale.is_empty():
		text = Game.t(raw_name)
	elif Game.get("_localization") != null:
		text = str(Game._localization._t_for_locale(raw_name,locale,false))
	return text.replace("_"," ")


func _fit_font_size(text:String,width:float,max_size:int,min_size:int) -> int:
	var font_size:int = max_size
	while font_size > min_size and FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
		font_size -= 2
	return maxi(font_size,min_size)


func _ellipsize(text:String,width:float,font_size:int) -> String:
	if FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x <= width:
		return text
	var trimmed:String = text
	while trimmed.length() > 1 and FONT.get_string_size(trimmed + "..",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
		trimmed = trimmed.substr(0,trimmed.length() - 1)
	return trimmed + ".."


func _outlined_text(canvas:CanvasItem,left_baseline:Vector2,text:String,alignment:HorizontalAlignment,
		width:float,font_size:int,color:Color,outline:int) -> void:
	canvas.draw_string_outline(FONT,left_baseline,text,alignment,width,font_size,outline,Color(0.0,0.0,0.0,color.a))
	canvas.draw_string(FONT,left_baseline,text,alignment,width,font_size,color)


## 计时模式的对战面板只显示受伤数字本身（不带“受到伤害”字样）。
func side_value_text(side:Dictionary) -> String:
	if bool(_data().timed_mode):
		return str(roundi(float(side.get("damage",0.0))))
	return "%d / %d" % [ceili(float(side.hp)),roundi(float(side.max_hp))]


## 数值颜色：计时模式按队伍受伤排名由白到红（与头顶数字一致）；其它模式为白色生命值。
func side_value_color(side:Dictionary) -> Color:
	if bool(_data().timed_mode):
		return side.get("value_color",HP_TEXT_COLOR)
	return HP_TEXT_COLOR


func side_name_text(side:Dictionary) -> String:
	if bool(side.get("is_team",false)):
		var wool:String = _wool_for_color(side.color)
		var index:int = WOOL_NAMES.find(wool)
		return WOOL_ZH[index] + "队伍" if _toast_locale() == "zh" else wool.replace("_"," ").capitalize() + " Team"
	return _display_name(str(side.raw_name))


func _team_wool_texture(side:Dictionary) -> Texture2D:
	var wool:String = _wool_for_color(side.color)
	if not _wool_cache.has(wool): _wool_cache[wool] = load("res://Images/UI/team_victory/" + wool + "_wool.png")
	return _wool_cache[wool]
func clock_text() -> String:
	var data=_data()
	if bool(data.timed_mode):
		if bool(data.timed_overtime): return "加赛" if _toast_locale()=="zh" else "OT"
		return format_elapsed(ceilf(float(data.timed_remaining)))
	return format_elapsed(float(data.elapsed))

func _draw_clock_text(center:Rect2) -> void:
	var data=_data()
	var inner_x:float = center.position.x + 8.0
	var inner_width:float = center.size.x - 16.0
	var time_text:String = clock_text()
	var time_size:int = _fit_font_size(time_text,inner_width,TIME_TEXT_SIZE,20)
	_outlined_text(_text_layer,Vector2(inner_x,center.position.y + 62.0),time_text,HORIZONTAL_ALIGNMENT_CENTER,
		inner_width,time_size,Color("ff5555") if bool(data.timed_mode) and float(data.timed_remaining)<=5.0 else TIME_COLOR,5)
	_outlined_text(_text_layer,Vector2(inner_x,center.position.y + 146.0),"VS",HORIZONTAL_ALIGNMENT_CENTER,
		inner_width,VS_TEXT_SIZE,Color.WHITE,8)

func _draw_text() -> void:
	var data = _data()
	if not is_instance_valid(data): return
	if data.sides.size()!=2:
		if bool(data.timed_mode) and not data.outro_active:
			_panel_shift=0.0
			_draw_clock_text(_panel_rects()[1])
		_draw_toast_text()
		return
	_panel_shift = _outro_panel_shift(data)
	var rects:Array = _panel_rects()
	for i:int in [0,2]:
		var panel:Rect2 = rects[i]
		var mirrored:bool = i == 2
		var side:Dictionary = data.sides[0 if i == 0 else 1]
		var area:Rect2 = _text_rect(panel,mirrored)
		var alignment:HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
		var dead:bool = bool(side.dead)
		var name_text:String = side_name_text(side)
		var name_size:int = _fit_font_size(name_text,area.size.x,NAME_MAX_SIZE,NAME_MIN_SIZE)
		name_text = _ellipsize(name_text,area.size.x,name_size)
		var name_color:Color = side.color
		if dead:
			name_color = name_color * DEAD_TEXT_TINT
		_outlined_text(_text_layer,Vector2(area.position.x,area.position.y + NAME_BASELINE),name_text,alignment,
			area.size.x,name_size,name_color,6)
		var hp_text:String = side_value_text(side)
		var row_x:float = panel.position.x + PAD
		var row_width:float = SIDE_WIDTH - PAD * 2.0
		var hp_size:int = _fit_font_size(hp_text,row_width,HP_TEXT_SIZE,16)
		_outlined_text(_text_layer,Vector2(row_x,panel.position.y + HP_BASELINE),hp_text,alignment,
			row_width,hp_size,side_value_color(side) * (DEAD_TEXT_TINT if dead else Color.WHITE),5)
	_draw_clock_text(rects[1])
	_draw_toast_text()

func _draw_toast_text() -> void:
	var data=_data()
	var toast:Rect2 = _toast_rect(data)
	var winner_side:int = int(data.winner_index)
	if toast.has_area():
		var strings:Dictionary = TOAST_TEXT[_toast_locale()]
		var text_x:float = toast.position.x + 30.0 * TOAST_PIXEL
		var text_width:float = toast.size.x - 30.0 * TOAST_PIXEL - 8.0 * TOAST_PIXEL
		var title:String = str(strings.title) if winner_side>=0 or not data.victory_result.is_empty() else ("本局结束" if _toast_locale()=="zh" else "Round Complete")
		var title_size:int = _fit_font_size(title,text_width,36,20)
		_text_layer.draw_string(FONT,Vector2(text_x,toast.position.y + 7.0 * TOAST_PIXEL + 30.0),title,
			HORIZONTAL_ALIGNMENT_LEFT,text_width,title_size,TOAST_TITLE_COLOR)
		var body:String = victory_body_text()
		var body_size:int = _fit_font_size(body,text_width,36,18)
		body = _ellipsize(body,text_width,body_size)
		_text_layer.draw_string(FONT,Vector2(text_x,toast.position.y + 18.0 * TOAST_PIXEL + 30.0),body,
			HORIZONTAL_ALIGNMENT_LEFT,text_width,body_size,data.victory_result.get("color",TOAST_BODY_COLOR) if bool(data.victory_result.get("is_team",false)) else TOAST_BODY_COLOR)
