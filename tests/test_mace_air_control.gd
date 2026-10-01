extends "res://tests/test_elytra_return_dash.gd"
## Real shared control holders; no gameplay timer or process-mode freeze on the actor.
var cold_script:Script
var ball_script:Script
var completed:bool = false

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	cold_script = load("res://scripts/characters/我的世界/snow_golem/cold.gd")
	ball_script = load("res://classes/ball.gd")
	arena = FlightArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	create_timer(100.0,true,false,true).timeout.connect(func():push_error("MACE_CONTROL_TIMEOUT");quit(2))
	for role:String in ["重锤","鞘翅重锤","鞘翅重锤长矛"]:
		await control_cases(role)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(640,480)
		var camera:Camera2D = Camera2D.new()
		arena.add_child(camera)
		camera.zoom = Vector2(1.8,1.8)
		camera.make_current()
		camera.force_update_scroll()
		for role:String in ["重锤","鞘翅重锤","鞘翅重锤长矛"]:
			await gpu_case(role)
	completed = true
	current_scene = null
	arena.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("MACE_AIR_CONTROL_RESULT checks=",checks," failures=",failures," completed=",completed)
	quit(0 if failures==0 else 1)

func prepare(role:String) -> Node2D:
	var unit:Node2D = actor(role,Vector2.ZERO)
	unit.stun_shake_enabled = false
	unit.hurt_shake_enabled = false
	unit.self_hitbox.monitoring = false
	unit._begin_flight(3)
	unit._chain_damage_multiplier = 14.8
	unit._update_flight(0.12)
	return unit

func step(unit:Node2D,delta:float) -> void:
	unit.tick_physics(ball_script.State.Attack,delta)

func snapshot(unit:Node2D) -> Dictionary:
	var state:Dictionary = {"elapsed":unit._flight_elapsed,"level":unit._chain_level,"multiplier":unit._chain_damage_multiplier,"position":unit.global_position,"graphics":unit.graphics.transform,"image":unit.image.transform}
	if "_glide_velocity" in unit: state["glide"] = unit._glide_velocity
	return state

func same_jump(unit:Node2D,state:Dictionary) -> bool:
	return is_equal_approx(unit._flight_elapsed,state.elapsed) and unit._chain_level==state.level and is_equal_approx(unit._chain_damage_multiplier,state.multiplier) and unit.global_position.is_equal_approx(state.position) and unit.graphics.transform.is_equal_approx(state.graphics) and unit.image.transform.is_equal_approx(state.image) and (not state.has("glide") or unit._glide_velocity.is_equal_approx(state.glide))

func control_cases(role:String) -> void:
	var unit:Node2D = prepare(role)
	var enemy:Node2D = victim(Vector2(600,0))
	for warm:int in 6: await process_frame
	check(unit._airborne and unit._flight_elapsed>0.0,"real airborne chain started: "+role)
	var knock:Node = unit.apply_knockback(Vector2.RIGHT,40.0,120.0,0.0,0.0,{"source":enemy})
	check(is_instance_valid(knock) and unit.dizziness and not unit.is_hard_controlled(),"ordinary knockback input lock is not hard control: "+role)
	var before:float = unit._flight_elapsed
	step(unit,0.01)
	check(unit._flight_elapsed>before,"ordinary knockback does not pause the jump: "+role)
	knock._finish_knockback(false)
	check(not unit.is_hard_controlled(),"knockback recovery is still only a soft lock: "+role)
	knock.free()
	var cold:Node = cold_script.ensure(unit)
	check(cold.add_cold(50.0,0.5,enemy) and not unit.is_hard_controlled(),"partial cold is only a slow: "+role)
	before = unit._flight_elapsed
	step(unit,0.01)
	check(unit._flight_elapsed>before,"partial cold does not pause the jump: "+role)
	var stun:Node = unit.apply_stun(0.25,enemy)
	check(is_instance_valid(stun) and unit.is_hard_controlled(),"real apply_stun pauses an airborne mace: "+role)
	check(cold.add_cold(50.0,0.6,enemy) and cold.frozen_left>0.0,"real cold accumulation reaches freeze: "+role)
	var overlap_soft:Node = unit.apply_knockback(Vector2.LEFT,30.0,100.0,0.0,0.0,{"source":enemy,"replace_existing":false})
	check(unit.is_hard_controlled(),"an overlapping ordinary knockback cannot hide a hard control: "+role)
	var state:Dictionary = snapshot(unit)
	var health_before:float = enemy.health
	for tick:int in 8:
		step(unit,0.02)
		stun._physics_process(0.02)
		cold.advance(0.02)
	check(same_jump(unit,state),"hard control holds height, position, rotation, phase, stacks and momentum: "+role)
	check(cold.frozen_left<0.6 and stun._stun_elapsed>0.0,"control timers keep advancing while the jump is paused: "+role)
	unit._update_flight(5.0)
	unit._finish_landing()
	check(same_jump(unit,state) and enemy.health==health_before,"direct update and landing entry points cannot deal damage while controlled: "+role)
	stun._physics_process(0.2)
	check(unit.is_hard_controlled(),"expiring stun cannot prematurely release overlapping freeze: "+role)
	step(unit,0.02)
	check(same_jump(unit,state),"freeze alone still pauses the chain after stun expires: "+role)
	cold.advance(0.7)
	check(not unit.is_hard_controlled(),"last hard-control holder expires normally: "+role)
	before = unit._flight_elapsed
	step(unit,0.01)
	check(is_equal_approx(unit._flight_elapsed,before+0.01) and unit._chain_level==state.level and is_equal_approx(unit._chain_damage_multiplier,state.multiplier),"resume uses only the current delta and keeps the original chain: "+role)
	overlap_soft.free()
	cold.free()
	if is_instance_valid(stun): stun.free()

	var queued:Node = unit.apply_knockback(Vector2.RIGHT,20.0,100.0,0.0,0.3,{"source":enemy,"stun_only_on_collision":true})
	check(not unit.is_hard_controlled(),"collision-only stun is not active before collision: "+role)
	queued._finish_knockback(true)
	check(unit.is_hard_controlled(),"actual transition into stun becomes hard control: "+role)
	state = snapshot(unit)
	step(unit,0.02)
	check(same_jump(unit,state),"collision stun also holds the committed jump: "+role)
	queued.free()
	check(not unit.is_hard_controlled(),"removed controller cannot leave a stuck pause: "+role)

	cold = cold_script.ensure(unit)
	cold.add_cold(100.0,3.0,enemy)
	stun = unit.apply_stun(3.0,enemy)
	state = snapshot(unit)
	var cleaned:int = unit.cleanse_negative_effects()
	await process_frame
	check(cleaned>=2 and not unit.is_hard_controlled(),"shared cleanse releases both real hard-control effects: "+role)
	step(unit,0.01)
	check(unit._flight_elapsed>float(state.elapsed) and unit._chain_level==state.level,"cleansing resumes instead of resetting the chain: "+role)

	enemy.global_position = unit._ground_impact_center()
	state = snapshot(unit)
	health_before = enemy.health
	unit._finish_landing()
	check(enemy.health<health_before and unit._airborne,"the resumed chain can land, damage and rebound normally: "+role)
	check(is_equal_approx(unit._chain_damage_multiplier,float(state.multiplier)*unit.landing_damage_jump_multiplier),"successful resumed landing keeps its damage multiplier growth: "+role)
	unit.free()
	enemy.free()
	await process_frame

