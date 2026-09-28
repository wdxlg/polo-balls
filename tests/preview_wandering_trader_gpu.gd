extends "res://tests/test_sulfur_cube_balance.gd"
## GPU preview (GUI mode only): real World rendering of the 流浪商人 herd, leash sag/taut, yank,
## spit in flight, milk and potion drinking, wall entry/hidden/exit tell/exit with a returning llama. Screenshots go to
## WANDERING_TRADER_EVIDENCE_DIR (default user://wandering_trader_gpu).
var folder:String
var camera:Camera2D

func hold(u:Node) -> void:
	u.state_machine.set_physics_process(false);u.set_physics_process(false)
	u.Has_Collision_Damage=false;u.Can_Attack=false;u.Can_Skill=false

func unit(scene:String,n:String,team:String,pos:Vector2) -> Node2D:
	var u:Node2D=load(scene).instantiate();u.name=n;u.Team=team;u.position=pos
	if u.has_node("CharacterAutoFit"):u.get_node("CharacterAutoFit").enabled=false
	world.add_child(u,true)
	return u

func seconds(t:float) -> void:
	var left:float=t
	while left>0.0:
		await physics_frame;left-=1.0/60.0

func grab(label:String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	image.save_png(folder.path_join(label+".png"))
	return image

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Actual GPU renderer required"); quit(2); return
	create_timer(150.0,true,false,true).timeout.connect(func(): print("WT_GPU_TIMEOUT"); quit(2))
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
	var trader:Node2D=unit("res://scenes/characters/我的世界/流浪商人.tscn","WT","Team0",center+Vector2(-30,10))
	var enemy:Node2D=unit("res://scenes/ball.tscn","WTEnemy","Team1",center+Vector2(60,-30))
	await process_frame
	hold(enemy);enemy.Max_health=100000;enemy.health=100000
	hold(trader)
	trader._invisibility_wait=999.0;trader._wall_wait=999.0;trader._milk_wait=999.0
	await seconds(0.6)
	var herd:Array=trader.living_llamas()
	for l:Node2D in herd:l.Max_health=100000;l.health=100000;l._spit_wait=999.0
	check(herd.size()==2,"two llamas")
	var blank:Image=await grab("01_herd")
	check(blank.get_width()==1080,"screenshot size")
	# yank: move the trader away, grab while taut
	trader.global_position=center+Vector2(40,40)
	await seconds(0.12)
	await grab("02_yank_taut")
	await seconds(1.2)
	await grab("03_after_yank")
	# spit in flight
	var l0:Node2D=herd[0]
	l0.spit_at(enemy)
	await seconds(0.05)
	await grab("04a_spit_launch")
	await seconds(0.12)
	await grab("04_spit")
	await seconds(0.4)
	await grab("04b_spit_smoke_after")
	await seconds(0.6)
	# milk
	var POT:Script=load("res://scripts/effects/我的世界/女巫药水效果.gd")
	POT.apply_effect(trader,"slowness",enemy)
	trader._milk_wait=0.0
	trader.set_physics_process(true);trader.state_machine.set_physics_process(true)
	await seconds(0.55)
	await grab("05_milk")
	await seconds(1.0)
	trader.start_drink(&"invisibility")
	await seconds(0.45)
	await grab("06_potion")
	await seconds(0.6)
	await grab("07_invisible")
	await seconds(6.0)
	# A dead llama whose return cooldown is over walks out of the wall with him.
	(herd[1] as Node2D).take_damage(1e9)
	await seconds(0.2)
	trader._llama_return_wait[1]=0.0
	trader.start_wall_phase()
	# Close-up on the entry wall: the body is clipped on the wall surface, no fading.
	var zoom_before:Vector2=camera.zoom
	camera.global_position=trader.wall_face_point(trader.entry_slot);camera.zoom=zoom_before*2.2
	var t:float=0.0
	for label:String in ["08a_wall_entering","08b_wall_entering","08c_wall_entering"]:
		await seconds(maxf(trader._phase_duration*0.3,0.05))
		if trader.wall_phase==1:await grab(label)
	while trader.wall_phase!=2 and t<2.0:
		await physics_frame;t+=1.0/60.0
	await seconds(0.05)
	await grab("09_hidden")
	while trader.exit_warnings==0 and trader.wall_phase!=3 and t<6.0:
		await physics_frame;t+=1.0/60.0
	check(trader.exit_warnings==1,"exit tell fired")
	camera.global_position=trader.wall_face_point(trader.exit_slot)
	await seconds(0.12)
	await grab("09b_exit_tell")
	while trader.wall_phase!=3 and t<6.0:
		await physics_frame;t+=1.0/60.0
	for label:String in ["10a_emerging","10b_emerging","10c_emerging"]:
		await seconds(maxf(trader._phase_duration*0.28,0.05))
		if trader.wall_phase==3:await grab(label)
	while trader.wall_phase!=0 and t<8.0:
		await physics_frame;t+=1.0/60.0
	camera.global_position=center;camera.zoom=zoom_before
	await seconds(0.3)
	await grab("11_reconnected")
	check(trader.llamas_returned==1 and trader.living_llamas().size()==2,"llama came back with him")
	print("WANDERING_TRADER_GPU checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
