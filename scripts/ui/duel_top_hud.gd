extends Control
## 1v1 顶部对战 HUD（2026-09-28）。
##
## 仅当场上恰好剩两名主角色、且分属两个阵营时显示（召唤物不算；比赛延续/死亡演出桥
## 沿用 return_battle_sides 的同一代表规则）。左右为原版 tooltip 面板：物品展示框头像、
## 角色名（与普通 VS 同色）、10 颗原版红心、盔甲值行（仅减伤 > 0 时）及当前/最大生命数字；
## 中间为原版药水效果背景，显示本局已过去的游戏时间与 VS。原有文字 VS 标题保留不动。
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
## 两侧快照：{side_key, raw_name, color, texture, nodes, hp, max_hp, dead}
var sides:Array = []

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
	if _scan_elapsed >= SCAN_INTERVAL:
		_scan_elapsed = 0.0
		_refresh_pair()
	_refresh_values()
	_apply_layout()
	var shown_now:bool = _should_show()
	if visible != shown_now:
		visible = shown_now
	if visible:
		queue_redraw()
		_text_layer.queue_redraw()


func _should_show() -> bool:
	if sides.size() != 2:
		return false
	if bool(world.get("_dead_save_ui_override_active")):
		return false
	if bool(world.get("_armor_stand_test_hud_active")):
		return false
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
	sides = []
	_pair_signature = ""


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
	var collected:Dictionary = _collect_battle_sides()
	var order:Array = collected.order
	var entries:Dictionary = collected.entries
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
			"hp":0.0,
			"max_hp":1.0,
			"block":0.0,
			"absorption":0.0,
			"reduction":0.0,
			"dead":false,
		})
	sides = built
	_refresh_values()


func _resolve_portrait(raw_name:String,node:Node) -> Texture2D:
	# 变形者等身份名与场景不同的角色，按身份名查场景，与轮换头像框一致。
	var scene_path:String = ""
	if is_instance_valid(node) and node.scene_file_path.get_file().get_basename() == raw_name:
		scene_path = node.scene_file_path
	return _portraits.resolve(world,{"char":raw_name,"scene_path":scene_path})


func _refresh_values() -> void:
	for side:Dictionary in sides:
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
	return [
		Rect2(SIDE_MARGIN,TOP,SIDE_WIDTH,PANEL_HEIGHT),
		Rect2(center_x,TOP,DESIGN_WIDTH - center_x * 2.0,PANEL_HEIGHT),
		Rect2(DESIGN_WIDTH - SIDE_MARGIN - SIDE_WIDTH,TOP,SIDE_WIDTH,PANEL_HEIGHT),
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
	if not is_instance_valid(data) or data.sides.size() != 2:
		return
	var rects:Array = _panel_rects()
	for i:int in [0,2]:
		var panel:Rect2 = rects[i]
		# tooltip 背景四周有 8px 透明边：外扩后可见的深色区域正好对齐布局框。
		var outer:Rect2 = panel.grow(TOOLTIP_TRANSPARENT_EDGE * GUI_PIXEL)
		_draw_patch(_tooltip_background_box,outer,GUI_PIXEL)
		_draw_patch(_tooltip_frame_box,outer,GUI_PIXEL)
		_draw_side_graphics(panel,data.sides[0 if i == 0 else 1],i == 2)
	_draw_patch(_effect_box,rects[1],GUI_PIXEL)


func _draw_side_graphics(panel:Rect2,side:Dictionary,mirrored:bool) -> void:
	var dead:bool = bool(side.dead)
	var tint:Color = DEAD_TINT if dead else Color.WHITE
	var slot:Rect2 = _portrait_rect(panel,mirrored)
	draw_texture_rect(ITEM_FRAME,slot,false,tint)
	var texture:Texture2D = side.texture
	if texture != null:
		var area:Rect2 = slot.grow(-slot.size.x * 0.15)
		var texture_size:Vector2 = texture.get_size()
		var fitted:Vector2 = texture_size * minf(area.size.x / maxf(texture_size.x,1.0),area.size.y / maxf(texture_size.y,1.0))
		draw_texture_rect(texture,Rect2(area.get_center() - fitted * 0.5,fitted),false,tint)
	_draw_hearts(panel,side,mirrored,tint)
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


func _draw_text() -> void:
	var data = _data()
	if not is_instance_valid(data) or data.sides.size() != 2:
		return
	var rects:Array = _panel_rects()
	for i:int in [0,2]:
		var panel:Rect2 = rects[i]
		var mirrored:bool = i == 2
		var side:Dictionary = data.sides[0 if i == 0 else 1]
		var area:Rect2 = _text_rect(panel,mirrored)
		var alignment:HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
		var dead:bool = bool(side.dead)
		var name_text:String = _display_name(str(side.raw_name))
		var name_size:int = _fit_font_size(name_text,area.size.x,NAME_MAX_SIZE,NAME_MIN_SIZE)
		name_text = _ellipsize(name_text,area.size.x,name_size)
		var name_color:Color = side.color
		if dead:
			name_color = name_color * DEAD_TEXT_TINT
		_outlined_text(_text_layer,Vector2(area.position.x,area.position.y + NAME_BASELINE),name_text,alignment,
			area.size.x,name_size,name_color,6)
		var hp_text:String = "%d / %d" % [ceili(float(side.hp)),roundi(float(side.max_hp))]
		var row_x:float = panel.position.x + PAD
		var row_width:float = SIDE_WIDTH - PAD * 2.0
		var hp_size:int = _fit_font_size(hp_text,row_width,HP_TEXT_SIZE,16)
		_outlined_text(_text_layer,Vector2(row_x,panel.position.y + HP_BASELINE),hp_text,alignment,
			row_width,hp_size,HP_TEXT_COLOR * (DEAD_TEXT_TINT if dead else Color.WHITE),5)
	var center:Rect2 = rects[1]
	var inner_x:float = center.position.x + 8.0
	var inner_width:float = center.size.x - 16.0
	var time_text:String = format_elapsed(float(data.elapsed))
	var time_size:int = _fit_font_size(time_text,inner_width,TIME_TEXT_SIZE,20)
	_outlined_text(_text_layer,Vector2(inner_x,center.position.y + 62.0),time_text,HORIZONTAL_ALIGNMENT_CENTER,
		inner_width,time_size,TIME_COLOR,5)
	_outlined_text(_text_layer,Vector2(inner_x,center.position.y + 146.0),"VS",HORIZONTAL_ALIGNMENT_CENTER,
		inner_width,VS_TEXT_SIZE,Color.WHITE,8)
