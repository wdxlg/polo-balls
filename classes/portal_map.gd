@tool
class_name PortalMap
extends Node2D

# 原生 TileMap 传送门组：仅通行类型与直接连通两项设置。
# 门=同色四邻接格；有红蓝则异色随机，单色则随机到其他门。
# 单门仅在开启直连并贴着两个不同岛时生效。组间互不连通。
# 旧 PortalLink 属性仅保留为隐藏迁移数据。

const Geometry = preload("res://classes/map_tile_geometry.gd")
const MC_AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const SIDE_NORMALS:Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const TRANSIT_COOLDOWN_MSEC:int = 150
const ARRIVAL_CLEARANCE:float = 2.0
const META_COOLDOWN:StringName = &"portal_cooldown_until_msec"
const MAX_BURSTS_PER_FRAME:int = 6
const BLOCKED_EFFECT_INTERVAL_MSEC:int = 180
const FALLBACK_CELL:Vector2 = Vector2(16.0,16.0)

@export_storage var links:Array[PortalLink] = []

# 门所在的墙留出一块“空洞”：墙体纹理被遮住，只剩地图外的虚空。
var carve_void:bool = true
# 空腔深度（方块数）。1 = 只挖掉最外圈那一层墙。
var void_depth_tiles:float = 1.0
var void_color:Color = Color(0.016,0.024,0.055,1.0)
# 空腔里由开口向内的彩色渐变强度（颜色取门的通行模式配色），0 表示纯黑。
var void_glow:float = 0.5
# 黑色边线在缺口处折进空腔，沿空腔两侧的墙延伸（与地图黑线同粗细）。
var notch_outline:bool = true

var portal_particles:bool = true
var particle_color:Color = Color(0.42,0.72,1.0,1.0)
# true 时粒子改用每条连接自己的颜色（青=都可、绿=仅角色、橙=仅子弹）。
var particles_use_gate_color:bool = true
var particles_per_gate:int = 24
var particle_speed:float = 28.0
var particle_lifetime:float = 0.85

# 在缺口处再画一条彩色门线（默认关闭：缺口本身已经足够明显）。
var show_portal_lines:bool = true
# 门线比黑色地图边线粗多少像素。
var line_extra_width:float = 0.0
var transit_effects:bool = true
# 被通行模式挡下的物体撞门时，在门口闪一圈提示。
var blocked_feedback:bool = true
# 门线 / 空腔渐变呼吸明暗幅度，0 表示不呼吸。
var pulse_strength:float = 0.35

var islands:Dictionary = {}          # name -> TileMapLayer
var _island_regions:Dictionary = {}
var _island_edges:Dictionary = {}
var _island_rects:Dictionary = {}    # name -> Rect2（世界坐标）
var _gates:Array[Dictionary] = []
var _portal_rng:RandomNumberGenerator = RandomNumberGenerator.new()
var _active:bool = false
var _visual_root:Node2D = null
var _particle_root:Node2D = null
var _particle_clips:Dictionary = {}
var _particle_budget:int = 256
var _particle_face_limit:int = 24
var _particle_ramp:Gradient
var _particle_scale_curve:Curve
var _void_root:Node2D = null
var _drawn_notch_segments:Dictionary = {}
var _gate_visuals:Dictionary = {}    # key -> Array[Line2D]
var _blocked_last:Dictionary = {}    # key -> msec
var _pulse_time:float = 0.0
var _border_width:float = 2.0
var _border_inset:float = 1.0
var _border_antialiased:bool = true
var _burst_budget:int = 0
var _pulse_nodes:Array[CanvasItem] = []
var _wall_carving:bool = true
# 被通行模式挡下的次数（调试 / 回归测试用）。
var blocked_event_count:int = 0


func _ready() -> void:
	_portal_rng.randomize()
	collect_islands()
	if not Engine.is_editor_hint():
		_ensure_editor_gate_nodes()
	if Engine.is_editor_hint():
		# 编辑器中不要把岛隐藏起来，也不生成运行时视觉；画布手柄由插件绘制。
		set_process(false)
		call_deferred("_ensure_editor_gate_nodes")
		set_physics_process(false)
		return
	for layer:TileMapLayer in islands.values():
		layer.visible = false
		layer.collision_enabled = false
		layer.navigation_enabled = false
	set_process(false)
	set_physics_process(false)


func _process(delta:float) -> void:
	if Engine.is_editor_hint():
		return
	if _pulse_nodes.is_empty():
		return
	_pulse_time += delta
	var factor:float = 1.0 - pulse_strength * 0.5 + pulse_strength * 0.5 * sin(_pulse_time * 4.0)
	var color:Color = Color(1.0,1.0,1.0,clampf(factor,0.0,1.0))
	for node:CanvasItem in _pulse_nodes:
		if node == null or not is_instance_valid(node):
			continue
		node.modulate = color


#========================================================
# 岛屿 / 几何
#========================================================
func portal_groups() -> Array[TileMapLayer]:
	var result:Array[TileMapLayer] = []
	for child:Node in get_children():
		if child is TileMapLayer and child.has_method("portal_doors"):
			result.append(child as TileMapLayer)
	return result


func _ensure_editor_gate_nodes() -> void:
	# 打开旧场景时一次性迁移；不轮询、不重绘，也不保留可编辑的入口/出口属性。
	if links.is_empty(): return
	collect_islands()
	for legacy:PortalLink in links:
		if legacy == null: continue
		var group:TileMapLayer = load("res://addons/portal_map_editor/portal_tiles.gd").new()
		group.name = "Portal_Group_%d" % (links.find(legacy)+1)
		group.set("pass_mode",int(legacy.pass_mode))
		add_child(group,true)
		group.owner = owner if owner != null else self
		var copied:bool = false
		for island:TileMapLayer in islands.values():
			for child:Node in island.get_children():
				if child is TileMapLayer and child.get_script() != null and child.get_script().resource_path == "res://addons/portal_map_editor/portal_tiles.gd" and child.get("link") == legacy:
					var old:TileMapLayer = child as TileMapLayer
					var color_id:int = 1 if bool(child.get("is_exit")) else 0
					for cell:Vector2i in old.get_used_cells():
						group.set_cell(group.local_to_map(group.to_local(old.to_global(old.map_to_local(cell)))),0,Vector2i(color_id,0))
					copied = true
					island.remove_child(old)
					old.queue_free()
		if not copied: group.call("seed_legacy",self,legacy)
	for child:Node in get_children():
		if child.get_script() != null and child.get_script().resource_path == "res://addons/portal_map_editor/portal_gate_node.gd":
			remove_child(child)
			child.queue_free()
	links = []


func collect_islands() -> void:
	islands.clear()
	for c:Node in get_children():
		if c is TileMapLayer and not c.has_method("portal_doors"):
			Geometry.invalidate(c)
			islands[str(c.name)] = c
	_refresh_island_rects()


