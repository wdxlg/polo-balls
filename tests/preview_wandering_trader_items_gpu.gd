extends "res://tests/preview_wandering_trader_gpu.gd"
## GPU preview (GUI mode only) of the 流浪商人 items: display frame, wall-texture exit crumbs and each
## item in the real World renderer. Screenshots go to WANDERING_TRADER_EVIDENCE_DIR.

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Actual GPU renderer required"); quit(2); return
	create_timer(170.0,true,false,true).timeout.connect(func(): print("WT_ITEMS_GPU_TIMEOUT"); quit(2))
	var CATALOG:GDScript=load("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
	var WALLS:Script=load("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
	game=root.get_node("Game")
	game.Game_Settings.Environment="none"
	game.Game_Settings.Minecraft_Clouds=false
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	AudioServer.set_bus_mute(0,true)
	root.size=Vector2i(1080,720);root.content_scale_size=root.size
	folder=OS.get_environment("WANDERING_TRADER_EVIDENCE_DIR")
	if folder.is_empty():folder="user://wandering_trader_gpu"
	DirAccess.make_dir_recursive_absolute(folder)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	world.control.hide();world.versus_label.hide()
	for layer:CanvasLayer in root.find_children("*","CanvasLayer",true,false):layer.hide()
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	var center:Vector2=rect.get_center()
	camera=Camera2D.new();world.add_child(camera);camera.global_position=center;camera.zoom=Vector2.ONE*(720.0/rect.size.y)*0.95;camera.make_current()
	var zoom0:Vector2=camera.zoom
	var trader:Node2D=unit("res://scenes/characters/我的世界/流浪商人.tscn","WT","Team0",center)
	var enemy:Node2D=unit("res://scenes/ball.tscn","WTEnemy","Team1",center+Vector2(45,-35))
	await process_frame
	hold(enemy);enemy.Max_health=100000;enemy.health=100000
	trader._invisibility_wait=999.0;trader._wall_wait=999.0;trader._milk_wait=999.0
	trader.Speed=0.0
	trader.item_show_time=999.0;trader.item_delay_min=999.0;trader.item_delay_max=999.0
	await seconds(0.6)
	var herd:Array=trader.living_llamas()
	for l:Node2D in herd:
		hold(l);l.Max_health=100000;l.health=100000;l.spit_range=0.0
	# --- frame with each item (close-up) -----------------------------------------------------------
	camera.global_position=trader.global_position+Vector2(0,10);camera.zoom=zoom0*2.4
	var n:int=0
	for kind:StringName in [CATALOG.GUNPOWDER,CATALOG.BLUE_ICE,CATALOG.PUFFERFISH,CATALOG.DRIPSTONE,CATALOG.SLIME_BALL,CATALOG.HAY,CATALOG.POTATO,CATALOG.CACTUS,CATALOG.TROPICAL_FISH]:
		trader.give_item(kind)
		await seconds(0.35)
		n+=1
		await grab("i%02d_frame_%s" % [n,kind])
	trader.give_item(&"")
	await seconds(0.3)
	await grab("i10_frame_empty")
	# --- wall entry / exit crumbs from the wall tiles ---------------------------------------------
	trader.Speed=80.0
	var near:Dictionary=WALLS.nearest_slot(WALLS.wall_slots(world,trader.mc_arena_rect()),trader.global_position)
	trader.direction=-(near.normal as Vector2).normalized()
	trader.start_wall_phase()
	var t:float=0.0
	while trader.wall_phase==0 and t<4.0:
		await physics_frame;t+=1.0/60.0
	camera.global_position=trader.wall_face_point(trader.entry_slot);camera.zoom=zoom0*2.4
	await seconds(0.12)
	await grab("i11_entry_crumbs")
	while trader.wall_phase!=3 and t<9.0:
		await physics_frame;t+=1.0/60.0
	camera.global_position=trader.wall_face_point(trader.exit_slot)
	await seconds(0.1)
	await grab("i12_exit_crumbs")
	await seconds(0.25)
	await grab("i12b_exit_crumbs_fall")
	while trader.wall_phase!=0 and t<10.0:
		await physics_frame;t+=1.0/60.0
	trader._wall_wait=999.0
	await seconds(0.2)
	camera.global_position=trader.global_position+Vector2(0,10)
	await grab("i13_frame_after_exit")
	trader.give_item(&"")
	trader.Speed=0.0;trader.direction=Vector2.ZERO
	trader.global_position=center+Vector2(-30,20)
	camera.global_position=center;camera.zoom=zoom0*1.4
	await seconds(0.3)
	# --- gunpowder -----------------------------------------------------------------------------------
	trader.item_delay_min=0.1;trader.item_delay_max=0.1;trader.item_show_time=0.1
	trader.give_item(CATALOG.GUNPOWDER)
	var cam_back:Vector2=camera.global_position
	camera.global_position=trader.global_position+Vector2(0,-6);camera.zoom=zoom0*3.0
	await seconds(0.2)
	await grab("i13b_swing_a")
	await seconds(0.12)
	await grab("i13c_swing_b")
	camera.global_position=cam_back;camera.zoom=zoom0*1.4
	await seconds(0.4)
	await grab("i14_gunpowder_placed")
	for gp:Node in get_nodes_in_group(&"MCWanderingTraderItem"):
		if gp.get(&"kind")==CATALOG.GUNPOWDER:enemy.global_position=(gp as Node2D).global_position
	await seconds(0.3)
	await grab("i15_gunpowder_fuse")
	for i:int in range(4):
		await seconds(0.12)
		await grab("i16_explosion_%d" % i)
	enemy.global_position=center+Vector2(45,-35)
	await seconds(0.8)
	# --- blue ice ------------------------------------------------------------------------------------
	trader.give_item(CATALOG.BLUE_ICE)
	await seconds(0.4)
	enemy.global_position=trader.global_position+Vector2(10,-4)
	await seconds(0.2)
	await grab("i17_blue_ice")
	enemy.global_position=center+Vector2(45,-35)
	# --- fish ------------------------------------------------------------------------------------------
	var puff:Node2D=trader.release_fish(true)
	var fish:Node2D=trader.release_fish(false)
	await seconds(0.25)
	await grab("i18_fish_released")
	await seconds(0.9)
	await grab("i19_fish_flopping")
	if is_instance_valid(puff):
		enemy.global_position=puff.global_position+Vector2(24,0)
		await seconds(0.5)
		camera.global_position=puff.global_position;camera.zoom=zoom0*2.4
		await grab("i20_puffer_puffed")
		camera.global_position=center;camera.zoom=zoom0*1.4
	enemy.global_position=center+Vector2(45,-35)
	await seconds(0.8)
	await grab("i21_fish_later")
	for f:Node in get_nodes_in_group(&"MCTraderFish"):f.take_damage(1e9)
	await seconds(1.5)
	# --- dripstone ------------------------------------------------------------------------------------
	trader.give_item(CATALOG.DRIPSTONE)
	trader.Speed=80.0
	near=WALLS.nearest_slot(WALLS.wall_slots(world,trader.mc_arena_rect()),trader.global_position)
	trader.direction=-(near.normal as Vector2).normalized()
	t=0.0
	while trader.held_item!=&"" and t<5.0:
		await physics_frame;t+=1.0/60.0
	trader.Speed=0.0;trader.direction=Vector2.ZERO
	trader.global_position=center+Vector2(-30,20)
	await seconds(0.1)
	for sp:Node in get_nodes_in_group(&"MCWanderingTraderItem"):
		if sp.get(&"kind")==CATALOG.DRIPSTONE:camera.global_position=(sp as Node2D).global_position
	camera.zoom=zoom0*2.4
	await grab("i22_dripstone")
	camera.global_position=center;camera.zoom=zoom0*1.4
	# --- slime ball ------------------------------------------------------------------------------------
	enemy.global_position=trader.global_position+Vector2(70,-20)
	trader.give_item(CATALOG.SLIME_BALL)
	await seconds(0.3)
	await grab("i23_slime_flight")
	await seconds(0.25)
	await grab("i24_slime_hit")
	trader._throw(CATALOG.SLIME_BALL,null,Vector2(rect.position.x-60.0,trader.global_position.y),0.5)
	await seconds(0.2)
	await grab("i25_slime_wall")
	await seconds(0.5)
	# --- hay -------------------------------------------------------------------------------------------
	var llama:Node2D=herd[1]
	llama.global_position=trader.global_position+Vector2(60,10)
	llama.health=llama.Max_health-300
	trader.give_item(CATALOG.HAY)
	await seconds(0.35)
	await grab("i26_hay_flight")
	await seconds(0.5)
	await grab("i27_hay_hearts")
	# --- potato ----------------------------------------------------------------------------------------
	trader.health=trader.Max_health-80
	trader.give_item(CATALOG.POTATO)
	await seconds(0.5)
	camera.global_position=trader.global_position;camera.zoom=zoom0*2.4
	await grab("i28_potato_eat")
	await seconds(0.8)
	camera.global_position=center;camera.zoom=zoom0*1.4
	# --- cactus ----------------------------------------------------------------------------------------
	trader.direction=Vector2.RIGHT
	trader.give_item(CATALOG.CACTUS)
	await seconds(0.5)
	trader.direction=Vector2.ZERO
	await grab("i29_cactus")
	for c:Node in get_nodes_in_group(&"MCWanderingTraderItem"):
		if c.get(&"kind")==CATALOG.CACTUS:
			var r:Rect2=c.rect()
			enemy.global_position=Vector2(r.position.x-CATALOG.body_rect(enemy).size.x*0.5,r.get_center().y)
	await seconds(0.15)
	await grab("i30_cactus_hit")
	print("WANDERING_TRADER_ITEMS_GPU checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
