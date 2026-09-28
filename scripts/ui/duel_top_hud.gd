extends Control
## 1v1 顶部对战 HUD（2026-09-28）。
##
## 仅当场上恰好剩两名主角色、且分属两个阵营时显示（召唤物不算；比赛延续/死亡演出桥
## 沿用 return_battle_sides 的同一代表规则）。左右为原版 tooltip 面板：物品展示框头像、
## 角色名（与普通 VS 同色）、当前/最大生命及原版经验条血条；中间为原版药水效果背景，
## 显示本局已过去的游戏时间与 VS。原有“角色名 VS 角色名”文字标题保留不动。
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
const XP_BACKGROUND:Texture2D = preload("res://Images/UI/minecraft_xp/experience_bar_background.png")
const XP_PROGRESS:Texture2D = preload("res://Images/UI/minecraft_xp/experience_bar_progress.png")

# 以 1080 逻辑宽度设计；实际视口宽度不同时整体等比缩放。
const DESIGN_WIDTH:float = 1080.0
const TOP:float = 32.0
const SIDE_MARGIN:float = 24.0
const GAP:float = 12.0
const SIDE_WIDTH:float = 404.0
const PANEL_HEIGHT:float = 176.0
const PAD:float = 20.0
const PORTRAIT_SIZE:float = 128.0 # item_frame 32px × 4
const BAR_HEIGHT:float = 10.0 # 经验条 182×5 × 2，宽度 364 = SIDE_WIDTH - 2 × PAD
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

var world:Node
## 录制镜像才设置：指向玩家画面上的本体 HUD。
var source:Control = null
## 空字符串 = 跟随游戏当前语言；镜像为 "zh" / "en"。
var locale:String = ""
var visibility_bit:int = 2

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
			scale = source.scale
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
	position = Vector2.ZERO
	scale = Vector2.ONE * factor
	size = Vector2(DESIGN_WIDTH,TOP + PANEL_HEIGHT + 8.0)
	if is_instance_valid(_text_layer):
		_text_layer.position = Vector2.ZERO
		_text_layer.size = size


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
		if any_valid:
			side.max_hp = max_hp
		side.hp = hp
		side.dead = hp <= 0.0


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
	return Rect2(x,panel.position.y + 14.0,PORTRAIT_SIZE,PORTRAIT_SIZE)


func _text_rect(panel:Rect2,mirrored:bool) -> Rect2:
	var portrait:Rect2 = _portrait_rect(panel,mirrored)
	var width:float = SIDE_WIDTH - PAD * 2.0 - PORTRAIT_SIZE - 14.0
	var x:float = panel.position.x + PAD if mirrored else portrait.end.x + 14.0
	return Rect2(x,portrait.position.y,width,PORTRAIT_SIZE)


func _bar_rect(panel:Rect2) -> Rect2:
	var portrait:Rect2 = _portrait_rect(panel,false)
	return Rect2(panel.position.x + PAD,portrait.end.y + 12.0,SIDE_WIDTH - PAD * 2.0,BAR_HEIGHT)


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
	var bar:Rect2 = _bar_rect(panel)
	draw_texture_rect(XP_BACKGROUND,bar,false)
	var ratio:float = clampf(float(side.hp) / maxf(float(side.max_hp),1.0),0.0,1.0)
	if ratio > 0.0:
		var source_size:Vector2 = XP_PROGRESS.get_size()
		var fill_width:float = bar.size.x * ratio
		var source_width:float = source_size.x * ratio
		# 左侧从左往右填，右侧镜像从右往左填，两边都向中间扣血。
		if mirrored:
			draw_texture_rect_region(XP_PROGRESS,Rect2(bar.end.x - fill_width,bar.position.y,fill_width,bar.size.y),
				Rect2(source_size.x - source_width,0.0,source_width,source_size.y))
		else:
			draw_texture_rect_region(XP_PROGRESS,Rect2(bar.position,Vector2(fill_width,bar.size.y)),
				Rect2(0.0,0.0,source_width,source_size.y))


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
		_outlined_text(_text_layer,Vector2(area.position.x,area.position.y + 48.0),name_text,alignment,
			area.size.x,name_size,name_color,6)
		var hp_text:String = "%d / %d" % [ceili(float(side.hp)),roundi(float(side.max_hp))]
		var hp_size:int = _fit_font_size(hp_text,area.size.x,HP_TEXT_SIZE,16)
		_outlined_text(_text_layer,Vector2(area.position.x,area.position.y + 108.0),hp_text,alignment,
			area.size.x,hp_size,HP_TEXT_COLOR * (DEAD_TEXT_TINT if dead else Color.WHITE),5)
	var center:Rect2 = rects[1]
	var inner_x:float = center.position.x + 8.0
	var inner_width:float = center.size.x - 16.0
	var time_text:String = format_elapsed(float(data.elapsed))
	var time_size:int = _fit_font_size(time_text,inner_width,TIME_TEXT_SIZE,20)
	_outlined_text(_text_layer,Vector2(inner_x,center.position.y + 62.0),time_text,HORIZONTAL_ALIGNMENT_CENTER,
		inner_width,time_size,TIME_COLOR,5)
	_outlined_text(_text_layer,Vector2(inner_x,center.position.y + 146.0),"VS",HORIZONTAL_ALIGNMENT_CENTER,
		inner_width,VS_TEXT_SIZE,Color.WHITE,8)
