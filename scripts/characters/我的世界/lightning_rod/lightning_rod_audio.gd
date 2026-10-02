extends RefCounted
## 避雷针的原版 Java 音效（来源与 SHA1 见 audio/characters/我的世界/lightning_rod/SOURCE.json）。
## 雷声与雷击爆裂直接复用苦力怕目录里同一批原版文件（ambient/weather/thunder*、random/explode*）。
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const THUNDER:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/苦力怕/thunder1.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/thunder2.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/thunder3.ogg"),
]
const IMPACT:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/苦力怕/explode1.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode2.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode3.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode4.ogg"),
]
const RAIN:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/lightning_rod/rain1.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/rain2.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/rain3.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/rain4.ogg"),
]
const HIT:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/lightning_rod/copper_step1.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_step2.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_step3.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_step4.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_step5.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_step6.ogg"),
]
const BREAK:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/lightning_rod/copper_break1.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_break2.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_break3.ogg"),
	preload("res://audio/characters/我的世界/lightning_rod/copper_break4.ogg"),
]
const FIZZ:Array[AudioStream] = [preload("res://audio/characters/我的世界/lightning_rod/fizz.ogg")]
enum Kind { THUNDER, IMPACT, RAIN, HIT, BREAK, FIZZ }
const EVENTS:Array[String] = ["entity.lightning_bolt.thunder","entity.lightning_bolt.impact","weather.rain","block.copper.hit","block.copper.break","block.redstone_torch.burnout"]


static func streams(kind:int) -> Array[AudioStream]:
	match kind:
		Kind.THUNDER: return THUNDER
		Kind.IMPACT: return IMPACT
		Kind.RAIN: return RAIN
		Kind.HIT: return HIT
		Kind.BREAK: return BREAK
		Kind.FIZZ: return FIZZ
	return []


## 按序号播放一个变体；index 为负时随机挑选。雷声与雷圈需要全场可闻。
static func play(context:Node,kind:int,point:Vector2,volume_db:float,index:int = -1,pitch:float = 1.0) -> Dictionary:
	var list:Array[AudioStream] = streams(kind)
	if list.is_empty(): return {}
	var pick:int = randi() % list.size() if index < 0 else posmod(index,list.size())
	var options:Dictionary = {"volume_db":volume_db,"pitch":pitch,"metadata":{"mc_sound_event":EVENTS[kind]}}
	if kind == Kind.THUNDER:
		options["max_distance"] = 6000.0
		options["attenuation"] = 0.3
		options["priority"] = true
		options["keep_after_source"] = true
	elif kind == Kind.IMPACT or kind == Kind.BREAK:
		options["priority"] = true
		options["keep_after_source"] = true
	return NATIVE.queue_stream(context,list[pick],point,options)
