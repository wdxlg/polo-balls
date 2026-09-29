extends "res://tests/test_diamond_spear_sfx.gd"
func active_echoes() -> Array[Node2D]:
	var result:Array[Node2D] = []
	for value:Variant in spear._visual_nodes:
		if is_instance_valid(value) and not value.is_queued_for_deletion() and value.attack_echo: result.append(value)
	return result
func clean_volley() -> void:
	spear._cancel_action()
	for value:Variant in spear._visual_nodes:
		if is_instance_valid(value): value.free()
	spear._visual_nodes.clear()
	clear_sounds()
func begin_volley() -> void:
	clean_volley()
	reset(Vector2.ZERO,600.0)
	enemy.global_position = Vector2(21,0)
	spear.Attack()
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("DIAMOND_VOLLEY_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	spear = load("res://scenes/characters/我的世界/钻石长矛.tscn").instantiate()
	spear.Team = "Team0"
	spear.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(spear)
	enemy = victim(Vector2(21,0))
	await physics_frame
	await physics_frame
	begin_volley()
	check(spear.thrust_distance==14.0 and spear.echo_thrust_distance==42.0,"echo stroke is tripled without changing the main spear stroke")
	check(active_echoes().size()==1 and spear._pending_echo_anchors.size()==3,"only one real echo exists immediately after attack")
	check(weapon_sounds("echo").size()==1,"only the first born echo emits a start sound")
	var first:Node2D = active_echoes()[0]
	var old_axis:Vector2 = first.axis
	var anchor:Vector2 = first.global_position
	spear._tick_echo_queue(spear.echo_spawn_interval*0.5)
	check(active_echoes().size()==1,"next echo does not appear before its interval")
	enemy.global_position = Vector2(70,12)
	spear._tick_echo_queue(spear.echo_spawn_interval*0.5)
	check(active_echoes().size()==2,"second echo appears after one interval")
	var second:Node2D = active_echoes()[1]
	check(second.axis.dot((Vector2(21,0)-second.anchor).normalized())>0.999,"later echo keeps the target position captured at attack start")
	check(first.axis==old_axis,"already born echo retains its shot direction instead of homing")
	check(second.stroke_distance==42.0,"moving target cannot lengthen an already committed volley")
	var before:int = enemy.health
	second._physics_process(second.stroke_duration*0.22)
	check(enemy.health==before,"committed echo misses a target that dodges away from its old position")
	spear.global_position = Vector2(90,35)
	check(first.global_position==anchor,"staggered echo remains fixed when the caster moves away")
	enemy.global_position = Vector2(1000,0)
	spear._tick_echo_queue(0.5)
	check(active_echoes().size()==3 and spear._pending_echo_anchors.size()==1,"slow frame spawns only one next echo rather than bursting the whole queue")
	check(is_equal_approx(active_echoes()[2].stroke_distance,42.0),"distant target cannot drag the remaining volley out of its committed path")
	var wait_before:float = spear._echo_spawn_wait
	game.now_stop_state = true
	spear._tick_echo_queue(0.5)
	check(active_echoes().size()==3 and spear._echo_spawn_wait==wait_before,"pause freezes pending births and their interval")
	game.now_stop_state = false
	spear._tick_echo_queue(spear._echo_spawn_wait)
	check(active_echoes().size()==4 and spear._pending_echo_anchors.is_empty(),"remaining echo resumes normally after pause")
	check(weapon_sounds("echo").size()==4,"each sequential birth has exactly one sound")
	begin_volley()
	spear._tick_action(spear.echo_spawn_interval*1.2)
	check(active_echoes().size()==1,"a long first action tick cannot spawn a second echo alongside the first")
	begin_volley()
	spear._cancel_action()
	spear._tick_echo_queue(1.0)
	check(spear._pending_echo_anchors.is_empty() and active_echoes().is_empty(),"action cancellation removes pending births and live attack echoes")
	begin_volley()
	spear.dizziness = true
	spear._tick_echo_queue(1.0)
	check(spear._pending_echo_anchors.is_empty() and weapon_sounds("echo").size()==1,"stun prevents all delayed births")
	spear.dizziness = false
	begin_volley()
	spear.Can_Attack = false
	spear._tick_echo_queue(1.0)
	check(spear._pending_echo_anchors.is_empty() and weapon_sounds("echo").size()==1,"attack disable prevents delayed births")
	spear.Can_Attack = true
	begin_volley()
	enemy.queue_free()
	spear._tick_echo_queue(spear.echo_spawn_interval)
	check(spear._pending_echo_anchors.size()==2 and active_echoes().size()==2,"lost target does not cancel the snapshotted volley or require a freed target reference")
	await process_frame
	enemy = victim(Vector2(50,0))
	clean_volley()
	reset(Vector2.ZERO,600.0)
	await physics_frame
	await physics_frame
	spear._emit_echo(Vector2.ZERO,Vector2.RIGHT,0.44,true,0.32)
	var long_echo:Node2D = active_echoes()[0]
	before = enemy.health
	long_echo._physics_process(0.16)
	check(enemy.health<before,"coarse frame still hits at full extension even when its endpoint has already returned")
	var once:int = enemy.health
	long_echo._physics_process(0.08)
	check(enemy.health==once,"long stroke and return cannot double-hit one victim")
	clean_volley()
	spear._emit_echo(Vector2.ZERO,Vector2.RIGHT,0.44,true,0.32)
	long_echo = active_echoes()[0]
	before = enemy.health
	long_echo._physics_process(0.6)
	check(enemy.health<before and long_echo.is_queued_for_deletion(),"a frame crossing lifetime processes the stroke before cleaning up")
	clean_volley()
	var wall:Node2D = barrier(Vector2(35,0),Vector2(2,100))
	await physics_frame
	await physics_frame
	spear._emit_echo(Vector2.ZERO,Vector2.RIGHT,0.44,true,0.32)
	long_echo = active_echoes()[0]
	before = enemy.health
	long_echo._physics_process(long_echo.stroke_duration*0.22)
	check(enemy.health==before,"extended echo cannot damage a target behind a wall")
	check(long_echo.tip_distance+long_echo.sprite.position.x<34.0,"visible forward extension also stops short of the wall")
	long_echo._physics_process(0.08)
	check(enemy.health==before,"returning stroke does not bypass the wall")
	spear.damage_segment(Vector2(80,0),Vector2(50,0),2.2,1.0,{},0.0,Vector2.ZERO)
	check(enemy.health==before,"fixed-origin line of sight rejects a stale tip already beyond a wall")
	wall.queue_free()
	clean_volley()
	arena.queue_free()
	await process_frame
	game.Game_Settings = saved_settings
	game.now_stop_state = saved_stop
	print("DIAMOND_VOLLEY_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
