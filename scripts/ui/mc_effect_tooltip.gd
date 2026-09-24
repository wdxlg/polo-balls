class_name MCPreviewTooltip
extends CanvasLayer

## Vanilla sprites with their original nine-slice margins. The CanvasLayer stays in
## screen space, independent of map tiles, camera zoom and world clipping.
const EFFECT_BACKGROUND:Texture2D = preload("res://Images/UI/minecraft_tooltips/effect_background_large.png")
const TOOLTIP_BACKGROUND:Texture2D = preload("res://Images/UI/minecraft_tooltips/tooltip_background.png")
const TOOLTIP_FRAME:Texture2D = preload("res://Images/UI/minecraft_tooltips/tooltip_frame.png")
const PIXEL_FONT:Font = preload("res://fonts/BoutiqueBitmap9x9_1.92.ttf")
const NUMBER_FONT:Font = preload("res://fonts/Mojangles.ttf")
const FONT_SIZE:int = 10
const ICON_SIZE:float = 18.0
const POTION_TEXT_X:float = 27.0
const POTION_RIGHT_PADDING:float = 6.0
const POTION_MIN_WIDTH:float = 40.0

var target:Node2D
var display_scale:float = 3.0
var right_gap:float = 8.0
var screen_margin:float = 8.0
var title_color:Color = Color("ffff55")
var potion_background:Texture2D = EFFECT_BACKGROUND
var enchant_background:Texture2D = TOOLTIP_BACKGROUND
var enchant_frame:Texture2D = TOOLTIP_FRAME
var potion_border:int = 5
var enchant_background_border:int = 9
var enchant_frame_border:int = 10
var text_font:Font = PIXEL_FONT
var time_font:Font = NUMBER_FONT
var text_size:int = FONT_SIZE

var _panel:Control
var _game:Node
var _kind:StringName = &"potion"
var _potions:Array[MCPreviewPotionEffect] = []
var _enchants:Array[MCPreviewEnchantment] = []
var _item_title:String = "附魔书"
var _item_title_en:String = ""
var _potion_backgrounds:Array[NinePatchRect] = []
var _potion_names:Array[Label] = []
var _time_labels:Array[Label] = []
var _remaining_seconds:Array[int] = []
var _elapsed:float = 0.0


func _ready() -> void:
	layer = 2 # Above the map, but below modal HUD layers.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.name = "VanillaTooltip"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_panel)
	_panel.hide()
	# Resolve the autoload at runtime: this class_name script is also parsed by
	# SceneTree test runners before autoload singletons are registered.
	_game = get_node_or_null("/root/Game")
	if _game != null and _game.has_signal("language_changed"):
		_game.connect("language_changed",_on_language_changed)


func set_potion_entries(entries:Array[MCPreviewPotionEffect]) -> void:
	_kind = &"potion"
	_potions = entries.duplicate()
	_elapsed = 0.0
	_rebuild()


func set_enchantment_entries(item_name:String, entries:Array[MCPreviewEnchantment], english_item_name:String = "") -> void:
	_kind = &"enchantment"
	_item_title = item_name
	_item_title_en = english_item_name
	_enchants = entries.duplicate()
	_rebuild()


func _on_language_changed(_locale:String) -> void:
	# Keep ticking the existing effects instead of restarting their timers when
	# labels and text-measured nine-slice frames are rebuilt for the new language.
	_rebuild(true)


func _process(delta:float) -> void:
	if _panel == null or not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree():
		if _panel != null:
			_panel.hide()
		return
	# Keep this display independent of ball.gd's compile-time dependencies: it can
	# also be reused by other Node2D previews and SceneTree test scripts.
	var health_value:Variant = target.get("health")
	if target.is_queued_for_deletion() or (health_value is int or health_value is float) and float(health_value) <= 0.0:
		_panel.hide()
		return
	if _kind == &"potion" and not _time_labels.is_empty() and not get_tree().paused:
		_elapsed += maxf(delta,0.0)
		var time_changed:bool = false
		while _elapsed >= 1.0:
			_elapsed -= 1.0
			for index:int in range(_remaining_seconds.size()):
				_remaining_seconds[index] = maxi(_remaining_seconds[index] - 1,0)
				var effect:MCPreviewPotionEffect = _potions[index]
				if effect != null and effect.duration_text_override.is_empty():
					var updated:String = _duration(_remaining_seconds[index])
					if _time_labels[index].text != updated:
						_time_labels[index].text = updated
						time_changed = true
		if time_changed:
			_refresh_potion_widths()
	_update_position()


func _clear_panel() -> void:
	if _panel == null:
		return
	for child:Node in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	_potion_backgrounds.clear()
	_potion_names.clear()
	_time_labels.clear()
	_remaining_seconds.clear()
	_panel.size = Vector2.ZERO
	_panel.hide()


