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
	create_timer(30).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.get_node("Game").Game_Settings.Have_Team_Damage = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(60,0),"B")
	var ally = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(125,0),"A")
	var enemy2 = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(230,0),"B")
	wall_at(Vector2(700,0))
	await physics_frame
	sheep._begin_charge(enemy.global_position,enemy)
	sheep._launch_charge()
	var heading:Vector2 = sheep._charge_dir
	var hp:int = enemy.health
	var hp2:int = enemy2.health
	var friend_hp:int = ally.health
	var damage_events:int = 0
	var second_events:int = 0
	var first_slow:bool = false
	var continued:bool = false
	var ally_slow:bool = false
	var past_old_limit:bool = false
	for i:int in range(240):
		if sheep.ram_state != sheep.RamState.CHARGE: break
		var speed:float = sheep._charge_speed
		var had_ally:bool = sheep._charge_contacts.has(ally.get_instance_id())
		sheep.move(sheep.Speed,1.0/60.0)
		if enemy.health < hp:
			damage_events += 1
			first_slow = sheep._charge_speed < speed
			continued = sheep.ram_state == sheep.RamState.CHARGE
			hp = enemy.health
		if enemy2.health < hp2:
			second_events += 1
			hp2 = enemy2.health
		if not had_ally and sheep._charge_contacts.has(ally.get_instance_id()): ally_slow = sheep._charge_speed < speed
		if sheep.global_position.x > 400 and sheep.ram_state == sheep.RamState.CHARGE: past_old_limit = true
	check(damage_events==1,"first target damaged once per charge")
	check(first_slow and continued,"enemy contact slows sheep but preserves charge")
	check(second_events==1,"same charge continues into second enemy")
	check(ally.health==friend_hp and ally_slow,"ally contact slows without friendly damage")
	check(past_old_limit,"no former distance-limit stop")
	check(sheep.global_position.x > 670 and sheep.global_position.x < 700,"actually travels through units and reaches wall")
	check(sheep.ram_state == sheep.RamState.RECOVER and sheep.dizziness,"only real wall contact ends charge with stun")
	check(sheep._charge_dir==heading,"unit impacts do not steer toward moving targets")
	check(sheep._charge_exceptions.is_empty() and sheep.get_collision_exceptions().is_empty(),"wall finish restores all collision exceptions")
	# Open field: no implicit timeout/distance stop, and renewed charges can hit again.
	sheep.global_position = Vector2(1000,500)
	for child:Node in sheep.get_children():
		if child.has_method("replace_with_hit"):
			child._finish(false)
	sheep.dizziness = false
	sheep._begin_charge(Vector2(1100,500))
	sheep._launch_charge()
	for i:int in range(180): sheep.move(sheep.Speed,1.0/60.0)
	check(sheep.ram_state==sheep.RamState.CHARGE and sheep._charge_distance > 1000,"open-field charge continues beyond three seconds")
	check(sheep._charge_speed > 0,"charge retains forward motion")
	sheep._finish_charge(false)
	sheep.global_position = Vector2(40,0)
	sheep._begin_charge(Vector2(100,0))
	sheep._launch_charge()
	hp = enemy.health
	sheep._hit_charge_path(sheep.global_position,sheep.global_position)
	check(enemy.health < hp,"new charge can hit prior target again")
	sheep._begin_grazing()
	check(sheep.get_collision_exceptions().is_empty(),"external state cancellation restores collisions")
	# Same enemy, same charge, repeated physical separation and recontact.
	sheep.global_position = Vector2(1000,1000)
	enemy.global_position = Vector2(1060,1000)
	sheep._begin_charge(Vector2(2000,1000))
	sheep._launch_charge()
	for cycle:int in range(3):
		hp = enemy.health
		for tick:int in range(90):
			sheep.move(sheep.Speed,1.0/60.0)
			if enemy.health < hp: break
		check(enemy.health < hp and sheep.ram_state==sheep.RamState.CHARGE,"same charge hits same enemy again "+str(cycle))
		var hp_after:int = enemy.health
		check(not sheep._charge_touch(enemy,sheep.global_position) and enemy.health==hp_after,"overlap does not duplicate hit")
		enemy.global_position = sheep.global_position+Vector2(100,0)
		sheep.move(sheep.Speed,1.0/60.0)
		check(not sheep._charge_contacts.has(enemy.get_instance_id()) and not sheep.get_collision_exceptions().has(enemy),"separation restores collision")
	sheep._finish_charge(false)
	sheep.global_position = Vector2(3000,2000)
	sheep.wool = 3
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	check(sheep._begin_wool(),"direct wool defence begins")
	sheep.visual_mob()
	check(is_equal_approx(sheep._wool_visual.scale.x,1.35),"wool immediately enlarged without compression")
	var fixed_pose:Transform2D = sheep._wool_fixed_visual.transform
	var samples:Array[float] = []
	for age:float in [0.07,0.15,0.30,0.45]:
		sheep._wool_elapsed = age
		sheep.visual_mob()
		samples.append(sheep._wool_visual.scale.x)
		check(sheep._wool_fixed_visual.transform.is_equal_approx(fixed_pose),"head and legs stay fixed")
	check(samples[0]<1.35 and samples[1]<1 and samples[2]>1 and is_equal_approx(samples[3],1),"wool damped elastic shrink returns exactly to normal")
	sheep._step_wool(0.01)
	check(sheep._wool_phase==0 and sheep.wool==2,"one layer consumed and pulse ends")
	# A destructible wall implemented as ball is still an obstacle.
	var wall_ball = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(2000,0),"B")
	wall_ball.set_meta("mc_wall",true)
	check(sheep._charge_obstacle(wall_ball),"ball-based obstacle recognized")
	sheep.global_position = Vector2(1940,0)
	sheep._begin_charge(Vector2(2100,0))
	sheep._launch_charge()
	await physics_frame
	for i:int in range(60):
		if sheep.ram_state != sheep.RamState.CHARGE: break
		sheep.move(sheep.Speed,1.0/60.0)
	check(sheep.ram_state == sheep.RamState.RECOVER and sheep.global_position.x < 2000,"destructible wall physically stops charge")
	print("SHEEP_CONTINUOUS_CHARGE_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
