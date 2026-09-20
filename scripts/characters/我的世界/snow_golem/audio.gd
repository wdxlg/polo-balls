extends RefCounted
const NATIVE = preload("res://scripts/characters/我的世界/snow_golem/native_sounds.gd")
const PHASES = preload("res://scripts/characters/我的世界/snow_golem/phase_sounds.gd")
# freeze 用原版冻伤音（冰晶脆响，和雪球击中的 block.snow.hit / 受击音区分得开）；
# 之前的 block.glass.place 实际是 dig/stone 石头闷响，和同一帧的击中音混在一起几乎听不出来。
# ice_hit：冻住期间被外来攻击打到（cold.gd 检测生命/护盾真实下降），节流由 cold.gd 负责。
const PHASE_EVENTS:Dictionary = {"freeze":["entity.player.hurt_freeze"],"ice_break":["block.glass.break"],"ice_hit":["mc_snow.ice_hit"],"mini_birth":["block.snow.place","block.wood.place"]}
# 相位转换音是一次性的关键反馈，抬到 play() 允许的 +2 dB 上限，压过同帧的击中音。
const PHASE_GAIN_DB:float = 2.0
const MC_HITS = preload("res://scripts/characters/我的世界/new5/audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
static var _last:Dictionary = {}
static func play(context:Node,event:String,point:Vector2,volume_db:float = -5.0,force_priority:bool = false,unthrottled:bool = false) -> AudioStreamPlayer2D:
	if not is_instance_valid(context) or not context.is_inside_tree() or (not NATIVE.EVENTS.has(event) and not PHASES.EVENTS.has(event)): return null
	var tree:SceneTree = context.get_tree()
	if tree.current_scene == null or tree.paused: return null
	var priority:bool = force_priority or event.ends_with(".death") or event.ends_with(".hurt") or event.ends_with(".shear")
	if Game.now_stop_state and not event.ends_with(".death"): return null
	var key:String = event+":"+str(context.get_instance_id()) if priority else event
	var now:int = Time.get_ticks_msec()
	if not unthrottled and now-int(_last.get(key,-10000)) < 60: return null
	if _last.size() > 256: _last.clear()
	_last[key] = now
	var active:Array[Node] = tree.get_nodes_in_group("MCNativeSFX")
	if active.size() >= 24:
		if not priority: return null
		var victim:Node = active[0]
		victim.call("stop")
		victim.remove_from_group("MCNativeSFX")
		victim.queue_free()
	var records:Array = NATIVE.EVENTS[event] if NATIVE.EVENTS.has(event) else PHASES.EVENTS[event]
	var record:Dictionary = records.pick_random()
	var player := AudioStreamPlayer2D.new()
	player.stream = record.stream
	player.pitch_scale = maxf(0.1,float(record.pitch))
	player.volume_db = clampf(volume_db+linear_to_db(maxf(float(record.volume),0.01)),-20.0,2.0)
	player.max_distance = 1700.0
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	tree.current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("MCNativeSFX")
	player.add_to_group("MCSnowSound")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sound_event",event)
	player.set_meta("mc_sound_priority",priority)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player

static func play_phase(context:Node,phase:String,point:Vector2) -> Array[AudioStreamPlayer2D]:
	var result:Array[AudioStreamPlayer2D] = []
	if not PHASE_EVENTS.has(phase): return result
	for event:String in PHASE_EVENTS[phase]:
		# These are gameplay transitions, not a per-frame ambient loop.
		var player:AudioStreamPlayer2D = play(context,event,point,PHASE_GAIN_DB,true,true)
		if is_instance_valid(player):
			player.set_meta("mc_snow_phase",phase)
			result.append(player)
	return result

static func impact_event(actual:float) -> String:
	return "entity.player.attack.crit" if actual > 50.0 else "entity.player.hurt"

static func impact_gain(actual:float) -> float:
	return HIT_GAIN.damage_gain(actual)

static func play_impact(context:Node,actual:float,point:Vector2,include_snow:bool = true) -> AudioStreamPlayer2D:
	# The original snow contact is no longer reduced by -9 dB. It is independent
	# per impact, so another snowball in the same frame cannot suppress it.
	if include_snow:
		var snow:AudioStreamPlayer2D = play(context,"block.snow.hit",point,0.0,true,true)
		if is_instance_valid(snow):
			snow.set_meta("mc_snow_impact_layer","snow")
			snow.set_meta("mc_snow_damage",actual)
	if actual <= 0.0: return null
	# Reuse the project's verified original hurt/critical OGGs and its existing
	# zero-dB-floor, monotonically increasing, safely bounded hit-gain policy.
	var player:AudioStreamPlayer2D = MC_HITS.play(context,impact_event(actual),point,impact_gain(actual),false,true,true,true)
	if is_instance_valid(player):
		player.add_to_group("MCSnowSound")
		player.set_meta("mc_snow_impact_layer","victim")
		player.set_meta("mc_snow_damage",actual)
	return player
