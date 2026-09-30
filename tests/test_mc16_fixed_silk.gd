extends "res://tests/test_mc16_spider_drowned.gd"
var capture_camera:Camera2D
func capture_silk(net:Node,wall:StaticBody2D,label:String) -> void:
	var directory:String = ""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--silk-capture="): directory = argument.trim_prefix("--silk-capture=")
	if directory.is_empty() or DisplayServer.get_name()=="headless": return
	root.content_scale_size = Vector2i(960,640)
	root.size = Vector2i(960,640)
	if not is_instance_valid(capture_camera):
		capture_camera = Camera2D.new()
		world.add_child(capture_camera)
		var face := Polygon2D.new()
		face.polygon = PackedVector2Array([Vector2(-6,-150),Vector2(6,-150),Vector2(6,150),Vector2(-6,150)])
		face.color = Color(0.18,0.2,0.24)
		face.z_as_relative = false
		face.z_index = -4
		wall.add_child(face)
	capture_camera.global_position = wall.global_position+Vector2(-160,0)
	capture_camera.zoom = Vector2.ONE*1.4
	capture_camera.make_current()
	capture_camera.force_update_scroll()
	net.queue_redraw()
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	check(not image.is_empty(),"GPU handoff frame is readable: "+label)
	if image.is_empty(): return
	var line:Dictionary = net.lines()[0]
	var sample:Vector2 = root.get_canvas_transform()*((Vector2(line.a)+Vector2(line.b))*0.5)
	var bright:bool = false
	for y:int in range(-3,4):
		for x:int in range(-3,4):
			var pixel:Vector2i = Vector2i(sample)+Vector2i(x,y)
			if pixel.x<0 or pixel.y<0 or pixel.x>=image.get_width() or pixel.y>=image.get_height(): continue
			var color:Color = image.get_pixelv(pixel)
			if color.r>0.8 and color.g>0.8 and color.b>0.8: bright = true
	check(bright,"GPU draws silk at its reported contact geometry: "+label)
	check(image.save_png(directory.path_join(label+".png"))==OK,"GPU handoff frame saved outside the project: "+label)
	print("SILK_CAPTURE ",label," ",image.get_size())
func fixed(net:Node,a:Vector2,b:Vector2) -> void:
	reset_silk(net)
	wall_touch(net,center+a)
	wall_touch(net,center+b)
	net.anchor = {}
func tether(net:Node,a:Vector2,b:Vector2) -> void:
	net.anchor = net._make_anchor(center+a,null)
	net.unit.global_position += center+b-net.unit.silk_tail_position()
