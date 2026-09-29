extends "res://tests/test_heavenfall_obstacle_visibility.gd"
## Real collision geometry, same-frame crossings, and actual GPU FIFO closure.

func check_pierce(center:Vector2) -> void:
	await super.check_pierce(center)
	var cases:Array[Dictionary] = [
		{"name":"thin/high-step","size":Vector2(2,30),"dt":100.0/620.0},
		{"name":"thin/60hz","size":Vector2(2,30),"dt":1.0/60.0},
		{"name":"ordinary/high-step","size":Vector2(28,30),"dt":100.0/620.0},
		{"name":"thick/60hz","size":Vector2(96,30),"dt":1.0/60.0,"start_distance":60.0},
		{"name":"rotated stone","size":Vector2(23,25.5),"rotation":0.65,"dt":100.0/620.0},
		{"name":"scaled rotated terrain","size":Vector2(23,25.5),"scale":Vector2(1.6,0.8),"rotation":-0.58,"dt":100.0/620.0},
		{"name":"diagonal crossing","size":Vector2(30,25),"axis":Vector2(1,0.35).normalized(),"dt":100.0/620.0},
		{"name":"circle chord","circle":10.0,"offset":Vector2(0,6),"dt":100.0/620.0},
		{"name":"edge-grazing","size":Vector2(28,30),"offset":Vector2(0,14),"dt":1.0/60.0,"narrow":true},
		{"name":"corner diagonal","size":Vector2(24,24),"axis":Vector2(1,0.35).normalized(),"offset":Vector2(-7,7),"dt":100.0/620.0},
		{"name":"visual circle","circle":10.0,"textured":true,"size":Vector2(30,30),"dt":1.0/60.0},
		{"name":"visual circle offset","circle":10.0,"textured":true,"size":Vector2(30,30),"offset":Vector2(0,8.5),"dt":1.0/60.0,"narrow":true},
		{"name":"transparent band","circle":10.0,"textured":true,"size":Vector2(30,30),"offset":Vector2(0,12.5),"miss":true,"dt":1.0/60.0}
	]
	for entry:Dictionary in cases:
		await footprint_case(center,entry)
	await vanish_inside_case(center)
	await closure_contract(center)

func textured_wall(center:Vector2,rect_size:Vector2,visual_radius:float) -> StaticBody2D:
	# 碰撞是整块矩形，可见部分只有中间的圆形贴图：模拟石头“贴图轮廓小于碰撞框”。
	var wall:=StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	wall.position = center
	var collision:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size = rect_size
	collision.shape = shape
	wall.add_child(collision)
	var texture_size:int = 128
	var image:=Image.create_empty(texture_size,texture_size,false,Image.FORMAT_RGBA8)
	image.fill(Color(1.0,1.0,1.0,0.0))
	var radius_px:float = visual_radius*float(texture_size)/rect_size.x
	for y:int in range(texture_size):
		var dy:float = float(y-texture_size/2)
		var dx:float = sqrt(maxf(radius_px*radius_px-dy*dy,-1.0))
		if dx<=0.0: continue
		for x:int in range(int(texture_size/2-dx),int(texture_size/2+dx)+1):
			image.set_pixel(x,y,Color(1.0,1.0,1.0,1.0))
	var sprite:=Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.scale = Vector2(rect_size.x/float(texture_size),rect_size.y/float(texture_size))
	wall.add_child(sprite)
	world.add_child(wall,true)
	return wall

