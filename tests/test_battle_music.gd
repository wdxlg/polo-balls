extends "res://tests/test_mc_bat.gd"
# Use registered music for playback lifecycle checks and a short tone for looping.

var music: Node
var _original_settings:PackedByteArray
var _settings_existed:bool = false
var _settings_captured:bool = false

func finish(code:int) -> void:
	if done: return
	if _settings_captured:
		if _settings_existed:
			var file:=FileAccess.open(game.SETTINGS_PATH,FileAccess.WRITE)
			file.store_buffer(_original_settings)
			file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(game.SETTINGS_PATH))
	super.finish(code)


func _tone(seconds: float) -> AudioStreamWAV:
	var rate: int = 22050
	var count: int = int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		data.encode_s16(i * 2, int(sin(TAU * 220.0 * float(i) / float(rate)) * 3000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _real_wait(seconds: float) -> void:
	# 真实时间等待：不受 Engine.time_scale 影响，也不受 SceneTree 暂停影响。
	await create_timer(seconds, true, false, true).timeout


func _dummy(point: Vector2, team: String) -> Node2D:
	var unit: Node2D = spawn("res://scenes/ball.tscn", point, team)
	unit.state_machine.set_physics_process(false)
	unit.Has_Collision_Damage = false
	unit.Speed = 0.0
	unit.default_properties.Speed = 0.0
	unit.direction = Vector2.ZERO
	return unit


func _spawn_pair(center: Vector2) -> void:
	_dummy(center + Vector2(-40, 0), "Team0")
	_dummy(center + Vector2(40, 0), "Team1")


func _clear() -> void:
	world.reset()
	await _frames(3)


func run() -> void:
	game = root.get_node("Game")
	_settings_existed = FileAccess.file_exists(game.SETTINGS_PATH)
	if _settings_existed: _original_settings = FileAccess.get_file_as_bytes(game.SETTINGS_PATH)
	_settings_captured = true
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Battle_Music = "none"
	game.set_runtime_game_setting("Battle_Music_Volume",100.0,false)
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(100.0, true, false, true).timeout.connect(func(): finish(2))

	# ---- 设置项与登记表 ----
	music = game.get_node_or_null("BattleMusic")
	check(music != null, "Game owns the battle music controller")
	if music == null:
		finish(1)
		return
	var registry: Script = music.get_script()
	check(Array(registry.OPTIONS) == ["none","the_king"], "the music list offers None and The King")
	var song:AudioStream = registry.track_stream("the_king")
	check(song is AudioStreamMP3 and song.resource_path=="res://audio/music/the_king.mp3" and song.get_length()>30.0,"The King loads from the music directory as a real MP3")
	for locale:String in ["zh","en"]:
		check(game._localization._t_for_locale("BATTLE_MUSIC_THE_KING",locale,false)=="The King","The King is translated in "+locale)
	check(registry.normalize("removed_track") == "none", "an unknown or removed track falls back to 无")
	var defaults: Variant = game.get_script().get_property_default_value("Game_Settings")
	check(defaults is Dictionary and str((defaults as Dictionary).get("Battle_Music", "")) == "none", "the music setting defaults to 无")
	check(not game._is_network_shared_setting("Battle_Music"), "music is a local preference and is never synced to the room")
	check(defaults.get("Battle_Music_Volume")==100.0,"music volume defaults to 100 percent for old settings")
	check(not game._is_network_shared_setting("Battle_Music_Volume") and not game._shared_settings_snapshot().has("Battle_Music_Volume"),"volume is a local preference excluded from room snapshots")
	check(registry.normalize_volume(-1)==0.0 and registry.normalize_volume(150)==100.0,"volume clamps to zero through one hundred")
	check(registry.normalize_volume(NAN)==100.0 and registry.normalize_volume(INF)==100.0 and registry.normalize_volume("bad")==100.0,"invalid volume safely falls back to the default")
	var player: AudioStreamPlayer = music.player()
	check(player.bus == &"GameplayRecord", "music plays on the gameplay bus (time-scaled like other game audio)")
	check(player.process_mode == Node.PROCESS_MODE_PAUSABLE, "the music player pauses together with the game")

	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.55).timeout
	var arena: Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	var center: Vector2 = arena.get_center()

	# ---- 设置界面 ----
	var box := VBoxContainer.new()
	world.control.add_child(box)
	world.control._create_battle_music_setting(box)
	var option: OptionButton = box.find_child("BattleMusicOption", true, false) as OptionButton
	check(option != null and option.item_count == 2 and str(option.get_item_metadata(0)) == "none" and option.selected == 0, "the settings dropdown offers two tracks with None selected")
	check(option != null and option.get_item_text(0) == game.ui_t("BATTLE_MUSIC_NONE") and game.ui_t("BATTLE_MUSIC_NONE") != "BATTLE_MUSIC_NONE", "the 无 entry is translated")
	check(option.get_item_text(1)=="The King" and str(option.get_item_metadata(1))=="the_king","the dropdown exposes the registered The King track")
	option.select(1)
	option.item_selected.emit(1)
	check(game.Game_Settings.Battle_Music=="the_king" and music.current_track()=="the_king" and player.stream==song,"selecting The King in settings loads the actual music")
	game.set_runtime_game_setting("Battle_Music","none",false)
	var slider:HSlider = box.find_child("BattleMusicVolumeSlider",true,false) as HSlider
	var value_label:Label = box.find_child("BattleMusicVolumeValue",true,false) as Label
	check(slider!=null and slider.min_value==0.0 and slider.max_value==100.0 and slider.step==1.0 and slider.value==100.0,"settings offer a zero-to-one-hundred percent volume slider")
	slider.value = 25.0
	check(game.Game_Settings.Battle_Music_Volume==25.0 and value_label.text=="25%" and is_equal_approx(player.volume_linear,0.25),"slider updates music gain and percentage immediately")
	var config:=ConfigFile.new()
	check(config.load(game.SETTINGS_PATH)==OK and config.get_value("game_settings","Battle_Music_Volume")==25.0,"slider automatically saves the local volume")
	game.Game_Settings.Battle_Music_Volume=90.0
	game.load_persistent_settings()
	check(game.Game_Settings.Battle_Music_Volume==25.0,"saved volume survives a settings reload")
	var restored:Node = registry.new()
	game.add_child(restored)
	check(is_equal_approx(restored.player().volume_linear,0.25),"a new music controller restores the saved gain")
	restored.free()
	game._receive_shared_setting("Battle_Music_Volume",80.0)
	check(game.Game_Settings.Battle_Music_Volume==25.0,"remote room settings cannot overwrite local volume")
	game.set_runtime_game_setting("Battle_Music_Volume",50.0,false)
	await _frames(2)
	check(slider.value==50.0 and value_label.text=="50%","external setting changes update the slider without feedback loops")
	for locale:String in ["zh","en"]:
		check(game._localization._t_for_locale("SETTING_BATTLE_MUSIC_VOLUME",locale,false)==("音乐音量" if locale=="zh" else "Music Volume"),"volume label is translated in "+locale)
	await capture_music_controls(box)
	game.set_runtime_game_setting("Battle_Music_Volume",100.0,false)
	box.queue_free()

	# ---- 选“无”：开战也保持安静 ----
	await _clear()
	check(not music.is_round_active(), "no battle, no music round")
	_spawn_pair(center)
	await _frames(4)
	check(music.is_round_active() and not music.is_music_playing(), "with 无 selected the battle starts silently")
	await _clear()
	check(not music.is_round_active(), "reset ends the music round")

	# ---- 有曲目时：时间静止推迟开始 ----
	game.set_runtime_game_setting("Battle_Music","the_king",false)
	check(player.stream==song,"battle playback uses The King, not a test tone")
	check(not music.is_music_playing(), "a track does not play before the battle starts")
	game.now_stop_state = true
	_spawn_pair(center)
	await _frames(5)
	check(not music.is_music_playing(), "while time is stopped the battle has not actually started, so no music")
	game.now_stop_state = false
	await _frames(3)
	check(music.is_music_playing(), "the music starts when the battle actually starts")
	await _real_wait(0.15)
	check(music.playback_position() < 0.6, "the music starts from the beginning (%.2fs)" % music.playback_position())

	# Music-only gain changes must never restart a playing stream or mute the gameplay bus.
	var other:=AudioStreamPlayer.new()
	other.bus=&"GameplayRecord"
	other.volume_linear=0.35
	other.stream=_tone(8.0)
	root.add_child(other)
	other.play()
	var bus_index:int=AudioServer.get_bus_index("GameplayRecord")
	var bus_gain:float=AudioServer.get_bus_volume_db(bus_index)
	var before_volume:float=music.playback_position()
	game.set_runtime_game_setting("Battle_Music_Volume",50.0,false)
	await _real_wait(0.15)
	check(is_equal_approx(player.volume_linear,0.5) and music.playback_position()>=before_volume,"live volume changes preserve the playback position")
	before_volume=music.playback_position()
	game.set_runtime_game_setting("Battle_Music_Volume",0.0,false)
	await _real_wait(0.15)
	check(is_zero_approx(player.volume_linear) and music.is_music_playing() and music.playback_position()>before_volume,"zero percent mutes without stopping the timeline")
	check(is_equal_approx(other.volume_linear,0.35) and other.playing and AudioServer.get_bus_volume_db(bus_index)==bus_gain and not AudioServer.is_bus_mute(bus_index),"other gameplay sounds and the shared bus are unaffected")
	game.set_runtime_game_setting("Battle_Music_Volume",200.0,false)
	check(game.Game_Settings.Battle_Music_Volume==100.0 and is_equal_approx(player.volume_linear,1.0),"runtime settings clamp excessive volume and restore original gain")
	other.queue_free()

	# ---- 时间流速 ----
	var p0: float = music.playback_position()
	await _real_wait(0.5)
	var normal_advance: float = music.playback_position() - p0
	Engine.time_scale = 3.0
	await _frames(2)
	check(is_equal_approx(AudioServer.playback_speed_scale, 3.0), "audio playback speed follows the 3x time scale (%.2f)" % AudioServer.playback_speed_scale)
	var p1: float = music.playback_position()
	await _real_wait(0.5)
	var fast_advance: float = music.playback_position() - p1
	Engine.time_scale = 1.0
	await _frames(2)
	print("PMUSIC: normal=", normal_advance, " fast=", fast_advance)
	check(normal_advance > 0.25 and normal_advance < 0.8, "at 1x the music advances in real time (%.2fs per 0.5s)" % normal_advance)
	check(fast_advance > normal_advance * 2.0, "at 3x the music plays faster (%.2fs vs %.2fs)" % [fast_advance, normal_advance])

	# ---- 暂停 ----
	paused = true
	await _frames(2)
	var pp: float = music.playback_position()
	game.set_runtime_game_setting("Battle_Music_Volume",35.0,false)
	check(is_equal_approx(player.volume_linear,0.35),"volume can change while paused without restarting music")
	await _real_wait(0.4)
	var paused_advance: float = music.playback_position() - pp
	paused = false
	await _frames(2)
	check(paused_advance < 0.1, "pausing the game pauses the music (%.2fs)" % paused_advance)
	check(music.is_music_playing(), "unpausing resumes the music")

	# ---- 重置：停止并回到开头，下一局从头放 ----
	await _real_wait(0.3)
	var before_reset: float = music.playback_position()
	await _clear()
	check(not music.is_music_playing() and not music.is_round_active(), "reset stops the music")
	check(music.playback_position() == 0.0, "reset rewinds the music")
	_spawn_pair(center)
	await _frames(3)
	check(music.is_music_playing(), "the next battle starts the music again")
	check(is_equal_approx(player.volume_linear,0.35),"reset keeps the chosen music volume")
	check(before_reset > 0.5 and music.playback_position() < 0.3, "and it plays from the beginning (%.2fs, was %.2fs)" % [music.playback_position(), before_reset])

	# ---- 重打 / 轮放系列重开：会话结束信号 ----
	await _real_wait(0.4)
	game.end_battle_random()
	check(not music.is_music_playing(), "a battle session ending (rematch) stops the music at once")
	await _frames(3)
	check(music.is_music_playing() and music.playback_position() < 0.3, "the rematched battle plays the music from the beginning")

	# ---- 循环 ----
	music.debug_set_stream(_tone(0.3), true)
	await _real_wait(0.8)
	check(music.is_music_playing(), "a track shorter than the battle loops")

	game.set_runtime_game_setting("Battle_Music_Volume",42.0,false)
	# ---- 战斗中切回“无” ----
	game.set_runtime_game_setting("Battle_Music", "none", false)
	await _frames(2)
	check(not music.is_music_playing() and player.stream == null, "switching to 无 mid-battle silences the music")
	game.set_runtime_game_setting("Battle_Music","the_king",false)
	check(is_equal_approx(player.volume_linear,0.42),"switching tracks keeps the volume preference")

	# ---- 离开 World ----
	music.debug_set_stream(_tone(8.0))
	await _frames(2)
	check(music.is_music_playing(), "fixture: music playing before leaving the world")
	current_scene = null
	world.queue_free()
	await _frames(3)
	check(not music.is_music_playing() and not music.is_round_active(), "leaving the world stops the music")
	world = null
	music.debug_set_stream(null)
	print("BATTLE MUSIC RESULT: %d/%d passed" % [checks - failures, checks])
	finish(0 if failures == 0 else 1)

func capture_music_controls(box:VBoxContainer) -> void:
	var path:String=OS.get_environment("BATTLE_MUSIC_UI_CAPTURE")
	if path.is_empty() or DisplayServer.get_name()=="headless": return
	var previous_parent:Node=box.get_parent()
	var view:=SubViewport.new()
	view.size=Vector2i(720,240)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var panel:=PanelContainer.new()
	panel.position=Vector2(12,12)
	panel.size=Vector2(232,68)
	panel.scale=Vector2(3,3)
	view.add_child(panel)
	box.reparent(panel)
	await _frames(3)
	await RenderingServer.frame_post_draw
	check(box.size.x<=232.0 and box.get_combined_minimum_size().x<=232.0,"music controls fit the existing narrow settings width")
	check(view.get_texture().get_image().save_png(path)==OK,"GPU settings capture saved outside the project")
	box.reparent(previous_parent)
	view.queue_free()
