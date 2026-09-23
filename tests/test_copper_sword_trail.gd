extends "res://tests/test_copper_sword_flow.gd"
## Run headless for physics/lifecycle checks, or with a real renderer for pixel checks.
func capture_trail(unit:Node2D) -> Image:
	unit.visual_mob()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var frame:Image = root.get_texture().get_image()
	var point:Vector2 = root.get_final_transform()*unit.get_global_transform_with_canvas().origin
	var crop:Image = frame.get_region(Rect2i(Vector2i(point)-Vector2i(128,128),Vector2i(256,256)))
	crop.convert(Image.FORMAT_RGB8)
	return crop
func difference(a:Image,b:Image) -> int:
	var changed:int = 0
	for y:int in range(a.get_height()):
		for x:int in range(a.get_width()):
			var first:Color = a.get_pixel(x,y)
			var second:Color = b.get_pixel(x,y)
			if absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)>0.12: changed += 1
	return changed
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"movement/trail preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	var target:Node2D = dummy(center+Vector2(200,0))
	await physics_frame
	await process_frame
	var original_speed:float = unit.Speed
	var default_speed:float = unit.default_properties.Speed
	check(unit.attack_movement_scale()==1.0,"idle movement is not slowed")
	var point:Vector2 = unit.global_position
	unit.move(unit.Speed,1.0/60.0)
	var idle_distance:float = unit.global_position.distance_to(point)
	var idle_velocity:float = unit._last_requested_velocity.length()
	unit.begin_swing(target)
	point = unit.global_position
	unit.move(unit.Speed,1.0/60.0)
	check(is_equal_approx(unit._last_requested_velocity.length()/idle_velocity,unit.attack_move_speed_ratio),"AI attack movement is 85 percent of normal")
	check(idle_distance>0.0 and absf(unit.global_position.distance_to(point)/idle_distance-unit.attack_move_speed_ratio)<0.01,"actual movement distance is reduced, not only a displayed number")
	check(unit.Speed==original_speed and unit.default_properties.Speed==default_speed,"attacking never overwrites Speed or default/buff properties")
	unit.set_player_control_peer(1)
	unit.player_control_direction = Vector2.LEFT
	unit.move(unit.Speed,1.0/60.0)
	check(unit._last_requested_velocity.x<0.0 and is_equal_approx(absf(unit._last_requested_velocity.x),idle_velocity*unit.attack_move_speed_ratio),"WASD movement receives the same slight reduction")
	unit.Speed = original_speed*1.4
	unit.move(unit.Speed,1.0/60.0)
	check(is_equal_approx(absf(unit._last_requested_velocity.x),idle_velocity*1.4*unit.attack_move_speed_ratio),"other speed changes compose with the attack multiplier")
	unit.Repel = Vector2(0,31)
	unit.move(unit.Speed,1.0/60.0)
	check(is_equal_approx(unit._last_requested_velocity.y,31.0),"knockback component is not reduced by attack slowdown")
	unit.Repel = Vector2.ZERO
	unit.cancel_swing()
	unit.move(unit.Speed,1.0/60.0)
	check(unit._returning and unit.attack_movement_scale()==1.0 and is_equal_approx(absf(unit._last_requested_velocity.x),idle_velocity*1.4),"stopping restores current buffed speed immediately, even during visual recovery")
	stop_restore(unit)
	unit.Speed = original_speed
	unit.set_player_control_peer(0)
	unit.velocity = Vector2.ZERO
	var trail:Node2D = unit.swing_trail
	check(not unit.motion_blur_enabled and not unit.motion_stretch_enabled,"weapon echoes do not opt the character into global motion blur/stretch")

	unit.reset_combo()
	unit.begin_swing(target)
	unit.advance_swing(unit._windup_left)
	check(trail.samples.is_empty(),"raising the sword emits no echoes")
	unit.advance_swing(unit._swing_duration)
	check(trail.samples.is_empty() and trail._created==0,"ordinary-speed cut emits no echoes or pool allocations")
	stop_restore(unit)
	unit.combo_hits = 13
	unit.rust = 0.8
	unit.begin_swing(target)
	unit.advance_swing(unit._windup_left+unit._swing_duration)
	check(not trail.samples.is_empty() and trail.visible,"high-speed cut produces visible sword echoes")
	check(trail.samples.size()<=trail.LIMIT and trail._created<=trail.LIMIT,"coarse full-stroke sampling stays within fixed pool limit")
	var valid_samples:bool = true
	for sample:Dictionary in trail.samples:
		valid_samples = valid_samples and sample.angular_speed>=unit.trail_min_angular_speed and sample.sprite.texture==unit.SWORD and sample.sprite.material==unit.image.material
	check(valid_samples,"all echoes meet actual angular-speed threshold and reuse native sword/material")
	check(trail.find_children("*","CollisionObject2D",true,false).is_empty(),"echoes have no collision or damage objects")
	var oldest:Dictionary = trail.samples[0]
	var frozen_pose:Transform2D = oldest.sprite.global_transform
	var frozen_flip:float = oldest.sprite.get_instance_shader_parameter("sprite_flip_h")
	unit.global_position += Vector2(70,-20)
	unit.rust = 0.0
	unit._face_right = not unit._face_right
	unit.visual_mob()
	check(oldest.sprite.global_transform.is_equal_approx(frozen_pose),"echo stays at historical world position when caster moves")
	check(is_equal_approx(oldest.sprite.get_instance_shader_parameter("rust_level"),0.8) and oldest.sprite.get_instance_shader_parameter("sprite_flip_h")==frozen_flip,"old echoes preserve oxidation and facing after live sword changes")
	game.now_stop_state = true
	var before_age:float = trail.samples[-1].age
	var before_count:int = trail.samples.size()
	trail.advance(2.0)
	trail.record_segment(0.0,1.0)
	check(trail.samples[-1].age==before_age and trail.samples.size()==before_count,"pause freezes fading and prevents new echoes")
	game.now_stop_state = false
	unit.cancel_swing()
	var youngest:Sprite2D = trail.samples[-1].sprite
	var before_alpha:float = youngest.modulate.a
	trail.advance(unit.trail_lifetime*0.5)
	check(youngest.visible and youngest.modulate.a<before_alpha,"existing echoes fade after attack stops")
	trail.advance(unit.trail_lifetime)
	check(trail.samples.is_empty() and not trail.visible,"all echoes disappear within their short lifetime")
	stop_restore(unit)

	# Threshold is angular speed, not a fake combo-count toggle or running speed.
	unit.reset_combo()
	var normal_cooling:float = unit.Attack_Cooling
	unit.Attack_Cooling = normal_cooling*0.4
	unit.begin_swing(target)
	unit.advance_swing(unit._windup_left+unit._swing_duration*0.9)
	check(unit.combo_hits==0 and not trail.samples.is_empty(),"external attack haste produces echoes without any combo stacks")
	stop_restore(unit)
	trail.clear()
	unit.Attack_Cooling = normal_cooling
	unit.velocity = Vector2(999,0)
	trail.advance(0.05)
	trail.record_segment(0.0,1.0)
	check(trail.samples.is_empty(),"fast running without swinging does not produce sword echoes")
	unit.velocity = Vector2.ZERO
	for i:int in range(18):
		unit.combo_hits = 13
		unit.begin_swing(target)
		unit.advance_swing(unit._windup_left+unit._swing_duration)
	check(trail.samples.size()<=trail.LIMIT and trail._created==trail.LIMIT,"many fast cuts reuse bounded sprites instead of leaking nodes")
	var replica:Node2D = copper(center+Vector2(300,160))
	replica.set_multiplayer_authority(2)
	# The preceding miss correctly reset the combo. Start a genuinely FAST source
	# stroke before asking the replica to display fast-stroke echoes.
	unit.combo_hits = 13
	unit.begin_swing(target)
	check(unit._swing_duration<unit.base_swing_duration*0.5,"replica fixture starts from an actual high-speed source stroke")
	replica.accept_visual(unit.network_visual_state())
	replica.client_visual_step(replica._windup_left+replica._swing_duration*0.95)
	check(not replica.swing_trail.samples.is_empty(),"non-authority presentation also renders high-speed blade echoes")
	replica.image.hide()
	replica.swing_trail.advance(0.01)
	check(replica.swing_trail.samples.is_empty(),"hiding the source clears echoes")
	stop_restore(unit)
	trail.clear()

	if DisplayServer.get_name()!="headless":
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = Vector2i(640,480)
		world.set_process(false)
		world.camera_2d.enabled = false
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.global_position = center
		camera.zoom = Vector2(4,4)
		camera.make_current()
		camera.force_update_scroll()
		unit.global_position = center
		unit.health_bar.hide()
		unit.set_player_control_peer(1)
		unit.player_control_direction = Vector2.RIGHT
		unit.player_control_aim_valid = true
		unit.player_control_aim_position = center+Vector2(60,-30)
		unit.combo_hits = 13
		unit.rust = 0.0
		unit.begin_swing()
		unit.advance_swing(unit._windup_left+unit._swing_duration*0.9)
		var with_echoes:Image = await capture_trail(unit)
		trail.hide()
		var without_echoes:Image = await capture_trail(unit)
		check(difference(with_echoes,without_echoes)>60,"GPU actually draws translucent sword echoes behind the live blade")
		trail.show()
		trail.advance(unit.trail_lifetime+0.01)
		var faded:Image = await capture_trail(unit)
		check(difference(without_echoes,faded)<16,"GPU returns to the identical clean picture after echoes fade")
		var sheet:Image = Image.create(768,256,false,Image.FORMAT_RGB8)
		for i:int in range(3):
			var frame:Image = [without_echoes,with_echoes,faded][i]
			sheet.blit_rect(frame,Rect2i(0,0,256,256),Vector2i(i*256,0))
		sheet.save_png("res://tests/copper_sword_trail_contact.png")
		stop_restore(unit)
	unit.combo_hits = 13
	unit.begin_swing(target)
	unit.advance_swing(unit._windup_left+unit._swing_duration)
	check(not trail.samples.is_empty(),"death-cleanup fixture has live echoes")
	unit.health = 0
	unit.Die()
	check(trail.samples.is_empty() and not trail.visible,"death immediately clears every remaining echo")
	print("COPPER_SWORD_TRAIL checks=",checks," failures=",failures," renderer=",DisplayServer.get_name())
	finish(0 if failures==0 else 1)