func footprint_case(center:Vector2,data:Dictionary) -> void:
	await _clear_probes()
	await _park_intruders()
	var wall:StaticBody2D
	if data.has("textured"):
		wall = textured_wall(center,data.size,float(data.circle))
	else:
		wall = StaticBody2D.new()
		wall.collision_layer = 1
		wall.collision_mask = 2
		wall.position = center
		wall.rotation = float(data.get("rotation",0.0))
		wall.scale = data.get("scale",Vector2.ONE)
		var collision:=CollisionShape2D.new()
		if data.has("circle"):
			var shape:=CircleShape2D.new()
			shape.radius = float(data.circle)
			collision.shape = shape
		else:
			var shape:=RectangleShape2D.new()
			shape.size = data.size
			collision.shape = shape
		wall.add_child(collision)
		world.add_child(wall,true)
	await physics_frame
	await process_frame
	var axis:Vector2 = data.get("axis",Vector2.RIGHT)
	var offset:Vector2 = data.get("offset",Vector2.ZERO)
	# 期望区间按“直线与实际形状的交”计算：偏置/贴边穿越是不对称的，不能假设过中心。
	# 带贴图的障碍：碰撞区间（矩形）决定箭的穿行与时钟原点，可见区间（圆形贴图）决定裂缝范围。
	var span_min:float
	var span_max:float
	var line_center:Vector2 = center+offset
	var local_center:Vector2 = wall.global_transform.affine_inverse()*line_center
	# 不能 normalize：t 的单位必须保持“世界路程”，缩放墙的本地方向长度恰好完成换算。
	var local_axis:Vector2 = wall.global_transform.affine_inverse().basis_xform(axis)
	var chord:=func(radius:float) -> Vector2:
		var projection:float = local_center.dot(local_axis)
		var squared:float = local_axis.length_squared()
		var discriminant:float = projection*projection-squared*(local_center.length_squared()-radius*radius)
		var root:float = sqrt(maxf(discriminant,0.0))/maxf(squared,0.000001)
		var middle:float = -projection/maxf(squared,0.000001)
		return Vector2(middle-root,middle+root)
	if data.has("circle") and not data.has("textured"):
		var interval:Vector2 = chord.call(float(data.circle))
		span_min = interval.x
		span_max = interval.y
	else:
		var size:Vector2 = data.size
		span_min = -INF
		span_max = INF
		for component:int in range(2):
			var direction:float = local_axis[component]
			var origin:float = local_center[component]
			var extent:float = size[component]*0.5
			if absf(direction)<0.000001:
				if absf(origin)>extent: span_min = INF
				continue
			var first:float = (-extent-origin)/direction
			var second:float = (extent-origin)/direction
			span_min = maxf(span_min,minf(first,second))
			span_max = minf(span_max,maxf(first,second))
	var visual_min:float = span_min
	var visual_max:float = span_max
	if data.has("textured"):
		var interval:Vector2 = chord.call(float(data.circle))
		visual_min = interval.x
		visual_max = interval.y
	var start:Vector2 = line_center-axis*float(data.get("start_distance",50.0))
	var bolt:Node2D = _spawn_bolt(start)
	bolt._dir = axis
	var dt:float = float(data.dt)
	for i in range(40):
		bolt._physics_process(dt)
		if bolt.has_pierced() and not bolt.is_inside_obstacle(): break
	var label:String = str(data.name)
	check(bolt.has_pierced() and not bolt.is_inside_obstacle() and not bolt.is_queued_for_deletion(),label+": arrow actually exits the real obstacle")
	check(_tears().size()==1,label+": exactly one crossing slit")
	if _tears().is_empty():
		wall.queue_free()
		return
	var tear:Node2D = _tears()[0]
	tear.set_process(false)
	if data.has("miss"):
		# 只穿过碰撞框、没碰到可见贴图的路径：不应留下任何可见裂缝。
		tear._rebuild_mesh()
		check(tear.sample_count()<2 or not tear._surface.visible,label+": a path through only the transparent margin leaves no visible slit")
		print("PIERCE_VISUAL_MISS ",label," samples=",tear.sample_count()," visible=",tear._surface.visible if tear.sample_count()>=2 else false)
		wall.queue_free()
		await _clear_probes()
		return
	var near_value:float = INF
	var far_value:float = -INF
	var clock_error:float = 0.0
	var ordered:bool = tear.sample_count()>2
	for i:int in tear.sample_count():
		var point:Vector2 = tear.to_global(tear._points[i])
		var along:float = (point-line_center).dot(axis)
		near_value = minf(near_value,along)
		far_value = maxf(far_value,along)
		clock_error = maxf(clock_error,absf(float(tear._open_at[i])-(along-span_min)/620.0))  # 时钟原点是碰撞入口
		if i>0: ordered = ordered and tear._open_at[i]>tear._open_at[i-1]
	var long_tolerance:float = 0.30 if data.has("textured") else 0.12
	check(near_value>=visual_min-long_tolerance and far_value<=visual_max+long_tolerance,label+": slit cannot inherit the arrow's unused frame travel outside the obstacle")
	check(visual_min>visual_max or (absf(near_value-visual_min)<=long_tolerance and absf(far_value-visual_max)<=long_tolerance),label+": slit covers the real entry AND exit, not just the last inside tick")
	check(ordered and clock_error<0.0002,label+": every section has its own physical opening time, including sections born in one frame")
	tear._rebuild_mesh()
	var mesh:ArrayMesh = tear._surface.mesh
	var longitudinal_ok:bool = mesh!=null
	if mesh!=null:
		var arrays:Array = mesh.surface_get_arrays(0)
		for vertex:Vector2 in arrays[Mesh.ARRAY_VERTEX]:
			var x:float = (tear.to_global(vertex)-line_center).dot(axis)
			longitudinal_ok = longitudinal_ok and x>=visual_min-(0.35 if data.has("textured") else 0.15) and x<=visual_max+(0.35 if data.has("textured") else 0.15)
	check(longitudinal_ok,label+": the complete halo mesh also stays near the obstacle boundaries")
	var lateral_ok:bool = mesh!=null
	var worst:Vector2 = Vector2.ZERO
	if mesh!=null:
		var inverse:Transform2D = wall.global_transform.affine_inverse()
		for vertex:Vector2 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var local_point:Vector2 = inverse*(tear.to_global(vertex))
			var overhang:float = maxf(maxf(absf(local_point.x)-(data.size.x*0.5 if not data.has("circle") else float(data.circle)),absf(local_point.y)-(data.size.y*0.5 if not data.has("circle") else float(data.circle))),local_point.length()-(float(data.circle) if data.has("circle") else 1.0e9))
			if overhang>worst.x: worst = Vector2(overhang,0.0)
			if data.has("circle"):
				lateral_ok = lateral_ok and local_point.length()<=float(data.circle)+0.25
			else:
				lateral_ok = lateral_ok and absf(local_point.x)<=data.size.x*0.5+0.25 and absf(local_point.y)<=data.size.y*0.5+0.25
	if not lateral_ok:
		print("CONTAINMENT_EXCESS ",label," worst_local_overhang=",worst)
	check(lateral_ok,label+": the visible slit stays inside the obstacle's actual shape, even near edges and corners")
	# 宽度非退化：裁剪不能把整条裂缝压成不可见的零宽线（真实像素渲染在 GPU 套件里复核）。
	# 以路径线为基准（路径过裂隙局部原点），不含采样间抖动差。
	var side:Vector2 = Vector2(-axis.y,axis.x)
	var max_lateral:float = 0.0
	if mesh!=null:
		for vertex:Vector2 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			max_lateral = maxf(max_lateral,absf(vertex.dot(side)))
	if data.has("narrow"):
		# 采样中心带 ±0.3 抖动：贴边窄缝宽度按抖动后的实际中心测量，上限放宽。
		check(max_lateral>0.2 and max_lateral<=2.0,label+": a grazing path keeps a narrowed but visible slit")
	elif data.has("textured"):
		check(max_lateral>2.5,label+": a path through the visible texture keeps a visible slit width")
	else:
		check(max_lateral>2.5 and max_lateral<=3.8,label+": clipping keeps the full slit width away from edges")
	print("PIERCE_BOUND ",label," expected=",Vector2(visual_min,visual_max)," actual=",Vector2(near_value,far_value)," time_error=",clock_error)
	wall.queue_free()
	await _clear_probes()

