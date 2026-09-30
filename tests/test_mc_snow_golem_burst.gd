extends "res://tests/test_mc_snow_golem.gd"
## Actual production volley scheduler, native heading ownership and retired construction.
var evidence:String
var metrics:Array = []

func finish(code:int) -> void:
	if done: return
	if not evidence.is_empty():
		var output:=FileAccess.open(evidence.path_join("metrics.json"),FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics},"\t"))
		output.close()
	print("SNOW_GOLEM_BURST_RESULT checks=",checks," failures=",failures)
	await super.finish(code)

func actor(point:Vector2) -> Node2D:
	var unit:Node2D = spawn(GOLEM_PATH,point)
	unit.set_physics_process(false)
	unit._field.set_physics_process(false)
	unit._shot_left = 0.0
	return unit

func shots(unit:Node2D) -> Array[Node2D]:
	var found:Array[Node2D] = []
	for node:Node in get_nodes_in_group("MCSnowball"):
		if node.Master==unit and not node.is_queued_for_deletion():
			node.state_machine.set_physics_process(false)
			found.append(node)
	found.sort_custom(func(a:Node,b:Node):return str(a.name).get_slice("_Snowball_",1).to_int()<str(b.name).get_slice("_Snowball_",1).to_int())
	return found

func clear_shots(unit:Node2D) -> void:
	for shot:Node2D in shots(unit): shot.free()

