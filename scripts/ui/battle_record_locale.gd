extends Node
## Mirror ONLY localized text into two visibility layers. Physics/audio/world stay shared.
const ZH_BIT:int = 1 << 17
const EN_BIT:int = 1 << 18
const HIDDEN_BIT:int = 1 << 19
var world:Node
var main:Viewport
var old_mask:int
var roots:Dictionary = {}
var screen_roots:Dictionary = {}
var sources:Dictionary = {}
var copies:Dictionary = {}
var masks:Dictionary = {}
var cache:Dictionary = {}
var fragments:Dictionary = {}
var pattern:RegEx
var markup:RegEx

func begin(scene:Node, viewport:Viewport, capture_viewports:Dictionary = {}) -> void:
	world = scene
	main = viewport
	old_mask = main.canvas_cull_mask
	main.canvas_cull_mask &= ~(ZH_BIT | EN_BIT)
	for locale:String in ["zh", "en"]:
		var root := Node2D.new()
		root.name = "RecordingText_" + locale
		root.set_meta("recording_copy", true)
		root.visibility_layer = ZH_BIT if locale == "zh" else EN_BIT
		world.add_child(root)
		roots[locale] = root
		# Unlike World2D, a CanvasLayer does not cross Viewport boundaries. Give
		# each recording its own screen-space VS layer, immune to camera movement.
		if capture_viewports.has(locale) and is_instance_valid(capture_viewports[locale]):
			var capture:SubViewport = capture_viewports[locale]
			var layer := CanvasLayer.new()
			layer.name = "RecordingVersus_" + locale
			layer.layer = 1
			layer.set_meta("recording_copy", true)
			layer.transform = Transform2D.IDENTITY.scaled(Vector2(capture.size) / main.get_visible_rect().size)
			capture.add_child(layer)
			screen_roots[locale] = layer
			# 1v1 顶部 HUD 同属玩家 Viewport 的屏幕层：给每个抓帧视口一份按语言翻译的只读镜像。
			var duel_hud:Variant = world.get("duel_top_hud")
			# 先判有效再判类型：World 拆除时 HUD 可能已释放，对已释放对象用 is 会报脚本错误。
			if is_instance_valid(duel_hud) and duel_hud is Control and duel_hud.has_method("make_mirror"):
				layer.add_child(duel_hud.make_mirror(locale, ZH_BIT if locale == "zh" else EN_BIT))
	_build_dictionary()
	_scan(world)
	get_tree().node_added.connect(_added)
	RenderingServer.frame_pre_draw.connect(sync)
	sync()

func _is_wasted(node:Node) -> bool:
	return node is Control and node.get_script() != null and node.get_script().resource_path == "res://scripts/effects/wasted_overlay.gd"

func _is_screen_source(node:Node) -> bool:
	return node == world.versus_label or node == world.armor_intro_label

func _is_source(node:Node) -> bool:
	if not (node is Label or node is RichTextLabel or _is_wasted(node)): return false
	# VS and armor introduction have independent screen-space copies.
	if _is_screen_source(node): return true
	var parent:Node = node
	while parent != null and parent != world:
		if parent is CanvasLayer or parent is Viewport or parent.has_meta("recording_copy"): return false
		if parent != node and _is_wasted(parent): return false
		parent = parent.get_parent()
	return parent == world

func _scan(node:Node) -> void:
	if node.has_meta("recording_copy") or node is Viewport: return
	if node is CanvasLayer:
		for label:Control in [world.versus_label,world.armor_intro_label]:
			if is_instance_valid(label) and label.get_parent() == node:
				sources[label.get_instance_id()] = label
		return
	if _is_source(node): sources[node.get_instance_id()] = node
	for child:Node in node.get_children(): _scan(child)

func _added(node:Node) -> void:
	if _is_source(node): sources[node.get_instance_id()] = node

func _escape(value:String) -> String:
	var escaped:String = ""
	for character:String in value:
		if character in "\\.^$|?*+()[]{}": escaped += "\\"
		escaped += character
	return escaped

