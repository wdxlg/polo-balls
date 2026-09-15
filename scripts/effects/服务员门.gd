extends Node2D

# 服务员开门的视觉节点。
# 真实墙体缺口 / 穿墙权限由 World 管理；这里负责：
# 1. 单扇黑色门叶从一侧铰链向地图外打开；
# 2. 门洞内侧显示与场景 Background 一致的蓝色方块。

var door_width:float = 36.0
var outward:Vector2 = Vector2.UP
var tangent:Vector2 = Vector2.RIGHT
# +1 表示铰链在 -tangent 一侧，门叶关闭时朝 +tangent 延伸；-1 相反。
var hinge_sign:float = 1.0
var line_width:float = 1.6
var inner_fill_color:Color = Color(0.0,0.5882353,0.87058824,1.0)
var inner_fill_depth:float = 36.0
var open_progress:float = 0.0:
	set(v):
		open_progress = clampf(v,0.0,1.0)
		queue_redraw()

var _active_tween:Tween = null
var _inner_fill:Polygon2D = null


func configure(
	center:Vector2,
	outward_normal:Vector2,
	width:float,
	open_duration:float,
	border_width:float = 1.0,
	single_hinge_sign:float = 1.0,
	background_color:Color = Color(0.0,0.5882353,0.87058824,1.0),
	fill_depth:float = -1.0
) -> void:
	global_position = center
	outward = outward_normal.normalized()
	if outward.length_squared() <= 0.000001:
		outward = Vector2.UP
	tangent = Vector2(-outward.y,outward.x).normalized()
	hinge_sign = 1.0 if single_hinge_sign >= 0.0 else -1.0
	door_width = maxf(width,8.0)
	line_width = maxf(border_width * 1.55,1.4)
	inner_fill_color = background_color
	# 用户要的是“方块”，默认深度直接等于门宽。
	inner_fill_depth = door_width if fill_depth <= 0.0 else maxf(fill_depth,4.0)
	open_progress = 0.0
	_ensure_inner_fill()
	_refresh_inner_fill()
	queue_redraw()
	_play_to(1.0,maxf(open_duration,0.05),Tween.EASE_OUT)


func close(close_duration:float) -> void:
	_play_to(0.0,maxf(close_duration,0.05),Tween.EASE_IN_OUT)


func _play_to(target:float,duration:float,ease_type:Tween.EaseType) -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(ease_type)
	_active_tween.tween_property(self,"open_progress",target,duration)


func _ensure_inner_fill() -> void:
	if _inner_fill != null and is_instance_valid(_inner_fill):
		return
	_inner_fill = Polygon2D.new()
	_inner_fill.name = "DoorInnerBackground"
	# WaiterDoor 本身在地图黑线层（z=100）。把蓝块放到它后面、普通角色前的
	# 背景层附近：父 z(100) + 子 z(-101) = 相对 World 的 -1。
	# World 自身为 -2 时最终约 -3，正好处于 Background 与角色之间。
	_inner_fill.z_index = -101
	_inner_fill.show_behind_parent = true
	add_child(_inner_fill)


func _refresh_inner_fill() -> void:
	if _inner_fill == null or not is_instance_valid(_inner_fill):
		return
	var half:float = door_width * 0.5
	var inward:Vector2 = -outward
	_inner_fill.color = inner_fill_color
	# 一条边贴着墙线，整个方块只朝地图内部延伸。
	_inner_fill.polygon = PackedVector2Array([
		-tangent * half,
		tangent * half,
		tangent * half + inward * inner_fill_depth,
		-tangent * half + inward * inner_fill_depth,
	])


func _draw() -> void:
	# 单扇门：整段门宽由一片门叶覆盖。铰链固定在门洞的一侧，
	# 关闭时门叶沿地图黑线封住整个缺口，打开时向地图外旋转约 90°。
	var half:float = door_width * 0.5
	var hinge:Vector2 = -tangent * half * hinge_sign
	var closed_dir:Vector2 = tangent * hinge_sign
	var target_dir:Vector2 = outward
	var t:float = smoothstep(0.0,1.0,open_progress)
	var turn_angle:float = closed_dir.angle_to(target_dir)
	var leaf_dir:Vector2 = closed_dir.rotated(turn_angle * t).normalized()

	draw_line(hinge,hinge + leaf_dir * door_width,Color.BLACK,line_width,true)
	draw_circle(hinge,maxf(line_width * 0.9,1.0),Color.BLACK)
