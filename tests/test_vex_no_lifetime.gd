extends SceneTree
# 恼鬼没有寿命：只会被打死；唤魔者召唤间隔放慢。末影分身仍保留寿命。
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String,master:Node = null) -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	if master != null:
		unit.Master = master
		unit.Master_name = str(master.get_path())
	current_scene.add_child(unit,true)
	unit.global_position = point
	return unit
func run() -> void:
	var game:Node = root.get_node("Game")
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(25.0).timeout.connect(func(): finish(2))
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.2).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var evoker:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center,"Team0")
	evoker.Speed = 0
	check(evoker.summon_interval >= 12.0,"summon interval is slower (%.1f s)" % evoker.summon_interval)
	check(evoker._summon_wait >= 5.0,"first summon waits longer (%.1f s)" % evoker._summon_wait)
	var vex:Node2D = spawn("res://scenes/creatures/唤魔恼鬼.tscn",center+Vector2(120,0),"Team0",evoker)
	vex.Speed = 0
	check(not vex.has_lifetime() and vex.lifetime <= 0.0,"vex scene has no lifetime")
	var ref:WeakRef = weakref(vex)
	# 模拟长时间战斗帧：远超旧的 7 秒寿命，恼鬼必须还活着。
	for i:int in range(60):
		vex.tick_physics(vex.state_machine.current_state,0.5)
	check(ref.get_ref() != null and vex.health > 0 and not vex._retired,"vex survives 30 simulated seconds without expiring")
	vex.take_damage(1000,true)
	await create_timer(0.15).timeout
	check(ref.get_ref() == null,"vex still dies and is freed when killed")
	var clone:Node2D = spawn("res://scenes/creatures/末影分身.tscn",center+Vector2(-120,0),"Team0",evoker)
	check(clone.has_lifetime(),"enderman clone keeps its natural lifetime")
	var cref:WeakRef = weakref(clone)
	clone._life_left = 0.05
	await create_timer(0.2).timeout
	check(cref.get_ref() == null,"enderman clone still expires naturally")
	finish(0 if failures == 0 else 1)
func finish(code:int) -> void:
	print("VEX_LIFE checks=",checks," failures=",failures)
	quit(code)
