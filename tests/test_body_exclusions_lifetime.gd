extends "res://tests/test_character_motion.gd"
const PAIRS = preload("res://classes/body_collision_exclusions.gd")
func run() -> void:
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game._settings_storage_path=OS.get_environment("TEMP").path_join("body_exclusion_settings.json")
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Ball_Can_Move=true;game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(60,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.5).timeout
	world.set_physics_process(false);center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var a:Node2D=spawn("木矛",Vector2.ZERO)
	a.get_body_motion().set_physics_process(false)
	for i:int in range(10):
		var victim:Node2D=spawn("僵尸",Vector2(24,0),"Team1")
		victim.get_body_motion().set_physics_process(false)
		a._cleanup_pass(false)
		a._start_pass_through(victim)
		check(PAIRS.are_excluded(a,victim) and a.get_collision_exceptions().has(victim),"real spear pass registers its native pair")
		if i==0:
			victim.global_position=a.global_position
			await physics_frame
			var before:Vector2=a.global_position
			victim.get_body_motion().separate_overlaps()
			a.get_body_motion().separate_overlaps()
			check(PAIRS.are_excluded(victim,a) and a.global_position==before and victim.global_position==before,"one-sided spear pass is honored by both overlap solvers")
		victim.queue_free()
		await process_frame;await physics_frame
		check(a.get_collision_exceptions().is_empty() and not a.has_meta(PAIRS.NATIVE_META),"dying pass target leaves no freed RID or registry entry")
		a._cleanup_pass(false)
	var b:Node2D=spawn("",Vector2(24,0),"Team1")
	b.get_body_motion().set_physics_process(false)
	var one:=Node.new();world.add_child(one)
	var two:=Node.new();world.add_child(two)
	PAIRS.add_exception(a,b)
	PAIRS.acquire(a,b,one);PAIRS.acquire(a,b,two)
	PAIRS.remove_exception(a,b)
	check(a.get_collision_exceptions().has(b) and b.get_collision_exceptions().has(a),"external removal cannot erase active leases")
	PAIRS.release(a,b,one)
	check(PAIRS.are_excluded(a,b),"one holder cannot erase another")
	two.queue_free();await process_frame
	check(not PAIRS.are_excluded(a,b) and a.get_collision_exceptions().is_empty() and b.get_collision_exceptions().is_empty(),"last holder exit restores both directions")
	PAIRS.acquire(a,b,one);PAIRS.add_exception(a,b);PAIRS.release(a,b,one)
	check(a.get_collision_exceptions().has(b) and b.get_collision_exceptions().is_empty(),"external exception added during a lease retains its direction and ownership")
	# Plain bodies isolate tree lifetime from MultiplayerSpawner's one-shot ready contract.
	PAIRS.remove_exception(a,b)
	var source:=CharacterBody2D.new();world.add_child(source)
	var target:=CharacterBody2D.new();world.add_child(target)
	PAIRS.add_exception(source,target)
	var bucket:=Node2D.new();world.add_child(bucket)
	target.reparent(bucket)
	await process_frame;await physics_frame
	check(source.get_collision_exceptions().has(target),"caller-owned exception survives target reparenting")
	source.reparent(bucket)
	await process_frame;await physics_frame
	check(source.get_collision_exceptions().has(target),"caller-owned exception survives source reparenting")
	target.reparent(world)
	PAIRS.remove_exception(source,target)
	await process_frame;await physics_frame
	check(source.get_collision_exceptions().is_empty(),"explicit removal during reparenting is not undone by deferred restoration")
	bucket.queue_free();target.queue_free()
	await process_frame;await physics_frame
	PAIRS.acquire(a,b,one)
	b.queue_free();await process_frame
	check(a.get_collision_exceptions().is_empty() and not a.has_meta(PAIRS.META),"target exit cleans lease and native metadata")
	b=spawn("",Vector2(24,0),"Team1");b.get_body_motion().set_physics_process(false)
	PAIRS.acquire(a,b,one)
	a.queue_free();await process_frame
	check(b.get_collision_exceptions().is_empty(),"source exit cleans the survivor's native exception")
	one.queue_free()
	# Simulate an old caller/hot-reloaded game retaining a stale native RID. Shared
	# motion must not turn that unrelated RID back into a Node while resolving b/c.
	var legacy:=StaticBody2D.new();world.add_child(legacy)
	b.add_collision_exception_with(legacy)
	legacy.queue_free();await process_frame;await physics_frame
	var c:Node2D=spawn("",Vector2(30,0))
	c.get_body_motion().set_physics_process(false)
	b.get_body_motion().current_velocity=Vector2.RIGHT*100
	b.get_body_motion().resolve_pair(c,Vector2.LEFT)
	b.get_body_motion().separate_overlaps()
	check(b.get_body_motion().current_velocity.x<100,"legacy stale RID does not prevent unrelated body response")
	var holder:=Node.new();world.add_child(holder)
	PAIRS.acquire(b,c,holder)
	check(PAIRS.are_excluded(b,c),"acquiring a new lease never enumerates a legacy stale RID")
	holder.queue_free();await process_frame
	print("BODY_EXCLUSION_LIFETIME checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
