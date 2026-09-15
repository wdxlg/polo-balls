extends RefCounted

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
