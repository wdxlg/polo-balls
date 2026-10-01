extends SceneTree
## 时钟：时间加速范围、速度伤害、时光倒流、带伤实体残影。
const SCENE := "res://scenes/characters/我的世界/时钟.tscn"
const FOE := "res://scenes/characters/物品/气球.tscn"
var FIELD:GDScript
var STATUS:GDScript
var checks:int = 0
var failures:int = 0
var game:Node
var arena:Node2D
var previous_scene:Node
var previous_stop:bool


func _initialize() -> void: call_deferred("run")


func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MC_CLOCK_FAIL " + label)


func frames(n:int) -> void:
	for i:int in n: await physics_frame


func spawn(path:String,pos:Vector2,team:String) -> Node2D:
	var actor:Node2D = (load(path) as PackedScene).instantiate() as Node2D
	actor.Team = team
	actor.position = pos
	arena.add_child(actor,true)
	return actor


func make_projectile(pos:Vector2) -> Node2D:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar travelled:float = 0.0\nfunc _physics_process(delta:float) -> void:\n\ttravelled += 100.0*delta\n"
	script.reload()
	var shot:Node2D = Node2D.new()
	shot.set_script(script)
	shot.add_to_group(&"Shooter")
	shot.position = pos
	arena.add_child(shot)
	return shot


