extends "res://scripts/training/test_mc_new5.gd"

func tick_actor(slime:Node2D,delta:float,effect:Node=null) -> void:
	# Drive the actual shared tick dispatch: dizziness redirects Move to Stand.
	slime.tick_physics(slime.State.Move,delta)
	if is_instance_valid(effect) and not effect._finished: effect._physics_process(delta)

func start_jump(slime:Node2D,fraction:float) -> void:
	slime.direction=Vector2.RIGHT
	slime.rest_left=0.0
	slime.step_mob(0.001)
	while slime.jump_elapsed<slime.jump_duration*fraction:
		await physics_frame
		tick_actor(slime,slime.get_physics_process_delta_time())

func run() -> void:
	game=root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("slime_mobile_settings.json")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	Engine.time_scale=1.0
	AudioServer.set_bus_mute(0,true)
	create_timer(90,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.5).timeout
	world.set_physics_process(false)
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	for stage:int in range(3):
		for fraction:float in [0.15,0.5,0.85]:
			await clear_units()
			var unit:Node2D=spawn(["史莱姆","史莱姆_中","史莱姆_小"][stage],Vector2.ZERO,"Team0","characters" if stage==0 else "creatures")
			unit.get_body_motion().set_physics_process(false)
			await start_jump(unit,fraction)
			var natural_x:float=unit.global_position.x+unit.jump_direction.x*unit._jump_remaining
			var force:Node=unit.apply_knockback(Vector2.LEFT,45,180)
			force.set_physics_process(false)
			check(unit.airborne and not unit.dizziness,"ordinary force preserves mobile flight stage="+str(stage)+" phase="+str(fraction))
			var continuous:bool=true;var coherent:bool=true;var progressed:bool=false
			for frame:int in range(120):
				await physics_frame
				var dt:float=unit.get_physics_process_delta_time()
				var from:Vector2=unit.global_position
				var old_phase:float=unit.jump_elapsed
				var bound:float=(4.0*unit.jump_height/unit.jump_duration+1.5*unit.jump_distance/unit.jump_duration+unit.get_body_motion().impulse_velocity().length())*dt+0.5
				tick_actor(unit,dt,force if is_instance_valid(force) else null)
				continuous=continuous and unit.global_position.distance_to(from)<=bound
				progressed=progressed or unit.jump_elapsed>old_phase
				coherent=coherent and unit.collision_shape_2d.global_position.is_equal_approx(unit.global_position)
				if not unit.airborne:break
			check(progressed and not unit.airborne,"ordinary knockback never pauses or restarts jump time")
			check(continuous and coherent,"body and collider follow a continuous combined arc")
			check(unit.global_position.x<natural_x-0.5 and unit.global_position.x>natural_x-50,"external impulse adds displacement instead of replacing voluntary jump")
			check(absf(unit.global_position.y-center.y)<0.1 and is_zero_approx(unit._jump_lift),"natural landing consumes all ballistic lift")
			if is_instance_valid(force):force._finish(false)
			var landing:Vector2=unit.global_position
			await physics_frame
			tick_actor(unit,unit.get_physics_process_delta_time())
			check(unit.global_position.distance_to(landing)<0.1,"ending force after landing cannot replay old motor or arc displacement")
	var slime:Node2D
	var effect:Node
	var smooth:bool
	var dt:float
	var before:Vector2
	# Golem flight moves the body directly, instead of writing ordinary Repel.
	await clear_units()
	slime=spawn("史莱姆",Vector2.ZERO)
	var golem:Node2D=spawn("铁傀儡",Vector2(300,300),"Team1")
	await start_jump(slime,0.35)
	effect=golem.launch_target(slime,55.0,260.0,Vector2.UP)
	effect.set_physics_process(false)
	smooth=true
	var saw_landing:bool=false
	for frame:int in range(220):
		await physics_frame
		dt=slime.get_physics_process_delta_time()
		before=slime.global_position
		var external_speed:float=absf(effect._vertical_speed) if is_instance_valid(effect) and not effect.landed else 0.0
		var bound:float=(4.0*slime.jump_height/slime.jump_duration+external_speed+40.0)*dt+0.5
		tick_actor(slime,dt,effect if is_instance_valid(effect) else null)
		smooth=smooth and slime.global_position.distance_to(before)<=bound
		if is_instance_valid(effect): saw_landing=saw_landing or effect.landed
		if not slime.dizziness and not slime.airborne: break
	before=slime.global_position
	await physics_frame
	tick_actor(slime,slime.get_physics_process_delta_time())
	check(smooth and saw_landing and not slime.dizziness,"real golem physical launch coexists with continuous slime arc consumption")
	check(not slime.airborne and slime.global_position.distance_to(before)<0.1 and not slime.has_meta("golem_air_height"),"golem recovery cannot snap a slime back to its old jump position")
	slime.rest_left=0.0
	slime.step_mob(0.001)
	check(slime.airborne and slime.global_position.is_equal_approx(before),"next jump starts at the retained current position, without a stored origin reset")
	print("SLIME_KNOCKBACK_CONTINUITY checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
