extends Node2D

@export var Master_name:String = ""
@export var Team:String = ""
@export var start_position:Vector2 = Vector2.ZERO
@export var landing_position:Vector2 = Vector2.ZERO
@export var flight_duration:float = 0.56
@export var shake_duration:float = 0.42
@export var explosion_radius:float = 42.0
@export var damage_multiplier:float = 0.70
@export var visual_radius:float = 5.0
@export var arc_height:float = 18.0
@export_range(0.5,6.0,0.1) var range_outline_width:float = 1.5
@export_range(0.02,0.60,0.01) var range_fill_alpha:float = 0.16

var _elapsed:float = 0.0
var _land_elapsed:float = 0.0
var _landed:bool = false
var _finished:bool = false
var _visual_offset:Vector2 = Vector2.ZERO
var _phase:float = 0.0


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MagicHornSmallBomb")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if start_position == Vector2.ZERO:
		start_position = global_position
	if landing_position == Vector2.ZERO:
		landing_position = global_position
	global_position = start_position
	_phase = randf_range(0.0,TAU)
	queue_redraw()


func _process(delta:float) -> void:
	if _finished:
		return
	_phase += delta * 34.0
	if not _landed:
		var duration:float = maxf(flight_duration,0.05)
		var t:float = clampf(_elapsed / duration,0.0,1.0)
		var height:float = sin(t * PI) * maxf(arc_height,0.0)
		_visual_offset = Vector2(0.0,-height)
	else:
		var p:float = clampf(_land_elapsed / maxf(shake_duration,0.05),0.0,1.0)
		var amp:float = (1.0 - p) * 2.4
		_visual_offset = Vector2(sin(_phase * 1.27),cos(_phase * 1.71)) * amp
	queue_redraw()


func _physics_process(delta:float) -> void:
	if not is_multiplayer_authority() or _finished:
		return
	var master:ball = _resolve_master()
	if master == null or not is_instance_valid(master) or master.health <= 0:
		_finish()
		return
	if not master.is_combat_runtime_active():
		return

	if not _landed:
		_elapsed += delta
		var duration:float = maxf(flight_duration,0.05)
		var t:float = clampf(_elapsed / duration,0.0,1.0)
		# smoothstep 只控制地面平面推进；局部Y高度由 _process() 的 sin 抛物线表现。
		var smooth_t:float = t * t * (3.0 - 2.0 * t)
		global_position = start_position.lerp(landing_position,smooth_t)
		if t >= 1.0:
			global_position = landing_position
			_landed = true
			_land_elapsed = 0.0
		return

	_land_elapsed += delta
	if _land_elapsed >= maxf(shake_duration,0.05):
		if master.has_method("resolve_magic_horn_small_bomb_explosion"):
			master.call("resolve_magic_horn_small_bomb_explosion",global_position,explosion_radius,damage_multiplier)
		_finish()


func _draw() -> void:
	var c:Vector2 = _visual_offset
	var r:float = maxf(visual_radius,2.0)
	var px:float = 2.0

	# 落地后先显示固定爆炸范围：外圈不缩放，只作为真实范围标识。
	# 内部半透明红圆从中心持续长大；当它碰到外圈时，逻辑层同一时刻触发爆炸。
	if _landed:
		var p:float = clampf(_land_elapsed / maxf(shake_duration,0.05),0.0,1.0)
		var warning_radius:float = maxf(explosion_radius,1.0)
		var fill_radius:float = warning_radius * p
		if fill_radius > 0.01:
			draw_circle(
				Vector2.ZERO,
				fill_radius,
				Color(1.0,0.035,0.025,clampf(range_fill_alpha,0.02,0.60)),
				true
			)
			draw_arc(
				Vector2.ZERO,
				fill_radius,
				0.0,
				TAU,
				64,
				Color(1.0,0.18,0.06,0.38 + 0.42 * p),
				1.0,
				true
			)
		draw_arc(
			Vector2.ZERO,
			warning_radius,
			0.0,
			TAU,
			72,
			Color(1.0,0.055,0.035,0.94),
			maxf(range_outline_width,0.5),
			true
		)

	# 保留像素化小爆弹本体；落地后的颤抖只作用于炸弹，不带着范围圈一起抖。
	var cells:int = int(ceil(r / px))
	for y:int in range(-cells,cells + 1):
		for x:int in range(-cells,cells + 1):
			var local:Vector2 = Vector2(float(x),float(y)) * px
			if local.length() > r:
				continue
			var edge:bool = false
			for neighbor in [Vector2(px,0),Vector2(-px,0),Vector2(0,px),Vector2(0,-px)]:
				if (local + neighbor).length() > r:
					edge = true
					break
			var color_value:Color = Color(0.01,0.01,0.012,1.0) if edge else (Color(0.19,0.16,0.18,1.0) if ((x + y) & 1) == 0 else Color(0.11,0.10,0.12,1.0))
			draw_rect(Rect2(c + local - Vector2.ONE * px * 0.5,Vector2.ONE * px),color_value,true)


func _resolve_master() -> ball:
	if Master_name.is_empty():
		return null
	var world:Node = get_tree().current_scene
	if world != null:
		var direct:Node = world.get_node_or_null(NodePath(Master_name))
		if direct is ball:
			return direct as ball
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and str(node.name) == Master_name:
			return node as ball
	return null


func _finish() -> void:
	if _finished:
		return
	_finished = true
	Game.free_node(self)
