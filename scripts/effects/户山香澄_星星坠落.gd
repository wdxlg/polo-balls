extends Node2D

# V392：户山香澄落星纯视觉效果。
# - 警告标识只快速红<->黄变色，不改变大小。
# - 星星从左上/右上斜向旋转坠落，缩小硬描边并增加多层星形发光。
# - 拖尾改为类似小刀猎 Stretch Only 的宽大拉伸残影带，不再是一条短细线。
# - 落地使用“快->慢”的黄色发光描边扩散并渐隐，同时生成类似人物受击白线的随机黄色爆射线。
# 真实伤害与命中音效仍由户山香澄 authority 脚本结算。

const HIT_BURST_EFFECT_SCRIPT = preload("res://scripts/effects/hit_burst_effect.gd")

@export_range(0.15,3.0,0.01) var impact_delay:float = 0.92
@export_range(0.04,1.0,0.01) var warning_color_cycle:float = 0.16
@export_range(4.0,42.0,0.5) var star_radius:float = 16.0
@export_range(0.10,1.0,0.01) var burst_lifetime:float = 0.42
@export_range(0.05,1.5,0.01) var warning_base_scale:float = 0.30
@export_range(0.25,6.0,0.05) var star_spin_turns:float = 2.35

@export_category("户山香澄 - 星星拖尾")
@export_range(40.0,260.0,2.0) var star_trail_length:float = 148.0
@export_range(0.25,2.5,0.05) var star_trail_head_width:float = 1.10
@export_range(0.0,1.0,0.01) var star_trail_alpha:float = 0.72

@export_category("户山香澄 - 落地视觉")
@export_range(1.5,7.0,0.1) var impact_ring_end_scale:float = 4.20
@export_range(5,28,1) var impact_line_min_count:int = 10
@export_range(5,32,1) var impact_line_max_count:int = 16

@onready var warning:Sprite2D = $Warning

var _elapsed:float = 0.0
var _configured:bool = false
var _start_offset:Vector2 = Vector2(-150.0,-210.0)
var _spin_direction:float = 1.0
var _visual_seed:int = 1
var _impact_lines_spawned:bool = false


func configure(
	impact_delay_value:float,
	start_offset_value:Vector2,
	warning_cycle_value:float,
	star_radius_value:float,
	visual_seed_value:int = 1
) -> void:
	impact_delay = maxf(impact_delay_value,0.05)
	_start_offset = start_offset_value
	if _start_offset.length_squared() <= 0.001:
		_start_offset = Vector2(-150.0,-210.0)
	warning_color_cycle = maxf(warning_cycle_value,0.04)
	star_radius = maxf(star_radius_value,2.0)
	_spin_direction = -1.0 if _start_offset.x < 0.0 else 1.0
	_visual_seed = visual_seed_value if visual_seed_value != 0 else 1
	_configured = true
	queue_redraw()


func _ready() -> void:
	top_level = true
	z_index = 90
	if warning != null:
		warning.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		warning.centered = true
		warning.scale = Vector2.ONE * warning_base_scale
		warning.z_index = 1
	_configured = true
	queue_redraw()


func _process(delta:float) -> void:
	if not _configured:
		return
	var previous_elapsed:float = _elapsed
	_elapsed += maxf(delta,0.0)
	_update_warning_visual()
	if not _impact_lines_spawned and previous_elapsed < impact_delay and _elapsed >= impact_delay:
		_spawn_yellow_impact_lines()
	queue_redraw()
	if _elapsed >= impact_delay + burst_lifetime:
		queue_free()


func _update_warning_visual() -> void:
	if warning == null:
		return
	if _elapsed >= impact_delay:
		warning.visible = false
		return
	warning.visible = true

	# 只变色，不呼吸、不改变 scale。
	var cycle:float = maxf(warning_color_cycle,0.04)
	var phase:float = fmod(_elapsed,cycle) / cycle
	var yellow_mix:float = (1.0 - cos(phase * TAU)) * 0.5
	var red_color:=Color(1.0,0.04,0.02,1.0)
	var yellow_color:=Color(1.0,0.96,0.04,1.0)
	warning.modulate = red_color.lerp(yellow_color,yellow_mix)
	warning.scale = Vector2.ONE * warning_base_scale


