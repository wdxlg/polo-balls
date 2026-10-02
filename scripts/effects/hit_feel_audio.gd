extends RefCounted
## 命中音分层：瞬态“咔哒”给每次攻击命中加脆感，重击再叠低频闷响；重击/击杀时压低其他游戏声。
## 同一帧的多次命中合成一份分层音，按命中数量略微加大音量，而不是叠出一串。
## 两个声音在运行时程序化合成（无外部素材），只生成一次后缓存。
## 主体受击音仍由原有路径（MC 统一受击音 / Hit_Audio）播放，这里只补层。

const SAMPLE_RATE:int = 44100
const CLICK_SECONDS:float = 0.03
const THUMP_SECONDS:float = 0.26
# 同帧合并：每多一个目标 +1.5 dB，最多 +4.5 dB。
const MERGE_STEP_DB:float = 1.5
const MERGE_MAX_DB:float = 4.5
# 与 MC 受击音的“暴击”分界一致：实际伤害 > 50 才算重击。
const HEAVY_DAMAGE:float = 50.0
const THUMP_MIN_DAMAGE:float = 30.0
const MAX_LIVE_LAYERS:int = 8
const GROUP:StringName = &"HitFeelLayerSFX"
const GAMEPLAY_BUS:StringName = &"GameplayRecord"
const ACCENT_BUS:StringName = &"ImpactAccent"

static var _click_stream:AudioStreamWAV = null
static var _thump_stream:AudioStreamWAV = null
static var _pending_count:int = 0
static var _pending_damage:float = 0.0
static var _pending_point:Vector2 = Vector2.ZERO
static var _pending_kill:bool = false
static var _pending_target:WeakRef = null
static var _flush_queued:bool = false
static var _rng := RandomNumberGenerator.new()
static var _rng_seeded:bool = false
# 测试/调试读取：最近一次实际播放的分层。
static var last_layers:Dictionary = {}


static func click_stream() -> AudioStreamWAV:
	if _click_stream == null:
		_click_stream = _make_click()
	return _click_stream


static func thump_stream() -> AudioStreamWAV:
	if _thump_stream == null:
		_thump_stream = _make_thump()
	return _thump_stream


static func merge_bonus_db(count:int) -> float:
	return minf(MERGE_STEP_DB * float(maxi(count - 1,0)),MERGE_MAX_DB)


static func click_volume_db(damage:float,count:int) -> float:
	var weight:float = clampf(damage / 80.0,0.0,1.0)
	return lerpf(-15.0,-7.0,sqrt(weight)) + merge_bonus_db(count)


static func wants_thump(damage:float,killing:bool) -> bool:
	return killing or damage >= THUMP_MIN_DAMAGE


static func thump_volume_db(damage:float,count:int,killing:bool) -> float:
	var weight:float = clampf((damage - THUMP_MIN_DAMAGE) / 120.0,0.0,1.0)
	return lerpf(-9.0,-1.0,weight) + (2.0 if killing else 0.0) + merge_bonus_db(count) * 0.5


static func wants_duck(damage:float,killing:bool) -> bool:
	return killing or damage > HEAVY_DAMAGE


static func duck_depth_db(damage:float,killing:bool) -> float:
	var depth:float = lerpf(3.0,6.0,clampf((damage - HEAVY_DAMAGE) / 150.0,0.0,1.0))
	return maxf(depth,5.0) if killing else depth


## 已确认的攻击命中（含远端复现）调用；同帧请求在帧末合并成一次播放。
static func request(target:Node2D,damage:float,point:Vector2,killing:bool = false) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree() or not is_finite(damage) or damage <= 0.0:
		return
	var tree:SceneTree = target.get_tree()
	if tree.paused or _now_stopped(tree):
		return
	_pending_count += 1
	_pending_kill = _pending_kill or killing
	if _pending_target == null or damage > _pending_damage:
		_pending_damage = damage
		_pending_point = point
		_pending_target = weakref(target)
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


static func _now_stopped(tree:SceneTree) -> bool:
	var game:Node = tree.root.get_node_or_null(^"Game")
	return game != null and bool(game.get("now_stop_state"))


