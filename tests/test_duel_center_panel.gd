extends "res://tests/test_rotation_live_team_victory.gd"
## 顶部中间“时间 + VS”面板：开场后默认显示，不再只跟左右人物面板一起出现。
var view:SubViewport
var mirror:Control
func region_pixels(at:float,center:bool) -> int:
	world.duel_top_hud.outro_elapsed=at
	mirror._process(0);mirror.queue_redraw();mirror._text_layer.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	var image:Image=view.get_texture().get_image()
	var count:int=0
	for y:int in range(0,320,2):
		for x:int in range(0,1080,2):
			# 中间面板 x∈[440,640)，左右面板分别止于 428 / 起于 652。
			if center and (x<440 or x>=640): continue
			if not center and x>=430 and x<650: continue
			if image.get_pixel(x,y).a>0.05: count+=1
	return count
func kill_now(actor:Node) -> void:
	actor.health=0;actor.queue_free()
func open_round(hud:Control) -> void:
	world._update_character_dialogue_battle_start_edge()
	hud._update_clock(0);hud._process(0.2)
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():push_error("DUEL_CENTER_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual";game.Game_Settings.Development_Mode=false
	game.Game_Settings.Map_Background="blue";game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation();world.set_process(false);world.set_physics_process(false)
	var hud:Control=world.duel_top_hud;hud.set_process(false);hud.set_physics_process(false)
	view=SubViewport.new();view.size=Vector2i(1080,1920);view.world_2d=World2D.new();view.transparent_bg=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	mirror=hud.make_mirror("en",1);view.add_child(mirror);mirror.set_process(false)

	# 2v1：不是 1v1，开场前不显示，开场后只显示中间面板。
	await normal_setup();hud._update_clock(0)
	var a:Node=normal_actor(101,"A",-40);var ally:Node=normal_actor(102,"A",-20);var b:Node=normal_actor(103,"B",40)
	world.refresh_versus_text();world._character_dialogue_battle_was_active=false;hud._process(0.2)
	check(not hud.visible,"before the round opens no top panel is shown")
	await open_round(hud)
	check(world._character_dialogue_battle_was_active,"world reports the opening edge")
	check(hud.visible and hud.sides.size()!=2,"after the opening a 2v1 shows the center time/VS panel")
	check(await region_pixels(0,true)>0,"center panel really draws")
	check(await region_pixels(0,false)==0,"side character panels stay hidden outside 1v1")
	check(world.versus_label.self_modulate.a==1.0 and not world.versus_label.has_meta(hud.TITLE_ALPHA_META),"plain VS names stay visible with only the center panel")
	for i:int in range(4): hud._process(0.2)
	check(is_zero_approx(hud.clock_shift),"world clock stays in place with only the center panel")
	var before:float=hud.elapsed
	hud._update_clock(1.0)
	check(hud.elapsed>=before+0.99,"center clock counts battle time")
	var third:Node=normal_actor(104,"C",60)
	world.refresh_versus_text();hud._process(0.2)
	check(hud.visible and hud.sides.size()!=2,"three sides also show the center panel")
	kill_now(third);await process_frame;world.refresh_versus_text();hud._process(0.2)
	world.versus_label.hide();hud._process(0.2)
	check(not hud.visible,"modes that hide the plain VS title also hide the center panel")
	world.versus_label.show();hud._process(0.2)
	check(hud.visible,"center panel returns with the title")

	# 胜负：显示过的中间面板与 1v1 面板一样上移退场，随后成就框。
	kill_now(b);await process_frame;world._update_manual_victory_bell();hud._process(0.2)
	check(world._victory_bell_played and hud.outro_active and hud._outro_show_center,"verdict animates the shown center panel out")
	check(await region_pixels(0,true)>0,"center panel present at result start")
	check(await region_pixels(0.39,true)==0,"center panel fully above the frame before the toast")
	check(await region_pixels(1.0,true)>0,"victory toast still appears")
	world.reset();await process_frame;hud._process(0)
	check(not hud.visible and not hud._center_was_visible,"reset clears the center panel")

	# 1v1 照旧：左右面板 + 中间面板，普通 VS 文字透明隐藏。
	await normal_setup();hud._update_clock(0)
	a=normal_actor(201,"A",-40);b=normal_actor(202,"B",40)
	world.refresh_versus_text();await open_round(hud)
	check(hud.visible and hud.sides.size()==2,"1v1 shows the matchup")
	check(await region_pixels(0,false)>0,"1v1 still draws both side panels")
	check(world.versus_label.self_modulate.a==0.0,"1v1 still hides the plain VS text")

	# 只有一方：没有对手，不显示。
	await normal_setup();hud._update_clock(0)
	a=normal_actor(301,"A",-40)
	world.refresh_versus_text();await open_round(hud)
	check(not hud.visible,"a single side shows no top panel")

	view.queue_free();world.queue_free();await process_frame;game.Game_Settings=saved
	print("DUEL_CENTER_PANEL checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
