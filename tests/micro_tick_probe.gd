extends SceneTree
## 原位微基准：拆解角色 / 飞刀“每个物理 tick”的脚本开销（headless，直接调用函数计时）。
var world:Node
func _initialize() -> void: call_deferred("run")
func _us(t0:int,n:int) -> String: return "%.2f us" % (float(Time.get_ticks_usec()-t0)/float(n))
func _bench(label:String,n:int,f:Callable) -> void:
	var t0:int = Time.get_ticks_usec()
	for i in range(n): f.call()
	print("  %-58s %s" % [label,_us(t0,n)])
func _frame_avg(frames:int) -> float:
	await process_frame
	var t0:int = Time.get_ticks_usec()
	for i in range(frames): await process_frame
	return float(Time.get_ticks_usec()-t0)/1000.0/float(frames)
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
	print("frame with empty world: %.2f ms" % (await _frame_avg(20)))
	for i in range(100):
		world.create_char("Team0" if i % 2 == 0 else "Team1","小刀猎",rect.position + rect.size * Vector2(0.1 + 0.8 * float(i % 10) / 9.0,0.1 + 0.8 * float(i / 10) / 9.0))
	await create_timer(0.3).timeout
	var units:Array = world.get_battle_units_fast().duplicate()
	var u = units[0]
	var delta:float = 1.0/60.0
	var N:int = 2000
	print("units=",units.size()," large_battle=",u.is_large_battle_performance_mode()," physics_tps=",Engine.physics_ticks_per_second)
	print("frame with 100 chars (fighting): %.2f ms" % (await _frame_avg(20)))
	# 冻结所有角色（不再产刀），单独量角色 tick
	game.now_stop_state = true
	await create_timer(0.5).timeout
	print("frame with 100 chars (now_stop_state, no knives): %.2f ms" % (await _frame_avg(20)))
	for x in units: x.state_machine.set_physics_process(false)
	print("frame with 100 chars, state machines OFF: %.2f ms" % (await _frame_avg(20)))
	for x in units: x.state_machine.set_physics_process(true)
	print("--- character (小刀猎) per-tick pieces ---")
	var st:int = u.state_machine.current_state
	_bench("state_machine._physics_process",N,func(): u.state_machine._physics_process(delta))
	_bench("get_next_state",N,func(): u.get_next_state(st))
	_bench("tick_physics",N,func(): u.tick_physics(st,delta))
	_bench("  _update_stun_shake_visual",N,func(): u._update_stun_shake_visual(delta))
	_bench("  _update_poison_visual",N,func(): u._update_poison_visual())
	_bench("  _update_motion_inertia_visual",N,func(): u._update_motion_inertia_visual(st,delta))
	_bench("  _update_projectile_facing_from_position_delta",N,func(): u._update_projectile_facing_from_position_delta(delta))
	_bench("  is_multiplayer_authority",N,func(): u.is_multiplayer_authority())
	_bench("  _ensure_upright_character_visual",N,func(): u._ensure_upright_character_visual())
	_bench("  apply_external_directional_gravity",N,func(): u.apply_external_directional_gravity(delta))
	_bench("  move(Speed)",N,func(): u.move(u.Speed,delta))
	_bench("  stand",N,func(): u.stand(delta))
	_bench("  _sync_projectile_facing_from_frame_motion",N,func(): u._sync_projectile_facing_from_frame_motion(Vector2.ZERO,delta))
	_bench("  _process_auto_after_image",N,func(): u._process_auto_after_image(delta))
	_bench("  is_combat_runtime_active (ball)",N,func(): u.is_combat_runtime_active())
	_bench("  world.is_combat_runtime_active",N,func(): world.is_combat_runtime_active())
	_bench("  Game.get_training_mode_type",N,func(): game.get_training_mode_type())
	_bench("  is_damage_output_disabled",N,func(): u.is_damage_output_disabled())
	_bench("  is_player_controlled",N,func(): u.is_player_controlled())
	_bench("  is_large_battle_performance_mode",N,func(): u.is_large_battle_performance_mode())
	_bench("  allows_character_motion_effects",N,func(): u.allows_character_motion_effects())
	_bench("  attack_damage(1.0)",N,func(): u.attack_damage(1.0))
	_bench("  current_hit_damage_multiplier",N,func(): u.current_hit_damage_multiplier())
	# 刀
	print("--- knife per-tick pieces ---")
	var knife_scene:PackedScene = load("res://scenes/shooter/knife.tscn")
	var RK = load("res://classes/runtime_knife_scene.gd")
	var k = RK.instantiate(world,knife_scene)
	k.set_collision_layer_value(2,false); k.Master = u; k.Master_name = u.name; k.Team = u.Team; k.Speed += u.Speed; k.Damage = u.Damage
	k.global_position = rect.get_center(); k.direction = Vector2.RIGHT; k.name = game.return_random_name(k)
	world.add_child(k,true)
	await process_frame
	var kst:int = k.state_machine.current_state
	print("  knife state=",kst," large_battle=",k.is_large_battle_performance_mode()," spacing=",k.AfterImage_Spacing," maxpf=",k.AfterImage_Max_Per_Frame)
	_bench("state_machine._physics_process",N,func(): k.state_machine._physics_process(delta))
	_bench("get_next_state",N,func(): k.get_next_state(kst))
	_bench("tick_physics",N,func(): k.tick_physics(kst,delta))
	_bench("  _update_stun_shake_visual",N,func(): k._update_stun_shake_visual(delta))
	_bench("  _update_poison_visual",N,func(): k._update_poison_visual())
	_bench("  _update_motion_inertia_visual",N,func(): k._update_motion_inertia_visual(kst,delta))
	_bench("  _update_projectile_facing_from_position_delta",N,func(): k._update_projectile_facing_from_position_delta(delta))
	_bench("  apply_external_directional_gravity",N,func(): k.apply_external_directional_gravity(delta))
	_bench("  move(Speed)",N,func(): k.move(k.Speed,delta))
	_bench("  _sync_projectile_facing_from_frame_motion",N,func(): k._sync_projectile_facing_from_frame_motion(Vector2(5,0),delta))
	_bench("  _process_auto_after_image",N,func(): k._process_auto_after_image(delta))
	_bench("  _update_after_image_stretch(no spawn)",N,func(): k._update_after_image_stretch(delta,k.image.global_transform,300.0,Vector2.RIGHT,true))
	_bench("  is_combat_runtime_active",N,func(): k.is_combat_runtime_active())
	k.queue_free()
	await process_frame
	# 整帧：K 把分散飞行的刀
	print("--- whole-frame cost vs flying knives (chars frozen) ---")
	for x in units: x.state_machine.set_physics_process(false)
	var base:float = await _frame_avg(20)
	print("  0 knives: %.2f ms" % base)
	for mode in ["normal","noafterimage","nostatemachine"]:
		var ks:Array = []
		for i in range(100):
			var kk = RK.instantiate(world,knife_scene)
			kk.set_collision_layer_value(2,false); kk.Master = units[i]; kk.Master_name = units[i].name; kk.Team = units[i].Team; kk.Speed = 20.0; kk.Damage = 0.0
			kk.global_position = rect.position + rect.size * Vector2(0.15 + 0.7 * float(i % 10) / 9.0,0.15 + 0.7 * float(i / 10) / 9.0)
			kk.direction = Vector2.RIGHT.rotated(float(i) * 0.7); kk.name = game.return_random_name(kk)
			if mode == "noafterimage": kk.AfterImage_Speed = -1.0
			world.add_child(kk,true)
			if mode == "nostatemachine": kk.state_machine.set_physics_process(false)
			ks.append(kk)
		await process_frame
		var t:float = await _frame_avg(20)
		print("  100 knives (%s): %.2f ms  (+%.2f ms, %.1f us/knife/frame)" % [mode,t,t-base,(t-base)*1000.0/100.0])
		for kk in ks: kk.queue_free()
		await process_frame
		await process_frame
	quit()