func _draw() -> void:
	if not _configured:
		return
	if _elapsed < impact_delay:
		_draw_falling_star()
	else:
		_draw_impact_burst()


func _draw_falling_star() -> void:
	var p:float = clampf(_elapsed / maxf(impact_delay,0.001),0.0,1.0)
	# 星体继续保持越接近地面越快的二次加速。
	var fall_p:float = p * p
	var star_center:Vector2 = _start_offset.lerp(Vector2.ZERO,fall_p)
	var move_dir:Vector2 = (-_start_offset).normalized()
	if move_dir.length_squared() <= 0.001:
		move_dir = Vector2.DOWN

	var current_radius:float = star_radius * lerpf(0.84,1.08,fall_p)
	_draw_knife_style_trail(star_center,move_dir,current_radius,fall_p)

	# 明显旋转着下落；左右入口使用相反旋转方向。
	var rotation_value:float = -PI * 0.5 + _spin_direction * p * TAU * star_spin_turns

	# V392：描边不再用 1.34 倍的大实心外壳。改成低透明星形光晕 + 细硬描边。
	var glow_far:=_star_points(star_center,current_radius * 1.16,rotation_value)
	var glow_near:=_star_points(star_center,current_radius * 1.08,rotation_value)
	var body:=_star_points(star_center,current_radius,rotation_value)
	var core:=_star_points(star_center,current_radius * 0.58,rotation_value)
	draw_colored_polygon(glow_far,Color(1.0,0.66,0.03,0.07))
	draw_colored_polygon(glow_near,Color(1.0,0.80,0.06,0.15))
	draw_colored_polygon(body,Color(1.0,0.91,0.12,1.0))
	draw_colored_polygon(core,Color(1.0,0.985,0.66,0.74))

	var outline:=PackedVector2Array(body)
	if not outline.is_empty():
		outline.append(outline[0])
	draw_polyline(outline,Color(1.0,0.55,0.025,0.98),maxf(current_radius * 0.050,0.72),true)


func _draw_knife_style_trail(
	star_center:Vector2,
	move_dir:Vector2,
	current_radius:float,
	fall_p:float
) -> void:
	# 小刀猎的刀使用 Stretch Only：主体后方是一条明显的拉伸残影，而不是细线。
	# 星星没有 Sprite 残影基类，所以在这里用历史运动方向构建同语义的宽大渐细 Ribbon。
	var trail_visibility:float = smoothstep(0.02,0.20,fall_p)
	if trail_visibility <= 0.001:
		return
	var trail_length:float = maxf(star_trail_length,8.0) * lerpf(0.68,1.0,fall_p)
	var head:Vector2 = star_center - move_dir * current_radius * 0.38
	var half_width:float = current_radius * maxf(star_trail_head_width,0.1)

	var outer:=_build_trail_ribbon(head,move_dir,trail_length,half_width * 1.38)
	var middle:=_build_trail_ribbon(head,move_dir,trail_length * 0.94,half_width * 0.86)
	var core:=_build_trail_ribbon(head,move_dir,trail_length * 0.82,half_width * 0.42)
	var alpha:float = clampf(star_trail_alpha,0.0,1.0) * trail_visibility
	draw_colored_polygon(outer,Color(1.0,0.51,0.02,0.10 * alpha))
	draw_colored_polygon(middle,Color(1.0,0.78,0.06,0.30 * alpha))
	draw_colored_polygon(core,Color(1.0,0.965,0.52,0.50 * alpha))


func _build_trail_ribbon(
	head:Vector2,
	move_dir:Vector2,
	length_value:float,
	head_half_width:float
) -> PackedVector2Array:
	var direction:Vector2 = move_dir.normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector2.DOWN
	var side:=Vector2(-direction.y,direction.x)
	var left:=PackedVector2Array()
	var right:=PackedVector2Array()
	var sections:int = 8
	for i:int in range(sections + 1):
		var t:float = float(i) / float(sections) # 0=尾端，1=星星后缘
		var width_factor:float = pow(t,0.72)
		var center:Vector2 = head - direction * length_value * (1.0 - t)
		# 极轻微横向弯曲，让长拖尾不是完全死板的三角形，但不改变真实落点。
		center += side * sin(t * PI) * head_half_width * 0.055 * _spin_direction
		var half_width:float = head_half_width * width_factor
		left.append(center - side * half_width)
		right.append(center + side * half_width)
	var polygon:=PackedVector2Array()
	for point:Vector2 in left:
		polygon.append(point)
	for i:int in range(right.size() - 1,-1,-1):
		polygon.append(right[i])
	return polygon


