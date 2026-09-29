extends "res://tests/test_elytra_return_dash.gd"
## Regression: a successful smash near the map edge must not become a miss in ascent.
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
	if evidence.is_empty(): evidence = "user://skull_trail_combo"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(80,true,false,true).timeout.connect(func(): failures+=1; finish())
	for role:String in ["鞘翅重锤","鞘翅重锤长矛"]:
		await chain_near_edge(role)
	await skull_trails()
	finish()

func chain_near_edge(role:String) -> void:
	var unit:Node2D = actor(role,Vector2(0,-145))
	var enemy:Node2D = victim(unit.global_position)
	unit._pvp_target = enemy
	unit._begin_flight(1)
	var before:float = enemy.health
	unit._finish_landing()
	check(enemy.health<before and unit._chain_level==2,role+": seed smash is accepted by production damage settlement")
	var route:Array = []
	var hit_count:int = 1
	var premature:bool = false
	var returned:bool = false
	for frame:int in range(480):
		before = enemy.health
		var prior_multiplier:float = unit._chain_damage_multiplier
		unit._update_flight(1.0/60.0)
		returned = returned or unit._returning_to_map
		if enemy.health<before: hit_count+=1
		route.append([frame,unit.global_position.x,unit.global_position.y,unit._glide_velocity.y,unit._airborne,unit._chain_level,unit._chain_damage_multiplier,enemy.health,unit._returning_to_map])
		if prior_multiplier>0.0 and unit._chain_damage_multiplier==0.0:
			premature = unit._flight_elapsed<0.55 and unit._glide_velocity.y<35.0
			break
		if hit_count>=4: break
	check(returned,role+": trajectory actually exercises map-return guard")
	check(not premature,role+": successful chain is not reset during rebound ascent/soft return")
	check(hit_count>=4 and unit._chain_level>=4,role+": continuous physical trajectories accumulate four accepted smashes")
	metrics.append({"role":role,"hits":hit_count,"premature":premature,"route":route})
	var retained:float = unit._chain_damage_multiplier
	var held_position:Vector2 = unit.global_position
	var held_elapsed:float = unit._flight_elapsed
	game.now_stop_state = true
	unit._update_flight(0.5)
	check(unit.global_position==held_position and unit._flight_elapsed==held_elapsed and unit._chain_damage_multiplier==retained,role+": pause preserves accumulated progress and flight clocks")
	game.now_stop_state = false
	unit.Damage = 37
	enemy.global_position = unit.global_position
	before = enemy.health
	var expected:float = unit.attack_damage(retained)
	unit._chain_level = unit.max_chain_level
	unit._finish_landing()
	check(absf(before-enemy.health-expected)<=1.0,role+": next smash reads changed live attack, not cached opening damage")
	check(unit._chain_level==unit.max_chain_level and is_equal_approx(unit._chain_damage_multiplier,retained*unit.landing_damage_jump_multiplier),role+": height cap does not cap accumulated damage")
	# An actual landing with no target, unlike mid-flight steering, resets both stacks.
	enemy.global_position = Vector2(3000,3000)
	unit._finish_landing()
	check(not unit._airborne and unit._chain_level==1 and unit._chain_damage_multiplier==0.0,role+": genuinely empty smash resets progress")
	unit._begin_flight(1)
	enemy.global_position = unit.global_position
	enemy.Damage_reduction = 1.0
	before = enemy.health
	unit._finish_landing()
	check(enemy.health==before and not unit._airborne and unit._chain_damage_multiplier==0.0,role+": rejected smash cannot award progress")
	unit._begin_flight(1)
	enemy.global_position = Vector2(3000,3000)
	unit._flight_elapsed = 2.79
	unit._update_flight(0.04)
	check(not unit._airborne and unit._chain_damage_multiplier==0.0,role+": an exhausted attempt with no accepted hit still times out as a miss")
	unit.free()
	enemy.free()
	await process_frame

func new_skull(source:Node2D,point:Vector2,direction:Vector2 = Vector2.RIGHT) -> Node2D:
	var skull:Node2D = source.SKULL.new()
	arena.add_child(skull)
	skull.global_position = point
	skull.configure(source,direction)
	skull.set_physics_process(false)
	return skull

func clear_smoke() -> void:
	for p:Node in get_nodes_in_group("MCSmokeTrail"): p.free()