func _refresh_island_rects() -> void:
	_island_rects.clear()
	_island_regions.clear()
	_island_edges.clear()
	for island_name:Variant in islands.keys():
		var layer:TileMapLayer = islands[island_name]
		if layer == null or not is_instance_valid(layer):
			continue
		_island_rects[str(island_name)] = layer_world_rect(layer)
		var shape:Dictionary = Geometry.from_layer(layer)
		_island_regions[str(island_name)] = shape.regions
		_island_edges[str(island_name)] = Geometry.edges(shape.regions)


static func layer_world_rect(layer:TileMapLayer) -> Rect2:
	if layer == null or not is_instance_valid(layer) or layer.tile_set == null:
		return Rect2()
	var rect:Rect2i = layer.get_used_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2(layer.global_position,Vector2.ZERO)
	var tile_size:Vector2 = Vector2(layer.tile_set.tile_size)
	var local_min:Vector2 = Vector2(rect.position) * tile_size
	var local_max:Vector2 = Vector2(rect.end) * tile_size
	var corners:PackedVector2Array = PackedVector2Array([
		layer.to_global(local_min),
		layer.to_global(Vector2(local_max.x,local_min.y)),
		layer.to_global(local_max),
		layer.to_global(Vector2(local_min.x,local_max.y)),
	])
	var min_p:Vector2 = corners[0]
	var max_p:Vector2 = corners[0]
	for p:Vector2 in corners:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return Rect2(min_p,max_p - min_p)


func island_entries() -> Array[Dictionary]:
	_refresh_island_rects()
	var result:Array[Dictionary] = []
	var names:Array = islands.keys()
	names.sort()
	for island_name:Variant in names:
		var layer:TileMapLayer = islands[island_name]
		if layer == null or not is_instance_valid(layer):
			continue
		result.append({
			"name": str(island_name),
			"layer": layer,
			"rect": _island_rects.get(str(island_name),Rect2()),
		})
	return result


func island_regions(island_name:String) -> Array[Rect2]:
	var regions:Array[Rect2] = []
	regions.assign(_island_regions.get(island_name,[]))
	return regions

func island_edges(island_name:String) -> Array:
	return _island_edges.get(island_name,[])

func _face_point(desc:Dictionary,u:float) -> Vector2:
	if desc.has("line"): return Geometry.point(desc,u)
	return _edge_point(island_rect(str(desc.island)),int(desc.side),u)

func island_rect(island_name:String) -> Rect2:
	if not _island_rects.has(island_name):
		_refresh_island_rects()
	return _island_rects.get(island_name,Rect2())


func primary_island() -> TileMapLayer:
	var names:Array = islands.keys()
	if names.is_empty():
		return null
	names.sort()
	return islands[names[0]]


func world_rect() -> Rect2:
	_refresh_island_rects()
	var merged:Rect2 = Rect2()
	var first:bool = true
	for rect:Rect2 in _island_rects.values():
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if first:
			merged = rect
			first = false
		else:
			merged = merged.merge(rect)
	return merged


func island_at(p:Vector2) -> String:
	for island_name:Variant in _island_rects.keys():
		if Geometry.contains(_island_regions.get(island_name,[]),p):
			return str(island_name)
	return ""


func contains_point(p:Vector2) -> bool:
	return not island_at(p).is_empty()


# 一格方块在世界里的尺寸（岛有缩放时按缩放折算），供空腔深度 / 手柄对齐使用。
func cell_size(island_name:String = "") -> Vector2:
	var layer:TileMapLayer = islands.get(island_name) if islands.has(island_name) else primary_island()
	if layer == null or not is_instance_valid(layer) or layer.tile_set == null:
		return FALLBACK_CELL
	var tile:Vector2 = Vector2(layer.tile_set.tile_size)
	var scale_xy:Vector2 = Vector2(
		layer.global_transform.x.length(),
		layer.global_transform.y.length()
	)
	return Vector2(
		maxf(tile.x * maxf(scale_xy.x,0.01),1.0),
		maxf(tile.y * maxf(scale_xy.y,0.01),1.0)
	)


#========================================================
# 激活 / 门几何
#========================================================
func set_active(active:bool) -> void:
	_active = active
	for layer:TileMapLayer in islands.values():
		if layer == null or not is_instance_valid(layer):
			continue
		layer.visible = false
		# 与普通 TileMapLayer 地图保持一致（见 World._sync_selected_map_visibility）：
		# 画出来的格子只是地面，墙体全部由 World 按“暴露边”生成的安全墙提供。
		# 瓦片自带的边框物理条经自动地形铺贴后会在非矩形岛的凹角落到地面内部，
		# 一旦启用就会在空地上出现看不见的碰撞，所以这里永远保持关闭。
		layer.collision_enabled = false
		layer.navigation_enabled = active
	if active:
		rebuild_gates()
		refresh_visuals(_border_width,_border_inset,_border_antialiased)
	else:
		_clear_visuals()
	set_process(active and not _gates.is_empty() and not Engine.is_editor_hint())


func is_active() -> bool:
	return _active


# World 在刷新表现时告诉 PortalMap：这张地图的边墙是不是“看得见的方块墙”
# （草方块地图的木墙 / 石砖地图的砖墙……）。只有看得见的墙才需要在门口挖空腔。
func set_wall_carving(enabled:bool) -> void:
	_wall_carving = enabled


# 空腔外沿相对物理边的偏移（正 = 向岛外）：取黑线外缘再外扩 1px，
# 保证木墙整圈方块、纯色地图最外一圈砖都被完整盖住。
func _void_outer_offset() -> float:
	return maxf(0.0,-_border_inset - maxf(_border_width,0.0) * 0.5)


static func _edge_axis_span(rect:Rect2,side:int) -> Vector2:
	return Vector2(rect.position.y,rect.end.y) if side < 2 else Vector2(rect.position.x,rect.end.x)


static func _edge_point(rect:Rect2,side:int,u:float) -> Vector2:
	match side:
		PortalLink.Edge.LEFT:
			return Vector2(rect.position.x,u)
		PortalLink.Edge.RIGHT:
			return Vector2(rect.end.x,u)
		PortalLink.Edge.TOP:
			return Vector2(u,rect.position.y)
		_:
			return Vector2(u,rect.end.y)


static func _edge_tangent(side:int) -> Vector2:
	return Vector2.DOWN if side < 2 else Vector2.RIGHT


static func _edge_scalar(p:Vector2,side:int) -> float:
	return p.y if side < 2 else p.x


static func _resolve_span(rect:Rect2,side:int,whole:bool,offset:float,length:float,step:float = 1.0) -> Vector2:
	var span:Vector2 = _edge_axis_span(rect,side)
	if whole:
		return span
	var total:float = span.y - span.x
	var size:float = clampf(roundf(length / step) * step,minf(step,total),total)
	var a:float = span.x + clampf(roundf(offset / step) * step,0.0,total - size)
	var b:float = a + size
	return Vector2(a,b)


# 某条连接解析出来的两条边段（含岛名 / 边 / 起止坐标，世界坐标）。
# 编辑器与 rebuild_gates 共用，保证手柄位置与实际传送范围完全一致。
func edge_cell_size(island_name:String,side:int) -> float:
	var cell:Vector2 = cell_size(island_name)
	return cell.y if side < 2 else cell.x


