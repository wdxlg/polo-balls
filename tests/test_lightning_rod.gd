extends SceneTree
const SCENE_PATH:String = "res://scenes/characters/我的世界/避雷针.tscn"
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
	target.Speed = 0.0
	target.default_properties["Speed"] = 0.0
	target.state_machine.set_physics_process(false)
	return target

func frames(n:int) -> void:
	for i:int in range(n): await physics_frame

func hold(unit:Node2D,point:Vector2) -> void:
	unit.global_position = point
	if "velocity" in unit: unit.velocity = Vector2.ZERO

func sound_streams() -> Array:
	return get_nodes_in_group("MCNativeSFX").map(func(n:Node): return n.get("stream"))

func finish(code:int) -> void:
	if done: return
	done = true
	print("LIGHTNING ROD RESULT: ",checks - failures,"/",checks," passed")
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	if "_settings_storage_path" in game: game._settings_storage_path = OS.get_temp_dir().path_join("arena_lightning_rod_settings.cfg")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings["Local_Hitstop"] = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(80.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()

	# --- 场景、数值与登记 ---
	var rod:Node2D = spawn(SCENE_PATH,center)
	rod.Speed = 0.0
	rod.default_properties["Speed"] = 0.0
	var near:Node2D = dummy(center + Vector2(70,0))
	await physics_frame
	await process_frame
	check(rod.Max_health == 750 and is_equal_approx(rod.Damage,30.0),"避雷针 750 HP / 30 damage")
	check(world.return_all_character_names().has("避雷针"),"避雷针 appears in the roster")
	check(rod.call("is_combat_runtime_active"),"real World combat is active")
	check(rod.dir_index >= 0 and rod.dir_index < 4,"a random direction is chosen at once")
	check(rod.cloud_position.distance_to(rod.global_position) > 100.0,"cloud gathers away from the rod")
	var map_rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	for side:int in range(4):
		rod._apply_direction(side,rod.cloud_serial + 1)
		var half:Vector2 = load("res://scripts/characters/我的世界/lightning_rod/storm_visual.gd").cloud_half_extent(side)
		var footprint := Rect2(rod.cloud_position - half,half * 2.0)
		check(not footprint.intersects(map_rect),"cloud on side %d sits wholly outside the map" % side)
		var along:float = rod.cloud_position.x - rod.global_position.x if side < 2 else rod.cloud_position.y - rod.global_position.y
		check(absf(along) < 1.0,"cloud on side %d lines up with the rod" % side)
	check(rod.charge_bar.BAR == load("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd"),"charge bar paints with the shared bar")
	check(rod.time_to_next_volley() > 2.5 and rod.time_to_next_volley() <= 3.0,"first volley about 3 s after the cloud appears")
	check(rod.get_node("LightningRodChargeBar").get_parent() == rod and rod.get_node_or_null("Graphics/LightningRodChargeBar") == null,"charge bar lives outside Graphics")
	check(rod.bar_alpha() == 0.0,"charge bar hidden while idle")

	# --- 落雷：小范围伤害 + 眩晕；每轮 2-5 条；每条充能 ---
	rod.cycle_age = rod.gather_time - 0.02
	var hp:float = near.health
	var serial_before:int = rod._volley_serial
	await frames(3)
	check(rod._volley_serial == serial_before + 1,"one volley fires at the gather time")
	var queued:int = rod._pending_bolts.size() + rod.nets.size()
	check(queued >= 2 and queued <= 5,"volley holds 2-5 bolts (got %d)" % queued)
	var shared_bolts:int = 0
	for i:int in range(30):
		hold(near,center + Vector2(70,0))
		await physics_frame
		for child:Node in rod.storm.get_children():
			if child.get_script() == load("res://scripts/effects/我的世界/雷电.gd") and child.get_meta("counted",false) == false:
				child.set_meta("counted",true)
				shared_bolts += 1
		if rod._pending_bolts.is_empty(): break
	await frames(2)
	check(shared_bolts == queued,"every bolt is the shared lightning effect (%d/%d)" % [shared_bolts,queued])
	var lost:float = hp - near.health
	check(lost >= 30.0 and is_equal_approx(fposmod(lost - 30.0,3.0),0.0) and lost < 60.0,"impact deals 30 once per volley, the rest are net ticks (lost %.1f)" % lost)
	check(near.dizziness,"impact stuns")
	check(is_equal_approx(rod.storm_charge,rod.charge_per_bolt * float(queued)),"each bolt adds charge (%.1f)" % rod.storm_charge)
	check(rod.bar_alpha() > 0.0,"charge bar appears when the charge changes")
	check(rod.nets.size() == queued,"each bolt leaves a net")
	var far:Node2D = dummy(center + Vector2(0,-330))
	var far_hp:float = far.health
	await frames(2)
	check(far.health == far_hp,"impact is small-radius only")

	# --- 电网：沿路径高频伤害 + 短眩晕 ---
	var net:Dictionary = rod.nets[0]
	var a:Vector2 = rod.cloud_position + Vector2(net.offset)
	var mid:Vector2 = a.lerp(rod.tip_world_position(),0.8)
	var on_net:Node2D = dummy(mid)
	var net_hp:float = on_net.health
	var hits:int = 0
	var last:float = net_hp
	for i:int in range(18):
		var n0:Dictionary = rod.nets[0] if not rod.nets.is_empty() else net
		hold(on_net,(rod.cloud_position + Vector2(n0.offset)).lerp(rod.tip_world_position(),0.8))
		await physics_frame
		if on_net.health < last:
			hits += 1
			last = on_net.health
	check(hits >= 2,"net ticks repeatedly on the path (%d ticks)" % hits)
	check(is_equal_approx((net_hp - on_net.health) / float(maxi(hits,1)),3.0),"net tick deals 10%% damage")
	check(on_net.dizziness,"net applies short stun")
	on_net.global_position = center + Vector2(-600,-600)

	# --- 威胁显示 ---
	var threats:Array = rod.get_ai_attack_threats(near)
	check(threats.any(func(t:Dictionary): return t.kind == "lightning_rod_net" and t.shape == "segment"),"net threats are shown")
	check(threats.any(func(t:Dictionary): return t.kind == "lightning_rod_impact" and is_equal_approx(t.radius,rod.impact_radius)),"impact threat matches the real radius")
	check(rod.get_ai_attack_threats(rod).is_empty(),"no threats toward allies")

	# --- 被打放电：消耗能量，小范围伤害 ---
	near.dizziness = false
	hold(near,center + Vector2(70,0))
	rod.storm_charge = 40.0
	var near_hp:float = near.health
	rod.receive_classified_spatial_damage(5.0,{"shape":"circle","point":rod.global_position,"origin":far.global_position,"radius":4.0,"source":far,"focus_position":rod.global_position,"carrier":"area"},&"ordinary")
	await frames(3)
	check(is_equal_approx(rod.storm_charge,40.0 - rod.discharge_cost),"being hit spends charge on a discharge")
	check(near.health < near_hp,"discharge hurts nearby enemies")
	check(far.health == far_hp,"discharge stays small-radius")
	rod.receive_classified_spatial_damage(5.0,{"shape":"circle","point":rod.global_position,"origin":far.global_position,"radius":4.0,"source":far,"focus_position":rod.global_position,"carrier":"area"},&"ordinary")
	await frames(2)
	check(is_equal_approx(rod.storm_charge,40.0 - rod.discharge_cost),"discharge has a short cooldown")
	rod.storm_charge = 3.0
	rod._discharge_wait = 0.0
	rod.receive_classified_spatial_damage(5.0,{"shape":"circle","point":rod.global_position,"origin":far.global_position,"radius":4.0,"source":far,"focus_position":rod.global_position,"carrier":"area"},&"ordinary")
	await frames(2)
	check(is_equal_approx(rod.storm_charge,3.0),"no discharge without enough charge")

	# --- 颤抖：接近满才抖，越满越大 ---
	rod.storm_charge = 50.0
	await process_frame
	var rest:Vector2 = rod._rest_image_position
	check(rod.image.position.is_equal_approx(rest),"no tremble at half charge")
	var amp_low:float = 0.0
	var amp_high:float = 0.0
	rod.storm_charge = 75.0
	for i:int in range(20):
		await process_frame
		amp_low = maxf(amp_low,rod.image.position.distance_to(rest))
	rod.storm_charge = 98.0
	for i:int in range(20):
		await process_frame
		amp_high = maxf(amp_high,rod.image.position.distance_to(rest))
	check(amp_low > 0.0 and amp_high > amp_low * 2.0,"tremble grows near full (%.2f -> %.2f)" % [amp_low,amp_high])

	# --- 充满：扩散雷圈，高频伤害 + 眩晕 ---
	rod.storm_charge = rod.storm_charge_max - 1.0
	far.dizziness = false
	far_hp = far.health
	rod._add_charge(rod.charge_per_bolt)
	await frames(2)
	var rings:Array = get_nodes_in_group("MCLightningRodRing")
	check(rings.size() == 1 and rod.storm_charge == 0.0,"full charge releases the thunder ring and empties the bar")
	check(rod.get_ai_attack_threats(near).any(func(t:Dictionary): return t.kind == "lightning_rod_ring"),"ring threat bands are shown")
	var ring_hits:int = 0
	last = far.health
	for i:int in range(150):
		hold(far,center + Vector2(0,-330))
		await physics_frame
		if far.health < last:
			ring_hits += 1
			last = far.health
		if get_nodes_in_group("MCLightningRodRing").is_empty(): break
	check(ring_hits >= 3,"ring sweeps hit a distant enemy repeatedly (%d)" % ring_hits)
	check(get_nodes_in_group("MCLightningRodRing").is_empty(),"ring expires")

	# --- 9 秒换方向 ---
	var old_dir:int = rod.dir_index
	var old_serial:int = rod.cloud_serial
	rod.cycle_age = rod.direction_interval - 0.01
	await frames(2)
	check(rod.cloud_serial == old_serial + 1 and rod.dir_index != old_dir and rod.nets.is_empty(),"direction changes after 9 s to a different side")
	check(rod.cycle_age < 0.2 and rod._volleys_fired == 0,"new cloud gathers again")

	# --- 暂停冻结 ---
	game.now_stop_state = true
	var frozen:float = rod.cycle_age
	await frames(5)
	check(is_equal_approx(rod.cycle_age,frozen),"storm freezes while combat is stopped")
	game.now_stop_state = false

	# --- 死亡：乌云散去，铜块碎裂音 ---
	check(rod.Unique_Death_Audio == rod.ROD_AUDIO.BREAK[0],"death uses copper break")
	var storm:Node2D = rod.storm
	rod.health = 0
	rod.Die()
	check(is_instance_valid(storm) and storm._dissipating and storm.get_parent() != rod,"storm dissipates on death and outlives the rod")
	for i:int in range(25):
		await create_timer(0.1).timeout
		if not is_instance_valid(storm): break
	check(not is_instance_valid(storm),"dissipated storm cleans itself up")
	finish(0 if failures == 0 else 1)
