extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(60).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	world.camera_2d.global_position=center
	world.camera_2d.zoom=Vector2(1.9,1.9)
	world.camera_2d.reset_smoothing()
	var start:int=Time.get_ticks_msec()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<13: await process_frame
	print("NEW5_ALL_PREWARM_MS ",Time.get_ticks_msec()-start)
	for role:String in ["史莱姆","守卫者","恶魂","粘性活塞","钓鱼竿"]:
		check(world._mc_prewarmer.is_ready(role),role+" prepared")
		var path:String="res://scenes/characters/我的世界/"+role+".tscn"
		var registered:bool=false
		for i:int in world.spawner.get_spawnable_scene_count():
			if world.spawner.get_spawnable_scene(i)==path: registered=true
		check(registered,role+" exact spawner path")
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	var roles:Array[String]=["史莱姆","守卫者","恶魂","粘性活塞","钓鱼竿"]
	var actors:Array[Node2D]=[]
	var victims:Array[Node2D]=[]
	for i:int in range(5):
		var y:float=(i-2)*95.0
		var t:int=Time.get_ticks_usec()
		var actor:Node2D=spawn(roles[i],Vector2(-115,y))
		print("NEW5_FIRST_READY_MS ",roles[i]," ",(Time.get_ticks_usec()-t)/1000.0)
		var victim:Node2D=spawn("",Vector2(-115+[42,80,170,65,135][i],y),"Team1")
		victim.health=10000
		victim.Damage=0
		actor.direction=Vector2.RIGHT
		actor.state_machine.set_physics_process(true)
		actors.append(actor)
		victims.append(victim)
	var p0:Vector2=actors[0].global_position
	var p2:Vector2=actors[2].global_position
	await create_timer(1.25).timeout
	check(actors[0].global_position.distance_to(p0)>3,"slime moves through real state machine")
	check(actors[2].global_position.distance_to(p2)>3,"ghast actually floats")
	for actor:Node2D in actors: check(actor.clock>0.5,str(actor.name)+" physics clock advances")
	# Visual snapshot with actual registered resources and active connected mechanics.
	for actor:Node2D in actors: actor.state_machine.set_physics_process(false)
	for i:int in range(5):
		actors[i].global_position=center+Vector2(-115,(i-2)*95)
		victims[i].global_position=center+Vector2(-115+[42,80,170,65,135][i],(i-2)*95)
	actors[1].dizziness=false
	actors[1].step_mob(0.01)
	actors[3].facing=Vector2.RIGHT
	actors[3].extension=40
	actors[4].hook_mode=2
	actors[4].hook_point=victims[4].global_position
	actors[4].hooked=victims[4]
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://mc_new5_preview.png")
	print("NEW5_SCREENSHOT ",ProjectSettings.globalize_path("user://mc_new5_preview.png"))
	# Same collision RID contains both exterior and interior pieces. Passing its
	# border must not exclude its internal wall from the remaining ray.
	var rect:Rect2=world.return_map_world_rect(world.map_group["Map50x50"])
	var edge:Vector2=Vector2(rect.position.x,rect.get_center().y)
	var projectile:Node2D=actors[2].fire_at(edge)
	projectile.state_machine.set_physics_process(false)
	projectile.global_position=edge-Vector2(70,0)
	var body:=StaticBody2D.new()
	body.name="SharedRIDWall"
	body.collision_layer=1
	body.collision_mask=0
	for x:float in [-4.0,44.0]:
		var shape:=CollisionShape2D.new()
		var box:=RectangleShape2D.new()
		box.size=Vector2(8,70)
		shape.shape=box
		shape.position=edge+Vector2(x,0)
		body.add_child(shape)
	world.add_child(body)
	await physics_frame
	var hit:Dictionary=u.trace(projectile,edge-Vector2(70,0),edge+Vector2(90,0),true,false)
	check(hit.get("collider")==body and hit.get("position",Vector2.ZERO).x>edge.x+30,"boundary pass preserves same-RID interior wall")
	body.queue_free()
	actors[2].global_position=edge-Vector2(25,0)
	world.camera_2d.global_position=edge+Vector2(20,0)
	await create_timer(0.3).timeout
	check(is_instance_valid(actors[2]) and actors[2].health>0,"ghast survives outside safety system")
	check(actors[2].global_position.x<rect.position.x,"ghast not rescued back into map")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://mc_new5_outside.png")
	print("NEW5_OUTSIDE ",ProjectSettings.globalize_path("user://mc_new5_outside.png"))
	# Verify real death transition creates two live children before removal.
	var slime:Node2D=actors[0]
	slime.state_machine.set_physics_process(true)
	slime.health=0
	await create_timer(0.12).timeout
	var medium_count:int=0
	for node:Node in get_nodes_in_group("Ball"):
		if node.get_script().resource_path.ends_with("/new5/slime.gd") and node.slime_stage==1: medium_count+=1
	check(medium_count==2,"actual death transition produces exactly two medium slimes")
	await clear_units()
	finish(0 if failures==0 else 1)
