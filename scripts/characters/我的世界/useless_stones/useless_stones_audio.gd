extends RefCounted
## 三废石的原版 Java 石质音效（来源与 SHA1 见 audio/characters/我的世界/useless_stones/SOURCE.json）。
## 变体由调用方给出：权威端挑选后随 RPC 下发，各端按同一序号播放。
## 原版石质音组：受击/敲击 = step 音、音调 ×0.5；破坏/放置 = dig 音、音调 ×0.8；
## 投掷沿用雪球投掷声（random/bow，音量 0.5、音调约 0.33–0.5）。
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const DIG:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/useless_stones/stone_dig1.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_dig2.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_dig3.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_dig4.ogg"),
]
const STEP:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/useless_stones/stone_step1.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_step2.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_step3.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_step4.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_step5.ogg"),
	preload("res://audio/characters/我的世界/useless_stones/stone_step6.ogg"),
]
const THROW:Array[AudioStream] = [preload("res://audio/characters/我的世界/useless_stones/throw.ogg")]
enum {THROW_SOUND, HIT_SOUND, BREAK_SOUND, PLACE_SOUND, STEP_SOUND}
const EVENTS:Array[String] = ["entity.snowball.throw","block.stone.hit","block.stone.break","block.stone.place","block.stone.step"]
const BASE:Array[Dictionary] = [
	{"volume_db":-6.0,"pitch":0.42},
	{"volume_db":-3.0,"pitch":0.5},
	{"volume_db":0.0,"pitch":0.8,"priority":true,"keep_after_source":true},
	{"volume_db":-4.0,"pitch":0.8},
	{"volume_db":-12.0,"pitch":1.0},
]

static func streams(kind:int) -> Array[AudioStream]:
	match kind:
		THROW_SOUND: return THROW
		BREAK_SOUND, PLACE_SOUND: return DIG
	return STEP

static func variant_count(kind:int) -> int: return streams(kind).size()

## pitch_scale 乘在原版基准音调上；extra 可覆盖 volume_db、keep_after_source 等队列参数。
static func play(context:Node,kind:int,index:int,point:Vector2,pitch_scale:float = 1.0,extra:Dictionary = {}) -> Dictionary:
	if kind < 0 or kind >= BASE.size(): return {}
	var list:Array[AudioStream] = streams(kind)
	if list.is_empty(): return {}
	var options:Dictionary = BASE[kind].duplicate()
	options.pitch = float(options.pitch)*maxf(pitch_scale,0.05)
	options.merge(extra,true)
	options["metadata"] = {"mc_sound_event":EVENTS[kind]}
	return NATIVE.queue_stream(context,list[posmod(index,list.size())],point,options)
