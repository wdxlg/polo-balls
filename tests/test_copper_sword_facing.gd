extends "res://tests/test_copper_sword.gd"
## Enemy-facing attacks must not steer locomotion or resurrect copper status text.
func finish_current_swing(unit:Node) -> void:
	var guard:int = 0
	while unit._swing_active and guard<1000:
		unit.advance_swing(1.0/120.0)
		guard += 1
	check(guard<1000,"enemy-facing swing completes")
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(75.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"facing-test preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	var target:Node2D = dummy(center+Vector2(-24,0))
	var friend:Node2D = dummy(center+Vector2(12,0),"Team0")
	await physics_frame
	await process_frame
	check(not has_copper_status(unit),"new copper sword has no rust/charge/combo text")
	unit.side_status_set_permanent("left","mc_copper_sword","legacy copper text",Color.WHITE)
	unit.side_status_set_permanent("left","fixture_other_status","other status",Color.WHITE)
	check(has_copper_status(unit),"legacy status label fixture exists")
	unit.visual_mob()
	check(not has_copper_status(unit),"render update removes already-existing copper status text")
	check(unit.side_status_ui._left_permanent_labels.has("fixture_other_status") and unit.health_bar!=null,"other status displays and normal health bar are preserved")
	unit.side_status_remove_permanent("left","fixture_other_status")
	for stage:float in [0.0,0.5,1.0]:
		unit.rust = stage
		unit.charged_left = 3.0
		unit.combo_hits = 4
		unit.visual_mob()
		check(not has_copper_status(unit),"rust/charge/combo cannot recreate text at rust="+str(stage))
	unit.rust = 0.0
	unit.charged_left = 0.0
	unit.reset_combo()
	unit.direction = Vector2.RIGHT
	unit._update_movement_facing()
	check(unit._face_right and unit._select_swing_target()==target,"rear enemy is selectable despite opposite movement facing")
	check(unit._face_right,"target probing does not prematurely turn the idle visual")
	var hp:float = target.health
	var friend_hp:float = friend.health
	unit.step_mob(0.01)
	check(unit._swing_active and not unit._face_right and unit.is_character_visual_flipped_h(),"AI automatically starts a left-facing attack against the rear enemy")
	check(unit.direction==Vector2.RIGHT and unit.velocity==Vector2.ZERO,"target facing does not rewrite movement direction or velocity")
	unit.velocity = Vector2(45,0)
	unit._update_movement_facing()
	check(not unit._face_right and unit.velocity==Vector2(45,0),"active attack facing is not overwritten by opposite movement")
	unit.charged_left = 3.0
	unit.visual_mob()
	unit.charge_visual.advance(0.05)
	check(unit.charge_visual.visible and unit.charge_visual.global_transform.determinant()<0.0,"charged trident overlay mirrors with enemy-facing swing")
	var replica:Node2D = copper(center+Vector2(300,200))
	replica.set_multiplayer_authority(2)
	replica.accept_visual(unit.network_visual_state())
	replica.visual_mob()
	check(replica._swing_active and replica.is_character_visual_flipped_h() and not has_copper_status(replica),"replica receives attack facing without status text")
	finish_current_swing(unit)
	check(is_equal_approx(hp-target.health,ceilf(unit.attack_damage())) and friend.health==friend_hp,"mirrored real hitbox damages rear enemy exactly once, never friendly decoy")
	check(unit._holding_pose and not unit._returning and not unit._face_right,"finished cut stays at endpoint for a continuous reverse cut")
	unit.cancel_swing()
	unit._advance_return(unit.return_duration)
	check(unit._face_right and not unit.is_character_visual_flipped_h(),"stopping quickly restores rightward movement facing")
	check(unit.combo_hits==1,"enemy-facing attack preserves combo progression")
	unit.velocity = Vector2.ZERO

	# Swap sides: the next swing uses the new target side, not the old lock.
	target.global_position = center+Vector2(24,0)
	unit.direction = Vector2.LEFT
	unit._update_movement_facing()
	await physics_frame
	await process_frame
	hp = target.health
	var next_down:bool = unit._next_swing_down
	check(unit.begin_swing() and unit._face_right and unit._swing_down==next_down,"next alternating swing turns toward right enemy while movement remains left")
	finish_current_swing(unit)
	unit.cancel_swing()
	unit._advance_return(unit.return_duration)
	check(target.health<hp and not unit._face_right and unit.direction==Vector2.LEFT,"right-facing hit lands and stopping restores leftward locomotion facing")

	# An enemy takes precedence over an opposite mouse aim, without changing WASD.
	unit.player_control_peer_id = 1
	unit.player_control_direction = Vector2.LEFT
	unit.player_control_aim_valid = true
	unit.player_control_aim_position = center+Vector2(-200,0)
	unit.player_control_action(0)
	check(unit._swing_active and unit._face_right and unit.player_control_direction==Vector2.LEFT,"manual attack turns to enemy rather than opposite movement/mouse")
	unit.cancel_swing()
	check(unit._returning,"interrupted swing begins fast recovery rather than snapping")
	unit._advance_return(unit.return_duration)
	check(not unit._face_right,"quick recovery releases the facing lock")
	unit.player_control_peer_id = 0

	# Damage geometry, not proximity alone: a wall-obstructed enemy is not selectable.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(3,90)
	shape.shape = rectangle
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(10,0)
	await physics_frame
	await process_frame
	check(unit._select_swing_target()==null and not unit._has_swing_target(),"turning toward enemies does not bypass wall occlusion")
	wall.queue_free()
	await process_frame
	print("COPPER_SWORD_FACING checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
