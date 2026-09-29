extends "res://tests/test_allay_extended.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.Game_Settings.Map_Background="blue"
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var allay:Node=spawn("res://scenes/characters/我的世界/悦灵.tscn",center,"Team0")
	freeze(allay)
	allay.process_mode=Node.PROCESS_MODE_DISABLED
	check(allay.notes==0 and is_equal_approx(allay._generate_left,1.5),"new battle starts empty with 1.5 second first-note wait")
	for record:Array in [[0.0,4,1.5],[2.59,4,1.5],[2.6,5,1.35],[5.2,6,1.2],[7.8,7,1.05],[18.2,11,0.45],[20.8,12,0.3],[41.6,20,0.3],[3600.0,20,0.3]]:
		allay.clock=record[0]
		check(allay.current_note_capacity()==record[1],"capacity at battle second "+str(record[0]))
		check(is_equal_approx(allay.current_note_interval(),record[2]),"interval at battle second "+str(record[0]))
	allay.clock=0.0; allay._note_growth_stage=0
	allay.step_mob(1.49)
	check(allay.notes==0,"no immediate/free first note")
	allay.step_mob(0.02)
	check(allay.notes==1,"first note generated after 1.5 seconds")
	for i:int in range(10): allay.step_mob(1.5)
	check(allay.notes==4,"initial real generation capped at four")
	allay._generate_left=0.75
	allay.clock=2.6
	allay._update_note_growth()
	check(is_equal_approx(allay._generate_left,0.675),"growth preserves half-complete production cycle")
	check(allay.notes==4,"capacity upgrade itself does not grant a note")
	allay.step_mob(0.68)
	check(allay.notes==5,"fifth note can be generated after first upgrade")
	allay.clock=41.6
	for i:int in range(30): allay.step_mob(0.31)
	check(allay.notes==20,"late battle generation fills twenty slots without overflow")
	check(allay.cube_capacity==8,"blue cube capacity unchanged")
	var previous_clock:float=allay.clock
	var previous_timer:float=allay._generate_left
	game.now_stop_state=true
	allay.tick_physics(0,100.0)
	check(allay.clock==previous_clock and allay._generate_left==previous_timer,"game pause freezes combat growth and generation")
	game.now_stop_state=false
	paused=true
	allay.tick_physics(0,100.0)
	check(allay.clock==previous_clock and allay._generate_left==previous_timer,"tree pause freezes combat growth and generation")
	paused=false
	allay.clock=2.59; allay._note_growth_stage=0; allay._generate_left=1.5
	allay.dizziness=true
	allay.tick_physics(0,0.02)
	check(allay.current_note_capacity()==5 and allay._note_growth_stage==1,"combat growth continues while stunned")
	allay.dizziness=false
	var fresh:Node=spawn("res://scenes/characters/我的世界/悦灵.tscn",center,"Team0")
	fresh.process_mode=Node.PROCESS_MODE_DISABLED
	check(fresh.clock==0.0 and fresh.current_note_capacity()==4 and is_equal_approx(fresh.current_note_interval(),1.5),"new instance/battle does not inherit previous growth")
	check(allay.note_capacity==4 and allay.note_interval==1.5,"growth does not mutate base configuration")
	allay.queue_free(); fresh.queue_free()
	await create_timer(0.2).timeout
	print("ALLAY_GROWTH_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
