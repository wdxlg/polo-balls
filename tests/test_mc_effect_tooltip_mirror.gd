extends SceneTree

## Fast headless regression for the two independent recording Viewports. The
## separate GPU test verifies pixels and the actual LIVE/SIM encoder output.
var checks:int = 0
var failures:int = 0
var stage:Node2D
var game:Node
var mirror:Node
var potion:Node2D
var enchant:Node2D
var zh:SubViewport
var en:SubViewport


func _initialize() -> void:
	call_deferred("run")


func check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TOOLTIP_MIRROR_FAIL: " + message)


func _copy(actor:Node2D,locale:String) -> MCPreviewTooltip:
	return mirror.copies[(actor.get_node("Minecraft信息框") as MCPreviewTooltip).get_instance_id()][locale] as MCPreviewTooltip


func run() -> void:
	create_timer(45.0,true,false,true).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	var saved_locale:String = game.get("current_locale")
	game.call("set_language","zh",false)
	root.size = Vector2i(1080,1920)
	var player_mask:int = root.canvas_cull_mask
	root.canvas_cull_mask &= ~((1 << 17) | (1 << 18))
	stage = Node2D.new()
	root.add_child(stage)
	current_scene = stage
	for language:String in ["zh","en"]:
		var viewport := SubViewport.new()
		viewport.name = "Capture_" + language
		viewport.size = Vector2i(1080,1920)
		viewport.disable_3d = true
		viewport.world_2d = root.world_2d
		# Same masks as the live bilingual recorder: exclude player-only frames
		# and the opposite language from this shared-world capture.
		viewport.canvas_cull_mask = 1 | (1 << (17 if language == "zh" else 18))
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.canvas_transform = Transform2D.IDENTITY.translated(Vector2(200 if language == "zh" else 320,0))
		if language == "zh": zh = viewport
		else: en = viewport
	potion = (load("res://scenes/characters/默认/药水测试盔甲架.tscn") as PackedScene).instantiate()
	enchant = (load("res://scenes/characters/默认/附魔测试盔甲架.tscn") as PackedScene).instantiate()
	for actor:Node2D in [potion,enchant]:
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.set("Team","A")
		actor.position = Vector2(120,500 if actor == potion else 940)
		stage.add_child(actor,true)
	var potion_pool:Array[Resource] = potion.get("potion_pool")
	var enchant_pool:Array[Resource] = enchant.get("enchantment_pool")
	var potion_entries:Array[MCPreviewPotionEffect] = [potion_pool[0] as MCPreviewPotionEffect]
	var enchant_entries:Array[MCPreviewEnchantment] = [enchant_pool[0] as MCPreviewEnchantment]
	potion.call("set_displayed_potions",potion_entries)
	enchant.call("set_displayed_enchantments","附魔书",enchant_entries,"Enchanted Book")
	mirror = (load("res://scripts/ui/battle_record_effect_tooltips.gd") as GDScript).new()
	stage.add_child(mirror)
	mirror.begin(zh,en)
	mirror.sync()
	check(mirror.copies.size() == 2,"both stands mirrored into both captures")
	if mirror.copies.size() != 2:
		quit(2)
		return
	var source:MCPreviewTooltip = potion.get_node("Minecraft信息框")
	var zh_potion:MCPreviewTooltip = _copy(potion,"zh")
	var en_potion:MCPreviewTooltip = _copy(potion,"en")
	var zh_enchant:MCPreviewTooltip = _copy(enchant,"zh")
	var en_enchant:MCPreviewTooltip = _copy(enchant,"en")
	check(zh_potion.get_viewport() == zh and en_potion.get_viewport() == en,"copies live in the actual language-specific capture Viewports")
	check(source.get_viewport() == root,"original stays on the player Viewport")
	check(source.top_level and zh_potion.top_level and en_enchant.top_level and source.z_index == MCPreviewTooltip.TOOLTIP_Z and zh_potion.z_index == source.z_index and en_enchant.z_index == source.z_index and source.visibility_layer == (1 << 19) and zh_potion.visibility_layer == (1 << 17) and en_enchant.visibility_layer == (1 << 18),"player and bilingual capture frames share foreground-safe world depth but use separate visibility masks")
	check(zh_potion._potion_names[0].text == "生命恢复" and en_potion._potion_names[0].text == "Regeneration","one frame contains Chinese AND English effect names")
	check((zh_enchant._panel.get_child(2) as Label).text == "附魔书" and (en_enchant._panel.get_child(2) as Label).text == "Enchanted Book","enchantment titles are bilingual")
	check((en_enchant._panel.get_child(3) as Label).text == "Piercing IV","enchantment rows are translated")
	check(not en_potion._potion_names[0].is_in_group(&"_runtime_localization_controls") and not en_enchant._panel.get_child(2).is_in_group(&"_runtime_localization_controls"),"fixed English names exempt from UI-language sweep")
	check(en_potion._potion_backgrounds[0].size.x > zh_potion._potion_backgrounds[0].size.x,"nine-slice grows to fit English wording")
	check(zh_potion._remaining_seconds[0] == source._remaining_seconds[0],"first captured second follows the original")
	var before:int = source._remaining_seconds[0]
	source._process(2.0)
	mirror.sync()
	check(source._remaining_seconds[0] == before-2 and en_potion._remaining_seconds[0] == before-2 and zh_potion._time_labels[0].text == source._time_labels[0].text,"both captures follow source's countdown exactly once")
	var center:Vector2 = en_potion._panel.position
	en.canvas_transform = Transform2D.IDENTITY.translated(Vector2(470,0))
	mirror.sync()
	check(en_potion._panel.position.x > center.x + 100.0,"recording positioning follows its OWN camera instead of the player camera")
	check(en_potion.transform.is_equal_approx(en.canvas_transform.affine_inverse()),"recording tooltip cancels only its own viewport camera transform")
	# The actor disappears from the player's camera, but must appear in the
	# independently framed recordings. Never gate on source._panel.visible.
	potion.position = Vector2(-350,500)
	zh.canvas_transform = Transform2D.IDENTITY.translated(Vector2(700,0))
	en.canvas_transform = Transform2D.IDENTITY.translated(Vector2(710,0))
	source._process(0.0)
	mirror.sync()
	check(not source._panel.visible and zh_potion._panel.visible and en_potion._panel.visible,"off-player-camera effect is STILL visible in both video cameras")
	game.call("set_language","en",false)
	mirror.sync()
	check(zh_potion._potion_names[0].text == "生命恢复" and en_potion._potion_names[0].text == "Regeneration" and (zh_enchant._panel.get_child(2) as Label).text == "附魔书","player language changes never alter either video locale")
	var custom := MCPreviewPotionEffect.new()
	custom.effect_name = "彩虹测试"
	custom.english_name = "Rainbow Tester"
	custom.duration_seconds = 9
	var custom_list:Array[MCPreviewPotionEffect] = [custom]
	potion.call("set_displayed_potions",custom_list)
	mirror.sync()
	check(zh_potion._potion_names[0].text == "彩虹测试" and en_potion._potion_names[0].text == "Rainbow Tester","new or changed effects propagate during recording")
	check(zh_potion._remaining_seconds[0] == 9 and en_potion._remaining_seconds[0] == 9,"replacement effect starts from the new source timer")
	var old_id:int = (enchant.get_node("Minecraft信息框") as MCPreviewTooltip).get_instance_id()
	enchant.queue_free()
	await process_frame
	mirror.sync()
	check(not mirror.copies.has(old_id) and mirror.copies.size() == 1,"despawning removes both orphaned copies")
	mirror.finish()
	await process_frame
	check(mirror.copies.is_empty() and not RenderingServer.frame_pre_draw.is_connected(mirror.sync),"session teardown removes all mirrors and the draw hook")
	check(source.is_inside_tree() and source._potion_names[0].text == "Rainbow Tester","teardown leaves the player's original untouched")
	stage.queue_free()
	zh.queue_free()
	en.queue_free()
	await process_frame
	game.call("set_language",saved_locale,false)
	root.canvas_cull_mask = player_mask
	print("MC_TOOLTIP_MIRROR_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
