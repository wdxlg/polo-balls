extends "res://tests/test_sulfur_cube_balance.gd"
## Real main-window pixels in the real World/map/camera: Haochen charges from a
## nearby enemy through its real physics tick, then copies. Diagnoses size and
## whether particles are actually visible in the battle view.
func hold(unit:Node) -> void:
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.set_process(false)
	unit.Has_Collision_Damage=false
	unit.Can_Attack=false
	unit.Can_Skill=false

var focus:Array[Node2D] = []
func shot(tag:String) -> Image:
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	image.save_png("user://haochen_real_%s.png"%tag)
	# Crop around the Haochen/enemy pair in real screen pixels for review.
	var live:Array[Node2D] = focus.filter(func(n):return is_instance_valid(n))
	if not live.is_empty():
		var mid:Vector2 = Vector2.ZERO
		for n:Node2D in live: mid += n.get_global_transform_with_canvas().origin
		mid /= float(live.size())
		var k:float = float(image.get_width())/root.get_visible_rect().size.x
		var side:int = int(420.0*k)
		var rect:=Rect2i(Vector2i(mid*k)-Vector2i(side/2,side/2),Vector2i(side,side)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		image.get_region(rect).save_png("user://haochen_real_%s_crop.png"%tag)
	return image

func glue(hero:Node2D,donor:Node2D,center:Vector2) -> void:
	var away:Vector2 = center-hero.global_position
	donor.global_position = hero.global_position+(away.normalized() if away.length()>8.0 else Vector2.RIGHT)*60.0

func group_report(group:String) -> String:
	var nodes:Array[Node]=get_nodes_in_group(group)
	if nodes.is_empty():return group+"=0"
	var p:CanvasItem=nodes[0] as CanvasItem
	var view:Rect2=root.get_visible_rect()
	var screen:Vector2=p.get_global_transform_with_canvas().origin
	var world_scale:Vector2=p.get_global_transform_with_canvas().get_scale()
	return "%s=%d parent=%s vis=%s z=%d screen=%s in_view=%s canvas_scale=%s mod=%s" % [group,nodes.size(),str(p.get_parent().get_path()),str(p.is_visible_in_tree()),p.z_index,str(screen),str(view.has_point(screen)),str(world_scale),str(p.self_modulate)]

func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func():print("HAOCHEN_REAL_TIMEOUT");quit(2))
	game=root.get_node("Game")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var hero:Node2D=load("res://scenes/characters/我的世界/皓宸.tscn").instantiate()
	hero.name="RealHaochen";hero.Team="Team0";hero.position=center
	world.add_child(hero,true)
	var donor:Node2D=load("res://scenes/characters/我的世界/苦力怕.tscn").instantiate()
	donor.name="RealCreeper";donor.Team="Team1";donor.position=center+Vector2(60,0)
	world.add_child(donor,true)
	await process_frame
	hold(donor)
	focus = [hero,donor]
	var hero_long:float = maxf(hero.image.texture.get_width(),hero.image.texture.get_height())*hero.image.scale.x
	var donor_long:float = maxf(donor.image.texture.get_width(),donor.image.texture.get_height())*absf(donor.image.scale.x) if donor.image is Sprite2D and donor.image.texture else 205.0
	var box:Vector2 = hero.collision_shape_2d.shape.size
	print("HAOCHEN_REAL size hero_long=",hero_long," standard_long=",donor_long," collision=",box)
	check(absf(hero_long-102.5)<0.6,"head front auto-fits to half of the standard 205 character size")
	# Visible head incl. protruding hat layer is 144x128 -> auto-fit collision 0.88/0.82 of 102.5 x 91.1.
	check(absf(box.x-90.2)<1.0 and absf(box.y-0.82*102.5*128.0/144.0)<1.0,"collision box is halved and follows the full head-front shape")
	print("HAOCHEN_REAL runtime=",world.is_combat_runtime_active()," view=",root.get_visible_rect()," canvas=",root.canvas_transform," hero_scale=",hero.scale," hero_screen=",hero.get_global_transform_with_canvas()," image_scale=",hero.image.scale)
	var cam:Camera2D=root.get_camera_2d()
	print("HAOCHEN_REAL camera=",cam.get_path() if cam else "none"," zoom=",cam.zoom if cam else Vector2.ZERO)
	# Real hero physics/AI keep running; the frozen enemy is kept 60px beside it.
	for i:int in range(48):
		glue(hero,donor,center)
		await physics_frame
	await shot("charging")
	print("HAOCHEN_REAL charging phase=",hero.charge_phase," energy=",hero.charge_energy," ",group_report("MCEnderParticle"))
	print("HAOCHEN_REAL charging ",group_report("MCHaochenChargeParticle"))
	print("HAOCHEN_REAL aura ",group_report("MCHaochenAuraParticle"))
	check(get_nodes_in_group("MCHaochenAuraParticle").size()>=3,"real charging keeps souls rising around Haochen")
	var drain:Array[Node] = []
	for raw:Node in get_nodes_in_group("MCHaochenChargeParticle"):
		if int(raw.get_meta("haochen_stream_owner",0))==hero.get_instance_id():drain.append(raw)
	# Both units move after emission, so allow travel slack around spawn-time ends.
	var flows:bool = drain.size()>=3
	for p:Node in drain:
		# Units keep moving after emission: assert each soul travels in from afar and ends on Haochen.
		flows = flows and p._motion.length()>=25.0 and (p._start+p._motion).distance_to(hero.global_position)<=18.0
	check(flows,"real charging continuously streams native souls from the feeding enemy into Haochen")
	var t:float=0.0
	while hero.charge_phase!=hero.Phase.COPYING and t<8.0:
		glue(hero,donor,center)
		await physics_frame
		t+=1.0/60.0
	print("HAOCHEN_REAL copy_started=",hero.charge_phase==hero.Phase.COPYING," after=",snappedf(t,0.01))
	await create_timer(0.3,true,false,true).timeout
	await shot("copying")
	print("HAOCHEN_REAL copying ",group_report("MCHaochenLinkParticle")," | ",group_report("MCHaochenCopyParticle"))
	check(get_nodes_in_group("MCHaochenLinkParticle").size()>=12,"real copy cast keeps a soul link from the copied character to Haochen")
	check(get_nodes_in_group("MCHaochenBurstParticle").size()>=10,"full meter bursts souls out of Haochen")
	var reqs:Array[Node]=get_nodes_in_group("MCCharacterCopyRequest")
	if not reqs.is_empty():print("HAOCHEN_REAL request link_visible=",reqs[0].link_visible," from=",reqs[0].link_from," to=",reqs[0].link_to," runtime=",reqs[0]._runtime_active())
	await create_timer(0.6,true,false,true).timeout
	await shot("after")
	print("HAOCHEN_REAL after copies=",hero.completed_copies)
	print("HAOCHEN_REAL after ",group_report("MCHaochenCopyParticle"))
	check(hero.completed_copies==1,"real battle tick completes the copy")
	# Task 8: the chosen "soul rise" spawn effect is really on screen in the battle view.
	var rising:int=0
	for s:Node in get_nodes_in_group("MCHaochenSpawnRiseParticle"):
		if s.visible:rising+=1
	check(rising>=3,"real battle: cyan souls rise from the new copy's body (%d visible)" % rising)
	var copy_voice:bool=false
	for node:Node in get_nodes_in_group("MCHaochenAudio"):
		if node.get_meta("haochen_event",&"")==&"copy_complete" and str(node.stream.resource_path).get_file().begins_with("illusioner.mirror_move_"):copy_voice=true
	check(copy_voice,"real battle: the copy appears with the illusioner mirror_move sound")
	await create_timer(0.35,true,false,true).timeout
	await shot("rise")
	print("HAOCHEN_REAL_DIR ",ProjectSettings.globalize_path("user://"))
	world.queue_free()
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings=saved
	print("HAOCHEN_REAL_BATTLE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
