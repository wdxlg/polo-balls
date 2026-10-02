extends "res://tests/test_copper_sword.gd"
## The body and hitbox use the small, rotated native grip, pinned to the character
## origin; the hurtbox is the whole sword. The blade-sweep query is separate.
const GRIP_PARTS:Array[NodePath] = [NodePath("CollisionShape2D"),NodePath("hitbox/CollisionShape2D")]

func overlaps_body(unit:Node2D,point:Vector2) -> bool:
	var probe := CircleShape2D.new()
	probe.radius = 0.35
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 0xFFFFFFFF
	for contact:Dictionary in unit.get_world_2d().direct_space_state.intersect_shape(query,32):
		if contact.collider == unit: return true
	return false

func overlaps_unit(unit:Node2D,point:Vector2) -> bool:
	var probe := CircleShape2D.new()
	probe.radius = 0.35
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = true
	for contact:Dictionary in unit.get_world_2d().direct_space_state.intersect_shape(query,32):
		if contact.collider == unit or contact.collider == unit.self_hurtbox: return true
	return false

func verify_pose(unit:Node2D,label:String) -> void:
	var facing:float = 1.0 if unit._face_right else -1.0
	var pose:Transform2D = unit.image.global_transform
	var handle:Vector2 = pose * Vector2(-4.5*facing,4.5)
	var axis:Vector2 = pose.basis_xform(Vector2(-facing,1.0)).normalized()
	for part:NodePath in GRIP_PARTS:
		var collider:CollisionShape2D = unit.get_node(part)
		var shape:CapsuleShape2D = collider.shape as CapsuleShape2D
		check(shape != null and absf(shape.radius-11.25)<0.01 and absf(shape.height-63.75)<0.01, label+" grip shape "+str(part))
		check(collider.global_position.distance_to(handle)<0.02, label+" handle position "+str(part))
		check(collider.global_transform.basis_xform(Vector2.DOWN).normalized().dot(axis)>0.999, label+" follows rotation "+str(part))
	check(handle.distance_to(unit.global_position)<0.05,label+" grip stays on the origin")
	check(overlaps_unit(unit,handle),label+" physics contacts the handle")
	var blade:Vector2 = pose * Vector2(5.5*facing,-5.5)
	check(not overlaps_body(unit,blade),label+" blade is not a body collider")
	var hurt:CollisionShape2D = unit.get_node("hurtbox/CollisionShape2D")
	check(hurt.shape is ConvexPolygonShape2D and hurt.global_transform.origin.distance_to(pose.origin)<0.02,label+" hurtbox is the whole sword")
	check(overlaps_unit(unit,blade) and overlaps_unit(unit,handle),label+" hurtbox covers blade and handle")

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(65.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"grip test preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	unit.set_physics_process(false)
	await physics_frame
	verify_pose(unit,"idle right")
	unit._face_right = false
	unit.visual_mob()
	await physics_frame
	verify_pose(unit,"shader mirrored left")
	unit._face_right = true
	unit.visual_mob()
	var rest_rotation:float = unit.get_node("CollisionShape2D").global_rotation
	check(unit.begin_swing(),"swing begins without changing blade query")
	unit._windup_left = 0.0
	unit.advance_swing(unit._swing_duration*0.85)
	await physics_frame
	verify_pose(unit,"rotated middle of swing")
	check(absf(angle_difference(rest_rotation,unit.get_node("CollisionShape2D").global_rotation))>0.5,"physical grip rotates substantially during a cut")
	unit.cancel_swing()
	unit._advance_return(unit.return_duration)
	await physics_frame
	verify_pose(unit,"returned to rest")
	print("COPPER_SWORD_GRIP checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
