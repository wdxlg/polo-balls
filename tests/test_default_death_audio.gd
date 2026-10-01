extends SceneTree
## 每个角色死亡都要有默认死亡铃声（Dead_Audio=DeadBell），与专属死亡音叠加；
## 盔甲架一族只用原版盔甲架破碎声。
const DEADBELL:String = "res://audio/system/dead_bell.wav"
var world:Node
var rect:Rect2
var checks:int = 0
var failures:int = 0

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func players(node:Node,acc:Array) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D: acc.append(node)
	for c in node.get_children(): players(c,acc)

func playing_with(path_part:String) -> Array:
	var acc:Array = []
	players(root,acc)
	return acc.filter(func(p): return is_instance_valid(p) and p.playing and p.stream != null and path_part in str(p.stream.resource_path))

func silence_bells() -> void:
	for p in playing_with(DEADBELL): p.stop()

func frames(n:int) -> void:
	for i in range(n): await process_frame

func spawn(name:String) -> Node:
	var before:Array = world.get_battle_units_fast().duplicate()
	var unit = world.create_char("Team0",name,rect.get_center())
	await create_timer(0.3).timeout
	if unit is Node and is_instance_valid(unit): return unit
	var picked:Node = null
	for u in world.get_battle_units_fast():
		if before.has(u) or not is_instance_valid(u): continue
		if picked == null or (int(u.get("Type")) == 0 and int(picked.get("Type")) != 0): picked = u
	return picked

func clear_units(keep:Array) -> void:
	for u in world.get_battle_units_fast().duplicate():
		if is_instance_valid(u) and not keep.has(u): u.queue_free()
	await create_timer(0.15).timeout

func kill_and_count_bells(unit:Node) -> int:
	silence_bells()
	unit.health = 0
	await frames(4)
	return playing_with(DEADBELL).size()

func run() -> void:
	var game:Node = root.get_node("Game")
	game.Game_Settings["Training_Mode"] = false
	game.Game_Settings["Development_Mode"] = false
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world._mc_prewarmer = null
	world.now_choose_map = "Map30x30" if world.map_group.has("Map30x30") else "Map10x10"
	world.refresh_map_presentation()
	world.control.visible = false
	await create_timer(0.5).timeout
	rect = world.return_map_world_rect(world.map_group[world.now_choose_map])
	# 两个冻结的陪练，保证受害者死后比赛不结束。
	for team in ["Team1","Team2"]:
		world.create_char(team,"小刀猎",rect.position + Vector2(8,8) + (Vector2(16,0) if team == "Team2" else Vector2.ZERO))
		await process_frame
	var keep:Array = world.get_battle_units_fast().duplicate()
	for u in keep:
		if u is Node: u.process_mode = Node.PROCESS_MODE_DISABLED

	# 之前完全无声 / 只有专属音 / Die() 不调 super 的几类，现在都要响一次默认铃声。
	for name in ["NC佬","凑企鹅","史莱姆","末影人","蜘蛛","三废石","苦力怕","雪傀儡","训犬师","锻剑储君","流浪商人","皓宸"]:
		var unit:Node = await spawn(name)
		if unit == null:
			check(false,"%s spawns" % name); continue
		check(str(unit.Dead_Audio) == "DeadBell","%s keeps the default death bell" % name)
		var bells:int = await kill_and_count_bells(unit)
		check(bells >= 1,"%s rings the default death bell on death" % name)
		check(not is_instance_valid(unit) or bool(unit.get("_default_death_audio_played")),"%s marks its death bell as played" % name)
		await clear_units(keep)

	# 唤魔者：图腾挡下的那次不算死亡；第二次真正死亡才响铃。
	var evoker:Node = await spawn("唤魔者")
	var totem_bells:int = await kill_and_count_bells(evoker)
	check(is_instance_valid(evoker) and evoker.health > 0 and totem_bells == 0,"evoker totem save does not ring the death bell")
	await create_timer(0.3).timeout
	check(await kill_and_count_bells(evoker) >= 1,"evoker real death rings the death bell")
	await clear_units(keep)

	# 专属死亡音挂在场景上，角色被释放后不会被掐断；默认铃声叠加。
	var anvil:Node = await spawn("铁砧")
	var anvil_bells:int = await kill_and_count_bells(anvil)
	await frames(3)
	var breaks:Array = playing_with("anvil_break")
	check(anvil_bells >= 1,"anvil layers the default bell on its break sound")
	check(not is_instance_valid(anvil) and breaks.size() >= 1 and breaks[0].get_parent() == world,"anvil break sound keeps playing after the anvil is freed")
	await clear_units(keep)

	# 盔甲架：只有原版盔甲架破碎声，没有默认铃声。
	var stand:Node = await spawn("盔甲架")
	check(str(stand.Dead_Audio) == "","armor stand has no default death bell")
	var stand_bells:int = await kill_and_count_bells(stand)
	var stand_break:Array = playing_with("audio/characters/盔甲架/").filter(func(p): return p.get_parent() == world and str(p.name).begins_with("ArmorStandBreak"))
	check(stand_bells == 0,"armor stand death does not ring the bell")
	check(stand_break.size() == 1,"armor stand death plays the vanilla armor-stand break sound")
	await clear_units(keep)

	# 老死已经播过死亡音：Die() 与 State.Die 兜底都不再重复。
	var old:Node = await spawn("NC佬")
	old.set_meta(&"wild_dog_milk_old_age_death_audio_played",true)
	silence_bells()
	old.Die()
	old.play_default_death_audio_once()
	await frames(2)
	check(playing_with(DEADBELL).is_empty() and (not is_instance_valid(old) or not old.has_meta(&"wild_dog_milk_old_age_death_audio_played")),"old-age death does not ring a second bell")
	# 每条命只响一次。
	var once:Node = await spawn("NC佬")
	silence_bells()
	once.play_default_death_audio_once()
	await frames(1)
	silence_bells()
	once.play_default_death_audio_once()
	once.Die()
	await frames(2)
	check(playing_with(DEADBELL).is_empty(),"default death bell rings once per life")
	await clear_units(keep)

	print("RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

