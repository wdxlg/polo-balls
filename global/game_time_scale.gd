extends RefCounted
## 可叠加的世界流速覆写与慢动作着色
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node

# 普通对局每个渲染帧最多补的物理步数（见 _apply_time_scale_overrides）。
const NORMAL_MAX_PHYSICS_STEPS_PER_FRAME:int = 2


func _init(game: Node) -> void:
	_game = game


var _base_game_time_scale:float = 1.0
var _development_time_multiplier:float = 1.0

var _time_scale_overrides:Dictionary = {}

var _time_scale_override_tints:Dictionary = {}

var _world_slow_tint_layer:CanvasLayer = null

var _world_slow_tint_rect:ColorRect = null

var _world_slow_tint_tween:Tween = null


func request_time_scale_override(source_key:String,factor:float,tint:Color = Color(0.20,0.55,1.0,0.14)) -> void:
	if source_key.is_empty():
		return
	_time_scale_overrides[source_key] = clampf(factor,0.05,1.0)
	_time_scale_override_tints[source_key] = tint
	_apply_time_scale_overrides()


func release_time_scale_override(source_key:String) -> void:
	if source_key.is_empty():
		return
	_time_scale_overrides.erase(source_key)
	_time_scale_override_tints.erase(source_key)
	_apply_time_scale_overrides()


func get_time_scale_override_factor() -> float:
	var result:float = 1.0
	for raw_factor in _time_scale_overrides.values():
		result = minf(result,clampf(float(raw_factor),0.05,1.0))
	return result


func get_base_game_time_scale() -> float:
	return _base_game_time_scale


func set_development_time_multiplier(multiplier:float) -> void:
	_development_time_multiplier = clampf(multiplier,0.0,32.0)
	_apply_time_scale_overrides()


func _apply_time_scale_overrides() -> void:
	var factor:float = get_time_scale_override_factor()
	var effective_scale:float = _base_game_time_scale * factor * _development_time_multiplier
	Engine.time_scale = effective_scale
	# V415：Engine.time_scale 不会自动改变音频播放速度。把同一有效倍率立即交给 Audios，
	# 游戏声会按该倍率播放；UI 声音由 Audios 做反向补偿，始终维持正常 1x。
	if Audios != null and Audios.has_method("set_game_time_scale"):
		Audios.set_game_time_scale(effective_scale)

	# Godot 文档指出：单独把 time_scale 拉高会降低物理精度。
	# 训练模式同步提高 physics_ticks_per_second，使高速投射物/极速闪避在高倍速下仍有足够采样。
	# 32x 时最多 1920 physics ticks/s；普通游戏仍维持 60Hz，避免无谓 CPU 开销。
	if _game.is_training_mode() or _development_time_multiplier > 1.0:
		var target_ticks:int = int(round(60.0 * maxf(effective_scale, 1.0)))
		Engine.physics_ticks_per_second = clampi(target_ticks, 60, _game.TRAINING_MAX_PHYSICS_TICKS)
		# 高 physics tick 时，Godot 还受“每个渲染帧最多模拟多少物理步”限制。
		# 32x 理论上需要约 32 个 physics step / render frame；留少量余量并封顶 64。
		Engine.max_physics_steps_per_frame = clampi(
			maxi(_game._normal_max_physics_steps_per_frame, int(ceil(maxf(effective_scale, 1.0))) + 2),
			_game._normal_max_physics_steps_per_frame,
			64
		)
	else:
		# 普通游戏维持60Hz；已移除的大规模降频接口不能再被读取并转换 int(null)。
		Engine.physics_ticks_per_second = 60
		# V420 性能：普通对局把“每渲染帧最多补多少物理步”压到 2。
		# 旧值 8 会形成死亡螺旋：一帧 CPU 超过 16.7ms 后，下一帧要补 2~8 个物理步，
		# 每个物理步又跑 100 个 state_machine/tick_physics，于是每帧更慢、要补的更多……
		# 100 单位实测：p50 从 128ms 降到 40ms。物理步数不足时 Godot 会自动放慢游戏时间，
		# 这比每帧 200ms 的顿挫要平滑得多。训练模式高倍速仍使用上面的动态上限。
		Engine.max_physics_steps_per_frame = mini(_game._normal_max_physics_steps_per_frame, NORMAL_MAX_PHYSICS_STEPS_PER_FRAME)

	_update_world_slow_tint(factor)


func _ensure_world_slow_tint() -> void:
	if _world_slow_tint_rect != null and is_instance_valid(_world_slow_tint_rect):
		return

	_world_slow_tint_layer = CanvasLayer.new()
	_world_slow_tint_layer.name = "WorldSlowTintLayer"
	_world_slow_tint_layer.layer = 110
	_world_slow_tint_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_game.add_child(_world_slow_tint_layer)

	_world_slow_tint_rect = ColorRect.new()
	_world_slow_tint_rect.name = "WorldSlowTint"
	_world_slow_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_slow_tint_rect.color = Color(0.0,0.0,0.0,0.0)
	_world_slow_tint_layer.add_child(_world_slow_tint_rect)
	_world_slow_tint_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _strongest_time_scale_tint(factor:float) -> Color:
	if _time_scale_overrides.is_empty():
		return Color(0.0,0.0,0.0,0.0)

	var best_key:String = ""
	var best_factor:float = 2.0
	for raw_key in _time_scale_overrides.keys():
		var key:String = str(raw_key)
		var candidate:float = clampf(float(_time_scale_overrides[raw_key]),0.05,1.0)
		if candidate < best_factor:
			best_factor = candidate
			best_key = key

	if best_key.is_empty() or not _time_scale_override_tints.has(best_key):
		return Color(0.20,0.55,1.0,0.14)

	var result:Color = _time_scale_override_tints[best_key]
	# 越慢颜色越明显，但始终尊重角色给出的 alpha 上限。
	var strength:float = clampf((1.0 - factor) / 0.75,0.0,1.0)
	result.a *= strength
	return result


func _update_world_slow_tint(factor:float) -> void:
	_ensure_world_slow_tint()
	if _world_slow_tint_rect == null or not is_instance_valid(_world_slow_tint_rect):
		return

	if _world_slow_tint_tween != null and _world_slow_tint_tween.is_valid():
		_world_slow_tint_tween.kill()

	var target:Color = _strongest_time_scale_tint(factor)
	_world_slow_tint_tween = _game.create_tween()
	_world_slow_tint_tween.set_ignore_time_scale(true)
	_world_slow_tint_tween.set_trans(Tween.TRANS_QUAD)
	_world_slow_tint_tween.set_ease(Tween.EASE_OUT)
	_world_slow_tint_tween.tween_property(
		_world_slow_tint_rect,
		"color",
		target,
		0.10 if factor < 1.0 else 0.16
	)
