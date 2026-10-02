extends RefCounted

# 下载自用户指定的 MCSounds 网站；对应 API 与 SHA1 见 MC_NATIVE_SOUNDS.json。
const EVENTS:Dictionary = {
	"entity.evoker.cast_spell": [{"stream":preload("res://audio/characters/唤魔者/evoker.cast_spell_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.cast_spell_2.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.prepare_attack": [{"stream":preload("res://audio/characters/唤魔者/evoker.prepare_attack_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.prepare_attack_2.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.prepare_summon": [{"stream":preload("res://audio/characters/唤魔者/evoker.prepare_summon_1.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.hurt": [{"stream":preload("res://audio/characters/唤魔者/evoker.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.hurt_2.ogg"),"volume":1,"pitch":1}],
	"entity.evoker.death": [{"stream":preload("res://audio/characters/唤魔者/evoker.death_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/唤魔者/evoker.death_2.ogg"),"volume":1,"pitch":1}],
	# Local Minecraft client asset index; see audio/characters/唤魔者/SOURCE.json.
	"item.totem.use": [{"stream":preload("res://audio/characters/唤魔者/totem.use.ogg"),"volume":1,"pitch":1}],
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
	"entity.spider.ambient": [{"stream":preload("res://audio/characters/蜘蛛/spider.ambient_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.ambient_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.ambient_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.ambient_4.ogg"),"volume":1,"pitch":1}],
	"entity.spider.hurt": [{"stream":preload("res://audio/characters/蜘蛛/spider.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.hurt_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.hurt_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.hurt_4.ogg"),"volume":1,"pitch":1}],
	"entity.spider.death": [{"stream":preload("res://audio/characters/蜘蛛/spider.death_1.ogg"),"volume":1,"pitch":1}],
	"entity.spider.lunge": [{"stream":preload("res://audio/characters/蜘蛛/spider.step_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.step_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.step_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/spider.step_4.ogg"),"volume":1,"pitch":1}],
	"entity.spider_web.cast": [{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_4.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_5.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_6.ogg"),"volume":1,"pitch":1}],
	"entity.spider_web.hit": [{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_4.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_5.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_6.ogg"),"volume":1,"pitch":1}],
	"entity.spider_web.patch": [{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_4.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_5.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/蜘蛛/cobweb.step_6.ogg"),"volume":1,"pitch":1}],
	"entity.drowned.ambient": [{"stream":preload("res://audio/characters/溺尸/drowned.ambient_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/drowned.ambient_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/drowned.ambient_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/drowned.ambient_4.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/drowned.ambient_5.ogg"),"volume":1,"pitch":1}],
	"entity.drowned.hurt": [{"stream":preload("res://audio/characters/溺尸/drowned.hurt_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/drowned.hurt_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/drowned.hurt_3.ogg"),"volume":1,"pitch":1}],
	"entity.drowned.death": [{"stream":preload("res://audio/characters/溺尸/drowned.death_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/drowned.death_2.ogg"),"volume":1,"pitch":1}],
	"entity.drowned.splash": [{"stream":preload("res://audio/characters/溺尸/paddle.water_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/paddle.water_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/paddle.water_3.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/paddle.water_4.ogg"),"volume":1,"pitch":1}],
	"entity.drowned.throw": [{"stream":preload("res://audio/characters/溺尸/trident.throw_1.ogg"),"volume":1,"pitch":1}],
	"entity.drowned.riptide": [{"stream":preload("res://audio/characters/溺尸/riptide.thunder_1.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/riptide.thunder_2.ogg"),"volume":1,"pitch":1},{"stream":preload("res://audio/characters/溺尸/riptide.thunder_3.ogg"),"volume":1,"pitch":1}],
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
	return _create_player(tree.current_scene,record["stream"],position,{
		"volume_db":clampf(volume_db+linear_to_db(maxf(float(record["volume"]),0.01)),-24.0,2.0),
		"pitch":float(record["pitch"]),"metadata":{"mc_sound_event":event,"mc_sound_priority":priority}})

# Reusable opt-in queue for native clips triggered during _ready, destruction,
# or one-shot effect teardown. A receipt is not an orphan AudioStreamPlayer.
# The entire allocation/attachment/play operation runs after scene child locks.
const QUEUED_META:StringName = &"mc_native_sfx_pending"
static func queue_stream(context:Node,stream:AudioStream,point:Vector2,options:Dictionary = {}) -> Dictionary:
	if not is_instance_valid(context) or not context.is_inside_tree() or stream == null: return {}
	var tree:SceneTree = context.get_tree()
	var scene:Node = tree.current_scene
	if not is_instance_valid(scene) or scene.is_queued_for_deletion() or tree.paused or Game.now_stop_state: return {}
	var pending:int = int(scene.get_meta(QUEUED_META,0))
	if not bool(options.get("priority",false)) and tree.get_nodes_in_group("MCNativeSFX").size()+pending >= 24: return {}
	var parent:Node = options.get("audio_parent",scene)
	if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.get_tree()!=tree or parent.is_queued_for_deletion(): return {}
	var parameters:Dictionary = options.duplicate(true)
	parameters.erase("audio_parent") # Deferred requests hold only a weak scene/parent reference.
	var ticket:Dictionary = {"state":"queued","stream":stream,"player":null,"started_msec":-1,"pitch":maxf(float(options.get("pitch",1.0)),0.01)}
	scene.set_meta(QUEUED_META,pending+1)
	_start_queued.call_deferred(weakref(tree),weakref(scene),weakref(context),weakref(parent),point,parameters,ticket)
	return ticket

static func _start_queued(tree_ref:WeakRef,scene_ref:WeakRef,source_ref:WeakRef,parent_ref:WeakRef,point:Vector2,options:Dictionary,ticket:Dictionary) -> void:
	var tree:SceneTree = tree_ref.get_ref() as SceneTree
	var scene:Node = scene_ref.get_ref() as Node
	if is_instance_valid(scene) and scene.has_meta(QUEUED_META):
		var left:int = maxi(int(scene.get_meta(QUEUED_META))-1,0)
		if left == 0: scene.remove_meta(QUEUED_META)
		else: scene.set_meta(QUEUED_META,left)
	ticket.state = "cancelled"
	if tree == null or not is_instance_valid(scene) or scene.is_queued_for_deletion(): return
	if not scene.is_inside_tree() or scene.get_tree() != tree or tree.current_scene != scene or tree.paused or Game.now_stop_state: return
	if bool(ticket.get("cancel_requested",false)): return
	var parent:Node = parent_ref.get_ref() as Node
	if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.get_tree()!=tree or parent.is_queued_for_deletion(): return
	var source:Variant = source_ref.get_ref()
	if not bool(options.get("keep_after_source",false)):
		if not is_instance_valid(source) or source.is_queued_for_deletion() or not source.is_inside_tree(): return
	var active:Array[Node] = tree.get_nodes_in_group("MCNativeSFX")
	if active.size() >= 24:
		if not bool(options.get("priority",false)): return
		# Actual damage/death is not crowded out by a trail's material chatter.
		var replace:Node = active[0]
		for candidate:Node in active:
			if not bool(candidate.get_meta("mc_sound_priority",false)):
				replace = candidate
				break
		replace.call("stop")
		replace.remove_from_group("MCNativeSFX")
		replace.queue_free()
	if ticket.has("volume_db_override"): options["volume_db"] = float(ticket.volume_db_override)
	var player:AudioStreamPlayer2D = _create_player(parent,ticket.stream,point,options)
	ticket.player = weakref(player)
	ticket.started_msec = Time.get_ticks_msec()
	ticket.state = "playing"

static func channel_busy(ticket:Dictionary) -> bool:
	if ticket.is_empty() or bool(ticket.get("cancel_requested",false)) or ticket.get("state","") == "cancelled": return false
	if ticket.get("state","") == "queued": return true
	var ref:WeakRef = ticket.get("player") as WeakRef
	var player:AudioStreamPlayer2D = ref.get_ref() as AudioStreamPlayer2D if ref != null else null
	if is_instance_valid(player) and player.playing: return true
	var duration:float = (ticket.stream as AudioStream).get_length()/maxf(float(ticket.get("pitch",1.0))*AudioServer.playback_speed_scale,0.01)
	return Time.get_ticks_msec()-int(ticket.started_msec) < ceili(duration*1000.0)

static func _create_player(scene:Node,stream:AudioStream,point:Vector2,options:Dictionary) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = float(options.get("volume_db",0.0))
	player.pitch_scale = maxf(float(options.get("pitch",1.0)),0.01)
	player.max_distance = float(options.get("max_distance",1700.0))
	player.attenuation = float(options.get("attenuation",0.65))
	var bus_name:StringName = StringName(options.get("bus",&"GameplayRecord"))
	if AudioServer.get_bus_index(bus_name) >= 0: player.bus = bus_name
	elif AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	var metadata:Dictionary = options.get("metadata",{})
	for key:Variant in metadata: player.set_meta(key,metadata[key])
	player.set_meta("mc_sound_priority",bool(options.get("priority",metadata.get("mc_sound_priority",false))))
	scene.add_child(player)
	player.global_position = point
	player.add_to_group("MCNativeSFX")
	player.add_to_group("BattleTransient")
	for group:Variant in options.get("groups",[]): player.add_to_group(StringName(str(group)))
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player
