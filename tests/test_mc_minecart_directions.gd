extends "res://tests/test_mc_bat_transform.gd"
const CART_PATH:String = "res://scenes/characters/我的世界/矿车.tscn"
func run() -> void:
	var center:Vector2 = await setup_world()
	var cart:Node2D = spawn(CART_PATH,center)
	cart.Can_Attack = true
	cart.state_machine.set_physics_process(false)
	cart.set_process(false)
	await process_frame
	cart.rails.set_physics_process(false)
	var frames:SpriteFrames = cart.CART_FRAMES
	check(frames.get_animation_names().size() == 64,"same 64-direction coverage as guardian")
	var collider:Shape2D = cart.collision_shape_2d.shape
	var base_position:Vector2 = cart.global_position
	for view:int in range(64):
		var name:StringName = StringName("v%02d" % view)
		cart.direction = Vector2.RIGHT.rotated(TAU*float(view)/64.0)
		cart._snap_facing(cart.direction)
		cart.advance_cart_visual(0.0)
		cart.visual_mob()
		check(frames.get_frame_count(name) == 9 and cart._view_index == view and cart.image.texture == frames.get_frame_texture(name,0),"native neutral and eight rolling poses for direction "+str(view))
	check(cart.collision_shape_2d.shape == collider and cart.rotation == 0.0 and cart.global_position == base_position,"model yaw never rotates or moves gameplay collision")
	check(cart.image.rotation == 0.0 and not cart.image.flip_h and not cart.is_character_visual_flipped_h(),"direction frames are not simulated by flat rotation or mirroring")
	var metadata:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Images/characters/我的世界/矿车/minecart_turns.json"))
	for path:String in metadata.outputs_sha256:
		check(FileAccess.get_sha256("res://Images/characters/我的世界/矿车/"+path) == metadata.outputs_sha256[path],"derived output hash: "+path)
	var pivot:Vector3 = Vector3(metadata.world_model_pivot[0],metadata.world_model_pivot[1],metadata.world_model_pivot[2])
	check(metadata.frames.size() == 576 and pivot == Vector3(0,5.5,0),"all 576 poses share the native model pivot")
	var atlas:Image = (frames.get_frame_texture(&"v00",0) as AtlasTexture).atlas.get_image()
	var valid:bool = true
	for record:Dictionary in metadata.frames:
		var region:Rect2i = Rect2i(record.rect[0],record.rect[1],record.rect[2],record.rect[3])
		var pixels:Image = atlas.get_region(region)
		var hash_context := HashingContext.new()
		hash_context.start(HashingContext.HASH_SHA256)
		hash_context.update(pixels.get_data())
		valid = valid and hash_context.finish().hex_encode() == record.pixel_sha256
	check(valid,"import preserves the pixels of every baked native-model pose")
	cart.direction = Vector2.RIGHT
	cart._snap_facing(cart.direction)
	var seen:Dictionary = {}
	for i:int in range(20):
		cart.move(110,0.05)
		cart.advance_cart_visual(0.05)
		cart.visual_mob()
		seen[cart._roll_frame] = true
	check(seen.size() >= 4 and not seen.has(0),"real ordinary movement plays multiple rolling frames without idle-frame flicker")
	cart.advance_cart_visual(0.2)
	check(cart._roll_frame == 0,"stationary cart settles to the native neutral pose")
	cart.move(110,0.04)
	var previous:float = cart._roll_phase
	cart.advance_cart_visual(0.04)
	var idle_rate:float = fposmod(cart._roll_phase-previous,1.0)
	cart.end_rush()
	cart.idle_left = 0.0
	cart.set_player_control_peer(1)
	cart.set_player_control_aim_position(cart.global_position+Vector2(300,0))
	cart.start_charge()
	base_position = cart.global_position
	seen.clear()
	for i:int in range(10):
		cart.move(110,0.08)
		cart.advance_cart_visual(0.08)
		seen[cart._roll_frame] = true
	check(seen.size() >= 4 and cart.global_position == base_position,"windup rocks through model poses while its body remains stationary")
	cart.step_mob(1.01)
	cart.rush_direction = Vector2.RIGHT
	cart.move(110,0.04)
	previous = cart._roll_phase
	cart.advance_cart_visual(0.04)
	check(fposmod(cart._roll_phase-previous,1.0) > idle_rate*1.5,"dash movement plays the rolling cycle faster than normal travel")
	cart.wall_contact(Vector2.LEFT,cart.global_position)
	check(cart.rush_phase == 0 and cart.rush_direction.is_equal_approx(Vector2.RIGHT) and cart._view_index == 0,"terrain braking retains the heading instead of reflecting the model")
	cart.rails.clear_tracks()
	cart.direction = Vector2(-1,-1).normalized()
	cart._snap_facing(cart.direction)
	check(cart._view_index == 40,"native diagonal views remain available for continuous arc steering")
	var phase:float = cart._roll_phase
	var view_index:int = cart._view_index
	game.now_stop_state = true
	cart.rush_direction = Vector2.DOWN
	cart.advance_cart_visual(0.4)
	check(cart._roll_phase == phase and cart._view_index == view_index,"combat stop freezes both temporal and direction animation")
	game.now_stop_state = false
	paused = true
	cart.advance_cart_visual(0.4)
	check(cart._roll_phase == phase and cart._view_index == view_index,"SceneTree pause also freezes model animation")
	paused = false
	cart.end_rush()
	cart._look_angle = deg_to_rad(179)
	cart.direction = Vector2.RIGHT.rotated(deg_to_rad(-179))
	cart.advance_cart_visual(0.02)
	check(absf(wrapf(cart._look_angle-deg_to_rad(179),-PI,PI)) < deg_to_rad(2.1),"turn interpolation crosses the angle seam on the short path")
	cart._motion_hold = 1.0
	game.Game_Settings.Ball_Can_Move = false
	cart.advance_cart_visual(0.04)
	check(cart._roll_frame == 0,"disabling movement prevents false rolling animation")
	game.Game_Settings.Ball_Can_Move = true
	cart.direction = Vector2.DOWN
	cart._snap_facing(cart.direction)
	cart._motion_hold = 1.0
	cart._visual_move_speed = 96.0
	cart._roll_phase = 0.1
	cart._roll_frame = 1
	var ghost:Node2D = spawn(CART_PATH,center+Vector2(0,100))
	ghost.set_multiplayer_authority(2)
	ghost.set_process(false)
	ghost.state_machine.set_physics_process(false)
	ghost.accept_visual(cart.visual_state())
	check(ghost.direction == Vector2.DOWN and ghost._view_index == 16 and ghost._roll_frame == 1,"snapshot includes ordinary direction and rolling pose, not just rush heading")
	ghost.advance_cart_visual(0.1)
	check(ghost._roll_frame != 1 and ghost._view_index == 16,"non-authority visual state continues the native rolling cycle between snapshots")
	ghost.free()
	finish(0 if failures == 0 else 1)
