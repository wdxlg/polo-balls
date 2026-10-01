extends "res://tests/test_high_damage_feedback.gd"
## Real settlement paths; coordinates are snapshots, not owner references.
var source_contract_completed:bool = false

func run() -> void:
	await super.run()
	if not source_contract_completed:
		push_error("Source-focus contract aborted before completion")
		quit(1)

func expect_focus(point:Vector2,label:String) -> void:
	check(world._damage_focus_pending_strength >= 0.0 and world._damage_focus_pending_position.is_equal_approx(point),label)

func contract_cases() -> void:
	super.contract_cases()
	reset_feedback()
	var mace:Node2D = spawn_actor("res://scenes/characters/我的世界/重锤.tscn","Team0",Vector2(-20,-28))
	var second:Node2D = spawn_actor("res://scenes/ball.tscn","Team1",Vector2(12,-25))
	var result:Dictionary = mace._damage_area(mace.global_position,100.0,150.0,0.0,0.0)
	check(result.hits >= 2 and target.health == 850 and second.health == 850,"real mace landing damage is unchanged")
	expect_focus(mace.global_position,"mace landing focuses the mace, not its victim")
	second.free()
	mace.free()

	for raw:bool in [false,true]:
		reset_feedback()
		var bullet:Node2D = spawn_actor("res://scenes/shooter/子弹.tscn","Team0",Vector2(4,24))
		bullet.Master = attacker
		bullet.Master_name = attacker.name
		bullet.Damage = 150
		bullet.set_meta("berserker_raw_health_damage",raw)
		var point:Vector2 = bullet.self_hitbox.global_position
		check(bullet.self_hitbox.try_hit_hurtbox(target.self_hurtbox),"real bullet contact accepted (raw=%s)"%raw)
		check(target.health == 850,"bullet settlement unchanged (raw=%s)"%raw)
		expect_focus(point,"bullet focuses its own hitbox rather than Master (raw=%s)"%raw)
		bullet.free()
		world._update_damage_focus()
		check(world._damage_focus_anchor.is_equal_approx(point),"deleted bullet retains its impact-time focus snapshot")
		check(target._damage_focus_origin == Vector2.INF,"hitbox context is restored after bullet deletion")

	reset_feedback()
	var undead_target:Node2D = target
	target = spawn_actor("res://scenes/ball.tscn","Team1",Vector2(25,12))
	var status_catalog:Script = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	check(status_catalog.apply_effect(target,"poison",150,10.0,attacker),"real poison status installed")
	var poison:Node = target.get_node("MinecraftStatus_poison")
	poison.set_physics_process(false)
	target.record_combat_damage_source(attacker,float(target.health))
	poison._tick_periodic_health_effect()
	check(target.health == 850,"real high-level poison tick retains original health loss")
	expect_focus(target.global_position,"poison focuses its victim, never the original caster or old kill source")
	poison.free()
	reset_feedback()
	check(status_catalog.apply_effect(target,"wither",15,10.0,attacker),"real wither status installed")
	var wither:Node = status_catalog.current(target,"wither")
	check(is_instance_valid(wither),"wither resolves through the shared status catalog")
	if not is_instance_valid(wither): return
	wither.set_physics_process(false)
	wither.tick_left = 0.0
	wither._physics_process(0.001)
	check(target.health==850,"real wither tick retains its max-health damage")
	expect_focus(target.global_position,"wither focuses the afflicted character rather than its caster")
	wither.free()
	target.free()
	target = undead_target
	reset_feedback()
	target.receive_internal_status_damage(150.0,&"bleed",attacker)
	expect_focus(target.global_position,"internal bleeding focuses the afflicted character")
	reset_feedback()
	target.receive_fire_positional_damage(150.0,target.global_position,false,attacker,{"carrier":"status_tick"})
	expect_focus(target.global_position,"burn status focuses the burning character")
	reset_feedback()
	target.receive_fire_positional_damage(150.0,attacker.global_position,false,attacker)
	expect_focus(attacker.global_position,"direct fire is not mistaken for a status tick")
	for path:String in ["res://scripts/status/战争女神_灼烧.gd","res://scripts/status/锻刀师_燃烧.gd"]:
		reset_feedback()
		var burn:Node = load(path).new()
		target.add_child(burn)
		burn.setup(target,attacker,10.0,0.5,150.0)
		burn.set_physics_process(false)
		burn._tick_left = 0.0
		burn._physics_process(0.001)
		check(target.health==850,"real burn status retains its damage: "+path.get_file())
		expect_focus(target.global_position,"real burn status focuses its victim: "+path.get_file())
		burn.free()

	reset_feedback()
	var point:Vector2 = center + Vector2(0,-30)
	target.receive_spatial_raw_health_damage(150.0,{"point":target.global_position,"source":attacker,"focus_position":point})
	expect_focus(point,"raw spatial damage separates visual origin from damage attribution")
	reset_feedback()
	target.receive_spatial_damage(150.0,{"point":target.global_position,"source":attacker,"focus_position":point})
	expect_focus(point,"non-raw spatial origin survives the virtual positional handoff")
	check(target._damage_focus_origin == Vector2.INF and target._pending_positional_focus_origin == Vector2.INF,"spatial handoff leaves no focus context behind")
	reset_feedback()
	target.health -= 150
	expect_focus(target.global_position,"source-free damage cannot reuse the previous projectile or skill")

	reset_feedback()
	target.receive_positional_damage(100.0,attacker.global_position,true,attacker)
	target.receive_positional_damage(180.0,point,true,null)
	target.receive_positional_damage(120.0,target.global_position,true,null)
	expect_focus(point,"same-frame strongest source wins, without averaging")
	reset_feedback()
	target.max_block = 1000
	target.block = 1000
	target.receive_positional_damage(150.0,attacker.global_position,false,attacker)
	check(world._damage_focus_pending_strength < 0.0 and target._damage_focus_origin == Vector2.INF,"shield-only damage neither focuses nor leaks its source")
	target.health -= 150
	expect_focus(target.global_position,"direct damage after a blocked hit remains self-focused")
	reset_feedback()
	target.Damage_reduction = 1.0
	target.receive_positional_damage(150.0,attacker.global_position,true,attacker)
	check(world._damage_focus_pending_strength < 0.0 and target._damage_focus_origin == Vector2.INF,"immune hit leaves no stale source")
	reset_feedback()
	target._remote_damage_camera_feedback(150.0,false,150.0,point)
	expect_focus(point,"remote feedback consumes the transmitted Vector2 snapshot")
	reset_feedback()
	target._remote_damage_camera_feedback(150.0,false,150.0,Vector2(NAN,INF))
	expect_focus(target.global_position,"invalid remote coordinates fall back safely")
	reset_feedback()
	target._remote_damage_camera_feedback(150.0,true,150.0,point)
	check(world._damage_focus_pending_strength < 0.0,"blocked remote feedback does not focus")
	reset_feedback()
	game.set_runtime_game_setting(KEY,false,false)
	target.receive_positional_damage(150.0,point,true,null)
	check(world._damage_focus_pending_strength < 0.0,"source-oriented focus still obeys the local switch")
	game.set_runtime_game_setting(KEY,true,false)
	reset_feedback()
	target.receive_positional_damage(10.0,point,true,null)
	check(world._damage_focus_pending_strength<0.0,"changing the origin does not lower the high-damage threshold")
	reset_feedback()
	world._cinematic_focus_weight = 0.5
	target.receive_positional_damage(150.0,point,true,null)
	check(world._damage_focus_pending_strength<0.0,"cinematic focus retains priority over source-directed damage focus")
	world._cinematic_focus_weight = 0.0
	reset_feedback()
	world._damage_focus_next_usec = Time.get_ticks_usec()+1000000
	target.receive_positional_damage(150.0,point,true,null)
	check(world._damage_focus_pending_strength<0.0,"source-directed focus cannot bypass cooldown")
	reset_feedback()

	var original_source:Vector2 = attacker.global_position
	var inner:Vector2 = center + Vector2(0,25)
	var observed:Array[Vector2] = []
	target.health_bar.health_changed.connect(func(_old,_new,_maximum,_animate):
		target.receive_spatial_raw_health_damage(90.0,{"point":target.global_position,"focus_position":inner})
		observed.append(world._damage_focus_pending_position)
		observed.append(target.damage_focus_position())
		attacker.global_position += Vector2(8,0)
	,CONNECT_ONE_SHOT)
	target.receive_positional_damage(150.0,original_source,true,attacker)
	check(observed.size()==2 and observed[0].is_equal_approx(inner) and observed[1].is_equal_approx(original_source),"nested damage uses its own source then restores the outer settlement")
	expect_focus(original_source,"outer health setter freezes its source before reentrant callbacks move it")
	check(target._damage_focus_origin == Vector2.INF,"reentrant health callbacks cannot leak focus context")
	attacker.global_position = original_source
	reset_feedback()

	var boat:Node2D = spawn_actor("res://scenes/characters/我的世界/木船.tscn","Team1",Vector2(20,0))
	var rider:Node2D = spawn_actor("res://scenes/ball.tscn","Team1",Vector2(22,0))
	boat._attach_passenger(rider,0)
	check(rider.is_transport_mounted(),"focus regression uses a real boat passenger")
	var boat_health:float = boat.health
	var rider_health:float = rider.health
	check(status_catalog.apply_effect(rider,"poison",200,10.0,attacker),"boat passenger receives a real high-level poison")
	var passenger_poison:Node = rider.get_node("MinecraftStatus_poison")
	passenger_poison.set_physics_process(false)
	passenger_poison._tick_periodic_health_effect()
	check(boat_health-boat.health==100.0 and rider_health-rider.health==100.0,"poison boat sharing keeps the original total damage")
	check(world._damage_focus_pending_strength>=0.0 and (world._damage_focus_pending_position.is_equal_approx(boat.global_position) or world._damage_focus_pending_position.is_equal_approx(rider.global_position)),"boat sharing preserves status focus instead of returning to the caster")
	passenger_poison.free()
	boat.release_all()
	rider.free()
	boat.free()
	reset_feedback()
	source_contract_completed = true

