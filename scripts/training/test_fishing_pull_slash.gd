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
	rod._sword_left=0
	rod.direction=Vector2.RIGHT
	var victim:Node2D=spawn("",Vector2(140,0),"Team1")
	victim.health=10000
	victim.block=0
	victim.Damage_reduction=0
	rod.hooked=victim
	rod.hook_point=victim.global_position
	rod.hook_mode=2
	rod.pull_hook()
	check(rod._pull_slash_target==null and rod._pull_slash_active,"retrieval immediately swings even with victim far away")
	check(rod.sword_pose==rod.SWORD_DURATION and rod.direction==Vector2.LEFT,"retrieval immediately leaves sword and retreats")
	victim.global_position=center+Vector2(36,0)
	rod.step_pull_slash(0.01)
	check(rod._pull_slash_active and rod.sword_pose==rod.SWORD_DURATION,"arrival starts world-fixed swing")
	check(rod._sword_facing.is_equal_approx(Vector2.RIGHT),"sword aims at pulled victim")
	var before:Vector2=rod.global_position
	rod.Repel=Vector2.ZERO
	rod._crowd_separation_velocity=Vector2(20,0)
	rod.move(rod.Speed,0.02)
	check(rod.global_position.x<before.x,"retreat moves immediately during the swing")
	var hilt:Vector2=rod.sword_hilt()
	rod.global_position+=Vector2(-20,0)
	rod.visual_mob()
	check(rod.sword_hilt()==hilt and rod.sword.global_position==hilt,"moving caster leaves blade at the original world position")
	rod._process(0.03)
	check(rod._sword_trails.size()>0,"sword emits pixel afterimages")
	var trail:Sprite2D=rod._sword_trails.back().sprite
	var trail_point:Vector2=trail.global_position
	rod.global_position+=Vector2(-10,0)
	rod._process(0.03)
	check(trail.global_position==trail_point and trail.modulate.a<0.38,"afterimage stays in world space and fades")
	var hp:float=victim.health
	rod.advance_sword(0.13)
	check(is_equal_approx(hp-victim.health,45.0),"stationary combo still uses real blade hit for forty-five damage")
	check(rod._pull_slash_active and rod.direction==Vector2.LEFT,"retreat is already active before swing finishes")
	rod.advance_sword(0.13)
	check(not rod._pull_slash_active and rod.direction.is_equal_approx(Vector2.LEFT),"swing completion reverses movement away from victim")
	check(rod._retreat_left>0,"retreat has short attack-free window")
	rod._crowd_separation_velocity=Vector2.ZERO
	rod.move(rod.Speed,0.02)
	check(rod.global_position.x<before.x,"retreat uses actual backward movement")
	rod.step_mob(0.01)
	check(rod.sword_pose==0,"retreat does not immediately start another sword attack")
	rod._sword_left=0
	rod._pull_slash_target=victim
	rod._pull_slash_wait=2.0
	victim.global_position=rod.global_position+Vector2(36,0)
	rod.step_pull_slash(0.01)
	hp=victim.health
	victim.global_position=center+Vector2(160,0)
	rod.advance_sword(0.26)
	check(victim.health==hp,"pulled victim can still dodge the stationary swing")
	rod._return_hits.clear()
	rod._return_hit(victim)
	check(not rod._pull_slash_active,"same retrieval cannot trigger another slash after first finishes")
	rod._sword_left=0
	rod._pull_slash_target=victim
	rod._pull_slash_wait=2.0
	rod.dizziness=true
	rod.step_mob(0.01)
	check(rod._pull_slash_target==null and not rod._pull_slash_active,"stun cancels queued combo")
	rod.dizziness=false
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
