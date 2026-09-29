extends "res://tests/test_mc_bat_transform.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	var s:Node2D = spawn("res://scenes/characters/传说之下/Sans.tscn",center)
	s.state_machine.set_physics_process(false)
	s.set_process(false)
	var root_before:Transform2D = s.transform
	var collision_before:Transform2D = s.collision_shape_2d.transform
	var foot:Vector2 = s.BODY_IDLE_FEET-s.BODY_IDLE.size*0.5
	s._idle_sway_elapsed = 0.0
	s._update_sans_visual(0.0)
	var feet_before:Vector2 = s._sans_body.transform*foot
	var face_before:Vector2 = s._sans_face.position
	s._update_sans_visual(0.5)
	var lean:float = s._sans_body.skew
	check(absf(lean) > 0.01 and s._sans_face.position.distance_to(face_before) > 1.0,"idle torso leans and head follows")
	check((s._sans_body.transform*foot).distance_to(feet_before) < 0.001,"foot anchor stays planted")
	check(s.transform == root_before and s.collision_shape_2d.transform == collision_before,"sway cannot move the actor or collision body")
	check(s._sans_body.scale == Vector2.ONE*s.SANS_VISUAL_SCALE,"idle motion does not pulse whole-body scale")
	s._update_sans_visual(1.0)
	check(lean*s._sans_body.skew < 0.0,"idle animation sways to both sides")
	var body_before:Transform2D = s._sans_body.transform
	face_before = s._sans_face.position
	for i:int in range(40): s._update_sans_visual(0.0)
	check(s._sans_body.transform.is_equal_approx(body_before) and s._sans_face.position.is_equal_approx(face_before),"reapplying pose cannot accumulate drift")
	game.now_stop_state = true
	s._process(1.0)
	check(s._sans_body.transform == body_before,"pause freezes the idle pose")
	game.now_stop_state = false
	s._set_visual_mode_local(s.SansVisual.GRAVITY_LEFT)
	s._update_sans_visual(0.1)
	check(is_zero_approx(s._sans_body.skew) and not s._sans_body.flip_h,"gravity gesture clears sway without mirroring its reverse frames")
	s._set_visual_mode_local(s.SansVisual.DODGE)
	s._update_sans_visual(0.1)
	check(is_zero_approx(s._sans_body.skew),"dodge remains controlled by its own pose")
	s._set_visual_mode_local(s.SansVisual.IDLE)
	s._dodge_count = 1
	s._update_sans_visual(0.1)
	var sweat_relative:Vector2 = s._sans_sweat.position-s._sans_face.position
	s._update_sans_visual(0.2)
	check(s._sans_sweat.visible and (s._sans_sweat.position-s._sans_face.position).is_equal_approx(sweat_relative),"sweat remains attached to the swaying head")
	s._last_trial_active = true
	s._update_sans_visual(0.1)
	check(not is_zero_approx(s._sans_body.skew),"final countdown retains idle sway between gestures")
	s._last_trial_active = false
	s._death_visual_started_local = true
	body_before = s._sans_body.transform
	s._process(1.0)
	check(s._sans_body.transform == body_before,"death presentation is not overwritten by idle animation")
	s._death_visual_started_local = false
	finish(0 if failures == 0 else 1)