func resolved_link_spans(index:int) -> Dictionary:
	if index < 0 or index >= links.size():
		return {}
	var link:PortalLink = links[index]
	if link == null:
		return {}
	_refresh_island_rects()
	if not _island_rects.has(link.from_island) or not _island_rects.has(link.to_island):
		return {}
	var ra:Rect2 = _island_rects[link.from_island]
	var rb:Rect2 = _island_rects[link.to_island]
	var span_a:Vector2 = _resolve_span(ra,link.from_side,link.whole_edge,link.from_offset,link.from_length,edge_cell_size(link.from_island,link.from_side))
	var to_length:float = link.to_length if link.to_length > 0.0 else link.from_length
	var to_offset:float = link.to_offset if link.to_length > 0.0 else link.from_offset
	var span_b:Vector2 = _resolve_span(rb,link.to_side,link.whole_edge,to_offset,to_length,edge_cell_size(link.to_island,link.to_side))
	return {
		"from": {"island":link.from_island,"side":int(link.from_side),"a":span_a.x,"b":span_a.y},
		"to": {"island":link.to_island,"side":int(link.to_side),"a":span_b.x,"b":span_b.y},
		"color": link.resolved_color(),
		"mode": int(link.pass_mode),
	}


func rebuild_gates() -> void:
	_gates.clear()
	_refresh_island_rects()
	# 一段墙面只属于最先（子节点顺序）画到它的图层：后面的图层即使也画了同一格，
	# 那扇门整体作废，既不做入口也不做同层其它门的目的地，保证门只在自己图层内互传。
	var claimed:Array[Dictionary] = []
	for group:TileMapLayer in portal_groups():
		var doors:Array = active_doors(group,claimed)
		for door:Dictionary in doors:
			for face:Dictionary in door.faces: claimed.append(face)
		var colors:Dictionary = {}
		for door:Dictionary in doors: colors[door.color_id] = true
		for door:Dictionary in doors:
			var islands_touched:Dictionary = {}
			for face:Dictionary in door.faces: islands_touched[face.island] = true
			var direct:bool = bool(group.get("direct_connection")) and islands_touched.size() >= 2
			for face:Dictionary in door.faces:
				var destinations:Array[Dictionary] = []
				if direct:
					var opposite:Array[Dictionary] = []
					for target_face:Dictionary in door.faces:
						if target_face.island != face.island: opposite.append(target_face)
					if not opposite.is_empty():
						destinations.append({"id":door.id,"faces":opposite,"color":door.color,"color_id":door.color_id})
				else:
					for other:Dictionary in doors:
						if other.id == door.id: continue
						if colors.size() > 1 and other.color_id == door.color_id: continue
						destinations.append({"id":other.id,"faces":other.faces,"color":other.color,"color_id":other.color_id})
				if destinations.is_empty(): continue
				var mode:int = int(group.get("pass_mode"))
				_gates.append({"entry":face,"exit":destinations[0].faces[0],"destinations":destinations,
					"chars":mode != 2,"proj":mode != 1,"mirror":false,"color":door.color,
					"exit_color":destinations[0].color,"color_id":door.color_id,"exit_color_id":destinations[0].color_id,"group_id":group.get_instance_id(),"door_id":door.id,
					"direct":direct})


static func _faces_overlap(a:Dictionary,b:Dictionary) -> bool:
	if str(a.island) != str(b.island) or int(a.side) != int(b.side): return false
	if absf(float(a.line)-float(b.line)) > 0.01: return false
	return minf(float(a.b),float(b.b)) - maxf(float(a.a),float(b.a)) > 0.01


# 排在 group 之前的图层已经占用的门面。
func claimed_faces_before(group:TileMapLayer) -> Array[Dictionary]:
	var claimed:Array[Dictionary] = []
	for other:TileMapLayer in portal_groups():
		if other == group: break
		for door:Dictionary in active_doors(other,claimed):
			for face:Dictionary in door.faces: claimed.append(face)
	return claimed


# group 里真正生效的门：与更早图层门面重叠的门整体剔除。
func active_doors(group:TileMapLayer,claimed:Array[Dictionary]) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	for door:Dictionary in group.call("portal_doors",self):
		if not _door_shadowed(door,claimed): result.append(door)
	return result


# group 里因为与更早图层重叠而被忽略的门（编辑器警告用）。
func shadowed_doors(group:TileMapLayer) -> Array[Dictionary]:
	var claimed:Array[Dictionary] = claimed_faces_before(group)
	var result:Array[Dictionary] = []
	for door:Dictionary in group.call("portal_doors",self):
		if _door_shadowed(door,claimed): result.append(door)
	return result


static func _door_shadowed(door:Dictionary,claimed:Array[Dictionary]) -> bool:
	for face:Dictionary in door.faces:
		for taken:Dictionary in claimed:
			if _faces_overlap(face,taken): return true
	return false


func _choose_gate_destination(gate:Dictionary,half_extents:Vector2) -> Dictionary:
	# 先按门等概率随机，再选该门可容纳物体的面；不会因门更长/格子更多而增加中奖权重。
	var eligible:Array[Dictionary] = []
	for option:Dictionary in gate.get("destinations",[]):
		var faces:Array[Dictionary] = []
		for face:Dictionary in option.faces:
			var half:float = half_extents.y if int(face.side) < 2 else half_extents.x
			if float(face.b)-float(face.a)+2.0 >= half*2.0: faces.append(face)
		if not faces.is_empty(): eligible.append({"id":option.id,"faces":faces,"color":option.color,"color_id":option.color_id})
	if eligible.is_empty(): return {}
	var target:Dictionary = eligible[_portal_rng.randi_range(0,eligible.size()-1)]
	var resolved:Dictionary = gate.duplicate()
	resolved["exit"] = target.faces[_portal_rng.randi_range(0,target.faces.size()-1)]
	resolved["exit_color"] = target.color
	resolved["exit_color_id"] = target.color_id
	resolved["destination_id"] = target.id
	return resolved


func gates() -> Array[Dictionary]:
	return _gates


static func _desc_key(desc:Dictionary) -> String:
	return "%s|%d|%.2f|%.2f|%.2f" % [str(desc.get("island","")),int(desc.get("side",0)),float(desc.get("line",0.0)),float(desc.get("a",0.0)),float(desc.get("b",0.0))]


# 某个岛某条边上被传送门占据的区间（已裁剪到 [axis_min,axis_max] 并合并）。
# World 用它在黑色边线 / 内沿阴影上留出缺口；物理墙不需要缺口。
func gap_intervals(island_name:String,side:int,axis_min:float,axis_max:float,line:float = INF) -> Array[Vector2]:
	var intervals:Array[Vector2] = []
	for gate:Dictionary in _gates:
		for key:String in ["entry","exit"]:
			var desc:Dictionary = gate[key]
			if str(desc.get("island","")) != island_name or int(desc.get("side",-1)) != side:
				continue
			if is_finite(line) and absf(float(desc.get("line",line))-line) > 0.01: continue
			var a:float = maxf(axis_min,float(desc.get("a",0.0)))
			var b:float = minf(axis_max,float(desc.get("b",0.0)))
			if b > a:
				intervals.append(Vector2(a,b))
	return merge_intervals(intervals)


