extends "res://tests/test_battle_recording.gd"

## GPU/encoder regression: compare actual video-source pixels with each
## original CanvasLayer on/off, then write both MP4s in both recording modes.
var actors:Array[Node2D] = []


func _changed_pixels(on:Image,off:Image,copy:MCPreviewTooltip) -> int:
	var panel:Control = copy._panel
	var rectangle:Rect2i = Rect2i(Vector2i(panel.position.round()),Vector2i((panel.size * panel.scale).round()))
	rectangle = rectangle.intersection(Rect2i(Vector2i.ZERO,on.get_size()))
	var count:int = 0
	for y:int in range(rectangle.position.y,rectangle.end.y,3):
		for x:int in range(rectangle.position.x,rectangle.end.x,3):
			var a:Color = on.get_pixel(x,y)
			var b:Color = off.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))) > 0.07:
				count += 1
	return count


func compare_recorded_pixels(actor:Node2D,locale:String,box_name:String = "Minecraft信息框") -> void:
	var source:MCPreviewTooltip = actor.get_node(box_name)
	var mirror:Node = recorder._effect_tooltips
	var copy:MCPreviewTooltip = mirror.copies[source.get_instance_id()][locale] as MCPreviewTooltip
	var variant:Node = recorder if locale == "zh" else recorder._secondary
	mirror.sync()
	variant._prepare_next_capture()
	await RenderingServer.frame_post_draw
	var on:Image = variant._grab_image()
	# The live-status source legitimately auto-shows every rendered frame while
	# its effect exists. Suspend only that UI process during the off-pixel probe.
	var auto_refresh:bool = box_name == "Minecraft药水状态框"
	if auto_refresh:
		source.set_process(false)
	source.hide()
	mirror.sync()
	variant._prepare_next_capture()
	await RenderingServer.frame_post_draw
	var off:Image = variant._grab_image()
	source.show()
	if auto_refresh:
		source.set_process(true)
		source.call("refresh_display")
	mirror.sync()
	var changed:int = _changed_pixels(on,off,copy)
	print("TOOLTIP_PIXELS ",actor.name," ",locale," ",box_name," ",changed," panel=",copy._panel.position," size=",copy._panel.size)
	check(on.get_size() == Vector2i(1080,1920) and changed > 100,"rendered "+actor.name+" "+box_name+" present in "+locale+" video source")


