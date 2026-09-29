extends "res://scripts/training/test_mc_new5.gd"
var explosions:Script
var chips:Script
func clear_fx() -> void:
	for group:String in ["MCExplosion","MCSlimeJumpFX"]:
		for item:Node in get_nodes_in_group(group): item.queue_free()
	await process_frame
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
	explosions=load("res://scripts/effects/我的世界/mc_explosion.gd")
	chips=load("res://scripts/characters/我的世界/new5/slime_jump_fx.gd")
	var guardian:Node2D=spawn("守卫者",Vector2(-140,0))
	guardian.set_process(false)
	check(guardian.FRAMES.get_animation_names().size()==64,"64 real model views")
	check(is_equal_approx(guardian.image.scale.x,3.24),"same physical size after model render rescale")
	var atlas:Texture2D=guardian.FRAMES.get_frame_texture(&"v00",0).atlas
	check(atlas.get_width()==10240 and atlas.get_height()==1280,"GPU atlas imported without truncation")
	var pixels:Image=atlas.get_image()
	for view:int in range(64):
		var clip:StringName=StringName("v%02d"%view)
		check(guardian.FRAMES.get_frame_count(clip)==8,"8 native tail frames per view")
		for frame:int in range(8):
			var texture:AtlasTexture=guardian.FRAMES.get_frame_texture(clip,frame)
			check(texture.get_size()==Vector2(160,160),"uniform pivot canvas")
			var used:Rect2i=pixels.get_region(texture.region).get_used_rect()
			check(used.position.x>1 and used.position.y>1 and used.end.x<159 and used.end.y<159,"full mesh no clipping")
		guardian.gaze=Vector2.RIGHT.rotated(float(view)*TAU/64)
		guardian.advance_facing(5)
		guardian.visual_mob()
		check(guardian._view_index==view,"direction maps to baked projection")
		check(is_zero_approx(guardian.image.rotation) and guardian.image.offset==Vector2.ZERO,"no 2D rotation or translated pivot")
	guardian._look_angle=0
	guardian.gaze=Vector2.DOWN
	guardian.advance_facing(1.0/60)
	check(guardian._look_angle>0 and guardian._look_angle<PI/4,"turn interpolates, not cardinal snap")
	guardian._look_angle=TAU-0.02
	guardian.gaze=Vector2.RIGHT.rotated(0.02)
	guardian.advance_facing(1.0/60)
	check(absf(angle_difference(TAU-0.02,guardian._look_angle))<0.02,"shortest turn through wraparound")
	guardian.beam_active=true
	guardian.beam_end=center+Vector2(200,0)
	guardian.visual_mob()
	check(guardian.beam.points[0].distance_to(guardian.image.to_global(guardian.EYE_OFFSETS[guardian._view_index]))<0.001,"beam starts at same view's eye")
	guardian.break_lock()
	var slime:Node2D=spawn("史莱姆",Vector2(140,0))
	slime.set_process(false)
	var feet:Vector2=slime.ground_point()
	slime.airborne=true
	slime.jump_elapsed=slime.jump_duration*0.5
	slime.visual_mob()
	check(slime.ground_point().distance_to(feet)<0.001,"ground anchor independent of jumping sprite")
	check(feet.y>slime.global_position.y,"ring sits at visible feet, not body centre")
	for stage:int in range(3):
		for landing:bool in [false,true]:
			var effect:Node2D=chips.spawn(world,feet,landing,slime.STAGE_FACTOR[stage],[43.0,30.0,20.0][stage],4321)
			effect.set_process(false)
			check(effect.particles.size()<=5 if not landing else effect.particles.size()>=7,"small takeoff / full landing circle")
			check(is_instance_valid(effect.ring)==landing,"ring only on landing")
			var r0:float=effect.ring_radius
			var alpha:float=effect.ring.default_color.a if landing else 0
			for i:int in range(6): effect.update_visual(1.0/60)
			for p:Dictionary in effect.particles: check(p.height>0.5,"chips initially rise")
			if landing:
				check(effect.ring_radius>r0 and effect.ring.default_color.a<alpha,"ring expands and fades")
				check(absf(effect.ring.points[18].y/effect.ring.points[0].x-0.42)<0.001,"ground-plane ellipse")
				check(effect.ring.z_index<slime.z_index,"ring drawn under slime")
			for i:int in range(20): effect.update_visual(1.0/60)
			var falling:int=0
			for p:Dictionary in effect.particles:
				if p.up<0 or p.grounded: falling+=1
			check(falling==effect.particles.size(),"every chip falls back down")
			effect.update_visual(1.0)
			check(effect.is_queued_for_deletion(),"slime FX self-clean")
	await clear_fx()
	slime.airborne=false
	slime.rest_left=0
	slime.direction=Vector2.RIGHT
	slime.step_mob(0.01)
	check(get_nodes_in_group("MCSlimeJumpFX").size()==1,"actual takeoff triggers one FX")
	slime.step_mob(0.7)
	check(get_nodes_in_group("MCSlimeJumpFX").size()==2,"actual landing triggers one more FX")
	for fx:Node2D in get_nodes_in_group("MCSlimeJumpFX"):
		check(fx.get_parent().name=="MCLocalEffects","not parented to dying actor / network spawn root")
	await clear_fx()
	var blast:Node2D=explosions.spawn(world,center,55,{"seed":1234,"sound":false})
	blast.set_process(false)
	for p:Dictionary in blast.particles:
		if p.smoke: check(p.position3.y<=1.5 and p.velocity3.y>=30 and p.velocity3.y<=68,"lower smoke spawn and lift")
	var peak:float=0
	for tick:int in range(40):
		blast.advance_visual(1.0/60)
		for p:Dictionary in blast.particles:
			if p.smoke:
				peak=maxf(peak,p.position3.y)
				check(is_equal_approx(p.sprite.modulate.a,1.0),"explosion smoke still no alpha fade")
	check(peak<10 and peak>2,"smoke stays low but retains 3D arc")
	print("ROUND3_SMOKE_PEAK ",peak)
	await clear_fx()
	var hunter:Node2D=load("res://scenes/characters/游戏/魔角猎人.tscn").instantiate()
	hunter.position=center
	world.add_child(hunter,true)
	hunter.state_machine.set_physics_process(false)
	hunter.Has_Collision_Damage=false
	hunter._rpc_play_magic_horn_explosion(center,2,108,-7)
	check(get_nodes_in_group("MCExplosion").size()==1,"magic horn overload uses MC explosion")
	var routed:Node2D=get_nodes_in_group("MCExplosion")[0]
	check(is_equal_approx(routed.radius,54) and routed.get_parent().name=="MCLocalEffects","magic horn radius and detached lifetime")
	await clear_fx()
	hunter.resolve_magic_horn_small_bomb_explosion(center,42,0.5)
	check(get_nodes_in_group("MCExplosion").size()==1,"actual small bomb handler uses MC explosion")
	await clear_fx()
	var head:Node2D=spawn("苦力怕头",Vector2.ZERO,"Team0","creatures")
	head._rpc_explosion_visual(center,2,90)
	check(get_nodes_in_group("MCExplosion").size()==1,"creeper head uses MC explosion")
	var headfx:Node2D=get_nodes_in_group("MCExplosion")[0]
	head.queue_free()
	await process_frame
	check(is_instance_valid(headfx) and not headfx.is_queued_for_deletion(),"head death does not cut off explosion")
	await clear_fx()
	hunter.queue_free()
	if DisplayServer.get_name()!="headless": await render_preview(guardian,slime)
	print("ROUND3_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
func label(parent:Node,text:String,point:Vector2,size:int=16) -> void:
	var item:=Label.new()
	item.text=text
	item.position=point
	item.add_theme_font_size_override("font_size",size)
	item.modulate=Color(0.78,0.86,0.86)
	parent.add_child(item)
func render_preview(guardian:Node2D,slime:Node2D) -> void:
	var vp:=SubViewport.new()
	vp.size=Vector2i(640,500)
	vp.disable_3d=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world.add_child(vp)
	var bg:=ColorRect.new()
	bg.size=Vector2(640,500)
	bg.color=Color(0.14,0.18,0.19)
	bg.z_index=-5
	vp.add_child(bg)
	label(vp,"GUARDIAN",Vector2(20,14))
	label(vp,"64 model views / fixed pivot",Vector2(20,38),12)
	label(vp,"SLIME",Vector2(340,14))
	label(vp,"Takeoff chips / landing ring",Vector2(340,38),12)
	label(vp,"SHARED MC EXPLOSION",Vector2(20,290))
	label(vp,"Magic Horn Hunter + Creeper / lower smoke",Vector2(20,314),12)
	for pair:Array in [[Vector2(320,0),Vector2(320,270)],[Vector2(0,275),Vector2(640,275)]]:
		var line:=Line2D.new()
		line.points=PackedVector2Array(pair)
		line.width=1
		line.default_color=Color(0.28,0.36,0.36)
		vp.add_child(line)
	var gs:=Sprite2D.new()
	gs.position=Vector2(165,165)
	gs.scale=guardian.image.global_scale.abs()*2.2
	gs.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	vp.add_child(gs)
	var ss:=Sprite2D.new()
	ss.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	vp.add_child(ss)
	var origin:Vector2=slime.global_position
	slime.airborne=false
	slime.rest_left=0.25
	slime.jump_elapsed=0
	slime.direction=Vector2.RIGHT
	var fx_list:Array[Node2D]=[]
	var blast:Node2D
	DirAccess.make_dir_recursive_absolute("user://mc_round3_preview")
	for frame:int in range(192):
		var delta:float=1.0/30
		guardian.gaze=Vector2.RIGHT.rotated(PI+float(frame)/192*TAU*2)
		guardian.advance_facing(delta)
		guardian._view_clock+=delta
		guardian.visual_mob()
		gs.texture=guardian.image.texture
		var was_airborne:bool=slime.airborne
		slime.step_mob(delta)
		slime.move(90,delta)
		if was_airborne and not slime.airborne: slime.direction=-slime.jump_direction
		slime._view_clock+=delta
		slime.visual_mob()
		ss.texture=slime.image.texture
		ss.flip_h=slime.is_character_visual_flipped_h()
		ss.scale=slime.image.global_scale.abs()*2.2
		ss.position=Vector2(410,180)+(slime.image.global_position-origin)*2.2
		for fx:Node2D in get_nodes_in_group("MCSlimeJumpFX"):
			if fx.get_parent().name=="MCLocalEffects":
				var screen:Vector2=Vector2(410,180)+(fx.global_position-origin)*2.2
				fx.reparent(vp,false)
				fx.position=screen
				fx.scale=Vector2.ONE*2.2
				fx.set_process(false)
				fx_list.append(fx)
		for fx:Node2D in fx_list:
			if is_instance_valid(fx) and not fx.is_queued_for_deletion(): fx.update_visual(delta)
		if frame%54==0:
			blast=load("res://scenes/effects/我的世界/MC爆炸.tscn").instantiate()
			blast.position=Vector2(320,409)
			blast.scale=Vector2.ONE*1.3
			blast.visual_seed=1234+frame
			blast.play_audio=false
			vp.add_child(blast)
			blast.set_process(false)
		if is_instance_valid(blast) and not blast.is_queued_for_deletion(): blast.advance_visual(delta)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame%2==0: vp.get_texture().get_image().save_png("user://mc_round3_preview/frame_%03d.png"%frame)
	print("ROUND3_PREVIEW ",ProjectSettings.globalize_path("user://mc_round3_preview"))
	vp.queue_free()
