@tool
class_name PortalTiles
extends TileMapLayer
# 一个 TileMapLayer 是一组互通门。同色四邻接色块是一扇门，红蓝分组路由。
@export_enum("都通过:0","仅角色:1","仅子弹:2") var pass_mode:int = 0
@export var direct_connection:bool = false:
	set(value):
		direct_connection = value
		if Engine.is_editor_hint() and is_inside_tree(): _on_paint_changed()
# 只供旧场景读取/迁移，不显示在检查器。
@export_storage var link:Resource
@export_storage var is_exit:bool = false
var _warning_pending:bool = false
const DOOR_COLORS:Array[Color] = [Color(0.1,0.55,1.0),Color(1.0,0.18,0.25)]
const NEIGHBORS:Array[Vector2i] = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	collision_enabled = false
	navigation_enabled = false
	z_index = 5
	if tile_set == null:
		tile_set = preload("res://addons/portal_map_editor/portal_brush.tres")
	visible = Engine.is_editor_hint()
	if Engine.is_editor_hint() and not changed.is_connected(_on_paint_changed):
		changed.connect(_on_paint_changed)


func _on_paint_changed() -> void:
	# 仅笔触变化时更新提示，不做每帧同步。
	if not Engine.is_editor_hint() or _warning_pending: return
	_warning_pending = true
	call_deferred("_refresh_paint_warning")


func _refresh_paint_warning() -> void:
	_warning_pending = false
	if is_inside_tree(): update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var map:Node = get_parent()
	if map == null or not map.has_method("portal_groups"):
		return PackedStringArray(["请将本瓦片层直接放在 PortalMap 下，而不是岛屿下面。"])
	if tile_set == null or get_used_cells().is_empty(): return PackedStringArray()
	map.collect_islands()
	var doors:Array[Dictionary] = portal_doors(map)
	if doors.is_empty():
		return PackedStringArray(["当前色块没有贴合完整地图格的边界。请沿岛屿外边缘绘制，并保持岛屿与瓦片网格对齐。"])
	var warnings:PackedStringArray = PackedStringArray()
	var shadowed:Array[Dictionary] = map.shadowed_doors(self)
	if not shadowed.is_empty():
		var cells:Array = []
		for door:Dictionary in shadowed: cells.append_array(door.cells)
		warnings.append("有 %d 扇门与排在前面的传送门图层画在同一段墙上，运行时会被忽略（门只在同一图层内互传）：%s。请改画到别的墙段，或删除重复的门。" % [shadowed.size(),str(cells)])
		doors = map.active_doors(self,map.claimed_faces_before(self))
		if doors.is_empty():
			warnings.append("本图层所有门都被前面的图层占用，本图层没有任何生效的门。")
			return warnings
	if doors.size() == 1:
		var islands_touched:Dictionary = {}
		for face:Dictionary in doors[0].faces: islands_touched[face.island] = true
		if not direct_connection or islands_touched.size() < 2:
			warnings.append("当前只有一扇门，尚未连通。再画一个分开的门，或开启直连并让这扇门同时接触两片地图。")
	return warnings

func _cell_world_rect(cell:Vector2i) -> Rect2:
	var size:Vector2 = Vector2(tile_set.tile_size)
	var a:Vector2 = to_global(Vector2(cell)*size)
	var b:Vector2 = to_global(Vector2(cell+Vector2i.ONE)*size)
	return Rect2(a.min(b),(a-b).abs())

func group_color() -> Color:
	# 独立于红蓝路由标记。以层路径作种子，伪随机但重建/切换地图时不变色。
	# 不占用传送随机数，也无需增加可编辑属性。
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(get_path()) if is_inside_tree() else str(name)).hash()
	return Color.from_hsv(rng.randf(),0.72,1.0)