func _draw_impact_burst() -> void:
	var p:float = clampf((_elapsed - impact_delay) / maxf(burst_lifetime,0.001),0.0,1.0)
	# ease-out：刚砸地时扩张最快，随后明显减速；同时持续渐隐。
	var expand:float = 1.0 - pow(1.0 - p,3.2)
	var alpha:float = pow(1.0 - p,1.35)
	var radius:float = lerpf(star_radius * 0.82,star_radius * maxf(impact_ring_end_scale,1.0),expand)

	# 视觉上仍是一条黄色描边，只是用三层同心线模拟发光，不再保留旧版实心黄色圆。
	draw_arc(Vector2.ZERO,radius,0.0,TAU,42,Color(1.0,0.68,0.02,0.15 * alpha),6.0,true)
	draw_arc(Vector2.ZERO,radius,0.0,TAU,42,Color(1.0,0.82,0.04,0.32 * alpha),3.2,true)
	draw_arc(Vector2.ZERO,radius,0.0,TAU,42,Color(1.0,0.97,0.32,0.96 * alpha),1.15,true)


func _spawn_yellow_impact_lines() -> void:
	if _impact_lines_spawned:
		return
	_impact_lines_spawned = true

	var rng:=RandomNumberGenerator.new()
	rng.seed = _visual_seed
	var low:int = mini(impact_line_min_count,impact_line_max_count)
	var high:int = maxi(impact_line_min_count,impact_line_max_count)
	var count:int = rng.randi_range(maxi(low,1),maxi(high,maxi(low,1)))
	var streaks:Array = []
	for index:int in range(count):
		# 黄金角打底再加随机扰动，既保证四周都有线，又让数量/角度/位置每次不同。
		var angle:float = float(index) * 2.39996323 + rng.randf_range(-0.62,0.62)
		var streak_direction:=Vector2.RIGHT.rotated(angle)
		var radial_offset:float = rng.randf_range(0.0,star_radius * 0.34)
		var tangent_offset:float = rng.randf_range(-star_radius * 0.20,star_radius * 0.20)
		var tangent:=Vector2(-streak_direction.y,streak_direction.x)
		var spawn_offset:Vector2 = streak_direction * radial_offset + tangent * tangent_offset
		var distance:float = star_radius * rng.randf_range(2.0,4.3)
		var length:float = star_radius * rng.randf_range(0.62,1.42)
		var width:float = rng.randf_range(0.52,1.05)
		var duration:float = rng.randf_range(0.19,0.31)
		var delay:float = rng.randf_range(0.0,0.045)
		var warmth:float = rng.randf_range(0.0,1.0)
		var line_color:=Color(1.0,lerpf(0.72,0.96,warmth),lerpf(0.02,0.22,warmth),0.98)
		streaks.append({
			"spawn_offset": spawn_offset,
			"direction": streak_direction,
			"distance": distance,
			"length": length,
			"width": width,
			"duration": duration,
			"delay": delay,
			"grow_end": rng.randf_range(0.22,0.34),
			"fade_in_end": rng.randf_range(0.07,0.13),
			"fade_out_start": rng.randf_range(0.46,0.62),
			"color": line_color,
		})

	var effect:Node2D = HIT_BURST_EFFECT_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "KasumiYellowImpactLines_%d" % (_visual_seed & 0x7fffffff)
	if effect.has_method("setup"):
		effect.call("setup",global_position,streaks)
	var parent:Node = get_parent()
	if parent != null:
		parent.add_child(effect,true)
	else:
		add_child(effect,true)


func _star_points(center:Vector2,outer_radius:float,rotation_value:float) -> PackedVector2Array:
	var points:=PackedVector2Array()
	var inner_radius:float = outer_radius * 0.46
	for i:int in range(10):
		var radius:float = outer_radius if (i % 2) == 0 else inner_radius
		var angle:float = rotation_value + TAU * float(i) / 10.0
		points.append(center + Vector2.RIGHT.rotated(angle) * radius)
	return points
