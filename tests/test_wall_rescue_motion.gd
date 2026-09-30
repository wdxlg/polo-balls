extends "res://tests/test_rotation_frames_challenge.gd"
# Isolated reproduction of the former ordinary recovery, without modifying project code.
func legacy_squeeze(actor:Node,rect:Rect2) -> void:
	if actor.has_meta("map_rescue_animating") or rect.has_point(actor.global_position):return
	var old:Vector2=actor.global_position
	if old.distance_to(old.clamp(rect.position,rect.end))>world.map_squeeze_rescue_distance:return
	var half:Vector2=world._ball_collision_world_half_extents(actor)+Vector2.ONE*world.map_squeeze_rescue_padding
	var target:Vector2=old.clamp(rect.position+half,rect.end-half)
	actor.velocity=Vector2.ZERO;actor.Repel=Vector2.ZERO
	actor.set_meta("map_rescue_animating",true);actor.set_meta("map_rescue_had_physics",actor.is_physics_processing())
	actor.set_physics_process(false)
	var tween:Tween=world.create_tween().bind_node(actor).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(actor,"global_position",target,world.map_rescue_animation_duration)
	tween.finished.connect(world._finish_ball_map_rescue.bind(weakref(actor)))
	var inward:Vector2=old.direction_to(target)
	if actor.direction.dot(inward)<0:actor.direction=actor.direction.bounce(inward).normalized()
func body_inside(actor:Node,rect:Rect2) -> bool:
	var cs:CollisionShape2D=actor.collision_shape_2d;var r:Rect2=cs.shape.get_rect()
	for v:Vector2 in [r.position,r.end,Vector2(r.end.x,r.position.y),Vector2(r.position.x,r.end.y)]:
		if not rect.grow(0.01).has_point(cs.global_transform*v):return false
	return true
