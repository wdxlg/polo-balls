extends RefCounted
## 野生狗奶“时间流逝”日月视觉与配乐（角色专属全局效果）
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node


func _init(game: Node) -> void:
	_game = game


const WILD_DOG_TIME_MUSIC:AudioStream = preload("res://audio/characters/meme/野生狗奶/古风音乐 P1 《吹梦到西洲dj(0.8x)》《野生狗奶の小曲》黄诗扶、王敬轩丨“忘你不舍 寻你不休 画外人易朽 似浓淡相间色相构”.mp3")

# 野生狗奶的“时间加速”使用独立的世界背景昼夜视觉：
# 只改变 World/Background 的 self_modulate，并在背景上方、人物下方绘制太阳/月亮。
# 不使用全屏 CanvasModulate/ColorRect，避免把人物、伤害字和 UI 一起染黑。
var _wild_dog_time_visual_sources:Dictionary = {}

var _wild_dog_time_visual_phase:float = 0.0

var _wild_dog_time_visual_rate:float = 0.0

var _wild_dog_time_visual_root:Node2D = null

var _wild_dog_time_visual_sun:Node2D = null

var _wild_dog_time_visual_moon:Node2D = null

var _wild_dog_time_visual_background:Sprite2D = null

var _wild_dog_time_visual_background_base_modulate:Color = Color.WHITE

var _wild_dog_time_visual_world_id:int = 0

var _wild_dog_time_music_player:AudioStreamPlayer = null

# V270：跨“加速结束 -> 冷却 -> 下一轮加速”保存音乐进度。
# 只保存全局单播放器的位置，因此多只狗奶不会各自维护一套进度。
var _wild_dog_time_music_resume_position:float = 0.0


func _ensure_wild_dog_time_music_player() -> AudioStreamPlayer:
	if _wild_dog_time_music_player != null and is_instance_valid(_wild_dog_time_music_player):
		return _wild_dog_time_music_player
	var player := AudioStreamPlayer.new()
	player.name = "WildDogMilkTimeMusic"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	else:
		player.bus = &"Master"
	var playback_stream:AudioStream = WILD_DOG_TIME_MUSIC.duplicate(true) as AudioStream
	if playback_stream is AudioStreamMP3:
		(playback_stream as AudioStreamMP3).loop = true
	player.stream = playback_stream
	_game.add_child(player)
	_wild_dog_time_music_player = player
	return player


func _start_wild_dog_time_music() -> void:
	var player:AudioStreamPlayer = _ensure_wild_dog_time_music_player()
	if player == null or player.playing:
		return

	var resume_position:float = maxf(_wild_dog_time_music_resume_position,0.0)
	if player.stream != null:
		var stream_length:float = player.stream.get_length()
		if stream_length > 0.001:
			resume_position = fmod(resume_position,stream_length)
	player.play(resume_position)


func _stop_wild_dog_time_music() -> void:
	if _wild_dog_time_music_player == null or not is_instance_valid(_wild_dog_time_music_player):
		return
	if _wild_dog_time_music_player.playing:
		_wild_dog_time_music_resume_position = maxf(
			_wild_dog_time_music_player.get_playback_position(),
			0.0
		)
	_wild_dog_time_music_player.stop()


func request_wild_dog_time_visual(
	source_key:String,
	factor:float,
	factor_start:float,
	factor_end:float,
	cycle_rate_start:float,
	cycle_rate_end:float
) -> void:
	if source_key.is_empty():
		return
	_wild_dog_time_visual_sources[source_key] = {
		"factor": clampf(factor,0.05,1.0),
		"factor_start": clampf(factor_start,0.05,1.0),
		"factor_end": clampf(factor_end,0.05,1.0),
		"cycle_rate_start": maxf(cycle_rate_start,0.05),
		"cycle_rate_end": maxf(cycle_rate_end,cycle_rate_start),
	}
	_start_wild_dog_time_music()