func vanish_inside_case(center:Vector2) -> void:
	# 箭身在墙内就消失（出屏/被回收）时，裂隙仍要补到真实穿出面，不能断在半路。
	await _clear_probes()
	await _park_intruders()
	var wall:=StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	wall.position = center
	var collision:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size = Vector2(96,30)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall,true)
	await physics_frame
	await process_frame
	var start:Vector2 = center + Vector2(-70.0,0.0)
	var bolt:Node = _spawn_bolt(start)
	var inside_seen:bool = false
	for i in range(40):
		bolt._physics_process(1.0/60.0)
		if bolt.is_inside_obstacle():
			inside_seen = true
			break
	check(inside_seen,"fixture: the arrow is still inside the thick wall when it vanishes")
	bolt._vanish()
	var tears:Array = _tears()
	check(tears.size()==1,"vanishing inside the wall still leaves exactly one rift")
	if tears.is_empty():
		wall.queue_free()
		await _clear_probes()
		return
	var tear:Node2D = tears[0]
	tear.set_process(false)
	var pts:PackedVector2Array = tear.get("_points")
	var far_value:float = -INF
	for p:Vector2 in pts:
		far_value = maxf(far_value,(tear.to_global(p)-start).dot(Vector2.RIGHT))
	print("VANISH_INSIDE far=",far_value," expected=",118.0)
	check(absf(far_value-118.0)<=0.20,"a rift survives an arrow vanishing mid-wall and still reaches the real exit face")
	wall.queue_free()
	await _clear_probes()

