extends "res://tests/test_rotation_live_team_victory.gd"
var views:Dictionary={}
var mirrors:Dictionary={}
func mirror_pixels(locale:String,at:float,key:String) -> int:
	world.duel_top_hud.outro_elapsed=at
	var mirror:Control=mirrors[locale]
	mirror._process(0);mirror.queue_redraw();mirror._text_layer.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	var image:Image=views[locale].get_texture().get_image()
	var nonempty:int=0
	for y:int in range(0,320,2):
		for x:int in range(0,1080,2):
			if image.get_pixel(x,y).a>0.05:nonempty+=1
	if not OS.get_cmdline_user_args().is_empty():image.save_png(OS.get_cmdline_user_args()[0]+"/"+key+"_"+locale+".png")
	return nonempty
func kill_now(actor:Node) -> void:
	actor.health=0;actor.queue_free()
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():push_error("HUD_OUTRO_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual";game.Game_Settings.Development_Mode=false
	game.Game_Settings.Map_Background="blue";game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation();world.set_process(false);world.set_physics_process(false)
	var hud:Control=world.duel_top_hud;hud.set_process(false);hud.set_physics_process(false)
	for locale:String in ["zh","en"]:
		var view:=SubViewport.new();view.size=Vector2i(1080,1920);view.world_2d=World2D.new();view.transparent_bg=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view);views[locale]=view
		var mirror:Control=hud.make_mirror(locale,1);view.add_child(mirror);mirror.set_process(false);mirrors[locale]=mirror
	# Actual 2v1 -> late pair scan -> final elimination before the pair ever gets a display frame.
	await normal_setup();hud._update_clock(0)
	var a:Node=normal_actor(101,"A",-40);var ally:Node=normal_actor(102,"A",-20);var b:Node=normal_actor(103,"B",40)
	world.refresh_versus_text();world._update_manual_victory_bell();hud._process(0.2)
	check(not hud.visible,"multi-character encounter has no matchup panels")
	kill_now(ally);hud._refresh_pair()
	check(hud.sides.size()==2 and not hud.visible,"late pair is identified without ever being shown")
	kill_now(b);world._update_manual_victory_bell();hud._process(0)
	check(world._victory_bell_played and hud.outro_active,"real elimination still creates a victory achievement")
	for locale:String in ["zh","en"]:
		check(await mirror_pixels(locale,0,"never_shown_start")==0,locale+" unseen matchup must not appear at result start")
		check(await mirror_pixels(locale,0.2,"never_shown_exit")==0,locale+" unseen matchup must not slide upward")
		check(await mirror_pixels(locale,1,"team_achievement")>0,locale+" team achievement still appears")
	check(hud.victory_result.get("is_team",false) and hud.victory_result.get("member_count",0)==2,"original team roster and wool victory retained")
	# Normal 1v1: panels really were shown and must keep their original exit animation.
	await normal_setup();hud._update_clock(0)
	a=normal_actor(201,"A",-40);b=normal_actor(202,"B",40)
	world.refresh_versus_text();world._update_manual_victory_bell();hud._process(0.2)
	check(hud.visible and await mirror_pixels("en",0,"visible_duel")>0,"ordinary matchup really displays before result")
	kill_now(b);world._update_manual_victory_bell();hud._process(0.2) # Force pair scan on the very first death frame.
	check(await mirror_pixels("en",0,"visible_exit_start")>0,"previously visible matchup still exits normally")
	check(await mirror_pixels("en",0.39,"visible_exit_end")==0,"normal panels move fully above the frame")
	check(await mirror_pixels("en",1,"solo_achievement")>0,"solo achievement retained after the normal exit")
	# Rotation creates a result snapshot even when an on-screen pair never existed.
	await setup("duel",2,2)
	check(not hud.visible,"new rotation has no previously presented matchup")
	hud.begin_round_result("left")
	for locale:String in ["zh","en"]:
		check(await mirror_pixels(locale,0,"rotation_unseen")==0,locale+" reconstructed round snapshot cannot invent an exiting matchup")
		check(await mirror_pixels(locale,1,"rotation_achievement")>0,locale+" round achievement remains visible")
	# A displayed rotation matchup retains its normal exit; a later correction cannot revive it.
	await setup("duel",2,2);hud._update_clock(0);world.refresh_versus_text();hud._process(0.2)
	check(hud.visible,"new rotation matchup can display after reset")
	hud.begin_round_result("left")
	check(await mirror_pixels("en",0,"rotation_seen")>0,"shown rotation matchup retains exit")
	hud.outro_elapsed=1;hud.begin_round_result("")
	check(await mirror_pixels("en",0,"round_correction")==0,"late double-knockout correction does not revive already exited panels")
	# Current suppression wins over visibility remembered from an earlier frame.
	await normal_setup();hud._update_clock(0)
	a=normal_actor(301,"A",-40);b=normal_actor(302,"B",40)
	world.refresh_versus_text();world._update_manual_victory_bell();hud._process(0.2)
	world.versus_label.hide();kill_now(b);world._update_manual_victory_bell();hud._process(0)
	check(await mirror_pixels("en",0,"suppressed_at_verdict")==0,"currently suppressed matchup is never resurrected by verdict")
	world.reset();hud._process(0)
	check(not hud.visible and not hud.outro_active,"reset clears the presentation lifecycle")
	for view:SubViewport in views.values():view.queue_free()
	world.queue_free();await process_frame;game.Game_Settings=saved
	print("HUD_OUTRO_VISIBILITY checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
