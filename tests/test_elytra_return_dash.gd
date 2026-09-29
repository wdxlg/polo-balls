extends SceneTree
## Production actors and combat shapes; fixed world rectangles supplied by a scoped arena.
class FlightArena extends Node2D:
	var regions:Array[Rect2] = [Rect2(-240,-160,480,320)]
	func current_map_island_rects() -> Array[Rect2]: return regions

var arena:Node2D
var game:Node
var checks:int = 0
var failures:int = 0
var evidence:String
var metrics:Array = []
var saved:Dictionary
var saved_stop:bool
var done:bool = false

func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures += 1

func actor(role:String,point:Vector2) -> Node2D:
	var node:Node2D = load("res://scenes/characters/我的世界/"+role+".tscn").instantiate()
	node.Team = "Team0"
	arena.add_child(node,true)
	node.global_position = point
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.health_bar.hide()
	return node

func victim(point:Vector2) -> Node2D:
	var node:Node2D = load("res://scenes/ball.tscn").instantiate()
	node.Team = "Team1"
	node.Max_health = 100000
	node.Health_Restore = 0
	node.Has_Collision_Damage = false
	arena.add_child(node,true)
	node.global_position = point
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.Can_Attack = false
	node.Can_Skill = false
	return node

func outside_distance(point:Vector2,rect:Rect2) -> float:
	return point.distance_to(point.clamp(rect.position,rect.end))

