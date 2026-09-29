extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	var guardian:Node2D=spawn("守卫者",Vector2.ZERO,"Team0")
	var target:Node2D=spawn("",Vector2(180,0),"Team1")
	target.health=10000
	target.block=0
	target.Damage_reduction=0
	guardian.step_mob(0.01)
	check(guardian.locked==target,"aim acquires target")
	check(is_instance_valid(guardian._laser_player) and guardian._laser_player.playing,"native attack sound starts during aiming")
	check(is_equal_approx(guardian._laser_player.volume_db,1.0),"aim sound increased by 8 dB")
	var first_player:AudioStreamPlayer2D=guardian._laser_player
	guardian.step_mob(0.01)
	check(guardian._laser_player==first_player,"aim sound not restarted every frame")
	guardian.break_lock()
	check(not first_player.playing and guardian._laser_player==null,"interruption stops aiming audio")
	var cross:Node2D=spawn("",Vector2(90,0),"Team1")
	cross.health=10000
	cross.block=0
	cross.Damage_reduction=0
	clear_sounds(guardian)
	guardian.locked=target
	guardian.beam_end=target.global_position
	var main_hp:float=target.health
	var cross_hp:float=cross.health
	guardian._laser_hit()
	var crit:Array[Node]=event_players("entity.player.attack.crit")
	var hurt:Array[Node]=event_players("entity.player.hurt")
	check(crit.size()==1 and hurt.size()==1,"same laser hit plays critical and ordinary sounds independently")
	if crit.size()==1:
		check(crit[0].global_position.is_equal_approx(target.global_position),"critical sound at main target")
		check(is_equal_approx(crit[0].volume_db,guardian.impact_volume(main_hp-target.health)),"critical volume follows actual damage")
	if hurt.size()==1:
		check(hurt[0].global_position.is_equal_approx(cross.global_position),"ordinary sound at crossing target")
		check(is_equal_approx(hurt[0].volume_db,guardian.impact_volume(cross_hp-cross.health)),"crossing volume follows actual damage")
	check(is_equal_approx(main_hp-target.health,90.0) and is_equal_approx(cross_hp-cross.health,4.0),"laser damage unchanged")
	clear_sounds(guardian)
	guardian.damage_with_sound(target,0.0,true)
	check(event_players("entity.player.attack.crit").is_empty(),"zero damage has no critical hit sound")
	target.Team="Team0"
	guardian.damage_with_sound(target,90.0,true)
	check(event_players("entity.player.attack.crit").is_empty(),"friendly rejected hit has no critical sound")
	target.Team="Team1"
	# Actual-health-loss volume caps overkill at remaining HP.
	var fragile:Node2D=spawn("",Vector2(230,80),"Team1")
	fragile.health=3
	fragile.block=0
	fragile.Damage_reduction=0
	guardian.damage_with_sound(fragile,90.0,true)
	crit=event_players("entity.player.attack.crit")
	check(crit.size()==1,"lethal main-target hit still sounds")
	if crit.size()==1: check(is_equal_approx(crit[0].volume_db,guardian.impact_volume(3.0)),"overkill volume uses three HP not ninety raw damage")
	clear_sounds(guardian)
	target.global_position=center+Vector2(25,0)
	cross.global_position=center+Vector2(400,0)
	guardian.spike_phase=0
	guardian.spike_charging=false
	guardian._spike_left=0
	guardian.step_spikes(0.01)
	check(event_players("entity.puffer_fish.sting").is_empty(),"no extension sound during windup")
	guardian.step_spikes(0.31)
	check(event_players("entity.puffer_fish.sting").size()==1,"puffer sting plays at extension")
	check(event_players("entity.player.hurt").size()==1 and event_players("entity.player.attack.crit").is_empty(),"spike burst uses ordinary hurt alongside sting")
	hurt=event_players("entity.player.hurt")
	if hurt.size()==1: check(is_equal_approx(hurt[0].volume_db,guardian.impact_volume(18.0)),"burst volume matches eighteen damage")
	guardian._spike_burst_age=guardian.spike_hold_time+0.01
	guardian.advance_spike_phase()
	check(event_players("entity.puffer_fish.blow_out").size()==1,"puffer shrink plays on retraction transition")
	var shrink:AudioStreamPlayer2D=event_players("entity.puffer_fish.blow_out")[0]
	guardian.advance_spike_phase()
	check(event_players("entity.puffer_fish.blow_out").size()==1 and event_players("entity.puffer_fish.blow_out")[0]==shrink,"retraction sound not retriggered each frame")
	clear_sounds(guardian)
	guardian.spike_phase=2
	guardian._contact_hits.clear()
	target.global_position=center+Vector2(guardian.U.radius(guardian)+guardian.U.radius(target)-0.1,0)
	check(guardian.try_spike_contact(target),"extended contact accepted")
	hurt=event_players("entity.player.hurt")
	check(hurt.size()==1 and event_players("entity.player.attack.crit").is_empty(),"contact uses only ordinary hit")
	if hurt.size()==1: check(is_equal_approx(hurt[0].volume_db,guardian.impact_volume(2.0)),"contact volume matches two damage")
	check(guardian.impact_volume(2)<guardian.impact_volume(4) and guardian.impact_volume(4)<guardian.impact_volume(18) and guardian.impact_volume(18)<guardian.impact_volume(90),"volume increases with actual damage")
	clear_sounds(guardian)
	var second:Node2D=spawn("守卫者",Vector2(-180,0),"Team0")
	guardian.start_charge_sound()
	second.start_charge_sound()
	check(event_players("entity.guardian.attack").size()==2,"two guardians can aim audibly together")
	var once:AudioStreamPlayer2D=guardian._guardian_sound("entity.puffer_fish.sting",guardian.global_position,-4.0)
	var twice:AudioStreamPlayer2D=guardian._guardian_sound("entity.puffer_fish.sting",guardian.global_position,-4.0)
	check(once!=null and twice==null,"per-guardian event cooldown actually suppresses duplicates")
	for frames:SpriteFrames in [guardian.RETRACTED_FRAMES,guardian.HALF_FRAMES,guardian.FRAMES]:
		check(frames.get_animation_names().size()==64,"fixed tail atlas has all directions")
		for angle:int in range(64):
			check(frames.get_frame_count(StringName("v%02d"%angle))==8,"fixed tail atlas has all animation frames")
			for frame_index:int in range(8):
				var tex:AtlasTexture=frames.get_frame_texture(StringName("v%02d"%angle),frame_index)
				check(tex!=null and tex.atlas!=null and tex.region.size==Vector2(160,160),"all corrected atlas regions resolve")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
func event_players(event:String) -> Array[Node]:
	var result:Array[Node]=[]
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","")==event and not player.is_queued_for_deletion(): result.append(player)
	return result
func clear_sounds(guardian:Node) -> void:
	guardian._beam_sfx(false)
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		player.stop()
		player.remove_from_group("MCNativeSFX")
		player.queue_free()
	for event:String in ["entity.guardian.attack","entity.player.hurt","entity.player.attack.crit","entity.puffer_fish.sting","entity.puffer_fish.blow_out"]:
		guardian.set_meta("mc_event_sound_"+event.replace(".","_"),-10000)