func portal_doors(map:Node) -> Array[Dictionary]:
	var painted:Dictionary = {}
	for cell:Vector2i in get_used_cells():
		var atlas:Vector2i = get_cell_atlas_coords(cell)
		if get_cell_source_id(cell) == 0 and atlas.y == 0 and atlas.x >= 0 and atlas.x <= 1:
			painted[cell] = atlas.x
	var ordered:Array = painted.keys()
	ordered.sort_custom(func(a:Vector2i,b:Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	var visited:Dictionary = {}
	var doors:Array[Dictionary] = []
	var tint:Color = group_color()
	for seed:Vector2i in ordered:
		if visited.has(seed): continue
		var color_id:int = painted[seed]
		var cells:Array[Vector2i] = [seed]
		visited[seed] = true
		var cursor:int = 0
		while cursor < cells.size():
			var cell:Vector2i = cells[cursor]
			cursor += 1
			for offset:Vector2i in NEIGHBORS:
				var next:Vector2i = cell+offset
				if not visited.has(next) and painted.get(next,-1) == color_id:
					visited[next] = true
					cells.append(next)
		var faces:Array[Dictionary] = _component_faces(map,cells)
		if faces.is_empty(): continue
		doors.append({"id":doors.size(),"color_id":color_id,"color":tint,"faces":faces,"cells":cells})
	return doors

func _component_faces(map:Node,cells:Array[Vector2i]) -> Array[Dictionary]:
	var intervals:Dictionary = {}
	var templates:Dictionary = {}
	for cell:Vector2i in cells:
		var tile:Rect2 = _cell_world_rect(cell)
		for name:Variant in map.islands.keys():
			var rect:Rect2 = map.island_rect(str(name))
			for edge:Dictionary in map.island_edges(str(name)):
				var side:int = edge.side
				var at:float = [tile.end.x,tile.position.x,tile.end.y,tile.position.y][side]
				if absf(at-float(edge.line)) >= 0.05: continue
				var a:float = maxf(float(edge.a),tile.position.y if side < 2 else tile.position.x)
				var b:float = minf(float(edge.b),tile.end.y if side < 2 else tile.end.x)
				var step:float = map.edge_cell_size(str(name),side)
				if b-a < step-0.05: continue
				var key:String = "%s|%d|%.4f" % [name,side,float(edge.line)]
				if not intervals.has(key):
					intervals[key] = []
					templates[key] = {"island":str(name),"side":side,"line":float(edge.line)}
				intervals[key].append(Vector2(a,b))
	var result:Array[Dictionary] = []
	var keys:Array = intervals.keys()
	keys.sort()
	for key:String in keys:
		var spans:Array = intervals[key]
		spans.sort_custom(func(a:Vector2,b:Vector2) -> bool: return a.x < b.x)
		var merged:Array[Vector2] = []
		for span:Vector2 in spans:
			if not merged.is_empty() and span.x <= merged.back().y+0.01:
				merged[merged.size()-1].y = maxf(merged.back().y,span.y)
			else: merged.append(span)
		for span:Vector2 in merged:
			var face:Dictionary = templates[key].duplicate()
			face["a"] = span.x
			face["b"] = span.y
			result.append(face)
	return result

func seed_legacy(map:Node,legacy:Resource) -> void:
	var spans:Dictionary = map.resolved_link_spans(map.links.find(legacy))
	if spans.is_empty(): return
	for color_id:int in range(2):
		var desc:Dictionary = spans["from" if color_id == 0 else "to"]
		var rect:Rect2 = map.island_rect(desc.island)
		var side:int = desc.side
		var step:float = map.edge_cell_size(desc.island,side)
		var u:float = float(desc.a)+step*0.5
		while u < float(desc.b):
			var point:Vector2
			match side:
				0: point = Vector2(rect.position.x-step*0.5,u)
				1: point = Vector2(rect.end.x+step*0.5,u)
				2: point = Vector2(u,rect.position.y-step*0.5)
				3: point = Vector2(u,rect.end.y+step*0.5)
			set_cell(local_to_map(to_local(point)),0,Vector2i(color_id,0))
			u += step
