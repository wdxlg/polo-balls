extends SceneTree
const SPEAR_PATH:String = "res://scenes/characters/我的世界/钻石长矛.tscn"
var world:Node
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var done:bool = false
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func setup() -> Vector2:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	return world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
func spawn(point:Vector2) -> Node2D:
	var unit:Node2D = load(SPEAR_PATH).instantiate()
	unit.Team = "Team0"
	unit.direction = Vector2.RIGHT
	unit.position = point
	world.add_child(unit,true)
	return unit
func victim(point:Vector2) -> Node2D:
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate()
	unit.Team = "Team1"
	unit.position = point
	unit.Max_health = 10000
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Has_Collision_Damage = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.state_machine.set_physics_process(false)
	for holder:Node in [unit,unit.self_hurtbox]:
		var shape := CircleShape2D.new()
		shape.radius = 20.0
		holder.get_node("CollisionShape2D").shape = shape
	return unit
func finish(code:int) -> void:
	if done: return
	done = true
	print("DIAMOND_LIVE_RESULT checks=",checks," failures=",failures)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.set_process(false)
	var warmer:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warmer.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/"+role+".tscn"
		var status:int = ResourceLoader.load_threaded_get_status(path)
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(path)
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	quit(code)
func run() -> void:
	var center:Vector2 = await setup()
	create_timer(40.0).timeout.connect(func(): finish(2))
	world._ensure_character_path_index()
	check(world._character_paths_by_folder["我的世界"].has("钻石长矛"),"indexed in real Minecraft selector")
	var a:Node2D = spawn(center+Vector2(-120,-180))
	var ea:Node2D = victim(a.global_position+Vector2(28,0))
	a._momentum = 330.0
	a._attack_wait = 0.0
	a._blink_wait = 10.0
	var b:Node2D = spawn(center+Vector2(-120,0))
	var eb:Node2D = victim(b.global_position+Vector2(0,16))
	# Isolate skill turning from a separate body-collision bounce; hurtbox stays active.
	eb.collision_layer = 0
	# At high travel speed a stationary trigger can legitimately leave the blade
	# arc. A second enemy lies on the actual moving shaft path, not a phantom hit.
	var sweep_path_enemy:Node2D = victim(b.global_position+Vector2(30,16))
	sweep_path_enemy.collision_layer = 0
	b._sweep_wait = 0.0
	b._blink_wait = 10.0
	var c:Node2D = spawn(center+Vector2(-120,180))
	var ec:Node2D = victim(c.global_position+Vector2(110,0))
	c._blink_wait = 0.0
	var flow_samples:int = 0
	var flow_stalls:int = 0
	var windup_samples:int = 0
	var echo_seen:Dictionary = {}
	var echo_birth_frames:Array[int] = []
	for i:int in range(int(ceil((b.sweep_duration+0.04)*Engine.physics_ticks_per_second))):
		await physics_frame
		for value:Variant in a._visual_nodes:
			if is_instance_valid(value) and value.attack_echo and not echo_seen.has(value.get_instance_id()):
				echo_seen[value.get_instance_id()] = true
				echo_birth_frames.append(Engine.get_physics_frames())
		if c._action==c.Action.BLINK_WINDUP:
			windup_samples += 1
			if c.velocity.length()<0.1: flow_stalls += 1
		if c._action==c.Action.BLINK_RECOVER:
			flow_samples += 1
			if c.velocity.length()<0.1: flow_stalls += 1
	check(windup_samples>0 and flow_samples>0 and flow_stalls==0,"live blink windup and landing recovery never force the moving actor to stand")
	var separate_births:bool = echo_birth_frames.size()>=2
	for i:int in range(1,echo_birth_frames.size()): separate_births = separate_births and echo_birth_frames[i]>echo_birth_frames[i-1]
	check(separate_births,"real automatic attack generates echoes on separate physics frames")
	check(a.total_thrusts>0 and ea.health<10000,"real state machine automatically stabs and damages")
	check(a._visual_nodes.size()>0,"automatic high-speed stab emits echoes")
	check(b.total_sweeps>0 and (eb.health<10000 or sweep_path_enemy.health<10000),"side enemy triggers automatic sweep and the moving shaft actually hits")
	check(a._momentum>330.0,"real attack state continues rapid acceleration")
	check(b._momentum>b._base_speed,"real sweep state continues rapid acceleration")
	check(b.direction.x < -0.99 and b.velocity.x < -1.0,"autonomous sweep reverses real movement rather than only its picture")
	var visible_tip_axis:Vector2 = Vector2(-1,-1).normalized().rotated(b.image.global_rotation)
	check(visible_tip_axis.dot(b.velocity.normalized())>0.99,"live native spear points along actual travel after sweep")
	check(c.total_blinks>0 and ec.health<10000,"real state machine automatically blinks and damages path")
	check(c.last_blink_to.x>ec.global_position.x,"live blink ends beyond victim")
	check(not c._floor_regions().is_empty(),"live floor checks use actual painted map")
	var paused_at:Vector2 = a.global_position
	var thrusts:int = a.total_thrusts
	game.now_stop_state = true
	await create_timer(0.2).timeout
	check(a.global_position==paused_at and a.total_thrusts==thrusts,"live pause freezes actor and attacks")
	game.now_stop_state = false
	# Measure travelled distance, not endpoint displacement: ordinary bouncing
	# may return to the starting area without ever stopping or chasing.
	var walk_previous:Vector2 = a.global_position
	var travelled:float = 0.0
	for i:int in range(40):
		await create_timer(0.1).timeout
		travelled += a.global_position.distance_to(walk_previous)
		walk_previous = a.global_position
	check(travelled>100.0,"continues ordinary movement after its first attack")
	print("TRAVEL_METRIC distance=",travelled)
	check(a._visual_nodes.size()<=48 and b._visual_nodes.size()<=48 and c._visual_nodes.size()<=48,"live visual count remains bounded")
	# Independent real-loop probe: a nearby side enemy does not bend the travel path.
	var probe_start:Vector2 = center+Vector2(-260,-330)
	var probe:Node2D = spawn(probe_start)
	probe.Can_Attack = false
	probe.Can_Skill = false
	var side_enemy:Node2D = victim(probe_start+Vector2(0,70))
	await create_timer(0.42).timeout
	check(probe._momentum>probe._base_speed and probe._momentum<probe.max_move_speed*0.7,"live acceleration is now gradual instead of filling in 0.4 seconds")
	await create_timer(0.8).timeout
	check(probe.global_position.x>probe_start.x+180.0,"gentler acceleration still produces continuous travel")
	check(probe._momentum>400.0 and probe._momentum<520.0,"live movement is still building speed around 1.2 seconds rather than already capped")
	check(absf(probe.global_position.y-probe_start.y)<0.1 and probe.direction==Vector2.RIGHT,"real movement remains straight despite nearby side enemy")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(5,90)
	col.shape = shape
	wall.add_child(col)
	world.add_child(wall)
	wall.global_position = probe.global_position+Vector2(60,0)
	await create_timer(0.25).timeout
	check(probe.direction.x<0.0,"real state machine uses ordinary wall bounce")
	var bounced_at:Vector2 = probe.global_position
	await create_timer(0.05).timeout
	check(probe.global_position.x<bounced_at.x,"moves away immediately while sprite finishes turning")
	wall.queue_free()
	side_enemy.queue_free()
	print("LIVE_METRICS thrusts=",a.total_thrusts+b.total_thrusts+c.total_thrusts," sweeps=",a.total_sweeps+b.total_sweeps+c.total_sweeps," blinks=",a.total_blinks+b.total_blinks+c.total_blinks)
	finish(0 if failures==0 else 1)