static func merge_intervals(intervals:Array[Vector2]) -> Array[Vector2]:
	if intervals.size() <= 1:
		return intervals
	intervals.sort_custom(func(a:Vector2,b:Vector2) -> bool: return a.x < b.x)
	var merged:Array[Vector2] = []
	var current:Vector2 = intervals[0]
	for i:int in range(1,intervals.size()):
		var next_span:Vector2 = intervals[i]
		if next_span.x <= current.y:
			current.y = maxf(current.y,next_span.y)
		else:
			merged.append(current)
			current = next_span
	merged.append(current)
	return merged


#========================================================
# 空腔几何（供视觉 / 编辑器 / 测试使用）
#========================================================
# 该边一条门段的空腔矩形（世界坐标）：从岛的外沿向岛内挖 void_depth。
func gate_void_rect(island_name:String,side:int,a:float,b:float,line:float = INF) -> Rect2:
	var rect:Rect2 = island_rect(island_name)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()
	var depth:float = void_depth_for_side(side)
	var n:Vector2 = SIDE_NORMALS[side]
	var outer:float = _void_outer_offset()
	var out_a:Vector2 = (_edge_point(rect,side,a) if not is_finite(line) else Geometry.point({"side":side,"line":line},a)) + n * outer
	var out_b:Vector2 = (_edge_point(rect,side,b) if not is_finite(line) else Geometry.point({"side":side,"line":line},b)) + n * outer
	var inner_a:Vector2 = out_a - n * depth
	var inner_b:Vector2 = out_b - n * depth
	var min_p:Vector2 = out_a.min(out_b).min(inner_a).min(inner_b)
	var max_p:Vector2 = out_a.max(out_b).max(inner_a).max(inner_b)
	return Rect2(min_p,max_p - min_p)


func void_depth_for_side(side:int) -> float:
	var cell:Vector2 = cell_size()
	var base:float = cell.x if side < 2 else cell.y
	return maxf(void_depth_tiles * base,0.0)


# 所有门面的空腔矩形（去重，世界坐标）。
func void_rects() -> Array[Rect2]:
	var result:Array[Rect2] = []
	var seen:Dictionary = {}
	for gate:Dictionary in _gates:
		for key:String in ["entry","exit"]:
			var desc:Dictionary = gate[key]
			var desc_key:String = _desc_key(desc)
			if seen.has(desc_key):
				continue
			seen[desc_key] = true
			var rect:Rect2 = gate_void_rect(
				str(desc.get("island","")),
				int(desc.get("side",0)),
				float(desc.get("a",0.0)),
				float(desc.get("b",0.0)),float(desc.get("line",INF))
			)
			if rect.size.x > 0.0 and rect.size.y > 0.0:
				result.append(rect)
	return result


# 缺口处折进空腔的黑线折线（世界坐标，A-B-C-D 四点）：
# 从缺口两侧的边线端点沿墙向内，贴着缺口两侧的墙走，再横穿空腔底部。
# 外侧两点多伸出一小段，正好压进被截断的地图黑线端点里，接缝看不见。
func notch_outline_points(island_name:String,side:int,a:float,b:float,line:float = INF) -> PackedVector2Array:
	var rect:Rect2 = island_rect(island_name)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return PackedVector2Array()
	var n:Vector2 = SIDE_NORMALS[side]
	var depth:float = void_depth_for_side(side)
	var outer:float = _void_outer_offset()
	var edge_a:Vector2 = (_edge_point(rect,side,a) if not is_finite(line) else Geometry.point({"side":side,"line":line},a))
	var edge_b:Vector2 = (_edge_point(rect,side,b) if not is_finite(line) else Geometry.point({"side":side,"line":line},b))
	return PackedVector2Array([
		edge_a - n * _border_inset,
		edge_a + n * (outer - depth),
		edge_b + n * (outer - depth),
		edge_b - n * _border_inset,
	])


static func _clip_axis_segment(a:Vector2,b:Vector2,occluder:Rect2) -> Array[PackedVector2Array]:
	# 只扣除严格位于其他岛内部的部分；共线外沿仍是合并轮廓，不能两边同时删出缺口。
	var vertical:bool = absf(a.x-b.x) < 0.01
	var fixed:float = a.x if vertical else a.y
	var fixed_min:float = occluder.position.x if vertical else occluder.position.y
	var fixed_max:float = occluder.end.x if vertical else occluder.end.y
	if fixed <= fixed_min+0.01 or fixed >= fixed_max-0.01: return [PackedVector2Array([a,b])]
	var low:float = minf(a.y,b.y) if vertical else minf(a.x,b.x)
	var high:float = maxf(a.y,b.y) if vertical else maxf(a.x,b.x)
	var cut_low:float = occluder.position.y if vertical else occluder.position.x
	var cut_high:float = occluder.end.y if vertical else occluder.end.x
	if cut_low >= high-0.01 or cut_high <= low+0.01: return [PackedVector2Array([a,b])]
	var ranges:Array[Vector2] = []
	if cut_low > low+0.01: ranges.append(Vector2(low,minf(cut_low,high)))
	if cut_high < high-0.01: ranges.append(Vector2(maxf(cut_high,low),high))
	var result:Array[PackedVector2Array] = []
	for span:Vector2 in ranges:
		result.append(PackedVector2Array([Vector2(fixed,span.x),Vector2(fixed,span.y)]) if vertical else PackedVector2Array([Vector2(span.x,fixed),Vector2(span.y,fixed)]))
	return result


func exposed_border_segments(island_name:String,a:Vector2,b:Vector2,width:float) -> Array[PackedVector2Array]:
	var segments:Array[PackedVector2Array] = [PackedVector2Array([a,b])]
	for other:Variant in _island_regions:
		if str(other) == island_name: continue
		var cell:Vector2 = cell_size(str(other))
		for rect:Rect2 in _island_regions[other]:
			var wall:Rect2 = Rect2(rect.position-cell,rect.size+cell*2.0).grow(width*0.5)
			var next:Array[PackedVector2Array] = []
			for segment:PackedVector2Array in segments: next.append_array(_clip_axis_segment(segment[0],segment[1],wall))
			segments = next
	return segments

func notch_side_segments(island_name:String,side:int,a:float,b:float,line:float = INF) -> Array[PackedVector2Array]:
	var points:PackedVector2Array = notch_outline_points(island_name,side,a,b,line)
	var result:Array[PackedVector2Array] = []
	if points.size() != 4: return result
	for pair:int in [0,2]:
		var segments:Array[PackedVector2Array] = [PackedVector2Array([points[pair],points[pair+1]])]
		for other:Variant in _island_rects.keys():
			if str(other) == island_name: continue
			for region:Rect2 in island_regions(str(other)):
				var clipped:Array[PackedVector2Array] = []
				for segment:PackedVector2Array in segments:
					clipped.append_array(_clip_axis_segment(segment[0],segment[1],region))
				segments = clipped
		result.append_array(segments)
	return result


