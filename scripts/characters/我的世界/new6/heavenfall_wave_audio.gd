extends RefCounted
# Arrival cue has a small independent pool: later MC hit priorities must not steal it.
# This respects the regular gameplay bus, user volume and global pause/time control.
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const MAX_VOICES: int = 4

static func play(context: Node, point: Vector2) -> AudioStreamPlayer2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree: SceneTree = context.get_tree()
	if tree.current_scene == null or tree.paused or Game.now_stop_state: return null
	if context.has_meta("heavenfall_wave_played"): return null
	context.set_meta("heavenfall_wave_played", true)
	var active: Array[Node] = tree.get_nodes_in_group("HeavenfallWaveSFX")
	while active.size() >= MAX_VOICES:
		var oldest: Node = active.pop_front()
		oldest.stop()
		oldest.remove_from_group("HeavenfallWaveSFX")
		oldest.queue_free()
	var record: Dictionary = AUDIO.EVENTS["entity.heavenfall.wave"].pick_random()
	var player := AudioStreamPlayer2D.new()
	player.stream = record["stream"]
	player.pitch_scale = float(record["pitch"])
	player.volume_db = 0.0
	player.max_distance = 2400.0
	player.attenuation = 0.25
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	tree.current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("HeavenfallWaveSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sound_event", "entity.heavenfall.wave")
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()
	return player
