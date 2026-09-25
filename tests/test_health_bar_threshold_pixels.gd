extends SceneTree
## Actual GPU readback: normal HP numerals are solid black above half,
## solid white at and below half, and never have an outline or shadow.

var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool, description:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HEALTH_TEXT_GPU_FAIL " + description)
	else:
		print("PASS: ",description)

func glyph_pixels(label:Label) -> Dictionary:
	await RenderingServer.frame_post_draw
	var drawn:Image = root.get_texture().get_image()
	label.hide()
	await RenderingServer.frame_post_draw
	var blank:Image = root.get_texture().get_image()
	label.show()
	var transform:Transform2D = root.get_final_transform() * label.get_global_transform_with_canvas()
	var a:Vector2 = transform * Vector2.ZERO
	var b:Vector2 = transform * label.size
	var left:int = clampi(int(floor(minf(a.x,b.x))) - 3,0,drawn.get_width()-1)
	var right:int = clampi(int(ceil(maxf(a.x,b.x))) + 3,0,drawn.get_width()-1)
	var top:int = clampi(int(floor(minf(a.y,b.y))) - 3,0,drawn.get_height()-1)
	var bottom:int = clampi(int(ceil(maxf(a.y,b.y))) + 3,0,drawn.get_height()-1)
	var changed:int = 0
	var dark:int = 0
	var bright:int = 0
	for y:int in range(top,bottom+1):
		for x:int in range(left,right+1):
			var actual:Color = drawn.get_pixel(x,y)
			var without:Color = blank.get_pixel(x,y)
			if absf(actual.r-without.r)+absf(actual.g-without.g)+absf(actual.b-without.b) < 0.16:
				continue
			changed += 1
			if actual.r < 0.11 and actual.g < 0.11 and actual.b < 0.11: dark += 1
			if actual.r > 0.89 and actual.g > 0.89 and actual.b > 0.89: bright += 1
	return {"changed":changed,"dark":dark,"bright":bright,"box":Rect2i(left,top,right-left+1,bottom-top+1)}

func run() -> void:
	create_timer(45.0,true,false,true).timeout.connect(func(): push_error("HEALTH_TEXT_GPU_TIMEOUT"); quit(2))
	var game:Node = root.get_node("Game")
	var saved_settings:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = false
	game.Game_Settings.Map_Background = "blue"
	root.size = Vector2i(540,960)
	var world:Node2D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node2D
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.control.get_parent().hide()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	world.camera_2d.global_position = center
	world.camera_2d.reset_smoothing()
	world.camera_2d.force_update_scroll()
	var unit:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Node2D
	unit.Team = "Team0"
	unit.position = center
	unit.Max_health = 100
	world.add_child(unit,true)
	unit.set_process(false)
	unit.set_physics_process(false)
	unit.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	world.set_process(false)
	world.set_physics_process(false)
	var hud:Node = unit.health_bar
	var label:Label = hud.label
	hud.suppress_floating_text = true
	# Render the actual HUD Label over an opaque, static screen color. This
	# isolates glyph pixels from moving actors and from white map highlights.
	var isolated:CanvasLayer = CanvasLayer.new()
	isolated.layer = 200
	root.add_child(isolated)
	var backdrop:ColorRect = ColorRect.new()
	backdrop.color = Color(0.35,0.35,0.35,1.0)
	backdrop.size = root.get_visible_rect().size
	isolated.add_child(backdrop)
	var authored_size:Vector2 = label.size
	label.reparent(isolated,false)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	label.pivot_offset = Vector2.ZERO
	label.size = authored_size
	label.position = Vector2(-280,420)
	label.scale = Vector2.ONE * 0.35
	await process_frame
	await process_frame
	# New CanvasLayers may need another rendered frame before GPU readback.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for amount:int in [100,50]:
		hud.health_changed.emit(amount,amount,100,false)
		var pixels:Dictionary = await glyph_pixels(label)
		print("HEALTH_TEXT_GPU_METRIC health=",amount," text=",label.text," pixels=",pixels)
		check(pixels.changed > 15,"%d%%: actual health numerals are visible in the GPU frame"%amount)
		if amount > 50:
			check(pixels.dark > 15 and pixels.bright == 0,"above 50%: rendered numeral is pure black, not outlined white")
		else:
			check(pixels.bright > 15 and pixels.dark == 0,"at 50%: rendered numeral is pure white, not outlined black")
	world.queue_free()
	isolated.queue_free()
	await process_frame
	game.Game_Settings = saved_settings
	print("HEALTH_TEXT_GPU_RESULT checks=",checks," failures=",failures)
	quit(1 if failures > 0 else 0)
