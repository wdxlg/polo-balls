extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("REWORK_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func spawn(path:String,point:Vector2,team:String):
	var packed:PackedScene = load(path)
	if packed == null:
		push_error("Scene unavailable: "+path)
		quit(2)
		return null
	var actor = packed.instantiate()
	actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in actor.find_children("*","CollisionObject2D",true,false):
		(child as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(actor,true)
	return actor
func wall_at(point:Vector2) -> StaticBody2D:
	var wall:StaticBody2D = StaticBody2D.new()
	var cs:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(5,200)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = point
	return wall
func effect_for(actor):
	for child in actor.get_children():
		if child.has_method("replace_with_hit") and child.is_active_effect(): return child
	return null
func run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(130,0),"B")
	await physics_frame
	sheep._begin_charge(enemy.global_position,enemy)
	var old:Vector2 = sheep.global_position
	for i:int in range(20): sheep.move(sheep.Speed,1.0/60.0)
	check(sheep.global_position.x < old.x-10,"real backward windup")
	check(sheep.facing.x > 0,"retreat still faces enemy")
	enemy.global_position += Vector2(0,30)
	sheep.step_mob(sheep.ram_windup+0.01)
	check(sheep._aim_point == enemy.global_position,"snapshot position at launch")
	check(sheep._charge_speed == sheep.Speed,"starts at default speed")
	var aim:Vector2 = sheep._aim_point
	var locked:Vector2 = sheep._charge_dir
	enemy.global_position = Vector2(1000,1000)
	var previous:float = sheep._charge_speed
	var descending:bool = true
	for i:int in range(90):
		if sheep.ram_state != sheep.RamState.CHARGE: break
		sheep.move(sheep.Speed,1.0/60.0)
		if sheep.ram_state == sheep.RamState.CHARGE and sheep._charge_speed < previous: descending = false
		previous = sheep._charge_speed
	check(descending,"speed rises during charge")
	check(sheep._aim_point == aim and sheep._charge_dir == locked,"no homing after launch")
	check(sheep.ram_state == sheep.RamState.CHARGE,"miss continues in open space")
	check(enemy.health == enemy.Max_health,"dodged enemy is not hit remotely")
	var slow:Dictionary = sheep.impact_profile(100)
	var fast:Dictionary = sheep.impact_profile(500)
	check(fast.damage > slow.damage,"damage scales with speed")
	check(fast.distance > slow.distance and fast.speed > slow.speed,"knockback distance and speed scale")
	check(fast.wall_damage > slow.wall_damage,"secondary damage scales with hit strength")
	var back = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(2000,0),"A")
	wall_at(Vector2(1975,0))
	await physics_frame
	back._begin_charge(Vector2(2100,0))
	for i:int in range(40): back.move(back.Speed,1.0/60.0)
	check(back.global_position.x > 1985,"backstep respects actual wall")
	back.step_mob(0.6)
	check(back.ram_state == back.RamState.CHARGE,"blocked backstep still launches")
	var damage_values:Array[int] = []
	var knock_values:Array[float] = []
	for index:int in range(2):
		var base:float = 4000.0+1000.0*index
		var attacker = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(base,0),"A")
		var victim = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(base+(35 if index == 0 else 115),0),"B")
		wall_at(victim.global_position+Vector2(65,0))
		await physics_frame
		attacker._begin_charge(victim.global_position,victim)
		attacker._launch_charge()
		var hp:int = victim.health
		for i:int in range(90):
			if attacker.ram_state != attacker.RamState.CHARGE or victim.health < hp: break
			attacker.move(attacker.Speed,1.0/60.0)
		damage_values.append(hp-victim.health)
		var effect = effect_for(victim)
		check(effect != null,"actual hit installs knockback "+str(index))
		if effect == null: continue
		knock_values.append(effect.distance)
		check(effect.wall_bounce_strength > 0 and effect.collision_damage_wall_only,"wall-only damage and rebound configured")
		hp = victim.health
		var bounced:bool = false
		var reversed:bool = false
		var damage_events:int = 0
		var last_hp:int = hp
		for i:int in range(100):
			await physics_frame
			if not is_instance_valid(effect) or not effect.is_active_effect(): break
			var x:float = victim.global_position.x
			victim.stand(1.0/60.0)
			effect._physics_process(1.0/60.0)
			if effect._wall_bounces > 0: bounced = true
			if bounced and victim.global_position.x < x-0.1: reversed = true
			if victim.health < last_hp: damage_events += 1
			last_hp = victim.health
		check(bounced,"real solid wall produces bounce "+str(index))
		check(reversed,"victim actually travels away from wall "+str(index))
		check(victim.health < hp,"actual wall impact causes secondary damage "+str(index))
		check(damage_events == 1,"no per-frame wall damage spam "+str(index))
	check(damage_values.size() == 2 and damage_values[0] < damage_values[1],"accelerated later hit stronger than early hit")
	check(knock_values.size() == 2 and knock_values[0] < knock_values[1],"accelerated later hit has longer knockback")
	print("SHEEP_RETREAT_BOUNCE_RESULT checks=",checks," failures=",failures," damage=",damage_values," knockback=",knock_values)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
