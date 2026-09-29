extends RefCounted

const NATIVE_AUDIO:Script = preload("res://scripts/characters/我的世界/new5/audio.gd")

const DAMAGE_SFX = [
	preload("res://audio/characters/女巫/hit1.ogg"),
	preload("res://audio/characters/女巫/hit2.ogg"),
	preload("res://audio/characters/女巫/hit3.ogg"),
]


static func play(context_node:Node,world_position:Vector2,gain_db:float = 0.0) -> void:
	if context_node == null or not is_instance_valid(context_node):
		return
	var tree:SceneTree = context_node.get_tree()
	if tree == null:
		return
	var world:Node = tree.current_scene
	if world == null or DAMAGE_SFX.is_empty():
		return
	var player:=AudioStreamPlayer2D.new()
	player.stream = DAMAGE_SFX.pick_random()
	player.volume_db = 1.0 + clampf(gain_db,0.0,12.0)
	player.pitch_scale = randf_range(0.98,1.02)
	world.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	player.play()


# 通用 MC 命中按实际掉血选音；已由公共伤害入口发声的来源不重复播放。
# 与其他Minecraft命中音效统一：原音量起步，按实际伤害渐增到+6 dB以内。
static func impact_volume(actual_health_damage:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual_health_damage)


static func play_scaled(context_node:Node,world_position:Vector2,actual_health_damage:float,source:Node = null,damage_kind:String = "") -> AudioStreamPlayer2D:
	if preload("res://scripts/effects/我的世界/mc_hit_feedback.gd").manages(source): return null
	var actual:float = maxf(actual_health_damage,0.0)
	if actual <= 0.0:
		return null
	var player:AudioStreamPlayer2D = NATIVE_AUDIO.play(
		context_node,
		preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_event(actual),
		world_position,
		impact_volume(actual),
		false,
		true,
		true,
		true
	)
	if player == null or not is_instance_valid(player):
		return null
	player.pitch_scale = randf_range(0.98,1.02)
	player.set_meta("mc_actual_damage",actual)
	if source != null and is_instance_valid(source):
		player.set_meta("mc_damage_source",source.get_instance_id())
	if not damage_kind.is_empty():
		player.set_meta("mc_damage_kind",damage_kind)
	return player