func refresh(nets:Array) -> int:
	var total:int = 0
	for net:Node in nets:
		net._update_crossings()
		total += net.webs.size()
	return total
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(55.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	var spider:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(180,0))
	var friend:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(400,0))
	var opponent:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(600,0),"Team1")
	var target:Node = dummy(center)
	await process_frame
	await process_frame
	var a:Node = spider.silk_network
	var b:Node = friend.silk_network
	var c:Node = opponent.silk_network
	check(spider.web_radius==8.0,"native cobweb diameter reduced from 32 to 16; trigger matches")
	check(a.COBWEB_TEXTURE.get_size()==Vector2(16,16),"small web still uses unchanged native texture")
	tether(a,Vector2(-100,-100),Vector2(100,100))
	tether(b,Vector2(-100,100),Vector2(100,-100))
	check(a.lines().size()==1 and a.lines(false).is_empty(),"live silk remains drawn but is excluded from fixed-line list")
	check(geometry.crossing(a.lines()[0].a,a.lines()[0].b,b.lines()[0].a,b.lines()[0].b)!=null,"live/live fixture really crosses")
	check(refresh([a,b])==0,"crossing two live body tethers creates no cobweb")
	fixed(b,Vector2(-100,0),Vector2(100,0))
	check(refresh([a,b])==0,"own live tether against friendly fixed line creates no cobweb")
	fixed(a,Vector2(0,-100),Vector2(0,100))
	check(refresh([a,b])==1,"two completed friendly wall strands create exactly one web")
	tether(a,Vector2(-100,-100),Vector2(100,100))
	tether(b,Vector2(-100,100),Vector2(100,-100))
	check(refresh([a,b])==1,"adding crossing body tethers creates no extra webs")
	spider.global_position += Vector2(160,30)
	friend.global_position += Vector2(-160,40)
	check(refresh([a,b])==1,"moving spiders do not create or relocate fixed crossing webs")
	for net:Node in [a,b]:
		for web:Dictionary in net.webs.values(): check(web.point.is_equal_approx(center),"fixed web stays at its wall-line intersection")
	fixed(b,Vector2(0,100),Vector2(100,100))
	check(refresh([a,b])==0,"shared wall endpoint still creates no web")
	reset_silk(b)
	fixed(c,Vector2(-100,0),Vector2(100,0))
	check(refresh([a,b,c])==0,"enemy fixed silk does not participate in friendly cobwebs")
	reset_silk(c)
	# The spider's own live tether crossing its own fixed line is also excluded.
	fixed(a,Vector2(-100,0),Vector2(100,0))
	tether(a,Vector2(-100,-100),Vector2(100,100))
	check(refresh([a])==0,"own fixed/live crossing does not create a web")
	# Live silk still deals accepted low damage/slow, not web stun or pounce.
	reset_silk(a)
	tether(a,Vector2(-150,-80),Vector2(150,-80))
	target.global_position = center+Vector2(0,-80)
	target.dizziness = false
	spider._lunge_left = 0.0
	var hp:float = target.health
	a._tick_contacts()
	check(target.health<hp,"excluding live silk from webs does not remove its damage")
	check(absf(target.motion_speed_factor()-spider.silk_slow_multiplier)<0.001,"live silk applies its actual-motion slow, not a Speed stat")
	check(not target.dizziness and spider._lunge_left==0.0,"live silk alone does not stun or trigger a web pounce")
	# Fallback geometry: with no wall shape in reach (surface-less fixture) the
	# exact contact stands, dipped along the strand by at most WALL_SINK.
	reset_silk(a)
	wall_touch(a,center+Vector2(-200,-80))
	var tail:Vector2 = center+Vector2(100,20)
	var contact:Vector2 = center+Vector2(150,0)
	var attachment:Dictionary = a.wall_attachment(contact,Vector2.LEFT,null,tail)
	var point:Vector2 = attachment.point
	var fallback_dir:Vector2 = (tail-(center+Vector2(-200,-80))).normalized()
	check(point.is_equal_approx(contact+fallback_dir*a.WALL_SINK),"no reachable wall shape: exact contact, sunk along the strand only")
	check(attachment.get("surface")==null,"surface-less fixture keeps a plain world-space anchor")
	a._contact_left = 0.0
	a.touch_wall(point)
	check(a.lines(false).size()==1 and a.lines(false)[0].b.is_equal_approx(point),"fixed segment keeps the attached endpoint without later replacement")
	reset_silk(a)
	wall_touch(a,center+Vector2(10,-200))
	point = (a.wall_attachment(center+Vector2(50,0),Vector2.LEFT,null,center+Vector2(20,0))).point
	check(point.distance_to(center+Vector2(50,0))<a.WALL_SINK+3.0,"grazing contact does not project an anchor hundreds of pixels away")
	# Real finite wall: a strand aimed past the shape cannot extend to it, so the
	# validated body contact holds; a strand aimed AT the shape extends until it
	# meets the wall, and that meeting point is the endpoint.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12,60)
	shape.shape = rectangle
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(150,-260)
	park_others([spider])
	await physics_frame
	await physics_frame
	reset_silk(a)
	wall_touch(a,center+Vector2(-200,-380))
	point = (a.wall_attachment(center+Vector2(144,-260),Vector2.LEFT,wall,center+Vector2(100,-240))).point
	check(point.distance_to(center+Vector2(144,-260))<=a.WALL_SINK+0.01,"strand missing a short wall keeps the validated body contact")
	check(a._on_wall_surface(point,Vector2.LEFT,wall),"missed-extension fallback still touches the same finite wall")
	check(a._inside_surface(point,wall),"strand end sits inside the wall so the wall covers it")
	a._contact_left = 0.0
	a.touch_wall(point,wall,center+Vector2(100,-240))
	check(Vector2(a.lines()[0].b).is_equal_approx(center+Vector2(100,-240)),"short-wall fallback starts at the abdomen instead of snapping sideways")
	a.advance(0.04)
	check(geometry.segment_distance(center+Vector2(100,-240),point,a.lines()[0].b)<0.01,"short-wall fallback moves continuously toward its validated contact")
	a.advance(0.1)
	check(Vector2(a.lines()[0].b).is_equal_approx(point),"short-wall fallback settles on the actual wall")
	reset_silk(a)
	wall_touch(a,center+Vector2(0,-240))
	attachment = a.wall_attachment(center+Vector2(144,-260),Vector2.LEFT,wall,center+Vector2(100,-240))
	point = attachment.point
	check(attachment.get("surface")==wall,"extension attaches to the wall the strand reaches")
	check(point.is_equal_approx(center+Vector2(144.0+a.WALL_SINK,-240)),"strand extends horizontally until it meets the wall (%s)" % str(point-center))
	check(geometry.segment_distance(center+Vector2(0,-240),point,center+Vector2(100,-240))<0.001,"extended endpoint stays on its own strand line")
	check(a._inside_surface(point,wall),"extended strand end sinks inside the wall")
	# A wall thinner than the sink keeps the end on its face instead of poking through.
	rectangle.size = Vector2(3,60)
	await physics_frame
	await physics_frame
	reset_silk(a)
	wall_touch(a,center+Vector2(-200,-380))
	point = (a.wall_attachment(center+Vector2(148.5,-260),Vector2.LEFT,wall,center+Vector2(100,-240))).point
	check(point.is_equal_approx(center+Vector2(148.5,-260)),"thin wall fallback keeps the end on its face (%s)" % str(point-center))
	reset_silk(a)
	wall_touch(a,center+Vector2(0,-240))
	point = (a.wall_attachment(center+Vector2(148.5,-260),Vector2.LEFT,wall,center+Vector2(100,-240))).point
	check(point.is_equal_approx(center+Vector2(148.5,-240)),"thin wall: extension stops exactly on the face (%s)" % str(point-center))
	a._contact_left = 0.0
	a.touch_wall(point,wall,center+Vector2(100,-240))
	check(Vector2(a.lines()[0].b).is_equal_approx(center+Vector2(100,-240)),"thin-wall handoff does not jump across the abdomen-to-wall gap")
	a.advance(0.13)
	check(Vector2(a.lines()[0].b).is_equal_approx(point),"thin-wall handoff never extends through the far face")
	# Actual CharacterBody move_and_slide collision, before reflected facing changes.
	rectangle.size = Vector2(12,300)
	wall.global_position = center+Vector2(200,-260)
	spider.global_position = center+Vector2(120,-260)
	spider.direction = Vector2.RIGHT
	spider.set_character_visual_flip_h(true)
	spider.dizziness = false
	spider._lunge_left = 0.0
	spider.Repel = Vector2.ZERO
	reset_silk(a)
	wall_touch(a,center+Vector2(-200,-340))
	a._contact_left = 0.0
	await physics_frame
	for i:int in range(100):
		spider.direction = Vector2.RIGHT
		spider.move(200.0,1.0/60.0)
		if not a.segments.is_empty(): break
		await physics_frame
	check(a.segments.size()==1,"real collision creates one fixed segment, not duplicate attachments")
	if not a.segments.is_empty():
		var incoming_tail:Vector2 = spider.silk_tail_position()
		var pinned:Vector2 = a._point(a.segments[0].end)
		var initial:Dictionary = a.lines()[0]
		check(initial.b.is_equal_approx(incoming_tail),"wall handoff starts at the incoming abdomen without an endpoint jump (%.2f px)" % Vector2(initial.b).distance_to(incoming_tail))
		check(a.lines(false).is_empty(),"an extending strand cannot create a completed-wall cobweb yet")
		await capture_silk(a,wall,"handoff_start")
		a.advance(0.03)
		var partial:Vector2 = a.lines()[0].b
		check(partial.distance_to(incoming_tail)>0.01 and partial.distance_to(incoming_tail)<pinned.distance_to(incoming_tail)-0.01,"wall handoff extends progressively instead of replacing the whole endpoint")
		check(geometry.segment_distance(incoming_tail,pinned,partial)<0.01,"handoff stays on the actual abdomen-to-wall extension")
		var old_facing:bool = spider._visual_facing_flipped_h
		spider.set_character_visual_flip_h(not old_facing)
		check(a.lines()[0].b.is_equal_approx(partial),"reflected facing does not teleport the strand being attached")
		spider.set_character_visual_flip_h(old_facing)
		game.now_stop_state = true
		a.advance(1.0)
		check(a.lines()[0].b.is_equal_approx(partial),"pause freezes the wall handoff")
		game.now_stop_state = false
		await capture_silk(a,wall,"handoff_partial")
		if a.has_method("pack_lines"):
			var packet:Array = a.pack_lines()
			b.receive_snapshot(packet,[])
			var received:Array = b.remote_line_points(packet[0])
			check(Vector2(received[1]).is_equal_approx(partial),"snapshot starts at the displayed handoff endpoint")
			b._clock += 0.03
			var continued:Array = b.remote_line_points(packet[0])
			check(Vector2(continued[1]).distance_to(partial)>0.01 and Vector2(continued[1]).distance_to(pinned)>0.01,"replica continues the handoff between snapshots")
			b._clock += 0.1
			check(Vector2(b.remote_line_points(packet[0])[1]).is_equal_approx(pinned),"replica settles exactly on the real wall endpoint")
			b.receive_snapshot(a.pack_lines(),[])
			b._clock += 0.02
			var before_rebase:Vector2 = b.remote_line_points(b._remote_lines[0])[1]
			var rebase:Vector2 = Vector2(27,-19)
			b.development_rebase(rebase)
			check(Vector2(b.remote_line_points(b._remote_lines[0])[1]).is_equal_approx(before_rebase+rebase),"map merging rebases both the displayed handoff and its wall target")
			var legacy:Array = [initial.a,pinned,false]
			check(Vector2(b.remote_line_points(legacy)[1]).is_equal_approx(pinned),"legacy static snapshots still keep their exact endpoints")
		else:
			check(false,"wall handoff is represented in replica snapshots")
		a.advance(0.1)
		check(a.lines(false).size()==1,"the extended strand becomes completed only after reaching the wall")
		await capture_silk(a,wall,"handoff_finished")
		var line:Dictionary = a.lines(false)[0]
		check(geometry.segment_distance(line.a,line.b,spider.silk_tail_position())<0.01,"real wall collision fixes silk collinearly with the abdomen endpoint")
		check(a._inside_surface(line.b,wall),"real anchor end sits inside the wall so the wall covers it")
		check(a._on_wall_surface(line.b,Vector2.LEFT,wall),"real anchor end touches the same wall")
		var inward:float = (line.b-(wall.global_position+Vector2(-6.0,0))).dot(Vector2.RIGHT)
		check(inward>0.0 and inward<=a.WALL_SINK+0.01,"real anchor dips at most WALL_SINK into the wall face (%.2f)" % inward)
		var old_end:Vector2 = line.b
		wall.global_position += Vector2(10,-15)
		check(a.lines(false)[0].b.is_equal_approx(old_end+Vector2(10,-15)),"aligned endpoint follows a moving wall in local coordinates")
	wall.queue_free()
	await process_frame
	await process_frame
	a.advance(0.02)
	check(a.lines(false).is_empty(),"destroyed wall invalidates its fixed strand")
	print("MC16_FIXED_SILK_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
