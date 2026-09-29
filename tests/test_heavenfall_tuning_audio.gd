extends "res://tests/test_mc_new6_load.gd"
# Exercise real World nodes and real AudioStreamPlayer2D event/stream/timing.
var bow: Node2D
var victim: Node2D
var sounds: Script

func event_nodes(event: String) -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in get_nodes_in_group("MCNativeSFX") + get_nodes_in_group("HeavenfallWaveSFX"):
		if node.get_meta("mc_sound_event", "") == event and not node.is_queued_for_deletion():
			result.append(node)
	return result

func clear_sounds() -> void:
	for node: Node in get_nodes_in_group("MCNativeSFX") + get_nodes_in_group("HeavenfallWaveSFX"):
		node.stop()
		node.free()

func rain(point: Vector2, index: int = 0, total: int = 1, authority: int = 1) -> Node2D:
	var arrow: Node2D = load("res://scenes/shooter/我的世界/天陨箭.tscn").instantiate()
	world.add_child(arrow, true)
	arrow.set_physics_process(false)
	arrow.set_multiplayer_authority(authority)
	arrow.configure(bow, bow.Team, point, bow.rain_delay, bow.attack_damage(bow.rain_damage_mult), bow.rain_aoe, index, total)
	return arrow

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(60.0, true, false, true).timeout.connect(func(): finish(2))
	sounds = load("res://scripts/characters/我的世界/new5/audio.gd")
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	for other: Node in get_nodes_in_group("Ball"):
		other.process_mode = Node.PROCESS_MODE_DISABLED
		other.remove_from_group("Ball")
		(other as Node2D).global_position = center + Vector2(4000, 4000)
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-50, 0))
	bow.state_machine.set_physics_process(false)
	bow.set_physics_process(false)
	bow.Can_Attack = true
	victim = _mk_enemy(center + Vector2(50, 0))
	await physics_frame
	await process_frame
	clear_sounds()
	check(is_equal_approx(bow.attack_damage(bow.bolt_damage_mult), 20.0), "default main arrow damage is 20")
	check(is_equal_approx(bow.attack_damage(bow.rain_damage_mult), 7.0), "default rain arrow damage is 7")
	check(bow.Damage == 10, "base attack stat remains unchanged")
	check(is_equal_approx(bow.cooldown, 1.65) and is_equal_approx(bow.draw_time, 0.5), "only shot cooldown is multiplied by 1.5; draw stays 0.5s")
	check(is_equal_approx(bow.rift_blast_tick_damage, 2.0), "rift impact damage is fixed at 2 per tick")
	check(is_equal_approx(bow.rift_dodge_cooldown, 0.9) and bow.rain_count == 7, "dodge cooldown and rain count stay unchanged")
	bow.step_mob(0.49)
	check(_bolts().is_empty(), "draw cannot release before 0.5s")
	bow.step_mob(0.02)
	check(_bolts().size() == 1, "completed draw emits one arrow")
	var bolt: Node2D = _bolts()[0]
	bolt.set_physics_process(false)
	check(is_equal_approx(bolt._damage, 20.0) and is_equal_approx(bolt._rain_damage, 7.0), "actual projectile receives both tuned damage values")
	check(is_equal_approx(bow._cool, 1.65), "release starts the new cooldown")
	var shot_id: int = bow._shot_seq
	for i in range(164): bow.step_mob(0.01)
	check(bow._shot_seq == shot_id and is_zero_approx(bow.drawing), "old 1.1s cooldown cannot trigger an early draw")
	for i in range(47): bow.step_mob(0.01)
	check(bow._shot_seq == shot_id, "cooldown plus draw still prevents a second shot before 2.11s")
	for i in range(6): bow.step_mob(0.01)
	check(bow._shot_seq == shot_id + 1, "next shot occurs around 2.15s")
	for node: Node in _bolts(): node.set_physics_process(false)
	var hp: float = victim.health
	bolt.global_position = victim.global_position
	bolt._hit_character(bow, victim)
	check(is_equal_approx(hp - victim.health, 20.0), "main arrow removes 20 actual health on an unarmored enemy")
	clear_sounds()
	bolt._expire()
	check(_falls().size() == 7 and _rifts().size() == 1, "actual arrow termination creates seven rain arrows and one main rift")
	check(event_nodes("entity.heavenfall.rift").size() == 1, "main rift opens with exactly one sound")
	var large_sound: AudioStreamPlayer2D = event_nodes("entity.heavenfall.rift")[0]
	check(large_sound.global_position.is_equal_approx(bolt.global_position), "large rift sound comes from impact, not bow position")
	check(large_sound.stream.resource_path.contains("respawn_anchor_deplete"), "large rift uses original respawn anchor audio, not arrow hit")
	check(event_nodes("entity.heavenfall.rain_shoot").is_empty(), "creating the whole hidden volley does not play all launch sounds early")
	var falls: Array[Node] = _falls()
	for node: Node in falls: node.set_physics_process(false)
	var start_counts: Array[int] = []
	for frame_index in range(105):
		for node: Node in falls:
			if not node.is_queued_for_deletion(): node._physics_process(0.01)
		start_counts.append(event_nodes("entity.heavenfall.rain_shoot").size())
	check(start_counts[0] == 1, "only the immediate first rain arrow plays at the start")
	check(start_counts[10] == 1 and start_counts[20] == 2, "second launch sound follows stagger timing rather than creation time")
	check(event_nodes("entity.heavenfall.rain_shoot").size() == 7, "seven individual arrow appearances produce seven launch sounds")
	check(event_nodes("entity.heavenfall.impact").is_empty() and event_nodes("entity.arrow.hit").is_empty(), "rain landings never play old arrow impact events")
	for node: Node in falls:
		if not node.is_queued_for_deletion(): node._physics_process(0.5)
	check(event_nodes("entity.heavenfall.rain_rift").size() == 7, "seven ground contacts produce seven small crack sounds")
	for node: Node in falls:
		if is_instance_valid(node) and not node.is_queued_for_deletion(): node._land()
	check(event_nodes("entity.heavenfall.rain_rift").size() == 7, "repeated landing calls cannot duplicate crack audio")
	clear_sounds()
	# A clean centered rain hit tests exact real health loss and landing idempotence.
	var arrow: Node2D = rain(victim.global_position)
	hp = victim.health
	arrow._land()
	check(is_equal_approx(hp - victim.health, 7.0), "one centered rain arrow removes 7 actual health")
	check(victim.Buff_Dic.get(bow.get_instance_id(), {}).has("天陨减速"), "rain still applies its existing slow")
	check(event_nodes("entity.heavenfall.rain_rift").size() == 1, "one rain contact plays one small rift sound")
	check(event_nodes("entity.heavenfall.rain_rift")[0].stream.resource_path.contains("amethyst_break"), "small rift uses original amethyst fracture audio")
	arrow._land()
	check(is_equal_approx(hp - victim.health, 7.0) and event_nodes("entity.heavenfall.rain_rift").size() == 1, "duplicate landing cannot damage or sound twice")
	arrow.queue_free()
	clear_sounds()
	var delayed: Node2D = rain(center, 6, 7)
	delayed._physics_process(0.1)
	check(not delayed.visible and event_nodes("entity.heavenfall.rain_shoot").is_empty(), "hidden delayed arrow is silent")
	var hold: float = delayed._hold
	game.now_stop_state = true
	delayed._physics_process(1.0)
	check(delayed._hold == hold and event_nodes("entity.heavenfall.rain_shoot").is_empty(), "battle pause freezes the wait and emits no launch audio")
	game.now_stop_state = false
	delayed._physics_process(hold + 0.001)
	check(event_nodes("entity.heavenfall.rain_shoot").size() == 1, "resuming triggers one launch when the arrow actually starts")
	delayed.queue_free()
	clear_sounds()
	var replica: Node2D = rain(victim.global_position, 0, 1, 2)
	replica._physics_process(0.001)
	check(event_nodes("entity.heavenfall.rain_shoot").size() == 1, "non-authority local visual replay also has launch sound")
	hp = victim.health
	replica._land()
	check(victim.health == hp, "non-authority rain cannot duplicate damage")
	check(event_nodes("entity.heavenfall.rain_rift").size() == 1, "non-authority local landing replays one crack sound")
	replica.queue_free()
	clear_sounds()
	hp = victim.health
	bow._rift_blast_damage(victim.global_position)
	check(is_equal_approx(hp - victim.health, 2.0), "real arrival damage removes exactly 2 health per tick")
	bow.Damage = 20
	check(is_equal_approx(bow.attack_damage(bow.bolt_damage_mult), 40.0) and is_equal_approx(bow.attack_damage(bow.rain_damage_mult), 14.0), "arrow multipliers still scale with the attack stat")
	hp = victim.health
	bow._rift_blast_damage(victim.global_position)
	check(is_equal_approx(hp - victim.health, 2.0), "rift counterattack stays fixed at 2 when attack stat increases")
	bow.Damage = 10
	for event: String in ["entity.heavenfall.rift", "entity.heavenfall.rain_rift", "entity.heavenfall.rain_shoot"]:
		for record: Dictionary in sounds.EVENTS[event]:
			var stream: AudioStream = record["stream"]
			check(stream != null and stream.get_length() > 0.05, event + " asset decodes and has audible duration")
	check(sounds.EVENTS["entity.heavenfall.rift"].size() == 2 and sounds.EVENTS["entity.heavenfall.rain_rift"].size() == 4, "large and small rifts have their own variant sets")
	check(sounds.EVENTS["entity.arrow.shoot"][0]["pitch"] == 1 and sounds.EVENTS["entity.arrow.hit"].size() == 3, "ordinary bow sound definitions remain unchanged")
	test_audio_style(center)
	print("HEAVENFALL TUNING AUDIO RESULT: %d/%d passed" % [checks - failures, checks])
	finish(0 if failures == 0 else 1)


