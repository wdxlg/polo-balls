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
	"charge": preload("res://audio/characters/我的世界/wither/wither_charge.ogg"),
	"heart": preload("res://audio/characters/我的世界/wither/nether_star_shoot.ogg"),
	"beacon_activate": preload("res://audio/characters/我的世界/wither/beacon_activate.ogg"),
	"beacon_ambient": preload("res://audio/characters/我的世界/wither/beacon_ambient.ogg"),
	"beacon_power": preload("res://audio/characters/我的世界/wither/beacon_power.ogg"),
	"beacon_deactivate": preload("res://audio/characters/我的世界/wither/beacon_deactivate.ogg"),
	"beacon_morph": preload("res://audio/characters/我的世界/wither/beacon_morph.ogg"),
	"soul_sand": preload("res://audio/characters/我的世界/wither/soul_sand.ogg"),
	"rose": preload("res://audio/characters/我的世界/wither/rose.ogg"),
}
static func play(source:Node,event:String,point:Vector2) -> void:
	if not STREAMS.has(event) or not is_instance_valid(source) or not source.is_inside_tree(): return
	var tree:SceneTree = source.get_tree()
	var parent:Node = tree.current_scene
	if parent == null or parent.is_queued_for_deletion(): return
	# Both _ready and _exit_tree can run while the scene's child list is locked.
	# Defer the WHOLE operation, not just add_child or play; allocate only after
	# validating the original scene. Do not retain the dying sound source.
	_play_in_scene.call_deferred(weakref(tree),weakref(parent),event,point)

static func _play_in_scene(tree_ref:WeakRef,parent_ref:WeakRef,event:String,point:Vector2) -> void:
	var tree:SceneTree = tree_ref.get_ref() as SceneTree
	var parent:Node = parent_ref.get_ref() as Node
	if tree == null or not is_instance_valid(parent) or parent.is_queued_for_deletion(): return
	if not parent.is_inside_tree() or parent.get_tree() != tree or tree.current_scene != parent: return
	var player:=AudioStreamPlayer2D.new()
	player.stream = STREAMS[event]
	player.volume_db = 0.0
	player.max_distance = 1800.0
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	parent.add_child(player)
	player.global_position = point
	player.play()