static func _flush() -> void:
	var count:int = _pending_count
	var damage:float = _pending_damage
	var point:Vector2 = _pending_point
	var killing:bool = _pending_kill
	var target:Node2D = _pending_target.get_ref() as Node2D if _pending_target != null else null
	_flush_queued = false
	_pending_count = 0
	_pending_damage = 0.0
	_pending_kill = false
	_pending_target = null
	if count <= 0 or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var tree:SceneTree = target.get_tree()
	if tree.paused or _now_stopped(tree):
		return
	var parent:Node = _audio_parent(target)
	if parent == null:
		return
	if not _rng_seeded:
		_rng.randomize()
		_rng_seeded = true
	var heavy:bool = wants_duck(damage,killing)
	var bus:StringName = ACCENT_BUS if heavy and AudioServer.get_bus_index(ACCENT_BUS) >= 0 else GAMEPLAY_BUS
	var layers:Dictionary = {"count":count,"damage":damage,"killing":killing,"bus":bus}
	var click:AudioStreamPlayer2D = _play(parent,click_stream(),point,click_volume_db(damage,count),_rng.randf_range(0.94,1.08),bus)
	layers["click_db"] = click_volume_db(damage,count) if click != null else NAN
	if wants_thump(damage,killing):
		var thump:AudioStreamPlayer2D = _play(parent,thump_stream(),point,thump_volume_db(damage,count,killing),_rng.randf_range(0.96,1.04),bus)
		layers["thump_db"] = thump_volume_db(damage,count,killing) if thump != null else NAN
	if heavy:
		var audios:Node = tree.root.get_node_or_null(^"Audios")
		if audios != null and audios.has_method("duck_for_impact"):
			audios.call("duck_for_impact",duck_depth_db(damage,killing),0.06,0.32)
			layers["duck_db"] = duck_depth_db(damage,killing)
	last_layers = layers


static func _audio_parent(target:Node2D) -> Node:
	var parent:Node = target.get_tree().current_scene
	if parent is Node2D and target.get_world_2d() != (parent as Node2D).get_world_2d():
		parent = target
		while parent.get_parent() is Node2D and (parent.get_parent() as Node2D).get_world_2d() == target.get_world_2d():
			parent = parent.get_parent()
	if parent == null or not parent.is_inside_tree() or parent.is_queued_for_deletion():
		return null
	return parent


static func _play(parent:Node,stream:AudioStream,point:Vector2,volume_db:float,pitch:float,bus:StringName) -> AudioStreamPlayer2D:
	if parent.get_tree().get_nodes_in_group(GROUP).size() >= MAX_LIVE_LAYERS:
		return null
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch,0.01)
	player.max_distance = 1700.0
	player.attenuation = 0.65
	player.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
	parent.add_child(player)
	player.global_position = point
	player.add_to_group(GROUP)
	player.add_to_group(&"BattleTransient")
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player


static func _to_wav(samples:PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index:int in range(samples.size()):
		data.encode_s16(index * 2,int(round(clampf(samples[index],-1.0,1.0) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


# 高通白噪声 + 2.3 kHz 短促音，4~6 ms 指数衰减：只提供“打中了”的起音脆感。
static func _make_click() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51C11C
	var count:int = int(CLICK_SECONDS * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var previous_noise:float = 0.0
	var high_pass:float = 0.0
	for index:int in range(count):
		var t:float = float(index) / float(SAMPLE_RATE)
		var noise:float = rng.randf_range(-1.0,1.0)
		high_pass = 0.72 * (high_pass + noise - previous_noise)
		previous_noise = noise
		var value:float = 0.55 * high_pass * exp(-t / 0.0045) + 0.35 * sin(TAU * 2300.0 * t) * exp(-t / 0.006)
		samples[index] = value * minf(float(count - index) / 40.0,1.0)
	return _to_wav(samples)


# 125 Hz 快速下滑到 42 Hz 的软饱和正弦，3 ms 起音、75 ms 衰减：重击的“闷响”。
static func _make_thump() -> AudioStreamWAV:
	var count:int = int(THUMP_SECONDS * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase:float = 0.0
	var drive:float = 1.6
	for index:int in range(count):
		var t:float = float(index) / float(SAMPLE_RATE)
		var frequency:float = 42.0 + (125.0 - 42.0) * exp(-t / 0.045)
		phase += TAU * frequency / float(SAMPLE_RATE)
		var envelope:float = (1.0 - exp(-t / 0.003)) * exp(-t / 0.075)
		var tail:float = minf(float(count - index) / (0.01 * SAMPLE_RATE),1.0)
		samples[index] = tanh(drive * sin(phase)) / tanh(drive) * envelope * tail * 0.9
	return _to_wav(samples)
