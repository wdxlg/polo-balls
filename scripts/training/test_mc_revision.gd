extends "res://scripts/training/test_mc_new5.gd"
var capture:AudioEffectCapture
var fx_script:Script
func clear_sounds() -> void:
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		player.call("stop")
		player.queue_free()
	await process_frame
func heard(event:String) -> bool:
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","")==event and not player.is_queued_for_deletion(): return true
	return false
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	create_timer(65).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var audio:Script=load("res://scripts/characters/我的世界/new5/audio.gd")
	fx_script=load("res://scripts/effects/我的世界/mc_explosion.gd")
	for event:String in audio.EVENTS:
		check(audio.EVENTS[event].size()>0,"original variants "+event)
		for record:Dictionary in audio.EVENTS[event]:
			check(record.stream is AudioStreamOggVorbis and record.stream.get_length()>0.01,"decodable original OGG "+event)
	var slime:Node2D=spawn("史莱姆",Vector2.ZERO)
	var ghast:Node2D=spawn("恶魂",Vector2(0,100))
	var fisher:Node2D=spawn("钓鱼竿",Vector2(0,200))
	var guardian:Node2D=spawn("守卫者",Vector2(-100,-120))
	var piston:Node2D=spawn("粘性活塞",Vector2(0,-200))
	for sign_value:float in [-1.0,1.0]:
		slime.airborne=true
		slime.jump_direction=Vector2(sign_value,0)
		slime.visual_mob()
		check(slime.is_character_visual_flipped_h()==(sign_value>0),"slime horizontal facing "+str(sign_value))
		ghast.drift=Vector2(sign_value,0)
		ghast.visual_mob()
		check(ghast.is_character_visual_flipped_h()==(sign_value>0),"ghast horizontal facing "+str(sign_value))
		for y:float in [-100.0,0.0,100.0]:
			fisher.facing=Vector2(sign_value*10,y).normalized()
			fisher.visual_mob()
			check(is_zero_approx(fisher.image.rotation),"fishing body never rotates toward vertical target")
			check(fisher.is_character_visual_flipped_h()==(sign_value<0),"fishing only flips left-right")
	# Corrected outer cheek must cover the former transparent atlas gap.
	var im:Image=guardian.PREVIEW.get_image()
	var old:Image=load("res://scripts/training/mc_new5_assets/before_visual_revision/Images/characters/我的世界/new5/guardian_00.png").get_image()
	var repaired:int=0
	for y:int in range(im.get_height()):
		for x:int in range(im.get_width()):
			if old.get_pixel(x,y).a<0.1 and im.get_pixel(x,y).a>0.9: repaired+=1
	check(repaired>100,"guardian missing face restored "+str(repaired)+" pixels")
	for extension:float in [piston.REST_EXTENSION,20.0,43.0]:
		piston.extension=extension
		piston.facing=Vector2.RIGHT
		piston.visual_mob()
		check(piston.image.texture==piston.CASE,"stationary piston case has no duplicate head")
		check(piston.head.texture==piston.PARTS.piston_head,"3D piston head texture")
		check(is_equal_approx(piston.head.global_position.x,piston.global_position.x+extension),"head stays on mechanical axis")
		check(piston.rod.global_position.x>piston.head.global_position.x,"candle attached in front of head")
	check(piston.get_node("PistonAssembly").get_child_count()==3,"one shaft, one head, one candle")
	# All five roles have real event hooks, no generic invented creature voices.
	await clear_sounds()
	audio._last.clear()
	slime.airborne=false
	slime.rest_left=0
	slime.direction=Vector2.RIGHT
	slime.step_mob(0.01)
	check(heard("entity.slime.jump"),"slime takeoff audio hook")
	slime.step_mob(0.8)
	check(heard("entity.slime.squish"),"slime landing audio hook")
	ghast.fire_at(center+Vector2(200,100))
	check(heard("entity.ghast.shoot"),"ghast fire audio hook")
	fisher.cast_at(center+Vector2(150,200))
	check(heard("entity.fishing_bobber.throw"),"fishing cast audio hook")
	var victim:Node2D=spawn("",Vector2(55,-200),"Team1")
	victim.health=10000
	piston.phase=0
	piston.extension=piston.REST_EXTENSION
	piston.direction=Vector2.RIGHT
	piston.step_mob(0.01)
	check(heard("block.piston.extend"),"piston extension audio hook")
	victim.global_position=guardian.global_position+Vector2(70,0)
	guardian.step_mob(0.01)
	check(heard("entity.guardian.attack"),"guardian beam audio hook")
	guardian.break_lock()
	check(not is_instance_valid(guardian._laser_player),"guardian cancelled beam stops linked sound")
	await clear_sounds()
	audio._last.clear()
	ghast.hurt_voice_chance=0
	ghast.receive_positional_damage(1,ghast.global_position+Vector2(5,0),false,victim)
	check(not heard("entity.ghast.hurt"),"hurt voice probability zero respected")
	ghast.hurt_voice_chance=1
	ghast.receive_positional_damage(1,ghast.global_position+Vector2(5,0),false,victim)
	check(heard("entity.ghast.hurt"),"actual HP damage triggers hurt voice")
	ghast._ambient_left=0
	ghast.tick_ambient(0.01)
	check(is_instance_valid(ghast._ambient_player),"ghast ambient starts")
	var ambient:AudioStreamPlayer2D=ghast._ambient_player
	if is_instance_valid(ambient):
		check(ghast._ambient_left>=ambient.stream.get_length()+ghast.ambient_gap_min-0.01,"ambient full duration plus random silence")
		ghast._ambient_left=0
		ghast.tick_ambient(0.01)
		check(ghast._ambient_player==ambient,"ambient not interrupted/restarted while playing")
		await physics_frame
		await process_frame
		game.now_stop_state=true
		ghast._process(0.1)
		check(ambient.stream_paused,"ambient pauses in setup")
		game.now_stop_state=false
		ghast._process(0.1)
		check(not ambient.stream_paused,"ambient resumes playback")
	# Real audio mixing, not only stream existence.
	await clear_sounds()
	audio._last.clear()
	for bus:int in range(AudioServer.bus_count):
		AudioServer.set_bus_mute(bus,false)
		AudioServer.set_bus_volume_db(bus,0)
	capture=AudioEffectCapture.new()
	capture.buffer_length=3.0
	AudioServer.add_bus_effect(0,capture)
	var voice:AudioStreamPlayer2D=ghast.play_sound("entity.generic.explode",-4.0)
	check(is_instance_valid(voice) and voice.playing,"explosion player actually playing")
	await create_timer(0.45).timeout
	var pcm:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
	var peak:float=0
	for sample:Vector2 in pcm: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	print("MC_REVISION_AUDIO_PCM ",pcm.size()," peak=",peak)
	check(peak>0.00001,"nonzero audio output captured")
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	capture=null
	# User's 16 frames, opaque greyscale, independent 3D smoke trajectories.
	var effect:Node2D=fx_script.spawn(world,center,55,{"seed":1234,"sound":false})
	effect.set_process(false)
	check(effect.FRAMES.get_frame_count(&"explode")==16,"all supplied explosion frames")
	var puffs:int=0
	var smokes:int=0
	for particle:Dictionary in effect.particles:
		if particle.smoke:
			smokes+=1
			check(particle.diameter<=55*0.17,"smoke much smaller than blast puffs")
			check(particle.velocity3.length()>50 and particle.velocity3.y>0,"smoke launched into 3D")
		else:
			puffs+=1
			check(particle.position3.length()<=55,"puffs originate within blast radius")
			check(particle.start_shade>=0.16 and particle.start_shade<=1,"puff white-to-dark-grey range")
	check(smokes>puffs and puffs>=8,"both particle layers spawned")
	for i:int in range(12): effect.advance_visual(1.0/60)
	var above:int=0
	var front:int=0
	var back:int=0
	for particle:Dictionary in effect.particles:
		check(is_equal_approx(particle.sprite.modulate.a,1.0),"no alpha fade")
		if particle.smoke:
			if particle.position3.y>5: above+=1
			if particle.position3.z>2: front+=1
			if particle.position3.z< -2: back+=1
	check(above>0 and front>0 and back>0,"smoke arcs have height and front/back depth")
	effect.advance_visual(2.0)
	check(effect.is_queued_for_deletion(),"explosion self-cleans after both animations")
	# Render a reusable effect showcase using the real Godot effect, independent
	# of the main world's camera and portrait UI.
	if DisplayServer.get_name()!="headless": await render_preview()
	await clear_units()
	await clear_sounds()
	finish(0 if failures==0 else 1)
func render_preview() -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(640,400)
	viewport.disable_3d=true
	viewport.transparent_bg=false
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world.add_child(viewport)
	var bg:=ColorRect.new()
	bg.size=Vector2(640,400)
	bg.color=Color(0.14,0.18,0.22)
	viewport.add_child(bg)
	var effect:Node2D=load("res://scenes/effects/我的世界/MC爆炸.tscn").instantiate()
	effect.position=Vector2(320,235)
	effect.scale=Vector2(2.2,2.2)
	effect.radius=55
	effect.visual_seed=1234
	effect.play_audio=false
	viewport.add_child(effect)
	effect.set_process(false)
	DirAccess.make_dir_recursive_absolute("user://mc_explosion_preview")
	for i:int in range(39):
		if not is_instance_valid(effect): break
		effect.advance_visual(1.0/30)
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("user://mc_explosion_preview/frame_%02d.png"%i)
	print("MC_REVISION_PREVIEW ",ProjectSettings.globalize_path("user://mc_explosion_preview"))
	viewport.queue_free()