func marker_center(image:Image,color:Color) -> Vector2:
	var sum:Vector2 = Vector2.ZERO
	var count:int = 0
	for y:int in image.get_height():
		for x:int in image.get_width():
			var c:Color = image.get_pixel(x,y)
			if absf(c.r-color.r)<0.005 and absf(c.g-color.g)<0.005 and absf(c.b-color.b)<0.005:
				sum += Vector2(x,y)
				count += 1
	return sum/float(count) if count>0 else Vector2.INF

func gpu_case(role:String) -> void:
	var unit:Node2D = prepare(role)
	for warm:int in 6: await process_frame
	for side:int in [-1,1]:
		var probe:Polygon2D = Polygon2D.new()
		probe.polygon = PackedVector2Array([Vector2(-3,-3),Vector2(3,-3),Vector2(3,3),Vector2(-3,3)])
		var pixel_scale:Vector2 = unit.image.global_scale.abs()
		probe.scale = Vector2.ONE/pixel_scale
		probe.position = Vector2(side*12,0)/pixel_scale
		probe.color = Color.MAGENTA if side<0 else Color.CYAN
		probe.z_as_relative = false
		probe.z_index = 4090
		unit.image.add_child(probe)
	var stun:Node = unit.apply_stun(1.0)
	unit._stun_visual_instance.set_process(false)
	unit._stun_visual_instance.hide()
	for frame:int in 3: await RenderingServer.frame_post_draw
	var first:Image = root.get_texture().get_image()
	var a:Vector2 = marker_center(first,Color.MAGENTA)
	var b:Vector2 = marker_center(first,Color.CYAN)
	for tick:int in 12:
		step(unit,1.0/60.0)
		stun._physics_process(1.0/60.0)
	await RenderingServer.frame_post_draw
	var held:Image = root.get_texture().get_image()
	var a_held:Vector2 = marker_center(held,Color.MAGENTA)
	var b_held:Vector2 = marker_center(held,Color.CYAN)
	check(a.is_finite() and b.is_finite() and a.distance_to(a_held)<0.6 and b.distance_to(b_held)<0.6,"GPU both body probes remain fixed during hard control: "+role)
	stun._physics_process(1.0)
	step(unit,0.08)
	await RenderingServer.frame_post_draw
	var resumed:Image = root.get_texture().get_image()
	var a_resumed:Vector2 = marker_center(resumed,Color.MAGENTA)
	var b_resumed:Vector2 = marker_center(resumed,Color.CYAN)
	check(a_resumed.is_finite() and b_resumed.is_finite() and maxf(a.distance_to(a_resumed),b.distance_to(b_resumed))>2.0,"GPU body movement/spin resumes after control expires: "+role)
	print("MACE_CONTROL_GPU ",role," held=",a_held-a,",",b_held-b," resumed=",a_resumed-a,",",b_resumed-b)
	unit.free()
	await process_frame
