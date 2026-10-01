extends Node

@onready var Sfx: Node = $Sfx
@export var sfx_default_settings:Dictionary = {}

# 手动录像只抓 GameplayRecord。UI 声音仍然送到 Master 给玩家听，
# 但不会经过 GameplayRecord，所以不会进入录像。
const GAMEPLAY_BUS:StringName = &"GameplayRecord"
const UI_BUS:StringName = &"UI"
const UI_SFX_NAMES:Dictionary = {
	"ButtonDown1": true,
	"ButtonUpMouseOut": true,
	"MouseEnterButton1": true,
	"Slider1": true,
	"StopGame": true,
	"StopTextClick": true,
}

# V415：统一“游戏时间 -> 音频时间”。Godot 的 Engine.time_scale 本身不会改变音频，
# 因此游戏声使用 AudioServer.playback_speed_scale 跟随有效时间倍率；UI 声音通过
# player.pitch_scale 反向补偿，最终仍保持 1x 的 UI 播放速度。
const AUDIO_EPSILON:float = 0.000001
const META_UI_LOGICAL_PITCH:StringName = &"_audios_ui_logical_pitch"
const META_UI_LAST_APPLIED_PITCH:StringName = &"_audios_ui_last_applied_pitch"

var _tracked_audio_players:Dictionary = {}
var _forced_pause_states:Dictionary = {}
var _explicit_gameplay_paused:bool = false
var _last_requested_game_time_scale:float = 1.0
var _active_audio_speed_scale:float = 1.0

# V432 性能：create_new_audio 的动态播放器改为“池化 + 同源并发上限”。
# 100 人混战时每物理帧会有 80+ 次碰撞/命中声请求，旧实现每次 new AudioStreamPlayer + queue_free，
# 树里同时挂着 1100+ 个播放器，音频线程混音 50~70 ms/帧、主线程每帧遍历追踪表也随之膨胀。
# 同一音源同时叠加超过几层后人耳已无法分辨，因此：同源最多 MAX_VOICES_PER_SOURCE 路，
# 全局动态播放器最多 MAX_DYNAMIC_VOICES 路；饱和时优先替换同源最旧播放，而不是丢掉新命中。
# 同帧超额请求仍合并，避免密集碰撞反复重启解码器；播放完的播放器回收复用。
const MAX_VOICES_PER_SOURCE:int = 6
const MAX_DYNAMIC_VOICES:int = 64
const META_DYNAMIC_SOURCE_KEY:StringName = &"_audios_dynamic_source_key"
const META_DYNAMIC_START_FRAME:StringName = &"_audios_dynamic_start_frame"
var _dynamic_free_players:Array[AudioStreamPlayer] = []
var _dynamic_active_count:int = 0
var _dynamic_active_by_source:Dictionary = {}
var _dynamic_active_players:Dictionary = {}
var _dynamic_last_start_frame_by_source:Dictionary = {}
var _dynamic_reclaim_frame:int = -1

const PREWARMED_PLAYBACK_STREAM = preload("res://classes/prewarmed_audio_stream.gd")

# Called during character preparation, never in the attack loop. Only unused
# playback objects are recycled; simultaneous voices and held references survive.
func prewarm_sfx_playbacks(sfx_name:String,count:int = 128) -> void:
	var player:AudioStreamPlayer = Sfx.get_node_or_null(sfx_name) as AudioStreamPlayer
	if player == null or player.stream == null:
		return
	if player.stream.get_script() == PREWARMED_PLAYBACK_STREAM:
		return
	# Restrict reuse to the engine decoder validated by test_audio_pool.gd.
	if not player.stream is AudioStreamOggVorbis:
		return
	var cached:AudioStream = PREWARMED_PLAYBACK_STREAM.new()
	cached.configure(player.stream,clampi(count,1,256))
	player.stream = cached

