extends SceneTree
const SCENE_PATH:String = "res://scenes/characters/我的世界/三废石.tscn"
var STATUS:Script
var world:Node
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var done:bool = false
var heard:Dictionary = {}

func _record_sound(node:Node) -> void:
	if node is AudioStreamPlayer2D and node.has_meta("mc_sound_event"):
		var event:String = str(node.get_meta("mc_sound_event"))
		heard[event] = int(heard.get(event,0)) + 1

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
	target.Speed = 1.0
	target.default_properties["Speed"] = 1.0
	target.Has_Collision_Damage = false
	return target

func stones() -> Array:
	return get_nodes_in_group("MCUselessStone").filter(func(n:Node): return is_instance_valid(n) and not n.is_queued_for_deletion())

func by_kind(kind:int) -> Node2D:
	for unit:Node2D in stones():
		if int(unit.stone_kind) == kind: return unit
	return null

func sound_events() -> Array:
	return get_nodes_in_group("MCNativeSFX").map(func(n:Node): return str(n.get_meta("mc_sound_event","")))

func frames(n:int) -> void:
	for i:int in range(n): await physics_frame

func wait_until(predicate:Callable,max_frames:int) -> bool:
	for i:int in range(max_frames):
		if predicate.call(): return true
		await physics_frame
	return bool(predicate.call())

func ripple_done() -> bool:
	return get_nodes_in_group("MCAndesiteRipple").filter(func(n:Node): return is_instance_valid(n) and not n.arrived).is_empty()