func _build_dictionary() -> void:
	var localizer = Game._localization
	for locale:String in localizer._translation_table:
		for key:String in localizer._translation_table[locale]:
			fragments[key] = key
			fragments[str(localizer._translation_table[locale][key])] = key
	for key:String in localizer.RUNTIME_LABELS:
		fragments[key] = key
		for value:String in localizer.RUNTIME_LABELS[key]: fragments[value] = key
	var keys:Array = fragments.keys()
	keys.sort_custom(func(a:String,b:String): return a.length() > b.length())
	var alternatives:PackedStringArray = []
	for key:String in keys:
		if key.is_empty() or key.is_valid_float(): continue
		var escaped:String = _escape(key)
		if key[0].to_lower() >= "a" and key[0].to_lower() <= "z": escaped = "(?<![A-Za-z0-9_])" + escaped
		if key[-1].to_lower() >= "a" and key[-1].to_lower() <= "z": escaped += "(?![A-Za-z0-9_])"
		alternatives.append(escaped)
	pattern = RegEx.new()
	pattern.compile("|".join(alternatives))
	markup = RegEx.new()
	markup.compile("\\[[^\\]]*\\]")

func _plain(text:String, locale:String) -> String:
	if fragments.has(text): return Game._localization._t_for_locale(fragments[text], locale, false)
	var output:String = ""
	var start:int = 0
	for found:RegExMatch in pattern.search_all(text):
		output += text.substr(start, found.get_start() - start)
		output += Game._localization._t_for_locale(fragments[found.get_string()], locale, false)
		start = found.get_end()
	return output + text.substr(start)

func translate(text:String, locale:String, rich:bool = false) -> String:
	var key:String = locale + str(rich) + ":" + text
	if cache.has(key): return cache[key]
	var output:String = ""
	var start:int = 0
	if rich:
		for found:RegExMatch in markup.search_all(text):
			output += _plain(text.substr(start, found.get_start() - start), locale) + found.get_string()
			start = found.get_end()
	output += _plain(text.substr(start), locale)
	if cache.size() > 4096: cache.clear()
	cache[key] = output
	return output

func _make_copy(source:Control, locale:String) -> Dictionary:
	var holder := Node2D.new()
	holder.set_meta("recording_copy", true)
	holder.z_as_relative = false
	if _is_screen_source(source) and screen_roots.has(locale):
		holder.visibility_layer = ZH_BIT if locale == "zh" else EN_BIT
		screen_roots[locale].add_child(holder)
	else:
		roots[locale].add_child(holder)
	var copy:Control = source.get_script().new() if _is_wasted(source) else source.duplicate(0) as Control
	for child:Node in copy.get_children(): child.free()
	copy.set_meta("recording_copy", true)
	if not _is_wasted(source): copy.set_script(null)
	copy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.visibility_layer = 1
	copy.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	copy.position = Vector2.ZERO
	copy.scale = Vector2.ONE
	copy.rotation = 0.0
	copy.pivot_offset = Vector2.ZERO
	var clip_sources:Array = []
	var ancestor:Node = source.get_parent()
	while ancestor != world and ancestor != null:
		if ancestor is Control and ancestor.clip_contents: clip_sources.push_front(ancestor)
		ancestor = ancestor.get_parent()
	var clips:Array = []
	var parent:Node = holder
	for clip_source:Control in clip_sources:
		var anchor := Node2D.new()
		parent.add_child(anchor)
		var rect := Control.new()
		rect.clip_contents = true
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.add_child(rect)
		clips.append({"source":clip_source, "anchor":anchor, "rect":rect})
		parent = rect
	var content := Node2D.new()
	parent.add_child(content)
	content.add_child(copy)
	copy.remove_from_group(Game._localization.RUNTIME_LOCALIZATION_GROUP)
	return {"holder":holder, "text":copy, "clips":clips, "content":content}

