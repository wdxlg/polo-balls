extends "res://tests/test_mc_bat.gd"
# 设置“音乐”：默认且目前唯一的选项是“无”；战斗实际开始时从头播放，
# 播放速度跟随时间流速、暂停随游戏暂停；重置 / 重打停止并回到开头。
# 登记表只有“无”，所以用程序生成的音调流验证播放流程。

var music: Node


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
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Battle_Music = "none"
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
	check(Array(registry.OPTIONS) == ["none"], "the music list only offers 无 (none)")
	check(registry.normalize("removed_track") == "none", "an unknown or removed track falls back to 无")
	var defaults: Variant = game.get_script().get_property_default_value("Game_Settings")
	check(defaults is Dictionary and str((defaults as Dictionary).get("Battle_Music", "")) == "none", "the music setting defaults to 无")
	check(not game._is_network_shared_setting("Battle_Music"), "music is a local preference and is never synced to the room")
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
	check(option != null and option.item_count == 1 and str(option.get_item_metadata(0)) == "none" and option.selected == 0, "the settings dropdown has exactly one entry, 无, selected")
	check(option != null and option.get_item_text(0) == game.ui_t("BATTLE_MUSIC_NONE") and game.ui_t("BATTLE_MUSIC_NONE") != "BATTLE_MUSIC_NONE", "the 无 entry is translated")
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
	music.debug_set_stream(_tone(8.0))
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

	# ---- 战斗中切回“无” ----
	game.set_runtime_game_setting("Battle_Music", "none", false)
	await _frames(2)
	check(not music.is_music_playing() and player.stream == null, "switching to 无 mid-battle silences the music")

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
