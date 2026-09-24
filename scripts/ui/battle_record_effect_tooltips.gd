extends Node
## The battle world is shared by both recording SubViewports, but a CanvasLayer
## belongs to ONE Viewport. Mirror only Minecraft tooltips into each capture,
## using its own camera and language. The originals remain on the player screen.

var viewports:Dictionary = {}
var copies:Dictionary = {} # source instance ID -> {source, version, zh, en}


func begin(chinese:SubViewport,english:SubViewport) -> void:
	viewports = {"zh":chinese,"en":english}
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.frame_pre_draw.connect(sync)
	sync()


func _copy_settings(source:MCPreviewTooltip,mirror:MCPreviewTooltip) -> void:
	for property:String in ["display_scale","right_gap","screen_margin","title_color",
		"potion_background","enchant_background","enchant_frame","potion_border",
		"enchant_background_border","enchant_frame_border","text_font","time_font","text_size"]:
		mirror.set(property,source.get(property))


func _make_copy(source:MCPreviewTooltip,locale:String) -> MCPreviewTooltip:
	var copy := MCPreviewTooltip.new()
	copy.name = "RecordedMinecraftTooltip_" + locale
	copy.target = source.target
	copy.locale_override = locale
	_copy_settings(source,copy)
	(viewports[locale] as SubViewport).add_child(copy)
	# Keep effects readable even when a recording composition (layer 100)
	# contains a header or map inset; do not clone any unrelated player HUD.
	copy.layer = 101
	# Timers belong to the original, not to an extra always-processing mirror.
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	return copy


func _apply_content(source:MCPreviewTooltip,mirror:MCPreviewTooltip) -> void:
	_copy_settings(source,mirror)
	if source._kind == &"potion":
		mirror.set_potion_entries(source._potions)
	else:
		mirror.set_enchantment_entries(source._item_title,source._enchants,source._item_title_en)


func _needs_refresh(source:MCPreviewTooltip,mirror:MCPreviewTooltip) -> bool:
	if mirror._kind != source._kind:
		return true
	if source._kind == &"potion":
		if mirror._potion_names.size() != source._potions.size():
			return true
		for index:int in range(source._potions.size()):
			if mirror._potion_names[index].text != mirror._potion_name(source._potions[index]):
				return true
		return false
	var panel:Control = mirror.get_node("VanillaTooltip") as Control
	if source._item_title.is_empty() and source._enchants.is_empty():
		return panel.get_child_count() != 0
	var expected:Array[String] = [mirror._localized(source._item_title,source._item_title_en)]
	for enchant:MCPreviewEnchantment in source._enchants:
		if enchant != null:
			expected.append(mirror._enchant_name(enchant))
	if panel.get_child_count() != expected.size() + 2:
		return true
	for index:int in range(expected.size()):
		if (panel.get_child(index + 2) as Label).text != expected[index]:
			return true
	return false


func sync() -> void:
	if viewports.is_empty() or not is_inside_tree():
		return
	var active:Dictionary = {}
	for actor:Node in get_tree().get_nodes_in_group("Ball"):
		if not actor is Node2D:
			continue
		var source:MCPreviewTooltip = actor.get_node_or_null("Minecraft信息框") as MCPreviewTooltip
		if source == null or not source.is_inside_tree() or source.target != actor:
			continue
		var id:int = source.get_instance_id()
		active[id] = true
		if not copies.has(id):
			copies[id] = {"source":source,"version":-1,
				"zh":_make_copy(source,"zh"),"en":_make_copy(source,"en")}
		var item:Dictionary = copies[id]
		for locale:String in ["zh","en"]:
			var mirror:MCPreviewTooltip = item[locale] as MCPreviewTooltip
			if not is_instance_valid(mirror):
				continue
			if int(item.version) != source.content_version:
				_apply_content(source,mirror)
			elif _needs_refresh(source,mirror):
				mirror._rebuild(true)
			if source._kind == &"potion":
				var changed:bool = false
				for index:int in range(mini(mirror._time_labels.size(),source._time_labels.size())):
					mirror._remaining_seconds[index] = source._remaining_seconds[index]
					var time:String = source._time_labels[index].text
					if mirror._time_labels[index].text != time:
						mirror._time_labels[index].text = time
						changed = true
				if changed:
					mirror._refresh_potion_widths()
			mirror.visible = source.visible
			mirror._process(0.0)
		item.version = source.content_version
	for id:int in copies.keys():
		if not active.has(id):
			_drop(id)


func _drop(id:int) -> void:
	var item:Dictionary = copies[id]
	for locale:String in ["zh","en"]:
		var copy:MCPreviewTooltip = item[locale] as MCPreviewTooltip
		if is_instance_valid(copy):
			copy.hide()
			copy.queue_free()
	copies.erase(id)


func finish() -> void:
	if RenderingServer.frame_pre_draw.is_connected(sync):
		RenderingServer.frame_pre_draw.disconnect(sync)
	for id:int in copies.keys():
		_drop(id)
	viewports.clear()


func _exit_tree() -> void:
	finish()
