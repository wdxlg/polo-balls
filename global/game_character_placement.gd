extends RefCounted
## 左键放置 / 长按框选批量放置人物与 Ghost 预览
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node


func _init(game: Node) -> void:
	_game = game


# 长按左键框选放置：覆盖层只画屏幕空间矩形，实际生成点仍使用世界坐标。
const PLACEMENT_BOX_OVERLAY_SCRIPT = preload("res://scripts/ui/placement_box_overlay.gd")

const PLACEMENT_BOX_HOLD_TIME:float = 0.30

const PLACEMENT_BOX_GRID_SPACING:float = 30.0

const PLACEMENT_BOX_MIN_MULTI_SPAN:float = 20.0

const PLACEMENT_BOX_MAX_CHARACTERS:int = 256

var mouse_poi:Vector2 = Vector2.ZERO

var ghost_ball

# 单击放置现在在“松开左键”时确认；按住超过阈值后切换为框选模式。
var _placement_press_active:bool = false

var _placement_box_mode:bool = false

var _placement_hold_elapsed:float = 0.0

var _placement_press_screen:Vector2 = Vector2.ZERO

var _placement_current_screen:Vector2 = Vector2.ZERO

var _placement_press_world:Vector2 = Vector2.ZERO

var _placement_current_world:Vector2 = Vector2.ZERO

var _placement_team:String = ""

var _placement_character:String = ""

var _placement_overlay:Control = null


func _position_inside_current_map(world:World,position:Vector2) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	var border:Dictionary = world.return_now_map_border()
	var start:Vector2 = border.get("start",Vector2.ZERO)
	var end:Vector2 = border.get("end",Vector2.ZERO)
	return position.x > start.x and position.x < end.x and position.y > start.y and position.y < end.y


func _position_inside_character_placement_area(world:World,position:Vector2) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	# World 提供一个专门的“地图外自动回拉测试带”。它与 mouse_in_map 分离，
	# 因此手动攻击、地图内判定等系统仍只认黑线内部。
	if world.has_method("can_place_character_at"):
		return bool(world.call("can_place_character_at",position))
	return _position_inside_current_map(world,position)


func _begin_placement_press(world:World,screen_position:Vector2) -> void:
	_cancel_placement_press()
	if world == null or not is_instance_valid(world):
		return
	var character_name:String = (
		"random"
		if world.now_choose_char == "" and bool(_game.Game_Settings.get("Set_Random_Char_When_Didnt_Choose",true))
		else world.now_choose_char
	)
	if character_name.is_empty():
		return
	_placement_press_active = true
	_placement_box_mode = false
	_placement_hold_elapsed = 0.0
	_placement_press_screen = screen_position
	_placement_current_screen = screen_position
	_placement_press_world = world.get_global_mouse_position()
	_placement_current_world = _placement_press_world
	_placement_team = world.now_choose_team
	_placement_character = character_name


func _ensure_placement_box_overlay(world:World) -> void:
	if is_instance_valid(_placement_overlay):
		return
	if world == null or not is_instance_valid(world):
		return
	var canvas_layer:Node = world.get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return
	var overlay_variant:Variant = PLACEMENT_BOX_OVERLAY_SCRIPT.new()
	if overlay_variant is not Control:
		return
	_placement_overlay = overlay_variant as Control
	_placement_overlay.name = "CharacterPlacementSelection"
	canvas_layer.add_child(_placement_overlay)


func _update_placement_box_overlay(world:World) -> void:
	if not _placement_press_active or not _placement_box_mode:
		return
	_ensure_placement_box_overlay(world)
	if is_instance_valid(_placement_overlay) and _placement_overlay.has_method("set_selection_points"):
		_placement_overlay.call("set_selection_points",_placement_press_screen,_placement_current_screen)
	# 蓝框左上角显示“横向个数x纵向个数”，与真正落子的网格算法保持同一份计算。
	if is_instance_valid(_placement_overlay) and _placement_overlay.has_method("set_grid_counts"):
		var counts:Vector2i = _box_placement_grid_counts(world,_placement_press_world,_placement_current_world)
		_placement_overlay.call("set_grid_counts",counts.x,counts.y)


func _cancel_placement_press() -> void:
	_placement_press_active = false
	_placement_box_mode = false
	_placement_hold_elapsed = 0.0
	_placement_team = ""
	_placement_character = ""
	if is_instance_valid(_placement_overlay) and _placement_overlay.has_method("clear_selection"):
		_placement_overlay.call("clear_selection")


func _spawn_placed_character(world:World,team_name:String,character_name:String,position:Vector2) -> void:
	if world == null or not is_instance_valid(world) or character_name.is_empty():
		return
	if not _game.is_multiplayer_authority():
		_game.create_ball_in_server.rpc_id(_game.Server_Id,team_name,character_name,position,world.rotation_selected_round)
	else:
		_game.create_ball_in_server(team_name,character_name,position,world.rotation_selected_round)


