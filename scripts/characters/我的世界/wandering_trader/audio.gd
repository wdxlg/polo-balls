extends RefCounted
## 流浪商人 / 羊驼 / 缰绳 / 墙体进出 sounds: original Minecraft Java 1.21 index objects,
## bytes unchanged (audio/characters/流浪商人/SOURCE.json). Own module on purpose: the shared
## mc_native_audio EVENTS table is not edited. Keys map 1:1 to vanilla sound events (NAMES).
const EVENTS:Dictionary = {
	&"trader_ambient":[preload("res://audio/characters/流浪商人/trader_idle1.ogg"),preload("res://audio/characters/流浪商人/trader_idle2.ogg"),preload("res://audio/characters/流浪商人/trader_idle3.ogg"),preload("res://audio/characters/流浪商人/trader_idle4.ogg"),preload("res://audio/characters/流浪商人/trader_idle5.ogg")],
	&"trader_hurt":[preload("res://audio/characters/流浪商人/trader_hurt1.ogg"),preload("res://audio/characters/流浪商人/trader_hurt2.ogg"),preload("res://audio/characters/流浪商人/trader_hurt3.ogg"),preload("res://audio/characters/流浪商人/trader_hurt4.ogg")],
	&"trader_death":[preload("res://audio/characters/流浪商人/trader_death.ogg")],
	&"trader_disappeared":[preload("res://audio/characters/流浪商人/trader_disappeared1.ogg"),preload("res://audio/characters/流浪商人/trader_disappeared2.ogg")],
	&"trader_reappeared":[preload("res://audio/characters/流浪商人/trader_reappeared1.ogg"),preload("res://audio/characters/流浪商人/trader_reappeared2.ogg")],
	&"drink_milk":[preload("res://audio/characters/流浪商人/trader_drink_milk1.ogg"),preload("res://audio/characters/流浪商人/trader_drink_milk2.ogg"),preload("res://audio/characters/流浪商人/trader_drink_milk3.ogg"),preload("res://audio/characters/流浪商人/trader_drink_milk4.ogg"),preload("res://audio/characters/流浪商人/trader_drink_milk5.ogg")],
	&"drink_potion":[preload("res://audio/characters/流浪商人/trader_drink_potion.ogg"),preload("res://audio/characters/流浪商人/generic_drink.ogg")],
	&"llama_ambient":[preload("res://audio/characters/流浪商人/llama_idle1.ogg"),preload("res://audio/characters/流浪商人/llama_idle2.ogg"),preload("res://audio/characters/流浪商人/llama_idle3.ogg"),preload("res://audio/characters/流浪商人/llama_idle4.ogg"),preload("res://audio/characters/流浪商人/llama_idle5.ogg")],
	&"llama_hurt":[preload("res://audio/characters/流浪商人/llama_hurt1.ogg"),preload("res://audio/characters/流浪商人/llama_hurt2.ogg"),preload("res://audio/characters/流浪商人/llama_hurt3.ogg")],
	&"llama_death":[preload("res://audio/characters/流浪商人/llama_death1.ogg"),preload("res://audio/characters/流浪商人/llama_death2.ogg")],
	&"llama_spit":[preload("res://audio/characters/流浪商人/llama_spit1.ogg"),preload("res://audio/characters/流浪商人/llama_spit2.ogg")],
	&"llama_step":[preload("res://audio/characters/流浪商人/llama_step1.ogg"),preload("res://audio/characters/流浪商人/llama_step2.ogg"),preload("res://audio/characters/流浪商人/llama_step3.ogg"),preload("res://audio/characters/流浪商人/llama_step4.ogg"),preload("res://audio/characters/流浪商人/llama_step5.ogg")],
	&"llama_angry":[preload("res://audio/characters/流浪商人/llama_angry1.ogg")],
	&"leash_break":[preload("res://audio/characters/流浪商人/leash_break1.ogg"),preload("res://audio/characters/流浪商人/leash_break2.ogg"),preload("res://audio/characters/流浪商人/leash_break3.ogg")],
	&"leash_place":[preload("res://audio/characters/流浪商人/leash_place1.ogg"),preload("res://audio/characters/流浪商人/leash_place2.ogg"),preload("res://audio/characters/流浪商人/leash_place3.ogg")],
	&"stone_break":[preload("res://audio/characters/流浪商人/stone_break1.ogg"),preload("res://audio/characters/流浪商人/stone_break2.ogg"),preload("res://audio/characters/流浪商人/stone_break3.ogg"),preload("res://audio/characters/流浪商人/stone_break4.ogg")],
	&"stone_hit":[preload("res://audio/characters/流浪商人/stone_hit1.ogg"),preload("res://audio/characters/流浪商人/stone_hit2.ogg"),preload("res://audio/characters/流浪商人/stone_hit3.ogg"),preload("res://audio/characters/流浪商人/stone_hit4.ogg"),preload("res://audio/characters/流浪商人/stone_hit5.ogg"),preload("res://audio/characters/流浪商人/stone_hit6.ogg")],
}
const NAMES:Dictionary = {
	&"trader_ambient":"entity.wandering_trader.ambient",
	&"trader_hurt":"entity.wandering_trader.hurt",
	&"trader_death":"entity.wandering_trader.death",
	&"trader_disappeared":"entity.wandering_trader.disappeared",
	&"trader_reappeared":"entity.wandering_trader.reappeared",
	&"drink_milk":"entity.wandering_trader.drink_milk",
	&"drink_potion":"entity.wandering_trader.drink_potion",
	&"llama_ambient":"entity.llama.ambient",
	&"llama_hurt":"entity.llama.hurt",
	&"llama_death":"entity.llama.death",
	&"llama_spit":"entity.llama.spit",
	&"llama_step":"entity.llama.step",
	&"llama_angry":"entity.llama.angry",
	&"leash_break":"entity.leash_knot.break",
	&"leash_place":"entity.leash_knot.place",
	&"stone_break":"block.stone.break",
	&"stone_hit":"block.stone.hit",
}
const GAIN:Dictionary = {
	&"trader_ambient":-9.0,
	&"trader_hurt":-4.0,
	&"trader_death":-2.0,
	&"trader_disappeared":-3.0,
	&"trader_reappeared":-3.0,
	&"drink_milk":-4.0,
	&"drink_potion":-4.0,
	&"llama_ambient":-11.0,
	&"llama_hurt":-5.0,
	&"llama_death":-4.0,
	&"llama_spit":-3.0,
	&"llama_step":-15.0,
	&"llama_angry":-6.0,
	&"leash_break":-2.0,
	&"leash_place":-3.0,
	&"stone_break":-3.0,
	&"stone_hit":-7.0,
}
const PRIORITY:Array[StringName] = [&"trader_death",&"llama_death",&"trader_disappeared",&"trader_reappeared",&"leash_break",&"leash_place",&"drink_milk",&"drink_potion"]
const GROUP:StringName = &"MCWanderingTraderAudio"
const MAX_VOICES:int = 14
static var _rng := RandomNumberGenerator.new()
static var _seeded:bool = false

