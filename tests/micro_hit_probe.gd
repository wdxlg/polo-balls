extends SceneTree
## 原位微基准：拆解“飞刀命中一名角色”各环节的真实耗时（不经 profiler，避免采样失真）。
var world:Node
func _initialize() -> void: call_deferred("run")
func _us(t0:int,n:int) -> String: return "%.1f us" % (float(Time.get_ticks_usec()-t0)/float(n))
func run() -> void:
	var game:Node = root.get_node("Game")
	game.Game_Settings["Training_Mode"] = false
	game.Game_Settings["Blood_Effects"] = true
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.visible = false
	await create_timer(0.5).timeout
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	for i in range(100):
		world.create_char("Team0" if i % 2 == 0 else "Team1","小刀猎",rect.position + rect.size * Vector2(0.1 + 0.8 * float(i % 10) / 9.0,0.1 + 0.8 * float(i / 10) / 9.0))
	await create_timer(0.5).timeout
	var units:Array = world.get_battle_units_fast().duplicate()
	print("units=",units.size()," large_battle=",units[0].is_large_battle_performance_mode())
	var u = units[0]
	var target = units[1]
	var knife_scene:PackedScene = load("res://scenes/shooter/knife.tscn")
	var RK = load("res://classes/runtime_knife_scene.gd")
	var N:int = 200
	# 1. hit_white
	var t0:int = Time.get_ticks_usec()
	for i in range(N): target.hit_white(false)
	print("hit_white: ",_us(t0,N))
	# 2. take_damage 1 点（血条 + 跳字 + 相机反馈）
	t0 = Time.get_ticks_usec()
	for i in range(N): target.take_damage(1.0,false)
	print("take_damage(1): ",_us(t0,N)," health=",target.health)
	target.health = target.Max_health
	# 3. 血条跳字单独
	t0 = Time.get_ticks_usec()
	for i in range(N): target.health_bar.health_changed.emit(target.health,target.health-1,target.Max_health,true)
	print("health_bar.health_changed emit: ",_us(t0,N))
	target.health = target.Max_health
	# 4. cross section
	t0 = Time.get_ticks_usec()
	for i in range(N): u._estimate_hit_effect_cross_section(u.self_hitbox,Vector2.RIGHT)
	print("_estimate_hit_effect_cross_section: ",_us(t0,N))
	# 5. 受击爆线（本地）
	t0 = Time.get_ticks_usec()
	for i in range(N): target.notify_hit_burst_feedback(u.global_position,10.0,10.0,0.0,12.0,i,Vector2.RIGHT)
	print("notify_hit_burst_feedback: ",_us(t0,N))
	await process_frame
	var effects:int = 0
	for c in world.get_children(): if c.get_script() and c.get_script().resource_path.ends_with("hit_burst_effect.gd"): effects += 1
	print("  live hit_burst effects=",effects)
	t0 = Time.get_ticks_usec()
	await process_frame
	print("  one process_frame with them: ",_us(t0,1))
	# 6. 音效
	var audios:Node = root.get_node("Audios")
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx("KnifeHit",{volume=-5.0},true)
	print("Audios.play_sfx(KnifeHit) direct: ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx.rpc("KnifeHit",{volume=-5.0},true)
	print("Audios.play_sfx.rpc(KnifeHit): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx.rpc("KnifeThrow1",{},true)
	print("Audios.play_sfx.rpc(KnifeThrow1): ",_us(t0,N))
	# 7. _has_death_animation / 刀死亡
	t0 = Time.get_ticks_usec()
	for i in range(N): u._has_death_animation()
	print("_has_death_animation(char): ",_us(t0,N))
	var knives:Array = []
	for i in range(N):
		var k = RK.instantiate(world,knife_scene)
		k.Master = u; k.Master_name = u.name; k.Team = u.Team; k.global_position = u.global_position; k.direction = Vector2.RIGHT
		k.name = game.return_random_name(k)
		world.add_child(k,true)
		knives.append(k)
	await process_frame
	t0 = Time.get_ticks_usec()
	for k in knives: k._has_death_animation()
	print("_has_death_animation(knife): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for k in knives: k.state_machine.current_state = k.State.Die
	print("knife Die transition (transition_state+Die+queue_free): ",_us(t0,N))
	await process_frame
	await process_frame
	# 8. 角色 transition_state Stand->Attack（含 Attack() 投刀）
	t0 = Time.get_ticks_usec()
	for i in range(50):
		u.transition_state(u.State.Stand,u.State.Attack)
		u.transition_state(u.State.Attack,u.State.Stand)
	print("transition Stand->Attack->Stand incl Attack(): ",_us(t0,50))
	await create_timer(0.3).timeout
	# 9. Attack 拆解：instantiate / add_child / play_sfx
	t0 = Time.get_ticks_usec()
	var ks:Array = []
	for i in range(N): ks.append(RK.instantiate(world,knife_scene))
	print("RK.instantiate: ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for k in ks:
		k.set_collision_layer_value(2,false); k.Master = u; k.Master_name = u.name; k.Team = u.Team; k.Speed += u.Speed; k.Damage = u.Damage
		k.global_position = u.global_position; k.global_rotation = k.Default_Rotation; k.direction = Vector2.RIGHT
		k.name = game.return_random_name(k)
	print("knife property setup: ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for k in ks: world.add_child(k,true)
	print("world.add_child(knife,true): ",_us(t0,N))
	await process_frame
	t0 = Time.get_ticks_usec()
	await process_frame
	print("one frame with ",N," flying knives: ",_us(t0,1))
	t0 = Time.get_ticks_usec()
	for k in ks: k.queue_free()
	await process_frame
	print("queue_free ",N," knives + frame: ",_us(t0,1))
	quit()
