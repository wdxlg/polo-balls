extends RefCounted

# 下载自用户指定的 MCSounds 网站；对应 API 与 SHA1 见 MC_NATIVE_SOUNDS.json。
const EVENTS:Dictionary = {
	"entity.evoker.cast_spell": [{"stream":preload("res://audio/characters/唤魔者/evoker.cast_spell_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.cast_spell_2.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.prepare_attack": [{"stream":preload("res://audio/characters/唤魔者/evoker.prepare_attack_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.prepare_attack_2.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.prepare_summon": [{"stream":preload("res://audio/characters/唤魔者/evoker.prepare_summon_1.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.hurt": [{"stream":preload("res://audio/characters/唤魔者/evoker.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.hurt_2.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.death": [{"stream":preload("res://audio/characters/唤魔者/evoker.death_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.death_2.ogg"),"volume":1,"pitch":1}],
	"entity.evoker_fangs.attack": [{"stream":preload("res://audio/characters/唤魔者/evoker_fangs.attack_1.ogg"),"volume":1,"pitch":1}],
	"entity.vex.charge": [{"stream":preload("res://audio/characters/唤魔者/vex.charge_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/vex.charge_2.ogg"),"volume":1,"pitch":1}],
	"entity.vex.hurt": [{"stream":preload("res://audio/characters/唤魔者/vex.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/vex.hurt_2.ogg"),"volume":1,"pitch":1}],
	"entity.vex.death": [{"stream":preload("res://audio/characters/唤魔者/vex.death_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/vex.death_2.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.open": [{"stream":preload("res://audio/characters/潜影贝/shulker.open_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.open_2.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.close": [{"stream":preload("res://audio/characters/潜影贝/shulker.close_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.close_2.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.shoot": [{"stream":preload("res://audio/characters/潜影贝/shulker.shoot_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.shoot_2.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.hurt": [{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_4.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.hurt_closed": [{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_closed_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_closed_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_closed_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_closed_4.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.hurt_closed_5.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.death": [{"stream":preload("res://audio/characters/潜影贝/shulker.death_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.death_2.ogg"),"volume":1,"pitch":1}],
	"entity.shulker_bullet.hit": [{"stream":preload("res://audio/characters/潜影贝/shulker_bullet.hit_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker_bullet.hit_2.ogg"),"volume":1,"pitch":1}],
	"entity.shulker_bullet.hurt": [{"stream":preload("res://audio/characters/潜影贝/shulker_bullet.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker_bullet.hurt_2.ogg"),"volume":1,"pitch":1}],
	"entity.enderman.teleport": [{"stream":preload("res://audio/characters/末影人/enderman.teleport_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.teleport_2.ogg"),"volume":1,"pitch":1}],
	"entity.enderman.stare": [{"stream":preload("res://audio/characters/末影人/enderman.stare_1.ogg"),"volume":1,"pitch":1}],
	"entity.enderman.scream": [{"stream":preload("res://audio/characters/末影人/enderman.scream_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.scream_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.scream_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.scream_4.ogg"),"volume":1,"pitch":1}],
	"entity.enderman.hurt": [{"stream":preload("res://audio/characters/末影人/enderman.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.hurt_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.hurt_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.hurt_4.ogg"),"volume":1,"pitch":1}],
	"entity.enderman.death": [{"stream":preload("res://audio/characters/末影人/enderman.death_1.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.ambient": [{"stream":preload("res://audio/characters/唤魔者/evoker.ambient_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.ambient_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.ambient_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.ambient_4.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.celebrate": [{"stream":preload("res://audio/characters/唤魔者/evoker.celebrate_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.celebrate_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.celebrate_3.ogg"),"volume":1,"pitch":1}],
	"entity.vex.ambient": [{"stream":preload("res://audio/characters/唤魔者/vex.ambient_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/vex.ambient_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/vex.ambient_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/vex.ambient_4.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.ambient": [{"stream":preload("res://audio/characters/潜影贝/shulker.ambient_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.ambient_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.ambient_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.ambient_4.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.ambient_5.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.ambient_6.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.ambient_7.ogg"),"volume":1,"pitch":1}],
	"entity.shulker.teleport": [{"stream":preload("res://audio/characters/潜影贝/shulker.teleport_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/潜影贝/shulker.teleport_2.ogg"),"volume":1,"pitch":1}],
	"entity.enderman.ambient": [{"stream":preload("res://audio/characters/末影人/enderman.ambient_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.ambient_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.ambient_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.ambient_4.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/末影人/enderman.ambient_5.ogg"),"volume":1,"pitch":1}],
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
