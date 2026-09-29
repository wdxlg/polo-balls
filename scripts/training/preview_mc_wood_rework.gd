extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()+Vector2(0,-80)
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<world._mc_prewarmer.CHARACTERS.size(): await process_frame
	world.set_process(false)
	world.set_physics_process(false)
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=center
	camera.zoom=Vector2(3.0,3.0)
	camera.make_current()
	camera.force_update_scroll()
	var sword:Node2D=spawn("木剑",Vector2.ZERO)
	var enemies:Array[Node2D]=[]
	for sign_value:float in [-1.0,1.0]:
		var enemy:Node2D=spawn("骷髅",Vector2(0,sign_value*78),"Team1")
		enemy.Max_health=10000
		enemy.health=10000
		enemy.Can_Attack=false
		enemies.append(enemy)
	var label:=Label.new()
	label.text="WOOD SWORD  /  50 DURABILITY"
	label.position=Vector2(20,120)
	label.add_theme_font_size_override("font_size",25)
	var hud:=CanvasLayer.new()
	root.add_child(hud)
	hud.add_child(label)
	DirAccess.make_dir_recursive_absolute("user://mc_wood_preview")
	var bench:Node2D
	for index:int in range(32):
		if index==3:
			sword.spend_durability(50)
			await process_frame
			bench=sword.workbench
			sword.state_machine.set_physics_process(true)
			label.text="BROKEN: HILT SWING + BLADE THRUST"
		if index==14:
			label.text="STAGED CONTACT / HEAL + 50% REDUCTION"
			for enemy:Node2D in enemies: enemy.queue_free()
			for piece:Node2D in bench.living_pieces():
				piece.dock_delay=0
				piece.global_position=bench.global_position+Vector2(-10 if piece==sword else 10,0)
				piece.Repel=Vector2.ZERO
				piece.velocity=Vector2.ZERO
				piece.set_migrated_health(180,piece.Max_health)
		if index>14 and sword.part_kind==0:
			label.text="REPAIRED / 50 DURABILITY"
			sword.state_machine.set_physics_process(false)
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://mc_wood_preview/frame_%02d.png"%index)
	check(sword.successful_repairs==1 and sword.durability==50,"real physics completes staged-contact repair once")
	print("WOOD_PREVIEW ",ProjectSettings.globalize_path("user://mc_wood_preview"))
	finish(0 if failures==0 else 1)
