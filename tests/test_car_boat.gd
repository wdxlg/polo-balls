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
	root.get_node("Game").now_stop_state = false
	root.get_node("Game").Game_Settings.Have_Team_Damage = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2.ZERO,"A")
	boat._integrate_drive(1,0,0.1)
	check(boat._forward_speed>0 and boat._forward_speed<20,"forward accelerates instead of snapping")
	for i:int in range(240): boat._integrate_drive(1,0,1.0/60)
	check(is_equal_approx(boat._forward_speed,boat.cruise_speed),"straight driving reaches maximum speed")
	var movement:Vector2 = boat._integrate_drive(-1,0,0.1)
	check(boat._forward_speed>0 and movement.x>0,"reverse command first cancels forward momentum")
	for i:int in range(180): boat._integrate_drive(-1,0,1.0/60)
	check(is_equal_approx(boat._forward_speed,-boat.reverse_speed),"reverse is slowest and capped")
	boat._forward_speed = boat.cruise_speed
	boat.facing = Vector2.RIGHT
	boat._integrate_drive(1,1,0.1)
	check(boat.facing.angle()>0 and boat.facing.angle()<0.1,"turning starts slowly")
	for i:int in range(240): boat._integrate_drive(1,1,1.0/60)
	check(is_equal_approx(boat._forward_speed,boat.turn_speed_floor),"turn braking has nonzero speed floor")
	check(absf(boat._angular_speed)<=boat.turn_rate,"bounded angular velocity")
	boat.facing = Vector2.RIGHT
	boat._angular_speed = 0
	boat._forward_speed = 0
	var foe = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(60,0),"B")
	var hp:int = foe.health
	boat._ram_path(Vector2.ZERO,Vector2(50,0),80)
	check(foe.health==hp,"bow cannot damage below threshold")
	boat._ram_path(Vector2.ZERO,Vector2(50,0),200)
	check(foe.health<hp,"fast bow sweep damages actual front target")
	check(boat.ram_profile(320).damage>boat.ram_profile(100).damage and boat.ram_profile(320).distance<=12,"speed increases damage but knockback remains small")
	boat._ram_cd.clear()
	foe.global_position = Vector2(-20,0)
	hp = foe.health
	boat._ram_path(Vector2.ZERO,Vector2.ZERO,320)
	check(foe.health==hp,"stern cannot ram")
	foe.global_position = Vector2(0,boat._body_radius(boat)+9)
	boat._paddle_attack(Vector2.ZERO,Vector2.RIGHT,0)
	check(foe.health==hp,"stationary paddles cause no damage")
	boat._paddle_attack(Vector2.ZERO,Vector2.RIGHT,0.3)
	var weak_damage:int = hp-foe.health
	check(weak_damage>0,"turning side paddle damages")
	boat._paddle_hits.clear()
	hp = foe.health
	boat._paddle_attack(Vector2.ZERO,Vector2.RIGHT,0.9)
	check(hp-foe.health>weak_damage,"faster rotation increases paddle damage")
	foe.global_position = Vector2(900,900)
	var ally = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(15,0),"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(-15,0),"B")
	var attack_flag:bool = enemy.Can_Attack
	var skill_flag:bool = enemy.Can_Skill
	check(boat.board_unit(ally) and boat.board_unit(enemy),"mixed teams fill front and rear seats")
	check(ally.global_position==boat.seat_position(0) and enemy.global_position==boat.seat_position(1),"distinct front and rear positions")
	var healths:Array[int] = [boat.health,ally.health,enemy.health]
	boat.receive_positional_damage(60,boat.global_position,false,foe)
	check(healths[0]-boat.health==20 and healths[1]-ally.health==20 and healths[2]-enemy.health==20,"external damage evenly shared among boat and riders")
	ally.receive_positional_damage(60,ally.global_position,false,foe)
	enemy.receive_positional_damage(60,enemy.global_position,false,foe)
	check(healths[0]-boat.health==20 and healths[1]-ally.health==20 and healths[2]-enemy.health==20,"one external area strike not tripled by overlapping seats")
	boat._shared_hits.clear()
	healths = [boat.health,ally.health,enemy.health]
	enemy.receive_positional_damage(30,enemy.global_position,false,foe)
	check(healths[0]-boat.health==10 and healths[1]-ally.health==10 and healths[2]-enemy.health==10,"external hit on passenger also shares")
	healths = [boat.health,ally.health,enemy.health]
	ally.receive_positional_damage(12,ally.global_position,false,enemy)
	check(ally.health==healths[1]-12 and boat.health==healths[0] and enemy.health==healths[2],"onboard attacks remain normal, not shared")
	boat._shared_hits.clear()
	healths = [boat.health,ally.health,enemy.health]
	ally.receive_spatial_damage(60,{"point":ally.global_position,"source":foe},true,true)
	check(healths[0]-boat.health==20 and healths[1]-ally.health==20 and healths[2]-enemy.health==20,"raw spatial damage shares across all three")
	boat._shared_hits.clear()
	enemy.receive_positional_damage(1,enemy.global_position,false,ally)
	check(enemy.apply_stun(1)==null,"legacy stun after onboard hit inherits its source context")
	var internal = enemy.apply_knockback(Vector2.UP,100,300,0,1,{"source":ally})
	check(internal==null and not enemy.dizziness,"onboard knockback and associated stun rejected")
	var stun = enemy.apply_knockback(Vector2.ZERO,0,0,0,1,{"source":boat})
	check(stun==null and not enemy.dizziness,"pure stun from boat rejected")
	var external = enemy.apply_knockback(Vector2.UP,50,200,0,0.2,{"source":foe})
	check(external!=null and enemy.dizziness,"outside control still applies")
	external._finish(false)
	var seat:Vector2 = enemy.global_position
	enemy.move(enemy.Speed,1)
	check(enemy.global_position==seat,"enemy passenger cannot move off seat")
	check(enemy.Can_Attack==attack_flag and enemy.Can_Skill==skill_flag,"boarding does not disable attack or skill")
	healths = [boat.health,ally.health,enemy.health]
	boat._wall_crash(80)
	check(enemy.health==healths[2],"low speed wall contact causes no passenger damage")
	boat._wall_crash(180)
	var low_crash:int = healths[2]-enemy.health
	check(low_crash>0 and boat.health==healths[0] and ally.health==healths[1],"wall crash hurts only enemy passenger")
	boat._crash_cd = 0
	hp = enemy.health
	boat._wall_crash(320)
	check(hp-enemy.health>low_crash,"wall damage increases with speed")
	ally.health = 0
	boat._prune_passengers()
	check(boat.passengers.size()==1 and boat.passengers[0]==enemy and enemy.get_transport_rider().slot==0,"rear passenger advances after front dies")
	foe.health = 0
	check(boat._nearest_outside_enemy()==null and boat._has_enemy_passenger(),"only carried enemy triggers wall-seeking condition")
	# Physical wall collision: no heading reversal or friendly/self damage.
	boat.global_position = Vector2(2000,0)
	boat.facing = Vector2.RIGHT
	boat._angular_speed = 0
	boat.player_control_peer_id = 1
	boat.player_control_direction = Vector2.RIGHT
	boat._forward_speed = 300
	boat._crash_cd = 0
	wall_at(Vector2(2050,0))
	await physics_frame
	boat._wall_heading = boat._pick_wall_heading()
	hp = enemy.health
	var ship_hp:int = boat.health
	boat.move(boat.Speed,0.2)
	check(enemy.health<hp and boat.health==ship_hp,"real wall collision damages enemy rider only")
	check(boat.facing.x>0.99 and boat._forward_speed<100,"wall brakes without instant turning")
	check(boat._reverse_left>0,"wall collision schedules slow reversing escape")
	check(boat._body_radius(boat)<=15 and boat._body_radius(boat)>=8,"boat effective footprint reduced")
	check(boat.image.scale.x<=1.6,"boat sprite scale reduced")
	var FRAMES8 = load("res://Images/characters/我的世界/new6/boat_frames8.tres")
	boat._rowing = false
	boat._view_clock = 0
	boat.facing = Vector2.from_angle(0.5)
	boat.visual_mob()
	check(boat.image.texture==FRAMES8.get_frame_texture(&"d1_idle",0) and is_zero_approx(boat.graphics.rotation),"baked eight-way idle frames without runtime rotation")
	boat.facing = Vector2.from_angle(-0.5)
	boat.visual_mob()
	check(boat.image.texture==FRAMES8.get_frame_texture(&"d7_idle",0),"negative headings wrap to eighth baked direction")
	boat._rowing = true
	boat.facing = Vector2.from_angle(PI*0.5)
	boat.visual_mob()
	check(boat.image.texture==FRAMES8.get_frame_texture(&"d2_row",0),"row animation per direction")
	print("CAR_BOAT_RESULT checks=",checks," failures=",failures)
	await process_frame
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
