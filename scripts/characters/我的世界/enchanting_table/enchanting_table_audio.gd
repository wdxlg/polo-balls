extends RefCounted
## 附魔台的原版 Java 音效（来源与 SHA1 见 audio/characters/我的世界/enchanting_table/SOURCE.json）。
## 变体由权威端挑选后随 RPC 下发，各端按同一序号播放。原版参数：
## 附魔完成 block.enchantment_table.use 音量 1、音调 0.9–1.1；翻书 item.book.page_turn、
## 合书 item.book.put 音量 1、音调 1。方块本身的受击/破坏/放置/脚步是石质音组（复用三废石）。
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const ENCHANT_STREAMS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/enchanting_table/enchant1.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/enchant2.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/enchant3.ogg"),
]
const PAGE_TURN_STREAMS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/enchanting_table/book_page_turn1.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/book_page_turn2.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/book_page_turn3.ogg"),
]
const BOOK_PUT_STREAMS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/enchanting_table/book_put1.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/book_put2.ogg"),
]
enum {ENCHANT, PAGE_TURN, BOOK_PUT}
const EVENTS:Array[String] = ["block.enchantment_table.use","item.book.page_turn","item.book.put"]
const BASE:Array[Dictionary] = [
	{"volume_db":0.0,"pitch":1.0,"keep_after_source":true},
	{"volume_db":-3.0,"pitch":1.0},
	{"volume_db":-3.0,"pitch":1.0},
]

static func streams(kind:int) -> Array[AudioStream]:
	match kind:
		ENCHANT: return ENCHANT_STREAMS
		PAGE_TURN: return PAGE_TURN_STREAMS
	return BOOK_PUT_STREAMS

static func play(context:Node,kind:int,index:int,point:Vector2,pitch_scale:float = 1.0,extra:Dictionary = {}) -> Dictionary:
	if kind < 0 or kind >= BASE.size(): return {}
	var list:Array[AudioStream] = streams(kind)
	var options:Dictionary = BASE[kind].duplicate()
	options.pitch = float(options.pitch)*maxf(pitch_scale,0.05)
	options.merge(extra,true)
	options["metadata"] = {"mc_sound_event":EVENTS[kind]}
	return NATIVE.queue_stream(context,list[posmod(index,list.size())],point,options)
