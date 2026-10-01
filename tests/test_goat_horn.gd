extends SceneTree
const SCENE_PATH:String = "res://scenes/characters/我的世界/山羊角.tscn"
const GOAT_PATH:String = "res://scripts/characters/我的世界/goat_horn/goat_charger.gd"
var world:Node
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var done:bool = false

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate() as Node2D
	unit.Team = team
	unit.Health_Restore = 0
	unit.position = point
	world.add_child(unit,true)
	return unit

func dummy(point:Vector2,team:String = "Team1") -> Node2D:
	var target:Node2D = spawn("res://scenes/ball.tscn",point,team)
	target.Can_Attack = false
	target.Can_Skill = false
	target.Max_health = 10000
	target.default_properties["Max_health"] = 10000
	target.health = 10000
	target.Has_Collision_Damage = false
	target.state_machine.set_physics_process(false)
	return target

func has_knockback(unit:Node) -> bool:
	return unit.get_children().any(func(c:Node): return c.has_method("replace_with_hit"))

func sound_events() -> Array:
	return get_nodes_in_group("MCNativeSFX").map(func(n:Node): return str(n.get_meta("mc_sound_event","")))

func goats() -> Array:
	return get_nodes_in_group("GoatHornGoat").filter(func(n:Node): return is_instance_valid(n) and not n.is_queued_for_deletion())

func clear_goats() -> void:
	for g:Node in goats(): g.queue_free()
	await process_frame

func any_goat_scale_ok(horn:Node2D) -> bool:
	var list:Array = goats()
	if list.is_empty(): return false
	var g:Node2D = list[0]
	var k:float = absf(horn.global_scale.x)
	return is_equal_approx(g.unit_scale,k) and is_equal_approx(g.get_node("Sprite").scale.x,g.SPRITE_SCALE * k) and is_equal_approx(g.body_radius,g.BODY_RADIUS_UNIT * k)

func goats_above_outside_mask() -> bool:
	var mask:Variant = world.get("map_outside_mask_root")
	if not (mask is Node2D and is_instance_valid(mask) and (mask as Node2D).visible): return false
	var mask_z:int = (mask as Node2D).z_index
	var list:Array = goats()
	return not list.is_empty() and list.all(func(g:Node2D): return not g.z_as_relative and g.z_index > mask_z)

func frames(n:int) -> void:
	for i:int in range(n): await physics_frame

