extends "res://tests/test_mc16_spider_drowned.gd"
var fx_script:Script
class RenderProbe extends Node2D:
	var health:float = 1000.0
	var hurt_shake_enabled:bool = true
	func is_combat_runtime_active() -> bool: return true

func image_centroid(image:Image,red_only:bool = false) -> Vector2:
	var sum:Vector2 = Vector2.ZERO
	var count:int = 0
	for y:int in range(image.get_height()):
		for x:int in range(image.get_width()):
			if image.get_pixel(x,y).a>0.5 and (not red_only or image.get_pixel(x,y).g<0.2):
				sum += Vector2(x,y)
				count += 1
	return sum/maxi(count,1)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Shaking_Camera = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await process_frame
	await process_frame
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	fx_script = load("res://scripts/effects/character_hurt_shake.gd")
	var previous:float = 0.0
	for damage:float in [1.0,5.0,20.0,80.0,300.0,1000000.0]:
		var strength:float = fx_script.strength_for_damage(damage)
		check(strength>previous and strength<=18.0,"larger damage produces stronger but bounded body shake")
		previous = strength
	check(fx_script.strength_for_damage(0.0)==0 and fx_script.strength_for_damage(-10)==0 and fx_script.strength_for_damage(INF)==0 and fx_script.strength_for_damage(NAN)==0,"zero/healing/nonfinite values cannot trigger shake")
	check(is_equal_approx(fx_script.strength_for_damage(48.0),0.6*sqrt(48.0/50.0)),"48 HP stays in the slight body-shake tier")
	var owner:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center)
	var target:Node2D = dummy(center+Vector2(180,0))
	var friend:Node2D = dummy(target.global_position+Vector2(0,15),"Team0")
	var far:Node2D = dummy(target.global_position+Vector2(0,200))
	await process_frame
	owner.mc_native_animation.set_process(false)
	check(owner.lightning_damage_ratio==1.4 and owner.impact_lightning_damage_ratio==0.7,"both drowned lightning multipliers reduced by thirty percent")
	check(owner.trident_damage_ratio==0.5 and owner.network_damage_ratio==0.7 and owner.lightning_stun==0.65 and owner.impact_lightning_stun==0.3,"direct hit, electric network and stun durations unchanged")
	check(owner._hurt_shake_render_parts.has(owner.hand_visual),"drowned detached hand weapon is registered for whole-body feedback")
	var friend_hp:float = friend.health
	var far_hp:float = far.health
	var hp:float = target.health
	owner._strike_area(target.global_position,false)
	check(hp-target.health==48.0,"actual periodic lightning resolves 48 instead of 68 baseline damage")
	hp = target.health
	owner._strike_area(target.global_position,true)
	check(hp-target.health==24.0,"actual contact lightning resolves 24 instead of 34 baseline damage")
	check(friend.health==friend_hp and far.health==far_hp,"lightning retains friendly immunity and radius")
	owner._trident.charge()
	owner.health -= 9
	owner._hurt_shake_effect._present()
	var glint:Node2D = owner._trident.charge_visual
	check(owner._hurt_shake_effect._rendered_extra_graphics.has(glint),"held enchantment and shaft electricity follow body shake too")
	owner._trident.launch(Vector2.RIGHT)
	glint.advance(0.0)
	var flying_pose:Transform2D = glint.transform
	owner._hurt_shake_effect._present()
	check(not owner._hurt_shake_effect._rendered_extra_graphics.has(glint) and glint.transform==flying_pose,"launched weapon and its electricity immediately leave body shake without changing flight anchors")
	owner._hurt_shake_effect.stop()
	var fx:Node = target._hurt_shake_effect
	check(is_instance_valid(fx) and fx.active,"confirmed damage automatically starts body shake with camera shake off")
	fx.stop()
	target.health += 1
	check(not fx.active,"healing does not shake")
	target.health -= 12
	check(fx.active and is_equal_approx(fx.amplitude,fx_script.strength_for_damage(12.0)),"direct health damage uses actual lost HP")
	check(fx.duration>=0.16 and fx.duration<=0.28,"stronger feedback remains brief with a 160 to 280 millisecond envelope")
	fx.stop()
	target.Damage_reduction = 1.0
	owner.mc_damage_with_impact(target,100.0,target.global_position)
	check(not fx.active,"full damage immunity does not shake")
	target.Damage_reduction = 0.5
	hp = target.health
	owner.mc_damage_with_impact(target,40.0,target.global_position)
	check(is_equal_approx(fx.amplitude,fx_script.strength_for_damage(hp-target.health)),"damage reduction is applied before choosing shake strength")
	fx.stop()
	target.Damage_reduction = 0.0
	target.max_block = 100
	target.block = 100
	owner.mc_damage_with_impact(target,20.0,target.global_position)
	check(not fx.active,"shield-only blocked damage does not fake body injury")
	target.block = 0
	var body_pose:Transform2D = target.global_transform
	var graphics_pose:Transform2D = target.graphics.transform
	var hit_pose:Transform2D = target.get_node("hitbox").global_transform
	var hurt_pose:Transform2D = target.get_node("hurtbox").global_transform
	var velocity_before:Vector2 = target.velocity
	fx.kick(100)
	fx.set_process(false)
	fx.advance(0.02)
	fx._present()
	check(fx.world_offset.length()>0 and fx.last_render_transform!=graphics_pose,"rendered graphics transform includes the visual offset")
	check(target.global_transform==body_pose and target.graphics.transform==graphics_pose,"body and Graphics node transforms remain untouched")
	check(target.get_node("hitbox").global_transform==hit_pose and target.get_node("hurtbox").global_transform==hurt_pose and target.velocity==velocity_before,"hit/hurt boxes and velocity remain untouched")
	# External animation/stun is composed on top of its current pose, never overwritten.
	target.graphics.position += Vector2(3,4)
	var animated_pose:Transform2D = target.graphics.transform
	fx._present()
	check(target.graphics.transform==animated_pose and fx.last_render_transform.origin!=animated_pose.origin,"existing animation pose is preserved while rendering the shake")
	fx.stop()
	check(fx.last_render_transform==animated_pose and target.graphics.transform==animated_pose,"ending restores the latest pose, not an old snapshot")
	seed(71287)
	var expected_random:float = randf()
	seed(71287)
	for i:int in range(250):
		fx.kick(10000)
		fx.advance(0.001)
		fx._present()
	check(is_equal_approx(randf(),expected_random),"shake consumes no global battle RNG")
	check(target._hurt_shake_effect==fx and fx.amplitude<=18.0 and fx.duration<=0.28,"dense repeated hits reuse one bounded effect without stacking nodes")
	fx.advance(1.0)
	check(not fx.active and not fx.is_processing() and not RenderingServer.frame_pre_draw.is_connected(fx._present),"effect expires, restores pose and removes its render callback")
	fx.kick(30)
	game.now_stop_state = true
	fx._present()
	check(not fx.active and fx.last_render_transform==target.graphics.transform,"pause cancels the offset instead of leaving a displaced body")
	game.now_stop_state = false
	target.hurt_shake_enabled = false
	target.health -= 5
	check(not fx.active,"per-character opt-out is respected")
	target.hurt_shake_enabled = true
	target.set_multiplayer_authority(2)
	target.health -= 5
	check(not fx.active,"replicated health values do not duplicate authority feedback")
	target._remote_damage_camera_feedback(5.0,false)
	check(fx.active,"the existing confirmed-feedback RPC renders on replicas")
	target.set_multiplayer_authority(1)
	fx.stop()
	target.Type = target.Ball_Type.Shooter
	target._play_body_hurt_shake(100)
	check(not fx.active,"projectiles are not treated as character bodies")
	target.Type = target.Ball_Type.Creature
	target.health -= 8
	check(fx.active,"summoned creatures use the same universal actual-damage feedback")
	fx.stop()
	target.Type = target.Ball_Type.Ball
	while target._stun_visual_ref_count>0: target.end_stun_visual()
	target.graphics.transform = graphics_pose
	target.begin_stun_visual()
	target._update_stun_shake_visual(0.025)
	var stun_pose:Transform2D = target.graphics.transform
	fx.kick(80)
	fx._present()
	check(target.graphics.transform==stun_pose,"real stun animation and hurt shake coexist without changing the stun baseline")
	target.end_stun_visual()
	fx.stop()
	check(target.graphics.transform.is_equal_approx(graphics_pose),"both effects ending leaves no accumulated displacement")
	fx.kick(20)
	paused = true
	fx._present()
	check(not fx.active,"SceneTree pause also clears active body shake")
	paused = false
	camera_feedback_check()
	if DisplayServer.get_name()!="headless":
		await gpu_render_check()
		await gpu_camera_check()
	var effect_ref:WeakRef = weakref(fx)
	target.free()
	check(effect_ref.get_ref()==null,"freeing a character frees the owned shake node")
	print("CHARACTER_HURT_SHAKE checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)

func gpu_render_check() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160,160)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var probe := RenderProbe.new()
	probe.position = Vector2(80,80)
	probe.scale = Vector2(0.5,0.75)
	var graphics := Node2D.new()
	probe.add_child(graphics)
	var sprite := Sprite2D.new()
	var pixels := Image.create(40,40,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(pixels)
	graphics.add_child(sprite)
	viewport.add_child(probe)
	var hand := Sprite2D.new()
	var red_pixels := Image.create(10,10,false,Image.FORMAT_RGBA8)
	red_pixels.fill(Color.RED)
	hand.texture = ImageTexture.create_from_image(red_pixels)
	probe.add_child(hand)
	hand.set_as_top_level(true)
	hand.global_position = Vector2(110,80)
	var effect:Node = fx_script.new()
	effect.actor = probe
	effect.graphics = graphics
	effect.extra_graphics.append(hand)
	probe.add_child(effect)
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline:Vector2 = image_centroid(viewport.get_texture().get_image())
	var hand_baseline:Vector2 = image_centroid(viewport.get_texture().get_image(),true)
	effect.kick(1000)
	effect.set_process(false)
	var desired:Vector2 = effect.world_offset
	await process_frame
	await RenderingServer.frame_post_draw
	var shaken:Vector2 = image_centroid(viewport.get_texture().get_image())
	check(shaken.distance_to(baseline)>1.0,"GPU pixels visibly move, not just internal bookkeeping")
	check((shaken-baseline).distance_to(desired)<1.25,"GPU motion is world-space bounded even under nonuniform character scale")
	var hand_shaken:Vector2 = image_centroid(viewport.get_texture().get_image(),true)
	check((hand_shaken-hand_baseline).distance_to(desired)<1.25 and hand_shaken.distance_to(hand_baseline)>1.0 and hand.global_position==Vector2(110,80),"detached top-level hand artwork shakes visually without shifting weapon anchors")
	check(probe.position==Vector2(80,80) and graphics.position==Vector2.ZERO,"GPU shake leaves scene-tree positions unchanged")
	effect.stop()
	await process_frame
	await RenderingServer.frame_post_draw
	check(image_centroid(viewport.get_texture().get_image()).distance_to(baseline)<0.1,"GPU pixels return exactly to neutral after the shake")
	# Real node animation changes while the additive render override is active.
	effect.kick(1000)
	effect.set_process(false)
	graphics.position = Vector2(8,0)
	await process_frame
	await RenderingServer.frame_post_draw
	var moved:Vector2 = image_centroid(viewport.get_texture().get_image())
	# The white body covers 600 pixels and the detached red item 100 pixels.
	check((moved-shaken).distance_to(Vector2(4.0*600.0/700.0,0.0))<0.75,"GPU shake composes with current animation instead of a stale cached pose")
	effect.extra_graphics.clear()
	await process_frame
	await RenderingServer.frame_post_draw
	check(image_centroid(viewport.get_texture().get_image(),true).distance_to(hand_baseline)<0.1,"GPU artwork detached mid-shake instantly returns to its own neutral transform")
	effect.stop()
	graphics.position = Vector2.ZERO
	effect.kick(20)
	probe.health = 0
	effect._present()
	check(not effect.active,"death cancels rendering overrides immediately on the next presentation")
	viewport.queue_free()
	await process_frame

func camera_feedback_check() -> void:
	var old_setting:bool = game.Game_Settings.Shaking_Camera
	game.Game_Settings.Shaking_Camera = false
	world._update_damage_camera_shake(0.0)
	world.add_damage_camera_shake(1000.0)
	check(world._damage_shake_pending_peak==0.0 and world.camera_2d.offset==Vector2.ZERO,"camera shake off still suppresses all camera feedback")
	game.Game_Settings.Shaking_Camera = true
	check(world.damage_shake_max_pixels==10.0 and world.damage_shake_strength==1.0 and world.max_shake_amount==100.0,"threshold change preserves the configured heavy and legacy camera ceilings")
	for invalid:float in [0.0,-1.0,INF,NAN]: world.add_damage_camera_shake(invalid)
	check(world._damage_shake_pending_peak==0.0,"invalid or zero camera damage cannot create an impulse")
	world.add_damage_camera_shake(48.0)
	check(is_equal_approx(world._damage_shake_pending_peak,0.75*sqrt(48.0/50.0)),"48 HP stays in the slight camera-shake tier")
	world._update_damage_camera_shake(0.0)
	check((world.camera_2d.offset*world.camera_2d.zoom).x>0.0 and (world.camera_2d.offset*world.camera_2d.zoom).x<1.0,"slight damage feedback reaches Camera2D without a strong jolt")
	for i:int in range(120): world.add_damage_camera_shake(1000000.0)
	check(world._damage_shake_pending_peak==10.0 and world._damage_shake_pending_sum<=80.0,"same-frame mass hits remain bounded at the configured ceiling")
	world._update_damage_camera_shake(0.0)
	check(world._damage_shake_pixels==10.0,"heavy hits retain the configured 10-pixel camera ceiling")
	world.camera_shake_amount = world.max_shake_amount
	world._update_damage_camera_shake(0.0)
	check(is_equal_approx((world.camera_2d.offset*world.camera_2d.zoom).x,10.0),"damage and legacy screen feedback use the stronger channel rather than adding twice")
	world.camera_shake_amount = 0.0
	var remaining:float = world._damage_shake_time_left
	world.add_damage_camera_shake(1.0)
	world._update_damage_camera_shake(0.0)
	check(world._damage_shake_time_left==remaining and world._damage_shake_pixels==10.0,"weak damage does not prolong or replace a strong camera impulse")
	var positive:bool = false
	var negative:bool = false
	var bounded:bool = true
	seed(19127)
	var expected_random:float = randf()
	seed(19127)
	for i:int in range(30):
		world.add_damage_camera_shake(1000.0)
		world._update_damage_camera_shake(1.0/60.0)
		var pixels:Vector2 = world.camera_2d.offset*world.camera_2d.zoom
		positive = positive or pixels.x>0.5
		negative = negative or pixels.x< -0.5
		bounded = bounded and absf(pixels.x)<=10.001 and absf(pixels.y)<=10.001
	check(positive and negative and bounded,"continuous heavy hits oscillate in both directions without exceeding the camera cap")
	check(is_equal_approx(randf(),expected_random),"stronger camera feedback still consumes no combat RNG")
	world._update_damage_camera_shake(1.0)
	world._update_damage_camera_shake(0.0)
	check(world.camera_2d.offset==Vector2.ZERO,"camera returns to center once damage stops")
	world.camera_shake_amount = world.max_shake_amount
	world._damage_shake_elapsed = 0.0
	world._update_damage_camera_shake(0.0)
	check(is_equal_approx((world.camera_2d.offset*world.camera_2d.zoom).x,10.0),"legacy skill effects can also reach the configured screen-shake ceiling")
	world._update_damage_camera_shake(2.1)
	world._update_damage_camera_shake(0.0)
	check(world.camera_shake_amount==0.0 and world.camera_2d.offset==Vector2.ZERO,"larger legacy shake retains a bounded recovery time rather than a six second tail")
	game.Game_Settings.Shaking_Camera = false
	world._update_damage_camera_shake(0.0)
	check(world.camera_shake_amount==0.0 and world.camera_2d.offset==Vector2.ZERO,"turning off camera shake clears both damage and legacy channels")
	game.Game_Settings.Shaking_Camera = old_setting

func gpu_camera_check() -> void:
	var old_camera:Camera2D = world.camera_2d
	var old_setting:bool = game.Game_Settings.Shaking_Camera
	var game_process:bool = game.is_processing()
	var game_physics:bool = game.is_physics_processing()
	var world_process:bool = world.is_processing()
	var world_physics:bool = world.is_physics_processing()
	# Game.process_always otherwise repositions/rescales the active world camera.
	game.set_process(false)
	game.set_physics_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.position = Vector2(128,128)
	viewport.add_child(sprite)
	var camera := Camera2D.new()
	camera.position = Vector2(128,128)
	viewport.add_child(camera)
	camera.make_current()
	world.camera_2d = camera
	for zoom:Vector2 in [Vector2.ONE,Vector2(0.5,0.75)]:
		camera.zoom = zoom
		game.Game_Settings.Shaking_Camera = false
		world._update_damage_camera_shake(0.0)
		camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		var baseline:Vector2 = image_centroid(viewport.get_texture().get_image())
		game.Game_Settings.Shaking_Camera = true
		world.add_damage_camera_shake(1000000.0)
		world._update_damage_camera_shake(0.0)
		var expected:Vector2 = -camera.offset*camera.zoom
		camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		var shaken:Vector2 = image_centroid(viewport.get_texture().get_image())
		check((shaken-baseline).distance_to(expected)<1.25 and absf(shaken.x-baseline.x)>9.0,"GPU camera motion visibly reaches the configured ceiling at zoom "+str(zoom))
		check(sprite.position==Vector2(128,128) and camera.position==Vector2(128,128),"screen shake changes rendering offset, not object or camera center positions")
		game.Game_Settings.Shaking_Camera = false
		world._update_damage_camera_shake(0.0)
		camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		check(image_centroid(viewport.get_texture().get_image()).distance_to(baseline)<0.1,"GPU camera pixels return to center when shaking is disabled")
	world.camera_2d = old_camera
	game.Game_Settings.Shaking_Camera = old_setting
	game.set_process(game_process)
	game.set_physics_process(game_physics)
	world.set_process(world_process)
	world.set_physics_process(world_physics)
	viewport.queue_free()
	await process_frame