func _probe_center(image:Image) -> Vector2:
	var sum:Vector2 = Vector2.ZERO
	var count:int = 0
	var color:Color = Color.MAGENTA
	for y:int in image.get_height():
		for x:int in image.get_width():
			var pixel:Color = image.get_pixel(x,y)
			if absf(pixel.r-color.r)<0.003 and absf(pixel.g-color.g)<0.003 and absf(pixel.b-color.b)<0.003:
				sum += Vector2(x,y)
				count += 1
	return sum/float(count) if count>0 else Vector2.INF

func capture_case(folder:String,label:String,_damage:float,_enabled:bool) -> void:
	# The inherited GPU runner supplies an isolated evidence directory and fixed FPS.
	if label != "special_on": return
	var probe:Polygon2D = Polygon2D.new()
	probe.polygon = PackedVector2Array([Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)])
	probe.color = Color.MAGENTA
	probe.z_index = 4090
	probe.z_as_relative = false
	probe.position = center
	world.add_child(probe)
	var source_cases:PackedStringArray = ["mace","bullet","poison"]
	for kind:String in source_cases:
		reset_feedback()
		game.set_runtime_game_setting(KEY,true,false)
		game.Game_Settings.Shaking_Camera = false
		world.camera_2d.global_position = center
		world.camera_2d.offset = Vector2.ZERO
		world.process_always(0.0)
		world.camera_2d.force_update_scroll()
		for frame:int in 4: await RenderingServer.frame_post_draw
		var before:Vector2 = _probe_center(root.get_texture().get_image())
		var expected:Vector2
		var source:Node2D
		var poison:Node
		var alive_target:Node2D
		if kind == "mace":
			source = spawn_actor("res://scenes/characters/我的世界/重锤.tscn","Team0",Vector2(-28,0))
			expected = source.global_position
			source._damage_area(expected,100.0,150.0,0.0,0.0)
		elif kind == "bullet":
			source = spawn_actor("res://scenes/shooter/子弹.tscn","Team0",Vector2(-18,0))
			source.Master = attacker
			source.Damage = 150
			expected = source.self_hitbox.global_position
			source.self_hitbox.try_hit_hurtbox(target.self_hurtbox)
			source.free()
		else:
			alive_target = spawn_actor("res://scenes/ball.tscn","Team1",Vector2(30,0))
			var catalog:Script = load("res://scripts/effects/我的世界/mc_status_effects.gd")
			catalog.apply_effect(alive_target,"poison",150,10.0,attacker)
			poison = alive_target.get_node("MinecraftStatus_poison")
			poison.set_physics_process(false)
			expected = alive_target.global_position
			poison._tick_periodic_health_effect()
		expect_focus(expected,"GPU real source queued: "+kind)
		world._update_damage_focus()
		world._damage_focus_started_usec = Time.get_ticks_usec()-int((world._feedback_number("Focus_In")+0.015)*1000000.0)
		world.process_always(0.0)
		world.camera_2d.force_update_scroll()
		await RenderingServer.frame_post_draw
		var image:Image = root.get_texture().get_image()
		var after:Vector2 = _probe_center(image)
		var shift:Vector2 = world.camera_2d.global_position-center
		check(world._damage_focus_anchor.is_equal_approx(expected) and shift.dot(expected-center)>0.0,"GPU camera pulls toward the actual source: "+kind)
		check(before.is_finite() and after.is_finite() and (after.x-before.x)*(expected.x-center.x)<-1.0,"rendered reference pixels move opposite the source-directed camera pull: "+kind)
		check(world.camera_2d.zoom.x>world._base_camera_zoom_value()*world.toolbar_zoom_multiplier,"GPU source-directed focus still zooms in: "+kind)
		print("FOCUS_SOURCE_GPU ",kind," anchor=",expected," camera_delta=",shift," pixel_delta=",after-before)
		image.save_png(folder.path_join("source_"+kind+".png"))
		if is_instance_valid(source): source.free()
		if is_instance_valid(alive_target): alive_target.free()
	probe.free()
	reset_feedback()