#========================================================
# 视觉：空腔 + 黑线 + 粒子 + 穿越闪光
#========================================================
func _clear_visuals() -> void:
	_drawn_notch_segments.clear()
	_gate_visuals.clear()
	_pulse_nodes.clear()
	for root:Node2D in [_visual_root,_void_root,_particle_root]:
		if root != null and is_instance_valid(root):
			# 先脱离父节点，名字立刻释放；同一帧里重建时不会变成 @Node2D@xx。
			remove_child(root)
			root.queue_free()
	_visual_root = null
	_void_root = null
	_particle_root = null
	_particle_clips.clear()


# 与引擎一致地累加 z_index（z_as_relative 会被父节点叠加）。
static func _draw_z(item:CanvasItem) -> int:
	var total:int = 0
	var node:CanvasItem = item
	while node != null:
		if node.z_as_relative:
			total += node.z_index
			node = node.get_parent() as CanvasItem
		else:
			total = node.z_index
			break
	return total


# 空腔盖在墙体之上、角色之下；这样角色走进空腔时仍然看得见。
func _void_layer_z() -> int:
	var layer:TileMapLayer = primary_island()
	if layer == null:
		return 0
	return _draw_z(layer) + 1


func _particle_clip(island_name:String) -> Control:
	if _particle_clips.has(island_name): return _particle_clips[island_name]
	if _particle_root == null or not _island_rects.has(island_name): return null
	var rect:Rect2 = _island_rects[island_name]
	var clip := Control.new()
	clip.name = "Clip_"+island_name
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.position = to_local(rect.position)
	clip.size = to_local(rect.end)-clip.position
	_particle_root.add_child(clip)
	var regions:Array[Rect2] = island_regions(island_name)
	if not regions.is_empty():
		var image:Image = Image.create(regions.size(),1,false,Image.FORMAT_RGBAF)
		for i:int in range(regions.size()):
			var r:Rect2 = regions[i]
			image.set_pixel(i,0,Color(r.position.x,r.position.y,r.end.x,r.end.y))
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scripts/effects/我的世界/map_ground_clip.gdshader")
		mat.set_shader_parameter("ground_regions",ImageTexture.create_from_image(image))
		mat.set_shader_parameter("ground_count",regions.size())
		clip.material = mat
	_particle_clips[island_name] = clip
	return clip


func _ensure_visual_roots() -> void:
	if _particle_root == null or not is_instance_valid(_particle_root):
		_particle_root = Node2D.new()
		_particle_root.name = "PortalParticlesClipped"
		_particle_root.z_as_relative = false
		_particle_root.z_index = 80
		add_child(_particle_root)
	if _void_root == null or not is_instance_valid(_void_root):
		_void_root = Node2D.new()
		_void_root.name = "PortalVoid"
		# 空腔盖在墙体之上、角色之下；这样角色走进空腔时仍然看得见。
		_void_root.z_as_relative = false
		_void_root.z_index = _void_layer_z()
		add_child(_void_root)
	if _visual_root == null or not is_instance_valid(_visual_root):
		_visual_root = Node2D.new()
		_visual_root.name = "PortalVisuals"
		# 高于地图外裁剪遮罩(90)与黑色边线(100)，粒子才能画在地图外的黑底上。
		_visual_root.z_as_relative = false
		_visual_root.z_index = 101
		add_child(_visual_root)


func refresh_visuals(border_width:float,inset:float,border_antialiased:bool = true) -> void:
	_border_width = maxf(border_width,0.0)
	_border_inset = inset
	_border_antialiased = border_antialiased
	_clear_visuals()
	# 编辑器中由插件画手柄，运行时节点不进场景，避免误存进 .tscn。
	if Engine.is_editor_hint():
		return
	if not _active or _gates.is_empty():
		return
	_ensure_visual_roots()

	# 同一个门面可能同时出现在入口和出口上：入口样式优先，且只建一次。
	var styles:Dictionary = {}
	for gate:Dictionary in _gates:
		for key:String in ["entry","exit"]:
			var desc:Dictionary = gate[key]
			var desc_key:String = _desc_key(desc)
			var is_entry:bool = key == "entry"
			if not styles.has(desc_key):
				styles[desc_key] = {"desc": desc,"color": gate["color"],"entry": is_entry}
			elif is_entry:
				styles[desc_key]["entry"] = true
				styles[desc_key]["color"] = gate["color"]
	var entry_count:int = 0
	for info:Dictionary in styles.values():
		if bool(info["entry"]): entry_count += 1
	_particle_budget = 256
	_particle_face_limit = clampi(256/maxi(entry_count,1),1,particles_per_gate)
	var keys:Array = styles.keys()
	keys.sort()
	for i:int in range(keys.size()):
		var info:Dictionary = styles[keys[i]]
		_build_gate_visuals(info["desc"] as Dictionary,info["color"] as Color,bool(info["entry"]),i)


func _gate_span_in_rect(desc:Dictionary) -> Dictionary:
	var island_name:String = str(desc.get("island",""))
	var side:int = int(desc.get("side",0))
	var rect:Rect2 = island_rect(island_name)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	var span:Vector2 = _edge_axis_span(rect,side)
	var pad:float = maxf(_border_inset,0.0) + 0.5
	var a:float = clampf(float(desc.get("a",0.0)),span.x + pad,span.y - pad)
	var b:float = clampf(float(desc.get("b",0.0)),span.x + pad,span.y - pad)
	if b - a <= 0.5:
		return {}
	return {"rect": rect,"side": side,"a": a,"b": b}


func _build_gate_visuals(desc:Dictionary,color:Color,is_entry:bool,tag:int = 0) -> void:
	var face_line:float = float(desc.get("line",INF))
	var resolved:Dictionary = _gate_span_in_rect(desc)
	if resolved.is_empty():
		return
	var rect:Rect2 = resolved["rect"]
	var side:int = int(resolved["side"])
	var a:float = float(resolved["a"])
	var b:float = float(resolved["b"])
	var n:Vector2 = SIDE_NORMALS[side]
	var mouth_a:Vector2 = (_edge_point(rect,side,a) if not is_finite(face_line) else Geometry.point({"side":side,"line":face_line},a))
	var mouth_b:Vector2 = (_edge_point(rect,side,b) if not is_finite(face_line) else Geometry.point({"side":side,"line":face_line},b))
	# 缺口不添加填色盖片：保留原有视差背景和地图阴影。
	# 两侧仍是普通黑边，只有内侧横跨缺口的传送面发光。
	if notch_outline and _wall_carving:
		var side_segments:Array[PackedVector2Array] = notch_side_segments(str(desc.get("island","")),side,a,b,face_line)
		for segment:PackedVector2Array in side_segments:
			var first:Vector2 = segment[0].min(segment[1])
			var last:Vector2 = segment[0].max(segment[1])
			var key:String = "%.3f,%.3f|%.3f,%.3f" % [first.x,first.y,last.x,last.y]
			if _drawn_notch_segments.has(key): continue
			_drawn_notch_segments[key] = true
			var outline := Line2D.new()
			outline.name = "NotchSide_%d_%d" % [tag,_drawn_notch_segments.size()]
			outline.points = PackedVector2Array([to_local(segment[0]),to_local(segment[1])])
			outline.width = _border_width
			outline.default_color = Color.BLACK
			outline.antialiased = _border_antialiased
			outline.begin_cap_mode = Line2D.LINE_CAP_NONE
			outline.end_cap_mode = Line2D.LINE_CAP_NONE
			_visual_root.add_child(outline)

	if show_portal_lines:
		var lines:Array[Line2D] = _create_gate_lines(desc,color,is_entry,tag)
		_gate_visuals[_desc_key(desc)] = lines
		for stroke:Line2D in lines:
			_pulse_nodes.append(stroke)

	if portal_particles and is_entry:
		_build_gate_particles(color,mouth_a,mouth_b,n,str(desc.get("island","")),tag)


