extends Node2D
## 轮换「一键布局」：先在地图上给蓝/红队各放一个位置（每队最多一个，再点就移动），
## 人物列表变成按顺序勾选、只有勾选的才算；再按一次，每队勾选的第 k 个人物放进
## 同一个新轮次（接在已有轮次之后），都放在该队的位置上。
## 位置和勾选只是本地界面状态，提交时交给主机统一生成。

const SIDES:Array[String] = ["left","right"]
const SIDE_COLORS:Dictionary = {"left":Color("418cff"),"right":Color("ef4f50")}
const MARKER_RADIUS:float = 9.0

var active:bool = false
var current_side:String = ""
var markers:Dictionary = {}
var checks:Dictionary = {"left":[],"right":[]}

func _init() -> void:
	name = "RotationQuickLayout"
	z_as_relative = false
	z_index = 95

func _process(_delta:float) -> void:
	if not active: return
	var world:Node = get_parent()
	var leave:bool = not Game.is_rotation_training_mode() or not is_instance_valid(world) or bool(world.get("_rotation_started"))
	if not leave and is_instance_valid(world.get("control")): leave = not world.control.is_set_team()
	if leave:
		cancel()
		if is_instance_valid(world) and is_instance_valid(world.get("control")): world.control.call_deferred("_sync_quick_layout_ui")

func begin() -> void:
	cancel()
	active = true

func cancel() -> void:
	active = false
	current_side = ""
	markers.clear()
	checks = {"left":[],"right":[]}
	queue_redraw()

func place_marker(side:String,poi:Vector2) -> void:
	if side not in SIDES: return
	markers[side] = poi
	current_side = side
	queue_redraw()

func set_side(side:String) -> void:
	if side in SIDES: current_side = side

func toggle(char_name:String) -> bool:
	if current_side not in SIDES or char_name.is_empty(): return false
	var list:Array = checks[current_side]
	if list.has(char_name): list.erase(char_name)
	else: list.append(char_name)
	queue_redraw()
	return true

func check_index(char_name:String) -> int:
	return (checks.get(current_side,[]) as Array).find(char_name)

func entries() -> Array:
	var result:Array = []
	for side:String in SIDES:
		if not markers.has(side): continue
		var poi:Vector2 = markers[side]
		var list:Array = checks[side]
		for index:int in range(list.size()):
			result.append({"side":side,"char":str(list[index]),"x":poi.x,"y":poi.y,"index":index})
	return result

func _draw() -> void:
	if not active: return
	var font:Font = ThemeDB.fallback_font
	for side:String in SIDES:
		if not markers.has(side): continue
		var poi:Vector2 = markers[side]
		var color:Color = SIDE_COLORS[side]
		var shade := Color(0,0,0,0.55)
		draw_arc(poi+Vector2(1,1),MARKER_RADIUS,0.0,TAU,32,shade,3.0)
		draw_arc(poi,MARKER_RADIUS,0.0,TAU,32,color,2.0)
		for axis:Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
			draw_line(poi+axis*(MARKER_RADIUS-3.0),poi+axis*(MARKER_RADIUS+4.0),color,2.0)
		draw_circle(poi,1.5,color)
		var count:String = str((checks[side] as Array).size())
		draw_string_outline(font,poi+Vector2(MARKER_RADIUS+3.0,-MARKER_RADIUS),count,HORIZONTAL_ALIGNMENT_LEFT,-1,10,3,shade)
		draw_string(font,poi+Vector2(MARKER_RADIUS+3.0,-MARKER_RADIUS),count,HORIZONTAL_ALIGNMENT_LEFT,-1,10,color)
