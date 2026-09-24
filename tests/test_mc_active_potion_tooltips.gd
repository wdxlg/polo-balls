extends "res://scripts/training/test_mc_new5.gd"

## Real world + real buffs/status nodes; no fake countdown in the test fixture.
const LIVE_NAME:String = "Minecraft药水状态框"


func _live(unit:Node2D) -> MCPreviewTooltip:
	return unit.get_node_or_null(LIVE_NAME) as MCPreviewTooltip


func _kinds(unit:Node2D) -> PackedStringArray:
	var tooltip:MCPreviewTooltip = _live(unit)
	return tooltip.get("_shown_keys") as PackedStringArray if tooltip != null else PackedStringArray()


func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.set_language("zh",false)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4,true,false,true).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	# Loading gameplay scripts during run allows the Game autoload to register
	# before dependent character scripts compile in a --script test runner.
	var beacon_script:GDScript = load("res://scripts/characters/我的世界/wither/beacon.gd") as GDScript
	var witch_effects:GDScript = load("res://scripts/effects/我的世界/女巫药水效果.gd") as GDScript
	var effects:GDScript = load("res://scripts/effects/我的世界/mc_status_effects.gd") as GDScript
	var levitation_script:GDScript = load("res://scripts/effects/我的世界/潜影浮空.gd") as GDScript
	var primaries:Array = beacon_script.get_script_constant_map().get("BUFFS",[])
	check(primaries == ["speed","haste","resistance","jump_boost","strength"],"beacon has all five level-I primary effects, not secondary regeneration")
	var wither:Node2D = spawn("凋灵",Vector2(-120,-40))
	var witch:Node2D = spawn("女巫",Vector2(-150,80))
	var victim:Node2D = spawn("",Vector2(70,10),"Team1")
	# Freeze only the actors' AI/status physics for precise timer assertions;
	# CanvasLayers explicitly process while their owner is not ticking.
	for unit:Node2D in [wither,witch,victim]:
		unit.process_mode = Node.PROCESS_MODE_DISABLED
	victim.Max_health = 10000.0
	victim.health = 10000.0
	var tooltip:MCPreviewTooltip
	for kind:String in primaries:
		wither.apply_beacon_buff(kind)
		tooltip = _live(wither)
		check(tooltip != null,"beacon buff creates a REAL on-Wither tooltip: " + kind)
		if tooltip == null:
			continue
		check(_kinds(wither) == PackedStringArray([kind]) and tooltip._potions[0].level == 1 and tooltip._time_labels[0].text == "00:06","beacon " + kind + " is level I with six seconds")
		check(tooltip._potions[0].icon != null and tooltip._potions[0].icon.resource_path.ends_with("/" + kind + ".png"),"beacon " + kind + " uses Mojang's icon")
	check(_live(victim) == null,"beacon's primary effect does not falsely attach to its target")
	var ui:MCPreviewTooltip = _live(wither)
	var primary:Node = wither.get_node("MinecraftStatus_strength")
	primary.remaining = 2.2
	ui.call("refresh_display")
	var version:int = ui.content_version
	check(ui._time_labels[0].text == "00:03" and _kinds(wither) == PackedStringArray(["strength"]),"visible countdown comes directly from shared Strength status")
	primary.remaining = 1.2
	ui.call("refresh_display")
	check(ui.content_version == version and ui._time_labels[0].text == "00:02","time-only changes don't recreate rows or restart the clock")
	game.set_language("en",false)
	check(ui._potion_names[0].text == "Strength" and ui._time_labels[0].text == "00:02","live buff switches to English without resetting duration")
	game.set_language("zh",false)
	effects.call("clear",wither,"strength",wither)
	wither._buff_left = 0.0
	wither._buff = ""
	ui.call("refresh_display")
	check(_kinds(wither).is_empty() and not ui.visible,"expired beacon status removes its frame")
	wither.apply_beacon_buff("jump_boost")
	check(_kinds(wither).has("jump_boost") and ui.visible,"a later beam wakes the existing hidden frame")
	# The same appearance packet now carries both kind and remaining time to a
	# remote Wither (the other status nodes have no multiplayer replication yet).
	wither._sync_appearance(wither.summon_time,true,false,"speed",2.4,Vector2.ZERO,Vector2.UP)
	check(_kinds(wither) == PackedStringArray(["speed"]) and ui._time_labels[0].text == "00:03","replica Wither packet carries a real bounded beacon timer")
	wither._sync_appearance(wither.summon_time,true,false,"",0.0,Vector2.ZERO,Vector2.UP)
	check(not ui.visible,"replica Wither clears its beacon row when authority sends expiration")
	# Heads, roses and Witch bottles share one Wither status. The Witch bottle
	# additionally installs canonical Weakness with its own timer and Buff.
	wither.apply_wither(victim)
	var wither_status:Node = victim.get_node_or_null("WitherStatus")
	check(wither_status != null and _kinds(victim).has("wither"),"Wither hits show Wither on the victim, not on the source")
	if wither_status != null:
		wither_status.remaining = 1.4
		_live(victim).call("refresh_display")
		check(_live(victim)._time_labels[0].text == "00:02","Wither hit countdown follows the real three-second status")
		wither.apply_wither(victim)
		check(is_equal_approx(float(wither_status.remaining),3.0),"second skull/rose hit refreshes one real Wither status")
	for kind:String in ["regen","poison","wither","invisibility","speed","strength","slowness"]:
		witch_effects.call("apply_effect",victim,kind,witch)
	ui = _live(victim)
	check(ui != null,"Witch's sustained potions attach to affected character")
	if ui == null:
		await finish(2)
		return
	var keys:PackedStringArray = _kinds(victim)
	for kind:String in ["regen","poison","wither","invisibility","speed","strength","slowness","weakness"]:
		check(keys.has(kind),"Witch sustained " + kind + " is visible from real status/Buff")
	for kind:String in ["regen","poison"]:
		var index:int = keys.find(kind)
		check(index >= 0 and ui._time_labels[index].text == "∞" and is_inf(float(victim.get_node("MinecraftStatus_"+kind).remaining)),kind + " remains indefinitely and displays infinity")
	var weakness:Node = victim.get_node_or_null("MinecraftStatus_weakness")
	var weakness_buffs:Dictionary = victim.Buff_Dic.get(weakness.get_instance_id(),{}) if weakness != null else {}
	var weak:Buff = weakness_buffs.get("MC效果_weakness_damage") as Buff
	check(weakness != null and weak != null and weak.duration > 0.0 and keys.has("weakness"),"Witch's Weakness row is backed by the real canonical status and -4 melee Buff")
	var speed_status:Node = victim.get_node("MinecraftStatus_speed")
	speed_status.remaining = 4.4
	ui.call("refresh_display")
	var speed_index:int = _kinds(victim).find("speed")
	version = ui.content_version
	check(ui._time_labels[speed_index].text == "00:05","finite Witch status rounds real remaining seconds up")
	ui.call("_process",2.0)
	check(ui._time_labels[speed_index].text == "00:05" and ui.content_version == version,"display never invents its own independent countdown")
	game.set_language("en",false)
	check(ui._potion_names[speed_index].text == "Speed" and ui._time_labels[speed_index].text == "00:05" and ui._potion_names[keys.find("poison")].text == "Poison","all sustained effects translate without changing time or infinity")
	game.set_language("zh",false)
	speed_status.remaining = 0.0
	speed_status.queue_free()
	ui.call("refresh_display")
	check(not _kinds(victim).has("speed") and _kinds(victim).has("poison"),"only expired status is removed; permanent effects remain")
	var before_keys:PackedStringArray = _kinds(victim)
	for kind:String in ["instant_heal","instant_damage"]:
		witch_effects.call("apply_effect",victim,kind,witch)
	check(_kinds(victim) == before_keys and not _kinds(victim).has("instant_damage"),"instant potions never create fictitious countdown rows")
	var immune:Node2D = spawn("",Vector2(120,95),"Team1")
	immune.process_mode = Node.PROCESS_MODE_DISABLED
	immune.minecraft_potion_negative_effect_ratio = 0.0
	witch_effects.call("apply_effect",immune,"poison",witch)
	check(_live(immune) == null and immune.get_node_or_null("MinecraftStatus_poison") == null,"potion immunity creates neither status nor tooltip")
	# Levitation comes from the Shulker bullet's existing effect and disappears
	# as soon as its effect ends or the ceiling interrupts it.
	immune.minecraft_potion_negative_effect_ratio = 1.0
	levitation_script.call("apply",immune,witch,3.0)
	ui = _live(immune)
	check(ui != null and _kinds(immune).has("levitation") and ui._potion_names[0].text == "飘浮" and ui._time_labels[0].text == "00:03","Shulker levitation uses the vanilla Chinese name and actual three-second effect")
	if immune.has_meta(&"mc_shulker_levitation"):
		var ref:WeakRef = immune.get_meta(&"mc_shulker_levitation") as WeakRef
		var effect:Node = ref.get_ref() as Node
		if effect != null:
			effect.call("finish")
			ui.call("refresh_display")
			check(not ui.visible and _kinds(immune).is_empty(),"ending levitation also removes its status row")
	print("MC_ACTIVE_POTIONS_RESULT checks=",checks," failures=",failures)
	await finish(1 if failures > 0 else 0)
