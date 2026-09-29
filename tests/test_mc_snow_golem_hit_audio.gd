extends "res://tests/test_mc_snow_golem.gd"
var AUDIO:Script
var serial:int = 0
func active_snow_sounds() -> Array:
	var result:Array = []
	for node:Node in get_nodes_in_group("MCSnowSound"):
		if not node.is_queued_for_deletion(): result.append(node)
	return result
func latest_layers(before:Array) -> Dictionary:
	var result:Dictionary = {"victim":[],"snow":[]}
	for node:Node in active_snow_sounds():
		if node.get_instance_id() in before: continue
		var layer:String = str(node.get_meta("mc_snow_impact_layer",""))
		if result.has(layer): result[layer].append(node)
	return result
func ids() -> Array:
	var result:Array = []
	for node:Node in active_snow_sounds(): result.append(node.get_instance_id())
	return result
func fire_once(source:Node2D,target:Node2D,damage:float) -> Dictionary:
	var before:Array = ids()
	var hp:int = target.health
	serial += 1
	var name_value:String = "SnowAudio_"+str(serial)
	source._spawn_snowball(name_value,source.global_position,source.global_position.direction_to(target.global_position),damage)
	var reference:WeakRef = weakref(world.get_node(name_value))
	var found:Dictionary = {"victim":[],"snow":[]}
	for frame:int in range(90):
		await physics_frame
		await process_frame
		found = latest_layers(before)
		if not found.snow.is_empty() or not found.victim.is_empty(): break
	found["actual"] = hp-target.health
	found["projectile"] = reference
	return found