func _style(source:Control, target:Control, localized_versus:bool = false) -> void:
	target.material = source.material
	target.self_modulate = source.self_modulate
	target.texture_filter = source.texture_filter
	var fonts:Array = ["font"] if source is Label else ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]
	var sizes:Array = ["font_size"] if source is Label else ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]
	for key:String in fonts:
		if target.get_theme_font(key) != source.get_theme_font(key): target.add_theme_font_override(key, source.get_theme_font(key))
	if not localized_versus:
		for key:String in sizes:
			if target.get_theme_font_size(key) != source.get_theme_font_size(key): target.add_theme_font_size_override(key, source.get_theme_font_size(key))
	for key:String in ["font_color", "default_color", "font_shadow_color", "font_outline_color"]:
		if source.has_theme_color(key) and target.get_theme_color(key) != source.get_theme_color(key): target.add_theme_color_override(key, source.get_theme_color(key))
	for key:String in ["outline_size", "shadow_offset_x", "shadow_offset_y", "shadow_outline_size", "line_spacing", "line_separation"]:
		if source.has_theme_constant(key) and target.get_theme_constant(key) != source.get_theme_constant(key): target.add_theme_constant_override(key, source.get_theme_constant(key))
	if source is Label:
		target.horizontal_alignment = source.horizontal_alignment
		target.vertical_alignment = source.vertical_alignment
		target.autowrap_mode = source.autowrap_mode
		target.visible_ratio = source.visible_ratio
	else:
		target.bbcode_enabled = source.bbcode_enabled
		target.autowrap_mode = source.autowrap_mode
		target.visible_ratio = source.visible_ratio

# Translated names need their own layout, not the source language's line height.
# Keep the bottom edge above the wall; extra lines grow upward, never into battle.
# Cache shaping inputs so frame_pre_draw does not reset/refit fonts every frame.
func _fit_localized_versus(source:RichTextLabel, copy:RichTextLabel, pair:Dictionary) -> void:
	var key:Array = [copy.text, source.size, world.versus_font_min_size,
		world.versus_font_max_size, world.versus_effect_margin,
		world.top_text_horizontal_padding, copy.get_theme_font("bold_font")]
	if pair.get("versus_layout_key", []) != key:
		var height:float = world.fit_rich_text_label(copy, world.versus_font_min_size,
			world.versus_font_max_size, source.size.x, world.versus_effect_margin)
		copy.size = Vector2(source.size.x, height)
		# Measure the shaped BBCode too; fallback fonts/line spacing can be taller.
		copy.size.y = maxf(height, float(copy.get_content_height()) + world.versus_effect_margin * 2.0)
		pair["versus_layout_key"] = key
		pair["versus_layout_size"] = copy.size
	copy.scale = Vector2.ONE
	copy.size = pair["versus_layout_size"]
	copy.position = Vector2(0.0, source.size.y - copy.size.y)

