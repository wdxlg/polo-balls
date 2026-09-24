extends SceneTree

## Actual GPU preview: two stands placed at the edge of a clipped map Control.
## The vanilla tooltips must remain visible OUTSIDE the map's clip rectangle.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2))
	var english:bool = OS.get_cmdline_user_args().has("--english")
	root.get_node("Game").call("set_language","en" if english else "zh",false)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1000,700)
	var backdrop := ColorRect.new()
	backdrop.name = "OutsideMapBackdrop"
	backdrop.color = Color("363437")
	backdrop.z_index = -8
	backdrop.size = Vector2(1000,700)
	root.add_child(backdrop)
	var map := Control.new()
	map.name = "ClipToMapOnly"
	map.clip_contents = true
	map.position = Vector2(110,95)
	map.size = Vector2(405,510)
	root.add_child(map)
	current_scene = map
	var floor := ColorRect.new()
	floor.color = Color("29372f")
	floor.z_index = -4 # Like World tiles, below tooltip(-3) and armor stands(0).
	floor.size = map.size
	map.add_child(floor)
	var border := ColorRect.new()
	border.color = Color("788174")
	border.position = map.position + Vector2(map.size.x,-2)
	border.size = Vector2(2,map.size.y + 4)
	root.add_child(border)

	var potion:Node2D = (load("res://scenes/characters/默认/药水测试盔甲架.tscn") as PackedScene).instantiate()
	potion.position = Vector2(345,155)
	potion.process_mode = Node.PROCESS_MODE_DISABLED
	potion.set("Team","A")
	map.add_child(potion,true)
	var potion_samples:Array[MCPreviewPotionEffect] = [potion.get("potion_pool")[0],potion.get("potion_pool")[1]]
	potion.call("set_displayed_potions",potion_samples)
	var enchant:Node2D = (load("res://scenes/characters/默认/附魔测试盔甲架.tscn") as PackedScene).instantiate()
	enchant.position = Vector2(345,355)
	enchant.process_mode = Node.PROCESS_MODE_DISABLED
	enchant.set("Team","A")
	map.add_child(enchant,true)
	var enchant_samples:Array[MCPreviewEnchantment] = [enchant.get("enchantment_pool")[0]]
	enchant.call("set_displayed_enchantments","附魔书",enchant_samples)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var output:String = "user://mc_effect_tooltips/preview_en.png" if english else "user://mc_effect_tooltips/preview.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mc_effect_tooltips"))
	var saved:Error = image.save_png(output)
	var real_map_right:int = int(map.position.x + map.size.x)
	var potion_ui:MCPreviewTooltip = potion.get("preview_tooltip") as MCPreviewTooltip
	var panel_p:Control = potion_ui.get_node("VanillaTooltip")
	var panel_e:Control = enchant.get("preview_tooltip").get_node("VanillaTooltip")
	var rect_p:Rect2 = Rect2(panel_p.position,panel_p.size * panel_p.scale)
	var rect_e:Rect2 = Rect2(panel_e.position,panel_e.size * panel_e.scale)
	var regen_frame:NinePatchRect = potion_ui._potion_backgrounds[0]
	var regen_text:Label = potion_ui._potion_names[0]
	var right_padding:float = regen_frame.size.x - regen_text.position.x - potion_ui._text_width(regen_text.text,potion_ui.text_font)
	var correct_language:bool = regen_text.text == ("Regeneration" if english else "生命恢复") and potion_ui._potion_names[1].text == ("Speed II" if english else "迅捷 II")
	correct_language = correct_language and (panel_e.get_child(2) as Label).text == ("Enchanted Book" if english else "附魔书")
	correct_language = correct_language and (panel_e.get_child(3) as Label).text == ("Piercing IV" if english else "穿透 IV")
	var all_rows_fit:bool = true
	for index:int in range(potion_ui._potion_backgrounds.size()):
		var content:float = maxf(potion_ui._text_width(potion_ui._potion_names[index].text,potion_ui.text_font),potion_ui._text_width(potion_ui._time_labels[index].text,potion_ui.time_font))
		var padding:float = potion_ui._potion_backgrounds[index].size.x - potion_ui._potion_names[index].position.x - content
		all_rows_fit = all_rows_fit and padding >= 5.0 and padding <= 8.0
	var hugs_regeneration:bool = correct_language and all_rows_fit and (english or regen_frame.size.x < 120.0)
	var extends_past_map:bool = rect_p.end.x > real_map_right + 50 and rect_e.end.x > real_map_right + 25
	var right_of_actor:bool = rect_p.position.x > potion.get_global_transform_with_canvas().origin.x and rect_e.position.x > enchant.get_global_transform_with_canvas().origin.x
	# Compare actual rendered frames with and without both tooltips. Comparing to
	# the source ColorRect would mistake the project's HDR/vignette for tooltip pixels.
	potion.get("preview_tooltip").set_process(false)
	enchant.get("preview_tooltip").set_process(false)
	panel_p.hide()
	panel_e.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var without:Image = root.get_texture().get_image()
	var outside_changed:int = 0
	for y:int in range(145,535):
		for x:int in range(real_map_right + 12,mini(real_map_right + 200,image.get_width())):
			var pixel:Color = image.get_pixel(x,y)
			var baseline:Color = without.get_pixel(x,y)
			if absf(pixel.r - baseline.r) + absf(pixel.g - baseline.g) + absf(pixel.b - baseline.b) > 0.18:
				outside_changed += 1
	var clear_x:int = int(panel_p.position.x + (regen_frame.size.x + 8.0) * panel_p.scale.x)
	var clear_y:int = int(panel_p.position.y + (regen_frame.position.y + regen_frame.size.y * 0.5) * panel_p.scale.y)
	var clear_after_frame:bool = false
	if clear_x >= 0 and clear_x < image.get_width() and clear_y >= 0 and clear_y < image.get_height():
		var frame_pixel:Color = image.get_pixel(clear_x,clear_y)
		var empty_pixel:Color = without.get_pixel(clear_x,clear_y)
		clear_after_frame = absf(frame_pixel.r - empty_pixel.r) + absf(frame_pixel.g - empty_pixel.g) + absf(frame_pixel.b - empty_pixel.b) < 0.025
	print("MC_TOOLTIP_GPU locale=",("en" if english else "zh")," saved=",saved == OK," path=",ProjectSettings.globalize_path(output)," image=",image.get_size()," outside_pixels=",outside_changed," beyond_map=",extends_past_map," right_of_actor=",right_of_actor," translations_ok=",correct_language," rows_fit=",all_rows_fit," regen_row_width=",regen_frame.size.x," right_padding=",right_padding," clear_after_frame=",clear_after_frame," potion_rect=",rect_p," enchant_rect=",rect_e)
	quit(0 if saved == OK and outside_changed > 200 and extends_past_map and right_of_actor and hugs_regeneration and clear_after_frame else 1)
