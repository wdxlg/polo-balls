extends "res://tests/test_mc_snow_golem.gd"
var AUDIO:Script
var HEADS:Script
func phase_players(phase:String) -> Array:
	var result:Array = []
	for node:Node in get_nodes_in_group("MCSnowSound"):
		if not node.is_queued_for_deletion() and str(node.get_meta("mc_snow_phase","")) == phase: result.append(node)
	return result
func clear_phase_players() -> void:
	for node:Node in get_nodes_in_group("MCSnowSound"):
		if node.has_meta("mc_snow_phase"):
			node.stop()
			node.remove_from_group("MCSnowSound")
			node.remove_from_group("MCNativeSFX")
			node.queue_free()
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(50.0).timeout.connect(func(): finish(2))
	AUDIO = load("res://scripts/characters/我的世界/snow_golem/audio.gd")
	HEADS = load("res://scripts/characters/我的世界/snow_golem/heads_view.gd")
	var source:Node2D = spawn(GOLEM_PATH,center)
	var mini:Node2D = spawn(MINI_PATH,center+Vector2(-96,0))
	var field:Node2D = source._field
	field.set_physics_process(false)
	check(source.Max_health == 360 and mini.Max_health == 150 and mini.health == 150,"mini keeps its existing lower health")
	var fields:Array[String] = ["Damage","Speed","Attack_Cooling","Skill_Cooling","Health_Restore","Damage_reduction","max_block","max_energy","snowball_speed","shot_cold","snow_cold","freeze_duration","snow_tick_interval","snow_damage_multiplier","snowball_knockback","attack_range","aim_hold_duration"]
	for key:String in fields: check(mini.get(key) == source.get(key),"mini matches normal combat parameter: "+key)
	check(mini.miniature and mini.global_scale.is_equal_approx(source.global_scale*0.65),"small form is retained instead of becoming a full-sized duplicate")
	mini.lay_trail()
	check(field.patches[FIELD.cell_at(mini.global_position)].level == 1,"the explicitly requested harmless half-trail mechanic is retained")

	# Configured base stats propagate; temporary runtime modifiers do not become permanent.
	source.default_properties.Damage = 12
	source.default_properties.Speed = 93.0
	source.default_properties.Attack_Cooling = 1.7
	source.Damage = 99
	source.Speed = 20.0
	source.snowball_knockback = 9.0
	var settings:Dictionary = source.mini_spawn_settings()
	field._spawn_mini("StatInheritanceMini",center+Vector2(-192,0),settings)
	var custom:Node2D = world.get_node("StatInheritanceMini")
	custom.state_machine.set_physics_process(false)
	check(custom.Max_health == 150 and custom.Damage == 12 and custom.Speed == 93.0 and is_equal_approx(custom.Attack_Cooling,1.7) and custom.snowball_knockback == 9.0,"birth matches parent base configuration except health, without copying temporary 99 damage/20 speed")
	field._spawn_mini("StatInheritanceGrandchild",center+Vector2(-240,0),custom.mini_spawn_settings())
	var grandchild:Node2D = world.get_node("StatInheritanceGrandchild")
	grandchild.state_machine.set_physics_process(false)
	check(grandchild.Max_health == 150 and grandchild.Damage == custom.Damage and grandchild.Speed == custom.Speed and grandchild.global_scale == custom.global_scale,"later generations keep both matching combat stats and fixed mini size")
	source.default_properties.Damage = 6
	source.default_properties.Speed = 80.0
	source.default_properties.Attack_Cooling = 2.0
	source.Damage = 6
	source.Speed = 80.0
	source.snowball_knockback = 8.0

	# Head renderer uses preserved native aspect and scale-aware compact geometry.
	source.direction = Vector2.RIGHT
	source.visual_mob()
	var id:int = field.drop_head(source)
	var head:Dictionary = field.heads[id]
	var size:Vector2 = HEADS.block_size(head)
	check(is_equal_approx(size.x,13.0) and size.x < FIELD.CELL*0.6,"normal dropped pumpkin is compact, not a full 24px terrain cube")
	check(is_equal_approx(size.y/size.x,float(HEADS.PUMPKIN.get_height())/HEADS.PUMPKIN.get_width()),"native cube texture is not stretched into an incorrect square")
	check(HEADS.layer_rise(head) < size.y and HEADS.layer_rise(head) > size.y*0.70,"stack rise matches the projected cube's vertical face instead of leaving gaps")
	check(head.start.is_equal_approx(source.image.to_global(source.image.offset+Vector2(0,-32))),"fall begins at the attached native head center rather than far above the actor")
	check(head.face_right == source.is_character_visual_flipped_h(),"detached head keeps its original left/right facing")
	var pose:Dictionary = field._head_view.flight_pose(head)
	check(pose.point.is_equal_approx(head.start) and is_zero_approx(pose.angle),"flight starts without a position or tilt discontinuity")
	head.elapsed = head.duration
	var dry:Dictionary = field._head_view.flight_pose(head)
	check(dry.point.is_equal_approx(head.point-Vector2(0,size.y*0.5)),"dry landing aligns cube center with the grounded sprite anchor")
	head.elapsed = 0.0
	field.deposit(source,head.cell,false)
	head.elapsed = head.duration
	var stacked:Dictionary = field._head_view.flight_pose(head)
	check(stacked.point.is_equal_approx(head.point-Vector2(0,size.y*0.5+HEADS.layer_rise(head))),"snow absorption lands smoothly at one-block height rather than jumping upward")
	head.elapsed = 0.0
	field.advance(0.33)
	check(field.heads[id].landed and field.heads[id].blocks == 1,"visual refinement preserves actual absorption/build mechanics")
	var mini_id:int = field.drop_head(mini)
	var mini_size:Vector2 = HEADS.block_size(field.heads[mini_id])
	check(is_equal_approx(mini_size.x,size.x*0.65),"mini's dropped pumpkin and snow stack scale down with its own body")
	var snapshot:Array = field._head_snapshot()
	check(snapshot[0].has("visual_scale") and snapshot[0].has("face_right") and not snapshot[0].has("source"),"network head snapshots preserve proportions/facing without unsafe owner references")

	# All transition clips are actual decoded vanilla resources.
	var decoded:bool = true
	for event:String in AUDIO.PHASES.EVENTS:
		for record:Dictionary in AUDIO.PHASES.EVENTS[event]: decoded = decoded and record.stream is AudioStreamOggVorbis and record.stream.get_length() > 0.0
	check(decoded and AUDIO.PHASES.EVENTS.size() == 5,"new material cues decode from original Minecraft OGG files")
	check(AUDIO.PHASES.EVENTS.has("mc_snow.ice_hit") and AUDIO.PHASES.EVENTS["mc_snow.ice_hit"].size() == 3 and AUDIO.PHASES.EVENTS["mc_snow.ice_hit"][0].pitch > 1.0,"frozen-hit cue reuses the three original glass break clips pitched up")
	check(AUDIO.PHASES.EVENTS.has("entity.player.hurt_freeze") and AUDIO.PHASES.EVENTS["entity.player.hurt_freeze"].size() == 5,"freeze cue owns the five original powder-snow freeze_hurt clips")
	var victim:Node2D = dummy(center+Vector2(168,96))
	var cold:Node2D = COLD.ensure(victim)
	clear_phase_players()
	cold.add_cold(25.0,1.4)
	check(phase_players("freeze").is_empty(),"partial cold does not play a premature ice-placement cue")
	cold.add_cold(75.0,1.4)
	cold.set_physics_process(false)
	cold.set_process(false)
	check(phase_players("freeze").size() == 1 and phase_players("freeze")[0].get_meta("mc_sound_event") == "entity.player.hurt_freeze","real threshold crossing plays exactly one vanilla freeze cue instead of a stone placement thud")
	check(phase_players("freeze")[0].volume_db >= AUDIO.PHASE_GAIN_DB-0.01,"freeze cue is boosted above normal volume so it is audible over the same-frame impact sound")
	cold.add_cold(100.0,1.4)
	for i:int in range(8): cold._ice.refresh()
	check(phase_players("freeze").size() == 1,"frozen hits and visual refreshes do not retrigger placement sound")
	# 冻住期间被打：真实扣血 → 一次冰碎脆响；同一节流窗口内再打不重复；窗口过后再打再响。护盾被削也算被打。
	check(phase_players("ice_hit").is_empty(),"freezing itself does not play the frozen-hit cue")
	cold.advance(0.01)
	check(phase_players("ice_hit").is_empty(),"an idle frozen frame plays no hit cue")
	victim.receive_positional_damage(4.0,victim.global_position,true,source)
	cold.advance(0.01)
	check(phase_players("ice_hit").size() == 1 and phase_players("ice_hit")[0].get_meta("mc_sound_event") == "mc_snow.ice_hit","a real hit on a frozen victim plays one ice-crack cue")
	victim.receive_positional_damage(4.0,victim.global_position,true,source)
	cold.advance(0.01)
	check(phase_players("ice_hit").size() == 1,"hits inside the throttle window share one cue")
	cold.advance(0.1)
	victim.block = 10.0
	cold.advance(0.01)
	check(phase_players("ice_hit").size() == 1,"gaining block is not a hit")
	victim.receive_positional_damage(4.0,victim.global_position,false,source)
	cold.advance(0.01)
	check(phase_players("ice_hit").size() == 2 and victim.block < 10.0,"a blocked hit still cracks the ice")
	check(cold.frozen_hit_count == 2,"frozen hit counter matches the cues")
	victim.block = 0.0
	cold.advance(0.01)
	game.now_stop_state = true
	cold.advance(5.0)
	check(phase_players("ice_break").is_empty(),"pause cannot prematurely trigger the break cue")
	game.now_stop_state = false
	cold.advance(1.41)
	check(phase_players("ice_break").size() == 1 and phase_players("ice_break")[0].get_meta("mc_sound_event") == "block.glass.break","actual thaw/fragment release plays one original glass/ice break sound")
	cold.advance(1.0)
	check(phase_players("ice_break").size() == 1,"an already thawed component cannot repeatedly play the break sound")
	var mirror_victim:Node2D = dummy(center+Vector2(192,144))
	var mirror:Node2D = COLD.ensure(mirror_victim)
	mirror.set_multiplayer_authority(2)
	var freeze_count_before:int = phase_players("freeze").size()
	mirror.accept_state(0.0,0.2,1.4)
	mirror._process(0.21)
	check(phase_players("freeze").size() == freeze_count_before and phase_players("ice_break").size() == 1,"visual replica prediction does not duplicate the authority's reliable transition sounds")

	# A real deferred construction completion emits snow + pumpkin placement once.
	clear_phase_players()
	field.deposit(source,head.cell,false)
	await process_frame
	check(not field.heads.has(id),"second real snow layer consumes the construction stack")
	var birth:Array = phase_players("mini_birth")
	check(birth.size() == 2,"one completed mini uses the two native material-placement layers")
	var events:Array = []
	for player:Node in birth: events.append(str(player.get_meta("mc_sound_event")))
	check(events.has("block.snow.place") and events.has("block.wood.place"),"birth sounds match the snow body and carved pumpkin materials")
	var loud:bool = true
	for player:Node in birth: loud = loud and player.volume_db >= 0.0 and player.is_in_group("BattleTransient")
	check(loud,"construction completion cues use normal level and belong to the battle")
	await physics_frame
	await process_frame
	var playing:bool = true
	for player:Node in birth: playing = playing and is_instance_valid(player) and player.playing
	check(playing,"new native construction sounds actually start playback")
	game.now_stop_state = true
	field._process(0.0)
	var paused_all:bool = true
	for player:Node in birth: paused_all = paused_all and is_instance_valid(player) and player.stream_paused
	check(paused_all,"active phase/construction sounds pause with gameplay")
	game.now_stop_state = false
	field._process(0.0)
	world.reset()
	await process_frame
	await process_frame
	check(get_nodes_in_group("MCSnowSound").is_empty(),"reset removes all phase cues instead of leaving detached sound players")
	print("SNOW_BUILD_REVISION_RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
