extends "res://tests/test_high_damage_feedback.gd"
## Exercises the actual render-only body effect and Camera2D after edits through the settings UI.


var fx_script:Script
class RenderProbe extends Node2D:
	var health:float = 1000.0
	var hurt_shake_enabled:bool = true
	func is_combat_runtime_active() -> bool: return true

func image_centroid(image:Image) -> Vector2:
	var sum:Vector2 = Vector2.ZERO
	var count:int = 0
	for y:int in image.get_height():
		for x:int in image.get_width():
			if image.get_pixel(x,y).a>0.5:
				sum += Vector2(x,y)
				count += 1
	return sum/maxi(count,1)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This pixel-measurement test requires a real GPU renderer")
		quit(2)
		return
	create_timer(45,true,false,true).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.High_Damage_Feedback = false
	game.Game_Settings.Minecraft_Clouds = false
	game.now_stop_state = false
	game.reset_feedback_settings("Shaking_Camera",false)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	center = world.return_map_world_rect(world._current_map_node()).get_center()
	attacker = spawn_actor("res://scenes/ball.tscn","Team0",Vector2(-38,0))
	target = spawn_actor("res://scenes/ball.tscn","Team1",Vector2(38,0))
	world.control.hide()
	fx_script = load("res://scripts/effects/character_hurt_shake.gd")
	await gpu_camera_check()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	print("SHAKE_PERCEPTION_GPU checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func gpu_camera_check() -> void:
	var original_camera:Camera2D = world.camera_2d
	var original_settings:Dictionary = game.Game_Settings.duplicate(true)
	var processes:Array = [game.is_processing(),game.is_physics_processing(),world.is_processing(),world.is_physics_processing()]
	game.set_process(false)
	game.set_physics_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var actor := RenderProbe.new()
	actor.position = Vector2(128,128)
	viewport.add_child(actor)
	var graphics := Node2D.new()
	actor.add_child(graphics)
	var sprite := Sprite2D.new()
	var pixels := Image.create(32,32,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(pixels)
	graphics.add_child(sprite)
	var effect:Node = fx_script.new()
	effect.actor = actor
	effect.graphics = graphics
	actor.add_child(effect)
	var camera := Camera2D.new()
	camera.position = Vector2(128,128)
	viewport.add_child(camera)
	camera.make_current()
	world.camera_2d = camera
	game.Game_Settings.Shaking_Camera = true
	game.reset_feedback_settings("Shaking_Camera",false)
	await settle_frame()
	var baseline:Vector2 = image_centroid(viewport.get_texture().get_image())
	for channel:String in ["Body","Camera"]:
		var previous:float = 0.0
		for damage:float in [51.0,100.0,250.0]:
			var moved:Vector2 = await rendered_offset(viewport,camera,effect,baseline,channel,damage)
			check(moved.length()>previous+0.5,"GPU "+channel+" visibly grows with actual damage "+str(damage))
			previous = moved.length()
		game.reset_feedback_settings("Shaking_Camera",false)
		var normal:Vector2 = await rendered_offset(viewport,camera,effect,baseline,channel,100.0)
		(world.control._feedback_spins.Feedback_Body_Strong as SpinBox).value = 20.0
		var stronger:Vector2 = await rendered_offset(viewport,camera,effect,baseline,channel,100.0)
		check(stronger.length()>normal.length()*1.8,"GPU "+channel+" doubles visibly after a strong-tier UI edit")
		(world.control._feedback_spins.Feedback_Body_Strong as SpinBox).value = 64.0
		var low:Vector2 = await rendered_offset(viewport,camera,effect,baseline,channel,51.0)
		var high:Vector2 = await rendered_offset(viewport,camera,effect,baseline,channel,250.0)
		check(high.length()>low.length()*1.6,"GPU "+channel+" retains damage growth at maximum UI strength")
		game.reset_feedback_settings("Shaking_Camera",false)
		var light_default:Vector2 = await rendered_offset(viewport,camera,effect,baseline,channel,30.0)
		(world.control._feedback_spins.Feedback_Body_Tiny as SpinBox).value = 1.0
		(world.control._feedback_spins.Feedback_Body_Light as SpinBox).value = 5.0
		(world.control._feedback_spins.Feedback_Body_Strong as SpinBox).value = 20.0
		var light_custom:Vector2 = await rendered_offset(viewport,camera,effect,baseline,channel,30.0)
		check(light_custom.length()>light_default.length()+2.0,"GPU "+channel+" responds visibly to the saved 1/5/20 profile")
		game.reset_feedback_settings("Shaking_Camera",false)
	for strength:float in [10.0,20.0]:
		(world.control._feedback_spins.Feedback_Body_Strong as SpinBox).value = strength
		var moved:Vector2 = await rendered_offset(viewport,camera,effect,baseline,"Legacy",100.0)
		check(absf(moved.x+strength)<1.1,"GPU legacy skill shake follows strong setting "+str(strength))
	effect.stop()
	world.camera_2d = original_camera
	game.Game_Settings = original_settings
	world._sync_feedback_settings()
	game.set_process(processes[0])
	game.set_physics_process(processes[1])
	world.set_process(processes[2])
	world.set_physics_process(processes[3])
	viewport.queue_free()
	await process_frame

func settle_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func rendered_offset(viewport:SubViewport,camera:Camera2D,effect:Node,baseline:Vector2,channel:String,damage:float) -> Vector2:
	effect.stop()
	game.Game_Settings.Shaking_Camera = false
	world._update_damage_camera_shake(0.0)
	game.Game_Settings.Shaking_Camera = true
	world._damage_shake_elapsed = 0.0
	if channel=="Body":
		effect.kick(damage)
		effect.set_process(false)
		effect._present()
	elif channel=="Camera":
		world.add_damage_camera_shake(damage)
		world._update_damage_camera_shake(0.0)
	else:
		world.camera_shake_amount = damage
		world._update_damage_camera_shake(0.0)
	camera.force_update_scroll()
	await settle_frame()
	var moved:Vector2 = image_centroid(viewport.get_texture().get_image())-baseline
	print("SHAKE_GPU ",channel," damage=",damage," strong=",game.Game_Settings.Feedback_Body_Strong," shift=",moved)
	return moved
