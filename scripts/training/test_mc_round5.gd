extends "res://scripts/training/test_mc_new5.gd"
var ghast:Node2D
func fire(origin:Vector2,direction:Vector2) -> Node2D:
	ghast.global_position=origin
	var p:Node2D=ghast.fire_at(origin+direction*300)
	p.state_machine.set_physics_process(false)
	p.set_process(false)
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
	create_timer(90).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var rect:Rect2=world.return_map_world_rect(world.map_group["Map50x50"])
	ghast=spawn("恶魂",Vector2.ZERO)
	var p:Node2D=fire(center,Vector2.RIGHT)
	check(p.boundary_passes_left==0,"inside launch has zero boundary exemptions")
	var wall:StaticBody2D=obstacle(Vector2(80,0),true,true)
	await physics_frame
	p.step_mob(0.4)
	check(p.exploded,"inside launch explodes at first boundary contact")
	wall.queue_free()
	await process_frame
	await physics_frame
	# Use the real map boundary, not only a synthetic tagged wall.
	var left:Vector2=Vector2(rect.position.x,center.y)
	p=fire(left-Vector2(60,0),Vector2.RIGHT)
	check(p.boundary_passes_left==1,"outside launch has one entry")
	var hit:Dictionary=p.trace_flight(left-Vector2(60,0),left+Vector2(60,0))
	check(hit.is_empty() and p.boundary_passes_left==0,"real outer border consumes entry once")
	hit=p.trace_flight(left+Vector2(60,0),left-Vector2(60,0))
	check(not hit.is_empty(),"returning to same border now blocks")
	p.queue_free()
	await process_frame
	# An offset muzzle can already lie across the wall; sweep that offset.
	p=fire(left+Vector2(12,0),Vector2.LEFT)
	check(p.global_position.x<rect.position.x and p.boundary_passes_left==0,"inside caster with outside muzzle still has zero")
	p.step_mob(0.01)
	check(p.exploded,"inside muzzle offset cannot teleport through border")
	await process_frame
	p=fire(left-Vector2(12,0),Vector2.RIGHT)
	check(p.global_position.x>rect.position.x and p.boundary_passes_left==1,"outside caster classification uses caster position")
	p.step_mob(0.01)
	check(not p.exploded and p.boundary_passes_left==0,"entry consumed even if mouth offset begins inside")
	p.receive_positional_damage(100,p.global_position+Vector2(20,0))
	check(p.neutral and p.boundary_passes_left==1 and not p._launch_pending,"reflection receives fresh single passage")
	hit=p.trace_flight(left+Vector2(50,0),left-Vector2(50,0))
	check(hit.is_empty() and p.boundary_passes_left==0,"reflected shot can cross out once")
	hit=p.trace_flight(left-Vector2(50,0),left+Vector2(50,0))
	check(not hit.is_empty(),"reflected second crossing blocked")
	p.queue_free()
	await process_frame
	ghast.global_position=center+Vector2(-250,180)
	var piston:Node2D=spawn("粘性活塞",Vector2(0,100))
	piston.direction=Vector2.RIGHT
	piston.stick_duration=10.0
	var target:Node2D=spawn("",Vector2(31,100),"Team1")
	target.health=10000
	var hp:float=target.health
	for i:int in range(20): piston.step_mob(0.016)
	check(target.has_meta("mc_sticky_hold"),"head captures victim")
	check(target.health<hp,"capture stroke also attacks")
	var hold:Node=instance_from_id(int(target.get_meta("mc_sticky_hold",0)))
	hold.set_physics_process(false)
	for cycle:int in range(3):
		piston.phase=0
		piston.extension=piston.REST_EXTENSION
		piston._hit_ids.clear()
		hp=target.health
		for tick:int in range(24):
			target.global_position=piston.sticky_anchor(target)
			piston.step_mob(0.016)
		check(target.health<hp,"held target damaged on subsequent stroke")
		check(target.has_meta("mc_sticky_hold") and int(target.get_meta("mc_sticky_hold"))==hold.get_instance_id(),"damage keeps same hold controller")
		check(piston.extending,"keeps attacking while enemy in front")
	var pushes:int=0
	for child:Node in target.get_children():
		if child.has_method("replace_with_hit") and not child.is_queued_for_deletion() and int(child.get("_stage"))==0: pushes+=1
	check(pushes==0,"no competing knockback controller during adhesion")
	var other:Node2D=spawn("",Vector2(60,100),"Team1")
	other.health=10000
	piston.phase=0
	piston.extension=piston.REST_EXTENSION
	piston._hit_ids.clear()
	hp=other.health
	for tick:int in range(24):
		target.global_position=piston.sticky_anchor(target)
		piston.step_mob(0.016)
	check(other.health<hp,"other enemies in front attacked while holding victim")
	hold.queue_free()
	await process_frame
	target.global_position=center+Vector2(0,330)
	other.global_position=center+Vector2(0,400)
	piston.step_mob(0.02)
	check(not piston.extending,"stops when nobody remains in front")
	var guardian:Node2D=spawn("守卫者",Vector2(-110,-100))
	guardian.set_process(false)
	target.global_position=center+Vector2(90,-100)
	guardian.step_mob(0.01)
	guardian.advance_facing(5)
	guardian._tick_left=0.04
	guardian.visual_mob()
	check(guardian.get_node_or_null("GuardianBeamCore")==null,"no invented solid core")
	check(guardian.beam.texture==guardian.BEAM_TEXTURE,"native guardian texture bound")
	check(guardian.beam.material.get_shader_parameter("native_beam")==guardian.BEAM_TEXTURE,"native pixels feed UV-corrected beam")
	check(guardian.beam.visible,"beam visible with valid target")
	if DisplayServer.get_name()!="headless": await preview(guardian,piston,target,other)
	guardian.break_lock()
	check(not guardian.beam.visible,"native beam hides immediately on disconnect")
	print("ROUND5_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
func preview(guardian:Node2D,piston:Node2D,target:Node2D,other:Node2D) -> void:
	# Real game scene + native beam, not a separately reconstructed image.
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<13: await process_frame
	world.set_process(false)
	world.set_physics_process(false)
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=center
	camera.zoom=Vector2(4,4)
	camera.make_current()
	camera.force_update_scroll()
	piston.global_position=center+Vector2(-90,50)
	other.global_position=center+Vector2(-59,50)
	other.health=10000
	piston.phase=0
	piston.extension=piston.REST_EXTENSION
	piston._hit_ids.clear()
	var t:float=0.0
	DirAccess.make_dir_recursive_absolute("user://mc_round5_preview")
	for index:int in range(48):
		t+=1.0/24
		guardian._view_clock=t
		guardian._tick_left=guardian.laser_tick*(1.0-fmod(t,1.0))
		guardian.visual_mob()
		piston.step_mob(1.0/24)
		piston.visual_mob()
		if other.has_meta("mc_sticky_hold"):
			var h:Node=instance_from_id(int(other.get_meta("mc_sticky_hold")))
			if is_instance_valid(h): h.set_physics_process(false)
			other.global_position=piston.sticky_anchor(other)
		await process_frame
		await RenderingServer.frame_post_draw
		if index%4==0: root.get_texture().get_image().save_png("user://mc_round5_preview/frame_%02d.png"%index)
	print("ROUND5_PREVIEW ",ProjectSettings.globalize_path("user://mc_round5_preview"))
