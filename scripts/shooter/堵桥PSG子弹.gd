extends "res://scripts/shooter/子弹.gd"

# V100：堵桥从地图外开枪时，子弹先忽略 layer1 地图/安全墙。
# 子弹中心第一次真正进入当前地图矩形后，立刻恢复原 layer1 mask，
# 所以它只“穿入边界”，进入地图后仍会被内部墙体正常挡住。

var _bridge_boundary_pass_active:bool = false
var _bridge_original_wall_mask:bool = true
var _bridge_original_z_index:int = 0


func _ready()->void:
	super._ready()
	if not bool(get_meta(&"bridge_pass_map_boundary",false)):
		return
	var rect:Rect2 = _bridge_current_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	if rect.has_point(global_position):
		return
	_bridge_boundary_pass_active = true
	_bridge_original_wall_mask = get_collision_mask_value(1)
	_bridge_original_z_index = z_index
	set_collision_mask_value(1,false)
	# 地图外视觉遮罩 z=90；让技能子弹在穿入边界前也能被看见，仍低于地图边线 z=100。
	z_index = 95


func move(speed:float,delta:float):
	super.move(speed,delta)
	if not _bridge_boundary_pass_active or not is_instance_valid(self):
		return
	var rect:Rect2 = _bridge_current_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	# 不在刚跨过黑线的一瞬间就恢复：安全墙本身有厚度，子弹碰撞体也有半径。
	# 等中心进入地图约 14px 后再恢复，避免下一物理帧因为仍与边界墙重叠而被错误销毁。
	var safe_rect:Rect2 = rect.grow(-14.0)
	var safely_inside:bool = safe_rect.size.x > 2.0 and safe_rect.size.y > 2.0 and safe_rect.has_point(global_position)
	if safely_inside:
		_bridge_boundary_pass_active = false
		set_collision_mask_value(1,_bridge_original_wall_mask)
		z_index = _bridge_original_z_index


func _bridge_current_map_rect()->Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var maps:Variant = world.get("map_group")
	var map_name:Variant = world.get("now_choose_map")
	if not maps is Dictionary:
		return Rect2()
	var map_dict:Dictionary = maps as Dictionary
	var key:String = str(map_name)
	if not map_dict.has(key):
		return Rect2()
	var map_node:Variant = map_dict[key]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.call("return_map_world_rect",map_node) as Rect2
