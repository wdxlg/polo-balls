extends "res://tests/test_stone_spear.gd"
var units:Array[Node2D]=[]
func run() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("STONE_FOLLOW_TIMEOUT"); quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Have_Team_Damage=false
	AudioServer.set_bus_mute(0,true)
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	spear.disable_mode=CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(spear)
	check(spear.movement_growth==10.0,"growth changed from 20 to 10, not an instant speed grant")
	check(spear.permanent_speed_bonus==0.0,"birth still has original movement speed")
	for form:int in range(3):
		reset_pose(form)
		spear.direction=Vector2.ZERO
		spear.orbit_base_rate=0.0 # isolate following from the independently tested spin
		spear._facing=PI*0.5
		var before_centers:Array=spear._centers.duplicate()
		var before_angles:Array=spear._angles.duplicate()
		spear.tick_physics(spear.State.Stand,1.0/60.0)
		check(spear._formation_heading>0.0 and spear._formation_heading<PI*0.5,"form %d frame turns gradually" % form)
		for i:int in range(4):
			var step:float=absf(angle_difference(before_angles[i],spear._angles[i]))
			check(step>0.00001 and step<PI*0.25,"form %d copy %d rotates, not a hard 90 degree cut" % [form,i])
			var distance:float=before_centers[i].distance_to(spear._centers[i])
			check(distance>0.00001 and distance<12.0,"form %d copy %d travels through intermediate position" % [form,i])
			check(spear._copies[i].global_position.distance_to(spear._centers[i])<0.001,"display and physical head anchor are the same")
			check(absf(angle_difference(spear._copies[i].global_rotation,spear._angles[i]+PI*0.75))<0.001,"display and physical head angle are the same")
		for frame:int in range(120): spear.tick_physics(spear.State.Stand,1.0/60.0)
		check(absf(angle_difference(spear._formation_heading,PI*0.5))<0.001,"form %d finishes following the new heading" % form)
		for i:int in range(4):
			var desired:Dictionary=spear.formation_pose(i,0.0)
			check(spear._centers[i].distance_to(spear._formation_center+desired.offset)<0.02,"form %d final layout converges" % form)
		# A second turn across +/- PI must take the short route.
		spear._formation_heading=PI-0.02
		spear._facing=-PI+0.02
		var old_angle:float=spear._formation_heading
		spear._advance_formation_frame(1.0/60.0)
		check(absf(angle_difference(old_angle,spear._formation_heading))<0.02,"shortest-angle wrapping has no full revolution")
	reset_pose(1)
	spear.direction=Vector2.ZERO
	spear.orbit_base_rate=0.65
	spear._facing=PI*0.5
	spear.tick_physics(spear.State.Stand,1.0/60.0)
	for i:int in range(4):
		var radial:Vector2=spear._centers[i]-spear._formation_center
		check(is_equal_approx(radial.length(),spear.scaled_spacing()),"orbit preserves one-grid radius while turning")
		check(absf(radial.normalized().dot(Vector2.from_angle(spear._angles[i])))<0.0001,"turning orbit remains tangent to its visible circle")
	# Accumulation depends on true movement, and is half the previous rate.
	reset_pose()
	spear.global_position=Vector2(1000,1000)
	spear._last_body_position=spear.global_position
	spear._formation_center=spear.global_position
	spear.direction=Vector2.RIGHT
	for frame:int in range(60):
		await physics_frame
		spear.tick_physics(spear.State.Move,1.0/60.0)
	check(absf(spear.permanent_speed_bonus-10.0)<0.01,"one real moving second earns exactly 10 growth")
	var bonus:float=spear.permanent_speed_bonus
	spear.direction=Vector2.ZERO
	spear.tick_physics(spear.State.Stand,0.3)
	check(spear.permanent_speed_bonus==bonus,"standing retains earned acceleration")
	game.now_stop_state=true
	var frozen_centers:Array=spear._centers.duplicate()
	var frozen_heading:float=spear._formation_heading
	spear.tick_physics(spear.State.Move,0.3)
	check(spear._centers==frozen_centers and spear._formation_heading==frozen_heading,"pause freezes follow animation")
	check(spear.permanent_speed_bonus==bonus,"pause neither adds nor resets growth")
	game.now_stop_state=false
	# Faster chasing remains attached instead of trailing farther at high speed.
	var gaps:Array[float]=[]
	for speed_value:float in [102.0,1000.0]:
		reset_pose()
		spear.Speed=speed_value/0.6
		spear.movement_growth=0.0
		spear.direction=Vector2.RIGHT
		for frame:int in range(120):
			await physics_frame
			spear.tick_physics(spear.State.Move,1.0/60.0)
		gaps.append(spear._centers[1].distance_to(spear.global_position))
	check(gaps[1]<gaps[0],"high speed brings outer follower nearer in actual world positions")
	spear.Speed=170.0
	spear.movement_growth=10.0
	# Locked thrust is not converted to a homing curve by the new carrier frame.
	reset_pose(2)
	spear.direction=Vector2.ZERO
	spear._stab_wait=0.0
	check(spear.begin_stab(),"thrust can start after turn changes")
	var locked:PackedFloat32Array=spear._stab_axes.duplicate()
	spear._facing=PI*0.5
	spear.tick_physics(spear.State.Stand,0.08)
	check(spear._stab_axes==locked,"outgoing thrust retains launch axes")
	spear._stab_time=spear.stab_out_time+0.1
	spear.tick_physics(spear.State.Stand,0.03)
	check(spear.get_ai_attack_threats(null).is_empty(),"return still harmless after follow changes")
	var config:SceneReplicationConfig=spear.get_node("MultiplayerSynchronizer").replication_config
	for field:String in ["_formation_center","_formation_heading"]:
		check(config.has_property(NodePath(".:"+field)) and config.property_get_spawn(NodePath(".:"+field)),"new follower state has spawn/current replication")
	if DisplayServer.get_name()!="headless": await visual_turns()
	print("STONE_FOLLOW_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)

func visual_turns() -> void:
	# Render the production actors at three real intermediate headings for every stance.
	spear.hide()
	root.size=Vector2i(1080,720)
	root.content_scale_size=Vector2i(1080,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var camera:=Camera2D.new()
	camera.zoom=Vector2(3,3)
	arena.add_child(camera)
	var layer:=CanvasLayer.new()
	arena.add_child(layer)
	for i:int in range(3):
		var unit:Node2D=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
		unit.position=Vector2((i-1)*110,0)
		arena.add_child(unit)
		unit.state_machine.set_physics_process(false)
		unit.formation=i
		unit._facing=0.0
		unit._formation_heading=0.0
		unit._formation_center=unit.global_position
		unit._last_body_position=unit.global_position
		unit._orbit=0.0
		unit.orbit_base_rate=0.65
		unit.direction=Vector2.ZERO
		unit._switch_wait=100.0
		unit._stab_wait=100.0
		for j:int in range(4):
			var pose:Dictionary=unit.formation_pose(j,0.0)
			unit._centers[j]=unit.global_position+pose.offset
			unit._angles[j]=pose.angle
		unit._apply_pose()
		unit.get_node("Health_Bar").hide()
		units.append(unit)
		var label:=Label.new()
		label.position=Vector2(35+i*350,105)
		label.text=["FOLLOW / SMOOTH TURN","ORBIT / FOLLOWS BODY","THRUST / SMOOTH TURN"][i]
		label.add_theme_font_size_override("font_size",19)
		layer.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://tests/previews/stone_spear_turn")
	for frame:int in range(61):
		for unit:Node2D in units:
			unit._facing=PI*0.5
			unit.tick_physics(unit.State.Stand,1.0/60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame%3==0:
			var img:Image=root.get_texture().get_image()
			check(img.save_png("res://tests/previews/stone_spear_turn/frame_%02d.png" % frame)==OK,"actual GPU turn frame %d saved" % frame)
	check(units[0]._formation_heading>1.5 and units[2]._formation_heading>1.5,"GPU production actors complete smooth following")
