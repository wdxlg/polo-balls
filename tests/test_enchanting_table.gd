extends SceneTree
## 附魔台：书本周期与合书免伤、符文索敌/伤害/回复、每目标罗马数字计数、
## 满 X 授予对该目标生效的随机附魔（友军正、敌人负，可叠加抵消）、手控、声音与碎裂。
const SCENE_PATH:String = "res://scenes/characters/我的世界/附魔台.tscn"
var ENCHANTS:Script
var SUPPORT:Script
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
	target.Speed = 0.0
	target.default_properties["Speed"] = 0.0
	target.Has_Collision_Damage = false
	target.state_machine.set_physics_process(false)
	return target

func runes() -> Array:
	return get_nodes_in_group("MCEnchantingRune").filter(func(n:Node): return is_instance_valid(n) and not n.is_queued_for_deletion())

func sound_events() -> Array:
	return get_nodes_in_group("MCNativeSFX").map(func(n:Node): return str(n.get_meta("mc_sound_event","")))

func frames(n:int) -> void:
	for i:int in range(n): await physics_frame

func wait_until(predicate:Callable,max_frames:int) -> bool:
	for i:int in range(max_frames):
		if predicate.call(): return true
		await physics_frame
	return bool(predicate.call())

func finish(code:int) -> void:
	if done: return
	done = true
	print("ENCHANTING TABLE RESULT: ",checks - failures,"/",checks," passed")
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
	ENCHANTS = load("res://scripts/effects/我的世界/mc_enchantments.gd")
	SUPPORT = load("res://scripts/effects/我的世界/mc_enchant_support.gd")
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

	# --- 场景、登记与合书免伤 ---
	var table:Node2D = spawn(SCENE_PATH,center)
	var enemy:Node2D = dummy(center + Vector2(140,0),"Team1")
	var ally:Node2D = dummy(center + Vector2(-140,0),"Team0")
	await frames(3)
	await process_frame
	check(world.return_all_character_names().has("附魔台"),"附魔台 appears in the Minecraft roster")
	check(table.Max_health == 600 and int(table.Damage) == 4 and is_equal_approx(table.Attack_Cooling,0.12),"600 HP, rune damage 4, rune every 0.12 s")
	check(not table.book_open and table.has_closed_guard() and is_equal_approx(table.Damage_reduction,0.25),"the book starts closed with 25% damage reduction")
	var before:float = float(table.health)
	table.receive_positional_damage(100.0,table.global_position,true,enemy)
	check(is_equal_approx(before - float(table.health),75.0),"closed book takes 75 from a 100 hit")
	check(is_equal_approx(table.closed_time,4.0) and is_equal_approx(table.open_time,6.0),"fixed cycle: closed 4 s, open 6 s")
	check(table.image.scale.x >= 1.1,"the table is drawn at the enlarged size")
	await frames(20)
	var ambient_fx:Node = world.get_node_or_null("MCEnchantRuneParticles")
	check(ambient_fx != null and int(ambient_fx.count(2)) > 0,"glyph particles keep floating up around the table even with the book closed")
	table.phase_left = 0.0
	await wait_until(func(): return table.book_open,10)
	check(table.book_open and not table.has_closed_guard() and is_equal_approx(table.Damage_reduction,0.0),"opening the book removes the damage reduction")
	check(sound_events().has("item.book.page_turn"),"opening plays the native page turn")
	check(table.get_node_or_null("Graphics/Image/附魔书") != null,"the floating book is drawn above the table")

	# --- 符文：从书页边上出来，飞向最近目标；敌人受伤，友军回复 ---
	check(table.nearest_rune_target() != null,"open book finds the nearest enemy or ally")
	table.set("attack_range",0.0)
	check(table.nearest_rune_target() == null,"nothing in range means no rune")
	# 以下只用显式 fire_rune，射程保持为 0 让自动连射不干扰逐发计数。
	var enemy_before:float = float(enemy.health)
	check(table.fire_rune(enemy,enemy.global_position),"a rune fires at the enemy while the book is open")
	var shot:Node = runes()[0] if not runes().is_empty() else null
	var page_rect:Rect2 = table.BOOK_PAGES_RECT
	var on_edge:bool = true
	for i:int in range(40):
		var local:Vector2 = table.get_node("Graphics/Image/附魔书").to_local(table.rune_spawn_point())
		var inner:Rect2 = page_rect.grow(-table.RUNE_EDGE_DEPTH - 0.01)
		if not page_rect.grow(0.01).has_point(local) or (inner.has_point(local) and absf(local.y - page_rect.position.y) > table.RUNE_EDGE_DEPTH + 0.01): on_edge = false
	check(shot != null and on_edge and shot.global_position.distance_to(table.book_world_position()) <= 40.0*0.225,"runes come out from the edges of the open book's pages")
	check(shot != null and float(shot.Speed) <= 140.0 and float(shot.get("turn_rate")) > 0.0 and float(shot.get("turn_rate")) <= 2.0,"runes fly slowly and home only slightly")
	await wait_until(func(): return float(enemy.health) < enemy_before,240)
	check(is_equal_approx(enemy_before - float(enemy.health),4.0),"a rune deals the table's current attack to an enemy")
	var fx:Node = world.get_node_or_null("MCEnchantRuneParticles")
	check(fx != null and int(fx.count(0)) > 0,"a flying rune leaves a trail of vanilla glyph particles")
	check(fx != null and int(fx.count(1)) >= 8,"a landing rune bursts into enchanted-hit sparks")
	check(table.counter_of(enemy) == 1,"the enemy's counter shows I")
	ally.health = 5000
	await frames(20)
	table._shot_left = 0.0
	check(table.fire_rune(ally,ally.global_position),"a rune fires at an ally")
	await wait_until(func(): return int(ally.health) > 5000,240)
	check(int(ally.health) == 5004 and table.counter_of(ally) == 1,"the ally is healed by the same amount and its counter shows I")
	check(load("res://scripts/characters/我的世界/enchanting_table/enchant_counter_overlay.gd").roman(9) == "IX","counters are written in roman numerals")

	# --- 计数到 X：随机生效附魔，友军正、敌人负 ---
	var enemy_pool:Array = SUPPORT.pool_for(enemy)
	var ally_pool:Array = SUPPORT.pool_for(ally)
	check(enemy_pool.has("projectile_protection") and not enemy_pool.has("sharpness") and not enemy_pool.has("power"),"enemy pool: defences against the ranged table, no attack enchantments for a passive dummy")
	check(not ally_pool.has("protection"),"ally pool has no defences when no enemy can deal damage")
	table.counters[enemy.get_instance_id()] = {"ref":weakref(enemy),"count":9}
	table.on_rune_landed(enemy)
	var enemy_levels:Dictionary = ENCHANTS.levels_of(enemy)
	check(table.counter_of(enemy) == 0 and enemy_levels.size() == 1 and int(enemy_levels.values()[0]) == -1 and enemy_pool.has(enemy_levels.keys()[0]),"the tenth enemy hit grants one negative level from its pool")
	await frames(3)
	check(sound_events().has("block.enchantment_table.use"),"granting plays the native enchant sound")
	var kind:String = enemy_levels.keys()[0]
	ENCHANTS.add(enemy,kind,1)
	check(not ENCHANTS.levels_of(enemy).has(kind),"an opposite level cancels it")
	table.counters[ally.get_instance_id()] = {"ref":weakref(ally),"count":9}
	table.on_rune_landed(ally)
	var ally_levels:Dictionary = ENCHANTS.levels_of(ally)
	check(ally_levels.size() == 1 and int(ally_levels.values()[0]) == 1 and ally_pool.has(ally_levels.keys()[0]),"the tenth ally hit grants one positive level from its pool")
	await frames(15)
	var glints:Array = ally.find_children("MCEnchantGlint*","",true,false)
	check(not glints.is_empty() and glints.all(func(g:Node): return ally.graphics.is_ancestor_of(g)),"the enchantment glint covers only the body art, never the health bar, status icon or shadow")
	var overlay:Node = table.overlay()
	check(overlay != null and overlay.z_index == 90 and not overlay.z_as_relative,"counters draw on a world overlay above characters, below health bars")

	# --- 投射物附魔作用于符文 ---
	ENCHANTS.add(table,"multishot",1)
	await frames(2)
	var count_before:int = runes().size()
	table._shot_left = 0.0
	table.fire_rune(enemy,enemy.global_position)
	await frames(3)
	check(runes().size() - count_before == 2,"Multishot I on the table splits each rune in two")
	ENCHANTS.remove(table,"multishot")

	# --- 手控：左键朝鼠标射出 ---
	check(table.player_control_action_ids() == [&"controlled_attack_action"],"manual control binds only the rune shot to the left button")

	# --- 合上恢复免伤；碎裂 ---
	table.phase_left = 0.0
	await wait_until(func(): return not table.book_open,10)
	check(not table.book_open and table.has_closed_guard() and is_equal_approx(table.Damage_reduction,0.25),"closing restores the damage reduction")
	check(sound_events().has("item.book.put"),"closing plays the native book put")
	check(not table.fire_rune(enemy,enemy.global_position),"no runes while the book is closed")
	table.receive_positional_damage(100000.0,table.global_position,true,enemy)
	await frames(3)
	check(sound_events().has("block.stone.break"),"breaking plays the stone break sound")
	finish(0 if failures == 0 else 1)
