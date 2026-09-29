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
	var victim:Node2D=spawn("",Vector2(120,0),"Team1")
	victim.health=10000
	victim.block=0
	check(rod.try_start_sword(Vector2.RIGHT,false),"normal sword starts when ready")
	rod.advance_sword(0.05)
	var pose:float=rod.sword_pose
	var cooldown:float=rod._sword_left
	var origin:Vector2=rod._sword_origin
	rod._sword_hits[123]=true
	rod.hook_mode=2
	rod.hooked=victim
	rod.hook_point=victim.global_position
	rod.pull_hook()
	check(rod.sword_pose==pose and rod._sword_origin==origin,"reel does not overwrite active normal sword")
	check(rod._sword_hits.has(123),"reel cannot reset hit deduplication")
	check(rod._sword_left==cooldown,"reel does not refresh shared cooldown")
	check(rod.direction==Vector2.LEFT and rod.hook_mode==4,"reel still pulls and retreats while sword unavailable")
	check(rod._pull_slash_target==null,"blocked reel sword is not queued")
	rod.advance_sword(0.3)
	check(not rod.try_start_sword(Vector2.RIGHT,true),"finished animation still respects shared cooldown")
	rod._sword_left=0
	check(rod.try_start_sword(Vector2.RIGHT,true),"reel sword starts after cooldown")
	check(not rod.try_start_sword(Vector2.LEFT,false),"normal sword cannot overlap reel sword")
	rod.advance_sword(0.3)
	check(not rod.try_start_sword(Vector2.LEFT,false),"normal sword remains blocked by reel cooldown")
	rod._sword_left=0
	check(rod.try_start_sword(Vector2.LEFT,false),"normal sword resumes when shared cooldown finishes")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