func test_audio_style(center: Vector2) -> void:
	# Verify actual stream content/duration, not only new event names.
	var roles: Dictionary = {
		"shoot": ["heaven_shot", 0.24],
		"rain_shoot": ["heaven_rain_shot", 0.16],
		"teleport": ["heaven_transit", 0.24],
		"wave": ["heaven_wave", 0.46],
	}
	for role: String in roles:
		var event: String = "entity.heavenfall." + role
		check(sounds.EVENTS.has(event) and sounds.EVENTS[event].size() == 2, role + " has two dedicated layered variants")
		for record: Dictionary in sounds.EVENTS[event]:
			var stream: AudioStream = record["stream"]
			check(stream.resource_path.get_file().begins_with(roles[role][0]) and absf(stream.get_length() - roles[role][1]) < 0.005 and is_equal_approx(record["pitch"], 1.0), role + " uses the baked short clip at its designed duration")
	for role: String in ["shoot", "rain_shoot", "wave"]:
		for record: Dictionary in sounds.EVENTS["entity.heavenfall." + role]:
			check(record["stream"].resource_path.contains("_punch"), role + " uses the new transient/impact master, not the soft original")
	check(sounds.EVENTS["entity.heavenfall.teleport"][0]["stream"].resource_path.ends_with("heaven_transit1.ogg"), "accepted transit sound is unchanged")
	check(sounds.EVENTS["entity.heavenfall.rift"][0]["stream"].resource_path.contains("respawn_anchor_deplete") and sounds.EVENTS["entity.heavenfall.rain_rift"][0]["stream"].resource_path.contains("amethyst_break"), "accepted large and small crack sounds are unchanged")
	check(sounds.EVENTS["entity.generic.explode"][0]["stream"].resource_path.contains("/new5/"), "generic explosion remains unchanged for other characters")
	clear_sounds()
	sounds._last.erase("entity.heavenfall.shoot")
	bow._fire()
	var shot_nodes: Array[Node] = event_nodes("entity.heavenfall.shoot")
	check(shot_nodes.size() == 1 and shot_nodes[0].stream.resource_path.get_file().begins_with("heaven_shot"), "main release plays the new sharp short shot")
	for bolt: Node in _bolts(): bolt.set_physics_process(false)
	clear_sounds()
	var launch: Node2D = rain(center)
	launch._physics_process(0.01)
	var rain_nodes: Array[Node] = event_nodes("entity.heavenfall.rain_shoot")
	check(rain_nodes.size() == 1 and rain_nodes[0].stream.resource_path.get_file().begins_with("heaven_rain_shot"), "rain appearance plays its lighter shorter shot")
	launch.queue_free()
	# Remove old fixture charges, then exercise a REAL incoming-hit dodge.
	for rift_node: Node in _rifts(): rift_node.close_quietly()
	bow._rifts.clear()
	bow._rift_cool = 0.0
	bow._rift_grace = 0.0
	var origin: Vector2 = bow.global_position
	bow.spawn_heaven_rift(center + Vector2(0, -30), Vector2.UP)
	_rifts().back()._age = _rifts().back().opening_time
	var destination: Vector2 = _rifts().back().landing
	clear_sounds()
	var hp: float = bow.health
	check(not bow.receive_positional_damage(10.0, origin, false, victim) and bow.health == hp and bow.is_rift_transiting(), "real incoming hit still triggers a damage-free dodge")
	var departures: Array[Node] = event_nodes("entity.heavenfall.teleport")
	check(departures.size() == 1 and departures[0].stream.resource_path.contains("heaven_transit"), "dodge uses spatial transit sound rather than a pitched arrow")
	check(departures[0].global_position.is_equal_approx(origin), "transit sound is fixed at departure position")
	check(event_nodes("entity.heavenfall.wave").is_empty(), "shockwave is silent before arrival")
	game.now_stop_state = true
	bow._advance_rift_transit(1.0)
	check(event_nodes("entity.heavenfall.wave").is_empty() and bow.global_position == origin, "pause cannot advance or sound the arrival")
	game.now_stop_state = false
	bow._advance_rift_transit(bow.TRANSIT.EXIT_AT + 0.001)
	var waves: Array[Node] = event_nodes("entity.heavenfall.wave")
	check(waves.size() == 1 and waves[0].stream.resource_path.contains("heaven_wave"), "arrival plays one dedicated dimensional energy wave")
	check(waves[0].global_position.is_equal_approx(bow.global_position) and bow.global_position.is_equal_approx(destination), "wave sound is fixed at actual safe landing position")
	check(event_nodes("entity.generic.explode").is_empty(), "arrival no longer plays the generic explosion")
	bow._emit_rift_arrival()
	var ring: Node = bow._arrival_ring.get_ref()
	ring.set_process(false)
	ring._process(0.4)
	check(ring.ticks_done() == 5 and event_nodes("entity.heavenfall.wave").size() == 1, "five damage ticks and repeated arrival call do not replay the wave sound")
	bow._advance_rift_transit(1.0)
	clear_sounds()
	# Local peer replay must sound without another network sound RPC or damage.
	var client: Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", origin)
	client.state_machine.set_physics_process(false)
	client.set_physics_process(false)
	client.set_process(false)
	client.set_multiplayer_authority(2)
	hp = victim.health
	client._apply_rift_dodge(origin, victim.global_position, 901, victim.global_position)
	check(event_nodes("entity.heavenfall.teleport").size() == 1, "client visual replay plays one departure cue")
	client._advance_rift_transit(1.0)
	check(event_nodes("entity.heavenfall.wave").size() == 1 and victim.health == hp, "client arrival has sound but never duplicates authoritative damage")
	client._apply_rift_dodge(origin, destination, 901, destination)
	check(event_nodes("entity.heavenfall.teleport").size() == 1 and not client.is_rift_transiting(), "duplicate reliable action cannot play another departure")
	client.queue_free()
	clear_sounds()
	_mature_rift_fixture(bow, destination, 902)
	clear_sounds()
	bow._apply_rift_dodge(origin, destination, 902, destination)
	bow._cancel_rift_transit()
	bow._advance_rift_transit(1.0)
	check(event_nodes("entity.heavenfall.wave").is_empty(), "interrupted transit has no false arrival sound")
	clear_sounds()
	_mature_rift_fixture(bow, destination, 903)
	clear_sounds()
	# Critical dodge cues must survive a full ordinary sound pool, without growing it.
	for i in range(24): sounds.play(bow, "entity.arrow.shoot", origin, -8.0, false, false, false, true)
	check(get_nodes_in_group("MCNativeSFX").size() == 24, "fixture: ordinary sound pool is full")
	bow._apply_rift_dodge(origin, destination, 903, destination)
	bow._advance_rift_transit(bow.TRANSIT.EXIT_AT + 0.001)
	check(event_nodes("entity.heavenfall.teleport").size() == 1 and event_nodes("entity.heavenfall.wave").size() == 1, "critical transit and wave cues replace ordinary voices instead of being lost")
	check(get_nodes_in_group("MCNativeSFX").size() == 24, "priority cues retain the shared 24-voice bound")
	var protected_wave: Node = event_nodes("entity.heavenfall.wave")[0]
	check(is_equal_approx(protected_wave.volume_db, 0.0) and not protected_wave.is_in_group("MCNativeSFX"), "wave uses default gain and an independent protected pool")
	for i in range(30): sounds.play(bow, "entity.arrow.hit", origin, 0.0, false, true, false, true)
	check(is_instance_valid(protected_wave) and not protected_wave.is_queued_for_deletion() and protected_wave.playing, "later priority hit bursts cannot steal the wave")
	for i in range(6):
		var context := Node.new()
		world.add_child(context)
		bow.WAVE_AUDIO.play(context, destination)
		check(bow.WAVE_AUDIO.play(context, destination) == null, "same arrival context cannot replay the wave")
		context.queue_free()
	check(get_nodes_in_group("HeavenfallWaveSFX").size() == 4, "dedicated arrival pool remains bounded to four voices")
	bow._cancel_rift_transit()
	clear_sounds()