# 把框选区域夹到可放置范围内，返回 [min_x,min_y,max_x,max_y]；范围无效时返回空数组。
func _box_placement_clamped_span(world:World,from_world:Vector2,to_world:Vector2) -> PackedFloat64Array:
	if world == null or not is_instance_valid(world):
		return PackedFloat64Array()

	# 框选放置也允许进入地图外测试带，但不会无限扩到整个屏幕。
	# 优先使用 World 给出的扩展 bounds；老版本 World 则退回黑线内部。
	var placement_bounds:Rect2 = Rect2()
	if world.has_method("return_character_placement_test_bounds"):
		var bounds_variant:Variant = world.call("return_character_placement_test_bounds")
		if bounds_variant is Rect2:
			placement_bounds = bounds_variant
	if placement_bounds.size.x <= 0.0 or placement_bounds.size.y <= 0.0:
		var border:Dictionary = world.return_now_map_border()
		var fallback_start:Vector2 = border.get("start",Vector2.ZERO)
		var fallback_end:Vector2 = border.get("end",Vector2.ZERO)
		placement_bounds = Rect2(fallback_start,fallback_end - fallback_start)
	var map_start:Vector2 = placement_bounds.position
	var map_end:Vector2 = placement_bounds.end
	var min_x:float = clampf(minf(from_world.x,to_world.x),map_start.x,map_end.x)
	var max_x:float = clampf(maxf(from_world.x,to_world.x),map_start.x,map_end.x)
	var min_y:float = clampf(minf(from_world.y,to_world.y),map_start.y,map_end.y)
	var max_y:float = clampf(maxf(from_world.y,to_world.y),map_start.y,map_end.y)
	if max_x < min_x:
		var swap_x:float = min_x
		min_x = max_x
		max_x = swap_x
	if max_y < min_y:
		var swap_y:float = min_y
		min_y = max_y
		max_y = swap_y
	return PackedFloat64Array([min_x,min_y,max_x,max_y])


# 框选网格的横向/纵向个数（含 256 上限收敛），蓝框上的“几x几”文本与实际生成完全一致。
func _box_placement_grid_counts(world:World,from_world:Vector2,to_world:Vector2) -> Vector2i:
	var span:PackedFloat64Array = _box_placement_clamped_span(world,from_world,to_world)
	if span.size() < 4:
		return Vector2i.ONE
	var span_x:float = span[2] - span[0]
	var span_y:float = span[3] - span[1]
	var count_x:int = 1
	var count_y:int = 1
	if span_x >= PLACEMENT_BOX_MIN_MULTI_SPAN:
		count_x = maxi(2,roundi(span_x / PLACEMENT_BOX_GRID_SPACING) + 1)
	if span_y >= PLACEMENT_BOX_MIN_MULTI_SPAN:
		count_y = maxi(2,roundi(span_y / PLACEMENT_BOX_GRID_SPACING) + 1)

	# 极大的框仍然保持规则网格，但限制一次性实例化数量，避免误拖把主线程卡死。
	while count_x * count_y > PLACEMENT_BOX_MAX_CHARACTERS:
		if count_x >= count_y and count_x > 1:
			count_x -= 1
		elif count_y > 1:
			count_y -= 1
		else:
			break
	return Vector2i(count_x,count_y)


func _box_placement_points(world:World,from_world:Vector2,to_world:Vector2) -> Array[Vector2]:
	var points:Array[Vector2] = []
	var span:PackedFloat64Array = _box_placement_clamped_span(world,from_world,to_world)
	if span.size() < 4:
		return points
	var min_x:float = span[0]
	var min_y:float = span[1]
	var max_x:float = span[2]
	var max_y:float = span[3]
	var counts:Vector2i = _box_placement_grid_counts(world,from_world,to_world)
	var count_x:int = counts.x
	var count_y:int = counts.y

	for row:int in range(count_y):
		var y:float = (min_y + max_y) * 0.5 if count_y == 1 else lerpf(min_y,max_y,float(row) / float(count_y - 1))
		for column:int in range(count_x):
			var x:float = (min_x + max_x) * 0.5 if count_x == 1 else lerpf(min_x,max_x,float(column) / float(count_x - 1))
			var point := Vector2(x,y)
			# grow() 的四个角可能超过真实救援半径，最终再按 World 的
			# can_place_character_at() 过滤，确保每个地图外点都能自动拉回。
			if _position_inside_character_placement_area(world,point):
				points.append(point)
	return points


func _finalize_placement_press(world:World) -> void:
	if not _placement_press_active:
		return
	var was_box_mode:bool = _placement_box_mode
	var team_name:String = _placement_team
	var character_name:String = _placement_character
	var start_world:Vector2 = _placement_press_world
	var end_world:Vector2 = _placement_current_world
	_cancel_placement_press()

	if world == null or not is_instance_valid(world) or not world.return_can_create_char():
		return
	if was_box_mode:
		for point:Vector2 in _box_placement_points(world,start_world,end_world):
			_spawn_placed_character(world,team_name,character_name,point)
	elif _position_inside_character_placement_area(world,end_world):
		_spawn_placed_character(world,team_name,character_name,end_world)