func run() -> void:
	create_timer(110,true,false,true).timeout.connect(func():push_error("WALL_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Development_Mode=false
	game.Game_Settings.Training_Mode_Type="rotation";game.Game_Settings.Rotation_Match_Type="duel";game.Game_Settings.Training_Wheel_Battle=false
	game.Game_Settings.Minecraft_Clouds=false;game.Game_Settings.Map_Background="blue";game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;world.set_process(false);world.set_physics_process(false)
	await process_frame
	world.control.hide();world.control.team.hide();world.now_choose_map="Map10x10";world.refresh_map_presentation()
	world._rotation_started=true
	await physics_frame;await physics_frame
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	var results:Array=[];var seq:int=3000
	for wall:int in range(4):
		for speed:float in [200.0,1600.0]:
			seq+=1
			var actor:Node=world._spawn_character_from_setup({"id":seq,"char":"ball","scene_path":"res://scenes/ball.tscn","team":"__rotation_left","x":rect.get_center().x,"y":rect.get_center().y})
			actor.Can_Attack=false;actor.Can_Skill=false;actor.Health_Restore=0;actor.Speed=speed
			await physics_frame;await physics_frame
			var normal:Vector2=[Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP][wall]
			var edge:Vector2=rect.get_center()
			if wall==0:edge.x=rect.position.x
			elif wall==1:edge.x=rect.end.x
			elif wall==2:edge.y=rect.position.y
			else:edge.y=rect.end.y
			actor.collision_shape_2d.position=-normal*180.0
			actor.image.position=-normal*180.0
			actor.global_position=edge-normal*8.0;actor.direction=-normal
			var starts:int=0;var was:bool=false;var backwards:int=0;var released_inside:bool=false;var tick_conflicts:int=0;var prev:float=(actor.global_position-edge).dot(normal);var trace:Array=[]
			for frame:int in range(100):
				if OS.get_cmdline_user_args().has("--legacy"):legacy_squeeze(actor,rect)
				else:world._process_map_squeeze_protection([actor])
				var rescuing:bool=actor.has_meta("map_rescue_animating")
				if rescuing and not was:starts+=1
				if rescuing and actor.state_machine.is_physics_processing():tick_conflicts+=1
				if was and not rescuing:released_inside=body_inside(actor,rect)
				var distance:float=(actor.global_position-edge).dot(normal)
				if was and rescuing and distance<prev-0.05:backwards+=1
				if wall==0 and speed==200.0 and frame in [0,6,13] and not OS.get_cmdline_user_args().is_empty():
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+("/legacy_" if OS.get_cmdline_user_args().has("--legacy") else "/fixed_")+str(frame)+".png")
				if frame<35:trace.append([frame,distance,rescuing,actor.state_machine.is_physics_processing()])
				prev=distance;was=rescuing
				# Stop this encounter at the map midpoint; a later visit to the opposite wall is not a retry.
				if not rescuing and distance>minf(rect.size.x,rect.size.y)*0.5:break
				await physics_frame
			results.append({"wall":wall,"speed":speed,"starts":starts,"backwards":backwards,"end":(actor.global_position-edge).dot(normal),"released_inside":released_inside,"tick_conflicts":tick_conflicts,"trace":trace})
			check(starts==1,"single rescue wall=%d speed=%s (actual %d)"%[wall,speed,starts])
			check(backwards==0,"rescue path is not pulled backwards by movement wall=%d speed=%s (actual %d)"%[wall,speed,backwards])
			check(released_inside,"entire real collision shape is inside when recovery releases")
			check(tick_conflicts==0,"state-machine movement cannot compete with the recovery tween")
			actor.queue_free();await process_frame
	if not OS.get_cmdline_user_args().has("--legacy"):await extra_checks(rect)
	print("WALL_REPRO ",JSON.stringify(results))
	world.queue_free();await process_frame;game.Game_Settings=saved
	print("WALL_RESCUE checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
func wait_rescue(actor:Node) -> void:
	var deadline:int=Time.get_ticks_msec()+4500
	while is_instance_valid(actor) and actor.has_meta("map_rescue_animating") and Time.get_ticks_msec()<deadline:await physics_frame
func extra_checks(rect:Rect2) -> void:
	var actor:Node=world._spawn_character_from_setup({"id":4000,"char":"ball","scene_path":"res://scenes/ball.tscn","team":"__rotation_left","x":rect.get_center().x,"y":rect.get_center().y})
	actor.Speed=0;actor.Can_Attack=false;actor.Can_Skill=false
	await physics_frame;await physics_frame
	var shape:CollisionShape2D=actor.collision_shape_2d
	var originals:Array=[RectangleShape2D.new(),CircleShape2D.new(),CapsuleShape2D.new()]
	originals[0].size=Vector2(50,120);originals[1].radius=35;originals[2].radius=25;originals[2].height=100
	for geometry:Shape2D in originals:
		for angle:float in [0.0,0.7]:
			shape.shape=geometry;shape.position=Vector2(-130,-150);shape.rotation=angle
			for point:Vector2 in [rect.position-Vector2(8,8),rect.end+Vector2(8,8)]:
				actor.global_position=world._map_safe_body_position(actor,rect,point)
				check(body_inside(actor,rect),"offset/scaled/rotated shape fits at both map corners")
	shape.rotation=0;shape.position=Vector2.ZERO
	var body:=RectangleShape2D.new();body.size=Vector2(80,80);shape.shape=body
	var start:Vector2=Vector2(rect.position.x-8,rect.get_center().y)
	actor.global_position=start
	world._process_map_squeeze_protection([actor])
	check(actor.has_meta("map_rescue_animating") and not actor.state_machine.is_physics_processing(),"ordinary recovery owns child state-machine motion")
	game.now_stop_state=true;await physics_frame;await physics_frame
	var stopped:Vector2=actor.global_position
	await create_timer(0.12,true,false,true).timeout
	check(actor.global_position.distance_to(stopped)<0.01,"ordinary recovery pauses with gameplay")
	game.now_stop_state=false;await wait_rescue(actor)
	check(actor.state_machine.is_physics_processing() and body_inside(actor,rect),"ordinary recovery resumes and restores movement")
	actor.set_physics_process(false);actor.state_machine.set_physics_process(false);actor.global_position=start
	world._process_map_squeeze_protection([actor]);await wait_rescue(actor)
	check(not actor.is_physics_processing() and not actor.state_machine.is_physics_processing(),"previously disabled processing stays disabled after recovery")
	actor.global_position=rect.position+Vector2(0.5,rect.size.y/2)
	world._process_map_squeeze_protection([actor])
	check(not actor.has_meta("map_rescue_animating"),"normal contact with center still inside does not trigger a rescue")
	actor.global_position=start;actor.set_meta("submission_allow_map_escape",true)
	world._process_map_squeeze_protection([actor])
	check(not actor.has_meta("map_rescue_animating"),"intentional escape exemption remains intact")
	actor.remove_meta("submission_allow_map_escape")
	actor.global_position=start-Vector2(100,0);world._process_map_squeeze_protection([actor])
	check(not actor.has_meta("map_rescue_animating"),"far-outside units still use the existing out-of-bounds rule")
	world.set_multiplayer_authority(2,false);actor.global_position=start
	world._process_map_squeeze_protection([actor]);world._animate_ball_back_inside_map(actor,rect.get_center())
	check(not actor.has_meta("map_rescue_animating"),"non-authority cannot start a competing correction")
	world.set_multiplayer_authority(1,false)
	game.Game_Settings.Training_Wheel_Battle=true
	body.size=Vector2(80,500);shape.position=Vector2(0,-180)
	var entry:Dictionary=world._rotation_wall_entry(rect.position+rect.size*Vector2(0.5,0.1))
	actor.global_position=entry.start;actor.set_meta("rotation_entry_target",entry.end);actor.Speed=200
	var old_z:int=actor.z_index;world._animate_queue_reinforcement_into_map(actor,"left")
	await wait_rescue(actor)
	check(body_inside(actor,rect),"wheel entry also clears the full offset body instead of stopping in the wall")
	check(actor.z_index==old_z and not actor.has_meta("queue_entry_z") and not actor.has_meta("map_rescue_state_physics"),"entry restores depth and removes recovery ownership metadata")
	game.Game_Settings.Training_Wheel_Battle=false;actor.global_position=start;actor.Type=actor.Ball_Type.Creature
	world._animate_ball_back_inside_map(actor,rect.get_center());actor.health=0
	await physics_frame;await physics_frame
	check(not actor.has_meta("map_rescue_animating"),"death cancels the correction without leaving a permanent lock")
	actor.Type=actor.Ball_Type.Ball;actor.health=100;actor.global_position=start
	world._animate_ball_back_inside_map(actor,rect.get_center())
	var ref:WeakRef=weakref(actor);actor.queue_free();await process_frame;await physics_frame
	check(not is_instance_valid(ref.get_ref()),"deletion during recovery releases the bound tween safely")