static func variant(event:StringName) -> int:
	if not EVENTS.has(event): return -1
	if not _seeded:
		_rng.randomize()
		_seeded = true
	return _rng.randi_range(0,(EVENTS[event] as Array).size()-1)

## Plays one vanilla variant at a world point. Returns the player (or null when skipped).
static func play(context:Node,event:StringName,point:Vector2,volume_offset:float = 0.0,pitch:float = 1.0,index:int = -1) -> AudioStreamPlayer2D:
	if not EVENTS.has(event) or not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree:SceneTree = context.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var streams:Array = EVENTS[event]
	if index < 0 or index >= streams.size(): index = variant(event)
	var voices:int = tree.get_nodes_in_group(GROUP).size()
	if voices >= MAX_VOICES and not PRIORITY.has(event): return null
	var player := AudioStreamPlayer2D.new()
	player.name = "WTAudio_%s" % String(event)
	player.stream = streams[index]
	player.volume_db = float(GAIN.get(event,-4.0)) + volume_offset
	player.pitch_scale = maxf(pitch,0.05)
	player.max_distance = 1700.0
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	player.add_to_group(GROUP)
	player.set_meta(&"mc_sound_event",String(NAMES.get(event,"")))
	player.set_meta(&"wt_event",event)
	player.set_meta(&"wt_variant",index)
	player.set_meta(&"wt_source",context.get_instance_id())
	parent.add_child(player)
	player.global_position = point
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	# Headless/muted buses may never emit finished: free after the clip length anyway.
	var length:float = (player.stream as AudioStream).get_length() if player.stream != null else 1.0
	tree.create_timer(length/player.pitch_scale + 0.6,false).timeout.connect(player.queue_free)
	player.play()
	return player
