extends "res://tests/test_iron_golem_hit_audio.gd"
class FloorFixture extends Node:
	func capture(_rect:Rect2) -> Dictionary:
		var im:Image = Image.create(4,4,false,Image.FORMAT_RGBA8)
		im.fill(Color(0.45,0.30,0.18,1.0))
		return {"image":im,"rect":Rect2(-500,-500,1000,1000)}
func fly(g:Node2D,victim:Node2D,h:float=55.0,s:float=260.0) -> Node:
	clear_control(victim)
	return g.launch_target(victim,h,s,Vector2.UP)
func clear_fx() -> void:
	for node:Node in get_nodes_in_group("GolemLandingImpact"): node.free()
func run() -> void:
	create_timer(75.0).timeout.connect(func(): push_error("GOLEM_LANDING_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var floor_fixture := FloorFixture.new()
	floor_fixture.name = "GroundSurfaceSampler"
	arena.add_child(floor_fixture)
	var g:Node2D = golem(Vector2(-200,0))
	g.companion.global_position = Vector2(-300,0)
	var victim:Node2D = enemy(Vector2.ZERO)
	var nearby:Node2D = enemy(Vector2(40,0))
	var ally:Node2D = enemy(Vector2(-40,0),"Team0")
	var distant:Node2D = enemy(Vector2(200,0))
	await physics_frame
	await process_frame
	var base_graphics:Vector2 = victim.graphics.position
	var base_bar:Vector2 = victim.health_bar.position
	var base_root:Vector2 = victim.global_position
	var flight:Node = fly(g,victim)
	check(flight!=null and victim.dizziness,"uppercut creates flight and shared control lock")
	check(is_equal_approx(flight.distance,55.0) and is_equal_approx(flight.speed,260.0),"baseline launch height and initial rise speed preserved")
	flight.land()
	check(not flight.landed and get_nodes_in_group("GolemLandingImpact").is_empty(),"cannot force an explosion before touching ground")
	flight.advance(flight.flight_duration*0.25)
	var rise_height:float = flight.height
	check(rise_height>0 and rise_height<55,"first quarter rises toward apex")
	check(victim.global_position.y<base_root.y and is_equal_approx(base_root.y-victim.global_position.y,flight.height),"actual body position follows measured flight height")
	check(victim.graphics.position.is_equal_approx(base_graphics),"no fake Graphics-only height offset")
	check(victim.health_bar.position.is_equal_approx(base_bar),"health bar follows real body without extra offset")
	check(nearby.health==10000 and get_nodes_in_group("GolemLandingImpact").is_empty(),"ascending enemy does not emit premature AOE")
	flight.advance(flight.flight_duration*0.25)
	check(is_equal_approx(flight.height,55.0) and is_equal_approx(flight.peak_height,55.0),"apex reaches actual configured height")
	var t:float = flight.flight_elapsed
	game.now_stop_state = true
	flight.advance(5.0)
	check(is_equal_approx(flight.flight_elapsed,t) and is_equal_approx(flight.height,55.0),"combat pause freezes midair height and timer")
	game.now_stop_state = false
	flight.advance(flight.flight_duration*0.25)
	check(flight.height<55.0 and is_equal_approx(flight.height,rise_height),"after apex enemy descends along ballistic arc")
	var landing_point:Vector2 = Vector2.ZERO
	var previous_victim:int = victim.health
	clear_hit_players(g)
	flight.advance(flight.flight_duration*0.25+0.001)
	landing_point = flight.ground_center()
	check(flight.landed and is_zero_approx(flight.height) and absf(victim.global_position.y-base_root.y)<0.02,"real body falls to ground and completes once")
	check(victim.graphics.position.is_equal_approx(base_graphics) and victim.health_bar.position.is_equal_approx(base_bar),"landing restores body and health bar to original baseline")
	check(flight.landing_position.is_equal_approx(landing_point),"impact uses actual foot shadow center")
	check(nearby.health<10000 and distant.health==10000,"landing damages nearby enemy but not distant one")
	check(ally.health==10000 and g.health==800 and g.companion.health==180,"landing obeys owner/team/companion exclusions")
	check(previous_victim-victim.health==10000-nearby.health,"launched enemy takes one fall hit, not an extra self-splash")
	var small_damage:int = 10000-nearby.health
	check(small_damage>=13 and small_damage<=15,"height 55 gives modest roughly 14 splash damage")
	check(nearby.Repel.length()>0.0 and nearby.Repel.length()<=120.01,"splash applies small outward knockback")
	check(hit_players(g).size()==2 and hit_players(g)[0].get_meta("mc_sound_event")=="entity.player.hurt" and hit_players(g)[1].get_meta("mc_sound_event")=="entity.player.hurt","both splash and victim fall reuse actual-health-damage sound")
	check(get_nodes_in_group("GolemLandingImpact").size()==1,"exactly one landing impact visual")
	var fx:Node2D = get_nodes_in_group("GolemLandingImpact")[0]
	check(fx.get_script().get_base_script().resource_path.ends_with("重锤落地冲击.gd"),"impact inherits real mace wave/debris implementation")
	check(fx._streaks.size()>0 and fx._blocks.size()>0,"mace wave streaks and sampled floor debris are built")
	check(fx.global_position.is_equal_approx(landing_point) and is_equal_approx(fx._radius,flight.landing_radius()),"wave center and radius match actual damage AOE")
	var fx_clock:float = fx._elapsed
	game.now_stop_state = true
	fx._process(1.0)
	check(is_equal_approx(fx._elapsed,fx_clock),"pause freezes wave and debris lifetime")
	game.now_stop_state = false
	var health_after:int = nearby.health
	flight.land()
	flight.damage_landing(landing_point)
	flight._land_visual(landing_point,flight.landing_radius())
	check(nearby.health==health_after and get_nodes_in_group("GolemLandingImpact").size()==1,"repeated land/damage/RPC callbacks cannot double hit or duplicate visual")
	flight.advance(0.66)
	check(flight._finished and not victim.dizziness,"post-landing stun ends and releases only its own lock")
	clear_control(nearby)
	clear_fx()
	flight = fly(g,victim,121.0,390.0)
	nearby.health = 10000
	flight.advance(flight.flight_duration+0.01)
	check(is_equal_approx(flight.peak_height,121.0),"large timestep still records exact crossed apex")
	check(10000-nearby.health>small_damage and flight.landing_push()>6.3,"higher flight increases landing damage and gentle push")
	check(flight.landing_radius()>30.6,"higher flight slightly enlarges splash radius")
	clear_control(nearby)
	clear_fx()
	flight = fly(g,victim)
	flight.advance(0.2)
	var held_height:float = flight.height
	var merged:Node = g.launch_target(victim,121.0,390.0,Vector2.UP)
	check(merged==flight and is_equal_approx(merged.height,held_height),"second uppercut merges without snapping target to ground")
	check(get_nodes_in_group("GolemAirborne").size()==1,"repeated launches keep one airborne controller")
	flight.advance(flight.flight_duration+0.01)
	check(get_nodes_in_group("GolemLandingImpact").size()==1 and flight.peak_height<=121.001,"merged flight lands once without unlimited height stacking")
	clear_control(nearby)
	clear_fx()
	flight = fly(g,victim)
	flight.advance(0.2)
	victim.global_position.x = 120
	nearby.global_position = Vector2(160,0)
	nearby.health = 10000
	landing_point = flight.ground_center()+Vector2.DOWN*flight.height
	flight.advance(flight.flight_duration)
	check(flight.landing_position.is_equal_approx(landing_point) and nearby.health<10000,"ground movement during flight changes the actual landing point")
	clear_control(nearby)
	clear_fx()
	victim.global_position = Vector2.ZERO
	nearby.global_position = Vector2(40,0)
	flight = fly(g,victim)
	var barrier:StaticBody2D = wall_at(Vector2(20,0),2)
	await physics_frame
	await process_frame
	nearby.health = 10000
	flight.advance(flight.flight_duration+0.01)
	check(nearby.health==10000,"landing shock cannot damage through a wall")
	barrier.free()
	clear_fx()
	flight = fly(g,victim)
	flight.set_multiplayer_authority(2)
	nearby.health = 10000
	flight.advance(flight.flight_duration+0.01)
	flight.land()
	check(nearby.health==10000 and get_nodes_in_group("GolemLandingImpact").is_empty(),"remote replica does not move a second physics body or settle AOE")
	flight._land_visual(flight.ground_center(),flight.landing_radius())
	flight._land_visual(flight.ground_center(),flight.landing_radius())
	check(get_nodes_in_group("GolemLandingImpact").size()==1 and nearby.health==10000,"authoritative landing visual callback is idempotent and visual-only")
	clear_fx()
	flight = fly(g,victim)
	victim.health = 0
	flight.advance(0.1)
	check(flight._finished and victim.graphics.position.is_equal_approx(base_graphics) and get_nodes_in_group("GolemLandingImpact").is_empty(),"victim death cancels flight, restores pose and creates no phantom landing")
	victim.health = 10000
	flight = fly(g,victim)
	var other_lock:Node = victim.apply_knockback(Vector2.ZERO,0.0,0.0,0.0,2.0,{"source":g,"replace_existing":false})
	flight.advance(flight.flight_duration+0.01)
	flight.advance(0.66)
	check(victim.dizziness and not other_lock._finished,"finishing flight preserves another controller's stun lock")
	clear_control(victim)
	check(not victim.dizziness,"all released control locks restore pre-hit state")
	clear_control(nearby)
	clear_fx()
	flight = fly(g,victim)
	g.notify_golem_death()
	g.free()
	nearby.health = 10000
	flight.advance(flight.flight_duration+0.01)
	check(flight.landed and nearby.health<10000,"already launched enemy still lands and splashes after golem is freed")
	check(ally.health==10000,"owner team snapshot still prevents friendly fire after owner removal")
	clear_control(victim)
	clear_control(nearby)
	clear_fx()
	# Real physics scene: rise, descend, land, then recover; no manual flight ticking.
	g = golem(Vector2(-200,-100))
	g.Can_Attack = false
	g.Speed = 0
	g.companion.global_position = Vector2(-300,-100)
	victim.global_position = Vector2(0,-100)
	victim.Speed = 0
	victim.Can_Attack = false
	victim.Can_Skill = false
	nearby.global_position = Vector2(40,-100)
	nearby.Speed = 0
	nearby.Can_Attack = false
	nearby.Can_Skill = false
	nearby.health = 10000
	flight = fly(g,victim,121.0,390.0)
	for unit:Node in get_nodes_in_group("Ball"):
		if unit.has_method("apply_knockback"):
			unit.Can_Attack = false
			unit.Can_Skill = false
			unit.Speed = 0.0
	Engine.time_scale = 4
	arena.process_mode = Node.PROCESS_MODE_INHERIT
	var highest:float = 0.0
	var saw_descent:bool = false
	var saw_ground:bool = false
	for frame:int in range(55):
		await physics_frame
		var current_height:float = float(victim.get_meta("golem_air_height",0.0))
		if highest>50 and current_height<highest-10: saw_descent = true
		highest = maxf(highest,current_height)
		if saw_descent and current_height<0.01: saw_ground = true
	check(highest>110 and saw_descent and saw_ground,"real physics displays a full high launch, descent and landing")
	check(nearby.health<10000,"real physics landing damages a nearby enemy")
	check(not victim.dizziness and not victim.has_meta("golem_air_height"),"real physics cleans up airborne state and restores normal movement")
	Engine.time_scale = 1
	print("GOLEM_LANDING_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