func _enter_tree() -> void:
	# Audios 自己必须在 SceneTree.paused 时继续运行，否则无法保持 UI 声音正常、
	# 也无法管理那些 process_mode=ALWAYS 的游戏播放器。
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_bus(GAMEPLAY_BUS)
	_ensure_audio_bus(UI_BUS)

	# Sfx 现在既可以直接放 AudioStreamPlayer，也可以放“音频组”Node。
	# 递归缓存默认参数，同时把战斗声音与 UI 声音分流。
	sfx_default_settings.clear()
	_cache_sfx_defaults(Sfx)

	# 场景里直接放置的 AudioStreamPlayer2D/3D（例如角色自己的声音）也属于游戏声。
	# 后续动态加入的节点同样自动分流；已经显式指定非 Master 总线的节点保持原设置。
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
	call_deferred("_route_existing_scene_audio")
	call_deferred("_sync_audio_clock", true)

func _process(_delta:float) -> void:
	# 兜底读取 Engine.time_scale，保证未来即使某个系统绕过 Game.set_speed() 直接改时间，
	# 游戏声音仍会在下一帧同步。
	var engine_scale:float = maxf(Engine.time_scale,0.0)
	# Game 声明过的引擎倍率（声音可与画面不同，例如命中顿挫）不算“绕过”。
	if _expected_engine_time_scale >= 0.0 and is_equal_approx(engine_scale,_expected_engine_time_scale):
		pass
	elif not is_equal_approx(engine_scale,_last_requested_game_time_scale):
		_last_requested_game_time_scale = engine_scale
		_expected_engine_time_scale = -1.0
	_sync_audio_clock(false)

# Game._apply_time_scale_overrides() 会在改变 Engine.time_scale 的同一帧调用这里，
# 避免倍速滑条改变后要等一帧音频才追上。
var _expected_engine_time_scale:float = -1.0

func set_game_time_scale(value:float,engine_scale:float = -1.0) -> void:
	_last_requested_game_time_scale = maxf(value,0.0)
	_expected_engine_time_scale = engine_scale if engine_scale >= 0.0 else _last_requested_game_time_scale
	_sync_audio_clock(true)

# Game.stop_game() 在设置 SceneTree.paused=true 之前调用；continue_game() 在解除暂停后调用。
# 这样可以在引擎自动改变 AudioStreamPlayer.stream_paused 之前保存原状态，恢复时不会把
# 原本就手动暂停的 BGM/循环声错误唤醒。
func set_gameplay_paused(value:bool) -> void:
	_explicit_gameplay_paused = value
	_sync_audio_clock(true)

func _ensure_audio_bus(bus_name:StringName) -> int:
	var index:int = AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(index,bus_name)
	AudioServer.set_bus_send(index,&"Master")
	return index

func _is_audio_player(node:Node) -> bool:
	return (
		node is AudioStreamPlayer
		or node is AudioStreamPlayer2D
		or node is AudioStreamPlayer3D
	)

func _track_audio_player(node:Node) -> void:
	if node == null or not is_instance_valid(node) or not _is_audio_player(node):
		return
	_tracked_audio_players[node.get_instance_id()] = true

func _cache_sfx_defaults(node:Node) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer:
			var sfx := child as AudioStreamPlayer
			sfx.bus = UI_BUS if _is_ui_sfx_player(sfx) else GAMEPLAY_BUS
			if sfx.bus == UI_BUS:
				sfx.process_mode = Node.PROCESS_MODE_ALWAYS
			_track_audio_player(sfx)
			sfx_default_settings[_settings_key(sfx)] = {
				volume = sfx.volume_db,
				pitch = sfx.pitch_scale,
			}
			if sfx.bus == UI_BUS:
				_register_ui_logical_pitch(sfx,sfx.pitch_scale)
		else:
			_cache_sfx_defaults(child)

func _is_ui_sfx_player(sfx:AudioStreamPlayer) -> bool:
	if sfx == null or Sfx == null:
		return false
	var path:String = String(Sfx.get_path_to(sfx))
	var top_name:String = path.get_slice("/",0)
	return UI_SFX_NAMES.has(top_name)

func _on_tree_node_added(node:Node) -> void:
	# Native node type cannot change: non-audio nodes were always no-ops below.
	# Do not enqueue a deferred routing call for every projectile/UI/after-image node.
	if not _is_audio_player(node):
		return
	# Keep routing deferred so scripts can still set bus during instantiation.
	# An instance ID avoids an invalid Node argument when a short-lived player is freed.
	call_deferred("_route_audio_node_by_id",node.get_instance_id())

