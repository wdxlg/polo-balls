extends RefCounted
# Original Minecraft sounds retrieved through the requested MCSounds API.
const EVENTS:Dictionary = {
	"entity.breeze.deflect": [{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.breeze.deflect_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.breeze.deflect_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.breeze.deflect_3.ogg"),"volume":1,"pitch":1}],
	"entity.bat.ambient": [{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.ambient_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.ambient_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.ambient_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.ambient_4.ogg"),"volume":1,"pitch":1}],
	"entity.bat.hurt": [{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.hurt_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.hurt_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.hurt_4.ogg"),"volume":1,"pitch":1}],
	"entity.bat.death": [{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.death_1.ogg"),"volume":1,"pitch":1}],
	"entity.bat.takeoff": [{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.bat.takeoff_1.ogg"),"volume":1,"pitch":1}],
	"entity.generic.eat": [{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.generic.eat_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.generic.eat_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/我的世界/蝙蝠/entity.generic.eat_3.ogg"),"volume":1,"pitch":1}],
}
static var _last:Dictionary = {}
static func play(context:Node,event:String,position:Vector2,volume_db:float = -4.0,allow_stopped:bool = false,priority:bool = false) -> AudioStreamPlayer2D:
	if not is_instance_valid(context) or not context.is_inside_tree() or not EVENTS.has(event): return null
	var tree:SceneTree = context.get_tree()
	if tree.current_scene == null or tree.paused or (Game.now_stop_state and not allow_stopped): return null
	var now:int = Time.get_ticks_msec()
	var last_time:int = int(context.get_meta("mc_priority_sound_msec",-10000)) if priority else int(_last.get(event,-10000))
	if now-last_time < 75: return null
	var active:Array[Node] = tree.get_nodes_in_group("MCNativeSFX")
	if active.size() >= 24:
		if not priority: return null
		# 关键格挡音优先于已有普通声，仍保持最多24声部。
		var victim:Node = active[0]
		for candidate:Node in active:
			if not candidate.get_meta("mc_sound_priority",false):
				victim = candidate
				if str(candidate.get_meta("mc_sound_event","")).ends_with(".ambient"): break
		victim.call("stop")
		victim.remove_from_group("MCNativeSFX")
		victim.queue_free()
	if priority: context.set_meta("mc_priority_sound_msec",now)
	else: _last[event] = now
	var record:Dictionary = EVENTS[event].pick_random()
	var player := AudioStreamPlayer2D.new()
	player.stream = record["stream"]
	player.volume_db = clampf(volume_db+linear_to_db(maxf(float(record["volume"]),0.01)),-24.0,2.0)
	player.pitch_scale = float(record["pitch"])
	player.max_distance = 1700.0
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	tree.current_scene.add_child(player)
	player.global_position = position
	player.add_to_group("MCNativeSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sound_event",event)
	player.set_meta("mc_sound_priority",priority)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player
