extends "res://tests/test_sulfur_cube_balance.gd"
## Actual rendered grayscale/painter pixels and real GameplayRecord PCM.
class BarProbe extends Node2D:
	var bar:Script
	func _draw() -> void:
		bar.paint(self,Rect2(0,0,110,16),0.6,0.6)

func frozen(unit:Node) -> void:
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.Has_Collision_Damage=false
	if unit.health_bar!=null:unit.health_bar.hide()

func pixels(image:Image,rect:Rect2i) -> Dictionary:
	var count:int=0
	var chromatic:int=0
	var maximum:float=0.0
	for y:int in range(maxi(rect.position.y,0),mini(rect.end.y,image.get_height())):
		for x:int in range(maxi(rect.position.x,0),mini(rect.end.x,image.get_width())):
			var c:Color=image.get_pixel(x,y)
			if c.a<0.4:continue
			count+=1
			var spread:float=maxf(c.r,maxf(c.g,c.b))-minf(c.r,minf(c.g,c.b))
			maximum=maxf(maximum,spread)
			if spread>0.04:chromatic+=1
	return {"visible":count,"colored":chromatic,"spread":maximum}

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func():print("HAOCHEN_VISUAL_TIMEOUT");quit(2))
	game=root.get_node("Game")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	var stopped:bool=game.now_stop_state
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Have_Team_Damage=false
	AudioServer.set_bus_mute(0,false)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world.set_process(false);world.set_physics_process(false)
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var hero:Node2D=load("res://scenes/characters/我的世界/皓宸.tscn").instantiate()
	hero.name="VisualHaochen";hero.Team="Team0";hero.position=center
	world.add_child(hero);frozen(hero)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(256,150)
	viewport.transparent_bg=true
	viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world.add_child(viewport)
	var layer:=Node2D.new();viewport.add_child(layer)
	var original:Node2D=load("res://scenes/characters/我的世界/苦力怕.tscn").instantiate()
	original.name="ColoredOriginal";original.Team="Team1";original.position=Vector2(64,65)
	layer.add_child(original);frozen(original)
	original.scale=Vector2.ONE*0.35
	var tools:Script=load("res://scripts/characters/投稿角色工具.gd")
	var snapshot:Dictionary=tools.capture_character_template(original)
	var copy:Node2D=tools.spawn_character_copy(hero,snapshot,Vector2(190,65),0.5,{"owner":hero,"parent":layer,"full_vitals":true,"monochrome":true})
	frozen(copy);copy.scale=original.scale
	for i:int in range(12):await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=viewport.get_texture().get_image()
	var a:Dictionary=pixels(image,Rect2i(32,32,64,65))
	var b:Dictionary=pixels(image,Rect2i(158,32,64,65))
	print("HAOCHEN_GPU original=",a," copy=",b)
	check(a.visible>100 and a.colored>30,"real native Creeper renderer produces colored body pixels")
	check(b.visible>100 and b.colored==0 and b.spread<0.01,"copied live3D/Creep body actually renders grayscale, not just gray modulation")
	check(original.image.get_instance_shader_parameter("character_grayscale")==null or original.image.get_instance_shader_parameter("character_grayscale")==0.0,"original shared material instance is not desaturated by the copy")
	image.save_png("user://haochen_monochrome_gpu.png")
	print("HAOCHEN_GPU_IMAGE ",ProjectSettings.globalize_path("user://haochen_monochrome_gpu.png"))

	var bar_view:=SubViewport.new()
	bar_view.size=Vector2i(142,52);bar_view.transparent_bg=true;bar_view.world_2d=World2D.new()
	bar_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;world.add_child(bar_view)
	var bar:=BarProbe.new();bar.bar=hero.BAR;bar.position=Vector2(16,18);bar_view.add_child(bar)
	await process_frame;await RenderingServer.frame_post_draw
	var bi:Image=bar_view.get_texture().get_image()
	var fill:Color=bi.get_pixel(30,24);var empty:Color=bi.get_pixel(112,24);var outer:Color=bi.get_pixel(13,24)
	check(fill.r>fill.g and fill.r>0.7 and empty.r<0.2 and outer.r<0.1,"shared meter renders the original white-to-red fill, dark trough and near-black outer frame")
	bi.save_png("user://haochen_shared_bar_gpu.png")

	# A real request emits existing native particle objects in its own viewport.
	var request:Node2D=load("res://scenes/effects/我的世界/角色复制请求.tscn").instantiate()
	request.position=Vector2(125,110);request.remaining=10.0;request.cast_duration=10.0
	layer.add_child(request);request.set_physics_process(false)
	await process_frame;await process_frame
	check(get_nodes_in_group("MCHaochenCopyParticle").size()>0 and get_nodes_in_group("MCHaochenBurstParticle").size()>=10,"copy cast instantiates native soul gathering plus the full-meter burst")
	# Native generic_0 starts transparent/small; inspect the developed animation,
	# not only the first two frames before its original atlas becomes visible.
	await create_timer(0.24,true,false,true).timeout
	await RenderingServer.frame_post_draw
	var particle_image:Image=viewport.get_texture().get_image()
	check(pixels(particle_image,Rect2i(95,84,65,56)).visible>5,"native copy-gathering particles are actually visible in GPU output")
	particle_image.save_png("user://haochen_copy_particles_gpu.png")

	var preview_hero:Node2D=load("res://scenes/characters/我的世界/皓宸.tscn").instantiate()
	preview_hero.name="PreviewHaochen";preview_hero.Team="Team0";preview_hero.position=Vector2(125,64)
	layer.add_child(preview_hero);frozen(preview_hero)
	preview_hero.charge_energy=65.0;preview_hero.charge_phase=preview_hero.Phase.CHARGING
	preview_hero.scale=Vector2.ONE*0.35
	await process_frame;await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("user://haochen_feature_preview.png")

	# Isolate the actual custom phrase on the existing game recording bus.
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		node.stop();node.free()
	var bus:int=AudioServer.get_bus_index(&"GameplayRecord")
	var capture:=AudioEffectCapture.new();capture.buffer_length=5.0
	var index:int=AudioServer.get_bus_effect_count(bus);AudioServer.add_bus_effect(bus,capture)
	var donor:Node2D=load("res://scenes/ball.tscn").instantiate()
	donor.name="VoiceDonor";donor.Team="Team1";donor.position=center+Vector2(20,0)
	world.add_child(donor);frozen(donor)
	hero._scan_left=0.0;hero._step_energy(0.1)
	await process_frame;await process_frame
	var voices:Array[Node]=[]
	for node:Node in get_nodes_in_group("MCHaochenAudio"):
		if node.get_meta("haochen_event",&"")==&"charge_start":voices.append(node)
	check(voices.size()==1,"entering real charging state starts the requested phrase exactly once")
	if not voices.is_empty():
		check(voices[0].stream.resource_path=="res://audio/characters/我的世界/haochen/charge_start.wav" and voices[0].volume_db==0.0,"playback uses the relocated original WAV at its default gain")
		check(absf(voices[0].stream.get_length()-2.368435)<0.002,"the supplied phrase (task 11 recording from 今天搬哪个.mp4) is played in full, not trimmed")
	for i:int in range(10):hero._step_energy(0.05)
	await create_timer(2.8,true,false,true).timeout
	var frames:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
	var peak:float=0.0
	for sample:Vector2 in frames:peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	check(frames.size()>44100 and peak>0.001,"real GameplayRecord capture contains audible PCM from the start phrase")
	check(hero._sound_serial==1,"continued charging does not replay the phrase every tick")
	print("HAOCHEN_PCM frames=",frames.size()," peak=",peak)
	var wave:=AudioStreamWAV.new();wave.format=AudioStreamWAV.FORMAT_16_BITS;wave.stereo=true;wave.mix_rate=AudioServer.get_mix_rate()
	var data:=PackedByteArray();data.resize(frames.size()*4)
	for i:int in range(frames.size()):
		data.encode_s16(i*4,roundi(clampf(frames[i].x,-1.0,1.0)*32767.0));data.encode_s16(i*4+2,roundi(clampf(frames[i].y,-1.0,1.0)*32767.0))
	wave.data=data;wave.save_to_wav("user://haochen_start_actual_pcm.wav")
	print("HAOCHEN_PCM_FILE ",ProjectSettings.globalize_path("user://haochen_start_actual_pcm.wav"))
	AudioServer.remove_bus_effect(bus,index)
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings=saved;game.now_stop_state=stopped
	print("HAOCHEN_VISUAL_AUDIO checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
