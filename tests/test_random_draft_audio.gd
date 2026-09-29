extends SceneTree
## Dedicated UI sound regression and an optional actual mixer capture (-- --record).
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)
func wait_real(seconds:float) -> void:
	var until:int = Time.get_ticks_msec()+int(ceil(seconds*1000))
	while Time.get_ticks_msec()<until: await process_frame

func run() -> void:
	var audio:Node = load("res://scripts/ui/random_character_draft_audio.gd").new()
	root.add_child(audio)
	await process_frame
	var audios:Node = root.get_node("Audios")
	var ui_bus:int = AudioServer.get_bus_index("UI")
	var master:int = AudioServer.get_bus_index("Master")
	check(audio._players.size()==4,"exactly four reusable sound voices")
	for player:AudioStreamPlayer in audio._players.values():
		check(player.bus==&"UI" and player.process_mode==Node.PROCESS_MODE_ALWAYS,"UI routing and pause-safe processing")
		check(player.max_polyphony==1 and player.volume_db>=-8 and player.volume_db<=-3,"bounded polyphony and audible local gain")
	var sources:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://audio/ui/random_draft/SOURCE.json"))
	for asset:Dictionary in sources.assets:
		check(FileAccess.get_sha256("res://audio/ui/random_draft/"+str(asset.file))==str(asset.sha256),"verified original sound bytes: "+str(asset.file))
	for asset:Dictionary in sources.runtime_assets:
		check(FileAccess.get_sha256("res://audio/ui/random_draft/"+str(asset.file))==str(asset.sha256),"verified runtime PCM bytes: "+str(asset.file))
	audio.reset_round()
	audio.begin_ticket()
	check(audio.play_tick(),"first reel step plays")
	for index:int in range(100): audio.play_tick()
	check(int(audio.played_counts.get("tick",0))==1,"repeated ticks are rate limited, not stacked")
	await wait_real(0.12)
	check(audio.play_tick(),"next eligible tick plays after cooldown")
	check(audio.play_confirmation(),"reveal plays original experience-orb cue")
	check(not audio._players.tick.playing and not audio.play_tick(),"reveal stops rolling sound")
	check(not audio.play_confirmation(),"duplicate dense reveals are coalesced")
	check(audio.play_arrival() and not audio.play_arrival(),"arrival pop is rate limited")
	check(audio.play_complete() and not audio.play_complete(),"level-up cue plays exactly once per round")
	check(not audio._players.confirm.playing and not audio._players.arrival.playing,"completion replaces lesser cues")
	check(audio.completion_duration()>=audio.STREAMS.complete.get_length(),"completion hold covers the entire original level-up sound")
	audio.stop_all()
	for player:AudioStreamPlayer in audio._players.values(): check(not player.playing,"stop clears all playing voices")
	check(not audio.play_arrival() and not audio.play_confirmation(),"cancel prevents late sound callbacks")

	var saved_scale:float = Engine.time_scale
	Engine.time_scale = 2.0
	audios.set_game_time_scale(2.0)
	audio.reset_round()
	paused = true
	audio.play_confirmation()
	await process_frame
	check(audio._players.confirm.can_process() and not audio._players.confirm.stream_paused,"draft pause does not mute its UI cue")
	check(is_equal_approx(audio._players.confirm.pitch_scale*AudioServer.playback_speed_scale,1.0),"2x battle speed does not change UI sound pitch")
	paused = false
	Engine.time_scale = saved_scale
	audios.set_game_time_scale(saved_scale)
	var saved_ui_mute:bool = AudioServer.is_bus_mute(ui_bus)
	var saved_master_mute:bool = AudioServer.is_bus_mute(master)
	var saved_ui_gain:float = AudioServer.get_bus_volume_db(ui_bus)
	AudioServer.set_bus_mute(ui_bus,true)
	AudioServer.set_bus_mute(master,true)
	AudioServer.set_bus_volume_db(ui_bus,-12)
	audio.reset_round()
	audio.play_confirmation()
	check(AudioServer.is_bus_mute(ui_bus) and AudioServer.is_bus_mute(master),"sound requests respect existing mute settings")
	check(is_equal_approx(AudioServer.get_bus_volume_db(ui_bus),-12.0),"sound requests never overwrite user gain")
	AudioServer.set_bus_mute(ui_bus,saved_ui_mute)
	AudioServer.set_bus_mute(master,saved_master_mute)
	AudioServer.set_bus_volume_db(ui_bus,saved_ui_gain)
	audio.reset_round()
	seed(73589)
	var expected:float = randf()
	seed(73589)
	audio.begin_ticket()
	audio.play_tick()
	check(is_equal_approx(randf(),expected),"sound effects do not consume global battle randomness")
	audio.stop_all()

	if "--record" in OS.get_cmdline_user_args():
		# Capture the real UI mixer, not a separately synthesized approximation.
		var recorder := AudioEffectRecord.new()
		recorder.format = AudioStreamWAV.FORMAT_16_BITS
		var effect_index:int = AudioServer.get_bus_effect_count(ui_bus)
		AudioServer.add_bus_effect(ui_bus,recorder)
		AudioServer.set_bus_mute(ui_bus,false)
		AudioServer.set_bus_volume_db(ui_bus,0.0)
		recorder.set_recording_active(true)
		await wait_real(0.12)
		audio.reset_round()
		audio.begin_ticket()
		for interval:float in [0.10,0.10,0.12,0.14,0.17,0.22]:
			audio.play_tick()
			await wait_real(interval)
		audio.play_confirmation()
		await wait_real(0.38)
		audio.play_arrival()
		await wait_real(0.52)
		audio.play_complete()
		await wait_real(audio.completion_duration()+0.18)
		recorder.set_recording_active(false)
		var recording:AudioStreamWAV = recorder.get_recording()
		check(recording!=null and recording.data.size()>0,"audio mixer produced recorded PCM")
		if recording!=null:
			var peak:int = 0
			for index:int in range(0,recording.data.size()-1,2): peak = maxi(peak,absi(recording.data.decode_s16(index)))
			check(peak>18000 and peak<32000,"recorded audio has the raised gain and remains unclipped")
			check(recording.save_to_wav("res://tests/random_draft_sound_preview.wav")==OK,"actual sound preview saved")
			print("DRAFT_AUDIO_RECORD seconds=",recording.get_length()," peak=",peak)
		AudioServer.remove_bus_effect(ui_bus,effect_index)
		AudioServer.set_bus_mute(ui_bus,saved_ui_mute)
		AudioServer.set_bus_volume_db(ui_bus,saved_ui_gain)
	var voice_reference:WeakRef = weakref(audio._players.complete)
	audio.free()
	check(voice_reference.get_ref()==null,"freeing overlay-owned sound node destroys every voice")
	await process_frame
	print("RANDOM_DRAFT_AUDIO checks=",checks," failures=",failures)
	quit(1 if failures else 0)
