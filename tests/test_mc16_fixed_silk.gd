extends "res://tests/test_mc16_spider_drowned.gd"
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
	check(not target.Buff_Dic.get(spider.get_instance_id(),{}).is_empty(),"live silk retains its slow")
	check(not target.dizziness and spider._lunge_left==0.0,"live silk alone does not stun or trigger a web pounce")
	# Exact geometry: freeze along the strand, rather than snapping to body contact.
	reset_silk(a)
	wall_touch(a,center+Vector2(-200,-80))
	var tail:Vector2 = center+Vector2(100,20)
	var contact:Vector2 = center+Vector2(150,0)
	var point:Vector2 = a.wall_attachment_point(contact,Vector2.LEFT,null,tail)
	check(absf(point.x-(contact.x-1.5))<0.001,"new endpoint lies on touched wall plane")
	check(geometry.segment_distance(a._point(a.anchor),point,tail)<0.001,"wall fixation preserves the pre-contact silk direction")
	check(point.distance_to(contact)>20.0,"fixture distinguishes abdomen strand from body collision point")
	a._contact_left = 0.0
	a.touch_wall(point)
	check(geometry.segment_distance(a.lines(false)[0].a,a.lines(false)[0].b,tail)<0.001,"fixed segment uses the aligned endpoint without later replacement")
	reset_silk(a)
	wall_touch(a,center+Vector2(10,-200))
	point = a.wall_attachment_point(center+Vector2(50,0),Vector2.LEFT,null,center+Vector2(20,0))
	check(point.distance_to(center+Vector2(50,0))<3.0,"grazing contact does not project an anchor hundreds of pixels away")
	# Real finite wall: reject a plane intersection outside the physical shape.
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
	point = a.wall_attachment_point(center+Vector2(144,-260),Vector2.LEFT,wall,center+Vector2(100,-240))
	check(point.is_equal_approx(center+Vector2(142.5,-240)),"short wall falls back to a validated abdomen projection")
	check(a._on_wall_surface(point,Vector2.LEFT,wall),"fallback really touches the same finite wall")
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
		var line:Dictionary = a.lines(false)[0]
		check(geometry.segment_distance(line.a,line.b,spider.silk_tail_position())<0.01,"real wall collision fixes silk collinearly with the abdomen endpoint")
		check(absf(line.b.x-(wall.global_position.x-7.5))<0.1,"real anchor stays on wall surface, not at character center")
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
