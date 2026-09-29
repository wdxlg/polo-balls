extends SceneTree
## Real motion / contact fixture: no Speed-buff assertion can substitute for displacement.
var checks:int = 0
var failures:int = 0
var world:Node
var source:Node2D
var SURFACE:Script
var game:Node
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func fighter(name_key:String,point:Vector2,sulfur:bool = false) -> Node2D:
	var unit:Node2D = load("res://scenes/characters/我的世界/硫方怪.tscn" if sulfur else "res://scenes/ball.tscn").instantiate()
	unit.name = name_key
	unit.Team = "Team0" if sulfur else "Team1"
	unit.position = point
	if not sulfur: unit.get_node("CharacterAutoFit").enabled = false
	world.add_child(unit)
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.Has_Collision_Damage = false
	unit.self_hitbox.set_deferred("monitoring",false)
	unit.Max_health = 4000
	unit.default_properties.Max_health = 4000
	unit.health = 4000
	unit.Speed = 100.0
	unit.default_properties.Speed = 100.0
	unit.player_control_peer_id = 1
	if not sulfur:
		var shape := CircleShape2D.new()
		shape.radius = 15.0
		unit.collision_shape_2d.shape = shape
		unit.get_node("hurtbox/CollisionShape2D").shape = shape
	return unit
func floor_tile(rect:Rect2) -> Node2D:
	var tile:Node2D = source.ICE_TRAIL.new()
	world.add_child(tile)
	tile.setup(source,rect)
	tile.set_physics_process(false)
	return tile
func motion_step(unit:Node2D,tile:Node2D) -> void:
	await physics_frame
	unit.tick_physics(unit.State.Move,1.0/60.0)
	if is_instance_valid(tile): tile._physics_process(1.0/60.0)
	var effect:Node = unit.get_node_or_null("SurfaceAcceleration")
	if effect != null:
		effect.set_physics_process(false)
		effect._physics_process(1.0/60.0)