func finish(code:int) -> void:
	if done: return
	done = true
	print("GOAT HORN RESULT: ",checks - failures,"/",checks," passed")
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world):
		for node:Node in world.find_children("*","Node",true,false):
			if node.get_script() != null and node.get_script().resource_path.ends_with("mc_native_prewarm.gd"):
				node.set_process(false)
	var warm:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warm.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/" + role + ".tscn"
		var status:int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var GOAT:Script = load(GOAT_PATH)

	# --- 场景与登记 ---
	var horn:Node2D = spawn(SCENE_PATH,center + Vector2(-160,0))
	var target:Node2D = dummy(center + Vector2(160,0))
	await physics_frame
	await process_frame
	check(horn.Max_health == 370 and is_equal_approx(horn.Damage,9.0) and is_equal_approx(horn.Speed,80.0),"山羊角 stats 370 HP / 9 damage / 80 speed")
	check(world.return_all_character_names().has("山羊角"),"山羊角 appears in the Minecraft roster")
	check(horn.Unique_Death_Audio == horn.AUDIO.EVENTS["entity.item.break"][0].stream,"death uses native item break")
	check(horn.call("is_combat_runtime_active"),"real World combat is active")
	check(is_equal_approx(horn._blow_wait,4.0) or horn._blow_wait < 4.0 and horn._blow_wait > 3.5,"first blow scheduled at about 4 s")

	# --- 吹号：起手、号声、声波环、山羊批次 ---
	horn._blow_wait = 0.0
	await frames(2)
	check(horn._blow_phase != 0,"AI starts blowing once ready with an enemy present")
	check(horn.motion_speed_factor() < 0.75,"movement is slowed while blowing")
	var tooted:bool = false
	for i:int in range(60):
		await physics_frame
		if horn._blow_serial > 0:
			tooted = true
			break
	check(tooted,"windup completes into a toot")
	await process_frame
	await process_frame
	check(sound_events().any(func(e:String): return e.begins_with("item.goat_horn.sound.")),"native goat horn call plays")
	check(get_nodes_in_group("GoatHornCallRing").size() >= 1,"call ring spawned at the bell")
	check(is_equal_approx(horn._blow_wait,horn.blow_interval) or horn._blow_wait > horn.blow_interval - 1.0,"next blow scheduled after the 15 s interval")
	var expected:int = horn._pending_goats.size()
	check(expected >= 14 and expected <= 16,"each blow schedules 14-16 goats (got %d)" % expected)
	var view:Rect2 = GOAT.view_rect(horn)
	var seen_start:Array = []
	var first_ids:Dictionary = {}
	var spawn_times:Array[float] = []
	var elapsed:float = 0.0
	var idle_while_spawning:bool = false
	for i:int in range(1200):
		await physics_frame
		elapsed += get_root().get_physics_process_delta_time()
		for g:Node in goats():
			if not first_ids.has(g.goat_id):
				first_ids[g.goat_id] = true
				seen_start.append(g.global_position)
				spawn_times.append(elapsed)
		if horn._blow_phase == 0 and not horn._pending_goats.is_empty(): idle_while_spawning = true
		if horn._pending_goats.is_empty() and horn._blow_phase == 0: break
	var min_gap:float = INF
	for k:int in range(1,spawn_times.size()): min_gap = minf(min_gap,spawn_times[k] - spawn_times[k - 1])
	check(spawn_times.size() >= 2 and min_gap >= horn.goat_spawn_gap - horn.goat_spawn_jitter - 0.05,"goats appear one by one with a clear gap (min %.2f s)" % min_gap)
	check(idle_while_spawning,"goats keep appearing after the horn finishes blowing (no long slowdown)")
	check(first_ids.size() == expected,"all scheduled goats spawned (%d/%d)" % [first_ids.size(),expected])
	check(view.size.x > 1.0 and seen_start.all(func(p:Vector2): return not view.has_point(p)),"every goat enters from off-screen")
	check(any_goat_scale_ok(horn),"goat size follows the horn's character scale")
	check(goats_above_outside_mask(),"goats draw above the map-outside mask so they stay visible off the map")
	check(goats().all(func(g:Node): return g.CHARGE_MAX_SPEED <= 150.0 and g.EXIT_MAX_SPEED <= 300.0),"goat speeds stay moderate")
	check(get_nodes_in_group("GoatHornGoat").all(func(g:Node): return not g is CollisionObject2D and not g.is_in_group("Ball")),"goats are bodiless, untargetable transients")
	var any_goat:Node = goats()[0] if not goats().is_empty() else null
	check(any_goat != null and any_goat.is_in_group("AI_Hazard") and is_equal_approx(any_goat.get_ai_hazard_info().get("radius",0.0),any_goat.body_radius) and any_goat.get_ai_hazard_info().get("source") == horn,"goat registers its real ram circle as AI hazard")
	var profile:Dictionary = load("res://classes/combat_classification.gd").profile_of(any_goat) if any_goat != null else {}
	check(str(profile.get("entity_kind","")) == "hazard","goat classified as hazard")
	check(horn._blow_phase == 0,"blow returns to idle after the hold")
	await clear_goats()

	# --- 冲撞：伤害、击退、撞击音，速度越快伤害越高 ---
	horn.state_machine.set_physics_process(false)
	var slow_target:Node2D = dummy(center + Vector2(0,-150))
	var fast_target:Node2D = dummy(center + Vector2(0,150))
	await physics_frame
	var g_slow:Node2D = GOAT.new()
	g_slow.setup_authority(horn,9001,slow_target,slow_target.global_position - Vector2(40,0),1)
	world.add_child(g_slow)
	g_slow.speed = 50.0
	var g_fast:Node2D = GOAT.new()
	g_fast.setup_authority(horn,9002,fast_target,fast_target.global_position - Vector2(40,0),2)
	world.add_child(g_fast)
	g_fast.speed = 120.0
	g_slow.set_physics_process(false)
	g_fast.set_physics_process(false)
	var hs:float = slow_target.health
	var hf:float = fast_target.health
	g_slow._ram(horn,slow_target,slow_target.global_position)
	g_fast._ram(horn,fast_target,fast_target.global_position)
	var loss_slow:float = hs - slow_target.health
	var loss_fast:float = hf - fast_target.health
	check(loss_slow > 0.0 and loss_fast > loss_slow,"ram damage grows with goat speed (%.1f slow vs %.1f fast)" % [loss_slow,loss_fast])
	check(has_knockback(slow_target) and has_knockback(fast_target),"ram applies shared knockback")
	var sheep_ref:Node2D = spawn("res://scenes/characters/我的世界/羊.tscn",center + Vector2(0,330),"Team2")
	await physics_frame
	var same_curve:bool = true
	for v:float in [50.0,120.0,260.0,520.0]:
		var mine:Dictionary = GOAT.impact_profile(horn,g_fast.impact_ratio(v))
		var theirs:Dictionary = sheep_ref.impact_profile(v)
		if not is_equal_approx(mine.distance,theirs.distance) or not is_equal_approx(mine.speed,theirs.speed): same_curve = false
	check(same_curve,"ram knockback follows the sheep's impact curve at the same speed")
	var top:Dictionary = GOAT.impact_profile(horn,g_fast.impact_ratio(g_fast.CHARGE_MAX_SPEED))
	check(top.distance < 90.0,"a goat at full charge knocks back like a sheep at that speed (%.0f px)" % top.distance)
	sheep_ref.queue_free()
	check(g_fast.speed < 120.0,"goat loses momentum on impact")
	await process_frame
	await process_frame
	check(sound_events().has("entity.goat.ram_impact"),"native goat ram impact plays")
	g_slow.queue_free()
	g_fast.queue_free()

	# --- 持续顶住：周期推撞 ---
	var push_target:Node2D = dummy(center + Vector2(0,40))
	await physics_frame
	var g_push:Node2D = GOAT.new()
	g_push.setup_authority(horn,9003,push_target,push_target.global_position,3)
	world.add_child(g_push)
	g_push.set_physics_process(false)
	g_push.speed = 100.0
	var id:int = push_target.get_instance_id()
	g_push._contacts[id] = 0.0
	var h0:float = push_target.health
	g_push._resolve_contacts(horn,g_push.global_position,g_push.global_position,0.01)
	var h1:float = push_target.health
	g_push._resolve_contacts(horn,g_push.global_position,g_push.global_position,0.01)
	var h2:float = push_target.health
	g_push._resolve_contacts(horn,g_push.global_position,g_push.global_position,0.2)
	var h3:float = push_target.health
	check(h1 < h0,"overlapping goat pushes and damages")
	check(is_equal_approx(h2,h1),"push respects its interval")
	check(h3 < h2,"continued pushing deals repeated damage")
	g_push.queue_free()

	# --- 不伤同队 ---
	var ally:Node2D = dummy(center + Vector2(0,-40),"Team0")
	await physics_frame
	var g_ally:Node2D = GOAT.new()
	g_ally.setup_authority(horn,9004,null,ally.global_position - Vector2(30,0),4)
	world.add_child(g_ally)
	g_ally.set_physics_process(false)
	var ha:float = ally.health
	g_ally._resolve_contacts(horn,ally.global_position - Vector2(30,0),ally.global_position + Vector2(30,0),0.016)
	check(is_equal_approx(ally.health,ha) and not has_knockback(ally),"goats never hit the horn's own team")
	check(horn.pick_goat_target() != ally,"own team is never chosen as a goat target")
	g_ally.queue_free()
	ally.queue_free()

	# --- 撞到目标后加速离场，离开屏幕即释放 ---
	var run_target:Node2D = dummy(center + Vector2(200,-260))
	await physics_frame
	var g_run:Node2D = GOAT.new()
	g_run.setup_authority(horn,9005,run_target,run_target.global_position - Vector2(120,0),5)
	world.add_child(g_run)
	g_run.speed = 120.0
	var rammed:bool = false
	for i:int in range(180):
		await physics_frame
		if not is_instance_valid(g_run): break
		if g_run._rammed: rammed = true
		if rammed and g_run.phase == GOAT.Phase.EXIT: break
	check(rammed and is_instance_valid(g_run) and g_run.phase == GOAT.Phase.EXIT,"after ramming the goat switches to exit")
	if is_instance_valid(g_run):
		var before:float = g_run.speed
		await frames(10)
		check(is_instance_valid(g_run) and g_run.speed > before,"exiting goat accelerates")
	if is_instance_valid(g_run):
		var far:Rect2 = GOAT.view_rect(g_run)
		g_run.global_position = far.end + Vector2(400,400)
		await frames(2)
	check(not is_instance_valid(g_run) or g_run.is_queued_for_deletion(),"exiting goat is freed once off-screen")

	# --- 锁定出现时的位置：目标移走后仍冲向原位置，越过后离场 ---
	var lock_target:Node2D = dummy(center + Vector2(-120,200))
	await physics_frame
	var locked_at:Vector2 = lock_target.global_position
	var g_lock:Node2D = GOAT.new()
	g_lock.setup_authority(horn,9007,lock_target,locked_at - Vector2(160,0),7)
	world.add_child(g_lock)
	var lock_heading:Vector2 = g_lock.heading
	lock_target.global_position = locked_at + Vector2(0,-120)
	var lock_hp:float = lock_target.health
	var steps_before:int = sound_events().count("entity.goat.step")
	var particles:int = 0
	var lock_exit:bool = false
	for i:int in range(300):
		await physics_frame
		particles = maxi(particles,get_nodes_in_group("MCBlockFragments").size())
		if not is_instance_valid(g_lock): break
		if g_lock.phase == GOAT.Phase.EXIT and g_lock.global_position.x > locked_at.x:
			lock_exit = true
			break
	check(is_instance_valid(g_lock) and g_lock.aim_point.is_equal_approx(locked_at) and g_lock.heading.is_equal_approx(lock_heading),"goat keeps the target position from when it appeared (no homing)")
	check(lock_exit,"goat passes the locked point and switches to exit")
	check(is_equal_approx(lock_target.health,lock_hp),"a target that moved away is not hit")
	await process_frame
	check(sound_events().count("entity.goat.step") > steps_before or sound_events().has("entity.goat.step"),"running goat plays native footsteps")
	check(particles > 1,"running goat keeps leaving block particles behind on the floor")
	if is_instance_valid(g_lock): g_lock.queue_free()
	lock_target.queue_free()

	# --- 脚下地面取样：格子地图取瓦片，方块主题取主题地板，墙上/地图外没有 ---
	var tile_floor:Dictionary = GOAT.floor_sample(horn,center + Vector2(0,-200))
	check(not tile_floor.is_empty() and tile_floor.texture != null and float(tile_floor.block_px) > 1.0,"floor sample reads the map tile under the goat")
	var outside_floor:Dictionary = GOAT.floor_sample(horn,center + Vector2(5000,0))
	check(outside_floor.is_empty(),"no floor particles outside the map")
	var old_bg:Variant = game.Game_Settings.get("Map_Background","blue")
	game.Game_Settings["Map_Background"] = "grass"
	var grass_floor:Dictionary = GOAT.floor_sample(horn,center + Vector2(0,-200))
	game.Game_Settings["Map_Background"] = old_bg
	check(not grass_floor.is_empty() and grass_floor.texture == GOAT.MAP_THEMES.floor_texture("grass") and grass_floor.modulate == GOAT.MAP_THEMES.theme("grass").floor_modulate,"block themes use the themed floor texture and tint")

	# --- 冻结：战斗暂停时山羊不动 ---
	var g_freeze:Node2D = GOAT.new()
	g_freeze.setup_authority(horn,9006,run_target,center + Vector2(-300,-300),6)
	world.add_child(g_freeze)
	await physics_frame
	game.now_stop_state = true
	var frozen_at:Vector2 = g_freeze.global_position
	await frames(5)
	check(g_freeze.global_position.is_equal_approx(frozen_at),"goats freeze while combat runtime is stopped")
	game.now_stop_state = false
	g_freeze.queue_free()

	# --- 客户端外推表现 ---
	var puppet:Node2D = GOAT.new()
	puppet.setup_puppet(horn,9100,center,Vector2.RIGHT,500.0,1)
	world.add_child(puppet)
	await process_frame
	puppet.apply_network_state(center + Vector2(10,0),Vector2.RIGHT,500.0,3)
	for i:int in range(6): await process_frame
	check(puppet.global_position.x > center.x and puppet.phase == GOAT.Phase.EXIT,"puppet follows network state and flags")
	check(puppet.get_node("Sprite").flip_h and puppet.get_node("Sprite").animation == &"ram","puppet faces its heading and plays the ram clip")
	puppet.apply_network_state(center + Vector2(20,20),Vector2(1,1).normalized(),500.0,0)
	await process_frame
	check(puppet.get_node("Sprite").flip_h and is_zero_approx(puppet.get_node("Sprite").rotation),"diagonal running still faces only right, no tilt")
	puppet.apply_network_state(center + Vector2(0,40),Vector2(-1,1).normalized(),500.0,0)
	await process_frame
	check(not puppet.get_node("Sprite").flip_h and is_zero_approx(puppet.get_node("Sprite").rotation),"diagonal running still faces only left, no tilt")
	check(puppet.get_node("Sprite").animation == &"ram","goat keeps the head-down ram pose while running")
	puppet.queue_free()

	# --- 起手被眩晕打断 ---
	horn.state_machine.set_physics_process(true)
	horn._blow_phase = 0
	horn._blow_wait = 0.0
	await frames(2)
	check(horn._blow_phase == 1,"windup begins")
	horn.dizziness = true
	await frames(2)
	check(horn._blow_phase == 0 and horn._blow_wait >= 0.9,"stun during windup cancels and retries shortly")
	horn.dizziness = false

	# --- 手控：只在按键时吹 ---
	horn.set_player_control_peer(1)
	horn._blow_phase = 0
	horn._blow_wait = 0.0
	await frames(3)
	check(horn._blow_phase == 0,"manual control stops automatic blowing")
	horn.controlled_attack_action()
	await frames(2)
	check(horn._blow_phase != 0,"left click blows the horn when ready")
	horn.set_player_control_peer(0)

	# --- 本体退出：清理全部山羊 ---
	for i:int in range(80):
		await physics_frame
		if not goats().is_empty(): break
	var had:bool = not goats().is_empty()
	horn.queue_free()
	await process_frame
	await process_frame
	check(had and goats().is_empty(),"all goats vanish with the horn")
	target.queue_free()
	finish(0 if failures == 0 else 1)
