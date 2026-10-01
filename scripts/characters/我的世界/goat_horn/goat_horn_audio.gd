extends RefCounted
## 山羊角与山羊的原版 Java 音效（来源与 SHA1 见 audio/characters/我的世界/goat_horn/SOURCE.json）。
## 变体序号只由权威端挑选后经 RPC 下发；这里只负责按序号播放。
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const CALL:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call0.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call1.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call2.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call3.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call4.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call5.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call6.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_horn_call7.ogg"),
]
const STEP:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/goat_horn/goat_step1.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_step2.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_step3.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_step4.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_step5.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_step6.ogg"),
]
const PRE_RAM:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/goat_horn/goat_pre_ram1.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_pre_ram2.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_pre_ram3.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_pre_ram4.ogg"),
]
const IMPACT:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/goat_horn/goat_impact1.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_impact2.ogg"),
	preload("res://audio/characters/我的世界/goat_horn/goat_impact3.ogg"),
]
const KIND_CALL:int = 0
const KIND_STEP:int = 1
const KIND_PRE_RAM:int = 2
const KIND_IMPACT:int = 3
# 号角声需要全场可闻（原版 item.goat_horn.sound.* 衰减距离 256 格）；山羊群脚步较轻，避免盖过战斗声。
const OPTIONS:Array[Dictionary] = [
	{"event":"item.goat_horn.sound","volume_db":-2.0,"max_distance":6000.0,"attenuation":0.3,"priority":true,"keep_after_source":true},
	{"event":"entity.goat.step","volume_db":-15.0},
	{"event":"entity.goat.prepare_ram","volume_db":-7.0},
	{"event":"entity.goat.ram_impact","volume_db":-3.0,"priority":true,"keep_after_source":true},
]

static func streams(kind:int) -> Array[AudioStream]:
	match kind:
		KIND_CALL: return CALL
		KIND_STEP: return STEP
		KIND_PRE_RAM: return PRE_RAM
		KIND_IMPACT: return IMPACT
	return []

static func variant_count(kind:int) -> int:
	return streams(kind).size()

static func length(kind:int,index:int) -> float:
	var list:Array[AudioStream] = streams(kind)
	if list.is_empty(): return 0.0
	return list[posmod(index,list.size())].get_length()

static func play(context:Node,kind:int,index:int,point:Vector2) -> Dictionary:
	var list:Array[AudioStream] = streams(kind)
	if list.is_empty() or kind < 0 or kind >= OPTIONS.size(): return {}
	var spec:Dictionary = OPTIONS[kind]
	var options:Dictionary = spec.duplicate()
	var event:String = str(options.get("event",""))
	options.erase("event")
	if kind == KIND_CALL: event += "." + str(posmod(index,list.size()))
	options["metadata"] = {"mc_sound_event":event}
	return NATIVE.queue_stream(context,list[posmod(index,list.size())],point,options)
