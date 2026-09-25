extends RefCounted
# Hollow pixel arcs: cached horizontal spans, submitted as one batched draw command.
const PIXEL:float=3.0
const CACHE_LIMIT:int=512
static var _span_cache:Dictionary={}
static var _cache_order:Array[Vector4]=[]
static var _cache_cursor:int=0
static func spans(radius:float,start:float,end:float,width:float) -> PackedVector2Array:
	# Visual-only quantization below one pixel; gameplay never uses this geometry.
	var r:float=snappedf(radius,PIXEL*0.5)
	var thickness:float=maxf(width,PIXEL)
	var key:Vector4=Vector4(r,start,end,thickness)
	if _span_cache.has(key): return _span_cache[key]
	var points:PackedVector2Array=_build_spans(r,start,end,thickness)
	if _cache_order.size()>=CACHE_LIMIT:
		_span_cache.erase(_cache_order[_cache_cursor])
		_cache_order[_cache_cursor]=key
		_cache_cursor=(_cache_cursor+1)%CACHE_LIMIT
	else: _cache_order.append(key)
	_span_cache[key]=points
	return points
static func _build_spans(radius:float,start:float,end:float,width:float) -> PackedVector2Array:
	var points:PackedVector2Array=[]
	if radius<=0.0: return points
	var outer:float=radius+width*0.5
	var inner:float=maxf(radius-width*0.5,0.0)
	var extent:int=int(ceil(outer/PIXEL))
	var sweep:float=end-start
	var full:bool=absf(sweep)>=TAU-0.001
	for y:int in range(-extent,extent):
		var py:float=(float(y)+0.5)*PIXEL
		if absf(py)>outer: continue
		var max_x:int=int(floor(sqrt(maxf(outer*outer-py*py,0.0))/PIXEL-0.5))
		var min_x:int=0
		if absf(py)<inner:
			min_x=maxi(0,int(ceil(sqrt(maxf(inner*inner-py*py,0.0))/PIXEL-0.5)))
		for side:int in [-1,1]:
			var run_start:int=-1
			for x:int in range(min_x,max_x+2):
				var included:bool=x<=max_x
				if included and not full:
					var point:Vector2=Vector2((float(x)+0.5)*PIXEL*side,py)
					var angle:float=fposmod(point.angle()-start,TAU) if sweep>=0.0 else fposmod(start-point.angle(),TAU)
					included=angle<=absf(sweep)
				if included:
					if run_start<0: run_start=x
				elif run_start>=0:
					points.append(Vector2(float(run_start)*PIXEL*side,py))
					points.append(Vector2(float(x)*PIXEL*side,py))
					run_start=-1
	return points
static func draw(canvas:CanvasItem,center:Vector2,radius:float,start:float,end:float,_segments:int,color:Color,width:float=1.0,_antialiased:bool=false) -> void:
	if radius<=0.0 or color.a<=0.0: return
	var points:PackedVector2Array=spans(radius,start,end,width)
	if points.is_empty(): return
	if center!=Vector2.ZERO:
		points=points.duplicate()
		for i:int in points.size(): points[i]+=center
	canvas.draw_multiline(points,color,PIXEL,false)

## Full Minecraft-style layered circle. Uses the SAME span rasterizer as the mace.
## Palette entries optionally replace the three layer tints; alpha remains shared.
static func draw_ring(canvas:CanvasItem,center:Vector2,radius:float,tint:Color = Color.WHITE,opacity:float = 1.0,palette:PackedColorArray = PackedColorArray()) -> void:
	var widths:PackedFloat32Array = PackedFloat32Array([7.0,3.6,1.35])
	var alphas:PackedFloat32Array = PackedFloat32Array([0.16,0.40,0.98])
	for i:int in range(3):
		var color:Color = palette[i] if i < palette.size() else tint
		color.a *= clampf(opacity,0.0,1.0)*alphas[i]
		draw(canvas,center,radius,0.0,TAU,64,color,widths[i],false)

## Filled pixel disk, not a smooth circle or a second hand-written rasterizer.
## An annulus of radius R/2 and width R has inner radius 0 and outer radius R.
static func draw_disk(canvas:CanvasItem,center:Vector2,radius:float,color:Color) -> void:
	if radius < PIXEL*0.5: return
	draw(canvas,center,radius*0.5,0.0,TAU,64,color,radius,false)
