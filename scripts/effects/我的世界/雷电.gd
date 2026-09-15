extends Node2D

# 苦力怕自引雷视觉与本地空间音效。
# 调用顺序：instantiate() -> setup(落点, 随机种子, 判定半径, 雷声预警时间) -> add_child()。
# 伤害仍由苦力怕 authority 在白圈出现的同一时刻结算；这里仅负责表现与音效。

const HIT_BURST_EFFECT_SCRIPT = preload("res://scripts/effects/hit_burst_effect.gd")
const THUNDER_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/苦力怕/thunder1.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/thunder2.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/thunder3.ogg"),
]
const EXPLOSION_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/苦力怕/explode1.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode2.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode3.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode4.ogg"),
]

@export_category("雷电 / 时序")
@export_range(0.10,1.50,0.01) var warning_delay:float = 0.68
@export_range(0.08,0.80,0.01) var bolt_lifetime:float = 0.28
@export_range(0.12,1.00,0.01) var impact_lifetime:float = 0.46
@export_range(0.015,0.15,0.005) var reroute_interval:float = 0.045

@export_category("雷电 / 闪电本体")
@export_range(5,22,1) var segment_count:int = 13
@export_range(4.0,70.0,1.0) var bend_strength:float = 22.0
@export_range(0.5,5.0,0.1) var core_width:float = 1.8
@export_range(1.0,10.0,0.1) var inner_glow_width:float = 4.6
@export_range(3.0,100.0,0.1) var outer_glow_width:float = 90.0

@export_category("雷电 / 落点")
@export_range(12.0,180.0,1.0) var impact_radius:float = 62.0
@export_range(1.05,3.0,0.05) var impact_ring_end_scale:float = 1.72
@export_range(5,28,1) var impact_line_min_count:int = 10
@export_range(5,32,1) var impact_line_max_count:int = 15

@export_category("雷电 / 音效")
@export_range(-30.0,12.0,0.5) var thunder_volume_db:float = -5.0
@export_range(-30.0,12.0,0.5) var explosion_volume_db:float = -2.5
@export_range(100.0,2400.0,25.0) var audio_max_distance:float = 1200.0

var _target_world:Vector2 = Vector2.ZERO
var _seed_value:int = 1
var _configured:bool = false
var _rng := RandomNumberGenerator.new()
var _start_local:Vector2 = Vector2.ZERO
var _end_local:Vector2 = Vector2.ZERO
var _points:PackedVector2Array = PackedVector2Array()
var _elapsed:float = 0.0
var _reroute_left:float = 0.0
var _impact_started:bool = false
var _impact_lines_spawned:bool = false


func setup(
	target_world_position:Vector2,
	seed_value:int = 1,
	new_impact_radius:float = -1.0,
	new_warning_delay:float = -1.0
) -> void:
	_target_world = target_world_position
	_seed_value = maxi(abs(seed_value),1)
	if new_impact_radius > 0.0:
		impact_radius = new_impact_radius
	if new_warning_delay > 0.0:
		warning_delay = new_warning_delay
	_configured = true


func _ready() -> void:
	add_to_group("BattleTransient")
	set_as_top_level(true)
	z_as_relative = false
	z_index = 180
	_rng.seed = _seed_value
	global_position = _target_world if _configured else global_position
	_end_local = Vector2.ZERO
	_start_local = _resolve_window_top_world(global_position) - global_position
	_rebuild_path()
	_play_random_spatial_sfx(THUNDER_SOUNDS,thunder_volume_db,"CreeperThunderWarning")
	queue_redraw()


func _process(delta:float) -> void:
	_elapsed += maxf(delta,0.0)
	if not _impact_started:
		_follow_parent_foot_until_impact()
	if not _impact_started and _elapsed >= warning_delay:
		_start_impact()

	if _impact_started:
		_reroute_left -= maxf(delta,0.0)
		if _reroute_left <= 0.0 and _impact_elapsed() <= bolt_lifetime:
			_reroute_left = maxf(reroute_interval,0.015)
			_rebuild_path()
		queue_redraw()

	if _elapsed >= warning_delay + maxf(bolt_lifetime,impact_lifetime):
		queue_free()


func _start_impact() -> void:
	# 最后一帧再同步一次脚底，并以当前落点重算屏幕顶部起点。
	_follow_parent_foot_until_impact()
	_impact_started = true
	_start_local = _resolve_window_top_world(global_position) - global_position
	_reroute_left = 0.0
	_rebuild_path()
	_spawn_white_impact_lines()
	_play_random_spatial_sfx(EXPLOSION_SOUNDS,explosion_volume_db,"CreeperLightningImpact")
	queue_redraw()


func _impact_elapsed() -> float:
	return maxf(_elapsed - warning_delay,0.0)


func _follow_parent_foot_until_impact() -> void:
	if _impact_started:
		return
	var owner_node:Node = get_parent()
	if owner_node == null or not is_instance_valid(owner_node):
		return
	if not owner_node.has_method("_self_foot_world_position"):
		return
	var resolved:Variant = owner_node.call("_self_foot_world_position")
	if resolved is Vector2:
		global_position = resolved as Vector2


func _resolve_window_top_world(target_world:Vector2) -> Vector2:
	var viewport:Viewport = get_viewport()
	if viewport == null:
		return target_world + Vector2(0.0,-900.0)
	var canvas_transform:Transform2D = viewport.get_canvas_transform()
	var target_screen:Vector2 = canvas_transform * target_world
	var visible_rect:Rect2 = viewport.get_visible_rect()
	var start_screen := Vector2(
		target_screen.x + _rng.randf_range(-18.0,18.0),
		visible_rect.position.y - 10.0
	)
	return canvas_transform.affine_inverse() * start_screen