func _rebuild(preserve_timers:bool = false) -> void:
	if _panel == null:
		return
	var prior_seconds:Array[int] = []
	if preserve_timers:
		prior_seconds = _remaining_seconds.duplicate()
	_clear_panel()
	_panel.scale = Vector2.ONE * maxf(display_scale,0.5)
	if _kind == &"potion":
		_build_potions()
		for index:int in range(mini(prior_seconds.size(),_remaining_seconds.size())):
			_remaining_seconds[index] = prior_seconds[index]
			if _potions[index].duration_text_override.is_empty():
				_time_labels[index].text = _duration(prior_seconds[index])
		if not prior_seconds.is_empty():
			_refresh_potion_widths()
	else:
		_build_enchantments()
	_update_position()


func _max_logical_width() -> float:
	var viewport_width:float = get_viewport().get_visible_rect().size.x
	return maxf(40.0,(viewport_width - screen_margin * 2.0) / maxf(display_scale,0.5))


func _text_width(value:String,font:Font) -> float:
	return font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x


func _localized(source:String,english_name:String) -> String:
	if _game != null and str(_game.get("current_locale")).begins_with("en"):
		return english_name if not english_name.is_empty() else str(_game.call("t",source))
	return source


func _potion_row_width(name:String,time:String) -> float:
	# The vanilla source is 120px wide, but it is a nine-slice, not a minimum
	# size: every effect's visible frame ends just after its longer text line.
	var content_width:float = maxf(_text_width(name,text_font),_text_width(time,time_font))
	return minf(maxf(POTION_MIN_WIDTH,ceilf(POTION_TEXT_X + content_width + POTION_RIGHT_PADDING)),_max_logical_width())


func _text_height(value:String,font:Font,width:float) -> float:
	return maxf(font.get_height(text_size),font.get_multiline_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,width,text_size).y)


func _make_patch(texture:Texture2D,border:int,size_value:Vector2) -> NinePatchRect:
	var patch := NinePatchRect.new()
	patch.texture = texture
	patch.set_patch_margin(SIDE_LEFT,border)
	patch.set_patch_margin(SIDE_TOP,border)
	patch.set_patch_margin(SIDE_RIGHT,border)
	patch.set_patch_margin(SIDE_BOTTOM,border)
	patch.size = size_value
	patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(patch)
	return patch


