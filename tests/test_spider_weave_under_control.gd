extends "res://tests/test_mc16_spider_drowned.gd"
# 2026-09-30 user rule: the spider weaves silk on EVERY obstacle contact, no
# matter whether it is stunned, knocked back, airborne, damage-disabled or under
# any other control. Damage/slow/lunge keep their own gates. Real World, real
# StaticBody wall, real shared knockback/stun/airborne/damage-disable APIs.
var spider:Node2D
var net:Node
var wall:StaticBody2D
# Lambdas capture locals by value; probes record into these members instead.
var stunned_at_touch:bool = false
var mid_air:bool = false
func make_wall(point:Vector2,size:Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	world.add_child(body)
	body.global_position = point
	return body
func prepare(offset:float = 110.0) -> void:
	reset_silk(net)
	spider.Repel = Vector2.ZERO
	spider.velocity = Vector2.ZERO
	spider.global_position = wall.global_position+Vector2(-offset,0)
	await physics_frame
	reset_silk(net)
## Runs physics frames until the spider has a wall anchor; returns whether it got one.
func wait_anchor(frames:int,probe:Callable = Callable()) -> bool:
	for i:int in range(frames):
		await physics_frame
		if probe.is_valid(): probe.call()
		if not net.anchor.is_empty(): return true
	return false
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
	create_timer(60.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	var map_rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	center = map_rect.get_center()
	spider = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(0,-260))
	var target:Node2D = dummy(center+Vector2(0,420))
	await process_frame
	await process_frame
	spider.mc_native_animation.set_process(false)
	net = spider.silk_network
	wall = make_wall(center+Vector2(150,-260),Vector2(12,220))
	check(spider.has_method("can_weave_silk") and spider.can_weave_silk(),"fixture spider can weave in active combat")
	# Real stance: the spider's own state machine drives stand()/move().
	spider.state_machine.set_physics_process(true)

	# A. Stun + real knockback into a wall (ball.stand() path, never when_collide()).
	await prepare()
	spider.apply_stun(2.0)
	check(spider.dizziness,"apply_stun really stuns the spider")
	spider.apply_knockback(Vector2.RIGHT,220.0,900.0,0.0,0.0)
	stunned_at_touch = false
	var got:bool = await wait_anchor(90,func(): stunned_at_touch = spider.dizziness)
	check(got,"stunned + knocked-back spider weaves an anchor on the wall it hits")
	check(stunned_at_touch,"the anchor was woven while the spider was still stunned")
	if got: check(absf(net._point(net.anchor).x-(wall.global_position.x-6.0))<=4.0,"stunned anchor sits on the real wall face")

	# A2. Long-wall contacts keep the collision's own Y position; only up to the
	# tiny wall sink follows the incoming motion, never the abdomen row.
	reset_silk(net)
	spider._last_requested_velocity = Vector2(500.0,-120.0)
	var contact_point:Vector2 = wall.global_position+Vector2(-6.0,43.0)
	var attached:Vector2 = net.wall_attachment_point(contact_point,Vector2.LEFT,wall,contact_point+Vector2(-80.0,160.0))
	check(attached.distance_to(contact_point)<=4.1,"silk end stays at the collision point, not beside the spider")
	check(attached.y<=contact_point.y and contact_point.y-attached.y<=4.0,"the sink follows incoming motion, not the abdomen projection")

	# A3. A real kinematic collision yields the same endpoint at its reported contact.
	reset_silk(net)
	spider.global_position = wall.global_position+Vector2(-70.0,43.0)
	await physics_frame
	reset_silk(net)
	spider._last_requested_velocity = Vector2(500.0,-120.0)
	var real_collision:KinematicCollision2D = spider.move_and_collide(Vector2(70.0,-20.0))
	check(real_collision!=null,"fixture diagonal motion truly hits the old wall")
	if real_collision!=null:
		net._contact_left = 0.0
		spider.when_collide(500.0,real_collision)
		check(not net.anchor.is_empty(),"real diagonal collision weaves the silk endpoint")
		check(net._point(net.anchor).distance_to(real_collision.get_position())<=4.1,"woven endpoint matches the real wall contact up to its sink")

	# B. Damage output disabled + stunned: still weaves; debounce still counts down.
	await prepare()
	spider.apply_damage_disable(8.0)
	check(not spider.mc_live() and spider.can_weave_silk(),"damage-disabled: no mc_live, weaving still allowed")
	spider.apply_stun(2.0)
	spider.apply_knockback(Vector2.RIGHT,220.0,900.0,0.0,0.0)
	check(await wait_anchor(90),"damage-disabled + stunned spider still weaves on wall contact")
	net._contact_left = 0.18
	net.advance(0.2)
	check(net._contact_left==0.0,"wall-contact debounce keeps counting while damage-disabled")

	# C. Damage-disabled: strands/webs form, but silk/web deal no damage until re-enabled.
	spider.state_machine.set_physics_process(false)
	reset_silk(net)
	var base:Vector2 = center+Vector2(-300,300)
	wall_touch(net,base+Vector2(-100,0))
	wall_touch(net,base+Vector2(100,0))
	net.anchor = {}
	wall_touch(net,base+Vector2(0,-100))
	wall_touch(net,base+Vector2(0,100))
	net.anchor = {}
	check(net.segments.size()==2,"damage-disabled spider completes wall-to-wall strands")
	spider.global_position = base+Vector2(-260,-200)
	target.global_position = base
	net._sample_left = 0.0
	var hp:float = target.health
	net.advance(0.05)
	check(net.webs.size()==1,"crossing strands still form a cobweb while damage-disabled")
	check(target.health==hp,"damage-disabled silk/web deal no damage")
	spider._damage_output_disabled_until_msec = 0
	check(spider.mc_live(),"damage disable cleared")
	net._sample_left = 0.0
	net.advance(0.05)
	check(target.health<hp,"after re-enable the same web damages normally")
	target.global_position = center+Vector2(0,420)
	spider._lunge_left = 0.0
	spider._lunge_wait = 0.0

	# D. Stale slide contacts: zero-motion stand() must not re-weave last frame's wall.
	await prepare(40.0)
	spider.dizziness = true
	spider.Repel = Vector2(4800,0) # 80 px this frame: reaches the wall
	spider.stand(1.0/60.0)
	spider.Repel = Vector2.ZERO
	var first:bool = not net.anchor.is_empty()
	check(first,"direct stand() with Repel into the wall weaves")
	reset_silk(net)
	spider.stand(1.0/60.0)
	check(net.anchor.is_empty(),"zero-motion stand() does not reuse stale slide collisions")
	# The lunge (an attack) is still blocked while stunned.
	check(not spider.hunt_web_target(target),"stunned spider still cannot start a web lunge")
	spider.dizziness = false

	# E. Airborne (physical_airborne_effect moves the body with move_and_collide).
	await prepare(120.0)
	var airborne:Script = load("res://scripts/effects/physical_airborne_effect.gd")
	var effect:Node = airborne.launch(spider,null,40.0,420.0,0.4,900.0)
	check(effect!=null,"airborne effect launched on the spider")
	mid_air = false
	got = await wait_anchor(120,func(): if is_instance_valid(effect) and not effect.landed and not net.anchor.is_empty(): mid_air = true)
	check(got,"airborne spider weaves on the obstacle it flies into")
	check(mid_air,"the airborne anchor was woven before landing")
	for i:int in range(90):
		if not is_instance_valid(effect) or effect._finished: break
		await physics_frame

	# F. Map-edge airborne: rect clamp has no collision object; the probe finds the wall.
	reset_silk(net)
	spider.global_position = Vector2(map_rect.position.x+40.0,center.y-260)
	await physics_frame
	reset_silk(net)
	effect = airborne.launch(spider,null,40.0,420.0,0.4,-900.0)
	got = await wait_anchor(120)
	check(got and absf(net._point(net.anchor).x-map_rect.position.x)<=8.0,"airborne into the map-edge wall weaves (rect clamp probe)")
	print("INFO map-edge airborne anchor=",got," anchor=",net._point(net.anchor) if got else Vector2.ZERO," edge_x=",map_rect.position.x)
	for i:int in range(90):
		if not is_instance_valid(effect) or effect._finished: break
		await physics_frame

	# G. Pause, death and replicas still stop weaving (not a "control").
	reset_silk(net)
	game.now_stop_state = true
	check(not net.touch_wall(center+Vector2(-50,-50)),"paused game does not weave")
	game.now_stop_state = false
	check(net.touch_wall(center+Vector2(-50,-50)),"unpaused: same touch weaves")

	print("SPIDER_WEAVE_CONTROL checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
