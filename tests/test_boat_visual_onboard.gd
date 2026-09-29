extends SceneTree
# 视觉诊断：木船八方向帧选择/旋转归零、烘焙座位锚点，以及活塞上船后各部件变换对齐。
var checks:int = 0
var failures:int = 0
var arena:Node2D

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("BOAT_VISUAL_FAIL ",label)

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
	root.get_node("Game").now_stop_state = false
	RenderingServer.set_default_clear_color(Color("263449"))
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var camera:Camera2D = Camera2D.new()
	camera.zoom = Vector2(1.4,1.4)
	camera.position = Vector2(430,250)
	arena.add_child(camera)
	var cols:Array[float] = [100.0,320.0,540.0,760.0]
	var rows:Array[float] = [90.0,250.0,410.0]
	var report:Dictionary = {}
	var boats:Array = []
	for i:int in range(8):
		var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(cols[i%4],rows[i/4]),"A")
		boats.append(boat)
		boat.facing = Vector2.from_angle(i*TAU/8.0)
		boat._rowing = true
		boat.visual_mob()
		check(absf(boat.global_rotation) < 0.001, "root_rotation_d%d"%i)
		check(absf(boat.graphics.rotation) < 0.001, "graphics_rotation_d%d"%i)
		check(absf(boat.image.rotation) < 0.001, "image_rotation_d%d"%i)
		var found:int = -1
		for k:int in range(8):
			if boat.image.texture == boat.FRAMES8.get_frame_texture(StringName("d%d_row"%i),k): found = k
		check(found >= 0, "frame_dir_d%d"%i)
		var front_found:int = -1
		for k3:int in range(8):
			if boat.front.texture == boat.FRAMES8_FRONT.get_frame_texture(StringName("d%d_row"%i),k3): front_found = k3
		check(front_found >= 0, "front_frame_dir_d%d"%i)
		check(absf(boat.front.rotation) < 0.001, "front_rotation_d%d"%i)
		report["d%d"%i] = {"found_frame":found,"image_rotation":boat.image.rotation,"graphics_rotation":boat.graphics.rotation}
		if i == 0:
			boat._rowing = false
			boat.visual_mob()
			var idle_found:int = -1
			for k2:int in range(8):
				if boat.image.texture == boat.FRAMES8.get_frame_texture(StringName("d0_idle"),k2): idle_found = k2
			check(idle_found >= 0, "frame_idle_d0")
			boat._rowing = true
			boat.visual_mob()
	check((boats[0].seat_position(0)-boats[0].global_position) != (boats[2].seat_position(0)-boats[2].global_position), "seat_anchor_direction_dependent")
	check(boats[0].seat_position(0).distance_to(boats[0].global_position+boats[0].SEAT_ANCHORS[0][0]) < 0.001, "seat_anchor_constant_d0")
	check(boats[2].seat_position(1).distance_to(boats[2].global_position+boats[2].SEAT_ANCHORS[2][1]) < 0.001, "seat_anchor_constant_d2")
	var boat2 = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(cols[3],rows[2]),"A")
	var piston = spawn("res://scenes/characters/我的世界/粘性活塞.tscn",Vector2(cols[3],rows[2]),"A")
	boat2.facing = Vector2.from_angle(7*TAU/8.0)
	piston.facing = Vector2.from_angle(7*TAU/8.0)
	piston._turn_target = piston.facing
	piston._turn_active = false
	check(boat2.board_unit(piston), "board_piston")
	var rider:Node = piston.get_node_or_null("BoatSeatConstraint")
	check(rider != null, "rider_exists")
	boat2._rowing = true
	boat2.visual_mob()
	if rider != null: rider.apply_pose()
	piston.visual_mob()
	check(absf(piston.graphics.global_rotation) < 0.001, "piston_graphics_rotation")
	check(absf(wrapf(piston.image.global_rotation-piston.weapon.global_rotation,-PI,PI)) < 0.001, "piston_case_rod_align")
	check(piston.weapon.global_position.distance_to(piston.global_position) < 0.001, "piston_weapon_anchor")
	if rider != null:
		check(piston.global_position.distance_to(boat2.seat_position(rider.slot)) < 0.001, "piston_seat_position")
	check(piston.direction.is_equal_approx(boat2.facing), "rider_direction_follows_heading")
	check(piston.graphics.position.y < -0.5, "rider_sprite_lifted_into_hull")
	check(is_instance_valid(boat2.front), "front_sprite_exists")
	var rider_rel:int = piston.graphics.z_index-boat2.graphics.z_index
	check(boat2.image.z_index < rider_rel, "rider_above_hull_back")
	check(rider_rel < boat2.front.z_index, "rider_below_hull_front")
	check(boat2.front.scale.is_equal_approx(boat2.image.scale), "front_scale_matches")
	report["boarded"] = {
		"boat_root_rotation":boat2.global_rotation,
		"boat_graphics_rotation":boat2.graphics.rotation,
		"boat_image_rotation":boat2.image.rotation,
		"piston_graphics_global_rotation":piston.graphics.global_rotation,
		"piston_image_global_rotation":piston.image.global_rotation,
		"piston_weapon_global_rotation":piston.weapon.global_rotation,
		"piston_graphics_local_position":piston.graphics.position,
		"piston_image_offset":piston.image.offset,
		"piston_image_scale":piston.image.scale,
		"piston_flip_h":piston.is_character_visual_flipped_h(),
		"boat_flip_h":boat2.is_character_visual_flipped_h(),
		"piston_global_position":piston.global_position,
		"boat_global_position":boat2.global_position,
		"seat0":boat2.seat_position(0),
	}
	# —— 重锤上船砸地腾空：座位组件必须保留动画写入的位置/旋转偏移 ——
	var boat3 = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(900,540),"A")
	var hammer = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(900,540),"B")
	boat3.facing = Vector2.RIGHT
	check(boat3.board_unit(hammer),"board_hammer")
	var rider3:Node = hammer.get_node_or_null("BoatSeatConstraint")
	check(rider3 != null,"hammer_rider_exists")
	if rider3 != null:
		rider3.apply_pose()
		var pose0:Vector2 = hammer.graphics.position
		var rot0:float = hammer.graphics.rotation
		hammer._begin_flight(1)
		hammer._update_flight(hammer._rise_duration*0.5)
		rider3.apply_pose()
		check(hammer.graphics.position.y < pose0.y-1.0,"hammer_flight_lift_survives_seat_pose")
		check(absf(wrapf(hammer.graphics.rotation-rot0,-PI,PI)) > 0.01,"hammer_flight_spin_survives_seat_pose")
		var mid_pos:Vector2 = hammer.graphics.position
		var mid_rot:float = hammer.graphics.rotation
		var mid_scale:Vector2 = hammer.image.scale
		hammer._flight_elapsed = hammer._flight_duration
		hammer._update_flight(0.0)
		rider3.apply_pose()
		check(hammer.graphics.position.distance_to(pose0) < 0.5,"hammer_landing_restores_seat_pose")
		report["hammer_flight"] = {
			"pose0":pose0,"mid_pos":mid_pos,"mid_rot":mid_rot,"mid_scale":mid_scale,
			"landed":hammer.graphics.position,
		}
	for i2:int in range(8):
		await process_frame
	print("BOAT_VISUAL_TRANSFORMS ",JSON.stringify(report))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		print("VOID_VISUAL ",root.get_texture().get_image().save_png("res://tests/boat_visual_debug.png"))
	print("BOAT_VISUAL_RESULT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures > 0 else 0)
