extends RefCounted
## Vanilla Java 1.21.11 sounds; every SHA-1 is in SOURCE_MANIFEST.json.
const STREAMS:Dictionary = {
	"spawn": preload("res://audio/characters/我的世界/wither/spawn.ogg"),
	"shoot": preload("res://audio/characters/我的世界/wither/shoot.ogg"),
	"hurt1": preload("res://audio/characters/我的世界/wither/hurt1.ogg"),
	"hurt2": preload("res://audio/characters/我的世界/wither/hurt2.ogg"),
	"hurt3": preload("res://audio/characters/我的世界/wither/hurt3.ogg"),
	"hurt4": preload("res://audio/characters/我的世界/wither/hurt4.ogg"),
	"death": preload("res://audio/characters/我的世界/wither/death.ogg"),
	"idle1": preload("res://audio/characters/我的世界/wither/idle1.ogg"),
	"idle2": preload("res://audio/characters/我的世界/wither/idle2.ogg"),
	"explode": preload("res://audio/characters/我的世界/wither/explode.ogg"),
	"beacon_activate": preload("res://audio/characters/我的世界/wither/beacon_activate.ogg"),
	"beacon_power": preload("res://audio/characters/我的世界/wither/beacon_power.ogg"),
	"beacon_deactivate": preload("res://audio/characters/我的世界/wither/beacon_deactivate.ogg"),
	"soul_sand": preload("res://audio/characters/我的世界/wither/soul_sand.ogg"),
	"rose": preload("res://audio/characters/我的世界/wither/rose.ogg"),
}
static func play(source:Node,event:String,position:Vector2) -> void:
	if not STREAMS.has(event) or not is_instance_valid(source) or source.get_tree() == null: return
	var parent:Node = source.get_tree().current_scene
	if parent == null: return
	var player:=AudioStreamPlayer2D.new()
	player.stream = STREAMS[event]
	player.volume_db = 0.0
	player.max_distance = 1800.0
	parent.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()
