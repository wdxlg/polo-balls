extends SceneTree
# 基准：50x50 地图 + 100 个小刀猎（两队各 50）。
# 输出每帧耗时统计，以及物理/节点/孤儿等计数。用法：
#   godot --headless --path . --script res://tests/bench_knife100.gd --quit-after 3000
const CHARACTER := "小刀猎"
const COUNT := 100
const WARM_FRAMES := 60
const MEASURE_FRAMES := 400

func _initialize() -> void: call_deferred("run")

var opt_max_steps:int = -1
var opt_blood:int = -1
var opt_after_image:int = -1
func _parse_args() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--steps="): opt_max_steps = int(arg.trim_prefix("--steps="))
		if arg.begins_with("--blood="): opt_blood = int(arg.trim_prefix("--blood="))

func run() -> void:
	_parse_args()
	var game:Node = root.get_node("Game")
	if opt_blood >= 0: game.Game_Settings["Blood_Effects"] = opt_blood == 1
	if opt_max_steps > 0:
		Engine.max_physics_steps_per_frame = opt_max_steps
		game._normal_max_physics_steps_per_frame = opt_max_steps
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	change_scene_to_file("res://scenes/world.tscn")
	await scene_changed
	var world:Node = current_scene
	if world.has_method("choose_map"): world.call("choose_map","Map50x50")
	else: world.now_choose_map = "Map50x50"
	await process_frame
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	print("MAP_RECT ",rect)
	var t0:int = Time.get_ticks_usec()
	var i:int = 0
	for team:String in ["Team0","Team1"]:
		for k in COUNT/2:
			var fx:float = 0.15 + 0.7*float(k%10)/9.0
			var fy:float = (0.15 if team=="Team0" else 0.85) + (0.0 if team=="Team0" else -0.0) + (float(k/10)*0.04 * (1 if team=="Team0" else -1))
			world.create_char(team,CHARACTER,rect.position + Vector2(rect.size.x*fx, rect.size.y*fy))
			i += 1
	print("SPAWN_MS=",(Time.get_ticks_usec()-t0)/1000.0," balls=",get_nodes_in_group("Ball").size())
	for f in WARM_FRAMES: await process_frame
	var frames:Array[float] = []
	var phys_ms:Array[float] = []
	var proc_ms:Array[float] = []
	var pf0:int = Engine.get_physics_frames()
	var last:int = Time.get_ticks_usec()
	for f in MEASURE_FRAMES:
		await process_frame
		var now:int = Time.get_ticks_usec()
		frames.append((now-last)/1000.0); last = now
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	var pf_per_frame:float = float(Engine.get_physics_frames()-pf0)/float(MEASURE_FRAMES)
	phys_ms.sort(); proc_ms.sort()
	print("PHYS steps/frame=%.2f  physics_ms p50=%.2f p90=%.2f  process_ms p50=%.2f p90=%.2f  max_steps=%d blood=%s" % [pf_per_frame, phys_ms[phys_ms.size()/2], phys_ms[int(phys_ms.size()*0.9)], proc_ms[proc_ms.size()/2], proc_ms[int(proc_ms.size()*0.9)], Engine.max_physics_steps_per_frame, str(game.Game_Settings.get("Blood_Effects"))])
	frames.sort()
	var sum:float = 0.0
	for v in frames: sum += v
	print("FRAME_MS avg=%.2f p50=%.2f p90=%.2f p99=%.2f max=%.2f" % [sum/frames.size(), frames[frames.size()/2], frames[int(frames.size()*0.9)], frames[int(frames.size()*0.99)], frames[-1]])
	print("MON process=%.2fms physics=%.2fms nav=%.2fms" % [Performance.get_monitor(Performance.TIME_PROCESS)*1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0, Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)*1000.0])
	print("MON nodes=%d orphans=%d objects=%d draw_calls=%d phys_active=%d phys_pairs=%d islands=%d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)])
	print("ALIVE balls=",get_nodes_in_group("Ball").size()," world_children=",world.get_child_count())
	# 按类型统计 World 下的子节点，看什么在膨胀
	var by_type:Dictionary = {}
	for c in world.get_children():
		var key:String = c.get_class()
		if c.get_script(): key = c.get_script().resource_path.get_file()
		by_type[key] = by_type.get(key,0)+1
	print("WORLD_CHILDREN ",by_type)
	quit()
