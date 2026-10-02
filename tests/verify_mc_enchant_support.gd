extends SceneTree
## 附魔适配登记与公共钩子：每个角色场景都能解析出附魔能力（审计登记或分类目录回退），
## 登记表只引用存在的场景与合法标志，附魔池只含真实效果；生命直伤 direct_health_loss、
## 原始生命伤害分支和带载体的直接元素命中都吃攻击方附魔，不带载体的元素跳伤不吃。
const SUPPORT_PATH:String = "res://scripts/effects/我的世界/mc_enchant_support.gd"
const FLAGS:Array[String] = ["melee","ranged","fire","explosion","multishot","efficiency","passive"]
var SUPPORT:Script
var ENCHANTS:Script
var CATALOG:Script
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

func scenes_under(dir_path:String) -> Array[String]:
	var result:Array[String] = []
	var dir:DirAccess = DirAccess.open(dir_path)
	if dir == null: return result
	for sub:String in dir.get_directories(): result.append_array(scenes_under(dir_path.path_join(sub)))
	for file:String in dir.get_files():
		if file.ends_with(".tscn"): result.append(dir_path.path_join(file))
	return result

func fighter(point:Vector2,team:String) -> Node2D:
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate() as Node2D
	unit.Team = team
	unit.Health_Restore = 0
	unit.position = point
	world.add_child(unit,true)
	unit.state_machine.set_physics_process(false)
	unit.Has_Collision_Damage = false
	unit.self_hitbox.monitoring = false
	unit.Max_health = 10000
	unit.default_properties.Max_health = 10000
	unit.health = 10000
	unit.block = 0
	unit.max_block = 0
	unit.Damage_reduction = 0.0
	unit.default_properties.Damage_reduction = 0.0
	return unit

func finish(code:int) -> void:
	if done: return
	done = true
	print("MC ENCHANT SUPPORT RESULT: ",checks - failures,"/",checks," passed")
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world):
		for node:Node in world.find_children("*","Node",true,false):
			if node.get_script() != null and node.get_script().resource_path.ends_with("mc_native_prewarm.gd"):
				node.set_process(false)
	var warm:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warm.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/"+role+".tscn"
		var state:int = ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS or state == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	SUPPORT = load(SUPPORT_PATH)
	ENCHANTS = load("res://scripts/effects/我的世界/mc_enchantments.gd")
	CATALOG = load("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")
	var classification:Script = load("res://classes/combat_classification_catalog.gd")
	create_timer(60.0).timeout.connect(func(): finish(2))

	# --- 登记表 ---
	var bad_scene:Array = []
	var bad_flag:Array = []
	for scene:String in SUPPORT.SUPPORT:
		if not ResourceLoader.exists(scene): bad_scene.append(scene)
		for flag:Variant in SUPPORT.SUPPORT[scene]:
			if not FLAGS.has(str(flag)): bad_flag.append(scene+":"+str(flag))
	for scene:String in SUPPORT.QUICK_CHARGE:
		if not ResourceLoader.exists(scene): bad_scene.append(scene)
	check(bad_scene.is_empty(),"every SUPPORT / QUICK_CHARGE scene exists %s" % [bad_scene])
	check(bad_flag.is_empty(),"every capability flag is known %s" % [bad_flag])
	var bad_pool:Array = SUPPORT.COMBAT_POOL.filter(func(id:String): return not CATALOG.has_id(id))
	check(bad_pool.is_empty(),"the combat pool only names catalog enchantments")
	var uncovered:Array = []
	for scene:String in scenes_under("res://scenes/characters"):
		if not SUPPORT.SUPPORT.has(scene) and not classification.SCENES.has(scene): uncovered.append(scene)
	check(uncovered.is_empty(),"every character scene has audited enchant support or a classification fallback %s" % [uncovered])
	for scene:String in SUPPORT.QUICK_CHARGE:
		var root_script:Variant = (classification.SCENES.get(scene,{}) as Dictionary).get("root_script","")
		check(not str(root_script).is_empty(),"quick-charge scene is classified: "+scene)

	# --- 公共钩子 ---
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var attacker:Node2D = fighter(center+Vector2(-150,0),"Team0")
	var target:Node2D = fighter(center+Vector2(150,0),"Team1")
	await physics_frame
	await process_frame
	ENCHANTS.add(attacker,"sharpness",5)
	await process_frame
	check(ENCHANTS.direct_health_loss(attacker,target,100.0) == 150,"direct_health_loss keeps the attacker's Sharpness")
	ENCHANTS.add(target,"protection",4)
	check(ENCHANTS.direct_health_loss(attacker,target,100.0) < 150,"direct_health_loss also applies the target's defences")
	ENCHANTS.remove(target,"protection")
	var before:float = float(target.health)
	target.receive_spatial_raw_health_damage(100.0,{"shape":"all","source":attacker})
	check(is_equal_approx(before-float(target.health),150.0),"raw health damage with a source keeps the attacker's offense")
	before = float(target.health)
	target.receive_spatial_raw_health_damage(100.0,{"shape":"all","carrier":"status_tick","damage_kind":"poison"})
	check(is_equal_approx(before-float(target.health),100.0),"sourceless status ticks are never boosted")
	before = float(target.health)
	target.receive_fire_spatial_damage(100.0,{"point":target.global_position,"source":attacker,"carrier":"body_contact"},false)
	var tagged:float = before-float(target.health)
	before = float(target.health)
	target.receive_fire_spatial_damage(100.0,{"point":target.global_position,"source":attacker},false)
	var tick:float = before-float(target.health)
	check(tagged > tick + 1.0,"a carrier-tagged direct fire hit (body contact) takes melee enchantments; an untagged fire tick does not (%.1f vs %.1f)" % [tagged,tick])

	# --- 附魔池：只含真实效果 ---
	var pool:Array = SUPPORT.pool_for(target)
	check(pool.all(func(id:String): return SUPPORT.COMBAT_POOL.has(id)),"pool_for only returns combat-pool enchantments")
	check(not pool.has("sharpness") and not pool.has("power") and not pool.has("quick_charge"),"a passive unit gets no attack or charge enchantments")
	check(not pool.has("depth_strider") and not pool.has("respiration"),"water-only enchantments are never offered")
	finish(0 if failures == 0 else 1)
