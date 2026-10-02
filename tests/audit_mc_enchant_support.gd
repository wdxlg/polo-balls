extends SceneTree
## Enchantment support audit (tool, not a pass/fail test). For every character scene it runs
## real World fights against an armor stand and measures which enchantment hooks the
## character's attacks actually reach:
##   A  baseline (inert enchantment so hooks run): melee / ranged / elemental hook events,
##      owned projectile spawns, hooked vs. real HP loss (unhooked damage = adaptation gap)
##   B  Multishot I: clones that really fly
##   C  Efficiency XX: attack events per second compared with A
## Output lines: SUPPORT|<scene>|key=value|...  Use the result to update
## scripts/effects/我的世界/mc_enchant_support.gd (see MCP_CONTEXT enchantment rule).
## user args: -- <out_file> <first_index> <count> [seconds]
const ENCHANTS_PATH:String = "res://scripts/effects/我的世界/mc_enchantments.gd"
const STAND:String = "res://scenes/characters/默认/盔甲架.tscn"
var game:Node
var world:Node
var subject:Node2D
var stand:Node2D
var spawned:Array = [] # owned shots: {"ref", "clone", "start", "max"}
var hp_loss:float = 0.0

func _initialize() -> void: call_deferred("run")

static func characters(dir:String,out:Array[String]) -> void:
	var access:DirAccess = DirAccess.open(dir)
	if access == null: return
	for sub:String in access.get_directories(): characters(dir.path_join(sub),out)
	for file:String in access.get_files():
		if file.ends_with(".tscn"): out.append(dir.path_join(file))

func _on_added(node:Node) -> void:
	if node is Node2D and load("res://classes/combat_classification.gd").is_projectile(node): _classify_spawn.call_deferred(node.get_instance_id())

func _classify_spawn(id:int) -> void:
	if not is_instance_id_valid(id): return
	var node:Node2D = instance_from_id(id) as Node2D
	if node != null and owned(node):
		spawned.append({"ref":weakref(node),"clone":node.has_meta("mc_projectile_clone"),"start":node.global_position,"max":0.0})

func _on_damage(source:Node,target:Node,amount:float,_before:float) -> void:
	if target == stand and is_instance_valid(subject) and (source == subject or load(ENCHANTS_PATH)._caster_of(source) == subject): hp_loss += amount

func owned(node:Node) -> bool:
	if not is_instance_valid(node) or not is_instance_valid(subject): return false
	var owner:Node = load("res://classes/projectile_interactions.gd").owner_of(node)
	return is_instance_valid(owner) and (owner == subject or load(ENCHANTS_PATH)._caster_of(owner) == subject)

func fight(scene:String,levels:Dictionary,seconds:float) -> Dictionary:
	seed(424242)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(8): await process_frame
	if "_mc_prewarmer" in world and is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.queue_free()
	var rect:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	var c:Vector2 = rect.get_center()
	subject = load(scene).instantiate()
	subject.name = "Subject"
	subject.Team = "Team0"
	subject.position = c+Vector2(-130.0,0.0)
	world.add_child(subject,true)
	stand = load(STAND).instantiate()
	stand.name = "Stand"
	stand.Team = "Team1"
	stand.position = c+Vector2(130.0,0.0)
	world.add_child(stand,true)
	await physics_frame
	var enchants:Script = load(ENCHANTS_PATH)
	for id:String in levels: enchants.apply(subject,id,int(levels[id]))
	var sink:Array = []
	enchants.audit_sink = sink
	spawned.clear()
	hp_loss = 0.0
	var t:float = 0.0
	while t < seconds and is_instance_valid(subject) and subject.is_inside_tree():
		await physics_frame
		t += 1.0/60.0
		if is_instance_valid(stand) and stand.health < stand.Max_health*0.5: stand.health = stand.Max_health
		for shot:Dictionary in spawned:
			var node:Node2D = shot.ref.get_ref() as Node2D
			if node != null: shot.max = maxf(float(shot.max),node.global_position.distance_to(shot.start))
	enchants.audit_sink = null
	var result:Dictionary = {"melee":0,"ranged":0,"elemental":0,"hooked":0.0,"fire":0,"explosion":0,"projectile_el":0,"shots":0,"clones":0,"flying_clones":0,"hp_loss":hp_loss}
	var sid:int = subject.get_instance_id() if is_instance_valid(subject) else 0
	for e:Dictionary in sink:
		if int(e.caster) != sid: continue
		var ordinary:bool = str(e.kind).is_empty() or str(e.kind) == "ordinary"
		if e.ranged: result.ranged += 1
		elif ordinary: result.melee += 1
		else: result.elemental += 1
		result.hooked += float(e.damage)
		if str(e.kind) == "fire" or str(e.element) == "fire": result.fire += 1
		if str(e.element) == "explosion": result.explosion += 1
	for shot:Dictionary in spawned:
		result.shots += 1
		if shot.clone:
			result.clones += 1
			if float(shot.max) > 24.0: result.flying_clones += 1
	result["alive"] = is_instance_valid(subject) and subject.is_inside_tree()
	world.queue_free()
	for i:int in range(6): await process_frame
	return result

func run() -> void:
	var args:PackedStringArray = OS.get_cmdline_user_args()
	game = root.get_node("Game")
	game._settings_storage_path = "user://arena_audit_settings_%d.cfg" % OS.get_process_id()
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	node_added.connect(_on_added)
	game.combat_damage_resolved.connect(_on_damage)
	var all:Array[String] = []
	characters("res://scenes/characters",all)
	all.sort()
	var first:int = int(args[1]) if args.size() > 1 else 0
	var count:int = int(args[2]) if args.size() > 2 else all.size()
	var seconds:float = float(args[3]) if args.size() > 3 else 10.0
	var out:FileAccess = FileAccess.open(args[0],FileAccess.WRITE)
	for index:int in range(first,mini(first+count,all.size())):
		var scene:String = all[index]
		var a:Dictionary = await fight(scene,{"luck_of_the_sea":1},seconds)
		var b:Dictionary = await fight(scene,{"luck_of_the_sea":1,"multishot":1},seconds) if int(a.shots) > 0 else {"clones":0,"flying_clones":0,"shots":0}
		var c:Dictionary = await fight(scene,{"luck_of_the_sea":1,"efficiency":20},seconds)
		var events_a:int = int(a.melee)+int(a.ranged)+int(a.elemental)+int(a.shots)
		var events_c:int = int(c.melee)+int(c.ranged)+int(c.elemental)+int(c.shots)
		var line:String = "SUPPORT|%s|melee=%d|ranged=%d|elemental=%d|fire=%d|explosion=%d|shots=%d|hooked=%.0f|hp_loss=%.0f|ms_shots=%d|ms_clones=%d|ms_flying=%d|events=%d|eff_events=%d|alive=%s" % [
			scene,int(a.melee),int(a.ranged),int(a.elemental),int(a.fire),int(a.explosion),int(a.shots),float(a.hooked),float(a.hp_loss),
			int(b.shots),int(b.clones),int(b.flying_clones),events_a,events_c,str(a.alive)]
		print(line)
		out.store_line(line)
		out.flush()
	out.store_line("ALLDONE")
	out.close()
	quit(0)