func sound_matches(player:AudioStreamPlayer2D,event:String) -> bool:
	for record:Dictionary in AUDIO.MC_HITS.EVENTS[event]:
		if player.stream == record.stream: return true
	return false
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(50.0).timeout.connect(func(): finish(2))
	AUDIO = load("res://scripts/characters/我的世界/snow_golem/audio.gd")
	var source:Node2D = spawn(GOLEM_PATH,center)
	var target:Node2D = dummy(center+Vector2(96,0))
	target.negative_effect_ratio = 0.0
	var field:Node2D = source._field
	field.set_physics_process(false)
	check(AUDIO.impact_gain(0.0) == 0.0,"damage gain begins at unchanged source level, not negative dB")
	var last_gain:float = -1.0
	for damage:float in [1.0,3.0,6.0,25.0,50.0,51.0,100.0,200.0,1000.0]:
		var gain:float = AUDIO.impact_gain(damage)
		check(gain >= 0.0 and gain > last_gain and gain <= 6.0,"hit gain increases without attenuating low damage: "+str(damage))
		last_gain = gain
	check(AUDIO.impact_event(50.0) == "entity.player.hurt" and AUDIO.impact_event(51.0) == "entity.player.attack.crit","strictly over 50 is critical; exactly 50 stays the normal MC hurt sound")

	for damage:float in [1.0,6.0,50.0,51.0,100.0,200.0]:
		var found:Dictionary = await fire_once(source,target,damage)
		check(found.actual == int(damage),"real flying snowball deals the measured damage: "+str(damage))
		check(found.victim.size() == 1 and found.snow.size() == 1,"one health hit produces one native victim cue plus one snow contact, without duplicate callbacks")
		if found.victim.size() == 1:
			var player:AudioStreamPlayer2D = found.victim[0]
			var event:String = AUDIO.impact_event(found.actual)
			check(str(player.get_meta("mc_sound_event")) == event and sound_matches(player,event) and player.stream.get_length() > 0.0,"actual player uses the original normal/critical stream: "+str(damage))
			check(is_equal_approx(player.volume_db,AUDIO.impact_gain(found.actual)) and player.volume_db >= 0.0,"final playback volume preserves positive damage gain: "+str(damage))
			print("SNOW_HIT_AUDIO damage=",found.actual," event=",event," db=",player.volume_db)
		if found.snow.size() == 1:
			check(is_equal_approx(found.snow[0].volume_db,0.0),"snowball's physical contact is played at normal 0 dB, not the old -9 dB")
		check(not is_instance_valid(found.projectile.get_ref()) or found.projectile.get_ref().is_queued_for_deletion(),"a successful impact removes the projectile immediately")

	# Use actual health loss after mitigation/shield, not the attack-card number.
	target.Damage_reduction = 0.75
	target.default_properties.Damage_reduction = 0.75
	var reduced:Dictionary = await fire_once(source,target,100.0)
	check(reduced.actual == 25 and reduced.victim.size() == 1 and reduced.victim[0].get_meta("mc_sound_event") == "entity.player.hurt","100 raw damage reduced to 25 does not falsely trigger a critical sound")
	target.Damage_reduction = 0.0
	target.default_properties.Damage_reduction = 0.0
	target.max_block = 100
	target.default_properties.max_block = 100
	target.block = 20
	var partial:Dictionary = await fire_once(source,target,80.0)
	check(partial.actual == 60 and partial.victim.size() == 1 and partial.victim[0].get_meta("mc_sound_event") == "entity.player.attack.crit","partial shield break reports the actual 60 HP hit, despite the nested blocked callback")
	check(partial.snow.size() == 1,"partial shield break does not double-play the material impact")
	target.block = 100
	var shielded:Dictionary = await fire_once(source,target,51.0)
	check(shielded.actual == 0 and shielded.victim.is_empty() and shielded.snow.size() == 1,"fully shielded hit has audible snow contact but no false hurt/critical health sound")
	target.block = 0
	target.max_block = 0
	target.default_properties.max_block = 0
	var zero:Dictionary = await fire_once(source,target,0.0)
	check(zero.actual == 0 and zero.victim.is_empty() and zero.snow.size() == 1,"zero-damage contact does not invent a health-hit sound")

	# A second ordinary golem uses the same non-attenuated hit baseline.
	var mini:Node2D = spawn(GOLEM_PATH,center+Vector2(0,96))
	var mini_target:Node2D = dummy(center+Vector2(96,96))
	mini_target.negative_effect_ratio = 0.0
	var small:Dictionary = await fire_once(mini,mini_target,float(mini.Damage))
	check(small.actual == 9 and small.victim.size() == 1 and small.victim[0].volume_db >= 0.0,"mini's matching-damage snowball keeps the normal sound level")

	# Same-frame independent hits must not be swallowed by global sound debounce.
	var before:Array = ids()
	field.emit_impact(6.0,center,true)
	field.emit_impact(51.0,center+Vector2(24,0),true)
	var simultaneous:Dictionary = latest_layers(before)
	check(simultaneous.victim.size() == 2 and simultaneous.snow.size() == 2,"two independent hits in the same frame both keep their original feedback")
	var terrain_before:Array = ids()
	park_contact(field,target,FIELD.point_at(FIELD.cell_at(center+Vector2(144,0))))
	field.deposit(source,FIELD.cell_at(target.global_position),false)
	field.advance(0.01)
	var terrain:Dictionary = latest_layers(terrain_before)
	check(terrain.victim.size() == 1 and terrain.snow.is_empty() and terrain.victim[0].volume_db >= 0.0,"real full-snow damage also uses the non-attenuated MC health-hit cue")

	# Voices outlive the disposable projectile and obey pause/cleanup.
	var player:AudioStreamPlayer2D = AUDIO.play_impact(field,51.0,center,true)
	await physics_frame
	await process_frame
	check(is_instance_valid(player) and player.playing and player.is_in_group("BattleTransient"),"native impact stream actually starts and is battle-scoped")
	game.now_stop_state = true
	field._process(0.0)
	check(is_instance_valid(player) and player.stream_paused,"existing normal/critical impact voices pause with gameplay")
	game.now_stop_state = false
	field._process(0.0)
	check(is_instance_valid(player) and not player.stream_paused,"impact voice resumes without being replaced by a quiet fallback")
	world.reset()
	await process_frame
	await process_frame
	check(get_nodes_in_group("MCSnowSound").is_empty() and get_nodes_in_group("MCSnowball").is_empty(),"battle reset leaves no impact players or projectiles behind")
	print("SNOW_HIT_AUDIO_RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