func sync() -> void:
	if not is_instance_valid(world): return
	for id:int in sources.keys():
		var raw:Variant = sources[id]
		if not is_instance_valid(raw) or not raw.is_inside_tree():
			_drop(id)
			continue
		var source:Control = raw
		if not source.is_node_ready(): continue
		if not source.is_visible_in_tree():
			if copies.has(id):
				for pair:Dictionary in copies[id].values(): pair.holder.hide()
			continue
		var source_text:String = source.label().text if _is_wasted(source) else source.text
		var rich:bool = source is RichTextLabel and source.bbcode_enabled
		var texts:Dictionary = {"zh":translate(source_text,"zh",rich), "en":translate(source_text,"en",rich)}
		if source == world._center_watermark_name and not world._dead_save_ui_override_active:
			texts = {"zh":"@丁某人睡觉", "en":"@Gameking"}
		if not copies.has(id) and texts.zh == source_text and texts.en == source_text and not _is_wasted(source) and not _is_screen_source(source): continue
		if not copies.has(id):
			masks[id] = source.visibility_layer
			copies[id] = {"zh":_make_copy(source,"zh"), "en":_make_copy(source,"en")}
		source.visibility_layer = HIDDEN_BIT
		var tint:Color = Color.WHITE
		var z:int = 0
		var ancestor:CanvasItem = source
		var relative_z:bool = true
		while ancestor != null:
			tint *= ancestor.modulate
			if relative_z: z += ancestor.z_index
			relative_z = relative_z and ancestor.z_as_relative
			ancestor = ancestor.get_parent() as CanvasItem
		for locale:String in ["zh", "en"]:
			var pair:Dictionary = copies[id][locale]
			var holder:Node2D = pair.holder
			var copy:Control = pair.text
			holder.visible = source.is_visible_in_tree()
			if _is_screen_source(source):
				if screen_roots.has(locale):
					# The capture layer scales logical screen coordinates to its output size.
					# Keep the title visible through FOLLOW zoom, even when the map
					# fills its header; the source controls intentional mode hiding.
					holder.transform = source.get_global_transform_with_canvas()
				else:
					# Standalone mirror clients without capture viewports keep the World2D fallback.
					holder.transform = roots[locale].get_global_transform_with_canvas().affine_inverse() * source.get_global_transform_with_canvas()
			else:
				holder.transform = roots[locale].global_transform.affine_inverse() * source.get_global_transform()
			var previous_transform:Transform2D = source.get_global_transform()
			for clip:Dictionary in pair.clips:
				var clip_transform:Transform2D = clip.source.get_global_transform()
				clip.anchor.transform = previous_transform.affine_inverse() * clip_transform
				clip.rect.size = clip.source.size
				previous_transform = clip_transform
			pair.content.transform = previous_transform.affine_inverse() * source.get_global_transform()
			holder.z_index = clampi(z, -4096, 4096)
			holder.modulate = tint
			copy.modulate = Color.WHITE
			if _is_wasted(source):
				copy.size = source.size
				copy.set_text_center(source._text_center_x)
				copy.label().text = texts[locale]
				continue
			var localized_versus:bool = source == world.versus_label and texts[locale] != source_text
			_style(source, copy, localized_versus)
			if copy.text != texts[locale]: copy.text = texts[locale]
			copy.position = Vector2.ZERO
			if source == world.armor_intro_label:
				copy.size.x = source.size.x
				var intro_height:float = world.fit_rich_text_label(copy,world.armor_intro_font_size,world.armor_intro_font_size,source.size.x,2.0)
				copy.size = Vector2(source.size.x,maxf(intro_height,float(copy.get_content_height()) + 4.0))
				continue
			if localized_versus:
				_fit_localized_versus(source as RichTextLabel, copy as RichTextLabel, pair)
				continue
			pair.erase("versus_layout_key")
			copy.size = source.size
			# Wider translations fit the same text box without shifting the battle.
			if copy is Label and copy.autowrap_mode == TextServer.AUTOWRAP_OFF:
				var needed:Vector2 = copy.get_minimum_size()
				if needed.x > source.size.x and source.size.x > 0.0:
					var factor:float = source.size.x / needed.x
					copy.scale = Vector2.ONE * factor
					copy.size = source.size / factor
				else: copy.scale = Vector2.ONE
			else: copy.scale = Vector2.ONE
	_layout_armor_screen_copies()

func _layout_armor_screen_copies() -> void:
	var intro:RichTextLabel = world.armor_intro_label
	if not is_instance_valid(intro) or not intro.is_visible_in_tree() or not copies.has(intro.get_instance_id()): return
	for locale:String in ["zh","en"]:
		if not screen_roots.has(locale): continue
		var pair:Dictionary = copies[intro.get_instance_id()][locale]
		pair.holder.position.y = maxf(24.0,world.armor_intro_screen_top_padding_px)
		# VS visibility follows its source; do not reserve or reposition a hidden matchup.

func _drop(id:int) -> void:
	var source:Variant = sources.get(id)
	if is_instance_valid(source) and masks.has(id) and source.visibility_layer == HIDDEN_BIT: source.visibility_layer = masks[id]
	if copies.has(id):
		for pair:Dictionary in copies[id].values():
			if is_instance_valid(pair.holder):
				pair.holder.hide()
				pair.holder.queue_free()
		copies.erase(id)
	masks.erase(id)
	sources.erase(id)

func finish() -> void:
	if RenderingServer.frame_pre_draw.is_connected(sync): RenderingServer.frame_pre_draw.disconnect(sync)
	if is_inside_tree() and get_tree().node_added.is_connected(_added): get_tree().node_added.disconnect(_added)
	for id:int in masks:
		var source:Variant = sources.get(id)
		if is_instance_valid(source) and source.visibility_layer == HIDDEN_BIT: source.visibility_layer = masks[id]
	if is_instance_valid(main): main.canvas_cull_mask = old_mask
	for root:Node2D in roots.values():
		if is_instance_valid(root):
			root.hide()
			root.queue_free()
	roots.clear()
	for layer:CanvasLayer in screen_roots.values():
		if is_instance_valid(layer): layer.queue_free()
	screen_roots.clear()
	copies.clear()
	masks.clear()
	sources.clear()

func _exit_tree() -> void:
	if not roots.is_empty(): finish()