func _route_audio_node_by_id(id:int) -> void:
	if not is_instance_id_valid(id):
		return
	var node:Variant = instance_from_id(id)
	if node is Node:
		_route_audio_node(node as Node)

func _route_existing_scene_audio() -> void:
	var root := get_tree().root
	if root == null:
		return
	_route_audio_subtree(root)
	_sync_audio_clock(true)

func _route_audio_subtree(node:Node) -> void:
	_route_audio_node(node)
	for child in node.get_children():
		_route_audio_subtree(child)

func _route_audio_node(node:Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not _is_audio_player(node):
		return

	_track_audio_player(node)

	# Audios/Sfx 的源由 _cache_sfx_defaults 精确按名称分流。
	if Sfx != null and Sfx.is_ancestor_of(node):
		if StringName(node.get("bus")) == UI_BUS:
			node.process_mode = Node.PROCESS_MODE_ALWAYS
			_ensure_ui_pitch_tracking(node)
		return

	# duplicate() 出来的 UI 音效已经继承 UI 总线，不要二次改写。
	var current_bus:StringName = StringName(node.get("bus"))
	if current_bus == UI_BUS:
		node.process_mode = Node.PROCESS_MODE_ALWAYS
		_ensure_ui_pitch_tracking(node)
		return
	if current_bus != &"Master":
		return

	var parent := node.get_parent()
	while parent != null:
		if parent is CanvasLayer:
			node.set("bus",UI_BUS)
			node.process_mode = Node.PROCESS_MODE_ALWAYS
			_register_ui_logical_pitch(node,float(node.get("pitch_scale")))
			return
		parent = parent.get_parent()

	node.set("bus",GAMEPLAY_BUS)

func _settings_key(sfx:AudioStreamPlayer) -> String:
	return String(Sfx.get_path_to(sfx))

func _get_default_settings(sfx:AudioStreamPlayer) -> Dictionary:
	var key := _settings_key(sfx)
	if not sfx_default_settings.has(key):
		sfx_default_settings[key] = {
			volume = sfx.volume_db,
			pitch = _get_logical_pitch(sfx),
		}
	return sfx_default_settings[key]

func _play_sfx_player(source:AudioStreamPlayer,params:Dictionary = {},random:bool = false,create_new_audio:bool = false) -> void:
	if source == null or source.stream == null:
		return

	var defaults := _get_default_settings(source)
	var sfx:AudioStreamPlayer = source

	if create_new_audio:
		sfx = _acquire_dynamic_player(source)
		if sfx == null:
			return

	if "volume" in params:
		sfx.volume_db = float(params.volume)
	else:
		sfx.volume_db = float(defaults.volume)

	var logical_pitch:float = float(params.pitch) if "pitch" in params else float(defaults.pitch)

	# 与原 play_sfx 完全相同：random 参数仍然负责少量音高/音量抖动。
	if random:
		logical_pitch *= randf_range(0.9,1.1)
		sfx.volume_db *= randf_range(0.9,1.1)
	# 调用方给的相对音高，叠在默认/指定音高之上。
	if "pitch_mul" in params:
		logical_pitch *= maxf(float(params.pitch_mul),0.01)

	_set_logical_pitch(sfx,logical_pitch)

	if "position" in params:
		sfx.play(float(params.position))
	else:
		sfx.play()


# 不 duplicate 正在充当“音效模板”的 Player。动态播放器只共享 AudioStream 资源；
# 这样每次碰撞拥有完全独立的 playback voice，不受源 Player 的 playing / max_polyphony 影响。
func _acquire_dynamic_player(source:AudioStreamPlayer) -> AudioStreamPlayer:
	var source_key:String = _settings_key(source)
	var frame:int = Engine.get_process_frames()
	var per_source:int = int(_dynamic_active_by_source.get(source_key,0))
	if per_source >= MAX_VOICES_PER_SOURCE or _dynamic_active_count >= MAX_DYNAMIC_VOICES:
		# stop() / stream_paused 不会发 finished；被外部停掉的播放器在这里补回收，再重新判断上限。
		_reclaim_stopped_dynamic_players()
		per_source = int(_dynamic_active_by_source.get(source_key,0))
		if per_source >= MAX_VOICES_PER_SOURCE or _dynamic_active_count >= MAX_DYNAMIC_VOICES:
			# 长音效（含安静的尾段）也一直占用名额。直接拒绝会使持续射击在前六声之后
			# 成段无声。跨帧的新命中应替换旧播放；同帧已有起音则无需再次抢占。
			if int(_dynamic_last_start_frame_by_source.get(source_key,-1)) == frame:
				return null
			var oldest:AudioStreamPlayer = _find_dynamic_voice_to_replace(source_key,per_source >= MAX_VOICES_PER_SOURCE)
			if oldest == null:
				return null
			oldest.stop()
			_release_dynamic_player(oldest)
			per_source = int(_dynamic_active_by_source.get(source_key,0))
	var sfx:AudioStreamPlayer = null
	while not _dynamic_free_players.is_empty() and sfx == null:
		var candidate:AudioStreamPlayer = _dynamic_free_players.pop_back()
		if candidate != null and is_instance_valid(candidate) and not candidate.playing:
			sfx = candidate
	if sfx == null:
		sfx = AudioStreamPlayer.new()
		sfx.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(sfx)
		_track_audio_player(sfx)
		sfx.finished.connect(_release_dynamic_player.bind(sfx))
	sfx.stream = source.stream
	sfx.bus = source.bus
	sfx.mix_target = source.mix_target
	sfx.stream_paused = false
	sfx.set_meta(META_DYNAMIC_SOURCE_KEY,source_key)
	sfx.set_meta(META_DYNAMIC_START_FRAME,frame)
	_dynamic_active_by_source[source_key] = per_source + 1
	_dynamic_active_count += 1
	_dynamic_active_players[sfx.get_instance_id()] = source_key
	_dynamic_last_start_frame_by_source[source_key] = frame
	return sfx


func _find_dynamic_voice_to_replace(source_key:String,same_source_only:bool) -> AudioStreamPlayer:
	# Dictionary 保持插入顺序；回收会 erase、复用会重新插入，因此最先遇到的是最旧播放。
	# 全局满时也优先替换同源，尽量不打断其它种类音效。暂停或本帧刚起音的播放不抢占。
	var frame:int = Engine.get_process_frames()
	var oldest_other:AudioStreamPlayer = null
	for raw_id:Variant in _dynamic_active_players:
		var same_source:bool = str(_dynamic_active_players[raw_id]) == source_key
		if same_source_only and not same_source:
			continue
		var id:int = int(raw_id)
		if not is_instance_id_valid(id):
			continue
		var player:AudioStreamPlayer = instance_from_id(id) as AudioStreamPlayer
		if player == null or player.stream_paused:
			continue
		if int(player.get_meta(META_DYNAMIC_START_FRAME,-1)) == frame:
			continue
		if same_source:
			return player
		if oldest_other == null:
			oldest_other = player
	return oldest_other


func _release_dynamic_player(sfx:AudioStreamPlayer) -> void:
	if sfx == null or not is_instance_valid(sfx):
		return
	if not sfx.has_meta(META_DYNAMIC_SOURCE_KEY):
		return
	var source_key:String = str(sfx.get_meta(META_DYNAMIC_SOURCE_KEY))
	sfx.remove_meta(META_DYNAMIC_SOURCE_KEY)
	sfx.remove_meta(META_DYNAMIC_START_FRAME)
	_dynamic_active_players.erase(sfx.get_instance_id())
	var remaining:int = int(_dynamic_active_by_source.get(source_key,0)) - 1
	if remaining <= 0:
		_dynamic_active_by_source.erase(source_key)
		_dynamic_last_start_frame_by_source.erase(source_key)
	else:
		_dynamic_active_by_source[source_key] = remaining
	_dynamic_active_count = maxi(_dynamic_active_count - 1,0)
	_dynamic_free_players.append(sfx)


func _reclaim_stopped_dynamic_players() -> void:
	# 上限命中时每个 process 帧最多扫一次活动表（不是全部子节点）；被 stop() 的播放器在此回收。
	var frame:int = Engine.get_process_frames()
	if frame == _dynamic_reclaim_frame:
		return
	_dynamic_reclaim_frame = frame
	for raw_id:Variant in _dynamic_active_players.keys():
		var id:int = int(raw_id)
		if not is_instance_id_valid(id):
			# 被外部 free 的播放器：只修正计数，不可再访问对象。
			var lost_key:String = str(_dynamic_active_players[raw_id])
			_dynamic_active_players.erase(raw_id)
			var remaining:int = int(_dynamic_active_by_source.get(lost_key,0)) - 1
			if remaining <= 0:
				_dynamic_active_by_source.erase(lost_key)
				_dynamic_last_start_frame_by_source.erase(lost_key)
			else:
				_dynamic_active_by_source[lost_key] = remaining
			_dynamic_active_count = maxi(_dynamic_active_count - 1,0)
			continue
		var player:AudioStreamPlayer = instance_from_id(id) as AudioStreamPlayer
		if player == null:
			continue
		# 暂停时 playing 也可能为 false，必须显式排除，不能把待恢复的播放当成空闲。
		if not player.playing and not player.stream_paused:
			_release_dynamic_player(player)


## 测试/诊断：当前动态播放器占用情况。
func get_dynamic_voice_stats() -> Dictionary:
	return {
		"active": _dynamic_active_count,
		"free": _dynamic_free_players.size(),
		"by_source": _dynamic_active_by_source.duplicate(),
	}
func _find_numbered_sfx_variant(base_name:String) -> AudioStreamPlayer:
	# 兼容项目原有的逻辑音效名：Buff / Debuff / Defense / Bee / KakaHurt / KakaSkill。
	# 场景实际保存的是 Buff1..N 等播放器；旧调用传组名时应随机选择一个编号变体，
	# 而不是每次都刷 “Sfx/<name> 不存在” 警告。
	if base_name.is_empty() or Sfx == null:
		return null
	var choices:Array[AudioStreamPlayer] = []
	for child in Sfx.get_children():
		if not child is AudioStreamPlayer:
			continue
		var child_name:String = String(child.name)
		if not child_name.begins_with(base_name):
			continue
		var suffix:String = child_name.substr(base_name.length())
		if suffix.is_empty() or not suffix.is_valid_int():
			continue
		var player := child as AudioStreamPlayer
		if player.stream != null:
			choices.append(player)
	if choices.is_empty():
		return null
	return choices.pick_random()

@rpc("any_peer","call_local")
func play_sfx(Name:String,params:Dictionary = {},random:bool = false,create_new_audio:bool = false) -> void:
	var source := Sfx.get_node_or_null(Name) as AudioStreamPlayer
	if source == null:
		source = _find_numbered_sfx_variant(Name)
	if source == null:
		push_warning("Audios.play_sfx: Sfx/%s 不是 AudioStreamPlayer，也没有找到 %s1..N 编号音效组。" % [Name,Name])
		return
	_play_sfx_player(source,params,random,create_new_audio)

# 从 Sfx 下指定的 Node 中随机挑选一个 AudioStreamPlayer 播放。
# 调用方式与 play_sfx 基本一致：
# Audios.play_sfx_from_node("脚步",{},true)
# 会从 Sfx/脚步 的直接子 AudioStreamPlayer 中随机选一个。
@rpc("any_peer","call_local")
func play_sfx_from_node(Name:String,params:Dictionary = {},random:bool = false,create_new_audio:bool = false) -> void:
	var container := Sfx.get_node_or_null(Name)
	if container == null:
		push_warning("Audios.play_sfx_from_node: 找不到 Sfx/%s。" % Name)
		return

	var choices:Array[AudioStreamPlayer] = []
	for child in container.get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			if player.stream != null:
				choices.append(player)

	if choices.is_empty():
		push_warning("Audios.play_sfx_from_node: Sfx/%s 内没有可播放的 AudioStreamPlayer。" % Name)
		return

	var source:AudioStreamPlayer = choices.pick_random()
	_play_sfx_player(source,params,random,create_new_audio)

# 碰撞反馈专用：调用方会先在本机直接播放，再用这个 RPC 只发给远端。
# 这样不会依赖 call_local RPC 的本地回环，也不会在调用端重复播放两次。
@rpc("any_peer","call_remote","unreliable")
func play_sfx_from_node_remote(Name:String,params:Dictionary = {},random:bool = false,create_new_audio:bool = true) -> void:
	play_sfx_from_node(Name,params,random,create_new_audio)

# -----------------------------------------------------------------------------
# V415 全局音频时钟
# -----------------------------------------------------------------------------
func _is_ui_audio_player(player:Node) -> bool:
	if player == null or not is_instance_valid(player) or not _is_audio_player(player):
		return false
	return StringName(player.get("bus")) == UI_BUS

func _register_ui_logical_pitch(player:Node,logical_pitch:float) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.set_meta(META_UI_LOGICAL_PITCH,maxf(logical_pitch,AUDIO_EPSILON))
	var desired:float = maxf(logical_pitch,AUDIO_EPSILON) / maxf(_active_audio_speed_scale,AUDIO_EPSILON)
	player.set("pitch_scale",desired)
	player.set_meta(META_UI_LAST_APPLIED_PITCH,desired)

func _ensure_ui_pitch_tracking(player:Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_meta(META_UI_LOGICAL_PITCH):
		_register_ui_logical_pitch(player,float(player.get("pitch_scale")))

func _get_logical_pitch(player:Node) -> float:
	if player == null or not is_instance_valid(player):
		return 1.0
	if _is_ui_audio_player(player) and player.has_meta(META_UI_LOGICAL_PITCH):
		return maxf(float(player.get_meta(META_UI_LOGICAL_PITCH)),AUDIO_EPSILON)
	return maxf(float(player.get("pitch_scale")),AUDIO_EPSILON)

func _set_logical_pitch(player:Node,logical_pitch:float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var safe_pitch:float = maxf(logical_pitch,AUDIO_EPSILON)
	if _is_ui_audio_player(player):
		_register_ui_logical_pitch(player,safe_pitch)
	else:
		# 如果节点之前曾在 UI 总线，现在改回游戏总线，要先清除 UI 的反补偿状态。
		player.remove_meta(META_UI_LOGICAL_PITCH)
		player.remove_meta(META_UI_LAST_APPLIED_PITCH)
		player.set("pitch_scale",safe_pitch)

func _sync_ui_player_pitch(player:Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	_ensure_ui_pitch_tracking(player)
	var logical_pitch:float = maxf(float(player.get_meta(META_UI_LOGICAL_PITCH)),AUDIO_EPSILON)
	var current_pitch:float = maxf(float(player.get("pitch_scale")),AUDIO_EPSILON)
	var last_applied:float = current_pitch
	if player.has_meta(META_UI_LAST_APPLIED_PITCH):
		last_applied = maxf(float(player.get_meta(META_UI_LAST_APPLIED_PITCH)),AUDIO_EPSILON)

	# 其它 UI 脚本若直接写 pitch_scale，把那次写入视为新的“逻辑音高”，
	# 再除以全局播放倍率；Audios.play_sfx 自身则会直接更新 logical meta，不会走错这一步。
	if not is_equal_approx(current_pitch,last_applied):
		logical_pitch = current_pitch
		player.set_meta(META_UI_LOGICAL_PITCH,logical_pitch)

	var desired_pitch:float = logical_pitch / maxf(_active_audio_speed_scale,AUDIO_EPSILON)
	if not is_equal_approx(current_pitch,desired_pitch):
		player.set("pitch_scale",desired_pitch)
	player.set_meta(META_UI_LAST_APPLIED_PITCH,desired_pitch)

func _restore_player_from_ui_compensation(player:Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_meta(META_UI_LOGICAL_PITCH):
		return
	var logical_pitch:float = maxf(float(player.get_meta(META_UI_LOGICAL_PITCH)),AUDIO_EPSILON)
	player.set("pitch_scale",logical_pitch)
	player.remove_meta(META_UI_LOGICAL_PITCH)
	player.remove_meta(META_UI_LAST_APPLIED_PITCH)

func _gameplay_pause_requested() -> bool:
	var tree := get_tree()
	if tree == null:
		return _explicit_gameplay_paused or _last_requested_game_time_scale <= AUDIO_EPSILON
	return (
		_explicit_gameplay_paused
		or tree.paused
		or _last_requested_game_time_scale <= AUDIO_EPSILON
	)

func _get_tracked_audio_player(raw_id:Variant) -> Node:
	# V416：追踪表只保存 Object instance_id，不再保存 Node 强引用。
	# Godot 的普通 Object 引用在对象 free 后不会自动变成 null；对这种悬空 Variant
	# 直接执行 `as Node` 会触发 "Trying to cast a freed object"。因此必须先用
	# is_instance_id_valid() 验证 ID，再通过 instance_from_id() 取回活对象，最后才类型转换。
	var id:int = int(raw_id)
	if id <= 0 or not is_instance_id_valid(id):
		return null
	var object_ref:Variant = instance_from_id(id)
	if not is_instance_valid(object_ref) or not (object_ref is Node):
		return null
	var player:Node = object_ref as Node
	if not _is_audio_player(player):
		return null
	return player

func _force_pause_gameplay_player(player:Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var id:int = player.get_instance_id()
	if not _forced_pause_states.has(id):
		# 这里只保存原 stream_paused 状态，不保存 player 引用，避免临时音效 queue_free 后
		# 在暂停恢复阶段留下 freed Object Variant。
		_forced_pause_states[id] = bool(player.get("stream_paused"))
	player.set("stream_paused",true)

func _restore_forced_pause_states() -> void:
	for raw_id in _forced_pause_states.keys():
		var player:Node = _get_tracked_audio_player(raw_id)
		if player != null:
			player.set("stream_paused",bool(_forced_pause_states[raw_id]))
	_forced_pause_states.clear()

func _cleanup_dead_audio_tracking() -> void:
	for raw_id in _tracked_audio_players.keys():
		var id:int = int(raw_id)
		if id <= 0 or not is_instance_id_valid(id):
			_tracked_audio_players.erase(raw_id)
			_forced_pause_states.erase(raw_id)

func _sync_audio_clock(_force:bool = false) -> void:
	_cleanup_dead_audio_tracking()

	var requested_scale:float = maxf(_last_requested_game_time_scale,0.0)
	if requested_scale > AUDIO_EPSILON:
		_active_audio_speed_scale = requested_scale
		# AudioServer.playback_speed_scale 是真正改变音频播放速率的全局时钟。
		# UI 会在下面按 1/scale 反补偿，因此只有非 UI 游戏声听起来跟随游戏时间。
		if _force or not is_equal_approx(AudioServer.playback_speed_scale,_active_audio_speed_scale):
			AudioServer.playback_speed_scale = _active_audio_speed_scale

	var pause_gameplay:bool = _gameplay_pause_requested()
	if not pause_gameplay and not _forced_pause_states.is_empty():
		_restore_forced_pause_states()

	for raw_id in _tracked_audio_players.keys():
		var player:Node = _get_tracked_audio_player(raw_id)
		if player == null:
			_tracked_audio_players.erase(raw_id)
			_forced_pause_states.erase(raw_id)
			continue

		if _is_ui_audio_player(player):
			# UI 永远允许在暂停菜单工作，并用反向 pitch 抵消全局 playback_speed_scale。
			player.process_mode = Node.PROCESS_MODE_ALWAYS
			if _forced_pause_states.has(raw_id):
				player.set("stream_paused",bool(_forced_pause_states[raw_id]))
				_forced_pause_states.erase(raw_id)
			_sync_ui_player_pitch(player)
			continue

		_restore_player_from_ui_compensation(player)
		if pause_gameplay:
			# Game.stop_game() 会在 tree.paused=true 之前显式调用，因此正常暂停流程能保存真实原状态。
			# 对其它来源的 tree.pause，只有仍可处理的 ALWAYS 节点需要手动强停；普通可暂停节点由引擎自身暂停。
			var should_force:bool = _explicit_gameplay_paused or not get_tree().paused or player.can_process()
			if should_force:
				_force_pause_gameplay_player(player)
