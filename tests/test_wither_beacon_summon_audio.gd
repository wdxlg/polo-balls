extends "res://scripts/training/test_mc_new5.gd"
## Exercise the real supporting platform, flight/flash frames, health bar visibility and vanilla sounds.
const FX=preload("res://scripts/characters/我的世界/wither/beacon_summon_fx.gd")
const SOUNDS=preload("res://scripts/characters/我的世界/wither/audio.gd")
var beacon:Node2D

func check(ok:bool,label:String) -> void:
	super.check(ok,label)
	if ok: print("PASS: "+label)
func advance(dt:float) -> void:
	beacon.clock+=dt
	beacon.step_mob(dt)
	beacon._process(0)
func sound_count(event:String) -> int:
	var count:int=0
	for node:Node in world.get_children():
		if node is AudioStreamPlayer2D and node.stream==SOUNDS.STREAMS[event]: count+=1
	return count

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode=false
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(55).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	# An intervening physical platform must win over the map's lower ground.
	var platform:StaticBody2D=obstacle(Vector2(0,54),true)
	(platform.get_child(0).shape as RectangleShape2D).size=Vector2(260,12)
	await physics_frame
	var wither:Node2D=spawn("凋灵",Vector2(0,-155))
	wither.summoned=true
	wither.health=250
	var heart_sound_before:int=sound_count("heart")
	wither.on_actual_health_damage_received(1,251)
	beacon=wither.beacon
	beacon.state_machine.set_physics_process(false)
	await process_frame # deferred initialization raycasts after the node and platform enter the world
	beacon._process(0)
	var body_half:float=beacon._body.shape.get_rect().size.y*absf(beacon._body.global_scale.y)*0.5
	var platform_top:float=center.y+54-6.0
	check(sound_count("heart")>heart_sound_before,"wither shoots nether star with heart sound")
	check(absf(beacon._summon_target.x-wither.global_position.x)<.1 and absf(beacon._summon_target.y-(platform_top-body_half))<1.0,"arrival ray hits the first real platform below the Wither, not the bottom of the map")
	check(beacon._summon_origin.distance_to(wither.global_position)<.1 and beacon._summon_flight>=.68 and beacon._summon_flight<=1.12,"flight begins at the Wither and lasts according to the actual gap")
	check(not beacon.image.visible and not beacon.health_bar.visible and beacon._summon_fx.star.visible and beacon._summon_fx.star.texture==beacon.HEART_TEXTURE,"real Nether Star appears while beacon block and health bar remain hidden")
	check(beacon._summon_fx.trail.texture==FX.SPARK and beacon._summon_fx.trail.amount>=20,"travel uses a textured Nether Star particle trail")
	var first_target:Vector2=beacon._summon_target
	advance(.29)
	var portion:float=beacon._summon_elapsed/beacon._summon_flight
	var axis:Vector2=first_target-beacon._summon_origin
	var line_point:Vector2=beacon._summon_origin.lerp(first_target,portion*portion*(3.0-2.0*portion))
	check(beacon._summon_fx.star.global_position.distance_to(FX.flight_position(beacon._summon_origin,first_target,portion))<1.0 and beacon._summon_fx.star.global_position.distance_to(line_point)>4.0 and axis.length()>100,"rotating star follows a gently bent curve instead of a straight vertical line")
	check(absf(beacon._summon_fx.star.global_rotation)>0.1 and beacon._summon_fx.trail.emitting,"Z-axis star rotation and particles progress with simulation time")
	var frozen_position:Vector2=beacon._summon_fx.star.global_position
	var frozen_rotation:float=beacon._summon_fx.star.global_rotation
	beacon._process(.5)
	check(beacon._summon_fx.star.global_position==frozen_position and beacon._summon_fx.star.global_rotation==frozen_rotation,"render-only frames never advance flight or rotation")
	for i:int in range(40):
		if beacon._summon_elapsed>=beacon._summon_flight+.03: break
		advance(.03)
	check(beacon.landed and beacon._activated and not beacon.image.visible and not beacon.health_bar.visible and beacon._summon_fx.star.visible,"a landed real body waits for the star's arrival tremble before showing the block and health bar")
	var tremble_before:Vector2=beacon._summon_fx.star.global_position
	advance(.025)
	check(beacon._summon_fx.star.global_position.distance_to(tremble_before)>.1 and beacon._summon_fx.star.global_position.distance_to(beacon.global_position)<2,"only the star trembles over the platform; the hitbox does not shake")
	var morph_sound_before:int=sound_count("beacon_morph")
	for i:int in range(36):
		if beacon._summon_morph_at>=0.0: break
		advance(.01)
	var fx:Node2D=beacon._summon_fx
	var settled_scale:Vector2=fx._normal_scale
	check(beacon._summon_morph_at>=0.0 and beacon.image.visible and beacon.health_bar.visible and not fx.star.visible and not fx.trail.emitting,"star becomes the beacon and shows health bar at the first supported landing")
	check(sound_count("beacon_morph")>morph_sound_before,"beacon morph triggers conduit activation sound effect")
	check(fx.white_flash.visible and fx.white_flash.material is ShaderMaterial and fx.white_flash.material.shader==FX.WHITE and fx.white_flash.self_modulate.a>.95,"first morph frame overlays a white silhouette")
	check(beacon.image.scale.x>settled_scale.x*1.18,"white impact briefly enlarges the beacon")
	var packet:Dictionary=beacon.visual_state()
	check(packet.summon_origin==beacon._summon_origin and packet.summon_target==beacon.global_position and packet.summon_morph_at>=0.0,"multiplayer visual state includes the path and morph timestamp")
	advance(.12)
	check(beacon.image.scale.x<settled_scale.x and fx.white_flash.self_modulate.a<.5,"elastic recoil briefly shrinks below normal size as the flash rapidly fades")
	advance(.35)
	check(beacon.image.scale.is_equal_approx(settled_scale) and beacon.image.visible and beacon.health_bar.visible and not fx.star.visible,"elastic bounce settles and health bar stays visible")

	# Test wither dash / charge sound
	var charge_sound_before:int=sound_count("charge")
	wither._begin_charge_at(wither.global_position+Vector2(50,0))
	check(sound_count("charge")>charge_sound_before,"wither charge plays wither_charge sound")

	# A valid enemy starts the warning, then all three emission sounds and the
	# ambient loop start at the exact firing transition; no audio on landing.
	var enemy:Node2D=spawn("",Vector2(0,-130),"Team1")
	enemy.Max_health=1000
	enemy.health=1000
	beacon.beam_timer=0
	var activate_before:int=sound_count("beacon_activate")
	advance(.01)
	check(beacon.warning_left>0 and not beacon._beacon_hum.playing and sound_count("beacon_activate")==activate_before,"warning/arrival play no activation or hum")
	advance(beacon.warning_left)
	check(beacon.firing_left>0 and sound_count("beacon_activate")>activate_before and sound_count("beacon_power")>0 and beacon._beacon_hum.playing and beacon._beacon_hum.stream.loop,"firing synchronizes activation, power selection and looping vanilla ambient")
	game.now_stop_state=true
	beacon._process(.3)
	check(beacon._beacon_hum.volume_db<-60 and beacon._beacon_hum.playing,"combat pause silences the hum without restarting the loop")
	game.now_stop_state=false
	beacon._process(0)
	check(beacon._beacon_hum.volume_db==-4 and beacon._beacon_hum.playing,"unpause resumes the same humming stream")
	var deactivated_before:int=sound_count("beacon_deactivate")
	advance(beacon.firing_left+.01)
	check(beacon.firing_left==0 and not beacon._beacon_hum.playing and sound_count("beacon_deactivate")>deactivated_before,"beam shutdown stops humming and plays vanilla deactivation")
	beacon.beam_timer=0
	advance(.62)
	check(beacon._beacon_hum.playing,"subsequent emissions restart ambient cleanly")
	deactivated_before=sound_count("beacon_deactivate")
	beacon.Die()
	check(not beacon._beacon_hum.playing and sound_count("beacon_deactivate")>deactivated_before and not beacon._summon_fx.star.visible,"beacon death stops audio and clears any arrival visuals")
	print("BEACON_SUMMON_AUDIO: %d checks / %d failures"%[checks,failures])
	await clear_units()
	finish(0 if failures==0 else 1)