func capture_mode(sim:bool) -> void:
	var mode_name:String = "SIM" if sim else "LIVE"
	check(recorder.start_simulated() if sim else recorder.start_live(),mode_name+": starts real bilingual encoder")
	if recorder.is_idle():
		print("RECORD_TOOLTIP_START_ERROR ",recorder.get_last_error())
		return
	await settle(0.3)
	var copyset:Node = recorder._effect_tooltips
	copyset.sync()
	check(copyset.copies.size() == 3,mode_name+": preview potion, enchantment and REAL potion all exist in capture pair")
	if copyset.copies.size() != 3:
		recorder.stop()
		await wait_idle()
		return
	var potion_source:MCPreviewTooltip = actors[0].get_node("Minecraft信息框")
	var enchant_source:MCPreviewTooltip = actors[1].get_node("Minecraft信息框")
	var active_source:MCPreviewTooltip = actors[0].get_node("Minecraft药水状态框")
	var pot_zh:MCPreviewTooltip = copyset.copies[potion_source.get_instance_id()].zh
	var pot_en:MCPreviewTooltip = copyset.copies[potion_source.get_instance_id()].en
	var ench_zh:MCPreviewTooltip = copyset.copies[enchant_source.get_instance_id()].zh
	var ench_en:MCPreviewTooltip = copyset.copies[enchant_source.get_instance_id()].en
	var real_zh:MCPreviewTooltip = copyset.copies[active_source.get_instance_id()].zh
	var real_en:MCPreviewTooltip = copyset.copies[active_source.get_instance_id()].en
	var composition:CanvasLayer = recorder._sim_viewport.get_node("RecordingComposition") as CanvasLayer
	check(pot_zh.layer > composition.layer and ench_zh.layer > composition.layer and real_zh.layer > composition.layer,mode_name+": effects cannot be covered by video headers")
	check(pot_zh._potion_names[0].text == "生命恢复" and pot_en._potion_names[0].text == "Regeneration",mode_name+": potion names in both languages")
	check((ench_zh._panel.get_child(2) as Label).text == "附魔书" and (ench_en._panel.get_child(2) as Label).text == "Enchanted Book",mode_name+": enchantment names in both languages")
	check(real_zh._potion_names[0].text == "迅捷" and real_en._potion_names[0].text == "Speed" and real_zh._potion_names[1].text == "中毒" and real_en._potion_names[1].text == "Poison",mode_name+": real effects are each recorded in their own language")
	check(real_zh._time_labels[1].text == "∞" and real_en._time_labels[1].text == "∞",mode_name+": Witch's infinite poison displays in both videos")
	var speed_status:Node = actors[0].get_node("MinecraftStatus_speed")
	speed_status.remaining = 2.4
	active_source.call("refresh_display")
	copyset.sync()
	check(real_zh._time_labels[0].text == "00:03" and real_en._time_labels[0].text == "00:03",mode_name+": both cameras copy real remaining time, not separate clocks")
	for locale:String in ["zh","en"]:
		var live_copy:MCPreviewTooltip = real_zh if locale == "zh" else real_en
		var demo_copy:MCPreviewTooltip = pot_zh if locale == "zh" else pot_en
		var live_rect:Rect2 = Rect2(live_copy._panel.position,live_copy._panel.size * live_copy._panel.scale)
		var demo_rect:Rect2 = Rect2(demo_copy._panel.position,demo_copy._panel.size * demo_copy._panel.scale)
		check(live_copy.stack_below == demo_copy and not live_rect.intersects(demo_rect),mode_name+": two frames on the same actor do not overlap in "+locale+" video")
	for actor:Node2D in actors:
		for locale:String in ["zh","en"]:
			await compare_recorded_pixels(actor,locale)
	for locale:String in ["zh","en"]:
		await compare_recorded_pixels(actors[0],locale,"Minecraft药水状态框")
	await settle(0.15)
	var recorded_frames:int = recorder._frame_index
	recorder.stop()
	await wait_idle()
	check(recorded_frames >= 2,mode_name+": actual video frames encoded")
	check(recorder.last_outputs.size() == 2,mode_name+": two language videos saved")
	for locale:String in ["zh","en"]:
		var path:String = str(recorder.last_outputs.get(locale,""))
		check(not path.is_empty() and FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > 10000,mode_name+": valid nonempty "+locale+" video at "+path)
	check(recorder._effect_tooltips == null,mode_name+": capture copies removed on stop")
	game.now_stop_state = false
	if game.has_method("continue_game"): game.continue_game()
	await settle(0.05)


func run() -> void:
	create_timer(140.0,true,false,true).timeout.connect(func(): print("TOOLTIP_VIDEO_TIMEOUT");quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_locale:String = game.current_locale
	game.set_language("zh",false)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = false
	game.Game_Settings.Map_Background = "blue"
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	root.size = Vector2i(540,960)
	await settle(0.5)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.team.hide()
	world.control.hide()
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	recorder.preferences = recorder.PreferencesScript.new("user://tooltip_recording_test.cfg")
	recorder.preferences.directory = "user://recordings/tooltip_recording_test"
	recorder.preferences.tail_seconds = 60.0
	recorder.set_composition(recorder.preferences.FULL)
	world._battle_setup.clear()
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	for index:int in range(2):
		var character:String = "药水测试盔甲架" if index == 0 else "附魔测试盔甲架"
		var actor:Node2D = (load("res://scenes/characters/默认/"+character+".tscn") as PackedScene).instantiate()
		actor.set("randomize_on_spawn",false)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.set("Team","Team"+str(index))
		actor.position = center + Vector2(-85 if index == 0 else 85,-120 if index == 0 else 120)
		world.add_child(actor,true)
		actors.append(actor)
		world._battle_setup.append({"id":index+1,"team":"Team"+str(index),"char":character})
	await settle(0.1)
	# Give the demo stand REAL effects as well. Freeze actor physics like the
	# preview fixture: the recorder still sees both independent CanvasLayers.
	actors[0].set("Max_health",10000.0)
	actors[0].set("health",10000.0)
	var witch_effects:GDScript = load("res://scripts/effects/我的世界/女巫药水效果.gd") as GDScript
	witch_effects.call("apply_effect",actors[0],"speed")
	witch_effects.call("apply_effect",actors[0],"poison")
	check(actors[0].get_node_or_null("Minecraft药水状态框") != null,"affected preview stand has a distinct real-status source frame")
	await capture_mode(false)
	recorder.set_composition(recorder.preferences.FOLLOW)
	await capture_mode(true)
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.set_language(saved_locale,false)
	print("MC_TOOLTIP_VIDEO_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
