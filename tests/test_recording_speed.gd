extends "res://tests/test_battle_recording.gd"
class Clock:
	extends Node
	var elapsed:float = 0.0
	var marker:ColorRect
	var camera:Camera2D
	var pulse_start:float = 0.0
	var pulse_active:bool = false
	var events:Array = []
	var next_pulse:float = 0.5
	func _physics_process(delta:float) -> void:
		elapsed += delta
		if marker == null: return
		marker.position = camera.get_screen_center_position() - marker.size * 0.5
		if not pulse_active: return
		var time:float = elapsed - pulse_start
		if time >= next_pulse:
			events.append(time)
			next_pulse += 0.5
		marker.color = Color.WHITE if fmod(time,0.5) < 0.1 and time >= 0.5 else Color(0.2,0.4,0.6)
	func restart_pulses() -> void:
		pulse_start = elapsed
		next_pulse = 0.5
		events.clear()
		pulse_active = true

func wall_wait(seconds:float) -> void:
	var deadline:int = Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline: await RenderingServer.frame_post_draw

func measure(clock:Clock, seconds:float, output_scale:float) -> Dictionary:
	var wall:int = Time.get_ticks_usec()
	var physics:float = clock.elapsed
	var video:float = recorder._game_time
	await wall_wait(seconds)
	return {"wall":float(Time.get_ticks_usec()-wall)/1e6,"physics":clock.elapsed-physics,"video":recorder._game_time-video,"scale":output_scale}

func run() -> void:
	create_timer(100,true,false,true).timeout.connect(func(): print("SPEED_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	DirAccess.remove_absolute("user://test_speed.cfg")
	recorder.preferences = recorder.PreferencesScript.new("user://test_speed.cfg")
	recorder.preferences.directory = "user://recordings/speed_test"
	world.control.team.hide()
	var clock := Clock.new()
	world.add_child(clock)
	var marker := ColorRect.new()
	marker.size = Vector2(36,36)
	marker.z_index = 900
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(marker)
	clock.marker = marker
	clock.camera = world.camera_2d
	var tone:AudioStreamPlayer = make_tone(440,&"GameplayRecord")
	await wall_wait(2)
	var t:int = Time.get_ticks_usec()
	var p:float = clock.elapsed
	await wall_wait(2)
	var baseline:float = (clock.elapsed-p)/(float(Time.get_ticks_usec()-t)/1e6)
	check(baseline > 0.92 and baseline < 1.08,"baseline physical motion advances at normal speed")
	var results:Array = []
	for kind:String in ["live_hardware","live_software"]:
		recorder._force_software = kind == "live_software"
		check(recorder.start_live(),kind + " starts")
		await wall_wait(1.2)
		if not recorder.is_recording():
			check(false,kind + " unexpectedly stopped: " + recorder.get_last_error())
			await wait_idle()
			quit(1)
			return
		clock.restart_pulses()
		var start_video:float = recorder._game_time
		var start_physics:float = clock.elapsed
		var scale:float = Engine.time_scale
		var stats:Dictionary = await measure(clock, 3.0, scale)
		stats.kind = kind
		stats.codec = recorder._video_codec
		check(stats.codec == ("libx264" if kind == "live_software" else "h264_nvenc"),kind + " exercises the intended encoder on this RTX test machine")
		stats.pulses = clock.events.duplicate()
		stats.pulse_video_start = start_video
		stats.physics_origin = start_physics
		var rate:float = stats.physics / stats.wall / scale
		var video_rate:float = stats.physics / stats.video
		check(rate > 0.90 and rate < 1.10,kind + " capture does not slow the intended physical simulation")
		check(absf(video_rate - scale) < 0.08,kind + " video seconds match independent physical progress")
		check(recorder.is_recording() and recorder.get_last_error().is_empty(),kind + " has no overload/error stop")
		var writer:RefCounted = recorder._writer
		var english_writer:RefCounted = recorder._secondary._writer
		stats.peak_bytes = maxi(writer.peak_bytes,english_writer.peak_bytes)
		check(stats.peak_bytes <= writer.MAX_BYTES,kind + " encoder memory remains bounded")
		recorder.stop()
		await wait_idle()
		clock.pulse_active = false
		check(not writer.is_running() and not english_writer.is_running(),kind + " writer threads drain and finish")
		check(writer.frames_written == recorder._frame_index and english_writer.frames_written == recorder._frame_index,kind + " no accepted frames lost by either writer")
		stats.frames = recorder._frame_index
		stats.outputs = recorder.last_outputs.duplicate()
		check(stats.outputs.size()==2,kind + " produces both language files")
		check(is_equal_approx(Engine.time_scale,1.0),kind + " restores normal game speed after stop")
		results.append(stats)
	# Fault-inject the independent speed witness; do not slow actual game physics.
	game.Game_Settings.Training_Mode_Type = "manual"
	recorder.start_live()
	await wall_wait(0.5)
	recorder._speed_warmup = 0.0
	recorder._speed_real = 2.1
	recorder._speed_physics_start = recorder._physics_clock + 5.0
	await wall_wait(0.2)
	await wait_idle()
	check(recorder.get_last_error().contains("明显减速") and recorder.last_outputs.is_empty(), "detected simulation slowdown cannot be published as a successful final video")
	check(not paused and is_equal_approx(Engine.time_scale,1.0), "overload guard leaves the game unpaused at normal speed")
	var f := FileAccess.open("user://recordings/speed_test/manifest.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"baseline":baseline,"runs":results},"\t"))
	f.close()
	print("SPEED_METRICS=",JSON.stringify(results))
	tone.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("RECORDING_SPEED: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
