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
	create_timer(35).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2.ZERO,"A")
	boat.Can_Skill = false
	boat.facing = Vector2.RIGHT
	var target = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(350,60),"B")
	var hp:int = target.health
	var max_speed:float = 0
	await physics_frame
	for tick:int in range(1200):
		boat.step_mob(1.0/60)
		boat.move(boat.Speed,1.0/60)
		max_speed = maxf(max_speed,boat._forward_speed)
		if target.health<hp: break
	check(target.health<hp,"autonomous steering actually reaches and hits external enemy")
	check(max_speed>boat.ram_min_speed*1.5,"AI builds meaningful impact speed")
	boat.global_position = Vector2(1000,0)
	boat.facing = Vector2.RIGHT
	boat._forward_speed = 0
	boat._angular_speed = 0
	target.global_position = boat.global_position+Vector2(15,0)
	check(boat.board_unit(target),"enemy loaded for autonomous crash test")
	wall_at(Vector2(1400,0))
	await physics_frame
	hp = target.health
	var ship_hp:int = boat.health
	# 巡航 AI 现在会在阻尼区收油轻触墙（不再必然硬撞），触墙或撞墙都算找到墙。
	var contact_seen:bool = false
	for tick:int in range(1200):
		boat.step_mob(1.0/60)
		boat.move(boat.Speed,1.0/60)
		if float(boat._wall_contact_left) > 0.0: contact_seen = true
		if contact_seen or target.health<hp: break
	check(contact_seen or target.health<hp,"without external targets AI finds and contacts wall")
	check(boat.health==ship_hp and boat.global_position.x>1350,"wall-seeking has actual movement and no self damage")
	var stuck_point:Vector2 = boat.global_position
	var furthest:float = 0.0
	for tick:int in range(600):
		boat.step_mob(1.0/60)
		boat.move(boat.Speed,1.0/60)
		furthest = maxf(furthest,boat.global_position.distance_to(stuck_point))
	check(furthest>90,"boat escapes after wall crash instead of freezing at wall")
	var proj = spawn("res://scenes/shooter/子弹.tscn",boat.global_position,"B")
	proj.Master = target
	check(boat.source_is_onboard(proj),"onboard projectile source traced through Master")
	var stun = target.apply_knockback(Vector2.ZERO,0,0,0,1,{"source":proj})
	check(stun==null and not target.dizziness,"onboard projectile stun rejected")
	var ally = spawn("res://scenes/characters/我的世界/重锤.tscn",boat.global_position+Vector2(-15,0),"A")
	check(boat.board_unit(ally),"friendly rider shares ship with hostile rider")
	root.get_node("Game").Game_Settings.Have_Team_Damage = true
	var ally_hp:int = ally.health
	boat._crash_cd = 0
	boat._wall_crash(320)
	check(ally.health==ally_hp,"wall impact spares friendly riders even with friendly fire enabled")
	print("CAR_BOAT_AI_RESULT checks=",checks," failures=",failures," maximum_speed=",max_speed)
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
