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
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	for stage:int in range(3):
		var slime:Node2D=spawn(["史莱姆","史莱姆_中","史莱姆_小"][stage],Vector2.ZERO,"Team0","characters" if stage==0 else "creatures")
		var target:Node2D=spawn("",Vector2.ZERO,"Team1")
		var touching:float=u.radius(slime)+u.radius(target)+2.0
		target.global_position=center+Vector2(touching+5,0)
		slime.plan_jump(Vector2.RIGHT)
		var near:float=slime.jump_distance
		check(near<=6,"face-to-face enemy causes tiny hop")
		target.global_position=center+Vector2(touching+slime.jump_max_distance*0.65,0)
		slime.plan_jump(Vector2.RIGHT)
		var middle:float=slime.jump_distance
		check(middle>near and middle<slime.jump_max_distance,"middle distance changes landing")
		target.global_position=center+Vector2(touching+slime.jump_max_distance*1.5,0)
		slime.plan_jump(Vector2.RIGHT)
		check(is_equal_approx(slime.jump_distance,slime.jump_max_distance),"far enemy capped at max jump")
		target.global_position=center+Vector2(-touching-10,0)
		slime.plan_jump(Vector2.RIGHT)
		var normal:float=slime.jump_distance
		target.global_position=center+Vector2(touching+5,slime.jump_max_distance*2)
		slime.plan_jump(Vector2.RIGHT)
		check(is_equal_approx(normal,slime.jump_distance),"off-route and rear enemies ignored")
		target.global_position=center+Vector2(touching+5,0)
		target.Team="Team0"
		slime.plan_jump(Vector2.RIGHT)
		check(is_equal_approx(normal,slime.jump_distance),"friendly unit ignored")
		check(not slime.motion_blur_enabled and slime.AfterImage_Speed<0,"no smear or afterimage")
		slime._set_motion_blur_values(Vector2.RIGHT,900,0.1)
		check(not is_instance_valid(slime._motion_blur_ghost) or not slime._motion_blur_ghost.visible,"blur layer stays hidden at speed")
		check(slime.body_stretch(false,0.9)==0.55 and slime.body_stretch(false,1.0)==0.55,"visible preload and compressed hold")
		check(slime.body_stretch(true,0.0)==0.55,"launch begins compressed")
		var before_height:float=slime.jump_height
		var fast:float=slime.body_stretch(true,0.22)
		slime.jump_height*=0.1
		var slow:float=slime.body_stretch(true,0.22)
		check(fast>slow,"shape responds to actual ballistic speed parameters")
		slime.jump_height=before_height
		check(slime.body_stretch(true,0.2)>1.2,"airborne body becomes tall")
		check(is_equal_approx(slime.body_stretch(true,1),slime.body_stretch(false,0)),"landing continuous")
		# Real physics frames: speed modifiers may shorten duration, never exceed range.
		target.global_position=center+Vector2(0,300)
		slime.Speed*=3
		slime.direction=Vector2.RIGHT
		slime.rest_left=0
		slime.step_mob(0.001)
		var origin:Vector2=slime.global_position
		var budget:float=slime.jump_distance
		for i:int in range(100):
			await physics_frame
			if not slime.airborne: break
			var dt:float=slime.get_physics_process_delta_time()
			slime.move(slime.Speed,dt)
			slime.step_mob(dt)
		check(slime.global_position.distance_to(origin)<=budget+1.0,"speed buff cannot exceed planned landing range")
		print("JUMP_MEASURE stage=",stage," moved=",slime.global_position.distance_to(origin)," budget=",budget)
		check(slime.global_position.distance_to(origin)>budget*0.75,"adaptive jump really moves")
		# Repeated jumps after effects expire must retain typed array storage.
		slime.clear_jump_fx()
		for cycle:int in range(3):
			slime.emit_jump_fx(false)
			check(slime._jump_fx_nodes.is_typed(),"FX registry retains its typed storage")
			check(slime._jump_fx_nodes.size()==1,"expired references pruned on next jump")
			await create_timer(0.85).timeout
			check(not is_instance_valid(slime._jump_fx_nodes[0]),"effect expires naturally before next jump")
		slime.emit_jump_fx(true)
		var queued:Node=slime._jump_fx_nodes.back()
		queued.queue_free()
		slime.emit_jump_fx(false)
		check(slime._jump_fx_nodes.size()==1,"queued references also pruned")
		slime.clear_jump_fx()
		# Clear only owner's effects, including battle-end pause and late RPC.
		slime.emit_jump_fx(true)
		var fx:Node=slime._jump_fx_nodes.back()
		var other:Node2D=spawn("史莱姆",Vector2(0,120),"Team0")
		other.emit_jump_fx(true)
		var other_fx:Node=other._jump_fx_nodes.back()
		slime.clear_jump_fx()
		check(fx.is_queued_for_deletion() and not fx.visible,"owned FX immediately hidden and queued")
		check(not other_fx.is_queued_for_deletion(),"other slime FX preserved")
		slime.emit_jump_fx(true)
		fx=slime._jump_fx_nodes.back()
		slime.health=0
		game.now_stop_state=true
		fx._process(0)
		check(fx.is_queued_for_deletion() and not fx.visible,"dead owner cleanup runs before pause guard")
		slime._jump_fx(center,true,stage,7)
		check(slime._jump_fx_nodes.size()==1,"late jump FX RPC rejected after death")
		game.now_stop_state=false
		slime.Die()
		check(slime._jump_fx_nodes.is_empty(),"Die clears effect registry")
		await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
