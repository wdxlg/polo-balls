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
func run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(-500,0),"A")
	var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(500,0),"A")
	var ally = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(490,0),"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(520,0),"B")
	var third = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(530,0),"B")
	await physics_frame
	check(sheep.health == 520 and sheep.wool == 3,"sheep initial profile")
	check(boat.health == 460 and boat.Can_Skill,"boat boarding skill enabled")
	check(not sheep.has_method("_baa"),"no damaging baa")
	var original_mask:int = ally.collision_mask
	var original_layer:int = ally.collision_layer
	var original_can_attack:bool = ally.Can_Attack
	var original_can_skill:bool = ally.Can_Skill
	var original_speed:float = ally.Speed
	boat._board_left = 0
	boat.Skill()
	check(boat.passengers.size() == 2,"skill fills two seats")
	check(boat.passengers.has(ally) and boat.passengers.has(enemy),"nearest ally and enemy both board")
	check(not boat.board_unit(third),"third passenger rejected")
	check(ally.is_transport_mounted() and enemy.is_transport_mounted(),"both constrained")
	check(ally.Team == "A" and enemy.Team == "B","teams preserved")
	check(ally.Can_Attack == original_can_attack and ally.Can_Skill == original_can_skill,"offensive controls preserved")
	check(ally.Speed == original_speed,"speed stat not overwritten")
	check(ally.collision_mask == 0 and ally.self_hurtbox.collision_layer != 0,"body disabled hurtbox alive")
	boat.global_position += Vector2(50,30)
	boat.facing = Vector2.DOWN
	boat.visual_mob()
	ally.apply_transport_pose()
	enemy.apply_transport_pose()
	check(ally.global_position.is_equal_approx(boat.seat_position(0)),"front seat follows boat")
	check(enemy.global_position.is_equal_approx(boat.seat_position(1)),"rear seat follows boat")
	check(ally.direction == boat.facing and enemy.direction == boat.facing,"direction equals boat")
	check(absf(angle_difference(ally.graphics.global_rotation,boat.graphics.global_rotation)) < 0.001,"render facing equals boat")
	var seated:Vector2 = ally.global_position
	ally.direction = Vector2.LEFT
	ally.move(999,0.1)
	check(ally.global_position == seated,"normal locomotion suppressed")
	ally.global_position += Vector2(80,80)
	ally.apply_transport_pose()
	check(ally.global_position == seated,"custom direct displacement corrected")
	var before:int = enemy.health
	var result:Dictionary = ally._damage_area(enemy.global_position,30,20,0,0)
	check(int(result.hits) >= 1 and enemy.health < before,"mounted enemy remains damageable and passenger attacks")
	var boat_before:int = boat.health
	before = ally.health
	enemy._damage_area(boat.global_position,40,10,0,0)
	check(boat.health < boat_before and ally.health < before,"enemy passenger can attack boat and ally")
	check(boat._board_left > 0,"boarding cooldown used")
	boat.release_all()
	check(boat.passengers.is_empty() and not ally.is_transport_mounted(),"release clears seats")
	check(ally.collision_mask == original_mask and ally.collision_layer == original_layer,"release restores collisions")
	check(ally.Can_Attack == original_can_attack and ally.Speed == original_speed,"release preserves stats")
	ally.global_position = boat.global_position+Vector2(15,0)
	check(boat.board_unit(ally),"reboard after release")
	ally.health = 0
	boat._prune_passengers()
	check(boat.passengers.is_empty() and not ally.is_transport_mounted(),"dead rider frees seat")
	enemy.global_position = boat.global_position+Vector2(15,0)
	check(boat.board_unit(enemy),"enemy boards alone")
	boat.health = 0
	enemy.apply_transport_pose()
	check(not enemy.is_transport_mounted() and enemy.collision_mask != 0,"boat death releases rider")
	# No remote grab through a solid wall.
	var boat2 = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(900,0),"A")
	third.global_position = Vector2(932,0)
	var wall:StaticBody2D = StaticBody2D.new()
	var cs:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(4,100)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = Vector2(916,0)
	await physics_frame
	check(not boat2.board_unit(third),"wall blocks boarding")
	check(not boat2.board_unit(boat),"nested boat prohibited")
	wall.queue_free()
	await physics_frame
	third.global_position = Vector2(915,0)
	check(boat2.board_unit(third),"board before carrier removal")
	boat2.queue_free()
	await process_frame
	check(not third.is_transport_mounted() and third.collision_mask != 0,"carrier removal restores rider")
	# Sheep has a windup and fixed charge line; grazing restores wool even at full HP.
	for unit in [enemy,third]: unit.global_position = Vector2(1500,800)
	sheep._begin_charge(sheep.global_position+Vector2(150,0))
	check(sheep.ram_state == sheep.RamState.WINDUP,"telegraphed charge")
	var point:Vector2 = sheep.global_position
	sheep.move(sheep.Speed,0.1)
	check(sheep.global_position.x < point.x,"windup retreats")
	var locked:Vector2 = sheep._charge_dir
	sheep.step_mob(sheep.ram_windup+0.01)
	check(sheep.ram_state == sheep.RamState.CHARGE and sheep._charge_dir == locked,"windup transitions to locked dash")
	enemy.health = enemy.Max_health
	enemy.global_position = sheep.global_position+Vector2(40,0)
	await physics_frame
	before = enemy.health
	for i:int in range(30):
		if sheep.ram_state != sheep.RamState.CHARGE: break
		sheep.move(sheep.Speed,1.0/60.0)
	check(enemy.health < before,"charge actual contact deals damage")
	check(sheep.wool == 3,"charge no longer consumes defensive wool")
	check(sheep.ram_state == sheep.RamState.CHARGE,"unit contact preserves charge")
	before = enemy.health
	sheep.move(sheep.Speed,0.1)
	check(enemy.health == before,"no repeated contact damage")
	sheep.wool = 1
	sheep._charge_speed = 500.0
	sheep._finish_charge(true)
	check(sheep.wool == 1 and sheep.dizziness,"wall crash no longer consumes defensive wool")
	sheep._charge_speed = 500.0
	sheep._finish_charge(true)
	check(sheep.dizziness,"bare sheep wall stun")
	# Wait only for the isolated stun controller to expire, not the whole scene AI.
	for child:Node in sheep.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("knockback_effect.gd"):
			child.queue_free()
	await process_frame
	sheep.dizziness = false
	enemy.global_position = Vector2(1500,800)
	sheep.health = sheep.Max_health
	sheep.wool = 0
	sheep._since_hurt = 10
	sheep.ram_state = sheep.RamState.ROAM
	sheep.step_mob(0.1)
	check(sheep.ram_state != sheep.RamState.GRAZE,"missing wool alone cannot trigger grazing")
	var ram_boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(2000,0),"A")
	var ram_target = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(2038,0),"B")
	ram_boat.facing = Vector2.RIGHT
	ram_boat._forward_speed = 180.0
	await physics_frame
	before = ram_target.health
	ram_boat.move(ram_boat.Speed,0.15)
	check(ram_target.health < before,"boat bow physical ram damages")
	check(ram_boat._ram_cd.has(ram_target.get_instance_id()),"ram per-target cooldown")
	var wall_boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(2500,0),"A")
	wall_boat.facing = Vector2.RIGHT
	wall_boat.player_control_peer_id = 1
	wall_boat.player_control_direction = Vector2.RIGHT
	wall_boat._forward_speed = 200.0
	var solid:StaticBody2D = StaticBody2D.new()
	var collider:CollisionShape2D = CollisionShape2D.new()
	var rect:RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(5,120)
	collider.shape = rect
	solid.add_child(collider)
	arena.add_child(solid)
	solid.global_position = Vector2(2536,0)
	await physics_frame
	before = wall_boat.health
	wall_boat.move(wall_boat.Speed,0.20)
	check(wall_boat.health == before,"wall impact no longer hurts boat")
	check(wall_boat.facing.x > 0.99 and wall_boat._forward_speed < 100,"wall brakes boat without snapping heading")
	wall_boat.global_position = Vector2(2400,300)
	wall_boat.facing = Vector2.RIGHT
	wall_boat.player_control_direction = Vector2.DOWN
	wall_boat._forward_speed = 0
	wall_boat.move(wall_boat.Speed,0.1)
	check(wall_boat._forward_speed > 0 and wall_boat._forward_speed < 30,"gradual acceleration")
	check(wall_boat.facing.angle() > 0 and wall_boat.facing.angle() < 0.2,"limited steering")
	wall_boat.Speed = 110
	wall_boat.move(wall_boat.Speed,1.0)
	check(wall_boat._forward_speed <= 110.01,"boat obeys speed debuffs")
	var bare = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(2500,0),"A")
	bare.wool = 0
	bare.Damage_reduction = 0
	bare._begin_charge(Vector2(2600,0))
	bare.ram_state = bare.RamState.CHARGE
	bare._charge_speed = 520
	await physics_frame
	before = bare.health
	bare.move(bare.Speed,0.15)
	check(bare.health < before and bare.dizziness,"bare sheep real wall damage and stun")
	var carrier = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(3500,0),"A")
	var sheep_rider = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(3510,0),"A")
	var close_enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(3532,0),"B")
	carrier.facing = Vector2.RIGHT
	carrier.board_unit(sheep_rider)
	before = close_enemy.health
	point = sheep_rider.global_position
	sheep_rider.step_mob(0.1)
	check(close_enemy.health < before,"mounted sheep retains stationary headbutt")
	check(sheep_rider.global_position == point,"mounted sheep cannot charge off boat")
	print("SHEEP_BOAT_REWORK_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