func knockback(unit:Node) -> Node:
	for child:Node in unit.get_children():
		if child.get_script() == unit.KNOCKBACK_EFFECT_SCRIPT: return child
	return null
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): print("BALANCE_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	SURFACE = load("res://scripts/effects/surface_acceleration.gd")
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	source = fighter("BalanceCube",Vector2(-1000,-1000),true)
	var runner:Node2D = fighter("RightRunner",Vector2(25,40))
	var reverse:Node2D = fighter("LeftRunner",Vector2(135,110))
	var idle:Node2D = fighter("Stationary",Vector2(15,15))
	runner.player_control_direction = Vector2.RIGHT
	reverse.player_control_direction = Vector2.LEFT
	idle.player_control_direction = Vector2.ZERO
	var tile:Node2D = floor_tile(Rect2(-10,-10,180,180))
	var start:Vector2 = runner.global_position
	var early:float = 0.0
	for i:int in range(30):
		await motion_step(runner,tile)
		if i == 5: early = runner.velocity.x
	var late:float = runner.velocity.x
	print("ICE_MOTION early=",early," late=",late," distance=",runner.global_position.x-start.x," base_speed=",runner.Speed*0.6)
	check(early > 65.0 and late > early+35.0,"ice adds sustained acceleration over successive real movement frames")
	check(runner.global_position.x-start.x > 45.0 and absf(runner.global_position.y-start.y) < 0.05,"actual traveled distance grows along the runner's own direction, not caster direction")
	check(is_equal_approx(runner.Speed,100.0) and runner.Buff_Dic.is_empty(),"acceleration is real additive velocity, not a nominal Speed buff")
	check(runner.surface_motion_velocity.length() <= 90.01,"ice speed has a bounded 1.5x base bonus, not runaway accumulation")
	for i:int in range(12): await motion_step(reverse,tile)
	check(reverse.velocity.x < -85.0 and absf(reverse.velocity.y) < 0.05,"a second actor accelerates in its own opposite direction")
	var idle_start:Vector2 = idle.global_position
	for i:int in range(5): await motion_step(idle,tile)
	check(idle.global_position.is_equal_approx(idle_start) and idle.surface_motion_velocity.is_zero_approx(),"a stationary body is not propelled by a caster or an arbitrary fallback direction")
	var effect:Node = runner.get_node("SurfaceAcceleration")
	var duplicate:Node2D = floor_tile(tile.cell_rect)
	SURFACE.touch(runner,duplicate)
	check(runner.get_node("SurfaceAcceleration") == effect and effect.surfaces.size() == 2,"overlapping tiles share one per-body controller")
	var before_bonus:float = effect.momentum.length()
	runner.global_position += Vector2(1,0)
	effect._physics_process(1.0/60.0)
	check(effect.momentum.length()-before_bonus <= 8.01,"overlapping surfaces do not double acceleration")
	var held:Vector2 = effect.momentum
	game.now_stop_state = true
	effect._physics_process(2.0)
	check(effect.momentum == held,"pause does not advance or expire surface momentum")
	game.now_stop_state = false
	runner.global_position = Vector2(400,40)
	for i:int in range(20): effect._physics_process(1.0/60.0)
	check(runner.surface_motion_velocity.is_zero_approx() and effect.is_queued_for_deletion(),"leaving ice removes acceleration and decays residual slide to zero")
	var guest:Node2D = fighter("NonAuthority",Vector2(40,60))
	guest.set_multiplayer_authority(2)
	check(SURFACE.touch(guest,tile) == null and guest.surface_motion_velocity.is_zero_approx(),"non-authority never simulates a duplicate ice acceleration controller")
	guest.queue_free()
	# Compare integrated acceleration budgets at two physics rates; move samples are explicit.
	var slow:Node2D = fighter("Rate30",Vector2(30,70))
	var fast:Node2D = fighter("Rate120",Vector2(30,90))
	var slow_effect:Node = SURFACE.touch(slow,tile)
	var fast_effect:Node = SURFACE.touch(fast,tile)
	slow_effect.set_physics_process(false)
	fast_effect.set_physics_process(false)
	for i:int in range(6):
		slow.global_position.x += 2.0
		slow_effect._physics_process(1.0/30.0)
	for i:int in range(24):
		fast.global_position.x += 0.5
		fast_effect._physics_process(1.0/120.0)
	check(absf(slow_effect.momentum.length()-fast_effect.momentum.length()) < 0.01,"ice acceleration integrates delta consistently at 30 and 120 Hz")
	# Clear ice before the unrelated contact mechanics section.
	tile.free()
	duplicate.free()
	for unit:Node in [runner,reverse,idle,slow,fast]: unit.free()
	source.global_position = Vector2(80,60)
	source.Damage = 48
	source.set_block(source.Block.IRON)
	source.set_process(false)
	var target:Node2D = fighter("CrushTarget",source._iron_bottom_rect().get_center()+Vector2(0,2))
	var above:Node2D = fighter("AboveTarget",source.global_position-Vector2(0,12))
	var side:Node2D = fighter("SideTarget",source.global_position+Vector2(25,0))
	await physics_frame
	check(is_equal_approx(source.IRON_IMPACT_MULT,0.4025*3.0) and is_equal_approx(source.AMETHYST_CONTACT_MULT,0.7*0.5) and is_equal_approx(source.SHARD.DAMAGE_MULT,0.4725*0.5),"iron is tripled from the current baseline; both approved purple reductions are retained")
	var hp:float = target.health
	source._iron_down_speed = 170.0
	source._iron_bottom_contacts()
	var initial:float = hp-target.health
	check(initial == floorf(source.attack_damage(source.IRON_IMPACT_MULT)),"iron first underside impact uses the increased current-attribute damage")
	var push:Node = knockback(target)
	check(push != null and push.direction.y > 0.0 and not push.lock_control_during_knockback,"initial underside hit applies shared downward knockback without permanently locking controls")
	if push != null: push.set_physics_process(false)
	hp = target.health
	for i:int in range(12): source._iron_bottom_contacts()
	check(target.health == hp,"multiple contact scans in the same tick cannot repeat impact or pressure")
	for i:int in range(4):
		source._clock += 0.25
		source._iron_bottom_contacts()
	var sustained:float = hp-target.health
	check(sustained == 0.0,"remaining underneath never generates sustained crush ticks")
	check(knockback(target) == push and push.distance <= 24.01,"continued contact does not renew or stack the original shared knockback")
	check(above.health == above.Max_health and side.health == side.Max_health,"iron top and side targets do not take underside pressure damage")
	var threats:Array = source.get_ai_attack_threats(null)
	check(threats.size() == 1 and threats[0].position == source._iron_bottom_rect().get_center() and is_equal_approx(threats[0].damage,floorf(source.attack_damage(source.IRON_IMPACT_MULT))),"falling threat geometry matches the underside and current speed-scaled damage")
	source._iron_down_speed = 0.0
	target.global_position += Vector2(40,0)
	hp = target.health
	source._clock += 3.0
	source._iron_bottom_contacts()
	check(target.health == hp,"leaving the underside stops pressure and cannot bank off-contact damage")
	target.global_position = source._iron_bottom_rect().get_center()+Vector2(0,2)
	source._iron_bottom_contacts()
	check(hp == target.health,"re-entry while stationary cannot farm iron impacts")
	source._slam_time = 0.1
	source._clock += 1.0
	hp = target.health
	source._iron_bottom_contacts()
	check(target.health == hp and source.get_ai_attack_threats(target).is_empty(),"rising jump phase has no underside pressure or threat")
	source._slam_time = -1.0
	source.dizziness = true
	source._iron_bottom_contacts()
	check(target.health == hp and source.get_ai_attack_threats(target).is_empty(),"stun suppresses iron damage and its damage warning")
	source.dizziness = false
	game.now_stop_state = true
	source._iron_bottom_contacts()
	check(target.health == hp,"paused iron cannot settle another crush tick")
	game.now_stop_state = false
	source.set_multiplayer_authority(2)
	source._iron_bottom_contacts()
	check(target.health == hp,"guest-side iron cannot damage or renew knockback")
	source.set_multiplayer_authority(1)
	source.Damage = 96
	source._iron_down_speed = 170.0
	source._slam_hits.clear()
	source._iron_bottom_contacts()
	check(hp-target.health == floorf(96.0*source.IRON_IMPACT_MULT),"changed attack attributes scale the new iron damage, rather than a fixed HP constant")
	source.set_block(source.Block.AMETHYST)
	check(source._slam_hits.is_empty(),"changing form clears iron pressure history")
	var analyzer:Node2D = load("res://scripts/training/combat_threat_analyzer.gd").new()
	world.add_child(analyzer)
	analyzer.set_physics_process(false)
	game.Game_Settings.Training_Debug_Mode = true
	source.set_block(source.Block.IRON)
	source._iron_down_speed = 170.0
	analyzer._physics_process(0.1)
	var found:bool = false
	for entry:Dictionary in analyzer._debug_threats:
		if entry.get("kind","") == "sulfur_iron_bottom": found = true
	check(found,"real settings threat display discovers downward iron impact")
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.1)
	check(not analyzer.visible,"turning threat display off removes the indicator")
	world.queue_free()
	await process_frame
	await create_timer(0.35,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("SULFUR_BALANCE: %d checks / %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
