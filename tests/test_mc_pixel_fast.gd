extends SceneTree
const ARC=preload("res://scripts/effects/我的世界/pixel_arc.gd")
var checks:int=0
var failures:int=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func reference(radius:float,start:float,end:float,width:float) -> Dictionary:
	var result:Dictionary={}
	var outer:float=radius+maxf(width,3.0)*0.5
	var inner:float=maxf(radius-maxf(width,3.0)*0.5,0.0)
	var extent:int=int(ceil(outer/3.0))
	for y:int in range(-extent,extent):
		for x:int in range(-extent,extent):
			var p:Vector2=Vector2(x+0.5,y+0.5)*3.0
			if p.length()>outer or p.length()<inner: continue
			var a:float=fposmod(p.angle()-start,TAU) if end>=start else fposmod(start-p.angle(),TAU)
			if absf(end-start)<TAU-0.001 and a>absf(end-start): continue
			result[Vector2i(x,y)]=true
	return result
func _initialize() -> void:
	for r:float in [6.0,30.0,55.0,120.0,225.0]:
		for angles:Vector2 in [Vector2(0,TAU),Vector2(-0.1,0.1),Vector2(2.8,3.5),Vector2(1,-1),Vector2(0,PI)]:
			for width:float in [0.5,7.0]:
				var spans:PackedVector2Array=ARC.spans(r,angles.x,angles.y,width)
				var actual:Dictionary={}
				for i:int in range(0,spans.size(),2):
					var a:Vector2=spans[i];var b:Vector2=spans[i+1]
					for x:int in range(int(round(minf(a.x,b.x)/3.0)),int(round(maxf(a.x,b.x)/3.0))):
						actual[Vector2i(x,int(floor(a.y/3.0)))]=true
				var expected:Dictionary=reference(snappedf(r,1.5),angles.x,angles.y,width)
				check(actual.size()==expected.size() and actual.keys().all(func(k):return expected.has(k)),"batched spans exactly preserve pixel cells")
	var begin:int=Time.get_ticks_usec()
	for i:int in range(128): ARC._build_spans(30.0+i*1.5,-0.6,0.6,3.0)
	var uncached:int=Time.get_ticks_usec()-begin
	for i:int in range(128): ARC.spans(30.0+i*1.5,-0.6,0.6,3.0)
	begin=Time.get_ticks_usec()
	for i:int in range(128): ARC.spans(30.0+i*1.5,-0.6,0.6,3.0)
	print("PIXEL_SPANS_128 uncached_us=",uncached," cached_us=",Time.get_ticks_usec()-begin)
	for i:int in range(700): ARC.spans(30.0+i*1.5,-0.6,0.6,3.0)
	check(ARC._span_cache.size()<=512 and ARC._cache_order.size()<=512,"cache stays bounded under sustained attacks")
	print("PIXEL_FAST_TEST checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
