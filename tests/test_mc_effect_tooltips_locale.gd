extends SceneTree

## Real scene resources, both languages, a live language switch, and the
## "in-game translation only" mode (UI locale remains Chinese).
var checks:int = 0
var failures:int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok:bool,description:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MC_TOOLTIP_LOCALE_FAIL: " + description)


func _run() -> void:
	create_timer(50.0).timeout.connect(func() -> void: quit(2))
	var game:Node = root.get_node("Game")
	var original_locale:String = str(game.get("current_locale"))
	var settings:Dictionary = game.get("Game_Settings")
	var original_only:bool = bool(settings.get("Only_In_Game_Translation",false))
	settings["Only_In_Game_Translation"] = false
	game.call("set_language","zh",false)
	var arena := Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var potion:Node2D = (load("res://scenes/characters/默认/药水测试盔甲架.tscn") as PackedScene).instantiate()
	potion.process_mode = Node.PROCESS_MODE_DISABLED
	potion.set("Team","A")
	potion.position = Vector2(150,350)
	arena.add_child(potion,true)
	var enchant:Node2D = (load("res://scenes/characters/默认/附魔测试盔甲架.tscn") as PackedScene).instantiate()
	enchant.process_mode = Node.PROCESS_MODE_DISABLED
	enchant.set("Team","A")
	enchant.position = Vector2(150,750)
	arena.add_child(enchant,true)
	var potion_effects:Array[MCPreviewPotionEffect] = []
	var enchant_effects:Array[MCPreviewEnchantment] = []
	var potion_pool:Array[Resource] = potion.get("potion_pool")
	var enchant_pool:Array[Resource] = enchant.get("enchantment_pool")
	for value:Resource in potion_pool:
		potion_effects.append(value as MCPreviewPotionEffect)
	for value:Resource in enchant_pool:
		enchant_effects.append(value as MCPreviewEnchantment)
	potion.call("set_displayed_potions",potion_effects)
	enchant.call("set_displayed_enchantments","附魔书",enchant_effects,"Enchanted Book")
	var potion_ui:MCPreviewTooltip = potion.get("preview_tooltip") as MCPreviewTooltip
	var enchant_ui:MCPreviewTooltip = enchant.get("preview_tooltip") as MCPreviewTooltip
	var potion_panel:Control = potion_ui.get_node("VanillaTooltip")
	var enchant_panel:Control = enchant_ui.get_node("VanillaTooltip")
	var zh_width:float = potion_ui._potion_backgrounds[0].size.x
	check(potion_ui._potion_names[0].text == "生命恢复" and (enchant_panel.get_child(2) as Label).text == "附魔书","Chinese names are unchanged")
	check(potion_effects.size() == 8 and enchant_effects.size() == 8,"all default effects are editable bilingual resources")
	var english_potions:PackedStringArray = ["Regeneration","Speed II","Strength II","Fire Resistance","Night Vision","Jump Boost III","Water Breathing","Resistance II"]
	var english_enchants:PackedStringArray = ["Piercing IV","Sharpness V","Protection IV","Unbreaking III","Efficiency V","Power V","Smite III","Mending I"]
	var catalog:Script = load("res://global/translation_catalog.gd") as Script
	check(catalog.TABLE.en.get("药水测试盔甲架") == "Potion Test Armor Stand" and catalog.TABLE.en.get("附魔测试盔甲架") == "Enchantment Test Armor Stand" and catalog.TABLE.en.get("附魔书") == "Enchanted Book","export-safe English translation catalog contains both stands and item title")
	game.call("set_language","en",false)
	check(str(game.call("ui_t","药水测试盔甲架")) == "Potion Test Armor Stand" and str(game.call("ui_t","附魔测试盔甲架")) == "Enchantment Test Armor Stand","character picker translates both armor stands")
	check((enchant_panel.get_child(2) as Label).text == "Enchanted Book" and (enchant_panel.get_child(2) as Label).get_theme_color("font_color") == Color("ffff55"),"English enchanted-book title remains yellow and first")
	var widest:float = 0.0
	for index:int in range(potion_effects.size()):
		var title:Label = potion_ui._potion_names[index]
		var timer:Label = potion_ui._time_labels[index]
		var frame:NinePatchRect = potion_ui._potion_backgrounds[index]
		check(title.text == english_potions[index],"potion English translation " + str(index))
		var content:float = maxf(potion_ui._text_width(title.text,potion_ui.text_font),potion_ui._text_width(timer.text,potion_ui.time_font))
		var gap:float = frame.size.x - title.position.x - content
		check(gap >= 5.0 and gap <= 8.0,"potion English nine-slice hugs row " + str(index))
		widest = maxf(widest,frame.size.x)
	check(potion_panel.size.x == widest and potion_ui._potion_backgrounds[0].size.x > zh_width,"English widths and enclosing panel grow with translated text")
	for index:int in range(enchant_effects.size()):
		check((enchant_panel.get_child(index + 3) as Label).text == english_enchants[index],"enchantment English translation " + str(index))
	check((enchant_panel.get_child(0) as NinePatchRect).size == enchant_panel.size and (enchant_panel.get_child(1) as NinePatchRect).size == enchant_panel.size,"both English frame sprites fit the text")
	potion_ui._process(2.0)
	var remaining:int = potion_ui._remaining_seconds[0]
	check(remaining == 238 and potion_ui._time_labels[0].text == "03:58","English potion countdown runs normally")
	game.call("set_language","zh",false)
	check(potion_ui._potion_names[0].text == "生命恢复" and (enchant_panel.get_child(2) as Label).text == "附魔书","language switch immediately restores Chinese frames")
	check(potion_ui._remaining_seconds[0] == remaining and potion_ui._time_labels[0].text == "03:58" and potion_ui._potion_backgrounds[0].size.x == zh_width,"language switch preserves timer and remeasures Chinese width")
	settings["Only_In_Game_Translation"] = true
	game.call("set_language","en",false)
	check(str(game.call("get_ui_locale")) == "zh" and potion_ui._potion_names[0].text == "Regeneration" and (enchant_panel.get_child(2) as Label).text == "Enchanted Book","in-game-only English ignores the outer UI locale")
	check(potion_ui._potion_names[0].auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED,"Godot auto-translation cannot undo English labels")
	var custom_potion := MCPreviewPotionEffect.new()
	custom_potion.effect_name = "彩虹测试"
	custom_potion.english_name = "Rainbow Tester"
	custom_potion.level = 2
	custom_potion.duration_text_override = "01:23"
	var custom_potions:Array[MCPreviewPotionEffect] = [custom_potion]
	potion.call("set_displayed_potions",custom_potions)
	var custom_enchant := MCPreviewEnchantment.new()
	custom_enchant.enchantment_name = "定制附魔"
	custom_enchant.english_name = "Custom Enchant"
	custom_enchant.level = 5
	var custom_enchants:Array[MCPreviewEnchantment] = [custom_enchant]
	enchant.call("set_displayed_enchantments","定制黄色标题",custom_enchants,"Custom Title")
	check(potion_ui._potion_names[0].text == "Rainbow Tester II" and potion_ui._time_labels[0].text == "01:23","custom potion has separate editable English text and unchanged duration")
	check((enchant_panel.get_child(2) as Label).text == "Custom Title" and (enchant_panel.get_child(3) as Label).text == "Custom Enchant V","custom enchantment item and line have editable English text")
	enchant.call("set_displayed_enchantments","附魔书",custom_enchants)
	check((enchant_panel.get_child(2) as Label).text == "Enchanted Book","optional English title falls back to the game translation table")
	settings["Only_In_Game_Translation"] = false
	game.call("set_language","zh",false)
	check(potion_ui._potion_names[0].text == "彩虹测试 II" and (enchant_panel.get_child(3) as Label).text == "定制附魔 V","custom Chinese resources restore on language switch")
	settings["Only_In_Game_Translation"] = original_only
	game.call("set_language",original_locale,false)
	print("MC_TOOLTIP_LOCALE_RESULT checks=",checks," failures=",failures)
	quit(1 if failures > 0 else 0)
