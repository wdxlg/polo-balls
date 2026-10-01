extends "res://tests/test_high_damage_feedback.gd"
const TUNING = preload("res://global/feedback_settings.gd")

func put(suffix:String,value:Variant) -> void:
	game.set_runtime_game_setting("Feedback_"+suffix,value,false)

func contract_cases() -> void:
	game.reset_feedback_settings("Shaking_Camera",false)
	game.reset_feedback_settings("High_Damage_Feedback",false)
	super.contract_cases()
	var before_hash:String = FileAccess.get_sha256(game.SETTINGS_PATH) if FileAccess.file_exists(game.SETTINGS_PATH) else ""
	var original_path:String = game._settings_storage_path
	var path:String = OS.get_cache_dir().path_join("feedback_controls_%d.cfg"%OS.get_process_id())
	game._settings_storage_path = path
	for channel:String in ["Body","Camera"]:
		var previous:float = 0.0
		for damage:float in [1.0,5.0,9.0,10.0,11.0,25.0,49.0,50.0,51.0,100.0,250.0,500.0,1000.0,1000000.0]:
			var amplitude:float = TUNING.amplitude(damage,game.Game_Settings,channel)
			check(amplitude>previous and amplitude<TUNING.number(game.Game_Settings,channel+"_Max"),"strict damage growth: "+channel+" "+str(damage))
			previous = amplitude
	check(TUNING.tier(10.0,game.Game_Settings)==0 and TUNING.tier(11.0,game.Game_Settings)==1 and TUNING.tier(50.0,game.Game_Settings)==1 and TUNING.tier(51.0,game.Game_Settings)==2,"10/11 and 50/51 use inclusive lower tiers")
	game.set_runtime_game_setting(KEY,false,false)
	for damage:float in [9.0,10.0,11.0,50.0,51.0,100.0,500.0]:
		reset_feedback()
		check(hit(damage)==damage and is_equal_approx(target._hurt_shake_effect.amplitude,TUNING.amplitude(damage,game.Game_Settings,"Body")) and is_equal_approx(world._damage_shake_pending_peak,TUNING.amplitude(damage,game.Game_Settings,"Camera")),"real loss drives both configurable curves: "+str(damage))
	put("Shake_Low",20.0)
	put("Shake_High",100.0)
	reset_feedback()
	hit(75.0)
	check(target._hurt_shake_effect.amplitude<0.6 and world._damage_shake_pending_peak<0.75,"custom damage boundaries affect actual hits")
	put("Shake_Low",5.0)
	put("Shake_High",15.0)
	reset_feedback()
	target.max_block=1000
	target.block=1000
	check(hit(500.0,false)==0.0 and world._damage_shake_pending_peak<=0.75,"pure shield respects the configured light ceiling")
	game.reset_feedback_settings("Shaking_Camera",false)
	put("Body_Gain",2.0)
	put("Camera_Gain",0.5)
	reset_feedback()
	hit(50.0)
	check(is_equal_approx(target._hurt_shake_effect.amplitude,1.2) and is_equal_approx(world._damage_shake_pending_peak,0.375),"body and screen gain are independent")
	put("Shake_MinDuration",0.8)
	put("Shake_MaxDuration",0.8)
	put("Shake_Frequency",30.0)
	reset_feedback()
	hit(51.0)
	world._update_damage_camera_shake(0.0)
	check(is_equal_approx(target._hurt_shake_effect.duration,0.8) and is_equal_approx(world._damage_shake_duration,0.8),"duration can exceed the old hardcoded envelope")
	target._hurt_shake_effect.advance(0.01)
	check(is_equal_approx(target._hurt_shake_effect.phase,TAU*30.0*0.01),"frequency setting drives the actual body oscillator")
	put("Body_Gain",0.0)
	target._hurt_shake_effect.advance(0.001)
	check(not target._hurt_shake_effect.active,"zero body gain removes the active body offset")
	game.reset_feedback_settings("Shaking_Camera",false)
	game.set_runtime_game_setting(KEY,true,false)
	put("Focus_Damage",150.0)
	put("Focus_ThresholdCap",150.0)
	put("Focus_HealthPercent",0.0)
	put("Focus_MinZoom",1.32)
	put("Focus_MaxZoom",1.32)
	put("Focus_In",0.2)
	put("Focus_Hold",0.4)
	put("Focus_Out",0.5)
	put("Focus_Cooldown",0.0)
	world.request_damage_focus(149.0,1000.0,target.global_position)
	check(world._damage_focus_pending_strength<0.0,"custom focus threshold rejects smaller hits")
	world.request_damage_focus(150.0,1000.0,target.global_position)
	world._update_damage_focus()
	check(is_equal_approx(world._damage_focus_peak_zoom,1.32),"custom zoom reaches the live camera channel")
	world._damage_focus_started_usec=Time.get_ticks_usec()-300000
	world._update_damage_focus()
	check(is_equal_approx(world._damage_focus_weight,1.0),"custom focus hold is not limited to the previous 70 ms")
	world._damage_focus_started_usec=Time.get_ticks_usec()-850000
	world._update_damage_focus()
	check(world._damage_focus_weight>0.1 and world._damage_focus_weight<0.9,"custom focus return duration is used")
	world._clear_high_damage_feedback()
	put("Hitstop_Damage",150.0)
	put("Hitstop_HealthPercent",0.0)
	put("Hitstop_Factor",0.25)
	put("Hitstop_MinDuration",0.2)
	put("Hitstop_MaxDuration",0.2)
	put("Hitstop_Cooldown",0.9)
	world.request_heavy_hitstop(149.0,1000.0,target.global_position)
	check(world._heavy_hit_pending_strength<0.0,"custom hitstop threshold rejects smaller hits")
	world.request_heavy_hitstop(150.0,1000.0,target.global_position)
	world._update_heavy_hitstop()
	check(is_equal_approx(game.get_time_scale_override_factor(),0.25) and world._heavy_hit_end_usec-Time.get_ticks_usec()>190000,"custom hitstop speed and 200 ms duration really apply")
	check(world._heavy_hit_next_allowed_usec-Time.get_ticks_usec()>890000,"custom hitstop cooldown really applies")
	world._clear_high_damage_feedback()
	for key:String in TUNING.SPECS:
		check(not game._is_network_shared_setting(key) and not game._shared_settings_snapshot().has(key),"tuning remains a local preference: "+key)
	put("Shake_Low",100.0)
	put("Shake_High",3.0)
	check(game.Game_Settings.Feedback_Shake_High==101.0,"reversed damage thresholds normalize into valid order")
	put("Body_Tiny",64.0)
	check(game.Game_Settings.Feedback_Body_Tiny<game.Game_Settings.Feedback_Body_Light and game.Game_Settings.Feedback_Body_Light<game.Game_Settings.Feedback_Body_Strong and game.Game_Settings.Feedback_Body_Strong<game.Game_Settings.Feedback_Body_Max,"tier strengths cannot be inverted")
	put("Focus_MaxZoom",NAN)
	put("Hitstop_Factor",-100.0)
	put("Shake_Curve","bad")
	check(is_finite(game.Game_Settings.Feedback_Focus_MaxZoom) and game.Game_Settings.Feedback_Hitstop_Factor==0.01 and game.Game_Settings.Feedback_Shake_Curve==0.75,"nonfinite, out-of-range and wrong-type settings are sanitized")
	game.reset_feedback_settings("Shaking_Camera",false)
	game.reset_feedback_settings("High_Damage_Feedback",false)
	var ui:Control=world.control
	var params:VBoxContainer=ui.settings_category_boxes.parameters
	var composition:HBoxContainer=params.get_node("CompositionRow")
	var background:HBoxContainer=params.get_node("MapBackgroundRow")
	check(composition.get_child(0) is PanelContainer and composition.get_child(0).get_theme_stylebox("panel")==background.get_child(0).get_theme_stylebox("panel"),"framing label reuses the exact existing framed title style")
	check(params.find_child("CompositionFeedback",true,false)==null,"framing description node has been removed")
	check(ui._feedback_spins.size()==6 and TUNING.SIMPLE_LABELS.size()==6,"only six simple feedback controls are visible")
	for locale:String in ["zh","en"]:
		game.set_language(locale,false)
		ui._refresh_runtime_translations()
		var translated:bool=true
		for key:String in TUNING.SIMPLE_LABELS:
			var label:Label=ui._feedback_spins[key].get_parent().get_node("Text/Label")
			translated=translated and label.text==game.ui_t(str(TUNING.SIMPLE_LABELS[key])) and not label.text.begins_with("SETTING_")
		check(translated,"parameter labels refresh in "+locale)
	game.set_language("zh",false)
	game.set_runtime_game_setting("Shaking_Camera",false,false)
	game.set_runtime_game_setting(KEY,false,false)
	ui._sync_feedback_options()
	check(not ui._feedback_groups.Shaking_Camera.visible and not ui._feedback_groups.High_Damage_Feedback.visible,"both switches collapse their own parameters")
	for node:Node in ui._collect_descendants(params):
		if node is TextureButton and str(node.get_meta("game_setting_key","")) in [KEY,"Shaking_Camera"]: node.button_up.emit()
	check(ui._feedback_groups.Shaking_Camera.visible and ui._feedback_groups.High_Damage_Feedback.visible,"actual toggle signal handlers expand both parameter groups")
	var spin:SpinBox=ui._feedback_spins.Feedback_Body_Light
	put("Body_Gain",0.0)
	put("Camera_Gain",0.0)
	spin.value=0.8
	check(is_equal_approx(game.Game_Settings.Feedback_Body_Light,0.8) and is_equal_approx(game.Game_Settings.Feedback_Camera_Light,1.0) and game.Game_Settings.Feedback_Body_Gain==1.0 and game.Game_Settings.Feedback_Camera_Gain==1.0,"one light-tier input updates body and camera together")
	var config:=ConfigFile.new()
	check(config.load(path)==OK and is_equal_approx(config.get_value("game_settings","Feedback_Body_Light"),0.8),"simple UI changes persist through the normal save path")
	put("Body_Light",0.3)
	game.load_persistent_settings(path)
	world._sync_feedback_settings()
	check(is_equal_approx(game.Game_Settings.Feedback_Body_Light,0.8),"saved simple tuning restores through the real load path")
	game.set_simple_feedback_setting("Feedback_Body_Strong",12.0,false)
	reset_feedback()
	hit(100.0)
	check(target._hurt_shake_effect.amplitude>12.0 and world._damage_shake_pending_peak>7.2,"simple strong setting changes both real damage feedback channels")
	for channel:String in ["Body","Camera"]:
		var weak_heavy:float = TUNING.amplitude(51.0,game.Game_Settings,channel)
		var stronger_heavy:float = TUNING.amplitude(250.0,game.Game_Settings,channel)
		check(stronger_heavy>weak_heavy*1.65,"heavy damage has perceptible growth rather than an almost fixed kick: "+channel)
	var strong_spin:SpinBox = ui._feedback_spins.Feedback_Body_Strong
	strong_spin.value = 64.0
	check(game.Game_Settings.Feedback_Body_Strong==64.0 and game.Game_Settings.Feedback_Body_Max>100.0,"maximum visible strength does not flatten against the old hidden 64 cap")
	check(TUNING.amplitude(250.0,game.Game_Settings,"Body")>TUNING.amplitude(51.0,game.Game_Settings,"Body")*2.0,"damage still grows substantially at the maximum UI strength")
	for strength:float in [10.0,20.0,40.0]:
		strong_spin.value = strength
		reset_feedback()
		world.camera_shake_amount = 100.0
		world._damage_shake_elapsed = 0.0
		world._update_damage_camera_shake(0.0)
		check(is_equal_approx((world.camera_2d.offset*world.camera_2d.zoom).x,strength),"legacy skill impulses obey the visible strength: "+str(strength))
	game.reset_feedback_settings("Shaking_Camera",false)
	game.set_simple_feedback_setting("Feedback_Focus_MaxZoom",1.0,false)
	check(game.Game_Settings.Feedback_Focus_MinZoom==1.0 and world.damage_focus_max_zoom==1.0,"simple zoom can reach 1 without a hidden minimum blocking it")
	game.set_simple_feedback_setting("Feedback_Hitstop_MaxDuration",0.02,false)
	check(world.heavy_hitstop_min_duration==0.02 and world.heavy_hitstop_max_duration==0.02,"simple duration is not overridden by a hidden minimum")
	put("Focus_MaxZoom",1.4)
	(ui._feedback_groups.Shaking_Camera.find_child("ResetFeedback",true,false) as Button).pressed.emit()
	check(game.Game_Settings.Feedback_Body_Light==0.6 and game.Game_Settings.Feedback_Camera_Light==0.75 and game.Game_Settings.Feedback_Focus_MaxZoom==1.4,"reset button resets only its own group")
	game.reset_feedback_settings(KEY,false)
	game.reset_feedback_settings("Shaking_Camera",false)
	game._settings_storage_path=original_path
	DirAccess.remove_absolute(path)
	check((FileAccess.get_sha256(game.SETTINGS_PATH) if FileAccess.file_exists(game.SETTINGS_PATH) else "")==before_hash,"UI/persistence tests never modify the personal settings file")
	reset_feedback()