func release_wild_dog_time_visual(source_key:String) -> void:
	if source_key.is_empty():
		return
	_wild_dog_time_visual_sources.erase(source_key)
	if _wild_dog_time_visual_sources.is_empty():
		_stop_wild_dog_time_music()
		_clear_wild_dog_time_visual_nodes()


func _wild_dog_time_circle_polygon(radius:float,segments:int = 40) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_segments:int = maxi(segments,8)
	for i:int in range(safe_segments):
		points.append(Vector2.from_angle(TAU * float(i) / float(safe_segments)) * radius)
	return points


func _create_wild_dog_time_sun() -> Node2D:
	var sun := Node2D.new()
	sun.name = "Sun"

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _wild_dog_time_circle_polygon(28.0,40)
	body.color = Color(1.0,0.82,0.20,1.0)
	sun.add_child(body)

	var core := Polygon2D.new()
	core.name = "Core"
	core.polygon = _wild_dog_time_circle_polygon(19.0,36)
	core.color = Color(1.0,0.95,0.55,1.0)
	sun.add_child(core)

	for i:int in range(8):
		var angle:float = TAU * float(i) / 8.0
		var ray := Line2D.new()
		ray.width = 4.0
		ray.default_color = Color(1.0,0.72,0.12,0.95)
		ray.antialiased = true
		ray.points = PackedVector2Array([
			Vector2.from_angle(angle) * 35.0,
			Vector2.from_angle(angle) * 48.0,
		])
		sun.add_child(ray)
	return sun


func _create_wild_dog_time_moon() -> Node2D:
	var moon := Node2D.new()
	moon.name = "Moon"

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _wild_dog_time_circle_polygon(27.0,40)
	body.color = Color(0.82,0.90,1.0,1.0)
	moon.add_child(body)

	# 用一个偏移的深色圆盖出月牙，不需要新增图片资源。
	var cutout := Polygon2D.new()
	cutout.name = "CrescentCutout"
	cutout.polygon = _wild_dog_time_circle_polygon(23.0,40)
	cutout.position = Vector2(10.0,-5.0)
	cutout.color = Color(0.035,0.055,0.11,1.0)
	moon.add_child(cutout)
	return moon


func _clear_wild_dog_time_visual_nodes() -> void:
	if _wild_dog_time_visual_background != null and is_instance_valid(_wild_dog_time_visual_background):
		_wild_dog_time_visual_background.self_modulate = _wild_dog_time_visual_background_base_modulate
	if _wild_dog_time_visual_root != null and is_instance_valid(_wild_dog_time_visual_root):
		_wild_dog_time_visual_root.queue_free()
	_wild_dog_time_visual_root = null
	_wild_dog_time_visual_sun = null
	_wild_dog_time_visual_moon = null
	_wild_dog_time_visual_background = null
	_wild_dog_time_visual_background_base_modulate = Color.WHITE
	_wild_dog_time_visual_world_id = 0
	_wild_dog_time_visual_phase = 0.0
	_wild_dog_time_visual_rate = 0.0


func _ensure_wild_dog_time_visual_nodes(world:World) -> void:
	if world == null or not is_instance_valid(world):
		return
	var world_id:int = world.get_instance_id()
	if _wild_dog_time_visual_root != null and is_instance_valid(_wild_dog_time_visual_root) and _wild_dog_time_visual_world_id == world_id:
		return

	_clear_wild_dog_time_visual_nodes()
	var background:Sprite2D = world.get_node_or_null("Background") as Sprite2D
	if background == null:
		return

	_wild_dog_time_visual_world_id = world_id
	_wild_dog_time_visual_background = background
	_wild_dog_time_visual_background_base_modulate = background.self_modulate

	_wild_dog_time_visual_root = Node2D.new()
	_wild_dog_time_visual_root.name = "WildDogMilkTimeSky"
	# World 自身 z=-2；Background 子节点 z=-3。这里 z=-2，最终位于背景之上、普通人物之下。
	_wild_dog_time_visual_root.z_index = -2
	_wild_dog_time_visual_root.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(_wild_dog_time_visual_root)

	_wild_dog_time_visual_sun = _create_wild_dog_time_sun()
	_wild_dog_time_visual_moon = _create_wild_dog_time_moon()
	_wild_dog_time_visual_root.add_child(_wild_dog_time_visual_sun)
	_wild_dog_time_visual_root.add_child(_wild_dog_time_visual_moon)