func _create_gate_lines(desc:Dictionary,color:Color,is_entry:bool,tag:int = 0) -> Array[Line2D]:
	var face_line:float = float(desc.get("line",INF))
	var resolved:Dictionary = _gate_span_in_rect(desc)
	var lines:Array[Line2D] = []
	if resolved.is_empty():
		return lines
	var rect:Rect2 = resolved["rect"]
	var side:int = int(resolved["side"])
	var n:Vector2 = SIDE_NORMALS[side]
	var a:float = float(resolved["a"])
	var b:float = float(resolved["b"])
	var from:Vector2 = (_edge_point(rect,side,a) if not is_finite(face_line) else Geometry.point({"side":side,"line":face_line},a)) - n * _border_inset
	var to:Vector2 = (_edge_point(rect,side,b) if not is_finite(face_line) else Geometry.point({"side":side,"line":face_line},b)) - n * _border_inset
	if _wall_carving:
		var points:PackedVector2Array = notch_outline_points(str(desc.get("island","")),side,a,b,face_line)
		if points.size() == 4:
			from = points[1]
			to = points[2]
	for i:int in range(2):
		var stroke := Line2D.new()
		stroke.name = "GateLine_%d" % tag
		stroke.points = PackedVector2Array([to_local(from),to_local(to)])
		stroke.begin_cap_mode = Line2D.LINE_CAP_BOX
		stroke.end_cap_mode = Line2D.LINE_CAP_BOX
		stroke.antialiased = false
		_visual_root.add_child(stroke)
		lines.append(stroke)
	_style_gate_lines(lines,color,is_entry)
	return lines


func _style_gate_lines(lines:Array[Line2D],color:Color,is_entry:bool) -> void:
	if lines.size() < 2:
		return
	var width:float = _border_width
	var alpha:float = 1.0 if is_entry else 0.55
	lines[0].width = width
	lines[0].default_color = Color(color.r,color.g,color.b,alpha)
	lines[1].width = maxf(width * 0.4,0.5)
	lines[1].default_color = Color(1.0,1.0,1.0,0.7 * alpha)


# 只在门内侧发射，朝岛内轻飘。按岛裁切，哪怕外遮罩关闭也不会漏到地图外。
func _build_gate_particles(gate_color:Color,mouth_a:Vector2,mouth_b:Vector2,n:Vector2,island_name:String,tag:int = 0) -> void:
	var clip:Control = _particle_clip(island_name)
	var length:float = mouth_a.distance_to(mouth_b)
	if clip == null or length <= 1.0 or _particle_budget <= 0: return
	var cell:Vector2 = cell_size(island_name)
	var tile_span:float = cell.y if absf(n.x) > 0.5 else cell.x
	var count:int = mini(_particle_budget,clampi(ceili(length/maxf(tile_span,1.0)*4.0),1,_particle_face_limit))
	_particle_budget -= count
	if _particle_ramp == null:
		_particle_ramp = Gradient.new()
		_particle_ramp.offsets = PackedFloat32Array([0.0,0.18,0.55,1.0])
		_particle_ramp.colors = PackedColorArray([Color(1,1,1,0),Color(1,1,1,0.9),Color(1,1,1,0.4),Color(1,1,1,0)])
		_particle_scale_curve = Curve.new()
		_particle_scale_curve.add_point(Vector2(0,0.45))
		_particle_scale_curve.add_point(Vector2(0.2,1))
		_particle_scale_curve.add_point(Vector2(1,0.1))
	var particles := CPUParticles2D.new()
	particles.name = "PortalParticles_%d" % tag
	particles.amount = count
	particles.lifetime = particle_lifetime
	particles.preprocess = 0.0
	particles.fixed_fps = 30
	particles.randomness = 0.4
	particles.lifetime_randomness = 0.25
	particles.local_coords = true
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(1.0,maxf(length*0.5-2.0,0.5))
	particles.rotation = (-n).angle()
	particles.direction = Vector2.RIGHT
	particles.spread = 10.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = particle_speed*0.65
	particles.initial_velocity_max = particle_speed
	particles.damping_min = 4.0
	particles.damping_max = 10.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.25
	particles.scale_amount_curve = _particle_scale_curve
	particles.color_ramp = _particle_ramp
	particles.color = gate_color if particles_use_gate_color else particle_color
	particles.material = clip.material
	clip.add_child(particles)
	particles.global_position = (mouth_a+mouth_b)*0.5-n*3.0
	particles.emitting = true


