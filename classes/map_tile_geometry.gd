@tool
class_name MapTileGeometry
extends RefCounted
# 实际占用格 -> 合并矩形与暴露边。外接矩形只用于相机，不再决定地面。
static var _cache:Dictionary = {}
static func invalidate(layer:TileMapLayer) -> void:
	_cache.erase(layer.get_instance_id())

static func from_layer(layer:TileMapLayer) -> Dictionary:
	if layer == null or layer.tile_set == null: return {"regions":[],"walls":[],"cells":{}}
	var id:int = layer.get_instance_id()
	var stamp:Transform2D = layer.global_transform
	if _cache.has(id) and _cache[id].stamp == stamp: return _cache[id]
	if not layer.has_meta("shape_cache_hook"):
		layer.set_meta("shape_cache_hook",true)
		layer.changed.connect(func(): _cache.erase(id))
		layer.tree_exiting.connect(func(): _cache.erase(id))
	var cells:Dictionary = {}
	for cell:Vector2i in layer.get_used_cells(): cells[cell] = true
	var walls:Dictionary = {}
	for cell:Vector2i in cells:
		for x:int in range(-1,2):
			for y:int in range(-1,2):
				var next:Vector2i = cell+Vector2i(x,y)
				if not cells.has(next): walls[next] = true
	var data:Dictionary = {"regions":_world_rects(layer,cells),"walls":_world_rects(layer,walls),"cells":cells,"stamp":stamp}
	_cache[id] = data
	return data

static func _world_rects(layer:TileMapLayer,cells:Dictionary) -> Array[Rect2]:
	var rows:Dictionary = {}
	for cell:Vector2i in cells:
		if not rows.has(cell.y): rows[cell.y] = []
		rows[cell.y].append(cell.x)
	var ys:Array = rows.keys()
	ys.sort()
	var rects:Array[Rect2i] = []
	var previous:Dictionary = {}
	var previous_y:int = -2147483648
	for y:int in ys:
		var xs:Array = rows[y]
		xs.sort()
		var spans:Array[Vector2i] = []
		var start:int = xs[0]
		var end:int = start+1
		for i:int in range(1,xs.size()):
			if int(xs[i]) == end: end += 1
			else:
				spans.append(Vector2i(start,end))
				start = xs[i]
				end = start+1
		spans.append(Vector2i(start,end))
		var current:Dictionary = {}
		for span:Vector2i in spans:
			var index:int
			if y == previous_y+1 and previous.has(span):
				index = previous[span]
				var r:Rect2i = rects[index]
				r.size.y += 1
				rects[index] = r
			else:
				index = rects.size()
				rects.append(Rect2i(span.x,y,span.y-span.x,1))
			current[span] = index
		previous = current
		previous_y = y
	var result:Array[Rect2] = []
	var size:Vector2 = Vector2(layer.tile_set.tile_size)
	for rect:Rect2i in rects:
		var a:Vector2 = layer.to_global(Vector2(rect.position)*size)
		var b:Vector2 = layer.to_global(Vector2(rect.end)*size)
		result.append(Rect2(a.min(b),(a-b).abs()))
	return result

static func contains(regions:Array,point:Vector2) -> bool:
	for rect:Rect2 in regions:
		if rect.has_point(point): return true
	return false

static func subtract(regions:Array[Rect2],cuts:Array[Rect2]) -> Array[Rect2]:
	var result:Array[Rect2] = regions.duplicate()
	for cut:Rect2 in cuts:
		var next:Array[Rect2] = []
		for rect:Rect2 in result:
			var hit:Rect2 = rect.intersection(cut)
			if not hit.has_area():
				next.append(rect)
				continue
			if hit.position.x > rect.position.x: next.append(Rect2(rect.position,Vector2(hit.position.x-rect.position.x,rect.size.y)))
			if hit.end.x < rect.end.x: next.append(Rect2(hit.end.x,rect.position.y,rect.end.x-hit.end.x,rect.size.y))
			if hit.position.y > rect.position.y: next.append(Rect2(hit.position.x,rect.position.y,hit.size.x,hit.position.y-rect.position.y))
			if hit.end.y < rect.end.y: next.append(Rect2(hit.position.x,hit.end.y,hit.size.x,rect.end.y-hit.end.y))
		result = next
	return result

static func edges(regions:Array[Rect2]) -> Array[Dictionary]:
	var buckets:Dictionary = {}
	var templates:Dictionary = {}
	for rect:Rect2 in regions:
		for side:int in range(4):
			var line:float = [rect.position.x,rect.end.x,rect.position.y,rect.end.y][side]
			var low:float = rect.position.y if side < 2 else rect.position.x
			var high:float = rect.end.y if side < 2 else rect.end.x
			var intervals:Array[Vector2] = [Vector2(low,high)]
			var probe:float = line+(-0.01 if side == 0 or side == 2 else 0.01)
			for other:Rect2 in regions:
				var normal_low:float = other.position.x if side < 2 else other.position.y
				var normal_high:float = other.end.x if side < 2 else other.end.y
				if probe <= normal_low or probe >= normal_high: continue
				var cut_a:float = other.position.y if side < 2 else other.position.x
				var cut_b:float = other.end.y if side < 2 else other.end.x
				var next:Array[Vector2] = []
				for span:Vector2 in intervals:
					if cut_a >= span.y or cut_b <= span.x: next.append(span)
					else:
						if cut_a > span.x: next.append(Vector2(span.x,cut_a))
						if cut_b < span.y: next.append(Vector2(cut_b,span.y))
				intervals = next
			var key:String = "%d|%.4f" % [side,line]
			if not buckets.has(key):
				buckets[key] = []
				templates[key] = {"side":side,"line":line}
			buckets[key].append_array(intervals)
	var result:Array[Dictionary] = []
	for key:String in buckets:
		var spans:Array = buckets[key]
		spans.sort_custom(func(a:Vector2,b:Vector2) -> bool: return a.x < b.x)
		var merged:Array[Vector2] = []
		for span:Vector2 in spans:
			if span.y-span.x <= 0.001: continue
			if not merged.is_empty() and span.x <= merged.back().y+0.001: merged[merged.size()-1].y = maxf(merged.back().y,span.y)
			else: merged.append(span)
		for span:Vector2 in merged:
			var edge:Dictionary = templates[key].duplicate()
			edge.a = span.x
			edge.b = span.y
			result.append(edge)
	return result

static func point(edge:Dictionary,u:float) -> Vector2:
	return Vector2(float(edge.line),u) if int(edge.side) < 2 else Vector2(u,float(edge.line))
