class_name PortalEditMath
extends RefCounted

# ============================================================
# 传送门编辑器用的纯几何计算（不依赖编辑器 API，可 headless 回归测试）。
#
# 坐标系：世界（画布）坐标。岛用 Rect2 表示，边段用 (side, a, b) 表示：
#   side 0=左 1=右 2=上 3=下；a/b 是这条边从“上端 / 左端”量起的起止像素。
# ============================================================

const SIDE_NORMALS:Array[Vector2] = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]


static func normal(side:int) -> Vector2:
	return SIDE_NORMALS[clampi(side,0,3)]


static func inward(side:int) -> Vector2:
	return -normal(side)


static func tangent(side:int) -> Vector2:
	return Vector2.DOWN if side < 2 else Vector2.RIGHT


static func axis_span(rect:Rect2,side:int) -> Vector2:
	if side < 2:
		return Vector2(rect.position.y,rect.end.y)
	return Vector2(rect.position.x,rect.end.x)


static func axis_scalar(p:Vector2,side:int) -> float:
	return p.y if side < 2 else p.x


static func edge_point(rect:Rect2,side:int,u:float) -> Vector2:
	match side:
		0:
			return Vector2(rect.position.x,u)
		1:
			return Vector2(rect.end.x,u)
		2:
			return Vector2(u,rect.position.y)
		_:
			return Vector2(u,rect.end.y)


static func snap_value(value:float,step:float) -> float:
	if step <= 0.001:
		return value
	return roundf(value / step) * step


# 一端的手柄位置：贴在该边的内侧 inner_offset 处，方便点选又不会盖住墙。
static func handles(rect:Rect2,side:int,a:float,b:float,inner_offset:float) -> Dictionary:
	var dir:Vector2 = inward(side)
	return {
		"start": edge_point(rect,side,a) + dir * inner_offset,
		"end": edge_point(rect,side,b) + dir * inner_offset,
		"mid": edge_point(rect,side,(a + b) * 0.5) + dir * inner_offset,
		"normal": normal(side),
		"inward": dir,
		"tangent": tangent(side),
		"span": Vector2(a,b),
	}


# 命中哪个手柄：返回 "start" / "end" / "mid" / ""（空串表示没点到）。
static func hit_test(rect:Rect2,side:int,a:float,b:float,inner_offset:float,point:Vector2,radius:float) -> String:
	var h:Dictionary = handles(rect,side,a,b,inner_offset)
	var order:Array[String] = ["start","end","mid"]
	var best:String = ""
	var best_distance:float = maxf(radius,0.001)
	for key:String in order:
		var position:Vector2 = h[key]
		var distance:float = point.distance_to(position)
		if distance <= best_distance:
			best_distance = distance
			best = key
	return best


# 拖动中点：整段沿边滑动，长度不变。
static func slide(rect:Rect2,side:int,a:float,b:float,pointer:float,snap:float,min_length:float) -> Dictionary:
	var span:Vector2 = axis_span(rect,side)
	var total:float = maxf(span.y - span.x,1.0)
	var length:float = clampf(b - a,minf(min_length,total),total)
	length = clampf(snap_value(length,snap),minf(min_length,total),total)
	var start:float = span.x + clampf(snap_value(pointer - span.x - length * 0.5,snap),0.0,total - length)
	return {
		"offset": start - span.x,
		"length": length,
		"whole_edge": length >= total - 0.5,
	}


# 拖动端点：只改起点或终点，长度随之变化。
static func resize(rect:Rect2,side:int,a:float,b:float,which:String,pointer:float,snap:float,min_length:float) -> Dictionary:
	var span:Vector2 = axis_span(rect,side)
	var total:float = maxf(span.y - span.x,1.0)
	var value:float = clampf(span.x + snap_value(pointer - span.x,snap),span.x,span.y)
	var start:float = a
	var end:float = b
	if which == "end":
		end = clampf(maxf(value,start + min_length),span.x,span.y)
	else:
		start = clampf(minf(value,end - min_length),span.x,span.y)
	return {
		"offset": start - span.x,
		"length": maxf(end - start,minf(min_length,total)),
		"whole_edge": absf(start - span.x) <= 0.5 and absf(end - span.y) <= 0.5,
	}


# 离指针最近的一条岛边（超出 max_dist 就返回空）。
static func nearest_edge(rects:Dictionary,point:Vector2,max_dist:float) -> Dictionary:
	var best:Dictionary = {}
	var best_distance:float = maxf(max_dist,0.001)
	for island_name:Variant in rects.keys():
		var rect:Rect2 = rects[island_name]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		for side:int in range(4):
			var span:Vector2 = axis_span(rect,side)
			var u:float = clampf(axis_scalar(point,side),span.x,span.y)
			var distance:float = point.distance_to(edge_point(rect,side,u))
			if distance <= best_distance:
				best_distance = distance
				best = {"island": str(island_name),"side": side,"u": u,"distance": distance}
	return best


# 新建连接时自动挑对岸：从这条边朝外探一步，取最近的另一条岛边作为出口。
static func auto_target(rects:Dictionary,source_island:String,source_side:int,a:float,b:float,probe_distance:float) -> Dictionary:
	var rect:Rect2 = rects.get(source_island,Rect2())
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	var probe:Vector2 = edge_point(rect,source_side,(a + b) * 0.5) + normal(source_side) * maxf(probe_distance,1.0)
	var best:Dictionary = {}
	var best_distance:float = INF
	for island_name:Variant in rects.keys():
		if str(island_name) == source_island:
			continue
		var other:Rect2 = rects[island_name]
		if other.size.x <= 0.0 or other.size.y <= 0.0:
			continue
		for side:int in range(4):
			var span:Vector2 = axis_span(other,side)
			var u:float = clampf(axis_scalar(probe,side),span.x,span.y)
			var distance:float = probe.distance_to(edge_point(other,side,u))
			if distance < best_distance:
				best_distance = distance
				best = {"island": str(island_name),"side": side,"u": u,"span": span}
	if best.is_empty():
		return {}
	var span_b:Vector2 = best["span"]
	var length:float = clampf(b - a,1.0,maxf(span_b.y - span_b.x,1.0))
	var source_offset:float = a - axis_span(rect,source_side).x
	var offset:float = clampf(source_offset,0.0,maxf(span_b.y - span_b.x - length,0.0))
	return {
		"island": str(best["island"]),
		"side": int(best["side"]),
		"offset": offset,
		"length": length,
	}


# 四条边各画一条“描边”（编辑器里给选中的边加亮用）。
static func side_rect_outline(rect:Rect2,side:int) -> PackedVector2Array:
	match side:
		0:
			return PackedVector2Array([rect.position,Vector2(rect.position.x,rect.end.y)])
		1:
			return PackedVector2Array([Vector2(rect.end.x,rect.position.y),rect.end])
		2:
			return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y)])
		_:
			return PackedVector2Array([Vector2(rect.position.x,rect.end.y),rect.end])