func _rebuild_path() -> void:
	var count:int = maxi(segment_count,3)
	var result := PackedVector2Array()
	var axis:Vector2 = _end_local - _start_local
	var length_value:float = axis.length()
	var normal:Vector2 = axis.normalized().orthogonal() if length_value > 0.001 else Vector2.RIGHT
	var tangent:Vector2 = axis.normalized() if length_value > 0.001 else Vector2.DOWN
	result.append(_start_local)
	for i:int in range(1,count):
		var t:float = float(i) / float(count)
		var envelope:float = sin(PI * t)
		var side_offset:float = _rng.randf_range(-bend_strength,bend_strength) * envelope
		var along_offset:float = _rng.randf_range(-4.0,4.0) * envelope
		var point:Vector2 = _start_local.lerp(_end_local,t)
		point += normal * side_offset + tangent * along_offset
		result.append(point)
	result.append(_end_local)
	_points = result


func _draw() -> void:
	if not _impact_started:
		return
	_draw_bolt()
	_draw_impact_ring()


func _draw_bolt() -> void:
	if _points.size() < 2:
		return
	var p:float = clampf(_impact_elapsed() / maxf(bolt_lifetime,0.001),0.0,1.0)
	if p >= 1.0:
		return
	var fade:float = pow(1.0 - p,0.82)
	var flicker:float = 0.82 + sin(_impact_elapsed() * 92.0) * 0.18
	var alpha:float = clampf(fade * flicker,0.0,1.0)
	# 细白核心 + 两层低透明冷白光晕：视觉发光，但不再形成粗灰柱。
	draw_polyline(_points,Color(0.58,0.78,1.0,0.055 * alpha),outer_glow_width * 0.72,true)
	draw_polyline(_points,Color(0.72,0.88,1.0,0.15 * alpha),outer_glow_width * 0.55,true)
	draw_polyline(_points,Color(0.90,0.96,1.0,0.58 * alpha),inner_glow_width,true)
	draw_polyline(_points,Color(1.0,1.0,1.0,1.0 * alpha),core_width,true)


func _draw_impact_ring() -> void:
	var p:float = clampf(_impact_elapsed() / maxf(impact_lifetime,0.001),0.0,1.0)
	if p >= 1.0:
		return
	var expand:float = 1.0 - pow(1.0 - p,3.1)
	var alpha:float = pow(1.0 - p,1.28)
	# p=0 时半径严格等于 impact_radius；苦力怕用同一个数值进行真实伤害判定。
	var radius:float = lerpf(impact_radius,impact_radius * maxf(impact_ring_end_scale,1.0),expand)
	draw_circle(Vector2.ZERO,impact_radius,Color(0.78,0.91,1.0,0.055 * alpha))
	draw_arc(Vector2.ZERO,radius,0.0,TAU,56,Color(0.55,0.78,1.0,0.12 * alpha),8.0,true)
	draw_arc(Vector2.ZERO,radius,0.0,TAU,56,Color(0.78,0.91,1.0,0.34 * alpha),4.0,true)
	draw_arc(Vector2.ZERO,radius,0.0,TAU,56,Color(1.0,1.0,1.0,0.98 * alpha),1.35,true)


func _spawn_white_impact_lines() -> void:
	if _impact_lines_spawned:
		return
	_impact_lines_spawned = true
	var low:int = mini(impact_line_min_count,impact_line_max_count)
	var high:int = maxi(impact_line_min_count,impact_line_max_count)
	var count:int = _rng.randi_range(maxi(low,1),maxi(high,maxi(low,1)))
	var streaks:Array = []
	for index:int in range(count):
		var angle:float = float(index) * 2.39996323 + _rng.randf_range(-0.54,0.54)
		var direction:=Vector2.RIGHT.rotated(angle)
		var tangent:=Vector2(-direction.y,direction.x)
		var spawn_offset:Vector2 = (
			direction * _rng.randf_range(impact_radius * 0.08,impact_radius * 0.36)
			+ tangent * _rng.randf_range(-impact_radius * 0.16,impact_radius * 0.16)
		)
		var cool_mix:float = _rng.randf_range(0.0,1.0)
		streaks.append({
			"spawn_offset": spawn_offset,
			"direction": direction,
			"distance": impact_radius * _rng.randf_range(1.25,2.35),
			"length": impact_radius * _rng.randf_range(0.34,0.78),
			"width": _rng.randf_range(0.65,1.25),
			"duration": _rng.randf_range(0.20,0.34),
			"delay": _rng.randf_range(0.0,0.045),
			"grow_end": _rng.randf_range(0.22,0.34),
			"fade_in_end": _rng.randf_range(0.06,0.12),
			"fade_out_start": _rng.randf_range(0.46,0.62),
			"color": Color(lerpf(1.0,0.82,cool_mix),lerpf(1.0,0.94,cool_mix),1.0,0.98),
		})

	var effect:Node2D = HIT_BURST_EFFECT_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "CreeperLightningWhiteLines_%d" % (_seed_value & 0x7fffffff)
	if effect.has_method("setup"):
		effect.call("setup",global_position,streaks)
	var parent:Node = get_parent()
	if parent != null:
		parent.add_child(effect,true)
	else:
		add_child(effect,true)


func _play_random_spatial_sfx(streams:Array[AudioStream],volume_db:float,node_name:String) -> void:
	if streams.is_empty():
		return
	var stream:AudioStream = streams[_rng.randi_range(0,streams.size() - 1)]
	if stream == null:
		return
	var parent:Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _rng.randf_range(0.97,1.03)
	player.max_distance = maxf(audio_max_distance,100.0)
	player.attenuation = 0.72
	player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	parent.add_child(player,true)
	player.global_position = global_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
