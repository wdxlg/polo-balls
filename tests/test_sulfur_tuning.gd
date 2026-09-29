extends "res://tests/test_sulfur_cube_balance.gd"
var victim:Node2D
var wall:StaticBody2D
var origin:Vector2
func wall_hit(speed:float,tangent:float = 0.0) -> float:
	victim.global_position = origin+Vector2(40,0)
	victim.force_update_transform()
	victim.velocity = Vector2.ZERO
	for i:int in range(3):
		await physics_frame
		victim.move_and_slide()
		victim._process_wall_hit_bursts_from_slide_collisions(0.0)
	victim.global_position = origin+Vector2(79.95,0)
	source.global_position = victim.global_position+Vector2(0,12)
	victim.force_update_transform()
	source._pull_touching_enemies(1.0/60.0)
	var hp:float = victim.health
	await physics_frame
	victim._last_requested_velocity = Vector2(speed,tangent)
	victim.velocity = Vector2(speed,tangent)
	victim.move_and_slide()
	victim._process_wall_hit_bursts_from_slide_collisions(speed)
	check(victim.get_slide_collision_count()>0,"real wall contact exists")
	return hp-victim.health
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func():quit(2))
	game=root.get_node("Game")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	var saved_stop:bool=game.now_stop_state
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Have_Team_Damage=false
	game.Game_Settings.Ball_Can_Move=true
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	origin=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	source=fighter("TuningCube",origin,true)
	source.set_process(false)
	source.Damage=48
	source.default_properties.Damage=48
	source.set_block(source.Block.HONEY)
	victim=fighter("HoneyVictim",origin+Vector2(5,0))
	victim.scale=Vector2.ONE
	victim.Damage_reduction=0
	victim.block=0
	victim.collision_mask=1
	wall=StaticBody2D.new()
	wall.collision_layer=1
	var shape:=CollisionShape2D.new()
	var rect:=RectangleShape2D.new()
	rect.size=Vector2(10,180)
	shape.shape=rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position=origin+Vector2(100,0)
	await physics_frame
	source._pull_touching_enemies(0.016)
	check(victim.wall_contact_impact.is_connected(source._on_honey_wall_impact.bind(victim)),"honey registers shared physical collision callback")
	var hp:float=victim.health
	for i:int in range(8): source._pull_touching_enemies(0.016)
	check(victim.health==hp,"adhesion without wall collision does not damage")
	var slow:float=await wall_hit(85.0)
	var fast:float=await wall_hit(170.0)
	print("HONEY_DAMAGE slow=",slow," fast=",fast)
	check(slow==0 and fast==0,"pure honey has no independent wall damage at any impact speed")
	hp=victim.health
	for i:int in range(5):
		await physics_frame
		victim._last_requested_velocity=Vector2(170,0)
		victim.velocity=Vector2(170,0)
		victim.move_and_slide()
		victim._process_wall_hit_bursts_from_slide_collisions(170)
	check(victim.health==hp,"continuous wall pressure cannot repeat damage")
	check(await wall_hit(85,170)==0,"sliding tangent velocity does not inflate inward impact damage")
	hp=victim.health
	game.now_stop_state=true
	source._on_honey_wall_impact(170,victim.global_position,victim)
	check(victim.health==hp,"paused honey cannot settle wall damage")
	game.now_stop_state=false
	victim.Team=source.Team
	source._on_honey_wall_impact(170,victim.global_position,victim)
	check(victim.health==hp,"friendly targets remain protected")
	victim.Team="Team1"
	source.acquire_block(source.Block.ICE)
	check(await wall_hit(170)==30,"retained ice supplies speed-based wall damage to an actively grabbed victim")
	source.Damage=96
	check(await wall_hit(170)==60,"honey plus ice reads current attacker damage")
	source.Damage=48
	victim.Damage_reduction=0.5
	check(await wall_hit(170)==15,"victim defenses apply to wall damage")
	victim.Damage_reduction=0
	source.set_multiplayer_authority(2)
	check(await wall_hit(170)==0,"non-authority source cannot damage")
	source.set_multiplayer_authority(1)
	source.set_block(source.Block.ICE)
	check(not victim.wall_contact_impact.is_connected(source._on_honey_wall_impact.bind(victim)),"losing honey disconnects callback")
	check(await wall_hit(170)==0,"unattached wall impacts stay harmless")
	check(is_equal_approx(source.IRON_IMPACT_MULT,1.2075) and source.IRON_REFERENCE_DOWN_SPEED==170,"iron reference impact tripled while continuous crush stays removed")
	check(is_equal_approx(source.AMETHYST_CONTACT_MULT,0.35) and is_equal_approx(source.SHARD.DAMAGE_MULT,0.23625),"attached and projectile crystal coefficients halved again from the current baseline")
	check(source.ICE_STEERING_ACCELERATION==420 and source.ICE_TRAIL.SLIDE_ACCELERATION==240,"continuous ice acceleration halved while steering remains420")
	check(is_equal_approx(source.ICE_TRAIL.MAX_BONUS_RATIO,1.5),"ice speed cap preserved")
	# Real ice integration before reaching cap.
	SURFACE=load("res://scripts/effects/surface_acceleration.gd")
	var runner:Node2D=fighter("IceRunner",origin-Vector2(90,0))
	var tile:Node2D=floor_tile(Rect2(origin-Vector2(150,150),Vector2(250,250)))
	var effect:Node=SURFACE.touch(runner,tile)
	effect.set_physics_process(false)
	for i:int in range(6):
		runner.global_position.x+=1
		effect._physics_process(1.0/60.0)
	check(is_equal_approx(effect.momentum.length(),24.0),"ice integrates240 acceleration into24 velocity over0.1 seconds")
	tile.free()
	runner.free()
	wall.free()
	await check_amethyst_damage()
	source.global_position=origin
	victim.global_position=origin+Vector2(25,0)
	var outside:Node2D=fighter("OutsideNewBlast",origin+Vector2(90,0))
	source.set_block(source.Block.TNT)
	source.fuse_left=1
	source._update_charge_circle()
	check(source.TNT_RADIUS==40 and source._charge_circle.radius==40,"TNT prewarning radius halved to 40")
	var threats:Array=source.get_ai_attack_threats(victim)
	check(threats.size()==1 and threats[0].radius==40 and threats[0].damage==200,"TNT threat matches 200 damage and radius 40")
	hp=victim.health
	var outside_hp:float=outside.health
	source._detonate()
	check(hp-victim.health==200,"unbuffed TNT applies 200 through shared defenses")
	check(outside.health==outside_hp,"old outer blast band no longer damages")
	check(not source.has_block(source.Block.TNT),"TNT consumption and dual-trait refill retained")
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings=saved
	game.now_stop_state=saved_stop
	print("SULFUR_TUNING checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)


func check_amethyst_damage() -> void:
	# Use production tip contact and actual PhysicsRayQueryParameters2D projectiles,
	# not a copy of their damage algorithm. One known crystal makes hits unambiguous.
	source.set_block(source.Block.AMETHYST)
	source.crystals_out = false
	source.global_position = origin
	source.crystal_layout = PackedVector3Array([Vector3(-0.4,0,0.4),Vector3(-1.70,0,1.1)])
	source._native_model.animate(0.0,0.3,true,0.0)
	victim.fire_effect_ratio = 0.0
	victim.cold_effect_ratio = 0.0
	check(source.CRYSTAL_COUNT_MIN==3 and source.CRYSTAL_COUNT_MAX==8 and source.CRYSTAL_VOLLEY_TIME==2.4 and source.CRYSTAL_REGROW_TIME==0.8,"crystal amount and firing/regrowth cadence are unchanged")
	check(source.SHARD.SPEED==270.0 and source.SHARD.RADIUS==3.0 and source.SHARD.LIFETIME==1.25,"projectile speed, hit radius and lifetime are unchanged")
	for values:Vector4 in [Vector4(48,0,17,12),Vector4(96,0,34,23),Vector4(48,0.5,9,6)]:
		source.Damage = values.x
		victim.Damage_reduction = values.y
		source._crystal_hits.clear()
		victim.global_position = source._crystal_tip_points()[0]
		var threats:Array = source.get_ai_attack_threats(victim)
		check(threats.size()==1 and is_equal_approx(threats[0].damage,source.attack_damage(0.7)*0.5),"attached-tip threat uses half the previous current-attribute damage")
		var hp:float = victim.health
		source._pulse_contact()
		var tip_loss:float = hp-victim.health
		check(tip_loss==values.z,"real crystal contact applies reduced ordinary damage through current attack/defense")
		hp = victim.health
		source._pulse_contact()
		check(victim.health==hp,"a crystal still hits each target only once per growth")
		var shot:Node2D = await make_damage_probe_shard()
		var info:Dictionary = shot.get_ai_hazard_info(victim)
		check(is_equal_approx(info.damage,source.attack_damage(0.4725)*0.5),"flying-crystal threat uses the same reduced damage as the real projectile")
		hp = victim.health
		shot._physics_process(0.5)
		check(hp-victim.health==values.w and shot.is_queued_for_deletion(),"real raycast projectile applies reduced ordinary damage and is consumed on impact")
		print("AMETHYST_DAMAGE attack=",values.x," defense=",values.y," tip=",tip_loss," shard=",hp-victim.health)
		if not shot.is_queued_for_deletion(): shot.queue_free()
		await process_frame
	# Permission/pause/friendship gates are not bypassed by the balance change.
	source.Damage = 48
	victim.Damage_reduction = 0.0
	for gate:String in ["pause","replica","friendly"]:
		if gate=="pause": game.now_stop_state = true
		if gate=="replica": source.set_multiplayer_authority(2)
		if gate=="friendly": victim.Team = source.Team
		source._crystal_hits.clear()
		victim.global_position = source._crystal_tip_points()[0]
		var hp:float = victim.health
		source._pulse_contact()
		check(victim.health==hp,gate+" still blocks attached crystal damage")
		var shot:Node2D = await make_damage_probe_shard()
		shot._physics_process(0.5)
		check(victim.health==hp,gate+" still blocks flying crystal damage")
		shot.queue_free()
		game.now_stop_state = false
		source.set_multiplayer_authority(1)
		victim.Team = "Team1"
		await process_frame
	victim.fire_effect_ratio = 1.0
	victim.cold_effect_ratio = 1.0

func make_damage_probe_shard() -> Node2D:
	# The saved map can be only 160x160. Keep the target and launch inside it;
	# otherwise the production ray correctly hits its boundary before the victim.
	victim.global_position = origin+Vector2(55,0)
	victim.force_update_transform()
	await physics_frame
	var shot:Node2D = source.SHARD.new()
	world.add_child(shot)
	shot.setup(source,origin+Vector2(20,0),Vector2.RIGHT)
	shot.set_physics_process(false)
	return shot
