extends "res://tests/test_iron_golem_landing.gd"
class BoundedArena extends Node2D:
	var regions:Array[Rect2] = []
	func current_map_island_rects() -> Array[Rect2]: return regions
func solid(point:Vector2,size:Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = point
	return wall
func restart(g:Node2D,victim:Node2D,point:Vector2,h:float=121.0) -> Node:
	clear_control(victim)
	clear_fx()
	victim.position = point
	victim.rotation = 0.0
	return fly(g,victim,h,390.0 if h>55.0 else 260.0)
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("GOLEM_PHYSICAL_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	arena = BoundedArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var g:Node2D = golem(Vector2(-500,-400))
	g.companion.global_position = Vector2(-600,-400)
	var victim:Node2D = enemy(Vector2.ZERO)
	await physics_frame
	await process_frame
	var initial_graphics:Vector2 = victim.graphics.position
	var initial_bar:Vector2 = victim.health_bar.position
	var initial_hurt:Vector2 = victim.self_hurtbox.global_position
	var flight:Node = restart(g,victim,Vector2.ZERO,55.0)
	flight.advance(flight.flight_duration*0.5)
	check(absf(victim.global_position.y+55.0)<0.03,"real CharacterBody2D reaches 55 world pixels of height")
	check(absf((victim.self_hurtbox.global_position-initial_hurt).y+55)<0.03,"hurtbox follows the real airborne position")
	check(victim.graphics.position==initial_graphics and victim.health_bar.position==initial_bar,"Graphics and health bar have no independent fake lift")
	check(g.overlaps_target(victim,victim.global_position,1.0),"airborne target can be hit at its displayed position")
	check(not g.overlaps_target(victim,Vector2.ZERO,1.0),"old ground position no longer contains airborne hurtbox")
	var airborne_position:Vector2 = victim.global_position
	game.now_stop_state = true
	flight.advance(2.0)
	check(victim.global_position==airborne_position,"pause freezes actual body, not only animation")
	game.now_stop_state = false
	flight.advance(2.0)
	check(flight.landed and absf(victim.global_position.y)<0.03,"actual body falls back down without leaving the hurtbox behind")
	check(flight.landing_position.is_equal_approx(flight.ground_center()),"splash is at final physical foot position")
	var ceiling:StaticBody2D = solid(Vector2(0,-50),Vector2(200,2))
	await physics_frame
	await process_frame
	flight = restart(g,victim,Vector2.ZERO)
	var highest:float = 0.0
	var outside:bool = false
	var descending:bool = false
	for i:int in range(240):
		flight.advance(1.0/120.0)
		highest = maxf(highest,flight.peak_height)
		outside = outside or flight.body_rect().position.y < -49.01
		descending = descending or (flight.height>0 and flight._vertical_speed>0)
		if flight.landed: break
	check(not outside,"ascending body cannot pass through thin ceiling")
	check(highest>5 and highest<50 and descending,"ceiling reduces real flight height and starts descent")
	check(flight.landed and flight.landing_damage()<30.0,"ceiling-limited landing uses actual height, not nominal 121")
	ceiling.free()
	var blocker:Node2D = enemy(Vector2(0,-70))
	await physics_frame
	await process_frame
	flight = restart(g,victim,Vector2.ZERO)
	flight.advance(2.0)
	check(flight.peak_height<55.0 and flight.landed,"flight preserves collisions with other characters")
	blocker.free()
	flight = restart(g,victim,Vector2.ZERO)
	flight.advance(flight.flight_duration*0.5)
	var platform:StaticBody2D = solid(Vector2(0,-35),Vector2(120,2))
	await physics_frame
	await process_frame
	flight.advance(2.0)
	check(flight.landed and flight.body_rect().end.y<=-35.99,"falling body lands on a physical platform instead of tunnelling through")
	check(victim.global_position.y < -35.0,"platform landing never teleports victim down to launch baseline")
	check(flight.landing_position.is_equal_approx(flight.ground_center()),"platform splash uses actual elevated landing position")
	platform.free()
	arena.regions.assign([Rect2(-100,-45,200,145)])
	flight = restart(g,victim,Vector2.ZERO)
	outside = false
	for i:int in range(180):
		flight.advance(1.0/90.0)
		outside = outside or flight.body_rect().position.y < -45.001
		if flight.landed: break
	check(not outside and flight.landed,"map top blocks flight even without a physical boundary wall")
	check(flight.peak_height<45.0,"map edge stops entire collision shape, not just root center")
	arena.regions.assign([Rect2(-100,-200,200,300)])
	flight = restart(g,victim,Vector2(70,0))
	flight.horizontal_speed = 1000
	flight.advance(2.0)
	check(flight.body_rect().end.x<=100.001 and flight.landed,"high-speed sideways drift cannot leave right map edge")
	flight = restart(g,victim,Vector2(-70,0))
	flight.horizontal_speed = -1000
	flight.advance(2.0)
	check(flight.body_rect().position.x>=-100.001 and flight.landed,"high-speed sideways drift cannot leave left map edge")
	flight = restart(g,victim,Vector2.ZERO)
	flight.advance(flight.flight_duration*0.5)
	arena.regions.assign([Rect2(-100,-200,200,170)])
	flight.advance(2.0)
	check(flight.landed and flight.body_rect().end.y<=-29.999,"current map lower boundary stops a fall before it goes outside")
	arena.regions.assign([Rect2(-100,-200,100,300),Rect2(0,-200,100,300)])
	flight = restart(g,victim,Vector2(-30,0))
	flight.horizontal_speed = 300
	flight.advance(0.2)
	check(victim.global_position.x>15.0,"adjacent floor regions do not create a fake internal wall")
	arena.regions.assign([Rect2(-100,-200,80,300),Rect2(20,-200,80,300)])
	flight = restart(g,victim,Vector2(-60,0))
	flight.horizontal_speed = 3000
	flight.advance(2.0)
	check(flight.body_rect().end.x<=-19.999,"swept body cannot jump over an out-of-map gap to another island")
	arena.regions.assign([Rect2(-100,-200,200,300)])
	flight = restart(g,victim,Vector2.ZERO)
	victim.rotation = 0.35
	flight.horizontal_speed = 1500
	flight.advance(2.0)
	check(flight.body_rect().end.x<=100.001,"boundary containment uses transformed body dimensions")
	arena.regions.clear()
	var thin_wall:StaticBody2D = solid(Vector2(50,-60),Vector2(0.5,300))
	await physics_frame
	await process_frame
	flight = restart(g,victim,Vector2.ZERO)
	flight.horizontal_speed = 2000
	flight.advance(2.0)
	check(flight.body_rect().end.x<=49.751 and flight.landed,"large delta/high-speed flight cannot tunnel through half-pixel wall")
	thin_wall.free()
	flight = restart(g,victim,Vector2.ZERO)
	flight.advance(0.15)
	var before:Vector2 = victim.global_position
	var merged:Node = g.launch_target(victim,121,390,Vector2.UP)
	check(merged==flight and victim.global_position==before,"relaunch keeps actual airborne position without snapping")
	flight.advance(2.0)
	check(flight.landed and flight.peak_height<=121.01,"merged physical flight stays bounded and lands once")
	flight = restart(g,victim,Vector2.ZERO)
	flight.set_multiplayer_authority(2)
	before = victim.global_position
	flight.advance(2.0)
	check(victim.global_position==before and not flight.landed,"remote replica never independently moves physical body")
	clear_control(victim)
	print("GOLEM_PHYSICAL_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