func skull_trails() -> void:
	var source:Node2D = actor("凋灵",Vector2(-180,80))
	source.summoned = true
	var skull:Node2D = new_skull(source,Vector2(-120,80))
	var start:Vector2 = skull.global_position
	skull._physics_process(0.1)
	var particles:Array[Node] = get_nodes_in_group("MCSmokeTrail")
	check(skull.global_position.is_equal_approx(start+Vector2(26,0)) and is_equal_approx(skull.life,3.9),"trail does not alter skull speed or lifetime")
	check(particles.size()==4,"26 units of flight emits four distance-spaced particles")
	var valid:bool = not particles.is_empty()
	for p:Node in particles:
		valid = valid and p.texture==source.CHARGE_SMOKE and p.global_position.x<skull.global_position.x and p.get_meta("mc_emitter_id")==source.get_instance_id() and p._pixel_width==8.0
	check(valid,"skull trail uses original texture, small pixels, source ownership and rear positions")
	if not particles.is_empty():
		var p:Node = particles[0]
		p.set_process(false)
		var age:float = p._age
		game.now_stop_state = true
		p._process(0.1)
		var point:Vector2 = skull.global_position
		var ttl:float = skull.life
		skull._physics_process(0.1)
		check(p._age==age and skull.global_position==point and skull.life==ttl and get_nodes_in_group("MCSmokeTrail").size()==4,"pause freezes projectile, trail emission and shared particle ageing")
		game.now_stop_state = false
		p._process(0.6)
		check(p.is_queued_for_deletion(),"shared trail naturally expires")
	skull.free()
	clear_smoke()
	# Density/carry is invariant to frame partitioning and each sampling call is capped.
	var visuals:Script = source.CHARGE_VISUALS
	var full:Dictionary = visuals.sample_smoke_trail(Vector2.ZERO,Vector2(26,0),6.0,6.0,0.0)
	var split:PackedVector2Array = []
	var carry:float = 0.0
	for i:int in range(10):
		var sample:Dictionary = visuals.sample_smoke_trail(Vector2(i*2.6,0),Vector2((i+1)*2.6,0),6.0,6.0,carry)
		split.append_array(sample.points)
		carry = sample.distance
	valid = split.size()==full.points.size()
	for i:int in range(mini(split.size(),full.points.size())): valid = valid and split[i].is_equal_approx(full.points[i])
	check(valid and is_equal_approx(carry,full.distance),"shared sampler has frame-independent positions and fractional carry")
	check(visuals.sample_smoke_trail(Vector2.ZERO,Vector2(50000,0),6.0,6.0,0.0).points.size()==48,"one movement sample has a hard 48-point budget")
	# Physical blocker: smoke ends at contact, not at the untraversed ray endpoint.
	var wall:=StaticBody2D.new()
	wall.collision_layer = 1
	wall.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var shape:=CollisionShape2D.new()
	var rect:=RectangleShape2D.new()
	rect.size = Vector2(8,60)
	shape.shape = rect
	wall.add_child(shape)
	arena.add_child(wall)
	wall.global_position = Vector2(20,80)
	await physics_frame
	skull = new_skull(source,Vector2(-40,80))
	skull._physics_process(0.5)
	particles = get_nodes_in_group("MCSmokeTrail")
	valid = not particles.is_empty()
	for p:Node in particles: valid = valid and p.global_position.x<16.0
	check(skull.exploded and skull.is_queued_for_deletion() and valid,"real ray collision clips trail before wall and retains explosion cleanup")
	wall.free()
	skull.free()
	clear_smoke()
	# Friendly bodies are skipped; the same authoritative direct hit still applies once.
	var ally:Node2D = victim(Vector2(-15,80))
	ally.Team = source.Team
	ally.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var enemy:Node2D = victim(Vector2(40,80))
	enemy.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	await physics_frame
	var ally_hp:float = ally.health
	var enemy_hp:float = enemy.health
	skull = new_skull(source,Vector2(-60,80))
	skull._physics_process(0.6)
	check(skull.exploded and ally.health==ally_hp and enemy.health<enemy_hp,"skull retains friendly pass-through and real hostile impact")
	var hp_after:float = enemy.health
	skull._physics_process(0.1)
	check(enemy.health==hp_after,"exploded skull cannot settle another hit")
	skull.free()
	ally.free()
	enemy.free()
	clear_smoke()
	skull = new_skull(source,Vector2.ZERO)
	skull.life = 0.01
	skull._physics_process(0.02)
	check(skull.is_queued_for_deletion() and get_nodes_in_group("MCSmokeTrail").is_empty(),"expired skull creates no final ghost trail")
	skull.free()
	skull = new_skull(source,Vector2.ZERO)
	source.health = 0
	skull._physics_process(0.01)
	check(skull.is_queued_for_deletion() and get_nodes_in_group("MCSmokeTrail").is_empty(),"source death removes skull without new particles")
	skull.free()
	source.health = 200
	var batch:PackedVector2Array = []
	for i:int in range(48): batch.append(Vector2(i,0))
	for i:int in range(8): source._show_skull_trail(batch,Vector2.RIGHT)
	check(get_nodes_in_group("MCSmokeTrail").size()==256,"all skulls and charges share the existing 256-particle cap")
	clear_smoke()
	source.free()
	await process_frame
