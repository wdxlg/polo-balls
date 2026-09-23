extends "res://tests/test_copper_sword.gd"
## Requires the real renderer. Captures original textures, oxidation and reused charge.
func pixel_difference(a:Image,b:Image) -> int:
	var count:int = 0
	for y:int in range(a.get_height()):
		for x:int in range(a.get_width()):
			var first:Color = a.get_pixel(x,y)
			var second:Color = b.get_pixel(x,y)
			if absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)>0.12: count += 1
	return count
func capture_motion(unit:Node2D) -> Image:
	unit.visual_mob()
	unit.charge_visual.advance(0.0)
	var expected:Transform2D = unit.image.global_transform
	if unit.is_character_visual_flipped_h(): expected.x = -expected.x
	check(unit.charge_visual.global_transform.is_equal_approx(expected),"charged overlay follows rotated/returning sword exactly")
	check(not has_copper_status(unit),"continuous attack/recovery does not recreate status text")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var frame:Image = root.get_texture().get_image()
	var point:Vector2 = root.get_final_transform()*unit.get_global_transform_with_canvas().origin
	var crop:Image = frame.get_region(Rect2i(Vector2i(point)-Vector2i(128,128),Vector2i(256,256)))
	crop.convert(Image.FORMAT_RGB8)
	return crop

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(640,480)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"GPU preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	unit.health_bar.hide()
	unit.charge_visual.set_process(false)
	world.set_process(false)
	world.camera_2d.enabled = false
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(3.5,3.5)
	camera.make_current()
	camera.reset_smoothing()
	camera.force_update_scroll()
	await process_frame
	var images:Array[Image] = []
	var contact:Image = Image.create(1024,512,false,Image.FORMAT_RGB8)
	var stages:Array[float] = [0.0,0.34,0.67,1.0,0.0,0.0,0.0,0.0]
	for i:int in range(stages.size()):
		unit.rust = stages[i]
		unit.charged_left = 5.0 if i==4 else 0.0
		unit._view_clock = 1.25
		unit._face_right = i!=7
		unit._swing_active = i in [5,6]
		unit._swing_down = i==5
		unit._swing_duration = unit.base_swing_duration
		unit._swing_elapsed = unit._swing_duration*unit.HIT_BEGIN
		unit.visual_mob()
		check(not has_copper_status(unit),"no copper status text in rendered state "+str(i))
		unit.charge_visual.advance(0.05)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var frame:Image = root.get_texture().get_image()
		var point:Vector2 = root.get_final_transform()*unit.get_global_transform_with_canvas().origin
		var crop:Image = frame.get_region(Rect2i(Vector2i(point)-Vector2i(128,128),Vector2i(256,256)))
		crop.convert(Image.FORMAT_RGB8)
		images.append(crop)
		contact.blit_rect(crop,Rect2i(0,0,256,256),Vector2i((i%4)*256,(i/4)*256))
	contact.save_png("res://tests/copper_sword_visual_contact.png")
	check(pixel_difference(images[0],images[1])>100,"exposed copper renders differently from clean copper")
	check(pixel_difference(images[1],images[2])>100,"weathered copper has a distinct rendered stage")
	var changed:int = pixel_difference(images[0],images[3])
	var greener:int = 0
	for y:int in range(256):
		for x:int in range(256):
			var before:Color = images[0].get_pixel(x,y)
			var after:Color = images[3].get_pixel(x,y)
			if after.g>before.g+0.025 and after.r<before.r-0.025: greener += 1
	check(changed>100 and greener>changed*0.25,"fully oxidized blade visibly turns copper-green in actual renderer")
	check(pixel_difference(images[0],images[4])>100,"native trident glint/electric arcs actually render on the sword")
	check(pixel_difference(images[5],images[6])>400,"upper and lower windups are visibly distinct")
	check(pixel_difference(images[0],images[7])>400,"left-facing art is a real horizontal mirror")
	# Film consecutive real animation states. Freeze only the decorative arc reroute,
	# so equal endpoint pictures really compare the sword/charge pose, not random arcs.
	unit._swing_active = false
	unit._holding_pose = false
	unit._returning = false
	unit._face_right = true
	unit._movement_face_right = true
	unit._next_swing_down = true
	unit.direction = Vector2.RIGHT
	unit.set_player_control_peer(1)
	unit.player_control_direction = Vector2.RIGHT
	unit.player_control_aim_valid = true
	unit.player_control_aim_position = center+Vector2(40,-18)
	unit.rust = 0.0
	unit.charged_left = 5.0
	var shots:Array[Image] = []
	shots.append(await capture_motion(unit)) # 0: ordinary idle.
	unit.begin_swing()
	unit.advance_swing(unit._windup_left)
	shots.append(await capture_motion(unit)) # 1: raised, first cut starts.
	for phase:float in [0.25,0.60,0.86,1.0]:
		unit.advance_swing(maxf(unit._swing_duration*phase-unit._swing_elapsed,0.0))
		shots.append(await capture_motion(unit)) # 2..5: slow then fast downstroke.
	unit.begin_swing()
	shots.append(await capture_motion(unit)) # 6: same lower endpoint; reverse starts.
	unit.advance_swing(unit._swing_duration*0.5)
	shots.append(await capture_motion(unit)) # 7: slow part of upstroke.
	unit.advance_swing(unit._swing_duration-unit._swing_elapsed)
	shots.append(await capture_motion(unit)) # 8: upper endpoint.
	unit.begin_swing()
	shots.append(await capture_motion(unit)) # 9: same upper endpoint; next downstroke.
	unit.advance_swing(unit._swing_duration)
	shots.append(await capture_motion(unit)) # 10: third cut ends, below.
	unit.cancel_swing()
	shots.append(await capture_motion(unit)) # 11: recovery begins without a pop.
	unit._advance_return(unit.return_duration*0.5)
	shots.append(await capture_motion(unit)) # 12: fast ease-out recovery.
	unit._advance_return(unit.return_duration*0.5)
	shots.append(await capture_motion(unit)) # 13: exact ordinary idle again.
	for aim:Vector2 in [Vector2.UP,Vector2(-1,1).normalized()]:
		unit.cancel_swing()
		unit._advance_return(unit.return_duration)
		unit.player_control_aim_position = center+aim*40.0
		unit.begin_swing()
		unit.advance_swing(unit._windup_left+unit._swing_duration*pow(0.5,1.0/unit.SWING_EASE_POWER))
		shots.append(await capture_motion(unit)) # 14/15: truly vertical / diagonal.
	check(pixel_difference(shots[5],shots[6])<16,"GPU: lower endpoint directly joins reverse cut with no idle picture")
	check(pixel_difference(shots[8],shots[9])<16,"GPU: upper endpoint directly joins the next cut")
	check(pixel_difference(shots[10],shots[11])<16,"GPU: stopping begins recovery from current pose, not a snap")
	check(pixel_difference(shots[0],shots[13])<16,"GPU: completed recovery exactly matches original idle")
	check(pixel_difference(shots[10],shots[13])>400,"GPU: final cut and returned idle are genuinely different poses")
	check(pixel_difference(shots[14],shots[15])>400,"GPU: vertical and diagonal strikes visibly differ")
	var flow_contact:Image = Image.create(768,768,false,Image.FORMAT_RGB8)
	for i:int in range(shots.size()):
		var shot:Image = shots[i]
		shot.resize(192,192,Image.INTERPOLATE_NEAREST)
		flow_contact.blit_rect(shot,Rect2i(0,0,192,192),Vector2i((i%4)*192,(i/4)*192))
	flow_contact.save_png("res://tests/copper_sword_flow_contact.png")
	print("COPPER_SWORD_GPU checks=",checks," failures=",failures," captures=res://tests/copper_sword_visual_contact.png,res://tests/copper_sword_flow_contact.png")
	finish(0 if failures==0 else 1)