func finish(code:int) -> void:
	if done: return
	done = true
	print("USELESS STONES RESULT: ",checks - failures,"/",checks," passed")
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
	STATUS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
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
	world.child_entered_tree.connect(_record_sound)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()

	# --- 场景、三人组与登记 ---
	var leader:Node2D = spawn(SCENE_PATH,center + Vector2(-90,0))
	leader._haste_wait = 999.0
	var target:Node2D = dummy(center + Vector2(60,0))
	await physics_frame
	await process_frame
	await physics_frame
	var granite:Node2D = by_kind(0)
	var diorite:Node2D = by_kind(1)
	var andesite:Node2D = by_kind(2)
	check(stones().size() == 3 and granite == leader and diorite != null and andesite != null,"placing 三废石 yields granite leader + diorite + andesite")
	if diorite == null or andesite == null:
		finish(1)
		return
	andesite._haste_wait = 999.0
	check(world.return_all_character_names().has("三废石"),"三废石 appears in the Minecraft roster")
	check(stones().all(func(s:Node2D): return s.Max_health == 200 and is_equal_approx(s.Speed,80.0)),"each stone has 200 HP and speed 80")
	check(int(granite.Damage) == 16 and int(diorite.Damage) == 8 and int(andesite.Damage) == 5,"damage granite 16 > diorite 8 > andesite 5")
	check(is_equal_approx(granite.Attack_Cooling,1.5) and is_equal_approx(diorite.Attack_Cooling,1.2) and is_equal_approx(andesite.Attack_Cooling,2.4),"cooldowns granite 1.5 / diorite 1.2 / andesite 2.4 (andesite slowest)")
	var trio_id:int = int(granite.get_meta("mc_stone_trio",-1))
	check(trio_id >= 0 and stones().all(func(s:Node2D): return int(s.get_meta("mc_stone_trio",-2)) == trio_id and s.get_meta("victory_side_key","") == granite.get_meta("victory_side_key","?")),"all three share trio id and victory side key")
	check(not granite.stone_enemy(diorite) and not andesite.stone_enemy(granite) and granite.stone_enemy(target),"stones never target each other, do target enemies")
	check(granite.get_collision_exceptions().has(diorite) and diorite.get_collision_exceptions().has(andesite),"no body collision inside the trio")
	check(diorite.manual_controllable_subentity and andesite.manual_controllable_subentity,"members are individually controllable subentities")
	check(granite.image.texture == granite.BLOCKS[0] and diorite.image.texture == granite.BLOCKS[1] and andesite.image.texture == granite.BLOCKS[2],"each stone shows its vanilla block cube")
	check(granite.Unique_Death_Audio == null and granite.Dead_Audio == "DeadBell" and granite.Hit_Audio == "","generic hit audio replaced by native stone sounds; default death bell kept")
	var mate:Node2D = dummy(center + Vector2(-90,60),"Team0")
	var shard_probe:Node = load("res://scenes/shooter/我的世界/废石碎块.tscn").instantiate()
	shard_probe.Master = granite
	shard_probe.Team = "Team0"
	check(not shard_probe.enemy(mate) and not shard_probe.enemy(diorite) and shard_probe.enemy(target),"shards skip teammates and the trio")
	shard_probe.free()
	mate.queue_free()

	check(int(heard.get("block.stone.place",0)) >= 3,"each stone plays the native place sound when the battle starts (%d)" % int(heard.get("block.stone.place",0)))

	# --- 花岗岩：击退 + 缓慢 I，不叠加、命中重置时间 ---
	var start_shots:int = granite.shots_fired
	var hit_ok:bool = await wait_until(func(): return STATUS.active(target,"slowness"),150)
	check(hit_ok and granite.shots_fired > start_shots,"granite throws a stone that lands and applies Slowness")
	check(STATUS.level_of(target,"slowness") == 1,"granite slowness is level I")
	check(target.get_children().any(func(c:Node): return c.has_method("replace_with_hit")) or target.global_position.x > center.x + 60.5,"granite hit knocks the target back")
	var status:Node = STATUS.current(target,"slowness")
	await create_timer(0.8).timeout
	var before_refresh:float = float(status.remaining) if is_instance_valid(status) else 0.0
	granite._shot_left = 0.0
	var refreshed:bool = await wait_until(func(): return is_instance_valid(status) and float(status.remaining) > before_refresh + 0.3,120)
	check(before_refresh < 2.6 and refreshed and STATUS.level_of(target,"slowness") == 1,"another granite hit resets the slowness time without raising its level")

	check(int(heard.get("entity.snowball.throw",0)) >= 1,"throwing plays the native throw sound")
	check(int(heard.get("block.stone.hit",0)) >= 1,"a landing stone plays the native stone hit sound")
	var hits_before:int = int(heard.get("block.stone.hit",0))
	await create_timer(0.15).timeout
	hits_before = int(heard.get("block.stone.hit",0))
	diorite.receive_positional_damage(3.0,diorite.global_position,true,target)
	await frames(3)
	check(int(heard.get("block.stone.hit",0)) > hits_before,"a hurt stone plays the native stone hit sound")

	# --- 闪长岩：命中无限叠加攻速 ---
	var stacks_ok:bool = await wait_until(func(): return diorite.diorite_stacks >= 2,240)
	check(stacks_ok,"diorite gains an attack-speed stack per hit")
	await physics_frame
	var expected_cd:float = 1.2/(1.0 + 0.1*float(diorite.diorite_stacks))
	check(absf(diorite.Attack_Cooling - expected_cd) < 0.02,"diorite cooldown = 1.2 / (1 + 0.1 x stacks) (got %.3f, want %.3f)" % [diorite.Attack_Cooling,expected_cd])
	diorite.diorite_stacks = 60
	diorite.add_diorite_stack()
	await physics_frame
	check(diorite.Attack_Cooling < 0.2 and diorite.diorite_attack_rate() > 7.0,"diorite stacking has no cap")
	# 落空后中速衰减，命中停止衰减。
	diorite.Can_Attack = false
	diorite.diorite_stacks = 10.0
	diorite.add_diorite_stack()
	var miss_shot:Node2D = load("res://scenes/shooter/我的世界/废石碎块.tscn").instantiate()
	miss_shot.name = "UselessStonesMissProbe"
	miss_shot.Master = diorite
	miss_shot.Team = diorite.Team
	miss_shot.stone_kind = 1
	miss_shot.direction = Vector2.UP
	miss_shot.life = 0.05
	miss_shot.position = diorite.global_position + Vector2(0,-30)
	world.add_child(miss_shot,true)
	await wait_until(func(): return not is_instance_valid(miss_shot),30)
	check(diorite.diorite_decaying,"a shard that touches no enemy starts the diorite decay")
	var decay_from:float = diorite.diorite_stacks
	await create_timer(1.0).timeout
	var lost:float = decay_from - diorite.diorite_stacks
	check(lost > 1.6 and lost < 2.4,"diorite decays about 2 stacks per second (lost %.2f)" % lost)
	await physics_frame
	var decayed_cd:float = 1.2/(1.0 + 0.1*diorite.diorite_stacks)
	check(absf(diorite.Attack_Cooling - decayed_cd) < 0.03,"decayed stacks lengthen the diorite cooldown")
	var at_hit:float = diorite.diorite_stacks
	diorite.on_stone_shard_hit(target,8.0)
	check(not diorite.diorite_decaying and is_equal_approx(diorite.diorite_stacks,at_hit + 1.0),"a hit stops the decay and adds a stack")
	await create_timer(0.5).timeout
	check(is_equal_approx(diorite.diorite_stacks,at_hit + 1.0),"stacks hold steady after the hit")
	diorite.diorite_decay_per_second = 1000.0
	diorite.on_stone_shard_miss()
	await frames(2)
	check(diorite.diorite_stacks == 0.0 and not diorite.diorite_decaying and absf(diorite.Attack_Cooling - 1.2) < 0.01,"decay bottoms out at the base attack speed")
	diorite.diorite_decay_per_second = 2.0
	diorite.Can_Attack = true

	# --- 安山岩：命中治疗血最少的石头，越残血治疗越多，以地面波纹送达 ---
	granite.Can_Attack = false
	diorite.Can_Attack = false
	andesite.Can_Attack = false
	await wait_until(func(): return get_nodes_in_group("MCUselessStoneShard").is_empty(),60)
	await wait_until(func(): return get_nodes_in_group("MCAndesiteRipple").filter(func(r:Node): return is_instance_valid(r) and not r.is_queued_for_deletion()).is_empty(),120)
	granite.health = 100
	diorite.health = 180
	andesite.health = 200
	andesite.heal_lowest_member()
	await physics_frame
	var ripples:Array = get_nodes_in_group("MCAndesiteRipple")
	check(ripples.size() == 1 and ripples[0].target_unit() == granite and ripples[0].kind == 0,"andesite heal ripple heads to the lowest-HP stone")
	check(granite.health == 100,"heal waits for the ripple to arrive")
	check(not ripples.is_empty() and ripples[0].bumps.size() >= 1,"ripple raises stone bumps along the ground")
	await wait_until(ripple_done,180)
	check(granite.health == 120,"heal at 50%% missing = 5 x (1 + 6 x 0.5) = 20 (got %d)" % (granite.health - 100))
	granite.health = 200
	diorite.health = 180
	andesite.heal_lowest_member()
	await wait_until(ripple_done,180)
	check(diorite.health == 188,"heal at 10%% missing = 5 x 1.6 = 8 (got %d)" % (diorite.health - 180))
	var sent:int = andesite.heals_sent
	granite.health = 200
	diorite.health = 200
	andesite.heal_lowest_member()
	check(andesite.heals_sent == sent,"no heal ripple when all stones are full")
	andesite.on_stone_shard_hit(target,5.0)
	check(andesite.heals_sent == sent,"andesite shard hit routes through the same heal rule")

	check(stones().any(func(st:Node2D): return st.footsteps > 0) and int(heard.get("block.stone.step",0)) >= 1,"moving stones play native stone footsteps")

	# --- 投掷后坐：沿投掷反方向按伤害震开，然后弹性恢复 ---
	await create_timer(1.0).timeout
	var aim_point:Vector2 = target.global_position
	var granite_aim:Vector2 = granite.global_position.direction_to(aim_point)
	var andesite_aim:Vector2 = andesite.global_position.direction_to(aim_point)
	var granite_rest:Vector2 = granite._rest_image_position
	granite.Can_Attack = true
	andesite.Can_Attack = true
	var granite_threw:bool = granite.throw_at(aim_point)
	var andesite_threw:bool = andesite.throw_at(aim_point)
	granite.Can_Attack = false
	andesite.Can_Attack = false
	check(granite_threw and andesite_threw,"recoil probe throws succeed")
	var granite_kick:Vector2 = granite.recoil_offset
	var andesite_kick:Vector2 = andesite.recoil_offset
	check(granite_kick.normalized().dot(-granite_aim) > 0.99 and andesite_kick.normalized().dot(-andesite_aim) > 0.99,"throw recoil points opposite the throw direction")
	check(is_equal_approx(granite_kick.length(),granite.recoil_distance(16.0)) and is_equal_approx(andesite_kick.length(),andesite.recoil_distance(5.0)),"recoil distance follows the thrown damage")
	check(granite_kick.length() > andesite_kick.length()*1.8,"granite (16 damage) recoils much farther than andesite (5 damage): %.2f vs %.2f" % [granite_kick.length(),andesite_kick.length()])
	await process_frame
	await process_frame
	var shown:Vector2 = granite.image.get_parent().global_transform.basis_xform(granite.image.position - granite_rest)
	check(shown.length() > 0.5 and shown.normalized().dot(-granite_aim) > 0.95 and shown.is_equal_approx(granite.recoil_offset),"the stone image is visibly displaced backwards on screen (%.2f px)" % shown.length())
	var overshoot:float = 0.0
	var elapsed:float = 0.0
	while elapsed < 1.0:
		await process_frame
		elapsed += get_root().get_process_delta_time()
		overshoot = maxf(overshoot,granite.recoil_offset.dot(granite_aim))
	check(overshoot > 0.3,"recovery is elastic: the image springs past rest toward the throw (%.2f px)" % overshoot)
	check(granite.recoil_offset == Vector2.ZERO and andesite.recoil_offset == Vector2.ZERO and granite.image.position.is_equal_approx(granite_rest),"recoil settles back to the exact rest position")
	var body_before:Vector2 = granite.global_position
	for i:int in range(10): granite.kick_recoil(Vector2.RIGHT,16.0)
	check(granite.recoil_offset.length() <= granite.recoil_max*granite._unit_scale() + 0.001 and granite.recoil_offset.length() > granite.recoil_distance(16.0)*1.2,"rapid throws stack recoil up to the cap")
	check(granite.global_position == body_before and granite.recoil_offset.x < 0.0,"recoil moves only the image, never the body")
	await create_timer(1.0).timeout
	await frames(1)

	# --- 安山岩：周期急迫 III，三块都有，同样走波纹 ---
	andesite._haste_wait = 0.0
	await physics_frame
	check(get_nodes_in_group("MCAndesiteRipple").filter(func(r:Node): return r.kind == 1).size() == 3,"haste sends one ripple to each living stone")
	check(andesite._haste_wait > andesite.andesite_haste_interval - 0.05 and andesite._haste_wait <= andesite.andesite_haste_interval,"next haste scheduled after the interval")
	await wait_until(ripple_done,180)
	check(stones().all(func(s:Node2D): return STATUS.level_of(s,"haste") == 3),"all three stones gain Haste III")
	check(is_equal_approx(andesite.andesite_haste_first,6.0) and is_equal_approx(andesite.andesite_haste_duration,5.0),"haste first at 6 s, lasts 5 s")

	# --- 三块共存：领头碎了另外两块继续，碎裂声与碎屑 ---
	granite.receive_positional_damage(10000.0,granite.global_position,true,target)
	await frames(3)
	await process_frame
	check(not is_instance_valid(granite) or granite.health <= 0,"granite can break")
	check(is_instance_valid(diorite) and diorite.health > 0 and is_instance_valid(andesite) and andesite.health > 0,"other stones survive the leader")
	check(sound_events().has("block.stone.break"),"breaking plays the native stone break sound")
	check(get_nodes_in_group("MCBlockFragments").size() >= 1,"breaking shatters into block pixels")
	andesite.heal_lowest_member()
	diorite.health = 50
	andesite.heal_lowest_member()
	await physics_frame
	check(get_nodes_in_group("MCAndesiteRipple").all(func(r:Node): return r.target_unit() == null or r.target_unit() == diorite or r.target_unit() == andesite),"dead stones are never healed")
	finish(0 if failures == 0 else 1)
