extends SceneTree
## 开场镜头：开战时视角先推近双方，再先快后慢拉远回正常视角；轮换下一场在门后就停在近景，开门后只拉远不再推近。
var world:Node
var game:Node
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("BATTLE_INTRO_CAMERA FAIL: "+label)
func wait_until(cond:Callable,ms:int) -> void:
	var deadline:int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline and not cond.call(): await process_frame
func shot(name:String) -> void:
	root.get_texture().get_image().save_png(OS.get_environment("TEMP") + "/" + name)
## 记录从开战起每帧的 (秒, 镜头缩放, 权重)，直到镜头动画结束。
func sample_intro(with_shots:bool) -> Array:
	var samples:Array = []
	var t:float = 0.0
	var shots:Array = [0.13,0.5,1.2] if with_shots else []
	for i:int in range(400):
		await process_frame
		t = float(world._intro_camera_age)
		samples.append([t,world.camera_2d.zoom.x,float(world._intro_camera_weight)])
		if not shots.is_empty() and t >= float(shots[0]):
			shot("intro_cam_%d.png" % int(float(shots.pop_front()) * 100))
		if int(world._intro_camera_state) == 0 and shots.is_empty(): break
	for i:int in range(5): await process_frame
	samples.append([99.0,world.camera_2d.zoom.x,float(world._intro_camera_weight)])
	return samples
func zoom_at(samples:Array,t:float) -> float:
	for s:Array in samples:
		if float(s[0]) >= t: return float(s[1])
	return float(samples[-1][1])
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): print("BATTLE_INTRO_CAMERA TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	game.now_stop_state = false
	world.reset()
	await process_frame
	var gs:Dictionary = game.Game_Settings
	gs.Training_Mode_Type = "rotation"; gs.Rotation_Match_Type = "duel"; gs.Training_Wheel_Battle = false
	gs.Rotation_Multi_Characters = true; gs.Rotation_Blue_Count = 1; gs.Rotation_Red_Count = 1
	world.control.team.show()
	world._battle_setup_next_id = 1
	var waves:Array = [[["left","苦力怕"],["right","烈焰人"]],[["left","骷髅"],["right","苦力怕"]]]
	for r:int in range(waves.size()):
		for pair:Array in waves[r]: world._enqueue_rotation_character("",str(pair[1]),world._rotation_spawn_position(str(pair[0])),str(pair[0]),"",r + 1)
	world.control.hide(); world.control.team.hide()
	world._update_special_training_modes(0.0)
	for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_until(func() -> bool: return bool(world._battle_start_bell_played),3000)
	check(int(world._intro_camera_state) == 2 and float(world._intro_camera_age) < 0.12,"the start bell begins the intro camera")
	var a:Array = await sample_intro(true)
	var peak:float = a.map(func(s:Array) -> float: return float(s[1])).max()
	var final_zoom:float = float(a[-1][1])
	for i:int in range(30): await process_frame
	var normal_zoom:float = world.camera_2d.zoom.x
	print("INFO normal=%.3f peak=%.3f final=%.3f mult=%.2f" % [normal_zoom,peak,final_zoom,float(world._intro_camera_peak)])
	check(peak > final_zoom * 1.25,"the view starts noticeably closer (peak %.2f vs %.2f)" % [peak,final_zoom])
	check(zoom_at(a,0.02) < peak * 0.97 and zoom_at(a,0.13) >= peak * 0.97,"a visible start punches in quickly instead of hard-cutting")
	var early:float = zoom_at(a,0.15) - zoom_at(a,0.45)
	var late:float = zoom_at(a,0.95) - zoom_at(a,1.25)
	check(early > 0.0 and early > late * 3.0,"the pull-out is fast first and slow at the end (%.3f vs %.3f)" % [early,late])
	var monotonic:bool = true
	for i:int in range(1,a.size() - 1):
		if float(a[i][0]) > 0.14 and float(a[i][1]) > float(a[i - 1][1]) + 0.0001: monotonic = false
	check(monotonic,"the pull-out never bounces back in")
	check(absf(final_zoom - normal_zoom) < normal_zoom * 0.02 and int(world._intro_camera_state) == 0 and is_zero_approx(float(world._intro_camera_weight)),"it settles exactly on the normal battle view (%.3f vs settled %.3f)" % [final_zoom,normal_zoom])
	# 下一场：门关着时就停在近景。
	var loser:Node = world._find_character_by_setup_id_any(int(world._rotation_active_setup.right))
	loser.health = 0
	loser.queue_free()
	await wait_until(func() -> bool:
		var d:Node = root.get_node_or_null("DarkOakDoorTransition")
		return d != null and d.phase == d.Phase.COVERED and int(world._intro_camera_state) == 1,8000)
	check(int(world._intro_camera_state) == 1 and is_equal_approx(float(world._intro_camera_weight),1.0),"behind the closed doors the camera already waits at the close-up")
	await wait_until(func() -> bool: return int(world._intro_camera_state) == 2,8000)
	check(int(world._intro_camera_state) == 2 and float(world._intro_camera_age) >= world.INTRO_CAMERA_PUNCH_SECONDS,"after the doors open it only pulls out (no punch-in through the door gap)")
	for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
	var b:Array = await sample_intro(false)
	check(int(world._intro_camera_state) == 0 and float(b[0][2]) > 0.8,"the second round pull-out also completes")
	world.reset()
	await process_frame
	check(int(world._intro_camera_state) == 0 and is_zero_approx(float(world._intro_camera_weight)),"reset clears the intro camera")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	var leftover_door:Node = root.get_node_or_null("DarkOakDoorTransition")
	if leftover_door != null: leftover_door.queue_free()
	print("BATTLE_INTRO_CAMERA_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

