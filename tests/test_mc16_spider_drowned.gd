extends SceneTree
# MC16 v2: wall silk / loyalty trident / charged same-team graph, real World.
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false
var center:Vector2
var geometry:Script
var units:Array[Node2D] = []
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	unit.state_machine.set_physics_process(false)
	units.append(unit)
	if unit.has_method("silk_tail_position"):
		unit.silk_network.set_physics_process(false)
		for manager:Node in get_nodes_in_group("MCSpiderWebFootsteps"): manager.set_physics_process(false)
	if unit.has_method("throw_trident"):
		unit._trident.set_physics_process(false)
		world.get_node("MCTridentNetwork").set_physics_process(false)
	return unit
func dummy(point:Vector2,team:String = "Team1") -> Node2D:
	var unit:Node2D = spawn("res://scenes/ball.tscn",point,team)
	unit.Max_health = 100000.0
	unit.default_properties["Max_health"] = 100000.0 # Buff refresh must not reset fixture HP to 1000.
	unit.health = 100000.0
	unit.Speed = 0.0
	return unit
func park_others(keep:Array) -> void:
	var i:int = 0
	for unit:Node2D in units:
		if unit not in keep:
			unit.global_position = center+Vector2(-800+i*90,800)
			i += 1
func reset_silk(net:Node) -> void:
	net.segments.clear()
	net.anchor.clear()
	net.webs.clear()
	net._previous.clear()
	net._previous_lines.clear()
	net._contact_left = 0.0
func wall_touch(net:Node,point:Vector2) -> void:
	net._contact_left = 0.0
	net.touch_wall(point)