func _flash_gate(desc:Dictionary,color:Color) -> void:
	var lines:Variant = _gate_visuals.get(_desc_key(desc),null)
	if lines == null:
		# 没画门线时，用门口的一圈涟漪代替闪光。
		_spawn_gate_ripple(desc,color)
		return
	for line:Line2D in lines:
		if line == null or not is_instance_valid(line):
			continue
		line.modulate = Color(2.2,2.2,2.2,1.0)
		var tween:Tween = line.create_tween()
		tween.tween_property(line,"modulate",Color.WHITE,0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _spawn_burst(pos:Vector2,color:Color,radius:float) -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	if _burst_budget <= 0:
		return
	_burst_budget -= 1
	var poly := Polygon2D.new()
	var pts:PackedVector2Array = PackedVector2Array()
	for i:int in range(16):
		var angle:float = TAU * float(i) / 16.0
		pts.append(Vector2(cos(angle),sin(angle)) * radius)
	poly.polygon = pts
	poly.color = Color(color.r,color.g,color.b,0.85)
	poly.z_index = 1
	var clip:Control = _particle_clip(island_at(pos))
	if clip == null:
		poly.free()
		return
	clip.add_child(poly)
	poly.global_position = pos
	poly.scale = Vector2(0.35,0.35)
	var tween:Tween = poly.create_tween().set_parallel(true)
	tween.tween_property(poly,"scale",Vector2(1.6,1.6),0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(poly,"modulate:a",0.0,0.24)
	tween.chain().tween_callback(poly.queue_free)


# 门口的一圈涟漪：穿门闪光与“被通行模式挡下”的提示共用。
func _spawn_ripple(pos:Vector2,color:Color,radius:float) -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	var ring := Line2D.new()
	ring.name = "PortalRipple"
	var pts:PackedVector2Array = PackedVector2Array()
	for i:int in range(25):
		var angle:float = TAU * float(i) / 24.0
		pts.append(Vector2(cos(angle),sin(angle)) * maxf(radius,4.0))
	ring.points = pts
	ring.closed = true
	ring.width = maxf(_border_width * 0.9,1.0)
	ring.default_color = Color(color.r,color.g,color.b,0.95)
	ring.antialiased = false
	ring.z_index = 3
	var clip:Control = _particle_clip(island_at(pos))
	if clip == null:
		ring.free()
		return
	clip.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector2(0.45,0.45)
	var tween:Tween = ring.create_tween().set_parallel(true)
	tween.tween_property(ring,"scale",Vector2(1.35,1.35),0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring,"modulate:a",0.0,0.3)
	tween.chain().tween_callback(ring.queue_free)


# 被通行模式挡下时的提示：门口一圈涟漪 + 计数（有最短间隔，避免连射刷屏）。
func _play_blocked_effect(desc:Dictionary,color:Color,force:bool = false) -> void:
	if not blocked_feedback and not force:
		return
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	var desc_key:String = _desc_key(desc)
	var now:int = Time.get_ticks_msec()
	if not force and now - int(_blocked_last.get(desc_key,0)) < BLOCKED_EFFECT_INTERVAL_MSEC:
		return
	_blocked_last[desc_key] = now
	blocked_event_count += 1
	_spawn_gate_ripple(desc,color)


# 门口的一圈涟漪（纯视觉，穿门闪光与阻挡提示共用）。
func _spawn_gate_ripple(desc:Dictionary,color:Color,radius_scale:float = 1.0) -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	var rect:Rect2 = island_rect(str(desc.get("island","")))
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var side:int = int(desc.get("side",0))
	var n:Vector2 = SIDE_NORMALS[side]
	var span:Vector2 = _edge_axis_span(rect,side)
	var u:float = clampf((float(desc.get("a",0.0)) + float(desc.get("b",0.0))) * 0.5,span.x,span.y)
	var width:float = float(desc.get("b",0.0)) - float(desc.get("a",0.0))
	_spawn_ripple(_face_point(desc,u) - n * 3.0,color,maxf(width * 0.22,6.0) * radius_scale)


func _play_transit_effects(gate:Dictionary,_from_pos:Vector2,to_pos:Vector2,radius:float) -> void:
	MC_AUDIO.play(self,"entity.enderman.teleport",to_pos,-5.0)
	if not transit_effects or _burst_budget <= 0: return
	_burst_budget -= 1
	var clip:Control = _particle_clip(island_at(to_pos))
	if clip == null: return
	var color:Color = gate.get("exit_color",gate["color"])
	var ring := Node2D.new()
	ring.name = "PortalArrivalRing"
	clip.add_child(ring)
	ring.global_position = to_pos
	var points:PackedVector2Array = PackedVector2Array()
	for i:int in range(49):
		var angle:float = TAU*float(i)/48.0
		points.append(Vector2(cos(angle),sin(angle))*maxf(radius,6.0))
	for i:int in range(3):
		var stroke := Line2D.new()
		stroke.points = points
		stroke.closed = true
		stroke.antialiased = true
		stroke.width = [5.0,3.0,1.25][i]
		stroke.default_color = Color(color.r*1.8,color.g*1.8,color.b*1.8,[0.12,0.25,1.0][i])
		stroke.material = clip.material
		ring.add_child(stroke)
	# 到达波纹：前 1/3 时间迅速撑开（指数缓出），全程正弦缓入渐隐，线宽同步收细，
	# 结束时透明度与线宽都归零，不会“啪”地消失。
	ring.scale = Vector2.ONE*0.55
	ring.modulate.a = 0.0
	var duration:float = 0.30
	var tween:Tween = ring.create_tween().set_parallel(true)
	tween.tween_property(ring,"scale",Vector2.ONE*2.6,duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring,"modulate:a",1.0,duration*0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring,"modulate:a",0.0,duration*0.88).set_delay(duration*0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for stroke:Line2D in ring.get_children():
		tween.tween_property(stroke,"width",0.0,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


#========================================================
# 穿越判定与映射
#========================================================
static func _shape_half_extents(shape_node:CollisionShape2D) -> Vector2:
	if shape_node == null or not is_instance_valid(shape_node) or shape_node.shape == null:
		return Vector2(-1.0,-1.0)
	var shape:Shape2D = shape_node.shape
	var xform:Transform2D = shape_node.global_transform
	var bx:Vector2 = xform.x
	var by:Vector2 = xform.y
	var half:Vector2
	if shape is RectangleShape2D:
		half = (shape as RectangleShape2D).size * 0.5
	elif shape is CircleShape2D:
		var r:float = (shape as CircleShape2D).radius
		half = Vector2(r,r)
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		half = Vector2(capsule.radius,capsule.height * 0.5)
	else:
		var r2:Rect2 = shape.get_rect()
		half = r2.size * 0.5
	return Vector2(
		absf(bx.x) * half.x + absf(by.x) * half.y,
		absf(bx.y) * half.x + absf(by.y) * half.y
	)


static func ball_half_extents(b:ball) -> Vector2:
	if b == null or not is_instance_valid(b):
		return Vector2(7.0,7.0)
	var extents:Vector2 = _shape_half_extents(b.collision_shape_2d)
	if extents.x < 0.0:
		return Vector2(7.0,7.0)
	return extents


static func node_half_extents(node:Node2D) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2(4.0,4.0)
	for c:Node in node.get_children():
		if c is CollisionShape2D:
			var extents:Vector2 = _shape_half_extents(c as CollisionShape2D)
			if extents.x >= 0.0:
				return extents
	return Vector2(4.0,4.0)


func _find_gate(p:Vector2,v:Vector2,he:Vector2,delta:float,is_character:bool,respect_pass_mode:bool = true) -> Dictionary:
	var island_name:String = island_at(p)
	if island_name.is_empty():
		return {}
	var rect:Rect2 = _island_rects[island_name]
	for gate:Dictionary in _gates:
		if respect_pass_mode:
			if is_character and not bool(gate["chars"]):
				continue
			if not is_character and not bool(gate["proj"]):
				continue
		var entry:Dictionary = gate["entry"]
		if str(entry["island"]) != island_name:
			continue
		var side:int = int(entry["side"])
		var n:Vector2 = SIDE_NORMALS[side]
		var vn:float = v.dot(n)
		if vn <= 0.0:
			continue
		var t:Vector2 = _edge_tangent(side)
		var h_n:float = absf(n.x) * he.x + absf(n.y) * he.y
		var h_t:float = absf(t.x) * he.x + absf(t.y) * he.y
		var u:float = _edge_scalar(p,side)
		# “实际门宽 = 显示门宽”：物体在门方向上的整个投影必须落在门内（1px 容差）。
		if u - h_t < float(entry["a"]) - 1.0 or u + h_t > float(entry["b"]) + 1.0:
			continue
		var depth:float = (p - _face_point(entry,u)).dot(n)
		if depth > 0.01: continue # 凹边另一侧的远处地面不是这个门的入口。
		var front:float = depth + h_n
		# 前沿将在两帧内碰到门边就传送，保证不会先撞上边缘那 1px 的墙体。
		var reach:float = maxf(vn * delta * 2.0,2.0) + 1.0
		if front + reach < 0.0:
			continue
		if not respect_pass_mode: return gate
		var selected:Dictionary = _choose_gate_destination(gate,he)
		if not selected.is_empty(): return selected
	return {}


func _map_vector(gate:Dictionary,vec:Vector2) -> Vector2:
	var side1:int = int((gate["entry"] as Dictionary)["side"])
	var side2:int = int((gate["exit"] as Dictionary)["side"])
	var n1:Vector2 = SIDE_NORMALS[side1]
	var t1:Vector2 = _edge_tangent(side1)
	var n2:Vector2 = SIDE_NORMALS[side2]
	var t2:Vector2 = _edge_tangent(side2)
	var sign:float = -1.0 if bool(gate["mirror"]) else 1.0
	return -n2 * vec.dot(n1) + t2 * vec.dot(t1) * sign


func _map_position(gate:Dictionary,p:Vector2,he:Vector2) -> Vector2:
	var entry:Dictionary = gate["entry"]
	var exit:Dictionary = gate["exit"]
	var side1:int = int(entry["side"])
	var side2:int = int(exit["side"])
	var rb:Rect2 = _island_rects.get(str(exit["island"]),Rect2())
	var n2:Vector2 = SIDE_NORMALS[side2]
	var t2:Vector2 = _edge_tangent(side2)
	var h_n2:float = absf(n2.x) * he.x + absf(n2.y) * he.y
	var h_t2:float = absf(t2.x) * he.x + absf(t2.y) * he.y
	var u:float = _edge_scalar(p,side1)
	var f:float = clampf((u - float(entry["a"])) / maxf(float(entry["b"]) - float(entry["a"]),0.001),0.0,1.0)
	if bool(gate["mirror"]):
		f = 1.0 - f
	var u2:float = float(exit["a"]) + f * (float(exit["b"]) - float(exit["a"]))
	var span2:Vector2 = _edge_axis_span(rb,side2)
	var lo:float = maxf(span2.x,float(exit["a"])) + h_t2
	var hi:float = minf(span2.y,float(exit["b"])) - h_t2
	if lo <= hi:
		u2 = clampf(u2,lo,hi)
	else:
		u2 = (span2.x + span2.y) * 0.5
	return _face_point(exit,u2) - n2 * (h_n2 + ARRIVAL_CLEARANCE)


func process_transits(delta:float,characters:Array,ball_projectiles:Array,other_projectiles:Array = []) -> void:
	if not _active or _gates.is_empty():
		return
	_burst_budget = MAX_BURSTS_PER_FRAME
	var now:int = Time.get_ticks_msec()
	for raw:Variant in characters:
		if raw is ball:
			_try_transit_ball(raw as ball,delta,true,now)
	for raw:Variant in ball_projectiles:
		if raw is ball:
			_try_transit_ball(raw as ball,delta,false,now)
	for raw:Variant in other_projectiles:
		if raw is Node2D and not raw is ball:
			_try_transit_node(raw as Node2D,delta,now)


func _try_transit_ball(b:ball,delta:float,is_character:bool,now:int) -> bool:
	if b == null or not is_instance_valid(b) or not b.is_inside_tree():
		return false
	if not b.is_multiplayer_authority():
		return false
	if is_character:
		if b.health <= 0:
			return false
		if b.state_machine != null and b.state_machine.current_state == ball.State.Die:
			return false
		if b.has_meta(&"map_rescue_animating") and bool(b.get_meta(&"map_rescue_animating")):
			return false
	if int(b.get_meta(META_COOLDOWN,0)) > now:
		return false

	var v:Vector2 = b.velocity
	if v.length_squared() <= 0.01:
		v = b.direction * maxf(b.Speed,0.0) + b.Repel
	if v.length_squared() <= 0.01:
		return false

	var he:Vector2 = ball_half_extents(b)
	var from_pos:Vector2 = b.global_position
	var gate:Dictionary = _find_gate(from_pos,v,he,delta,is_character)
	if gate.is_empty():
		_report_blocked_ball(from_pos,v,he,delta,is_character,now)
		return false

	var to_pos:Vector2 = _map_position(gate,from_pos,he)
	var new_velocity:Vector2 = _map_vector(gate,v)
	b.global_position = to_pos
	b.velocity = new_velocity
	b._last_requested_velocity = new_velocity
	if b.direction.length_squared() > 0.0001:
		b.direction = _map_vector(gate,b.direction)
	if b.Repel.length_squared() > 0.0001:
		b.Repel = _map_vector(gate,b.Repel)
	b.reset_physics_interpolation()
	# 残影 / 运动模糊按“画面实际位移”采样；瞬移后清空历史，避免拉出一条跨岛长线。
	if b.has_method("_clear_after_image_path"):
		b.call("_clear_after_image_path")
	if b.has_method("_reset_after_image_sampling"):
		b.call("_reset_after_image_sampling")
	b.set_meta(META_COOLDOWN,now + TRANSIT_COOLDOWN_MSEC)
	_play_transit_effects(gate,from_pos,to_pos,maxf(he.x,he.y))
	return true


# 被通行模式挡下的物体（例如“仅角色”门前的子弹）刚好贴着门时，门口闪一圈提示。
func _report_blocked_ball(p:Vector2,v:Vector2,he:Vector2,delta:float,is_character:bool,_now:int) -> void:
	if not blocked_feedback or _visual_root == null or not is_instance_valid(_visual_root):
		return
	var gate:Dictionary = _find_gate(p,v,he,delta,is_character,false)
	if gate.is_empty():
		return
	_play_blocked_effect(gate["entry"] as Dictionary,gate["color"] as Color)


func _try_transit_node(node:Node2D,delta:float,now:int) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if not node.is_multiplayer_authority():
		return false
	if int(node.get_meta(META_COOLDOWN,0)) > now:
		return false
	var world:Node = get_parent()
	if world == null or not world.has_method("portal_get_projectile_velocity"):
		return false
	var v:Vector2 = world.call("portal_get_projectile_velocity",node)
	if v.length_squared() <= 0.01:
		return false

	var he:Vector2 = node_half_extents(node)
	var from_pos:Vector2 = node.global_position
	var gate:Dictionary = _find_gate(from_pos,v,he,delta,false)
	if gate.is_empty():
		if blocked_feedback and _visual_root != null and is_instance_valid(_visual_root):
			var blocked:Dictionary = _find_gate(from_pos,v,he,delta,false,false)
			if not blocked.is_empty():
				_play_blocked_effect(blocked["entry"] as Dictionary,blocked["color"] as Color)
		return false

	var to_pos:Vector2 = _map_position(gate,from_pos,he)
	node.global_position = to_pos
	world.call("portal_set_projectile_velocity",node,_map_vector(gate,v))
	node.reset_physics_interpolation()
	node.set_meta(META_COOLDOWN,now + TRANSIT_COOLDOWN_MSEC)
	_play_transit_effects(gate,from_pos,to_pos,maxf(he.x,he.y))
	return true
