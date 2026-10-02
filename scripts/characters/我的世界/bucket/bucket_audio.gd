extends RefCounted
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const DIR:String = "res://audio/characters/我的世界/bucket/"
const EMPTY:Array[AudioStream] = [preload(DIR + "bucket_empty1.ogg"),preload(DIR + "bucket_empty2.ogg"),preload(DIR + "bucket_empty3.ogg")]
const EMPTY_LAVA:Array[AudioStream] = [preload(DIR + "bucket_empty_lava1.ogg"),preload(DIR + "bucket_empty_lava2.ogg"),preload(DIR + "bucket_empty_lava3.ogg")]
const WATER:Array[AudioStream] = [preload(DIR + "water_ambient.ogg")]
const LAVA:Array[AudioStream] = [preload(DIR + "lava_ambient.ogg")]
const POP:Array[AudioStream] = [preload(DIR + "lava_pop.ogg")]
const FIZZ:Array[AudioStream] = [preload(DIR + "fizz.ogg")]
const SPLASH:Array[AudioStream] = [preload(DIR + "splash.ogg")]
const DROWN:Array[AudioStream] = [preload(DIR + "drown1.ogg"),preload(DIR + "drown2.ogg"),preload(DIR + "drown3.ogg"),preload(DIR + "drown4.ogg")]
const STONE:Array[AudioStream] = [preload(DIR + "stone_break1.ogg"),preload(DIR + "stone_break2.ogg"),preload(DIR + "stone_break3.ogg"),preload(DIR + "stone_break4.ogg")]
const KIND_EMPTY:int = 0
const KIND_EMPTY_LAVA:int = 1
const KIND_WATER:int = 2
const KIND_LAVA:int = 3
const KIND_POP:int = 4
const KIND_FIZZ:int = 5
const KIND_SPLASH:int = 6
const KIND_DROWN:int = 7
const KIND_STONE:int = 8
const OPTIONS:Array[Dictionary] = [
	{"event":"item.bucket.empty","volume_db":-4.0},
	{"event":"item.bucket.empty_lava","volume_db":-4.0},
	{"event":"block.water.ambient","volume_db":-16.0,"keep_after_source":true},
	{"event":"block.lava.ambient","volume_db":-12.0,"keep_after_source":true},
	{"event":"block.lava.pop","volume_db":-12.0,"keep_after_source":true},
	{"event":"block.lava.extinguish","volume_db":-8.0,"keep_after_source":true},
	{"event":"entity.generic.splash","volume_db":-10.0},
	{"event":"entity.player.hurt_drown","volume_db":-6.0},
	{"event":"block.stone.break","volume_db":-5.0,"keep_after_source":true},
]


static func streams(kind:int) -> Array[AudioStream]:
	match kind:
		KIND_EMPTY: return EMPTY
		KIND_EMPTY_LAVA: return EMPTY_LAVA
		KIND_WATER: return WATER
		KIND_LAVA: return LAVA
		KIND_POP: return POP
		KIND_FIZZ: return FIZZ
		KIND_SPLASH: return SPLASH
		KIND_DROWN: return DROWN
		KIND_STONE: return STONE
	return []


static func variant_count(kind:int) -> int:
	return streams(kind).size()


static func play(context:Node,kind:int,index:int,point:Vector2,pitch:float = 1.0) -> Dictionary:
	var list:Array[AudioStream] = streams(kind)
	if list.is_empty() or kind < 0 or kind >= OPTIONS.size() or not is_instance_valid(context) or not context.is_inside_tree(): return {}
	var options:Dictionary = OPTIONS[kind].duplicate()
	var event:String = str(options.get("event",""))
	options.erase("event")
	options["pitch"] = pitch
	options["metadata"] = {"mc_sound_event":event}
	return NATIVE.queue_stream(context,list[posmod(index,list.size())],point,options)