func capture_case(folder:String,label:String,damage:float,enabled:bool) -> void:
	if OS.get_cmdline_user_args().has("--ui-only"):
		if label=="special_on": await capture_settings(folder)
		return
	await super.capture_case(folder,label,damage,enabled)
	if label!="damage_51": return
	for value:float in [9.0,10.0,11.0,100.0,500.0]:
		await super.capture_case(folder,"damage_%d"%int(value),value,false)
	await capture_settings(folder)

func capture_settings(folder:String) -> void:
	var ui:Control=world.control
	for warm:int in 120: await RenderingServer.frame_post_draw
	ui.show()
	ui.game_setting.show()
	ui._show_settings_category("parameters")
	for locale:String in ["zh","en"]:
		game.set_language(locale,false)
		ui._refresh_runtime_translations()
		game.set_runtime_game_setting(KEY,false,false)
		game.set_runtime_game_setting("Shaking_Camera",false,false)
		ui._sync_feedback_options()
		await ui_shot(folder,locale+"_framing",null)
		game.set_runtime_game_setting("Shaking_Camera",true,false)
		ui._sync_feedback_options()
		await ui_shot(folder,locale+"_shake_expanded",ui._feedback_groups.Shaking_Camera.get_parent().get_child(ui._feedback_groups.Shaking_Camera.get_index()-1))
		await ui_shot(folder,locale+"_shake",ui._feedback_spins.Feedback_Body_Tiny.get_parent())
		game.set_runtime_game_setting("Shaking_Camera",false,false)
		game.set_runtime_game_setting(KEY,true,false)
		ui._sync_feedback_options()
		await ui_shot(folder,locale+"_focus_expanded",ui._feedback_groups.High_Damage_Feedback.get_parent().get_child(ui._feedback_groups.High_Damage_Feedback.get_index()-1))
		await ui_shot(folder,locale+"_focus",ui._feedback_spins.Feedback_Focus_MaxZoom.get_parent())
	ui.game_setting.hide()
	ui.hide()
	game.set_language("zh",false)

func ui_shot(folder:String,label:String,anchor:Control) -> void:
	var ui:Control=world.control
	for frame:int in 4: await RenderingServer.frame_post_draw
	ui.settings_scroll.scroll_vertical=0 if anchor==null else roundi((ui.settings_stack.get_global_transform().affine_inverse()*anchor.global_position).y)
	for frame:int in 4: await RenderingServer.frame_post_draw
	var width:float=ui.settings_scroll.size.x
	var good:bool=true
	for key:String in ui._feedback_spins:
		var spin:SpinBox=ui._feedback_spins[key]
		if spin.is_visible_in_tree():
			good=good and spin.get_parent().size.x<=width+0.1
	check(good,"GPU settings rows fit the scroll viewport: "+label)
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"GPU settings screenshot: "+label)
