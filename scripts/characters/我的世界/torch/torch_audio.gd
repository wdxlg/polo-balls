extends RefCounted
## 火把的原版 Java 音效（来源与 SHA1 见 audio/characters/我的世界/torch/SOURCE.json）。
## 变体序号只由权威端挑选后经 RPC 下发；这里只负责按序号播放。
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const IGNITE:Array[AudioStream] = [preload("res://audio/characters/我的世界/torch/ignite.ogg")]
const DASH:Array[AudioStream] = [preload("res://audio/characters/我的世界/torch/firecharge_use.ogg")]
const FIZZ:Array[AudioStream] = [preload("res://audio/characters/我的世界/torch/fizz.ogg")]
const SOUL:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/torch/soul_escape1.ogg"),
	preload("res://audio/characters/我的世界/torch/soul_escape2.ogg"),
	preload("res://audio/characters/我的世界/torch/soul_escape3.ogg"),
	preload("res://audio/characters/我的世界/torch/soul_escape4.ogg"),
	preload("res://audio/characters/我的世界/torch/soul_escape5.ogg"),
]
const KIND_IGNITE:int = 0
const KIND_DASH:int = 1
const KIND_FIZZ:int = 2
const KIND_SOUL:int = 3
# 火星落地很频繁，点火声压低；变成灵魂火把与连冲是关键提示，音量略高。
const OPTIONS:Array[Dictionary] = [
	{"event":"item.flintandsteel.use","volume_db":-13.0},
	{"event":"item.firecharge.use","volume_db":-7.0},
	{"event":"block.fire.extinguish","volume_db":-9.0},
	{"event":"particle.soul_escape","volume_db":-2.0,"priority":true,"keep_after_source":true},
]


static func streams(kind:int) -> Array[AudioStream]:
	match kind:
		KIND_IGNITE: return IGNITE
		KIND_DASH: return DASH
		KIND_FIZZ: return FIZZ
		KIND_SOUL: return SOUL
	return []


static func variant_count(kind:int) -> int:
	return streams(kind).size()


static func play(context:Node,kind:int,index:int,point:Vector2,pitch:float = 1.0) -> Dictionary:
	var list:Array[AudioStream] = streams(kind)
	if list.is_empty() or kind < 0 or kind >= OPTIONS.size(): return {}
	var options:Dictionary = OPTIONS[kind].duplicate()
	var event:String = str(options.get("event",""))
	options.erase("event")
	options["pitch"] = pitch
	options["metadata"] = {"mc_sound_event":event}
	return NATIVE.queue_stream(context,list[posmod(index,list.size())],point,options)
