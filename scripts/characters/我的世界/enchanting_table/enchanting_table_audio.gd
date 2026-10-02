extends RefCounted
## 附魔台的原版 Java 音效（来源与 SHA1 见 audio/characters/我的世界/enchanting_table/SOURCE.json）。
## 变体由权威端挑选后随 RPC 下发，各端按同一序号播放。原版参数：
## 附魔完成 block.enchantment_table.use 音量 1、音调 0.9–1.1；翻书 item.book.page_turn、
## 合书 item.book.put 音量 1、音调 1。翻书/合书原版文件很轻且各变体响度差很多，按 VARIANT_GAIN_DB
## 把均方根响度拉到附魔声附近，战斗中听得见。符文出书用原版紫水晶共鸣 block.amethyst_block.resonate
## （同样很轻，逐变体补增益；附魔台按间隔节流，不是每发都响）。
## 方块本身的受击/破坏/放置/脚步是石质音组（复用三废石）。
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
const RUNE_STREAMS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/enchanting_table/amethyst_resonate1.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/amethyst_resonate2.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/amethyst_resonate3.ogg"),
	preload("res://audio/characters/我的世界/enchanting_table/amethyst_resonate4.ogg"),
]
enum {ENCHANT, PAGE_TURN, BOOK_PUT, RUNE}
const EVENTS:Array[String] = ["block.enchantment_table.use","item.book.page_turn","item.book.put","block.amethyst_block.resonate"]
const BASE:Array[Dictionary] = [
	{"volume_db":0.0,"pitch":1.0,"keep_after_source":true},
	{"volume_db":0.0,"pitch":1.0},
	{"volume_db":0.0,"pitch":1.0},
	{"volume_db":0.0,"pitch":1.0},
]
## 逐变体补偿（dB）：翻书/合书拉到均方根约 -24 dBFS（峰值不过 -0.5），符文共鸣拉到约 -34 dBFS 作为轻点缀。
const VARIANT_GAIN_DB:Array = [
	[0.0,0.0,0.0],
	[6.4,15.4,14.5],
	[9.3,9.9],
	[9.0,8.5,7.0,10.0],
]

static func streams(kind:int) -> Array[AudioStream]:
	match kind:
		ENCHANT: return ENCHANT_STREAMS
		PAGE_TURN: return PAGE_TURN_STREAMS
		RUNE: return RUNE_STREAMS
	return BOOK_PUT_STREAMS

static func play(context:Node,kind:int,index:int,point:Vector2,pitch_scale:float = 1.0,extra:Dictionary = {}) -> Dictionary:
	if kind < 0 or kind >= BASE.size(): return {}
	var list:Array[AudioStream] = streams(kind)
	var options:Dictionary = BASE[kind].duplicate()
	var variant:int = posmod(index,list.size())
	var gains:Array = VARIANT_GAIN_DB[kind]
	options.volume_db = float(options.volume_db) + (float(gains[variant]) if variant < gains.size() else 0.0)
	options.pitch = float(options.pitch)*maxf(pitch_scale,0.05)
	options.merge(extra,true)
	options["metadata"] = {"mc_sound_event":EVENTS[kind]}
	return NATIVE.queue_stream(context,list[variant],point,options)
