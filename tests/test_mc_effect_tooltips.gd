extends SceneTree

const POTION_PATH:String = "res://scenes/characters/默认/药水测试盔甲架.tscn"
const ENCHANT_PATH:String = "res://scenes/characters/默认/附魔测试盔甲架.tscn"

var total:int = 0
var failed:int = 0
var arena:Node2D


func _initialize() -> void:
	call_deferred("_run")


func check(condition:bool,description:String) -> void:
	total += 1
	if not condition:
		failed += 1
		push_error("MC_TOOLTIP_FAIL: " + description)


func _spawn(scene:PackedScene,position:Vector2) -> Node2D:
	var stand:Node2D = scene.instantiate()
	stand.position = position
	stand.process_mode = Node.PROCESS_MODE_DISABLED
	stand.set("Team","A")
	arena.add_child(stand,true)
	return stand


func _run() -> void:
	create_timer(50).timeout.connect(func() -> void: quit(2))
	# Use the Chinese baseline even when the player last saved English settings.
	root.get_node("Game").call("set_language","zh",false)
	arena = Node2D.new()
	arena.name = "MCTooltipTestArena"
	root.add_child(arena)
	current_scene = arena
	var potion_scene:PackedScene = load(POTION_PATH) as PackedScene
	var enchant_scene:PackedScene = load(ENCHANT_PATH) as PackedScene
	check(potion_scene != null and enchant_scene != null,"both default-category scenes can be loaded")
	if potion_scene == null or enchant_scene == null:
		quit(2)
		return
	var registry:Node = (load("res://scripts/world.gd") as GDScript).new()
	registry.call("_ensure_character_path_index")
	var folders:Dictionary = registry.get("_character_paths_by_folder")
	var defaults:Dictionary = folders.get("默认",{})
	check(defaults.has("药水测试盔甲架") and defaults.has("附魔测试盔甲架"),"both scenes appear in the game's default character picker")
	registry.free()
	var fixed:Node2D = potion_scene.instantiate()
	fixed.process_mode = Node.PROCESS_MODE_DISABLED
	fixed.set("Team","A")
	fixed.set("randomize_on_spawn",false)
	arena.add_child(fixed,true)
	var fixed_pool:Array[Resource] = fixed.get("potion_pool")
	var fixed_entries:Array[MCPreviewPotionEffect] = fixed.get("displayed_potions")
	check(fixed_entries.size() == fixed_pool.size(),"switching off sampling displays the full editable potion pool")
	fixed.queue_free()
	var potion:Node2D = _spawn(potion_scene,Vector2(200,440))
	var enchant:Node2D = _spawn(enchant_scene,Vector2(200,760))
	await process_frame
	var potion_ui:MCPreviewTooltip = potion.get("preview_tooltip") as MCPreviewTooltip
	var enchant_ui:MCPreviewTooltip = enchant.get("preview_tooltip") as MCPreviewTooltip
	check(potion_ui != null and enchant_ui != null,"both stands create screen-space tooltips")
	if potion_ui == null or enchant_ui == null:
		quit(2)
		return
	check(potion_ui.get_parent() == potion and enchant_ui.get_parent() == enchant,"tooltips are freed with their owners")
	check(potion_ui.top_level and enchant_ui.top_level and not potion_ui.z_as_relative and not enchant_ui.z_as_relative and potion_ui.z_index == MCPreviewTooltip.TOOLTIP_Z and enchant_ui.z_index == MCPreviewTooltip.TOOLTIP_Z,"both frames draw between map ground and foreground world entities")
	check(float(potion.get("Speed")) > 0.0 and float(enchant.get("Speed")) > 0.0,"both armor stands retain movement")
	check(not bool(potion.get("Has_Collision_Damage")) and not bool(enchant.get("Can_Attack")),"preview stands never deal combat damage")
	var potion_entries:Array[MCPreviewPotionEffect] = potion.get("displayed_potions")
	var enchant_entries:Array[MCPreviewEnchantment] = enchant.get("displayed_enchantments")
	check(potion_entries.size() >= 2 and potion_entries.size() <= 4,"potion stand samples two to four effects")
	check(enchant_entries.size() >= 2 and enchant_entries.size() <= 4,"enchantment stand samples two to four lines")
	var unique_potions:Dictionary = {}
	for effect:MCPreviewPotionEffect in potion_entries:
		unique_potions[effect.effect_name] = true
		check(effect.icon != null,"each sampled potion has a real icon")
	check(unique_potions.size() == potion_entries.size(),"potion samples do not repeat")
	var unique_enchants:Dictionary = {}
	for effect:MCPreviewEnchantment in enchant_entries:
		unique_enchants[effect.enchantment_name] = true
	check(unique_enchants.size() == enchant_entries.size(),"enchantment samples do not repeat")
	var potion_panel:Control = potion_ui.get_node("VanillaTooltip") as Control
	var enchant_panel:Control = enchant_ui.get_node("VanillaTooltip") as Control
	check(potion_ui.potion_background.get_size() == Vector2(120,32),"potion source is Mojang's 120x32 effect background")
	check(enchant_ui.enchant_background.get_size() == Vector2(100,100),"tooltip source is Mojang's 100x100 nine-slice background")
	check((potion_panel.get_child(0) as NinePatchRect).texture == potion_ui.potion_background,"effect rows use the original background sprite")
	check((enchant_panel.get_child(1) as NinePatchRect).texture == enchant_ui.enchant_frame,"enchantment tooltip uses the original purple frame sprite")
	check(MCPreviewTooltip._roman(4) == "IV" and MCPreviewTooltip._roman(50) == "L","Roman levels display correctly")
	check(MCPreviewTooltip._duration(64) == "01:04" and MCPreviewTooltip._duration(3670) == "1:01:10","effect durations format correctly")
	check(enchant_ui._item_title == "附魔书" and enchant_ui.title_color == Color("ffff55"),"yellow title precedes enchantment lines")
	# The 120px-wide vanilla image is nine-sliced, not a minimum width. Each
	# potion row must wrap its own longer line (name or time), not the widest row.
	var source_effects:Array[Resource] = potion.get("potion_pool")
	var short_effect := MCPreviewPotionEffect.new()
	short_effect.effect_name = "短"
	short_effect.duration_text_override = "0:01"
	var two_entries:Array[MCPreviewPotionEffect] = [source_effects[0] as MCPreviewPotionEffect,short_effect]
	potion.call("set_displayed_potions",two_entries)
	var regen_frame:NinePatchRect = potion_ui._potion_backgrounds[0]
	var short_frame:NinePatchRect = potion_ui._potion_backgrounds[1]
	var regen_text_width:float = potion_ui._text_width(potion_ui._potion_names[0].text,potion_ui.text_font)
	var regen_time_width:float = potion_ui._text_width(potion_ui._time_labels[0].text,potion_ui.time_font)
	var regen_right_gap:float = regen_frame.size.x - potion_ui._potion_names[0].position.x - regen_text_width
	var regen_width:float = regen_frame.size.x
	check(potion_ui._potion_names[0].text == "生命恢复" and regen_text_width >= regen_time_width,"regeneration title is the widest content of its row")
	check(regen_frame.size.x < 120.0 and regen_right_gap >= 5.0 and regen_right_gap <= 8.0,"vanilla frame ends just after regeneration text, without a fixed 120px width")
	check(short_frame.size.x < regen_frame.size.x and potion_panel.size.x == regen_frame.size.x,"shorter effect uses its own narrower background while the panel tracks the longest row")
	var short_content_width:float = maxf(potion_ui._text_width(potion_ui._potion_names[1].text,potion_ui.text_font),potion_ui._text_width(potion_ui._time_labels[1].text,potion_ui.time_font))
	var short_right_gap:float = short_frame.size.x - potion_ui._potion_names[1].position.x - short_content_width
	check(short_right_gap >= 5.0 and short_right_gap <= 8.0,"short potion row leaves only a small right inset after its longest line")
	short_effect.duration_text_override = "00:00:00:00:00"
	potion.call("set_displayed_potions",two_entries)
	check(potion_ui._potion_backgrounds[1].size.x > regen_width and potion_panel.size.x == potion_ui._potion_backgrounds[1].size.x,"a longer custom time expands only its own row and panel")
	var clock_effect := MCPreviewPotionEffect.new()
	clock_effect.effect_name = "短"
	clock_effect.duration_seconds = 3600
	var clock_entries:Array[MCPreviewPotionEffect] = [clock_effect]
	potion.call("set_displayed_potions",clock_entries)
	var hour_width:float = potion_ui._potion_backgrounds[0].size.x
	potion_ui._process(1.0)
	check(potion_ui._time_labels[0].text == "59:59" and potion_ui._potion_backgrounds[0].size.x < hour_width and potion_panel.size.x == potion_ui._potion_backgrounds[0].size.x,"shorter countdown shrinks both the row and panel in place")
	potion.call("set_displayed_potions",two_entries)
	# Placing a stand near a map edge must not clip a popup into the map surface.
	# This test also checks the popup follows a moving owner in screen coordinates.
	potion_ui._process(0.0)
	var first_x:float = potion_panel.position.x
	check(first_x > potion.global_position.x,"potion popup starts on the actor's right")
	potion.position.x += 150.0
	potion_ui._process(0.0)
	check(potion_panel.position.x > first_x + 140.0,"popup tracks the moving stand")
	potion.position.x = get_root().get_visible_rect().size.x - 35.0
	potion_ui._process(0.0)
	check(potion_panel.position.x + potion_panel.size.x * potion_panel.scale.x <= get_root().get_visible_rect().end.x - potion_ui.screen_margin + 0.01,"entire popup stays on-screen at the right edge")
	check(potion_ui.get_parent() is Node2D and potion_ui.top_level and potion_ui.get_viewport() == root,"top-level world frame ignores its actor's map clipping")
	var original_size:Vector2 = potion_panel.size
	var custom_effect := MCPreviewPotionEffect.new()
	custom_effect.effect_name = "一条足够长、可自己编辑名字图标等级时间的药水效果"
	custom_effect.icon = load("res://Images/UI/minecraft_tooltips/mob_effect/regeneration.png") as Texture2D
	custom_effect.level = 5
	custom_effect.duration_seconds = 3670
	var custom_potions:Array[MCPreviewPotionEffect] = [custom_effect]
	potion.call("set_displayed_potions",custom_potions)
	check(potion_panel.size.x > original_size.x,"long customized potion text grows the entire vanilla background")
	check((potion_panel.get_child(0) as NinePatchRect).size.x == potion_panel.size.x,"nine-slice frame covers all potion content")
	check(potion_ui._time_labels[0].text == "1:01:10","runtime custom duration is rendered")
	potion_ui._process(1.0)
	check(potion_ui._time_labels[0].text == "1:01:09","duration visually counts down")
	var original_enchant:Vector2 = enchant_panel.size
	var custom_line := MCPreviewEnchantment.new()
	custom_line.enchantment_name = "一条可以任意编辑的很长的附魔描述"
	custom_line.level = 4
	var custom_enchants:Array[MCPreviewEnchantment] = []
	for index:int in range(enchant_entries.size() + 2):
		custom_enchants.append(custom_line)
	enchant.call("set_displayed_enchantments","自定义黄色标题",custom_enchants)
	check(enchant_panel.size.x > original_enchant.x and enchant_panel.size.y > original_enchant.y,"enchantment frame grows in both dimensions")
	check((enchant_panel.get_child(0) as NinePatchRect).size == enchant_panel.size and (enchant_panel.get_child(1) as NinePatchRect).size == enchant_panel.size,"original 9px/10px nine-slice sprites enclose every enchantment")
	check((enchant_panel.get_child(2) as Label).text == "自定义黄色标题","custom item name remains the first line")
	check((enchant_panel.get_child(3) as Label).text.ends_with("IV"),"custom enchantment uses Roman level")
	var many_effects:Array[MCPreviewPotionEffect] = []
	for index:int in range(30):
		many_effects.append(custom_effect)
	potion.call("set_displayed_potions",many_effects)
	potion_ui._process(0.0)
	check(potion_panel.scale.x < potion_ui.display_scale,"very long custom lists auto-fit the viewport")
	var visible_rect:Rect2 = get_root().get_visible_rect()
	check(potion_panel.position.y >= potion_ui.screen_margin and potion_panel.position.y + potion_panel.size.y * potion_panel.scale.y <= visible_rect.end.y - potion_ui.screen_margin + 0.01,"auto-fitted panel keeps every row on screen")
	potion.call("set_displayed_potions",custom_potions)
	var before_pause:String = potion_ui._time_labels[0].text
	paused = true
	potion_ui._process(2.0)
	check(potion_ui._time_labels[0].text == before_pause,"visual countdown pauses with the scene tree")
	paused = false
	# A demonstration stand can ALSO be hit by an actual Witch potion. Neither
	# frame may cover the other or replace the stand's editable preview content.
	potion.position = Vector2(200,440)
	var one_preview:Array[MCPreviewPotionEffect] = [source_effects[0] as MCPreviewPotionEffect]
	potion.call("set_displayed_potions",one_preview)
	potion_ui._process(0.0)
	var potion_behavior:GDScript = load("res://scripts/effects/我的世界/女巫药水效果.gd") as GDScript
	potion_behavior.call("apply_effect",potion,"regen")
	var real_ui:MCPreviewTooltip = potion.get_node_or_null("Minecraft药水状态框") as MCPreviewTooltip
	check(real_ui != null and potion_ui._potion_names[0].text == "生命恢复","real status adds a separate frame without replacing the armor stand preview")
	if real_ui != null:
		real_ui.call("refresh_display")
		var real_panel:Control = real_ui._panel
		var demo_rect:Rect2 = Rect2(potion_panel.position,potion_panel.size * potion_panel.scale)
		var real_rect:Rect2 = Rect2(real_panel.position,real_panel.size * real_panel.scale)
		check(real_ui.stack_below == potion_ui and potion_panel.visible and real_panel.visible,"preview and live frames both render above the map")
		check(not demo_rect.intersects(real_rect),"real status frame avoids overlapping the same actor's demonstration frame")
	potion.hide()
	potion_ui._process(0.0)
	check(not potion_panel.visible,"hiding a stand hides its tooltip immediately")
	if real_ui != null:
		real_ui.call("refresh_display")
		check(not real_ui._panel.visible,"hiding the target hides its real effect frame too")
	potion.show()
	potion_ui._process(0.0)
	check(potion_panel.visible,"tooltip reappears with its owner")
	print("MC_TOOLTIP_RESULT checks=",total," failures=",failed)
	quit(1 if failed > 0 else 0)