func _make_label(value:String,color:Color,font:Font,rect:Rect2) -> Label:
	var label := Label.new()
	label.text = value
	# These strings use the battle language, which can differ from the UI locale
	# when "in-game translation only" is enabled. Never auto-translate them again.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",text_size)
	label.add_theme_color_override("font_color",color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = rect.position
	label.size = rect.size
	_panel.add_child(label)
	return label


func _build_potions() -> void:
	var displayed:Array[MCPreviewPotionEffect] = []
	for effect:MCPreviewPotionEffect in _potions:
		if effect != null:
			displayed.append(effect)
	_potions = displayed
	if displayed.is_empty():
		return
	var widest_row:float = 0.0
	var y:float = 0.0
	for effect:MCPreviewPotionEffect in displayed:
		var name:String = _potion_name(effect)
		var time:String = _duration_for(effect)
		var row_width:float = _potion_row_width(name,time)
		var text_width:float = maxf(8.0,row_width - POTION_TEXT_X - POTION_RIGHT_PADDING)
		var title_height:float = _text_height(name,text_font,text_width)
		var timer_height:float = _text_height(time,time_font,text_width)
		var row_height:float = maxf(32.0,ceilf(5.0 + title_height + timer_height + 3.0))
		var background:NinePatchRect = _make_patch(potion_background,potion_border,Vector2(row_width,row_height))
		background.position.y = y
		_potion_backgrounds.append(background)
		if effect.icon != null:
			var image := TextureRect.new()
			image.texture = effect.icon
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			image.position = Vector2(6.0,y + floorf((row_height - ICON_SIZE) / 2.0))
			image.size = Vector2.ONE * ICON_SIZE
			_panel.add_child(image)
		var name_label:Label = _make_label(name,effect.name_color,text_font,Rect2(POTION_TEXT_X,y + 2.0,text_width,title_height + 1.0))
		_potion_names.append(name_label)
		var time_label:Label = _make_label(time,effect.duration_color,time_font,Rect2(POTION_TEXT_X,y + 3.0 + title_height,text_width,timer_height + 1.0))
		_time_labels.append(time_label)
		_remaining_seconds.append(maxi(effect.duration_seconds,0))
		widest_row = maxf(widest_row,row_width)
		y += row_height + 2.0
	_panel.size = Vector2(widest_row,y - 2.0)


func _refresh_potion_widths() -> void:
	var widest_row:float = 0.0
	for index:int in range(_potion_backgrounds.size()):
		var row_width:float = _potion_row_width(_potion_names[index].text,_time_labels[index].text)
		_potion_backgrounds[index].size.x = row_width
		var text_width:float = maxf(8.0,row_width - POTION_TEXT_X - POTION_RIGHT_PADDING)
		_potion_names[index].size.x = text_width
		_time_labels[index].size.x = text_width
		widest_row = maxf(widest_row,row_width)
	_panel.size.x = widest_row


func _build_enchantments() -> void:
	if _item_title.is_empty() and _enchants.is_empty():
		return
	# Vanilla's 100x100 tooltip sprites have transparent 9px margins OUTSIDE
	# the visible frame. Reserve those margins as well as the 5px text insets;
	# simply fitting text to the NinePatchRect size leaves it outside the border.
	const TEXT_INSET:float = 14.0
	const TEXT_TOP:float = 13.0
	var labels:Array[String] = [_localized(_item_title,_item_title_en)]
	var colors:Array[Color] = [title_color]
	for enchant:MCPreviewEnchantment in _enchants:
		if enchant == null:
			continue
		labels.append(_enchant_name(enchant))
		colors.append(enchant.text_color)
	var longest:float = 0.0
	for value:String in labels:
		longest = maxf(longest,_text_width(value,text_font))
	var width:float = minf(maxf(40.0,ceilf(longest + TEXT_INSET * 2.0)),_max_logical_width())
	var available:float = maxf(8.0,width - TEXT_INSET * 2.0)
	var heights:Array[float] = []
	var height:float = TEXT_TOP
	for value:String in labels:
		var line_height:float = ceilf(_text_height(value,text_font,available))
		heights.append(line_height)
		height += line_height + 1.0
	height = maxf(40.0,height + TEXT_TOP)
	_panel.size = Vector2(width,height)
	_make_patch(enchant_background,enchant_background_border,_panel.size)
	_make_patch(enchant_frame,enchant_frame_border,_panel.size)
	var y:float = TEXT_TOP
	for index:int in range(labels.size()):
		_make_label(labels[index],colors[index],text_font,Rect2(TEXT_INSET,y,available,heights[index] + 1.0))
		y += heights[index] + 1.0


func _update_position() -> void:
	if _panel == null or _panel.size == Vector2.ZERO or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var bounds:Rect2 = Rect2(target.get_global_transform_with_canvas().origin - Vector2(1.0,1.0),Vector2(2.0,2.0))
	var image:Sprite2D = target.get_node_or_null("Graphics/Image") as Sprite2D
	if image != null:
		bounds = (image.get_global_transform_with_canvas() * image.get_rect()).abs()
	var visible_rect:Rect2 = get_viewport().get_visible_rect()
	if not bounds.intersects(visible_rect,true):
		_panel.hide()
		return
	# When a custom list is taller than the physical viewport, fit the WHOLE
	# frame rather than clipping rows outside the window. Normal 2-4 row samples
	# keep the native integer pixel scale from the stand's editor properties.
	var available_size:Vector2 = (visible_rect.size - Vector2.ONE * screen_margin * 2.0).max(Vector2.ONE)
	var fitted_scale:float = minf(display_scale,minf(available_size.x / maxf(_panel.size.x,1.0),available_size.y / maxf(_panel.size.y,1.0)))
	_panel.scale = Vector2.ONE * maxf(fitted_scale,0.01)
	var scaled_size:Vector2 = _panel.size * _panel.scale
	var desired:Vector2 = Vector2(bounds.end.x + right_gap,bounds.get_center().y - scaled_size.y * 0.5)
	var inside:Vector2 = visible_rect.position + Vector2.ONE * screen_margin
	var far_edge:Vector2 = visible_rect.end - scaled_size - Vector2.ONE * screen_margin
	_panel.position = Vector2(
		clampf(desired.x,inside.x,maxf(inside.x,far_edge.x)),
		clampf(desired.y,inside.y,maxf(inside.y,far_edge.y))
	).round()
	_panel.show()


static func _roman(level:int) -> String:
	if level <= 0:
		return ""
	if level > 3999:
		return str(level)
	var numbers:Array[int] = [1000,900,500,400,100,90,50,40,10,9,5,4,1]
	var numerals:Array[String] = ["M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I"]
	var result:String = ""
	var remaining:int = level
	for index:int in range(numbers.size()):
		while remaining >= numbers[index]:
			result += numerals[index]
			remaining -= numbers[index]
	return result


static func _duration(seconds:int) -> String:
	var time_value:int = maxi(seconds,0)
	if time_value >= 3600:
		return "%d:%02d:%02d" % [time_value / 3600,(time_value / 60) % 60,time_value % 60]
	return "%02d:%02d" % [time_value / 60,time_value % 60]


func _duration_for(effect:MCPreviewPotionEffect) -> String:
	return effect.duration_text_override if not effect.duration_text_override.is_empty() else _duration(effect.duration_seconds)


func _potion_name(effect:MCPreviewPotionEffect) -> String:
	var suffix:String = effect.level_text_override if not effect.level_text_override.is_empty() else (_roman(effect.level) if effect.level > 1 else "")
	var name:String = _localized(effect.effect_name,effect.english_name)
	return name if suffix.is_empty() else name + " " + suffix


func _enchant_name(enchant:MCPreviewEnchantment) -> String:
	var suffix:String = enchant.level_text_override if not enchant.level_text_override.is_empty() else _roman(enchant.level)
	var name:String = _localized(enchant.enchantment_name,enchant.english_name)
	return name if suffix.is_empty() else name + " " + suffix
