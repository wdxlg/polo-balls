extends "res://tests/test_mc_bat_transform.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	var e:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center)
	e.state_machine.set_physics_process(false)
	await process_frame
	var animation:Node = e.mc_native_animation
	animation.set_process(false)
	var frames:SpriteFrames = animation.frames
	check(frames.get_frame_count(&"celebrate") == 16,"all sixteen original-timing celebration frames remain available")
	var intact:bool = true
	for i:int in range(16):
		var picture:Image = frames.get_frame_texture(&"celebrate",i).get_image()
		var box:Rect2i = picture.get_used_rect()
		intact = intact and box.size.x >= 100 and box.position.x > 0 and box.end.x < picture.get_width()
	check(intact,"both raised arms remain extended and inside the canvas in every celebration frame")
	e.mc_cast_animation(0.85)
	check(animation.current_clip == &"cast","normal spell casting still selects its independent clip")
	e.on_battle_victory()
	animation.advance(0.1)
	check(animation.current_clip == &"celebrate","victory switches to corrected celebration")
	var texture_before:Texture2D = e.image.texture
	animation.advance(0.09)
	check(e.image.texture != texture_before,"celebration remains animated, not replaced by a static pose")
	game.now_stop_state = true
	texture_before = e.image.texture
	animation.advance(0.2)
	check(e.image.texture == texture_before,"pause freezes the corrected animation")
	game.now_stop_state = false
	if DisplayServer.get_name() != "headless":
		game.Game_Settings.Training_Debug_Mode = false
		world.versus_label.hide()
		e.health_bar.hide()
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.global_position = center
		camera.zoom = Vector2(7,7)
		camera.make_current()
		await RenderingServer.frame_post_draw
		var screenshot:Image = root.get_texture().get_image()
		var size:Vector2i = screenshot.get_size()
		screenshot.get_region(Rect2i(Vector2i(size.x/2-160,size.y/2-150),Vector2i(320,300))).save_png("res://tests/evoker_arms_fixed.png")
	finish(0 if failures == 0 else 1)
