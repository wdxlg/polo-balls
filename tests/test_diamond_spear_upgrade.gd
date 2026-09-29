extends "res://tests/test_diamond_spear_sfx.gd"
## Speed tiers, committed non-homing volleys, actual one-way travel and safe body-first piercing.
class FloorArena extends Node2D:
	var region:Rect2 = Rect2(-1000,-1000,2000,2000)
	var map_group:Dictionary = {}
	var now_choose_map:String = "test"
	func return_map_world_rect(_map:Node) -> Rect2: return region

var extras:Array[Node2D] = []

func ghosts() -> Array[Node2D]:
	var result:Array[Node2D] = []
	for node:Variant in spear._visual_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.attack_echo: result.append(node)
	return result

func impacts() -> int:
	var count:int = 0
	for node:Variant in spear._feedback_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.kind==1: count += 1
	return count

func extra(point:Vector2,team:String="Team1") -> Node2D:
	var result:Node2D = victim(point,team)
	extras.append(result)
	return result

func fixture(speed:float=600.0,point:Vector2=Vector2(21,0)) -> void:
	spear._cancel_action()
	for list:Array in [spear._visual_nodes,spear._feedback_nodes]:
		for node:Variant in list:
			if is_instance_valid(node): node.free()
		list.clear()
	clear_sounds()
	for node:Variant in extras:
		if is_instance_valid(node): node.free()
	extras.clear()
	game.now_stop_state = false
	arena.region = Rect2(-1000,-1000,2000,2000)
	reset(Vector2.ZERO,speed)
	spear.Can_Attack = true
	spear.Can_Skill = true
	if not is_instance_valid(enemy): enemy = victim(point)
	enemy.global_position = point
	enemy.Team = "Team1"
	enemy.block = 0
	enemy.health = 10000

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("DIAMOND_UPGRADE_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = FloorArena.new()
	var map_node := Node2D.new()
	arena.add_child(map_node)
	arena.map_group = {"test":map_node}
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

	check(spear.echo_full_speed==600 and spear.echo_upgrade_speed==800,"separate editable full-count and upgraded-form thresholds")
	for pair:Array in [[100,0],[150,1],[239,1],[240,2],[419,2],[420,3],[599,3],[600,4],[799,4],[960,4]]:
		check(spear.echo_count(pair[0])==pair[1],"echo count at speed "+str(pair[0]))
	check(not spear.echoes_upgraded(799.99) and spear.echoes_upgraded(800) and spear.echoes_upgraded(960),"upgrade happens only at the second threshold")
	check(spear.Damage==26 and spear.Max_health==500 and spear.max_move_speed==960,"base damage, health and maximum speed are unchanged")

	fixture()
	spear.Attack()
	check(ghosts().size()==1 and not ghosts()[0].piercing,"full-count tier still begins with an ordinary anchored echo")
	spear._tick_echo_queue(0.039)
	check(ghosts().size()==1,"second echo does not start early")
	spear._tick_echo_queue(0.001)
	check(ghosts().size()==2,"second echo at .04 seconds")
	spear._tick_echo_queue(0.04)
	check(ghosts().size()==3,"third echo at .08 seconds")
	spear._tick_echo_queue(0.069)
	check(ghosts().size()==3,"last echo leaves room for the final accent")
	spear._tick_echo_queue(0.001)
	check(ghosts().size()==4 and ghosts()[3].accent,"last echo at .15 seconds carries the accent")
	check(not ghosts()[0].accent and ghosts()[3].multiplier==ghosts()[0].multiplier,"accent does not secretly increase per-echo damage")
	check(weapon_sounds("echo").back().pitch_scale<=0.98,"last echo has its own lower, weightier sound without more gain")

	fixture(800)
	var old_target:Vector2 = enemy.global_position
	var saved_blink:float = 2.0
	spear._blink_wait = saved_blink
	spear.Can_Skill = false
	var time_scale:float = Engine.time_scale
	var audio_scale:float = AudioServer.playback_speed_scale
	spear.Attack()
	check(spear._action in [spear.Action.PIERCE_CHARGE,spear.Action.PIERCE_RECOVER],"upgraded basic attack crosses with the body first, even with skills disabled")
	check(spear.total_pierce_thrusts==1 and spear._blink_wait==saved_blink,"basic crossing does not consume or reset the independent blink skill cooldown")
	check(enemy.health<10000 and ghosts().is_empty() and spear._pending_echo_anchors.size()==4,"body deals its hit before any attacking ghost exists")
	check(spear.image.global_position.distance_to(spear.global_position)<0.001,"short crossing snaps the real visual to its landing")
	check(impacts()>0 and spear._impact_hold_remaining>0.0,"confirmed crossing produces a local impact and pose hold")
	check(Engine.time_scale==time_scale and AudioServer.playback_speed_scale==audio_scale,"new impact feedback never changes global game or audio speed")
	var speed_before_hit:float = spear._momentum
	spear._action_hits.clear()
	spear.damage_segment(spear.global_position, enemy.global_position, 3.0, 1.0, spear._action_hits, 0.0)
	check(spear._momentum > speed_before_hit, "landing hit increases movement speed")
	var hp_after_body:int = enemy.health
	spear._tick_action(0.08)
	check(spear.global_position.x>old_target.x,"body passage finishes crossing behind target")
	spear._tick_action(0.016)
	check(enemy.health==hp_after_body and ghosts().is_empty(),"crossing recovery neither double-hits nor spawns echoes in the same physics update")
	spear._tick_echo_queue(0.039)
	check(ghosts().is_empty(),"first chase echo waits until after the body passage")
	spear._tick_echo_queue(0.001)
	check(ghosts().size()==1 and ghosts()[0].piercing,"first travelling echo starts at .04 seconds after passage")
	var first:Node2D = ghosts()[0]
	var fixed_axis:Vector2 = first.axis
	var origin:Vector2 = first.anchor
	enemy.global_position = Vector2(80,80)
	spear.global_position = Vector2(140,-30)
	for i:int in range(3): spear._tick_echo_queue(spear._echo_spawn_wait)
	check(ghosts().size()==4 and spear._pending_echo_anchors.is_empty(),"upgraded volley generates four separate travelling spears")
	for ghost:Node2D in ghosts():
		check(ghost.axis.dot((old_target-ghost.anchor).normalized())>0.999,"each delayed echo keeps the original target coordinate")
		check(ghost._trail_sprites.size()==3,"travelling echo has exactly three bounded reused afterimages")
	check(first.axis==fixed_axis and first.anchor==origin,"moving target and caster cannot steer an existing echo")
	var replacement:Node2D = extra(old_target)
	await physics_frame
	await physics_frame
	first._physics_process(0.06)
	check(first.sprite.global_position.distance_to(origin)>10.0,"the entire upgraded spear visibly travels instead of poking in place")
	check(replacement.health<10000 and enemy.health==hp_after_body,"echo hits the old line, not the dodging original target")
	check(first._trail_sprites[0].visible and first._trail_sprites[0].position.x<first.sprite.position.x,"afterimages stay behind the travelling blade")
	var once:int = replacement.health
	var clock:float = first.elapsed
	first._render_at(0.04)
	check(first.elapsed==clock and replacement.health==once,"render interpolation does not advance time or apply damage")
	first._physics_process(0.05)
	var arrived:float = first.sprite.position.x
	first._physics_process(0.05)
	check(first.sprite.position.x>=arrived and replacement.health==once,"passage does not retract or damage the same victim twice")
	game.now_stop_state = true
	clock = first.elapsed
	first._physics_process(0.2)
	check(first.elapsed==clock,"pause freezes travelling echoes and their trails")
	game.now_stop_state = false

	fixture(800)
	spear.Attack()
	enemy.free()
	enemy = null
	for i:int in range(4): spear._tick_echo_queue(spear._echo_spawn_wait)
	check(ghosts().size()==4,"target death after the body hit does not swallow the committed volley")
	spear.dizziness = true
	var cancelled:Node2D = ghosts()[0]
	cancelled._physics_process(0.02)
	spear._tick_echo_queue(1.0)
	check(cancelled.is_queued_for_deletion() and spear._pending_echo_anchors.is_empty(),"stun cancels live damage echoes and queued births")

	fixture(800,Vector2(80,0))
	var plan:Dictionary = spear.blink_plan(enemy)
	check(not plan.is_empty(),"long crossing plan exists")
	var ally:Node2D = extra(plan.end,"Team0")
	await physics_frame
	await physics_frame
	check(not spear.blink_plan(enemy).is_empty(),"friendly body in the rear no longer blocks direct piercing")
	spear.Can_Attack = false
	check(spear._begin_blink(enemy),"skill crossing can start independently of basic attack permission")
	spear._tick_action(spear.blink_windup)
	check(spear.global_position.x>enemy.global_position.x and ally.health==10000,"body passes through occupied rear without friendly damage")
	check(ghosts().is_empty() and spear._pending_echo_anchors.size()==4,"upgraded long blink also crosses before its delayed volley")
	spear._tick_echo_queue(spear.echo_pierce_start_delay)
	check(ghosts().size()==1 and ghosts()[0].requires_skill,"skill-origin volley follows skill permission, not basic-attack permission")
	spear.Can_Skill = false
	cancelled = ghosts()[0]
	cancelled._physics_process(0.02)
	spear._tick_echo_queue(1.0)
	check(cancelled.is_queued_for_deletion() and spear._pending_echo_anchors.is_empty(),"disabling skills cancels remaining skill-origin damage")

	fixture(800)
	enemy.max_block = 10000
	enemy.block = 10000
	spear.Attack()
	check(enemy.health==10000 and impacts()==0 and is_zero_approx(spear._impact_hold_remaining),"full block cannot create a false confirmed-hit burst or pose hold")

	fixture()
	var limit:float = spear._tip_position().x+spear.thrust_tip_reach+spear._target_extent(enemy,Vector2.RIGHT)
	enemy.global_position = Vector2(limit+3.0,0)
	check(spear._front_target()==null,"target outside the current tip window is not already in range")
	spear._thrust_lookahead_delta = 1.0/60.0
	check(spear._front_target()==enemy and enemy.health==10000,"one-step high-speed lookahead starts a legal opportunity without predictive damage")
	var wall:Node2D = barrier(Vector2(limit-1.0,0),Vector2(2,80))
	await physics_frame
	await physics_frame
	check(spear._front_target()==null,"lookahead cannot see a target through terrain")
	wall.free()

	fixture(600,Vector2(80,20))
	var distant:Node2D = extra(Vector2(160,0))
	extra(Vector2(110,0))
	await physics_frame
	await physics_frame
	check(spear._try_blink_target() and spear._blink_ref.get_ref()==distant,"valid multi-enemy line is preferred over a nearer single target")

	fixture(800,Vector2(80,0))
	wall = barrier(Vector2(40,0),Vector2(4,80))
	await physics_frame
	await physics_frame
	check(spear.blink_plan(enemy).is_empty(),"removing rear occupancy gating never grants wall crossing")
	wall.free()
	arena.region = Rect2(-100,-100,200,200)
	check(spear.blink_plan(enemy).is_empty(),"whole-body direct crossing still respects painted-map boundaries")

	fixture(800)
	spear.Attack()
	wall = barrier(Vector2(35,0),Vector2(2,100))
	var behind:Node2D = extra(Vector2(50,0))
	await physics_frame
	await physics_frame
	spear._tick_echo_queue(spear.echo_pierce_start_delay)
	check(ghosts().size()==1,"committed ghost is independent of the caster's new position beyond a wall")
	first = ghosts()[0]
	first._physics_process(0.11)
	check(behind.health==10000 and first.sprite.global_position.x+first.tip_distance<34.0,"travelling spear and its damage both stop before a newly present wall")
	wall.free()

	fixture(800)
	spear.Attack()
	arena.region = Rect2(-100,-100,160,200)
	spear._tick_echo_queue(spear.echo_pierce_start_delay)
	first = ghosts()[0]
	first._physics_process(0.11)
	check(first.sprite.global_position.x+first.tip_distance<60.0,"travelling echo is clipped before the real floor edge")
	for i:int in range(80): spear._play_impact_feedback(Vector2.ZERO,Vector2.RIGHT)
	check(spear._feedback_nodes.size()<=12 and spear._visual_nodes.size()<=48,"feedback and spear-node budgets stay bounded")

	fixture()
	spear._emit_echo(Vector2.ZERO,Vector2.RIGHT,0.04,false,0.0)
	var expired:Node2D = spear._visual_nodes.back()
	expired.queue_free()
	await process_frame
	spear._cancel_action()
	check(spear._visual_nodes.is_empty(),"cancelling after an expired silhouette safely prunes stale references")
	arena.queue_free()
	await process_frame
	game.Game_Settings = saved_settings
	game.now_stop_state = saved_stop
	print("DIAMOND_UPGRADE_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
