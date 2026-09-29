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
	var rod:Node2D=spawn("钓鱼竿",Vector2.ZERO,"Team0")
	rod._cast_left=999
	rod._sword_left=999
	var victim:Node2D=spawn("",Vector2(120,0),"Team1")
	victim.health=10000
	victim.block=0
	victim.Damage_reduction=0
	rod.hook_mode=3
	rod.hook_point=victim.global_position
	rod._rest_left=0.5
	var hp:float=victim.health
	rod.step_mob(0.01)
	check(rod.hook_mode==2 and rod.hooked==victim,"touching resting bait attaches")
	check(victim.health==hp,"resting bait attachment deals no damage")
	rod.pull_hook()
	check(rod.hook_mode==4 and is_equal_approx(hp-victim.health,10.0),"reeling attached victim deals exactly ten damage and pulls")
	rod.break_line()
	rod.hook_mode=3
	rod._rest_left=0.5
	rod.hook_point=center+Vector2(180,100)
	rod.step_mob(0.01)
	check(rod.hook_mode==3,"empty bait remains resting")
	rod._rest_left=0.001
	rod.step_mob(0.02)
	check(rod.hook_mode==4,"empty ground dwell still retracts normally")
	rod.hook_mode=3
	rod._rest_left=0.5
	rod.hook_point=victim.global_position
	victim.Team="Team0"
	rod.step_mob(0.01)
	check(rod.hook_mode==3,"teammate does not attach to ground bait")
	victim.Team="Team1"
	rod.facing=Vector2.LEFT
	rod.visual_mob()
	check(rod.is_character_visual_flipped_h(),"left view uses effective shader-aware flip")
	check(rod.rope.points[0].is_equal_approx(rod.image.to_global(Vector2(-6,-6))),"left rope begins at mirrored rod tip")
	rod.facing=Vector2.RIGHT
	rod.visual_mob()
	check(rod.rope.points[0].is_equal_approx(rod.image.to_global(Vector2(6,-6))),"right rope begins at original rod tip")
	await clear_units()
	rod=spawn("钓鱼竿",Vector2.ZERO,"Team0")
	rod._cast_left=999
	victim=spawn("",Vector2(40,0),"Team1")
	victim.health=10000
	victim.block=0
	victim.Damage_reduction=0
	hp=victim.health
	rod.step_mob(0.001)
	check(rod.sword_pose>0 and victim.health==hp,"starting sword animation does not automatically deal damage")
	rod.advance_sword(0.13)
	check(is_equal_approx(hp-victim.health,45.0),"sweeping sword deals exactly forty-five damage")
	var after:float=victim.health
	rod.advance_sword(0.1)
	check(victim.health==after,"one swing cannot damage same victim twice")
	rod.sword_pose=0.13
	rod.visual_mob()
	var tip:Vector2=rod.sword.to_global(Vector2(6.5,-6.5)+rod.sword.offset)
	check(tip.is_equal_approx(rod.sword_segment(rod.sword_pose)[1]),"collision blade matches visible sword tip")
	rod.sword_pose=0
	rod._sword_left=0
	victim.global_position=center+Vector2(40,0)
	rod.step_mob(0.001)
	hp=victim.health
	victim.global_position=center+Vector2(150,0)
	rod.advance_sword(0.26)
	check(victim.health==hp,"victim can dodge after swing starts")
	rod.sword_pose=0
	rod._sword_left=0
	victim.global_position=center+Vector2(40,0)
	rod.step_mob(0.001)
	hp=victim.health
	var wall:StaticBody2D=obstacle(Vector2(25,0),true)
	await physics_frame
	rod.advance_sword(0.26)
	check(victim.health==hp,"swing cannot damage through wall")
	wall.queue_free()
	await clear_units()
	rod=spawn("钓鱼竿",Vector2.ZERO,"Team0")
	rod._sword_left=999
	rod._cast_left=999
	victim=spawn("",Vector2(120,0),"Team1")
	victim.health=10000
	victim.block=0
	victim.Damage_reduction=0
	rod.cast_at(victim.global_position)
	rod.hook_point=victim.global_position
	rod._cast_origin=victim.global_position
	rod._cast_target=victim.global_position
	rod._arc_height=0
	rod.AUDIO._last.erase("entity.player.hurt")
	hp=victim.health
	rod.step_mob(0.01)
	check(rod.hook_mode==2 and is_equal_approx(hp-victim.health,20.0),"airborne hook deals exactly twenty damage")
	var has_mc_hit:bool=false
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if sound.get_meta("mc_sound_event","")=="entity.player.hurt": has_mc_hit=true
	check(has_mc_hit,"damaging hook plays MC hurt sound")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