func run() -> void:
	game = root.get_node("Game")
	game.Game_Settings.Environment = "none"
	var center:Vector2 = await setup_world()
	create_timer(130,true,false,true).timeout.connect(func():finish(2))
	evidence = OS.get_environment("SNOW_GOLEM_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://snow_golem_burst"
	DirAccess.make_dir_recursive_absolute(evidence)
	var unit:Node2D = actor(center)
	var field:Node2D = unit._field
	var target:Node2D = dummy(center+Vector2(120,0))
	target.set_physics_process(false)
	await physics_frame
	await process_frame
	check(not unit.has_method("mini_spawn_settings"),"Snow Golem has no summon-stat pipeline")
	check(not field.has_method("drop_head") and not field.has_method("_spawn_mini") and not field.has_method("_land_head"),"snow manager has no physical pumpkin, construction or spawn endpoints")
	check(not ResourceLoader.exists("res://scenes/creatures/我的世界/小雪人.tscn") and not ResourceLoader.exists("res://scripts/characters/我的世界/snow_golem/heads_view.gd"),"retired mini scene and ground-head renderer are removed")
	var head_view:bool = false
	for node:Node in field.get_children():
		if node.get_script()!=null and node.get_script().resource_path.ends_with("heads_view.gd"): head_view = true
	check(not head_view,"a weather/trail field creates no hidden construction renderer")
	check(unit.PUMPKIN.size()==16 and unit.BARE.size()==16 and unit.HEAD_FRAMES.size()==16,"both body states and matching pumpkin fragments have full native direction sets")
	check(unit.burst_probability==0.1 and unit.burst_shots==20 and unit.burst_interval_min==0.05 and unit.burst_interval_max==0.10 and unit.burst_spread_degrees==15,"default volley is exactly the user's 10 percent / twenty / random interval / 15-degree choice")
	check(unit.Max_health==425 and unit.Damage==9 and unit.Speed==80 and unit.Attack_Cooling==2.0,"425 HP with unchanged damage, speed and attack cooldown")
	check(unit.is_cold_immune() and unit.player_control_action_ids()==[&"Attack"],"cold immunity remains and the attack modifier does not invent another manual action")
	check_volley(unit,target)
	await check_half_health(unit,target,field)
	check_headings(unit)
	check_chance_and_replay(unit,target)
	check_interruptions(unit,target)
	check(get_nodes_in_group("MCSnowGolem").size()==1,"all attacks/half-health/terrain operations created no autonomous offspring")
	await finish(0 if failures==0 else 1)

func check_volley(unit:Node2D,target:Node2D) -> void:
	unit.burst_probability = 0.0
	unit._shot_left = 0.0
	check(unit.fire_at(target.global_position,target) and unit.shots_fired==1 and unit._burst_remaining==0,"ordinary non-proc attack still emits one real snowball")
	check(not unit.fire_at(target.global_position,target),"ordinary attack still respects its original slow cooldown")
	clear_shots(unit)
	unit._shot_left = 0.0
	unit.burst_probability = 1.0
	unit.rng.seed = 18473
	var serial:int = unit.shots_fired
	var rounds:int = unit.attacks_started
	check(unit.fire_at(target.global_position,target) and unit._burst_remaining==19,"burst starts with a real first projectile and schedules nineteen more")
	check(not unit.fire_at(target.global_position,target),"held/manual retries cannot nest or duplicate an ongoing volley")
	var times:Array[float] = [0.0]
	var angles:Array[float] = []
	var now:float = 0.0
	var last:int = unit.shots_fired
	var within:bool = true
	var live_damage:bool = false
	for shot:Node2D in shots(unit): angles.append(rad_to_deg(unit.global_position.direction_to(target.global_position).angle_to(shot.direction)))
	while unit._burst_remaining>0 and now<3.0:
		now += 0.005
		target.global_position.y += 0.015
		if unit.shots_fired-serial>=10: unit.Damage = 18
		unit.step_mob(0.005)
		if unit.shots_fired!=last:
			var current:Array[Node2D] = shots(unit)
			var shot:Node2D = current.back()
			var angle:float = rad_to_deg(unit.global_position.direction_to(target.global_position).angle_to(shot.direction))
			angles.append(angle)
			within = within and absf(angle)<=15.001
			if unit.Damage==18: live_damage = live_damage or shot.Damage==18
			times.append(now)
			last = unit.shots_fired
	var intervals:Array[float] = []
	var valid_intervals:bool = true
	for i:int in range(1,times.size()):
		var gap:float = times[i]-times[i-1]
		intervals.append(gap)
		valid_intervals = valid_intervals and gap>=0.045-0.00001 and gap<=0.105+0.00001
	check(unit.shots_fired-serial==20 and times.size()==20,"one successful proc emits exactly twenty actual production projectiles")
	check(unit.attacks_started-rounds==1,"the twenty projectiles count as one attack, not twenty chance rolls")
	check(valid_intervals and now>0.95 and now<1.95,"each release has a small random gap and the full burst finishes in the requested short window")
	check(intervals.min()<0.070 and intervals.max()>0.080,"intervals genuinely vary rather than repeating one fixed delay")
	check(within and angles.min()<-7.0 and angles.max()>7.0,"independent spread stays within plus/minus fifteen degrees and exercises both sides")
	check(live_damage,"later snowballs sample the source's CURRENT attack attribute")
	check(shots(unit).all(func(s):return s.Master==unit and s.Team==unit.Team and s.cold_gain==22.0 and s.snow_knockback==8.0),"burst snowballs retain real ownership, ordinary hit, cold and knockback parameters")
	check(unit._shot_left>0.0,"normal two-second attack cooldown continues while the volley is firing")
	metrics.append({"phase":"volley","times":times,"angles":angles,"duration":now})
	unit.Damage = 9
	clear_shots(unit)

func check_half_health(unit:Node2D,target:Node2D,field:Node2D) -> void:
	unit.burst_probability = 0.0
	var cell:Vector2i = FIELD.cell_at(unit.global_position)
	field.deposit(unit,cell,false)
	var snow_before:Dictionary = field.patches.duplicate(true)
	unit.take_damage(unit.health-ceilf(unit.Max_health*0.5),true)
	check(unit.health==ceilf(unit.Max_health*0.5) and unit.has_pumpkin and unit.head_break_count==0,"pumpkin stays worn strictly above half health")
	unit.take_damage(1.0,true)
	check(unit.health==floorf(unit.Max_health*0.5) and not unit.has_pumpkin and unit.head_break_count==1 and unit.force_next_burst,"crossing fifty percent breaks once and arms the NEXT attack")
	check(field.patches==snow_before,"head fracture never consumes or stacks snow beneath the character")
	var fragments:Array[Node] = []
	for node:Node in get_nodes_in_group("MCBlockFragments"):
		if node.has_meta("snow_pumpkin_break"): fragments.append(node)
	check(fragments.size()==1 and fragments[0].pieces.size()>6 and fragments[0].is_in_group("BattleTransient"),"half health creates genuine shared block-pixel fragments, not a falling pumpkin entity")
	var effect:Node2D = fragments[0]
	effect.set_process(false)
	check(effect.get_parent()==unit._battle_parent(),"pumpkin fragments stay in this actor's own battle world")
	var effect_count:int = fragments.size()
	unit._show_pumpkin_break(1,unit.global_position,0,0.2,55)
	var current_count:int = 0
	for node:Node in get_nodes_in_group("MCBlockFragments"):
		if node.has_meta("snow_pumpkin_break"): current_count+=1
	check(current_count==effect_count,"duplicate reliable break event cannot replay fragments")
	await process_frame # Critical action audio now uses the safe deferred player queue.
	var sounds_count:int = 0
	for node:Node in get_nodes_in_group("MCSnowSound"):
		if node.get_meta("mc_snow_phase","")=="pumpkin_break" and node.get_meta("mc_sound_event","")=="block.wood.break": sounds_count+=1
	check(sounds_count==1,"pumpkin break uses the verified original wood-break event once")
	unit._shot_left = 0.0
	var rng_before:int = unit.rng.state
	check(not unit.fire_at(unit.global_position+Vector2(2000,0)) and unit.force_next_burst and unit.rng.state==rng_before,"invalid/out-of-range attempt consumes neither the guarantee nor a chance roll")
	var before:int = unit.shots_fired
	check(unit.fire_at(target.global_position,target) and unit._burst_remaining==19 and not unit.force_next_burst,"the next valid attack is a volley even with random proc probability zero")
	while unit._burst_remaining>0: unit.step_mob(0.02); shots(unit)
	check(unit.shots_fired-before==20,"half-health guarantee produces a full twenty-shot volley")
	clear_shots(unit)
	unit.heal(500)
	unit.take_damage(ceilf(unit.Max_health*0.5),true)
	check(unit.head_break_count==1 and not unit.force_next_burst and not unit.has_pumpkin,"healing and crossing half health again cannot regrow/break another pumpkin or rearm the consumed guarantee")
	var old_age:float = effect.age
	game.now_stop_state = true
	effect._process(0.5)
	check(effect.age==old_age,"block fracture particles obey battle pause")
	game.now_stop_state = false
	effect.advance(2.0)
	check(effect.is_queued_for_deletion(),"short-lived shards expire instead of becoming permanent ground blocks")
	await process_frame

func check_headings(unit:Node2D) -> void:
	unit._cancel_burst()
	unit._aim_hold_left = 0.0
	for pumpkin:bool in [true,false]:
		unit.has_pumpkin = pumpkin
		for i:int in range(16):
			var heading:Vector2 = Vector2.from_angle(TAU*float(i)/16.0)
			unit.direction = heading
			unit._aim = heading
			unit._aim_hold_left = 0.25 # Full sixteen-direction views are now ATTACK poses.
			unit.move(0.0,0.01)
			unit.visual_mob()
			var expected:Texture2D = unit.PUMPKIN[i] if pumpkin else unit.BARE[i]
			check(unit._aim_pose==i and unit.image.texture==expected and not unit.is_character_visual_flipped_h() and not unit.image.flip_h and is_zero_approx(unit.image.rotation),"native direction %02d pumpkin=%s survives BOTH mover and render without double mirroring" % [i,pumpkin])
	unit.has_pumpkin = false
	unit._aim_hold_left = 0.0
	unit.set_player_control_peer(1)
	unit.set_player_control_direction(Vector2.RIGHT)
	unit.direction = Vector2.LEFT
	unit.move(0.0,0.01)
	check(unit._aim_pose==2,"manual movement chooses the right diagonal over stale AI heading")
	unit.set_player_control_aim_position(unit.global_position+Vector2(0,-120))
	unit._shot_left = 0.0
	unit.burst_probability = 1.0
	unit.player_control_action(0)
	check(unit._burst_remaining==19 and unit._aim_pose==12 and unit.player_control_direction==Vector2.RIGHT,"manual LMB uses the same volley toward mouse aim without rewriting WASD")
	unit._cancel_burst()
	clear_shots(unit)
	unit.set_player_control_peer(0)

func check_chance_and_replay(unit:Node2D,target:Node2D) -> void:
	unit.burst_probability = 0.10
	unit.force_next_burst = false
	unit.rng.seed = 261001
	var procs:int = 0
	var rounds:int = unit.attacks_started
	for i:int in range(1000):
		unit._shot_left = 0.0
		var previous:int = unit.bursts_started
		unit.fire_at(target.global_position,target)
		if unit.bursts_started>previous: procs+=1
		unit._cancel_burst()
		clear_shots(unit)
	check(unit.attacks_started-rounds==1000 and procs>=70 and procs<=130,"one seeded 10-percent roll per valid attack across 1000 actual activations: "+str(procs))
	metrics.append({"phase":"chance","rounds":1000,"procs":procs})
	var sequences:Array = []
	unit.burst_probability = 1.0
	for trial:int in range(2):
		unit.rng.seed = 19377
		unit._shot_left = 0.0
		unit.fire_at(target.global_position,target)
		var data:Array = [[shots(unit).back().direction,unit._burst_wait]]
		while unit._burst_remaining>0:
			var before:int = unit.shots_fired
			unit.step_mob(0.01)
			if unit.shots_fired>before: data.append([shots(unit).back().direction,unit._burst_wait])
		sequences.append(data)
		clear_shots(unit)
	check(sequences[0]==sequences[1] and sequences[0].size()==20,"same actor RNG seed and combat deltas replay all twenty spread/delay choices")

func check_interruptions(unit:Node2D,target:Node2D) -> void:
	unit._shot_left = 0.0
	unit.fire_at(target.global_position,target)
	var remain:int = unit._burst_remaining
	var cooldown:float = unit._shot_left
	var wait:float = unit._burst_wait
	var count:int = unit.shots_fired
	game.now_stop_state = true
	unit.step_mob(10.0)
	check(unit._burst_remaining==remain and unit._shot_left==cooldown and unit._burst_wait==wait and unit.shots_fired==count,"pause freezes volley, attack cooldown and release timing")
	game.now_stop_state = false
	unit.dizziness = true
	unit.step_mob(0.25)
	check(unit._burst_remaining==0 and unit.shots_fired==count and unit.get_debug_detection_regions().is_empty(),"stun cancels remaining projectiles and unavailable detection geometry")
	unit.dizziness = false
	clear_shots(unit)
	unit._shot_left = 0.0
	unit.fire_at(target.global_position,target)
	unit.Can_Attack = false
	count = unit.shots_fired
	unit.step_mob(0.25)
	check(unit._burst_remaining==0 and unit.shots_fired==count,"attack disable cannot finish an illicit burst")
	unit.Can_Attack = true
	clear_shots(unit)
	unit.set_multiplayer_authority(2)
	unit._shot_left = 0.0
	check(not unit.fire_at(target.global_position,target),"replica cannot create its own attack or chance roll")
	unit.step_mob(3.0)
	check(unit.shots_fired==count,"replica cannot advance authoritative volley emissions")
	unit.set_multiplayer_authority(1)
	unit.health = unit.Max_health
	unit.has_pumpkin = true
	unit.head_break_count = 0
	unit._last_break_fx_serial = 0
	unit._shot_left = 0.0
	unit.fire_at(target.global_position,target)
	unit.take_damage(ceilf(unit.Max_health*0.5),true)
	check(unit._burst_remaining>0 and unit.force_next_burst,"half health reached DURING a volley arms the following attack, not the current one")
	while unit._burst_remaining>0: unit.step_mob(0.02); shots(unit)
	check(unit.force_next_burst,"finishing the current volley cannot erase the pending next-attack guarantee")
	unit._shot_left = 0.0
	unit.burst_probability = 0.0
	check(unit.fire_at(target.global_position,target) and unit._burst_remaining==19 and not unit.force_next_burst,"following attack consumes the preserved guarantee exactly once")
	count = unit.shots_fired
	unit.health = 0
	unit.tick_physics(unit.State.Stand,0.016)
	check(unit._burst_remaining==0 and unit.shots_fired==count and unit.get_debug_detection_regions().is_empty(),"death retires the volley without a delayed shot or leftover targeting region")
	clear_shots(unit)
