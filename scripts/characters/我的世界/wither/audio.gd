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
# Loaded lazily: both scripts reference the Game autoload, and tests preload this file.
const NATIVE_AUDIO_PATH:String = "res://scripts/effects/我的世界/mc_native_audio.gd"
const GENERIC_SOUNDS_PATH:String = "res://scripts/characters/我的世界/new5/audio.gd"
const EXPLOSION_EVENT:String = "entity.generic.explode"
const EXPLOSION_VOLUME_DB:float = 2.0
const EXPLOSION_MAX_DISTANCE:float = 2400.0

static func play(source:Node,event:String,point:Vector2) -> void:
	if event == "explode":
		play_explosion(source,point)
		return
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

## 原版爆炸（头颅命中、苏醒爆炸）统一播放 entity.generic.explode：四个变体随机，
## 音调 (1+(r1-r2)*0.2)*0.7。变体和音调由爆炸点推出，主机与客户端听到同一声。
static func explosion_choice(point:Vector2) -> Dictionary:
	var records:Array = load(GENERIC_SOUNDS_PATH).EVENTS[EXPLOSION_EVENT]
	var rng:=RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(point.x*8.0),roundi(point.y*8.0)))
	var record:Dictionary = records[rng.randi_range(0,records.size()-1)]
	return {"stream":record["stream"],"pitch":(1.0+(rng.randf()-rng.randf())*0.2)*0.7}

static func play_explosion(source:Node,point:Vector2) -> Dictionary:
	if not is_instance_valid(source) or not source.is_inside_tree(): return {}
	var choice:Dictionary = explosion_choice(point)
	return load(NATIVE_AUDIO_PATH).queue_stream(source,choice["stream"],point,{"volume_db":EXPLOSION_VOLUME_DB,"pitch":choice["pitch"],
		"priority":true,"keep_after_source":true,"max_distance":EXPLOSION_MAX_DISTANCE,
		"metadata":{"mc_sound_event":EXPLOSION_EVENT,"mc_sound_priority":true}})