func finish() -> void:
	game.now_stop_state = previous_stop
	current_scene = previous_scene
	arena.queue_free()
	print("MC_CLOCK_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)


func run() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	FIELD = load("res://scripts/characters/我的世界/clock/time_field.gd")
	STATUS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	previous_scene = current_scene
	previous_stop = game.now_stop_state
	game.now_stop_state = false
	var arena_script := GDScript.new()
	arena_script.source_code = "extends Node2D\nvar day_night_cycle:Node2D\nvar map_wall_light_direction:Vector2\nvar map_wall_volume:Node\n"
	arena_script.reload()
	arena = Node2D.new()
	arena.set_script(arena_script)
	root.add_child(arena)
	current_scene = arena
	var cycle:Node2D = (load("res://scripts/day_night_cycle.gd") as GDScript).new(arena)
	arena.add_child(cycle)
	arena.set("day_night_cycle",cycle)

	var clock:Node2D = spawn(SCENE,Vector2(300,300),"A")
	var foe:Node2D = spawn(FOE,Vector2(900,700),"B")
	await frames(3)
	var field:Node = null
	for n:Node in get_nodes_in_group(&"MCClockTimeField"): field = n
	check(field != null,"time field installed")
	check(clock.get_preview_texture() != null,"preview texture")
	check(clock.player_control_action_ids().is_empty(),"passive only, no C-key actions")
	check(not game.t("MC_ARMOR_INTRO_CLOCK").begins_with("MC_ARMOR"),"intro translated")

	check(is_equal_approx(float(clock.get_node("CharacterAutoFit").visual_size_multiplier),0.5),"scene-level auto-fit size (preview uses the same fit)")
	var foe_size:float = foe.image.texture.get_size().x*foe.image.global_scale.x
	var clock_size:float = clock.image.texture.get_size().x*clock.image.global_scale.x
	check(clock_size < foe_size*0.6,"clock drawn smaller than a normal character (%.1f vs %.1f)" % [clock_size,foe_size])
	clock._measured_speed = clock.base_travel_speed()*2.8
	check(not clock.ghosts_armed(),"no damaging afterimages below 3x speed")
	clock._measured_speed = clock.base_travel_speed()*3.2
	check(clock.ghosts_armed(),"damaging afterimages from 3x speed")
	# Speed -> collision damage multiplier.
	clock._measured_speed = clock.base_travel_speed()
	check(is_equal_approx(clock.current_hit_damage_multiplier(),1.0),"normal speed x1")
	clock._measured_speed = clock.base_travel_speed()*2.0
	check(is_equal_approx(clock.current_hit_damage_multiplier(),2.0),"double speed x2")
	clock._measured_speed = clock.base_travel_speed()*9.0
	check(is_equal_approx(clock.current_hit_damage_multiplier(),9.0),"multiplier uncapped (x9 at 9x)")
	clock._measured_speed = clock.base_travel_speed()*40.0
	check(is_equal_approx(clock.current_hit_damage_multiplier(),40.0),"multiplier uncapped (x40 at 40x)")
	clock._measured_speed = 0.0

	# Accelerated scope at k = 2.5: clock / projectile / status / world time, not the foe.
	clock.rewind_interval = 999.0
	clock._rewind_left = 999.0
	clock.time_accel_per_second = 0.0
	clock.time_scale = 2.5
	var shot:Node2D = make_projectile(Vector2(100,100))
	STATUS.apply_effect(foe,"resistance",1,20.0,null)
	var poison:Node = foe.get_node_or_null("MinecraftStatus_resistance")
	check(poison != null,"status applied")
	await frames(2)
	var shot0:float = float(shot.get("travelled"))
	var poison0:float = float(poison.get("remaining")) if poison != null else 0.0
	var minute0:float = cycle.minutes
	foe.set("_growth",0.0)
	var clock_wait0:float = float(clock.get("_clock_t"))
	var foe_wait0:float = float(foe.get("_growth"))
	await frames(60)
	var dt:float = 60.0/float(Engine.physics_ticks_per_second)
	var shot_rate:float = (float(shot.get("travelled"))-shot0)/(100.0*dt)
	check(absf(shot_rate-2.5) < 0.2,"projectile x2.5 (%.2f)" % shot_rate)
	if poison != null and is_instance_valid(poison):
		var poison_rate:float = (poison0-float(poison.get("remaining")))/dt
		check(absf(poison_rate-2.5) < 0.25,"status duration x2.5 (%.2f)" % poison_rate)
	var minute_rate:float = (cycle.minutes-minute0)/dt
	# The bare test arena does not advance day/night itself; only the clock's extra 1.5x shows.
	check(absf(minute_rate-1.5) < 0.2,"world time gets +1.5x extra (%.2f)" % minute_rate)
	var clock_rate:float = (float(clock.get("_clock_t"))-clock_wait0)/dt
	var foe_rate:float = (float(foe.get("_growth"))-foe_wait0)/(float(foe.get("grow_per_second"))*dt)
	check(absf(clock_rate-2.5) < 0.2,"clock itself x2.5 (%.2f)" % clock_rate)
	check(absf(foe_rate-1.0) < 0.1,"other character unaffected (%.2f)" % foe_rate)
	shot.queue_free()
	if poison != null and is_instance_valid(poison): STATUS.clear(foe,"resistance")

	# Growth.
	clock.time_scale = 1.0
	clock.time_accel_per_second = 0.5
	await frames(60)
	check(clock.time_scale > 1.3,"time scale grows (%.2f)" % clock.time_scale)
	clock.time_scale = 60.0
	await frames(10)
	check(clock.time_scale > 60.0,"time scale has no cap (%.2f)" % clock.time_scale)
	var fast_shot:Node2D = make_projectile(Vector2(100,140))
	await frames(2)
	var f0:float = float(fast_shot.get("travelled"))
	await frames(30)
	var fast_rate:float = (float(fast_shot.get("travelled"))-f0)/(100.0*30.0/float(Engine.physics_ticks_per_second))
	check(fast_rate > 55.0,"x60 still fully applied to delta-based projectiles (%.1f)" % fast_rate)
	fast_shot.queue_free()
	clock.time_accel_per_second = 0.0
	clock.time_scale = 1.0

	# Rewind returns along the path and restores health lost in the window.
	# At 5x the rewind still reaches back one real second and plays over real time.
	clock.time_scale = 5.0
	clock.direction = Vector2(1.0,0.4).normalized()
	clock.rewind_interval = 999.0
	clock._rewind_left = 999.0
	clock.health = clock.Max_health - 150
	STATUS.apply_effect(clock,"resistance",1,30.0,null)
	await frames(75)
	var resist_then:float = -1.0
	await frames(1)
	# Within the last second: healed, lost resistance, gained slowness.
	clock.health = clock.Max_health
	STATUS.clear(clock,"resistance")
	STATUS.apply_effect(clock,"slowness",1,30.0,null)
	await frames(2)
	check(STATUS.active(clock,"slowness") and not STATUS.active(clock,"resistance"),"status setup before rewind")
	var before:int = clock.rewind_count
	clock._rewind_left = 0.0
	var rewind_frames:int = 0
	var invincible_ok:bool = true
	var overlay_seen:bool = false
	var rewind_ghost_fx:bool = false
	for i:int in 60:
		await frames(1)
		if clock._rewinding:
			rewind_frames += 1
			if resist_then < 0.0:
				for e:Dictionary in clock._rewind_snap.get("statuses",[]):
					if str(e.kind) == "resistance": resist_then = float(e.props.get("remaining",-1.0))
			var hp_before:int = clock.health
			clock.take_damage(80.0,true)
			clock.receive_positional_damage(80.0,clock.global_position,true,foe)
			if clock.health < hp_before: invincible_ok = false
			var overlay:Node = clock.image.get_parent().get_node_or_null("ClockRewindOverlay")
			if overlay != null and overlay.material != null and not clock.image.visible: overlay_seen = true
			for n:Node in arena.get_children():
				if n.name.begins_with("ClockAfterimage") and n.get_child_count() > 0 and (n.get_child(0) as CanvasItem).material != null: rewind_ghost_fx = true
		elif clock.rewind_count > before: break
	check(invincible_ok,"invincible while rewinding")
	check(overlay_seen,"rewind shader overlay on the clock")
	check(rewind_ghost_fx,"rewind afterimages carry the rewind shader")
	check(clock.image.visible and clock.image.get_parent().get_node_or_null("ClockRewindOverlay") == null or clock.image.get_parent().get_node("ClockRewindOverlay").is_queued_for_deletion(),"overlay removed after rewind")
	check(clock.health == clock.Max_health - 150,"rewind restores exact health, both ways (%d)" % clock.health)
	check(STATUS.active(clock,"resistance"),"rewind restores a status that was removed")
	check(not STATUS.active(clock,"slowness"),"rewind removes a status gained afterwards")
	if STATUS.active(clock,"resistance"):
		var r:float = float(STATUS.current(clock,"resistance").remaining)
		check(absf(r - resist_then) < 0.3,"restored status timer matches the past (%.2f vs %.2f)" % [r,resist_then])
	STATUS.clear(clock,"resistance")
	check(clock.rewind_count > before,"rewind fired")
	check(absf(clock.rewind_real_span - 1.0) < 0.06,"rewind reaches back one real second (%.2f)" % clock.rewind_real_span)
	check(rewind_frames >= 12,"rewind plays over real time at 5x (%d frames)" % rewind_frames)
	clock.time_scale = 1.0
	var trail:int = 0
	for n:Node in arena.get_children(): if n.name.begins_with("ClockAfterimage"): trail += 1
	check(trail > 0,"rewind always leaves a visible trail")
	clock.health = clock.Max_health
	clock.rewind_interval = 999.0
	clock._rewind_left = 999.0

	# Afterimages: armed ones are solid, damage enemies once per guard window and appear as threats.
	var ghosts_before:int = 0
	for n:Node in arena.get_children(): if n.name.begins_with("ClockAfterimage"): ghosts_before += 1
	foe.global_position = Vector2(600,300)
	foe.set("_base_speed",0.0)
	foe.Speed = 0.0
	clock.global_position = Vector2(150,150)
	await frames(2)
	var hp0:int = foe.health
	clock._measured_speed = clock.base_travel_speed()*2.0
	clock._spawn_ghost(foe.global_position,true)
	await frames(3)
	var solid:StaticBody2D = null
	for n:Node in arena.get_children():
		if n.name.begins_with("ClockAfterimage"):
			for c:Node in n.get_children(): if c is StaticBody2D: solid = c
	check(solid != null,"armed afterimage has a collision body")
	if solid != null: check(not solid.get_parent().z_as_relative and solid.get_parent().z_index < clock._effective_z(clock.image) and solid.get_parent().z_index < clock._effective_z(foe.image),"afterimage drawn below characters")
	if solid != null: check(clock.get_collision_exceptions().has(solid),"clock passes through own afterimage")
	check(foe.health < hp0,"afterimage damages enemy (%d -> %d)" % [hp0,foe.health])
	var kinds:Array = clock.get_debug_attack_regions().map(func(r): return r.kind)
	check(kinds.has("clock_body") and kinds.has("clock_afterimage"),"threat regions body + afterimage")
	var hp1:int = foe.health
	await frames(6)
	check(foe.health == hp1,"per-target guard prevents multi-hit")
	foe.Team = "A"
	clock._ghost_hits.clear()
	clock._spawn_ghost(foe.global_position,true)
	await frames(3)
	check(foe.health == hp1,"afterimage never hurts teammates")
	await frames(40)
	var left:int = 0
	for n:Node in arena.get_children(): if n.name.begins_with("ClockAfterimage"): left += 1
	check(left == 0,"afterimages expire")
	finish()
