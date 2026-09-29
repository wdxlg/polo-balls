extends "res://scripts/training/test_mc_new5.gd"
var ghast:Node2D
func projectile(point:Vector2) -> Node2D:
	var p:Node2D=ghast.fire_at(point+Vector2(100,0))
	p.state_machine.set_physics_process(false)
	p.set_process(false)
	p.global_position=point
	# Isolate one-passage geometry; actual inside/outside launch policy is tested in round5.
	p._launch_pending=false
	p.boundary_passes_left=1
	p._smoke_previous=point
	return p
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(100).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	world.set_process(false)
	world.camera_2d.enabled=false
	var fixed_camera:=Camera2D.new()
	world.add_child(fixed_camera)
	fixed_camera.global_position=center
	fixed_camera.zoom=Vector2(3,3)
	fixed_camera.make_current()
	world.camera_2d=fixed_camera
	fixed_camera.force_update_scroll()
	ghast=spawn("恶魂",Vector2(-200,150))
	var p:Node2D=projectile(center)
	var first:StaticBody2D=obstacle(Vector2(30,0),true,true)
	var second:StaticBody2D=obstacle(Vector2(75,0),true,true)
	await physics_frame
	var hit:Dictionary=p.trace_flight(center,center+Vector2(50,0))
	check(hit.is_empty() and p.boundary_passes_left==0,"first boundary consumes one passage")
	hit=p.trace_flight(center+Vector2(50,0),center+Vector2(100,0))
	check(hit.get("collider")==second,"second boundary blocks")
	p.boundary_passes_left=1
	p._inside_boundary=false
	hit=p.trace_flight(center,center+Vector2(100,0))
	check(hit.get("collider")==second,"two boundaries in one fast step do not tunnel")
	p.boundary_passes_left=1
	p._inside_boundary=false
	for index:int in range(25,37):
		hit=p.trace_flight(center+Vector2(index,0),center+Vector2(index+1,0))
		check(hit.is_empty(),"one thick boundary spanning frames is ONE passage")
	check(p.boundary_passes_left==0,"thick wall costs exactly one")
	p.flight_velocity=Vector2.RIGHT*185
	p.receive_positional_damage(5,center+Vector2(20,0))
	check(not p.neutral and p.boundary_passes_left==0,"mere braking does not reset budget")
	p.receive_positional_damage(100,center+Vector2(20,0))
	check(p.neutral and p.flight_velocity.x<0 and p.boundary_passes_left==1,"reflection restores one passage")
	hit=p.trace_flight(center+Vector2(50,0),center+Vector2(10,0))
	check(hit.is_empty() and p.boundary_passes_left==0,"reflected flight can cross once")
	hit=p.trace_flight(center+Vector2(10,0),center+Vector2(50,0))
	check(hit.get("collider")==first,"reflected flight next boundary blocks")
	p.receive_positional_damage(10,center-Vector2(20,0))
	check(p.boundary_passes_left==1,"subsequent confirmed reflection restores one")
	first.queue_free()
	second.queue_free()
	await physics_frame
	await process_frame
	var wall:StaticBody2D=obstacle(Vector2(30,0),true,false)
	var crate:StaticBody2D=obstacle(Vector2(75,0),false,false)
	await physics_frame
	p.neutral=false
	p._inside_boundary=false
	hit=p.trace_flight(center,center+Vector2(100,0))
	check(hit.get("collider")==wall,"original flight still blocked by internal wall")
	p.neutral=true
	hit=p.trace_flight(center,center+Vector2(100,0))
	check(hit.get("collider")==crate,"reflected internal wall rule preserved; crate still blocks")
	wall.queue_free()
	crate.queue_free()
	await physics_frame
	await process_frame
	# An internal wall and both exterior edges on ONE collision RID.
	var rect:Rect2=world.return_map_world_rect(world.map_group["Map50x50"])
	var shared:=StaticBody2D.new()
	shared.name="SharedRIDWall"
	shared.collision_layer=1
	shared.collision_mask=0
	for x:float in [rect.position.x,rect.position.x+50,rect.end.x]:
		var shape:=CollisionShape2D.new()
		var box:=RectangleShape2D.new()
		box.size=Vector2(8,30)
		shape.shape=box
		shape.position=Vector2(x,center.y)
		shared.add_child(shape)
	world.add_child(shared)
	await physics_frame
	p.boundary_passes_left=1
	p._inside_boundary=false
	hit=p.trace_flight(Vector2(rect.position.x-20,center.y),Vector2(rect.end.x+20,center.y))
	check(not hit.is_empty() and hit.position.x>rect.end.x-25,"same RID internal pass must not exempt second outer edge")
	shared.queue_free()
	p.queue_free()
	await process_frame
	await physics_frame
	# Real collision path explodes at the second boundary, not merely ray result.
	first=obstacle(Vector2(-40,0),true,true)
	second=obstacle(Vector2(40,0),true,true)
	await physics_frame
	p=projectile(center+Vector2(-70,0))
	p.flight_velocity=Vector2.RIGHT*200
	p.step_mob(0.25)
	check(not p.exploded and p.boundary_passes_left==0,"real projectile exits first boundary")
	p.step_mob(0.4)
	check(p.exploded and p.is_queued_for_deletion(),"real projectile explodes on second contact")
	first.queue_free()
	second.queue_free()
	await process_frame
	await physics_frame
	p=projectile(center)
	var screen_to_world:Transform2D=world.get_canvas_transform().affine_inverse()
	p.global_position=screen_to_world*Vector2(-1,get_root().size.y*0.5)
	check(not p.fully_outside_window(),"partially visible fireball retained")
	p.global_position=screen_to_world*Vector2(-120,get_root().size.y*0.5)
	check(p.fully_outside_window(),"full projected sprite outside window detected")
	var blasts:int=get_nodes_in_group("MCExplosion").size()
	p.step_mob(0.016)
	check(p.is_queued_for_deletion() and get_nodes_in_group("MCExplosion").size()==blasts,"offscreen disposal without blast")
	await process_frame
	p=projectile(center)
	var before:int=get_nodes_in_group("MCGhastFireSmoke").size()
	for i:int in range(60): p.update_smoke(1.0/60)
	var emitted:int=get_nodes_in_group("MCGhastFireSmoke").size()-before
	print("ROUND4_SMOKE_PER_SECOND ",emitted)
	check(emitted>=14,"denser than blaze 0.20-0.38 second interval")
	for smoke:Node in get_nodes_in_group("MCGhastFireSmoke"):
		check(smoke.get_parent().name=="MCLocalEffects","smoke detached from projectile lifetime")
		check(smoke.get_node("AnimatedSprite2D").self_modulate.a==1,"same non-fading blaze smoke")
	p.queue_free()
	for fx:Node in get_nodes_in_group("MCGhastFireSmoke"): fx.queue_free()
	await process_frame
	for group:String in ["MCExplosion","MCSlimeJumpFX","MCGhastFireSmoke"]:
		for node:Node in get_nodes_in_group(group): node.queue_free()
	await process_frame
	var slime:Node2D=spawn("史莱姆",Vector2(0,75))
	slime.set_process(false)
	slime.visual_mob()
	var fx:Node2D=slime.JUMP_FX.spawn(slime,slime.ground_point(),true,1.0,43,1234)
	fx.set_process(false)
	fx.update_visual(0.1)
	var z:int=fx.effective_z(slime.image)
	check(z==world.z_index,"test includes inherited WORLD z, not only local actor z")
	check(fx.body_z==z and fx.ring.z_index<z,"ring under effective body layer")
	var front:int=0
	var back:int=0
	for part:Dictionary in fx.particles:
		if part.sprite.z_index>z: front+=1
		if part.sprite.z_index<z: back+=1
	check(front>0 and back>0,"particles genuinely straddle effective body layer")
	check(slime.ground_point().y-slime.global_position.y<18,"ellipse centred on foot plane, not projected front edge")
	fx.queue_free()
	await process_frame
	var guardian:Node2D=spawn("守卫者",Vector2(-90,-85))
	var victim:Node2D=spawn("",Vector2(70,-85),"Team1")
	victim.health=10000
	guardian.set_process(false)
	guardian.step_mob(0.01)
	guardian.advance_facing(5)
	guardian.visual_mob()
	check(guardian.beam.texture_repeat==CanvasItem.TEXTURE_REPEAT_ENABLED,"laser texture actually repeats")
	check(guardian.get_node_or_null("GuardianBeamCore")==null and guardian.beam.visible,"native beam visible without artificial core")
	if DisplayServer.get_name()!="headless": await gpu_checks(slime,guardian)
	victim.global_position=guardian.global_position+Vector2(150,60)
	guardian.step_mob(0.01)
	check(not guardian.beam.visible,"native beam immediately disappears outside sector")
	victim.global_position=center+Vector2(70,-85)
	guardian.step_mob(0.01)
	guardian.visual_mob()
	if DisplayServer.get_name()!="headless": await render_preview(slime,guardian)
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<13: await process_frame
	print("ROUND4_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
func snap() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func gpu_checks(slime:Node2D,guardian:Node2D) -> void:
	var screen:Transform2D=root.get_final_transform()
	print("ROUND4_VIEW_TRANSFORM ",root.get_visible_rect()," final ",screen)
	var point:Vector2i=Vector2i((screen*slime.image.get_global_transform_with_canvas()*Vector2.ZERO).round())
	var before:Image=await snap()
	point=Vector2i((screen*slime.image.get_global_transform_with_canvas()*Vector2.ZERO).round())
	var original:Color=before.get_pixelv(point)
	var fx:Node2D=slime.JUMP_FX.spawn(slime,slime.ground_point(),false,1.0,43,1234)
	fx.set_process(false)
	for part:Dictionary in fx.particles: part.life=0.0
	var part:Dictionary=fx.particles[0]
	part.life=10.0
	part.grounded=true
	var sentinel:=Image.create(2,2,false,Image.FORMAT_RGBA8)
	sentinel.fill(Color.MAGENTA)
	part.sprite.texture=ImageTexture.create_from_image(sentinel)
	part.sprite.scale=Vector2.ONE*3
	part.plane=Vector2(0,-6)
	part.height=fx.global_position.y-slime.image.global_position.y-6*0.42
	fx.update_visual(0)
	var rear:Image=await snap()
	point=Vector2i((screen*slime.image.get_global_transform_with_canvas()*Vector2.ZERO).round())
	print("PIX_REAR ",point," original ",original," rear ",rear.get_pixelv(point)," z ",fx.body_z," part ",part.sprite.z_index)
	before.save_png("user://mc_occlusion_before.png")
	rear.save_png("user://mc_occlusion_rear.png")
	check(rear.get_pixelv(point).is_equal_approx(original),"GPU: rear chip actually occluded by opaque slime core")
	part.plane=Vector2(0,6)
	part.height=fx.global_position.y-slime.image.global_position.y+6*0.42
	fx.update_visual(0)
	var front:Image=await snap()
	point=Vector2i((screen*slime.image.get_global_transform_with_canvas()*Vector2.ZERO).round())
	print("PIX_FRONT ",front.get_pixelv(point)," z ",part.sprite.z_index)
	front.save_png("user://mc_occlusion_front.png")
	check(front.get_pixelv(point).r>original.r+0.1,"GPU: front chip actually covers body")
	fx.queue_free()
	guardian.beam.hide()
	var off:Image=await snap()
	guardian.visual_mob()
	var on:Image=await snap()
	var changed:int=0
	var transform:Transform2D=screen*guardian.get_canvas_transform()
	for i:int in range(20):
		var sample:Vector2i=Vector2i((transform*guardian.beam.points[0].lerp(guardian.beam_end,0.15+float(i)*0.035)).round())
		var best:float=0
		for y:int in range(-2,3):
			var a:Color=off.get_pixelv(sample+Vector2i(0,y))
			var b:Color=on.get_pixelv(sample+Vector2i(0,y))
			best=maxf(best,absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))
		if best>0.1: changed+=1
	print("ROUND4_LASER_VISIBLE_SAMPLES ",changed,"/20")
	check(changed>=8,"GPU: repeating native patterned beam visible along its length")
func render_preview(slime:Node2D,guardian:Node2D) -> void:
	DirAccess.make_dir_recursive_absolute("user://mc_round4_preview")
	var p:Node2D=projectile(center+Vector2(-110,-5))
	p.flight_velocity=Vector2.RIGHT*120
	slime.direction=Vector2.RIGHT
	slime.airborne=false
	slime.rest_left=0.2
	for index:int in range(90):
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			p.step_mob(1.0/30)
			if not p.exploded:
				p.update_smoke(1.0/30)
				p.visual_mob()
		var was_airborne:bool=slime.airborne
		slime.step_mob(1.0/30)
		slime.move(90,1.0/30)
		if was_airborne and not slime.airborne: slime.direction=-slime.jump_direction
		slime.visual_mob()
		guardian._view_clock+=1.0/30
		guardian.visual_mob()
		var frame:Image=await snap()
		if index%2==0: frame.save_png("user://mc_round4_preview/frame_%03d.png"%index)
	print("ROUND4_PREVIEW ",ProjectSettings.globalize_path("user://mc_round4_preview"))