func closure_contract(center:Vector2) -> void:
	var script:Script = load("res://scripts/characters/我的世界/new6/heavenfall_pierce_rift.gd")
	var tear:Node2D = script.new()
	world.add_child(tear)
	tear.set_process(false)
	var start:Vector2 = center+Vector2(-20,36)
	tear.configure(start,Vector2.RIGHT,39)
	tear.add_sample(start+Vector2(40,0),Vector2.RIGHT)
	tear.finish()
	check(tear.close_start(0)==tear._open_at[0]+tear.OPEN_RAMP+tear.HOLD_TIME,"hold starts after opening, and the declared closing time matches the shader's timeline")
	check(tear.has_method("sample_aperture"),"uniform per-section aperture curve is explicit and testable")
	if tear.has_method("sample_aperture"):
		var uniform:bool = true
		for i:int in [1,tear.sample_count()/2,tear.sample_count()-2]:
			var born:float = tear._open_at[i]
			for fraction:float in [0.25,0.5,0.75,1.0]:
				var eased:float = fraction*fraction*(3.0-2.0*fraction)
				uniform = uniform and is_equal_approx(tear.sample_aperture(i,born+tear.OPEN_RAMP*fraction),eased)
				uniform = uniform and is_equal_approx(tear.sample_aperture(i,tear.close_start(i)+tear.CLOSE_TIME*fraction),1.0-eased)
		check(uniform,"all sections share one eased open/close curve (no velocity kinks); only their start times differ")
		var first_born:float = tear._open_at[1]
		check(tear.sample_aperture(1,first_born+0.05)>0.0 and tear.sample_aperture(1,first_born+0.05)<1.0,"sections visibly tear open instead of popping into place")
		check(tear.sample_aperture(1,tear.close_start(1)+0.22)>0.0,"closing is slow enough to be watched instead of snapping shut")
		var local_end:float = tear.OPEN_RAMP+tear.HOLD_TIME+tear.CLOSE_TIME
		var at:float = local_end+0.020
		check(tear.sample_aperture(1,at)==0.0 and tear.sample_aperture(tear.sample_count()-2,at)>0.0,"entry sections are fully closed while later exit sections remain open")
	tear.queue_free()
	await process_frame
	if render:
		var saved_hdr:bool = root.use_hdr_2d
		for hdr:bool in [true,false]:
			root.use_hdr_2d = hdr
			await process_frame
			await gpu_closure(start,script,hdr)
		root.use_hdr_2d = saved_hdr
		await process_frame

func gpu_closure(start:Vector2,script:Script,hdr:bool) -> void:
	var tear:Node2D = script.new()
	world.add_child(tear)
	tear.set_process(false)
	tear.configure(start,Vector2.RIGHT,39)
	tear.add_sample(start+Vector2(40,0),Vector2.RIGHT)
	tear.finish()
	var label:String = "HDR" if hdr else "LDR"
	if not tear.has_method("sample_aperture"):
		check(false,label+": GPU FIFO probe requires the independent section timeline")
		tear.queue_free()
		await process_frame
		return
	tear._age = tear.OPEN_RAMP+tear.HOLD_TIME
	tear._process(0.0)
	tear.hide()
	var without:Image = await frame()
	tear.show()
	var widths:Array[Vector2] = []
	for along:float in [10.0,30.0]:
		var measured:=Vector2.ZERO
		for k:int in range(2):
			var fraction:float = 0.25 if k==0 else 0.75
			tear._age = along/620.0+tear.OPEN_RAMP+tear.HOLD_TIME+tear.CLOSE_TIME*fraction
			tear._process(0.0)
			measured[k] = section_pixel_width(without,await frame(),start+Vector2(along,0))
		widths.append(measured)
	check(widths[0].x>widths[0].y+2.0 and widths[1].x>widths[1].y+2.0,label+": actual GPU apertures visibly narrow instead of simply fading")
	check(absf(widths[0].x-widths[1].x)<=2.0 and absf(widths[0].y-widths[1].y)<=2.0,label+": sections reach the same rendered width at the same LOCAL age")
	tear._age = tear.OPEN_RAMP+tear.HOLD_TIME+tear.CLOSE_TIME+11.0/620.0
	tear._process(0.0)
	var closing:Image = await frame()
	var early_width:float = section_pixel_width(without,closing,start+Vector2(5,0))
	var late_width:float = section_pixel_width(without,closing,start+Vector2(30,0))
	check(early_width==0.0 and late_width>0.0,label+": entry is completely sealed while exit remains visibly open")
	print("PIERCE_GPU ",label," quarter/three-quarter widths=",widths," fifo=",Vector2(early_width,late_width))
	export_image(closing,"heavenfall_pierce_fifo_"+label.to_lower()+".png")
	tear.queue_free()
	await process_frame

func section_pixel_width(without:Image,with_tear:Image,point:Vector2) -> float:
	var at:Vector2i = Vector2i(screen_point(point).round())
	var sum:float = 0.0
	for x:int in range(at.x-1,at.x+2):
		var count:int = 0
		for y:int in range(at.y-16,at.y+17):
			if x>=0 and y>=0 and x<with_tear.get_width() and y<with_tear.get_height():
				if colour_delta(without.get_pixel(x,y),with_tear.get_pixel(x,y))>0.025: count+=1
		sum += count
	return sum/3.0
