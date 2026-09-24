extends "res://scripts/effects/我的世界/重锤落地冲击.gd"
# Reuse the mace's actual three pixel-arc bands, streaks and expansion curve.
# Only its palette is changed; the cosmic disk is behind actors, not over them.
# 到达圆圈在落位当帧就发出第一跳，之后每 tick_interval 一跳；每一跳都用圆圈当前扩张半径结算，
# 造成固定伤害并做一次微小向外击退，一共 tick_count 跳。
signal tick(point: Vector2, radius: float, index: int)

const COSMIC_SHADER: Shader = preload("res://shaders/heavenfall_ring.gdshader")
const COSMIC_ATLAS: Texture2D = preload("res://Images/characters/我的世界/new6/av_cosmic_atlas.png")
@export var tick_count: int = 5
@export var tick_interval: float = 0.09
var _fill: Polygon2D
var _fill_material: ShaderMaterial
var _cosmic_start: float = 0.0
var _ticks: int = 0


func configure(point: Vector2, radius: float, aperture: Vector2, cosmic_age: float, seed_value: int) -> void:
	add_to_group("BattleTransient")
	add_to_group("HeavenfallArrivalRing")
	global_position = point
	_radius = maxf(radius, 8.0)
	_elapsed = 0.0
	_effect_end_time = lifetime
	_cosmic_start = cosmic_age
	z_as_relative = false
	z_index = 98
	_ring_palette = PackedColorArray([Color("14534f"), Color("83dbd6"), Color("c8c8c8"), Color("83dbd6")])
	_rng.seed = maxi(seed_value, 1)
	_build_streaks()
	# Do not call the mace's floor sampler / rubble generator for a space attack.
	_fill = Polygon2D.new()
	_fill.name = "CosmicCircleInterior"
	_fill.z_as_relative = false
	_fill.z_index = _world_depth() - 2 # Below the rift rim too, so its fast closure stays visible.
	var extent: float = _radius * maxf(ring_end_scale, 1.0) + 8.0
	_fill.polygon = PackedVector2Array([Vector2(-extent, -extent), Vector2(extent, -extent), Vector2(extent, extent), Vector2(-extent, extent)])
	_fill_material = ShaderMaterial.new()
	_fill_material.shader = COSMIC_SHADER
	_fill_material.set_shader_parameter("cosmic_atlas", COSMIC_ATLAS)
	_fill_material.set_shader_parameter("cosmic_origin", aperture)
	_fill_material.set_shader_parameter("linear_output", get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility")
	_fill.material = _fill_material
	add_child(_fill)
	_sync_fill()
	queue_redraw()
	# 落位当帧的第一跳：每个 peer 都重放圆圈，只有权威端在回调里真正结算。
	_emit_tick()


func _world_depth() -> int:
	var depth: int = 0
	var node: Node = get_parent()
	while node != null and not node is CanvasLayer and not node is Viewport:
		if node is CanvasItem:
			depth += node.z_index
			if not node.z_as_relative: break
		node = node.get_parent()
	return clampi(depth, -4095, 4095)


func ticks_done() -> int:
	return _ticks


func tick_radius() -> float:
	# 与重锤同一条扩张曲线；这里不取整数吸附，命中判定用真实半径。
	var p: float = clampf(_elapsed / maxf(lifetime, 0.02), 0.0, 1.0)
	var expand: float = 1.0 - pow(1.0 - p, 3.1)
	return lerpf(_radius, _radius * maxf(ring_end_scale, 1.0), expand)


func _process(delta: float) -> void:
	if Game.now_stop_state or get_tree().paused:
		return
	_elapsed += maxf(delta, 0.0)
	_sync_fill()
	queue_redraw()
	_emit_due_ticks()
	if _elapsed >= maxf(lifetime, 0.02): queue_free()


func _emit_tick() -> void:
	if _ticks >= maxi(tick_count, 1):
		return
	tick.emit(global_position, tick_radius(), _ticks)
	_ticks += 1


func _emit_due_ticks() -> void:
	# 每 tick_interval 一跳，跳数封顶，圆圈本身仍按原曲线扩张。
	var interval: float = maxf(tick_interval, 0.01)
	while _ticks < maxi(tick_count, 1) and _elapsed >= float(_ticks) * interval:
		_emit_tick()


func _sync_fill() -> void:
	if _fill_material == null: return
	_fill_material.set_shader_parameter("radius", snappedf(tick_radius(), 1.5))
	_fill_material.set_shader_parameter("opacity", pow(1.0 - clampf(_elapsed / maxf(lifetime, 0.02), 0.0, 1.0), 1.28))
	_fill_material.set_shader_parameter("cosmic_time", _cosmic_start + _elapsed)


func _draw() -> void:
	_draw_ring_and_streaks()