func _update_wild_dog_time_visual(delta:float,world:World) -> void:
	if _wild_dog_time_visual_sources.is_empty():
		if _wild_dog_time_visual_root != null or _wild_dog_time_visual_background != null:
			_clear_wild_dog_time_visual_nodes()
		return

	_ensure_wild_dog_time_visual_nodes(world)
	if (_wild_dog_time_visual_root == null or not is_instance_valid(_wild_dog_time_visual_root)
		or _wild_dog_time_visual_background == null or not is_instance_valid(_wild_dog_time_visual_background)):
		return

	# 多只狗奶同时加速时，选择“时间推进最深”的来源驱动共同天空；来源结束后自动切到剩余来源。
	var best_progress:float = -1.0
	var best_rate_start:float = 0.45
	var best_rate_end:float = 4.25
	for raw_key:Variant in _wild_dog_time_visual_sources.keys():
		var raw_data:Variant = _wild_dog_time_visual_sources[raw_key]
		if not raw_data is Dictionary:
			continue
		var data:Dictionary = raw_data as Dictionary
		var factor:float = clampf(float(data.get("factor",1.0)),0.05,1.0)
		var factor_start:float = clampf(float(data.get("factor_start",0.78)),0.05,1.0)
		var factor_end:float = clampf(float(data.get("factor_end",0.24)),0.05,1.0)
		var span:float = maxf(absf(factor_start - factor_end),0.001)
		var progress:float = (factor_start - factor) / span if factor_start >= factor_end else (factor - factor_start) / span
		progress = clampf(progress,0.0,1.0)
		if progress > best_progress:
			best_progress = progress
			best_rate_start = maxf(float(data.get("cycle_rate_start",0.45)),0.05)
			best_rate_end = maxf(float(data.get("cycle_rate_end",4.25)),best_rate_start)

	if best_progress < 0.0:
		return

	var target_rate:float = lerpf(best_rate_start,best_rate_end,pow(best_progress,1.20))
	# delta 已乘 Engine.time_scale；除掉当前临时时间覆写，让天空循环不被狗奶自己的减速拖慢。
	# 玩家主动设置的基础速度仍然保留，因此 2x/0.5x 游戏速度下视觉仍与整场战斗同步。
	var visual_delta:float = maxf(delta,0.0) / maxf(_game.get_time_scale_override_factor(),0.05)
	if _wild_dog_time_visual_rate <= 0.0:
		_wild_dog_time_visual_rate = target_rate
	else:
		var response:float = 1.0 - exp(-visual_delta * 5.0)
		_wild_dog_time_visual_rate = lerpf(_wild_dog_time_visual_rate,target_rate,clampf(response,0.0,1.0))
	_wild_dog_time_visual_phase = fmod(
		_wild_dog_time_visual_phase + visual_delta * _wild_dog_time_visual_rate * TAU,
		TAU
	)

	# phase=0 为原本蓝色；半圈达到纯黑；一整圈回到原本蓝色。循环频率会随加速阶段越来越快。
	var darkness:float = 0.5 - 0.5 * cos(_wild_dog_time_visual_phase)
	var base_color:Color = _wild_dog_time_visual_background_base_modulate
	var black_color := Color(0.0,0.0,0.0,base_color.a)
	_wild_dog_time_visual_background.self_modulate = base_color.lerp(black_color,darkness)

	# 日月必须始终在“真实地图矩形”外侧，而不是围绕镜头中心在地图内部转。
	# 位置按当前地图世界 Rect2 计算；相机只负责反向缩放日月本体，让视觉尺寸不因工具栏缩放而忽大忽小。
	var camera:Camera2D = world.camera_2d
	if camera == null or not is_instance_valid(camera):
		camera = world.get_viewport().get_camera_2d()
	var inverse_zoom_x:float = 1.0
	var inverse_zoom_y:float = 1.0
	if camera != null and is_instance_valid(camera):
		inverse_zoom_x = 1.0 / maxf(absf(camera.zoom.x),0.001)
		inverse_zoom_y = 1.0 / maxf(absf(camera.zoom.y),0.001)

	var map_rect := Rect2()
	if world.map_group.has(world.now_choose_map):
		var map_node:Variant = world.map_group[world.now_choose_map]
		if map_node is TileMapLayer:
			map_rect = world.return_map_world_rect(map_node as TileMapLayer)

	# 没有有效地图时宁可暂时隐藏日月，也不回退到镜头中心，避免再次出现在地图内部。
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		if _wild_dog_time_visual_sun != null and is_instance_valid(_wild_dog_time_visual_sun):
			_wild_dog_time_visual_sun.visible = false
		if _wild_dog_time_visual_moon != null and is_instance_valid(_wild_dog_time_visual_moon):
			_wild_dog_time_visual_moon.visible = false
		return

	var map_center:Vector2 = map_rect.get_center()
	var half_size:Vector2 = map_rect.size * 0.5
	var sun_angle:float = _wild_dog_time_visual_phase - PI * 0.5
	var orbit_direction:Vector2 = Vector2.from_angle(sun_angle)

	# 从地图中心沿当前角度求射线与地图外框的交点距离，再额外推出“日月半径 + 缓冲距离”。
	# 这样无论角度怎么转，太阳和月亮的整个图形都不会进入地图矩形。
	var border_distance_x:float = INF if absf(orbit_direction.x) < 0.0001 else half_size.x / absf(orbit_direction.x)
	var border_distance_y:float = INF if absf(orbit_direction.y) < 0.0001 else half_size.y / absf(orbit_direction.y)
	var border_distance:float = minf(border_distance_x,border_distance_y)
	var visual_world_radius:float = 52.0 * maxf(inverse_zoom_x,inverse_zoom_y)
	var outside_gap:float = 14.0 * maxf(inverse_zoom_x,inverse_zoom_y)
	var orbit_distance:float = border_distance + visual_world_radius + outside_gap

	_wild_dog_time_visual_root.global_position = map_center
	_wild_dog_time_visual_root.global_rotation = 0.0
	_wild_dog_time_visual_root.scale = Vector2.ONE

	if _wild_dog_time_visual_sun != null and is_instance_valid(_wild_dog_time_visual_sun):
		_wild_dog_time_visual_sun.visible = true
		_wild_dog_time_visual_sun.position = orbit_direction * orbit_distance
		_wild_dog_time_visual_sun.scale = Vector2(inverse_zoom_x,inverse_zoom_y)
		_wild_dog_time_visual_sun.rotation = _wild_dog_time_visual_phase * 0.45
		_wild_dog_time_visual_sun.modulate.a = lerpf(1.0,0.28,darkness)
	if _wild_dog_time_visual_moon != null and is_instance_valid(_wild_dog_time_visual_moon):
		_wild_dog_time_visual_moon.visible = true
		_wild_dog_time_visual_moon.position = -orbit_direction * orbit_distance
		_wild_dog_time_visual_moon.scale = Vector2(inverse_zoom_x,inverse_zoom_y)
		_wild_dog_time_visual_moon.rotation = -_wild_dog_time_visual_phase * 0.18
		_wild_dog_time_visual_moon.modulate.a = lerpf(0.32,1.0,darkness)
