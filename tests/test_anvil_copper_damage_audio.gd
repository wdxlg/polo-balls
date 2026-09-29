extends "res://tests/test_anvil.gd"
func damage_cues(unit:Node) -> Array[Node]:
	var result:Array[Node] = []
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_damage_source",0)==unit.get_instance_id(): result.append(player)
	return result
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(75.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"damage-audio preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var sources:Array[Node2D] = [copper(center+Vector2(-100,0)),anvil(center+Vector2(100,0))]
	var gain_script:Script = load("res://scripts/effects/我的世界/hit_audio_gain.gd")
	check(gain_script.damage_event(50.0)=="entity.player.hurt" and gain_script.damage_event(51.0)=="entity.player.attack.crit","shared strict 50/51 critical threshold")
	check(gain_script.damage_event(0.0)=="" and gain_script.damage_gain(0.0)==0.0,"zero damage has no cue and baseline gain is exactly 0dB")
	check(gain_script.damage_gain(1000000.0)<=6.0,"damage loudness has a safe upper bound")
	for source:Node2D in sources:
		var target:Node2D = dummy(center+Vector2(0,100))
		var impact_point:Vector2 = target.global_position
		if source.has_method("_underside_rect"):
			var hurt_shape:CollisionShape2D = target.self_hurtbox.get_node("CollisionShape2D")
			var hurt_rect:Rect2 = hurt_shape.global_transform*hurt_shape.shape.get_rect()
			source.global_position = Vector2(target.global_position.x,hurt_rect.position.y-source.body_half_size().y)
			impact_point = source.global_position
		await physics_frame
		await process_frame
		clear_cues()
		var previous:float = -1.0
		for amount:float in [1.0,25.0,50.0,51.0,100.0,200.0]:
			var hp:float = target.health
			var before:int = damage_cues(source).size()
			check(source._damage_with_feedback(target,amount,impact_point) and is_equal_approx(hp-target.health,amount),str(source.name)+" damage remains unchanged at "+str(amount))
			var cues:Array[Node] = damage_cues(source)
			check(cues.size()==before+1,str(source.name)+" exactly one cue per real hit at "+str(amount))
			if cues.is_empty(): continue
			var cue:AudioStreamPlayer2D = cues[-1]
			var expected:String = "entity.player.attack.crit" if amount>50.0 else "entity.player.hurt"
			var native:bool = false
			for record:Dictionary in source.AUDIO.EVENTS[expected]:
				if record.stream==cue.stream: native = true
			check(cue.playing and native and cue.get_meta("mc_sound_event")==expected,str(source.name)+" plays correct original Minecraft clip at "+str(amount))
			check(cue.volume_db>=0.0 and cue.volume_db>previous and is_equal_approx(cue.volume_db,gain_script.damage_gain(amount)),str(source.name)+" raises volume from original source level without negative attenuation")
			previous = cue.volume_db
		target.Damage_reduction = 0.9
		var hp:float = target.health
		source._damage_with_feedback(target,100.0,impact_point)
		var actual:float = hp-target.health
		check(damage_cues(source)[-1].get_meta("mc_sound_event")=="entity.player.hurt" and is_equal_approx(damage_cues(source)[-1].volume_db,gain_script.damage_gain(actual)),str(source.name)+" uses resolved post-armor damage, not requested damage")
		target.Damage_reduction = 1.0
		var count:int = damage_cues(source).size()
		check(not source._damage_with_feedback(target,1000.0,impact_point) and damage_cues(source).size()==count,str(source.name)+" immunity produces no fake successful-hit sound")
		target.Damage_reduction = 0.0
		target.Team = source.Team
		check(not source._damage_with_feedback(target,100.0,impact_point) and damage_cues(source).size()==count,str(source.name)+" friendly target produces no damage cue")
		target.queue_free()
		clear_cues()
	print("ANVIL_COPPER_DAMAGE_AUDIO checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