func finish() -> void:
	if done: return
	done = true
	if not evidence.is_empty():
		var f:=FileAccess.open(evidence.path_join("metrics.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics},"\t"))
		f.close()
	print("ELYTRA_RETURN_DASH_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	quit(0 if failures==0 else 1)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = FlightArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	evidence = OS.get_environment("ELYTRA_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://elytra_return_dash"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(110,true,false,true).timeout.connect(func():push_error("ELYTRA_RETURN_TIMEOUT"); failures+=1; finish())
	for role:String in ["鞘翅重锤","鞘翅长矛","鞘翅重锤长矛"]:
		await check_return(role)
	for role:String in ["鞘翅重锤","鞘翅长矛","鞘翅重锤长矛"]:
		await check_return_edges(role)
	for role:String in ["鞘翅长矛","鞘翅重锤长矛"]:
		await check_dash(role)
		await check_restrictions_and_manual(role)
		await check_multi_hit_and_death(role)
	await check_map_scope()
	await finish()

func check_return(role:String) -> void:
	var unit:Node2D = actor(role,Vector2(255,0))
	var enemy:Node2D = victim(Vector2(2000,0))
	unit._pvp_target = enemy
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.apply_damage_disable(60.0)
	unit._glide_velocity = Vector2.RIGHT*850.0
	unit.velocity = unit._glide_velocity
	unit._rocket_cooldown = 0.0
	var maximum:float = 0.0
	var inside:bool = false
	var continuous:bool = true
	var route:Array = []
	for frame:int in range(900):
		var before:Vector2 = unit.global_position
		unit._step_glide(1.0/60.0)
		var point:Vector2 = unit.global_position
		maximum = maxf(maximum,outside_distance(point,arena.regions[0]))
		continuous = continuous and point.distance_to(before)<=unit.maximum_flight_speed/60.0+0.1
		inside = inside or arena.regions[0].grow(-12).has_point(point)
		if frame%6==0: route.append([point.x,point.y])
	metrics.append({"role":role,"maximum_outside_distance":maximum,"returned_inside":inside,"route":route})
	check(maximum<260,role+": distant enemy cannot lure the flyer arbitrarily far outside")
	check(inside,role+": outward high-speed flight actively returns inside the arena")
	check(continuous,role+": recovery is real curved flight, not teleporting or clamping")
	check(unit.get_meta("submission_allow_map_escape",false) and unit.collision_layer==0 and unit.self_hurtbox.collision_layer!=0,role+": temporary outside flight remains allowed and damageable")
	unit.free()
	enemy.free()
	await process_frame

func prime(unit:Node2D,point:Vector2,motion:Vector2) -> void:
	unit.global_position = point
	unit._glide_velocity = motion
	unit.velocity = motion
	unit.Repel = Vector2.ZERO
	unit.glide_gravity = 0.0
	unit.glide_drag = 0.0
	unit._rocket_cooldown = 100.0
	unit._rocket_remaining = 0.0
	unit._poke_retreat_left = 0.0
	unit._pierce_dash_cooldown_left = 0.0
	unit._spear_contacts.clear()
	unit._pierce_heading = Vector2.ZERO
	unit._returning_to_map = false
	unit._tactic_hold = 0.0
	unit._patrol_rect_refresh = 0.0
	unit.Can_Attack = true
	unit.Can_Skill = true
	unit._face_flight_direction()

func check_return_edges(role:String) -> void:
	for heading:Vector2 in [Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var point:Vector2 = heading*Vector2(255,175)
		var unit:Node2D = actor(role,point)
		var enemy:Node2D = victim(heading*2000.0)
		unit._pvp_target = enemy
		unit.Can_Attack = false
		unit.Can_Skill = false
		unit.apply_damage_disable(60.0)
		unit._glide_velocity = heading*850.0
		var maximum:float = 0.0
		var entered:bool = false
		for frame:int in range(420):
			unit._step_glide(1.0/60.0)
			maximum = maxf(maximum,outside_distance(unit.global_position,arena.regions[0]))
			entered = entered or arena.regions[0].grow(-12).has_point(unit.global_position)
		check(entered and maximum<260,role+": bounded return from "+str(heading))
		unit.free()
		enemy.free()
		await process_frame
	if role!="鞘翅长矛":
		var unit:Node2D = actor(role,Vector2(400,0))
		unit._begin_flight(1)
		unit._glide_velocity = Vector2.RIGHT*600
		unit._patrol_rect_refresh = 0.0
		var before:Vector2 = unit.global_position
		unit._update_flight(1.0/60.0)
		check(unit._airborne and unit._returning_to_map and unit._chain_damage_multiplier>0.0,role+": distant rebound turns home without falsely declaring a missed smash")
		check(unit.global_position.distance_to(before)<=unit.maximum_flight_speed/60.0+0.1,role+": rebound return keeps continuous physical motion")
		unit.free()
		await process_frame

func check_dash(role:String) -> void:
	var unit:Node2D = actor(role,Vector2(-140,0))
	var enemy:Node2D = victim(Vector2(20,0))
	unit._pvp_target = enemy
	prime(unit,Vector2(-140,0),Vector2.RIGHT*240)
	check(unit.Can_Skill and is_equal_approx(unit.Skill_Cooling,1.8),role+": new ability is enabled with a real live cooldown attribute")
	var regions:Array = unit.get_debug_detection_regions()
	check(regions.size()==1 and regions[0].shape=="polygon" and Geometry2D.is_point_in_polygon(enemy.global_position,regions[0].points),role+": blue region describes the real aligned-enemy activation cone")
	check(not Geometry2D.is_point_in_polygon(unit.global_position+Vector2(0,100),regions[0].points),role+": perpendicular enemies are outside the activation cone")
	unit._step_glide(1.0/60.0)
	check(unit._pierce_dashing and unit._glide_velocity.length()>=unit.pierce_dash_min_speed,role+": normal AI stepping starts a real speed burst when aligned")
	check(unit.get_debug_detection_regions().is_empty(),role+": activation cone disappears during the committed dash")
	check(is_instance_valid(unit._firework_trail) and unit._firework_trail.get_world_2d()==unit.get_world_2d(),role+": dash reuses native rocket media in the actor's own world")
	var initial_speed:float = unit._glide_velocity.length()
	var hp:int = enemy.health
	var hit:bool = false
	var delayed:bool = true
	var crossed:bool = false
	var maximum:float = initial_speed
	var route:Array = []
	for frame:int in range(70):
		unit._step_glide(1.0/60.0)
		if enemy.health<hp and not hit:
			hit = true
			delayed = not unit._airborne
			check(unit.last_contact_speed==initial_speed and is_equal_approx(unit.last_contact_damage,unit.flight_damage_at_speed(initial_speed,true)),role+": hit uses incoming speed/current attack before awarding propulsion")
		maximum = maxf(maximum,unit._glide_velocity.length())
		crossed = crossed or unit.global_position.x>enemy.global_position.x+40.0
		route.append([unit.global_position.x,unit.global_position.y,unit._glide_velocity.length(),unit._pierce_dashing,unit._airborne])
		if not unit._pierce_dashing: break
	check(hit and maximum>initial_speed+100.0,role+": accepted hit accelerates the actual flight further")
	check(crossed,role+": body physically clears the enemy rather than immediately bouncing back")
	check(delayed,role+": first dash contact does not interrupt pass-through with a rebound")
	if role=="鞘翅重锤长矛":
		check(unit._airborne and unit._chain_level==1 and not unit._dash_combo_pending,role+": completed pass starts exactly one original mace chain")
	else:
		check(not unit._airborne and not unit.Attacking,role+": pure spear never gains the mace rebound")
	check(unit._pierce_dash_cooldown_left>0.0 and not unit.try_pierce_dash(enemy),role+": immediate repeat cannot bypass cooldown")
	metrics.append({"role":role,"dash_initial_speed":initial_speed,"post_hit_maximum_speed":maximum,"crossed":crossed,"route":route})
	unit.free()
	enemy.free()
	await process_frame
	# Separate blocked-contact pass: no reward and, for the combo, no deferred leap.
	unit = actor(role,Vector2(-140,0))
	enemy = victim(Vector2(20,0))
	enemy.Damage_reduction = 1.0
	unit._pvp_target = enemy
	prime(unit,Vector2(-140,0),Vector2.RIGHT*240)
	check(unit.try_pierce_dash(enemy),role+": rejected-damage probe starts a valid dash")
	initial_speed = unit._glide_velocity.length()
	hp = enemy.health
	for frame:int in range(45):
		unit._step_glide(1.0/60.0)
		if not unit._pierce_dashing: break
	check(enemy.health==hp and is_equal_approx(unit._glide_velocity.length(),initial_speed),role+": rejected damage cannot grant hit speed")
	check(not unit._airborne,role+": missing/blocked pass cannot manufacture a combo follow-up")
	unit.free()
	enemy.free()
	await process_frame

func check_restrictions_and_manual(role:String) -> void:
	var unit:Node2D = actor(role,Vector2(-140,0))
	var enemy:Node2D = victim(Vector2(20,0))
	unit._pvp_target = enemy
	prime(unit,Vector2(-140,0),Vector2.UP*240)
	check(not unit.try_pierce_dash(enemy),role+": AI cannot burst while facing away from the enemy")
	unit._glide_velocity = Vector2.RIGHT*240
	unit.Can_Skill = false
	check(not unit.try_pierce_dash(enemy),role+": skill disable blocks a new burst")
	unit.Can_Skill = true
	unit.Can_Attack = false
	check(not unit.try_pierce_dash(enemy),role+": attack disable also blocks a damaging burst")
	unit.Can_Attack = true
	unit.dizziness = true
	check(not unit.try_pierce_dash(enemy),role+": stun blocks new bursts")
	unit.dizziness = false
	unit.set_multiplayer_authority(2)
	var point:Vector2 = unit.global_position
	check(not unit.try_pierce_dash(enemy),role+": remote replica cannot start its own speed bonus")
	unit._step_glide(0.25)
	check(unit.global_position==point,role+": replica does not run the authority flight integrator")
	unit.set_multiplayer_authority(1)
	unit.Skill_Cooling = 0.77
	check(unit.try_pierce_dash(enemy) and is_equal_approx(unit._pierce_dash_cooldown_left,0.77),role+": activation reads the CURRENT cooldown, not a detached fixed timer")
	var left:float = unit._pierce_dash_left
	var cooldown:float = unit._pierce_dash_cooldown_left
	point = unit.global_position
	game.now_stop_state = true
	unit._step_glide(0.5)
	check(unit.global_position==point and unit._pierce_dash_left==left and unit._pierce_dash_cooldown_left==cooldown,role+": pause freezes dash movement and both clocks")
	game.now_stop_state = false
	unit.dizziness = true
	unit._step_glide(0.01)
	check(not unit._pierce_dashing and not unit._airborne and unit.get_debug_attack_regions().is_empty(),role+": interruption removes the dash without a delayed extra attack")
	unit.dizziness = false
	prime(unit,Vector2(220,0),Vector2.RIGHT*400)
	enemy.global_position = Vector2(360,0)
	check(not unit.try_pierce_dash(enemy),role+": AI rejects a dash whose predicted exit flies beyond its return band")
	unit.player_control_peer_id = 1
	unit.player_control_direction = Vector2.UP
	unit.player_control_aim_valid = true
	unit.player_control_aim_position = unit.global_position+Vector2(200,0)
	check(unit.player_control_action_ids()==[&"controlled_pierce_dash_action",&"controlled_skill_action"],role+": LMB dash and RMB rocket occupy distinct real action slots")
	check(not unit.try_pierce_dash(enemy),role+": direct control suppresses autonomous aligned-enemy bursts")
	unit.player_control_action(0)
	check(unit._pierce_dashing and unit._glide_velocity.x>400 and unit.player_control_direction==Vector2.UP,role+": manual LMB aims with the mouse without rewriting WASD")
	unit._finish_pierce_dash(false)
	unit._rocket_cooldown = 0.0
	unit.player_control_action(1)
	check(unit._rocket_remaining>0.0,role+": manual RMB still activates the original rocket")
	unit.global_position = Vector2(700,0)
	unit._returning_to_map = true
	check(unit._map_return_aim(0.1).is_zero_approx() and not unit._returning_to_map,role+": auto-return does not seize the direction of a manually controlled flyer")
	unit.free()
	enemy.free()
	await process_frame

func check_map_scope() -> void:
	var unit:Node2D = actor("鞘翅重锤",Vector2(600,0))
	unit._glide_velocity = Vector2.RIGHT*600
	unit._patrol_rect_refresh = 0
	unit._map_return_aim(0.1)
	var translated:Array[Rect2] = [Rect2(1000,600,480,320)]
	arena.regions = translated
	unit._patrol_rect_refresh = 0.0
	unit._map_return_aim(0.1)
	check(unit._patrol_rect==arena.regions[0],"changing the real arena layout refreshes the return boundary")
	var entered:bool = false
	for frame:int in range(900):
		unit._step_glide(1.0/60.0)
		entered = entered or arena.regions[0].grow(-10).has_point(unit.global_position)
	check(entered,"return steering reaches a translated arena rather than the old world origin")
	var view:=SubViewport.new()
	view.world_2d = World2D.new()
	root.add_child(view)
	var foreign:Node2D = load("res://scenes/ball.tscn").instantiate()
	foreign.Team = "Team1"
	view.add_child(foreign)
	check(not unit._is_enemy(foreign),"a flyer never chases or hits a different replicated physics world")
	foreign.free()
	view.queue_free()
	unit.free()
	var original:Array[Rect2] = [Rect2(-240,-160,480,320)]
	arena.regions = original
	await process_frame

func check_multi_hit_and_death(role:String) -> void:
	var unit:Node2D = actor(role,Vector2(-160,0))
	var first:Node2D = victim(Vector2(-20,0))
	var second:Node2D = victim(Vector2(70,0))
	prime(unit,Vector2(-160,0),Vector2.RIGHT*240)
	unit._pvp_target = first
	check(unit.try_pierce_dash(first),role+": starts a multi-enemy straight pass")
	var initial:float = unit._glide_velocity.length()
	var hp_first:int = first.health
	var hp_second:int = second.health
	var peak:float = initial
	for frame:int in range(45):
		unit._step_glide(1.0/60.0)
		peak = maxf(peak,unit._glide_velocity.length())
		if not unit._pierce_dashing: break
	check(first.health<hp_first and second.health<hp_second,role+": one dash actually pierces two distinct enemies")
	check(is_equal_approx(peak,minf(initial+unit.pierce_hit_speed_bonus*2,unit.maximum_flight_speed)),role+": two different accepted contacts each award one bounded speed increment")
	check(is_equal_approx(unit.last_contact_speed,initial+unit.pierce_hit_speed_bonus),role+": later contact uses the speed earned by the previous actual hit")
	unit.free()
	first.free()
	second.free()
	await process_frame
	unit = actor(role,Vector2(-140,0))
	first = victim(Vector2(20,0))
	prime(unit,Vector2(-140,0),Vector2.RIGHT*240)
	unit.try_pierce_dash(first)
	unit.health = 0
	unit.tick_physics(unit.State.Stand,0.0)
	check(not unit._pierce_dashing and not unit._airborne,role+": death cancels the active dash and any deferred attack")
	check(unit.get_debug_attack_regions().is_empty() and unit.get_debug_detection_regions().is_empty(),role+": dead flyer leaves no damage or activation geometry")
	unit.queue_free()
	first.queue_free()
	await process_frame