func cycle(unit:Node,target:Node,distance:float) -> float:
	unit.global_position = center+Vector2(-300,300)
	target.global_position = unit.global_position+Vector2(distance,0)
	unit.dizziness = false
	var hp:float = target.health
	check(unit.throw_trident(target),"held spear throws immediately")
	check(not unit.throw_trident(target),"no duplicate throw while empty-handed")
	var spear:Node = unit._trident
	spear.set_physics_process(false)
	var elapsed:float = 0.0
	var saw_return:bool = false
	var spin_before:float = 0.0
	while elapsed<8.0 and not unit.has_trident:
		if spear.flight_state==2 and not saw_return:
			spin_before = spear.rotation
			saw_return = true
		spear.advance(1.0/120.0)
		elapsed += 1.0/120.0
	check(saw_return and unit.has_trident,"enemy hit returns to actual moving hand")
	check(not is_equal_approx(spin_before,float(spear.rotation)),"return visibly spins")
	check(is_equal_approx(hp-float(target.health),ceilf(unit.trident_hit_damage())),"half-strength direct attack per round trip, no return double-hit")
	return elapsed
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(60.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.35).timeout
	# Avoid concurrent background texture initialization in Godot's dummy renderer.
	await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self)
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	var spider:Node2D = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(180,0))
	var drowned:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-300,300))
	var target:Node2D = dummy(center)
	var friend:Node2D = dummy(center,"Team0")
	await process_frame
	await process_frame
	spider.mc_native_animation.set_process(false)
	drowned.mc_native_animation.set_process(false)
	var net:Node = spider.silk_network
	check(spider.mc_live() and drowned.mc_live(),"fixtures in active combat")
	check(not spider.has_method("_fire_web") and not drowned.has_method("_fire_splash"),"old web pellets / splash / riptide skills removed")
	# Strict intersection semantics.
	check(geometry.crossing(Vector2(0,0),Vector2(100,100),Vector2(0,100),Vector2(100,0))==Vector2(50,50),"X intersection creates web")
	check(geometry.crossing(Vector2.ZERO,Vector2(100,0),Vector2(100,0),Vector2(100,100))==null,"shared wall endpoint does NOT create web")
	check(geometry.crossing(Vector2.ZERO,Vector2(100,0),Vector2(20,0),Vector2(120,0))==null,"collinear strands do not manufacture junctions")
	# Live wall-to-body strand and fixed wall-to-wall strand both hurt.
	wall_touch(net,center+Vector2(-180,0))
	check(net.lines().size()==1 and net.segments.is_empty(),"first wall touch creates one live tether")
	var tail:Vector2 = spider.silk_tail_position()
	check(net.lines()[0].b.is_equal_approx(tail),"tether endpoint follows abdomen")
	target.global_position = (net.lines()[0].a+tail)*0.5
	friend.global_position = target.global_position
	var hp:float = target.health
	var friendly_hp:float = friend.health
	net._tick_contacts()
	check(target.health<hp and friend.health==friendly_hp,"live tether damages enemies only")
	check(not net.touch_wall(center+Vector2(-179,0)),"wall contact debounce prevents micro-strand spam")
	wall_touch(net,center+Vector2(180,0))
	check(net.segments.size()==1 and net.lines().size()==2,"second wall touch fixes previous strand and starts next tether")
	reset_silk(net)
	for p:Vector2 in [Vector2(-120,-80),Vector2(120,80),Vector2(120,-80),Vector2(-120,80)]: wall_touch(net,center+p)
	net.anchor = {}
	net._update_crossings()
	check(net.webs.size()==1,"only interior diagonal crossing creates web")
	target.global_position = center
	friend.global_position = center
	target.Buff_Dic.clear()
	hp = target.health
	net._tick_contacts()
	var buffs:Dictionary = target.Buff_Dic.get(spider.get_instance_id(),{})
	check(buffs.size()==3,"two strand slows plus one strong web slow are independently keyed")
	# ball.health is integer: each accepted hit rounds the requested new HP down.
	check(is_equal_approx(hp-float(target.health),ceilf(spider.silk_damage)*2.0+ceilf(spider.web_damage)),"two strands plus web each deal fixed one-point damage")
	var product:float = 1.0
	for buff:Variant in buffs.values(): product *= float(buff.amount)
	check(is_equal_approx(product,pow(spider.silk_slow_multiplier,2.0)*spider.web_slow_multiplier),"strand slows multiply with the strong web slow")
	check(spider._lunge_left>0.0,"crossing web triggers spider hunt")
	net._tick_contacts()
	check(target.Buff_Dic[spider.get_instance_id()].size()==3,"refresh does not infinitely stack strand/web slows")
	await physics_frame
	check(not target.dizziness,"web contact slows instead of stunning")
	# Freeze projectile/net processing again after yielding; hunt must strike once only.
	spider.global_position = target.global_position+Vector2(4,0)
	spider._last_lunge_position = spider.global_position
	hp = target.health
	spider._try_lunge_hit(target)
	spider._try_lunge_hit(target)
	check(is_equal_approx(hp-float(target.health),ceilf(spider.attack_damage()*spider.lunge_damage_ratio)),"web hunt applies exactly one attack")
	check(spider._lunge_left==0.0,"hunt stops after connecting")
	# Swept contact catches a target crossing between high-frequency samples.
	reset_silk(net)
	wall_touch(net,center+Vector2(-100,0)); wall_touch(net,center+Vector2(100,0)); net.anchor = {}
	target.global_position = center+Vector2(0,70)
	net._previous[target.get_instance_id()] = center+Vector2(0,-70)
	hp = target.health
	net._tick_contacts()
	check(target.health<hp,"fast enemies cannot tunnel through silk")
	var before_clock:float = net._clock
	game.now_stop_state = true
	net.advance(1.0)
	check(net._clock==before_clock,"pause freezes silk sampling and damage")
	game.now_stop_state = false
	net.advance(600.0)
	check(net.segments.size()==1,"fixed silk remains after ten simulated minutes")
	# Actual contact against a Physics wall, not only direct helper calls.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12,160)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(150,-260)
	spider.global_position = center+Vector2(100,-260)
	await physics_frame
	var collision:KinematicCollision2D = spider.move_and_collide(Vector2(100,0))
	check(collision!=null,"fixture actually contacts an obstacle")
	net._contact_left = 0.0
	if collision!=null: spider.when_collide(100.0,collision)
	check(not net.anchor.is_empty(),"real wall collision attaches silk")
	reset_silk(net)
	wall.queue_free()
	await physics_frame
	# Slow outgoing / faster returning: near target produces a faster attack cycle.
	park_others([drowned,target])
	var near_time:float = cycle(drowned,target,70.0)
	var far_time:float = cycle(drowned,target,260.0)
	check(far_time>near_time*1.7,"closer enemies yield faster attacks without fixed cooldown")
	check(drowned.trident_return_speed>drowned.trident_speed,"return is faster than outbound")
	# A real wall before the target must beat target collision even at huge steps.
	wall = StaticBody2D.new()
	wall.collision_layer = 1; wall.collision_mask = 0
	shape = CollisionShape2D.new(); rect = RectangleShape2D.new(); rect.size = Vector2(12,220); shape.shape = rect
	wall.add_child(shape); world.add_child(wall)
	drowned.global_position = center+Vector2(-300,-300)
	target.global_position = drowned.global_position+Vector2(260,0)
	wall.global_position = drowned.global_position+Vector2(100,0)
	await physics_frame
	hp = target.health
	drowned.throw_trident(target)
	var lodged:Node2D = drowned._trident
	lodged.set_physics_process(false)
	lodged.advance(3.0)
	check(lodged.flight_state==3 and target.health==hp,"wall-first swept hit sticks rather than damaging enemy behind wall")
	check(absf(lodged.global_position.x-(wall.global_position.x-7.0))<3.0,"spear lodges at wall surface, not end-of-step position")
	check(not drowned.has_trident and drowned._trident==null,"lodging starts empty-hand refill state")
	drowned.dizziness = true
	drowned.tick_physics(drowned.state_machine.current_state,1.0)
	check(not drowned.has_trident,"no immediate replacement after wall hit")
	drowned.tick_physics(drowned.state_machine.current_state,2.0)
	check(drowned.has_trident and drowned._trident!=lodged,"replacement appears after refill delay")
	drowned._trident.set_physics_process(false)
	drowned.dizziness = false
	check(not lodged.charged,"untouched lodged trident starts uncharged")
	drowned.global_position = lodged.global_position+Vector2(-4,0)
	lodged.advance(0.01)
	check(not lodged.charged,"nearby drowned cannot bypass the grounded enchant wait")
	lodged.advance(11.98)
	check(not lodged.charged,"grounded trident waits the full twelve seconds")
	lodged.advance(0.02)
	check(lodged.charged,"grounded trident automatically enchants after twelve seconds")
	# Creeper visual warns first; the impact signal is the single damage clock.
	target.global_position = lodged.global_position+Vector2(0,30)
	hp = target.health
	var own_hp:float = drowned.health
	drowned.summon_trident_lightning(lodged)
	var lightning:Node
	for child:Node in lodged.get_children():
		if child.has_signal("impact_started"): lightning = child
	lightning.set_process(false)
	lightning._process(drowned.lightning_warning-0.01)
	check(target.health==hp,"lightning warning has no premature damage")
	game.now_stop_state = true
	lightning._process(2.0)
	check(target.health==hp and not lightning._impact_started,"pause freezes warning/impact together")
	game.now_stop_state = false
	lightning._process(0.02)
	check(target.health<hp and lightning._impact_started,"actual Creeper lightning impact damages enemy")
	check(drowned.health==own_hp and drowned._trident.charged,"friendly/self lightning charges hand without self-damage")
	var after_bolt:float = target.health
	lightning._process(0.05)
	check(target.health==after_bolt,"one bolt cannot deal damage twice")
	var child_count:int = lodged.get_child_count()
	lodged.lightning_left = 0.0; lodged.advance(0.01)
	check(lodged.get_child_count()>child_count,"charged pole periodically creates another lightning warning")
	for child:Node in lodged.get_children(): child.set_process(false)
	# Same-team full graph including held spear; enemy-team endpoints excluded.
	var ally:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(120,0))
	var enemy_drowned:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(0,-200),"Team1")
	await process_frame
	ally.mc_native_animation.set_process(false); enemy_drowned.mc_native_animation.set_process(false)
	for spear:Node in get_nodes_in_group("MCTrident"): spear.charged = false
	drowned.global_position = center+Vector2(-120,0)
	ally.global_position = center+Vector2(120,0)
	lodged.wall_ref = null; lodged.global_position = center+Vector2(0,140)
	var a:Node = drowned._trident
	var b:Node = ally._trident
	a.charge(); b.charge(); lodged.charge(); enemy_drowned._trident.charge()
	a.advance(0.0); b.advance(0.0)
	target.global_position = (a.global_position+b.global_position)*0.5
	friend.global_position = target.global_position
	for arc:Node in get_nodes_in_group("MCTridentArc"): arc.free()
	var manager:Node = world.get_node("MCTridentNetwork")
	manager.pulse()
	check(manager.last_pair_count==3,"three friendly charged endpoints make exactly three unordered pairs")
	check(get_nodes_in_group("MCTridentArc").size()==3,"hostile team's spear is not connected")
	hp = target.health; friendly_hp = friend.health
	for arc:Node in get_nodes_in_group("MCTridentArc"):
		arc.set_physics_process(false)
		arc.advance(0.01)
	check(target.health<hp and friend.health==friendly_hp,"arc contact hurts enemies and excludes allies")
	var once:float = target.health
	for arc:Node in get_nodes_in_group("MCTridentArc"): arc.advance(0.02)
	check(target.health==once,"each link hits a victim at most once per pulse")
	for arc:Node in get_nodes_in_group("MCTridentArc"): arc.free()
	manager.pulse()
	for arc:Node in get_nodes_in_group("MCTridentArc"):
		arc.set_physics_process(false); arc.advance(0.01)
	check(target.health<once,"next network pulse can damage again")
	# Real Creeper bolts can also charge a drowned's spear.
	var creeper:Node2D = spawn("res://scenes/characters/我的世界/苦力怕.tscn",ally.global_position)
	b.charged = false
	creeper._apply_lightning_area(ally.global_position)
	check(b.charged,"original Creeper lightning charges nearby drowned")
	# Exact actual-damage audio threshold and monotonically increasing volume.
	var base:Script = load("res://scripts/characters/我的世界/mc_mob_base.gd")
	check(base.mc_impact_event(50.0)=="entity.player.hurt","50 damage still uses native hurt")
	check(base.mc_impact_event(50.01)=="entity.player.attack.crit","strictly above 50 uses native critical hit")
	check(base.mc_impact_volume(3.0)<base.mc_impact_volume(30.0) and base.mc_impact_volume(30.0)<base.mc_impact_volume(80.0),"higher actual damage raises sound volume")
	var heard_hurt:bool = false
	var heard_crit:bool = false
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.has_meta("mc_damage_source"):
			heard_hurt = heard_hurt or player.get_meta("mc_sound_event","")=="entity.player.hurt"
			heard_crit = heard_crit or player.get_meta("mc_sound_event","")=="entity.player.attack.crit"
	check(heard_hurt and heard_crit,"actual mechanics emitted native hurt AND critical sounds")
	# New poles do not evict old poles.
	for i:int in range(10):
		var extra:Node = drowned._create_trident(100+i)
		extra.set_physics_process(false)
		extra.stick(center+Vector2(500+i*20,500))
	var stuck_count:int = 0
	for spear:Node in drowned._tridents.values():
		if is_instance_valid(spear) and spear.flight_state==3 and not spear.is_queued_for_deletion(): stuck_count += 1
	check(stuck_count>=10,"lodged spears are not evicted by the former six-spear cap")
	var life:float = a.traveled
	game.now_stop_state = true
	a.advance(1.0)
	check(a.traveled==life,"pause freezes projectile simulation")
	game.now_stop_state = false
	print("MC16_REWORK checks=",checks," failures=",failures," near=",near_time," far=",far_time)
	finish(0 if failures==0 else 1)
func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self): code = 1
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	_stop_audio(root)
	await create_timer(0.12,true,false,true).timeout
	print("MC16_REWORK_EXIT=",code)
	quit(code)
func _stop_audio(node:Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.stop()
		if node.is_in_group("MCNativeSFX"): node.queue_free()
	for child:Node in node.get_children(): _stop_audio(child)
