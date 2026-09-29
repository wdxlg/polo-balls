extends "res://tests/test_ding_sleep.gd"
var gpu_images:Dictionary={}
func capture_pose(key:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	gpu_images[key]=image
	image.save_png("user://ding_z_pose_"+key+".png")
func changed_bounds(image:Image,blank:Image) -> Rect2i:
	var minimum:=Vector2i(image.get_width(),image.get_height())
	var maximum:=Vector2i(-1,-1)
	for y:int in range(image.get_height()):
		for x:int in range(image.get_width()):
			var a:Color=image.get_pixel(x,y);var b:Color=blank.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.12:
				minimum=minimum.min(Vector2i(x,y));maximum=maximum.max(Vector2i(x,y))
	return Rect2i(minimum,maximum-minimum+Vector2i.ONE)
func run() -> void:
	create_timer(40).timeout.connect(func():print("DING_POSE_TIMEOUT");quit(2))
	game=root.get_node("Game");game.now_stop_state=false;game.Game_Settings.Have_Team_Damage=false
	arena=Node2D.new();root.add_child(arena);current_scene=arena
	var camera:=Camera2D.new();camera.zoom=Vector2(6,6);arena.add_child(camera)
	cat=load(CAT_PATH).instantiate();cat.Team="Team0";arena.add_child(cat)
	cat.state_machine.set_physics_process(false);cat.set_process(false);cat.player_control_peer_id=0
	cat.health_bar.hide();cat._counter.hide()
	node_added.connect(heard)
	await flush()
	var collider:CollisionShape2D=cat.get_node("CollisionShape2D")
	var body_shape:Rect2=collider.shape.get_rect();var body_transform:Transform2D=collider.global_transform
	var hurt_transform:Transform2D=cat.self_hurtbox.get_node("CollisionShape2D").global_transform
	var ui_scale:Vector2=cat._counter.scale;var hp_scale:Vector2=cat.health_bar.scale
	var graphic:Node2D=cat.get_node("Graphics")
	if DisplayServer.get_name()!="headless":
		cat.image.hide();await capture_pose("blank");cat.image.show();await capture_pose("rest")
	cat._burst_wait=0
	check(cat.begin_burst(Vector2.RIGHT),"burst accepts one windup")
	check(cat.shots_fired==0 and cat.z_pose_phase==1,"windup precedes all actual projectiles")
	check(not cat.begin_burst(Vector2.LEFT),"cannot restart squash during same burst")
	cat.step_sleep(0.17);cat._counter.hide()
	check(cat.shots_fired==0 and graphic.scale.y<0.65 and graphic.scale.x>1.25,"body becomes flat before firing")
	check(sounds.get("user.ding_sleep.z_start",0)==0,"windup does not prematurely play actual attack sound")
	await capture_pose("flat")
	cat.step_sleep(0.01);cat._counter.hide()
	check(cat.shots_fired==1 and cat.z_pose_phase==2,"first actual shot starts tall transition")
	check(graphic.scale.is_equal_approx(cat.Z_FLAT),"no hard jump from flat to tall at first shot")
	await flush()
	check(sounds.get("user.ding_sleep.z_start",0)==1,"first actual shot plays user sound once")
	cat.step_sleep(cat.z_stretch_time);cat._counter.hide()
	check(graphic.scale.is_equal_approx(cat.Z_TALL),"quick stretch reaches finite thin/tall cap")
	await clear_shots();await capture_pose("tall")
	cat.step_sleep(0.2);cat.step_sleep(0.2);cat._counter.hide()
	check(cat.shots_fired==3 and cat.z_pose_phase==2,"one pose spans first three projectiles")
	check(graphic.scale.is_equal_approx(cat.Z_TALL),"no further stretching or recovery between shots")
	await clear_shots();await capture_pose("hold")
	check(collider.shape.get_rect()==body_shape and collider.global_transform==body_transform,"main collision shape and transform unaffected")
	check(cat.self_hurtbox.get_node("CollisionShape2D").global_transform==hurt_transform,"hurtbox unaffected")
	check(cat._counter.scale==ui_scale and cat.health_bar.scale==hp_scale,"countdown and health bar never squash")
	cat.step_sleep(0.2-cat.z_stretch_time);cat._counter.hide()
	check(cat.shots_fired==4 and cat._shots_left==0 and cat.z_pose_phase==3,"recovery begins only after fourth actual shot")
	check(graphic.scale.is_equal_approx(cat.Z_TALL),"last shot does not snap body back")
	cat.step_sleep(cat.z_recover_time*0.5);cat._counter.hide()
	check(graphic.scale.y>1.0 and graphic.scale.y<cat.Z_TALL.y,"recovery is continuous")
	var frozen:Vector2=graphic.scale;var age:float=cat.z_pose_age
	game.now_stop_state=true;cat.step_sleep(2)
	check(graphic.scale==frozen and cat.z_pose_age==age,"pause freezes exact recovery pose")
	game.now_stop_state=false;cat.step_sleep(cat.z_recover_time*0.5+0.001);cat._counter.hide()
	check(cat.z_pose_phase==0 and graphic.transform.is_equal_approx(cat._pose_base),"fully stopped burst restores normal shape")
	await clear_shots();await capture_pose("restored")
	cat._burst_wait=0;cat.begin_burst(Vector2.RIGHT);cat.step_sleep(0.09)
	cat.dizziness=true;cat.step_sleep(0.01)
	check(cat._shots_left==0 and cat.z_pose_phase==3,"stun cancels pending shots and releases current pose")
	cat.step_sleep(cat.z_recover_time+0.001);cat.dizziness=false
	check(graphic.transform.is_equal_approx(cat._pose_base) and cat.shots_fired==4,"cancelled windup never emits a late projectile")
	cat._burst_wait=0;cat.begin_burst(Vector2.RIGHT);cat.step_sleep(0.28)
	cat._wake()
	check(cat.wave_charging and cat.z_pose_phase==4 and graphic.scale.is_equal_approx(cat.z_recover_from),"wave smoothly takes over current Z shape")
	cat._reset_z_pose()
	cat.awake=false;cat.sleep_left=60;cat._sync_wave(false);cat._burst_wait=0
	cat.begin_burst(Vector2.RIGHT);cat.step_sleep(0.28);cat.Die()
	check(graphic.transform.is_equal_approx(cat._pose_base) and cat.z_pose_phase==0,"death clears attack deformation before shared death pose")
	if not gpu_images.is_empty():
		var rest:Rect2i=changed_bounds(gpu_images.rest,gpu_images.blank)
		var flat:Rect2i=changed_bounds(gpu_images.flat,gpu_images.blank)
		var tall:Rect2i=changed_bounds(gpu_images.tall,gpu_images.blank)
		var hold:Rect2i=changed_bounds(gpu_images.hold,gpu_images.blank)
		var restored:Rect2i=changed_bounds(gpu_images.restored,gpu_images.blank)
		print("DING_POSE_PIXELS rest=%s flat=%s tall=%s hold=%s restored=%s" % [rest,flat,tall,hold,restored])
		check(flat.size.x>rest.size.x and flat.size.y<rest.size.y,"GPU pixels show wider flatter anticipation")
		check(tall.size.x<rest.size.x and tall.size.y>rest.size.y,"GPU pixels show narrower taller firing")
		check(hold==tall,"GPU held shape does not continue growing")
		check(restored==rest,"GPU restored bounds equal original")
	cat.queue_free();await create_timer(1.2).timeout
	arena.queue_free();await flush()
	print("DING_SQUASH_RESULT checks=%d failures=%d renderer=%s" % [checks,failures,DisplayServer.get_name()])
	quit(0 if failures==0 else 1)
