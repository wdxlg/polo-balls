extends "res://tests/test_mc_frontier.gd"
## Real swept spear tip, native user image and full physical mace rebound chain.
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")

func impact_count() -> int:
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container == null: return 0
	var count:int = 0
	for node:Node in container.get_children():
		if node.name.begins_with("重锤落地冲击_"): count += 1
	return count

func own_mc_hits(spear:Node2D) -> Array[Node]:
	var players:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_damage_source",-1) == spear.get_instance_id(): players.append(node)
	return players

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(80.0).timeout.connect(func(): finish(2))
	check(world.return_all_character_names().has("鞘翅重锤长矛") and world._get_character_scene_any("鞘翅重锤长矛") != null,"combo appears in actual Minecraft roster")
	var spear:Node2D = actor("鞘翅重锤长矛",center+Vector2(0,-210))
	spear.Can_Skill = false
	check(spear.Max_health == 200 and spear.get_preview_texture() == spear.COMBO_TEXTURE and spear.image.texture == spear.COMBO_TEXTURE,"user artwork drives battle sprite and preview")
	check(spear.COMBO_TEXTURE.get_size() == Vector2(128,128) and spear.COMBO_TEXTURE.get_image().get_pixel(0,0).a == 0.0,"provided artwork is an imported transparent 128px game texture")
	check(spear.COMBO_TIP_PIXEL == Vector2(121,5) and spear.COMBO_TEXTURE.get_image().get_pixel(121,5).a>0.9,"real striking point is on the opaque mace head, not the handle")
	check(spear.is_in_group("MinecraftElytraMaceSpear") and spear.is_in_group("MinecraftElytraSpear") and spear.is_in_group("MinecraftMace"),"both spear movement and mace chain identities are present")
	check(spear.collision_layer == 0 and spear.collision_mask == 0 and spear.has_node("FireworkAudio"),"spear glide, rocket and pass-through contract inherited")
	check(not spear._airborne and spear.get_next_state(spear.State.Stand) == spear.State.Move,"mace jump only starts after a genuine contact")
	var primary:Node2D = dummy(center+Vector2(0,-120))
	var secondary:Node2D = dummy(primary.global_position+Vector2(18,0))
	var outside:Node2D = dummy(primary.global_position+Vector2(220,0))
	var ally:Node2D = dummy(primary.global_position+Vector2(-18,0),"Team0")
	await physics_frame
	var regions:Array = spear.get_debug_attack_regions()
	check(regions.size() == 2 and regions[0].kind == "elytra_spear_tip" and regions[1].kind == "elytra_spear_mace_on_tip_hit","gliding shows actual swept tip and conditional mace radius")
	check(regions.size() == 2 and regions[1].position == spear.spear_tip_world_position() and regions[1].radius == spear.base_landing_radius,"opening blast tracks the moving spear tip, not the sprite box")
	check(spear.get_debug_detection_regions().is_empty(),"damage circles never masquerade as blue detection")
	spear._glide_velocity = Vector2.RIGHT*120.0
	spear.velocity = spear._glide_velocity
	spear._face_flight_direction()
	var forward:Vector2 = spear.spear_tip_world_position()-spear.global_position
	var shaft:Vector2 = Vector2(5,121)-spear.image.texture.get_size()*0.5+spear.image.offset
	check(forward.dot(Vector2.RIGHT)>12.0 and spear.image.to_global(shaft).x<spear.global_position.x-12.0,"rightward glide keeps mace head ahead and handle behind")
	spear.set_character_visual_flip_h(true) # Base movement tries to mirror right-facing fighters.
	check(not spear.is_character_visual_flipped_h() and float(spear.image.get_instance_shader_parameter("sprite_flip_h"))==0.0,"shader does not secretly mirror the art away from its collision head")
	spear._glide_velocity = Vector2.LEFT*120.0
	spear.velocity = spear._glide_velocity
	spear._face_flight_direction()
	check((spear.spear_tip_world_position()-spear.global_position).dot(Vector2.LEFT)>12.0 and spear.image.to_global(shaft).x>spear.global_position.x+12.0,"leftward glide also keeps the mace head ahead")
	spear._glide_velocity = Vector2.RIGHT*120.0
	spear.velocity = spear._glide_velocity
	spear._face_flight_direction()
	var primary_before:int = primary.health
	var secondary_before:int = secondary.health
	var outside_before:int = outside.health
	var ally_before:int = ally.health
	var audio_before:int = own_mc_hits(spear).size()
	var fx_before:int = impact_count()
	var contact:Vector2 = primary.global_position
	check(spear._apply_spear_contact(primary,contact,Vector2.RIGHT,120.0,false),"real tip contact accepts direct spear hit")
	check(absf(float(primary_before-primary.health)-spear.flight_damage_at_speed(120.0,false))<=1.0,"direct victim receives spear damage only once")
	check(absf(float(secondary_before-secondary.health)-spear.attack_damage(spear.base_landing_damage_multiplier))<=1.0,"other overlapping enemy receives first mace shockwave")
	check(outside.health == outside_before and ally.health == ally_before,"mace ring excludes outsiders and friendlies")
	check(impact_count() == fx_before+1 and own_mc_hits(spear).size() == audio_before+2,"one impact and one native MC sound per actually damaged target")
	check(spear._airborne and spear.Attacking and spear._chain_level == 1 and spear._glide_velocity.y<0.0 and spear._flight_mode == spear.FlightMode.REBOUND,"spear hit immediately launches a physical mace rebound")
	fx_before = impact_count()
	primary_before = primary.health
	primary.Damage_reduction = 1.0
	check(not spear._apply_spear_contact(primary,contact,Vector2.RIGHT,120.0,false) and impact_count() == fx_before and primary.health == primary_before,"rejected repeat cannot create another impact or jump")
	primary.Damage_reduction = 0.0
	var ascent:Vector2 = spear.global_position
	spear._update_flight(0.08)
	check(spear.global_position.y < ascent.y-2.0 and spear._airborne and spear._flight_elapsed>0.0,"rebound moves the real body upward, not just a drawn sprite")
	primary.global_position += Vector2(600,0)
	secondary.global_position += Vector2(600,0)
	ally.global_position += Vector2(600,0)
	var landing_one:Node2D = dummy(spear.global_position+Vector2(0,16))
	var landing_before:int = landing_one.health
	fx_before = impact_count()
	audio_before = own_mc_hits(spear).size()
	spear._glide_velocity = Vector2(0,220)
	spear.velocity = spear._glide_velocity
	spear._flight_elapsed = 0.7
	spear._update_flight(0.016)
	check(landing_one.health < landing_before and impact_count() == fx_before+1 and own_mc_hits(spear).size() >= audio_before+1,"descending real-body circle lands and produces MC hit feedback")
	check(spear._airborne and spear._chain_level == 2 and is_equal_approx(spear._chain_damage_multiplier,spear.base_landing_damage_multiplier*spear.landing_damage_jump_multiplier) and spear._glide_velocity.y<0.0,"successful landing automatically chains to higher/faster second jump")
	regions = spear.get_debug_attack_regions()
	check(regions.size()==1 and regions[0].kind=="elytra_spear_mace_landing" and regions[0].radius==spear.base_landing_radius+spear.landing_radius_gain and is_equal_approx(regions[0].damage,spear.attack_damage(spear._chain_damage_multiplier)),"airborne threat is the exact level-two landing circle, not a spear-tip ghost")
	landing_one.global_position += Vector2(500,0)
	var landing_two:Node2D = dummy(spear.global_position+Vector2(0,16))
	landing_before = landing_two.health
	var second_damage:float = spear.attack_damage(spear._chain_damage_multiplier)
	spear._glide_velocity = Vector2(0,230)
	spear.velocity = spear._glide_velocity
	spear._flight_elapsed = 0.7
	spear._update_flight(0.016)
	check(absf(float(landing_before-landing_two.health)-second_damage)<=1.0 and spear._airborne and spear._chain_level==3,"next actual landing deals stacked damage and begins level three")
	landing_two.global_position += Vector2(500,0)
	var cap_victim:Node2D = dummy(spear.global_position)
	spear._chain_level = spear.max_chain_level
	spear._chain_damage_multiplier = spear.base_landing_damage_multiplier*4.0
	var previous_multiplier:float = spear._chain_damage_multiplier
	spear._finish_landing()
	check(spear._airborne and spear._chain_level == spear.max_chain_level and is_equal_approx(spear._chain_damage_multiplier,previous_multiplier*spear.landing_damage_jump_multiplier),"height/radius level caps but actual combo damage keeps multiplying")
	cap_victim.global_position += Vector2(500,0)
	spear._end_missed_rebound()
	check(not spear._airborne and not spear.Attacking and spear._chain_level==1 and spear._chain_damage_multiplier==0.0,"missed rebound ends the chain and resets all stacks")
	var exact:Node2D = dummy(center+Vector2(-260,150))
	exact.health = 50
	spear._glide_velocity = Vector2.RIGHT*600.0
	audio_before = own_mc_hits(spear).size()
	check(spear._apply_spear_contact(exact,exact.global_position,Vector2.RIGHT,600.0,true),"high-speed spear penetration begins a mace leap")
	var audio:Array[Node] = own_mc_hits(spear)
	check(exact.health == 0 and audio.size() == audio_before+1 and audio.back().get_meta("mc_actual_damage",0.0)==50.0 and audio.back().get_meta("mc_sound_event","")=="entity.player.hurt","50 effective HP uses normal native hit, never critical")
	spear._end_missed_rebound()
	var critical:Node2D = dummy(center+Vector2(-260,240))
	critical.health = 51
	spear._glide_velocity = Vector2.RIGHT*600.0
	audio_before = audio.size()
	check(spear._apply_spear_contact(critical,critical.global_position,Vector2.RIGHT,600.0,true),"second high-speed contact accepted")
	audio = own_mc_hits(spear)
	check(critical.health == 0 and audio.size() == audio_before+1 and audio.back().get_meta("mc_actual_damage",0.0)==51.0 and audio.back().get_meta("mc_sound_event","")=="entity.player.attack.crit","51 effective HP triggers exactly one critical sound")
	check(audio.back().volume_db >= HIT_GAIN.damage_gain(51.0)-0.01 and audio.back().volume_db>0.0,"native hits grow louder with settled health damage")
	spear._end_missed_rebound()
	spear.global_position = center+Vector2(350,240)
	spear._glide_velocity = Vector2.RIGHT*120.0
	spear.velocity = spear._glide_velocity
	spear._face_flight_direction()
	spear._spear_contacts.clear()
	var tip:Vector2 = spear.spear_tip_world_position()
	var swept:Node2D = dummy(tip+Vector2(7,0))
	var swept_before:int = swept.health
	fx_before = impact_count()
	spear._sweep_spear_contacts(spear.global_position,spear.global_position+Vector2(10,0),tip,tip+Vector2(10,0))
	check(swept.health<swept_before and spear._airborne and impact_count()==fx_before+1,"automatic swept tip, not a manual hit call, triggers shockwave and rebound")
	var analyzer:Node = world.get_node_or_null("CombatThreatAnalyzer")
	check(analyzer != null,"World exposes live threat display")
	if analyzer != null:
		game.Game_Settings.Training_Debug_Mode = true
		analyzer._physics_process(0.2)
		var matched:bool = false
		for threat:Dictionary in analyzer._debug_threats:
			if threat.source==spear and threat.kind=="elytra_spear_mace_landing" and threat.debug_role=="damage" and threat.radius==spear.base_landing_radius: matched = true
		check(analyzer.visible and matched,"setting shows current real rebound landing radius")
		spear.dizziness = true
		analyzer._refresh_debug_world()
		matched = false
		for threat:Dictionary in analyzer._debug_threats:
			if threat.source==spear and threat.kind=="elytra_spear_mace_landing": matched = true
		check(not matched,"stun immediately removes unavailable mace damage threat")
		spear.dizziness = false
		game.Game_Settings.Training_Debug_Mode = false
		analyzer._physics_process(0.1)
		check(not analyzer.visible and analyzer._debug_threats.is_empty(),"turning off threat display immediately clears all circles")
	print("MC COMBO SPEAR CHAIN CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
