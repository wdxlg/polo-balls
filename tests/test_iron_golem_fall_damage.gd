extends "res://tests/test_iron_golem_physical_flight.gd"

func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("GOLEM_FALL_DAMAGE_TIMEOUT"); quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Have_Team_Damage=false
	game.Game_Settings.Ball_Can_Move=true
	AudioServer.set_bus_mute(0,true)
	arena=BoundedArena.new()
	root.add_child(arena)
	current_scene=arena
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	var g:Node2D=golem(Vector2(-30,0))
	g.companion.global_position=Vector2(-500,0)
	g.set_character_visual_flip_h(true)
	var victim:Node2D=enemy(Vector2.ZERO)
	var nearby:Node2D=enemy(Vector2(40,0))
	await physics_frame
	await process_frame
	check(g.resolve_upswing()==1 and victim.health==9952,"original uppercut still deals its 48 damage at impact, not fall damage early")
	var flight:Node=victim.get_node("KnockbackEffect_GolemAirborne")
	var hp:int=victim.health
	flight.advance(flight.flight_duration*0.5)
	check(not flight.landed and victim.health==hp,"ascending to apex causes no premature fall damage")
	flight.land()
	flight.damage_landing(flight.ground_center())
	check(victim.health==hp and not flight.landed,"manual landing and damage callbacks cannot settle in midair")
	game.now_stop_state=true
	flight.advance(4.0)
	check(victim.health==hp and not flight.landed,"pause cannot advance to a damaging landing")
	game.now_stop_state=false
	flight.advance(flight.flight_duration+0.01)
	var small:int=hp-victim.health
	check(flight.landed and small==ceili(flight.landing_damage()) and small==14,"height 55 adds exactly one 14-point victim fall hit at real contact")
	check(10000-nearby.health==small and flight.landing_hits==2,"victim and one nearby enemy each receive a single landing hit")
	check(g.health==800 and g.companion.health==180,"fall damage is on the launched enemy, never on the golem or helper")
	check(victim.Repel==Vector2.ZERO,"the direct victim fall hit does not knock itself sideways or relaunch")
	hp=victim.health
	var nearby_hp:int=nearby.health
	flight.land()
	flight.damage_landing(flight.landing_position)
	flight._land_visual(flight.landing_position,flight.landing_radius())
	flight.advance(0.2)
	check(victim.health==hp and nearby.health==nearby_hp,"repeated callbacks and post-landing stun cannot double-charge fall or splash")
	clear_control(nearby)
	nearby.global_position=Vector2(500,300)
	g.global_position=Vector2(-300,0)
	flight=restart(g,victim,Vector2.ZERO,121.0)
	hp=victim.health
	flight.advance(2.0)
	check(hp-victim.health==31 and flight.landing_hits==1,"full-height fall deals 31 once even with no surrounding victims")
	g.enraged=true
	flight=restart(g,victim,Vector2.ZERO,121.0)
	hp=victim.health
	flight.advance(2.0)
	check(hp-victim.health==46,"victim fall uses the same snapshotted rage scaling as landing splash")
	g.enraged=false
	flight=restart(g,victim,Vector2.ZERO,55.0)
	hp=victim.health
	flight.advance(0.2)
	var merged:Node=g.launch_target(victim,121.0,390.0,Vector2.UP)
	check(merged==flight and victim.health==hp,"midair relaunch merges without charging an extra fall immediately")
	flight.advance(2.0)
	check(hp-victim.health==31,"merged flight produces one final fall hit, not one per launch")
	hp=victim.health
	merged=g.launch_target(victim,55.0,260.0,Vector2.UP)
	check(merged==flight and not flight.landed,"a new launch after landing may reuse the controller")
	flight.advance(2.0)
	check(hp-victim.health==14,"a genuinely separate second landing gets one new fall hit")
	var ceiling:StaticBody2D=solid(Vector2(0,-50),Vector2(200,2))
	await physics_frame
	await process_frame
	flight=restart(g,victim,Vector2.ZERO,121.0)
	hp=victim.health
	flight.advance(2.0)
	check(flight.landed and flight.peak_height<50 and hp-victim.health==ceili(flight.landing_damage()) and hp-victim.health<31,"ceiling collision reduces victim fall damage to actual achieved height")
	ceiling.free()
	flight=restart(g,victim,Vector2.ZERO,121.0)
	hp=victim.health
	flight.advance(flight.flight_duration*0.5)
	var platform:StaticBody2D=solid(Vector2(0,-35),Vector2(120,2))
	await physics_frame
	await process_frame
	check(victim.health==hp,"new platform below an airborne victim cannot charge damage early")
	flight.advance(2.0)
	check(flight.landed and victim.global_position.y< -35 and hp-victim.health==ceili(flight.landing_damage()),"actual elevated platform contact also damages the victim without a self-LOS failure")
	platform.free()
	victim.Damage_reduction=0.5
	flight=restart(g,victim,Vector2.ZERO,55.0)
	hp=victim.health
	flight.advance(2.0)
	check(hp-victim.health==7,"fall damage follows normal damage reduction")
	victim.Damage_reduction=1.0
	clear_hit_players(g)
	flight=restart(g,victim,Vector2.ZERO,55.0)
	hp=victim.health
	flight.advance(2.0)
	check(victim.health==hp and hit_players(g).is_empty(),"fully reduced fall produces no false health loss or damage sound")
	victim.Damage_reduction=0.0
	victim.max_block=100
	victim.default_properties.max_block=100
	victim.block=100
	flight=restart(g,victim,Vector2.ZERO,55.0)
	hp=victim.health
	flight.advance(2.0)
	check(victim.health==hp and victim.block<100,"fall damage uses the existing shield rules rather than bypassing defenses")
	victim.block=0
	flight=restart(g,victim,Vector2.ZERO,55.0)
	flight.set_multiplayer_authority(2)
	hp=victim.health
	flight.advance(2.0)
	flight._land_visual(flight.ground_center(),flight.landing_radius())
	flight.damage_landing(flight.ground_center())
	check(victim.health==hp,"replica movement/landing visuals never settle victim damage")
	flight=restart(g,victim,Vector2.ZERO,55.0)
	victim.health=0
	flight.advance(0.1)
	check(flight._finished and not flight.landed and not victim.has_meta("golem_air_height"),"death in flight cancels rather than creating a ghost fall hit")
	victim.health=10000
	flight=restart(g,victim,Vector2.ZERO,55.0)
	hp=victim.health
	g.notify_golem_death()
	g.free()
	flight.advance(2.0)
	check(flight.landed and hp-victim.health==14,"an already launched victim still takes fall damage after the golem is removed")
	g=golem(Vector2(-300,-200))
	g.companion.global_position=Vector2(-500,-200)
	nearby.global_position=Vector2(40,0)
	nearby.health=10000
	victim.health=5
	flight=restart(g,victim,Vector2.ZERO,55.0)
	flight.advance(2.0)
	check(victim.health==0 and flight.landed and flight._finished,"lethal fall settles once and finishes its controller immediately")
	check(nearby.health==9986,"lethal victim fall does not suppress the simultaneous surrounding shock")
	check(not victim.has_meta("golem_air_height") and not flight._stun_visual_acquired and not flight._lock_acquired,"lethal landing leaves no airborne metadata or corpse stun/control lock")
	hp=nearby.health
	flight.land()
	flight.damage_landing(flight.landing_position)
	check(victim.health==0 and nearby.health==hp,"lethal landing cannot be replayed through repeated callbacks")
	print("GOLEM_FALL_DAMAGE_RESULT checks=",checks," failures=",failures)
	current_scene=null
	arena.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
