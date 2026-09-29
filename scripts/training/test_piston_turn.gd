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
	var piston:Node2D=spawn("粘性活塞",Vector2.ZERO,"Team0")
	piston.facing=Vector2.RIGHT
	piston._turn_target=Vector2.RIGHT
	piston.direction=Vector2.UP
	piston.step_mob(0.02)
	check(piston.facing.x>0.0 and piston.facing.y<0.0,"quarter turn frame interpolates instead of snapping")
	check(piston.direction==Vector2.UP,"physical movement direction remains unchanged")
	piston.visual_mob()
	check(is_equal_approx(piston.image.rotation,piston.facing.angle()),"case follows smooth facing")
	check(is_equal_approx(piston.weapon.global_rotation,piston.facing.angle()),"head and rod follow smooth facing")
	var target:Node2D=spawn("",Vector2(180,0),"Team1")
	var anchor:Vector2=piston.sticky_anchor(target)-piston.global_position
	check(anchor.normalized().is_equal_approx(piston.facing),"sticky anchor uses same smooth facing")
	piston.step_mob(0.02)
	check(is_equal_approx(piston.facing.angle(),-PI/4),"halfway uses spear style smoothstep")
	piston.step_mob(0.04)
	check(piston.facing.is_equal_approx(Vector2.UP) and not piston._turn_active,"turn completes in eighty ms")
	piston.request_turn(Vector2.LEFT)
	piston.advance_turn(0.02)
	var before:Vector2=piston.facing
	piston.request_turn(Vector2.DOWN)
	check(piston.facing==before,"mid-turn retarget starts from current angle")
	piston.advance_turn(0.08)
	check(piston.facing.is_equal_approx(Vector2.DOWN),"mid-turn retarget completes")
	piston.facing=Vector2.RIGHT.rotated(deg_to_rad(179))
	piston._turn_target=piston.facing
	piston.request_turn(Vector2.RIGHT.rotated(deg_to_rad(-170)))
	piston.advance_turn(0.04)
	check(absf(piston.facing.angle())>3.0,"wrap boundary takes shortest arc")
	before=piston.facing
	game.now_stop_state=true
	piston.advance_turn(0.1)
	check(piston.facing==before,"pause freezes turning")
	game.now_stop_state=false
	piston.advance_turn(0.08)
	piston.accept_visual({"facing":Vector2.RIGHT})
	piston.accept_visual({"facing":Vector2.UP})
	check(piston.facing==Vector2.RIGHT,"subsequent network facing does not snap")
	piston.client_visual_step(0.04)
	check(is_equal_approx(piston.facing.angle(),-PI/4),"client interpolates network turn")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
