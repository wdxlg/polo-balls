extends SceneTree

const BOAT:String = "res://scenes/characters/我的世界/木船.tscn"
const PISTON:String = "res://scenes/characters/我的世界/粘性活塞.tscn"
const ACTOR:String = "res://scenes/characters/我的世界/重锤.tscn"
var HOLD:Script
var PUSH:Script
var U:Script
const DT:float = 1.0/60.0
var arena:Node2D
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("BOAT_ONBOARD_CONTROL_FAIL ",label)

func spawn(path:String,point:Vector2,team:String):
	var packed:PackedScene = load(path)
	var actor = packed.instantiate()
	actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in actor.find_children("*","CollisionObject2D",true,false):
		(child as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(actor,true)
	return actor

func clear_controls(actor) -> void:
	for effect:Node in actor.get_children():
		if effect.get_script() == HOLD:
			effect.free()
		elif effect.has_method("replace_with_hit"):
			effect._finish(false)

func reset_stroke(piston) -> void:
	piston.phase = 0.0
	piston.charge = 0.0
	piston.extension = piston.REST_EXTENSION
	piston._hit_ids.clear()
	piston._hold_ids.clear()
	piston.facing = Vector2.RIGHT
	piston.direction = Vector2.RIGHT

func wall_at(point:Vector2) -> void:
	var wall:StaticBody2D = StaticBody2D.new()
	var shape:CollisionShape2D = CollisionShape2D.new()
	var rect:RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(5,200)
	shape.shape = rect
	wall.add_child(shape)
	arena.add_child(wall)
	wall.global_position = point

func run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	# Load after autoloads are initialized, as in the other headless tests.
	HOLD = load("res://scripts/characters/我的世界/new5/sticky_hold.gd")
	PUSH = load("res://scripts/characters/我的世界/new5/piston_push.gd")
	U = load("res://scripts/characters/我的世界/new5/utils.gd")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var boat = spawn(BOAT,Vector2.ZERO,"A")
	var ally = spawn(ACTOR,Vector2(10,0),"A")
	var piston = spawn(PISTON,Vector2(-10,0),"B")
	var outside = spawn(PISTON,Vector2(500,300),"B")
	await physics_frame
	check(boat.board_unit(ally) and boat.board_unit(piston),"mixed-team riders occupy both seats")
	var layer:int = boat.collision_layer
	var mask:int = boat.collision_mask
	var knockback = boat.apply_knockback(Vector2.UP,100,300,0,1,{"source":piston})
	check(knockback == null and not boat.dizziness,"boat rejects onboard knockback and stun")
	if knockback != null: knockback._finish(false)
	var stun = boat.apply_stun(1,piston)
	check(stun == null and not boat.dizziness,"boat rejects pure onboard stun")
	if stun != null: stun._finish(false)
	boat.receive_positional_damage(1,boat.global_position,false,piston)
	stun = boat.apply_stun(1)
	check(stun == null,"legacy source-less stun uses onboard damage source")
	if stun != null: stun._finish(false)
	var projectile:Node2D = Node2D.new()
	projectile.set_meta("combat_source",piston)
	arena.add_child(projectile)
	stun = boat.apply_stun(1,projectile)
	check(stun == null,"onboard projectile provenance is rejected")
	if stun != null: stun._finish(false)
	stun = boat.apply_stun(1,piston.weapon)
	check(stun == null,"onboard child-node provenance is rejected")
	if stun != null: stun._finish(false)
	await process_frame

	# The actual rear-seat piston stroke used to attach the hull to its own rider.
	var origin:Vector2 = boat.global_position
	var hp:int = boat.health
	reset_stroke(piston)
	piston.step_mob(0.18)
	check(boat.health < hp,"onboard piston still damages hull")
	check(not boat.has_meta("mc_sticky_hold"),"onboard stroke cannot capture hull")
	check(not ally.has_meta("mc_sticky_hold"),"onboard stroke cannot capture another rider")
	for i:int in range(20):
		for effect:Node in boat.get_children():
			if effect.get_script() == HOLD: effect._physics_process(DT)
		piston.apply_transport_pose()
		ally.apply_transport_pose()
	var drift:float = origin.distance_to(boat.global_position)
	print("BOAT_ONBOARD_FEEDBACK_DRIFT ",drift)
	check(drift < 0.001,"seat/anchor feedback cannot move stationary boat")
	check(boat.collision_layer == layer and boat.collision_mask == mask,"onboard control never disables hull collisions")
	check(not boat.dizziness and not boat.has_meta("submission_allow_map_escape"),"no onboard control lock or map-escape flag")
	clear_controls(boat)
	clear_controls(ally)
	boat.global_position = origin
	piston.apply_transport_pose()
	ally.apply_transport_pose()
	await process_frame

	# Direct effect construction must obey the same gate, including derived pushes.
	for target in [boat,ally]:
		var hold = HOLD.new()
		hold.target = target
		hold.source = piston
		target.add_child(hold)
		check(not hold.acquired,"raw sticky hold rejected on hull/rider")
		hold.free()
		var push = PUSH.new()
		push.target = target
		push.source = piston
		target.add_child(push)
		check(not push.is_active_effect(),"derived piston push rejected on hull/rider")
		push._finish(false)
	await process_frame

	var external = boat.apply_knockback(Vector2.UP,100,300,0,0.2,{"source":outside})
	check(external != null and boat.dizziness,"external knockback remains effective")
	var repel_before:Vector2 = boat.Repel
	var rejected_push = PUSH.new()
	rejected_push.target = boat
	rejected_push.source = piston
	boat.add_child(rejected_push)
	check(not rejected_push.is_active_effect(),"raw onboard push rejected during external knockback")
	if rejected_push.is_active_effect(): rejected_push._finish(false)
	await process_frame
	check(external.is_active_effect() and boat.Repel == repel_before,"rejected effect cleanup preserves external motion")
	external.replace_with_hit(Vector2.LEFT,100,300,0,1,{"source":piston})
	check(external.source == outside,"onboard hit cannot replace an external controller")
	clear_controls(boat)
	await process_frame

	external = boat.apply_knockback(Vector2.UP,100,300,0,0.2,{"source":outside})
	reset_stroke(piston)
	piston.step_mob(0.18)
	check(external.is_active_effect(),"onboard piston cannot cancel a valid external displacement")
	check(not boat.has_meta("mc_sticky_hold"),"onboard piston cannot replace external push with hold")
	clear_controls(boat)
	clear_controls(ally)
	U.slow(piston,boat,0.1,1,"onboard_test_slow")
	check(not boat.Buff_Dic.get(piston.get_instance_id(),{}).has("onboard_test_slow"),"onboard fishing-style slow rejected")
	U.slow(outside,boat,0.5,1,"external_test_slow")
	check(boat.Buff_Dic.get(outside.get_instance_id(),{}).has("external_test_slow"),"external slow remains effective")
	boat.release_all()
	stun = boat.apply_stun(0.2,piston)
	check(stun != null and boat.dizziness,"former passenger can control hull after disembarking")
	if stun != null: stun._finish(false)
	await process_frame

	# Recheck source membership while an existing controller is running.
	var boat2 = spawn(BOAT,Vector2(1000,500),"A")
	var piston2 = spawn(PISTON,Vector2(1015,500),"B")
	await physics_frame
	var active_hold = HOLD.new()
	active_hold.target = boat2
	active_hold.source = piston2
	boat2.add_child(active_hold)
	check(active_hold.acquired and boat2.collision_mask == 0,"offboard piston can still capture hull")
	check(boat2.board_unit(piston2),"previously external piston boards")
	var before_board_tick:Vector2 = boat2.global_position
	active_hold._physics_process(DT)
	check(boat2.global_position == before_board_tick,"existing hold cannot start seat feedback after boarding")
	await process_frame
	check(not boat2.has_meta("mc_sticky_hold") and not boat2.dizziness,"boarding cancels existing onboard hold")
	check(boat2.collision_mask != 0 and not boat2.has_meta("submission_allow_map_escape"),"cancelled hold restores collision and map containment")
	clear_controls(boat2)
	boat2.release_all()
	piston2.global_position = boat2.global_position+Vector2(15,0)
	var active_push = PUSH.new()
	active_push.target = boat2
	active_push.source = piston2
	boat2.add_child(active_push)
	check(active_push.is_active_effect() and not boat2.dizziness and boat2.get_body_motion().impulse_velocity().length()>0,"external derived push stays effective without locking controls")
	check(boat2.board_unit(piston2),"push source boards")
	active_push._physics_process(DT)
	check(not active_push.is_active_effect() and not boat2.dizziness and boat2.Repel == Vector2.ZERO,"boarding cancels existing derived push and releases lock")
	clear_controls(boat2)
	await process_frame

	# A real collision immediately after the rear-seat attack must still stop the hull.
	var wall_boat = spawn(BOAT,Vector2(2000,1000),"A")
	var front = spawn(ACTOR,Vector2(2010,1000),"A")
	var rear = spawn(PISTON,Vector2(1990,1000),"B")
	wall_at(Vector2(2050,1000))
	await physics_frame
	check(wall_boat.board_unit(front) and wall_boat.board_unit(rear),"wall regression seats occupied")
	wall_boat.player_control_peer_id = 1
	wall_boat.player_control_direction = Vector2.RIGHT
	wall_boat._forward_speed = 300.0
	reset_stroke(rear)
	rear.step_mob(0.18)
	wall_boat.move(wall_boat.Speed,0.2)
	check(wall_boat.global_position.x < 2050 and wall_boat._forward_speed < 100,"onboard piston cannot propel hull through boundary wall")
	check(front.global_position == wall_boat.seat_position(0) and rear.global_position == wall_boat.seat_position(1),"riders still follow normally after wall collision")
	clear_controls(wall_boat)
	clear_controls(front)
	# Source tracking survives legacy calls and safely handles a freed attacker.
	boat2.release_all()
	piston2.global_position = boat2.global_position+Vector2(15,0)
	boat2.receive_positional_damage(1,boat2.global_position,false,piston2)
	var legacy = boat2.apply_stun(0.2)
	check(legacy != null and legacy.source == piston2,"legacy external control retains inferred source")
	check(boat2.board_unit(piston2),"legacy control source boards")
	legacy._physics_process(DT)
	check(not legacy.is_active_effect() and not boat2.dizziness,"legacy control is released when its source boards")
	var transient_source:Node2D = Node2D.new()
	arena.add_child(transient_source)
	var orphan_effect = boat2.apply_knockback(Vector2.UP,100,300,0,0,{"source":transient_source})
	check(orphan_effect != null,"external transient source can create control")
	transient_source.free()
	orphan_effect._physics_process(DT)
	check(orphan_effect._elapsed > 0 and orphan_effect.is_active_effect(),"freed external source does not break ongoing control")
	clear_controls(boat2)
	await process_frame
	print("BOAT_ONBOARD_CONTROL_RESULT checks=",checks," failures=",failures)
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
