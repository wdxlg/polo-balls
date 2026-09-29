extends "res://tests/test_mc_frontier.gd"
## Deliberately arranged GPU presentation, NOT gameplay verification or an unlock shortcut.
var captures:Array[Image] = []
var preview_camera:Camera2D
func capture(unit:Node2D,zoom:float) -> void:
	unit.side_status_ui_enabled = false
	unit.health_bar.hide()
	unit.set_process(true)
	unit.visual_mob()
	preview_camera.global_position = unit.global_position
	preview_camera.zoom = Vector2.ONE*zoom
	preview_camera.reset_smoothing()
	preview_camera.force_update_scroll()
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var screen:Image = root.get_texture().get_image()
	var point:Vector2 = root.get_final_transform()*unit.get_global_transform_with_canvas().origin
	print("PREVIEW_SCALE ",unit.role_key() if unit.has_method("role_key") else "cart"," root=",unit.global_scale," image=",unit.image.scale," camera=",preview_camera.zoom," body_z=",unit.image.z_index," visible=",unit.image.is_visible_in_tree()," color=",unit.image.modulate," offset=",unit.image.position)
	var region:Rect2i = Rect2i(Vector2i(point)-Vector2i(95,70),Vector2i(190,140)).intersection(Rect2i(Vector2i.ZERO,screen.get_size()))
	var frame:Image = screen.get_region(region)
	frame.resize(380,280,Image.INTERPOLATE_NEAREST)
	captures.append(frame)
	unit.queue_free()
	await process_frame
func run() -> void:
	var center:Vector2 = await setup_world()
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.enabled = false
	preview_camera = Camera2D.new()
	preview_camera.position_smoothing_enabled = false
	world.add_child(preview_camera)
	preview_camera.make_current()
	create_timer(30.0).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	for i:int in range(3):
		moss.growth_left = 0.0
		moss.cultivate()
	for i:int in range(moss.patches.size()): moss.patches[i].layers = 1+i%3
	moss.frontier_fx.particles.clear()
	await capture(moss,3.5)
	var sword:Node2D = actor("木剑",center)
	sword.sword_charge = 1.0
	sword.direction = Vector2.RIGHT
	sword.brace_left = 0.3
	await capture(sword,5.0)
	var broken:Node2D = actor("木剑",center)
	broken.spend_durability(59)
	broken.repair_lock = 0.0
	broken.start_repair()
	broken.repair_left = 1.15
	await capture(broken,5.0)
	var shrieker:Node2D = actor("监守者",center)
	shrieker.warnings = 3
	await capture(shrieker,5.0)
	var w:Node2D = actor("监守者",center)
	# Stage the POST-SUMMON form only for this preview; production scenes always start DORMANT.
	w.form = w.Form.AWAKE
	w._form_stats(true)
	w.warnings = 4
	w.anger = 85.0
	w.sonic_origin = center
	w.sonic_end = center+Vector2(170,0)
	w.sonic_left = 0.0 # Show the recognizable standing post-summon silhouette.
	w.direction = Vector2.RIGHT
	await capture(w,4.4)
	var cart:Node2D = actor("矿车",center)
	cart.direction = Vector2.RIGHT
	await process_frame
	cart.rails.set_physics_process(false)
	cart.idle_left = 0.0
	cart.start_charge()
	cart.charge_left = 0.0
	cart.launch_rush()
	cart.global_position = cart.rails.node_point(cart._travel_from).lerp(cart.rails.node_point(cart._travel_to),0.5)
	cart.drive_speed = 460.0
	cart.rail_powered = true
	cart._motion_hold = 1.0
	cart._visual_move_speed = 460.0
	cart.cart_fx.particles.clear()
	await capture(cart,4.4)
	var montage:Image = Image.create(1200,640,false,Image.FORMAT_RGB8)
	montage.fill(Color(0.075,0.10,0.11))
	for i:int in range(captures.size()):
		captures[i].convert(Image.FORMAT_RGB8)
		montage.blit_rect(captures[i],Rect2i(Vector2i.ZERO,Vector2i(380,280)),Vector2i(10+(i%3)*400,10+int(i/3)*320))
	montage.save_png("res://tests/mc_frontier_preview.png")
	montage.save_jpg("res://tests/mc_frontier_preview.jpg",0.9)
	print("FRONTIER GPU PREVIEW: 6 real rendered states saved (presentation fixtures, not gameplay tests)")
	finish(0)
