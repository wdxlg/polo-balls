extends "res://scripts/training/test_mc_new5.gd"
## Actual World, production Wither + Beacon exit callback, and isolated PCM capture.
const SOUNDS = preload("res://scripts/characters/我的世界/wither/audio.gd")
var capture:AudioEffectCapture
var probe_bus:int = -1
var probe_name:StringName = &"WitherLifecycleProbe"
func settle_audio() -> void:
	await process_frame
	await physics_frame
	await process_frame
func sound_players(event:String) -> Array[AudioStreamPlayer2D]:
	var found:Array[AudioStreamPlayer2D] = []
	for node:Node in world.get_children():
		if node is AudioStreamPlayer2D and node.stream==SOUNDS.STREAMS[event]: found.append(node)
	return found
func route_probe(node:Node) -> void:
	if node is AudioStreamPlayer2D and node.stream==SOUNDS.STREAMS.beacon_deactivate:
		node.bus = probe_name
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var wither:Node2D = spawn("凋灵",Vector2(0,-100))
	wither.summoned = true
	wither.health = 250
	wither.on_actual_health_damage_received(1,251)
	var beacon:Node2D = wither.beacon
	beacon.state_machine.set_physics_process(false)
	await settle_audio()
	check(is_instance_valid(beacon) and beacon.is_inside_tree(),"real half-health summon creates the production beacon")
	for node:Node in world.get_children():
		if node is AudioStreamPlayer2D: node.free()
	probe_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(probe_bus,probe_name)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(probe_bus,capture)
	node_added.connect(route_probe)
	beacon.firing_left = 1.0
	beacon._start_beacon_hum()
	await settle_audio()
	check(beacon._beacon_hum.playing,"real beacon is humming before removal")
	var point:Vector2 = beacon.global_position
	capture.clear_buffer()
	beacon.free() # Production _exit_tree -> _emit_sound -> shared helper; parent is blocked here.
	await settle_audio()
	var tails:Array[AudioStreamPlayer2D] = sound_players("beacon_deactivate")
	check(tails.size()==1,"production beacon tree-exit emits exactly one deactivation tail")
	if not tails.is_empty():
		check(tails[0].playing and tails[0].global_position==point and tails[0].volume_db==0.0,"tail plays at the original point with unchanged gain after source deletion")
		await create_timer(0.25).timeout
		var samples:PackedVector2Array = capture.get_buffer(capture.get_frames_available())
		var peak:float = 0.0
		for sample:Vector2 in samples: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		check(samples.size()>0 and peak>0.000001,"isolated real audio mix contains nonzero deactivation PCM, not just a playing flag")
		print("WITHER_AUDIO_PCM frames=",samples.size()," peak=",peak)
		var tail:AudioStreamPlayer2D = tails[0]
		await create_timer(tail.stream.get_length()+0.2).timeout
		check(not is_instance_valid(tail),"real deactivation tail finishes and cleans itself up")
	# Ordinary Wither requests and remote visual callback use the same safe public helper.
	wither._emit_sound("shoot",wither.global_position)
	wither._sync_event("charge",wither.global_position)
	await settle_audio()
	check(sound_players("shoot").size()==1 and sound_players("charge").size()==1,"Wither local emit and remote callback retain their distinct native sounds")
	for event:String in ["shoot","charge"]:
		for player:AudioStreamPlayer2D in sound_players(event): player.free()
	# Existing death feedback must survive the caller being removed before the deferred flush.
	wither._emit_sound("death",wither.global_position)
	wither.free()
	await settle_audio()
	check(sound_players("death").size()==1,"captured Wither death sound does not depend on a still-live source")
	node_added.disconnect(route_probe)
	AudioServer.remove_bus(probe_bus)
	print("WITHER_AUDIO_WORLD checks=",checks," failures=",failures)
	await clear_units()
	finish(0 if failures==0 else 1)
