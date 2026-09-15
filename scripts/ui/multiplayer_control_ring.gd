extends Node2D

# V279：多人控制圈。
# - 紧贴人物脚底影子外沿。
# - 大间隔黄色发光虚线；每段之间保留明确空白，光晕也不跨段粘连。
# - 动画不是旋转 Node2D，而是虚线“相位”沿椭圆周长非常缓慢地循环。
# - 遮挡不再依赖错误的绝对 z=-1：Game 会把圈放到受控人物同一父节点、
#   同一最终 Z，并在场景树顺序上紧挨着放到人物之前，因此地图先画、圈再画、人物最后画。
var ring_radii:Vector2 = Vector2(18.0,10.0)
var local_owner:bool = false
var _dash_phase:float = 0.0
var _glow_phase:float = 0.0

const DASH_COUNT:int = 16
const DASH_FRACTION:float = 0.22
const DASH_CYCLE_SPEED:float = 0.08 # 每秒绕完整圆周的比例；约12.5秒轮回一圈，不旋转节点。

func _ready() -> void:
	# V279：最终 Z 与目标人物保持一致，真正的前后关系由 Game 把本节点
	# 放在目标人物前一个场景树位置来保证。不要再使用绝对 z=-1。
	z_as_relative = true
	z_index = 0
	set_process(true)
	queue_redraw()

func configure(radii_value:Vector2,is_local_owner:bool) -> void:
	var new_radii := Vector2(maxf(radii_value.x,4.0),maxf(radii_value.y,4.0))
	if new_radii.distance_to(ring_radii) > 0.05 or local_owner != is_local_owner:
		ring_radii = new_radii
		local_owner = is_local_owner
		queue_redraw()

func _process(delta:float) -> void:
	var safe_delta:float = maxf(delta,0.0)
	_dash_phase = fmod(_dash_phase + safe_delta * TAU * DASH_CYCLE_SPEED,TAU)
	_glow_phase = fmod(_glow_phase + safe_delta * 0.82,TAU)
	queue_redraw()

func _ellipse_arc_points(start_angle:float,end_angle:float,steps:int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count:int = maxi(steps,3)
	for i:int in range(count + 1):
		var t:float = float(i) / float(count)
		var angle:float = lerpf(start_angle,end_angle,t)
		points.append(Vector2(cos(angle)*ring_radii.x,sin(angle)*ring_radii.y))
	return points

func _draw() -> void:
	# V279：16 个槽位，每段只占 22%，也就是每格 78% 都是明确空隙。
	# 相比 V278 的 24×34%，段数更少、段更短，肉眼能稳定看出“虚线”而不是近似实线。
	var cell_angle:float = TAU / float(DASH_COUNT)
	var dash_angle:float = cell_angle * DASH_FRACTION
	var pulse:float = 0.5 + 0.5 * sin(_glow_phase)
	var brightness:float = 1.0 if local_owner else 0.82
	var core := Color(1.0,0.84 + 0.10*pulse,0.03,0.98*brightness)
	var glow_mid := Color(1.0,0.70,0.0,(0.19 + pulse*0.06)*brightness)
	var glow_outer := Color(1.0,0.58,0.0,(0.055 + pulse*0.025)*brightness)

	for index:int in range(DASH_COUNT):
		var center_angle:float = _dash_phase + cell_angle * float(index)
		var start_angle:float = center_angle - dash_angle*0.5
		var end_angle:float = center_angle + dash_angle*0.5
		var points:PackedVector2Array = _ellipse_arc_points(start_angle,end_angle,3)
		# 光晕宽度压小，避免相邻虚线的 glow 互相盖住。
		draw_polyline(points,glow_outer,3.4,true)
		draw_polyline(points,glow_mid,2.0,true)
		draw_polyline(points,core,1.05,true)
