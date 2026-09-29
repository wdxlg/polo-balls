extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	await physics_frame
	moss.set_player_control_peer(0)
	moss.direction = Vector2.RIGHT
	moss.visual_mob()
	check(moss._face_right and moss._visual_facing_flipped_h==moss.dir_left,"AI right movement uses configured native orientation")
	moss.direction = Vector2.LEFT
	moss.visual_mob()
	check(not moss._face_right and moss._visual_facing_flipped_h!=moss.dir_left,"AI left movement mirrors the body")
	moss.direction = Vector2.UP
	moss.visual_mob()
	check(not moss._face_right,"vertical movement retains last horizontal facing")
	moss.set_player_control_peer(1)
	moss.direction = Vector2.LEFT
	moss.player_control_direction = Vector2.RIGHT
	moss.visual_mob()
	check(moss._face_right,"direct control follows movement input instead of stale AI direction")
	moss.player_control_direction = Vector2.ZERO
	moss.visual_mob()
	check(moss._face_right,"standing still preserves facing")
	moss.player_control_direction = Vector2.LEFT
	moss.visual_mob()
	check(not moss._face_right,"direct control can turn left")
	moss._moss_pose_phase = "plant"
	moss._moss_pose_started = moss.clock
	moss.clock += moss.placement_shrink_time*0.5
	moss.visual_mob()
	var shrink_scale:Vector2 = moss.image.scale
	moss.player_control_direction = Vector2.RIGHT
	moss.visual_mob()
	check(moss._face_right and moss.image.scale.is_equal_approx(shrink_scale),"turning during shrink does not overwrite animated scale")
	check(moss.image.scale.x>0 and moss.image.scale.y>0,"mirroring uses shared visual path, not negative body scaling")
	moss.clock = moss._moss_pose_started+moss.placement_shrink_time+moss.placement_spring_time*0.28
	moss.visual_mob()
	check(moss.image.scale.x>moss._moss_rest_scale.x and moss._face_right,"elastic rebound keeps current facing")
	moss._moss_pose_phase = "dig"
	moss._moss_pose_started = moss.clock-0.1
	moss.player_control_direction = Vector2.LEFT
	moss.visual_mob()
	check(not moss._face_right and moss.image.scale.x<moss._moss_rest_scale.x,"digging shrink and horizontal mirroring coexist")
	var mirror:Node2D = actor("苔藓",center+Vector2(250,0))
	mirror.set_multiplayer_authority(2)
	mirror.player_control_direction = Vector2.RIGHT
	mirror.accept_visual(moss.network_visual_state())
	mirror.visual_mob()
	check(not mirror._face_right and mirror._visual_facing_flipped_h==moss._visual_facing_flipped_h,"remote ignores local input and renders authority facing")
	moss._moss_pose_phase = "emerge"
	moss.player_control_direction = Vector2.RIGHT
	moss.visual_mob()
	mirror.accept_visual(moss.network_visual_state())
	mirror.visual_mob()
	check(mirror._face_right and mirror.image.scale.is_equal_approx(moss.image.scale),"remote right turn retains synchronized emergence pose")
	print("MOSS FACING CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
