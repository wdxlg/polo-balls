extends Node3D
## Fixed original mountain + adaptive ancient arena. Pure visuals, no gameplay bodies.
const MOUNTAIN:PackedScene = preload("res://assets/maps/summit/shandian_natural.glb")
const STONE:Texture2D = preload("res://assets/maps/summit/stone_bricks.png")
const CRACKED:Texture2D = preload("res://assets/maps/summit/cracked_stone_bricks.png")
const MOSS:Texture2D = preload("res://assets/maps/summit/mossy_stone_bricks.png")
const CARVED:Texture2D = preload("res://assets/maps/summit/chiseled_stone_bricks.png")
const MOUNTAIN_RANGE = preload("res://scripts/effects/summit_mountain_range.gd")
const PLATFORM_DROP_CELLS:float = 0.3
const FLOATING_CLEARANCE_CELLS:float = 4.9
const MAX_SEAT_HEIGHT_CELLS:float = 0.34
var column_count:int = 0
var seat_segment_count:int = 0
var mountain:Node3D
var backdrop:Node3D
var landscape:Node3D
var backdrop_highest_y:float = 0.0
var mesh_count:int = 0
var floor_regions:Array[Rect2] = []
var decoration_regions:Array[Rect2] = []
var mountain_highest_y:float = 0.0
var mountain_source_bounds:AABB
var _tools:Dictionary = {}
var _used:Dictionary = {}
var _materials:Dictionary = {}
var _cell:float = 16.0

func _surface(key:String,texture:Texture2D,tint:Color) -> void:
	var material:=StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.texture_repeat = true
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	var tool:=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tools[key] = tool

func _face(key:String,points:Array[Vector3],span:Vector2) -> void:
	var tool:SurfaceTool = _tools[key]
	_used[key] = true
	var normal:Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	var uv:Array[Vector2] = [Vector2.ZERO,Vector2(span.x,0),span,Vector2(0,span.y)]
	for i:int in [0,2,1,0,3,2]:
		tool.set_normal(normal)
		tool.set_uv(uv[i])
		tool.add_vertex(points[i])

func _plane(key:String,rect:Rect2,y:float) -> void:
	_face(key,[Vector3(rect.position.x,y,rect.end.y),Vector3(rect.end.x,y,rect.end.y),Vector3(rect.end.x,y,rect.position.y),Vector3(rect.position.x,y,rect.position.y)],rect.size/_cell)

func _box(key:String,rect:Rect2,low:float,high:float,decoration:bool = false) -> void:
	if decoration: decoration_regions.append(rect)
	_plane(key,rect,high)
	var x:float = rect.position.x
	var z:float = rect.position.y
	var a:float = rect.end.x
	var b:float = rect.end.y
	var h:float = (high-low)/_cell
	_face(key,[Vector3(x,low,z),Vector3(a,low,z),Vector3(a,low,b),Vector3(x,low,b)],rect.size/_cell)
	_face(key,[Vector3(a,low,z),Vector3(x,low,z),Vector3(x,high,z),Vector3(a,high,z)],Vector2(rect.size.x/_cell,h))
	_face(key,[Vector3(x,low,b),Vector3(a,low,b),Vector3(a,high,b),Vector3(x,high,b)],Vector2(rect.size.x/_cell,h))
	_face(key,[Vector3(x,low,z),Vector3(x,low,b),Vector3(x,high,b),Vector3(x,high,z)],Vector2(rect.size.y/_cell,h))
	_face(key,[Vector3(a,low,b),Vector3(a,low,z),Vector3(a,high,z),Vector3(a,high,b)],Vector2(rect.size.y/_cell,h))

func _stand(side:int,a:float,b:float,line:float) -> void:
	if b-a<0.05: return
	seat_segment_count += 1
	for tier:int in range(2):
		var distance:float = (0.5+float(tier)*0.65)*_cell
		var rect:Rect2
		if side==0: rect = Rect2(a,line-distance-_cell*0.65,b-a,_cell*0.65)
		elif side==1: rect = Rect2(a,line+distance,b-a,_cell*0.65)
		elif side==2: rect = Rect2(line-distance-_cell*0.65,a,_cell*0.65,b-a)
		else: rect = Rect2(line+distance,a,_cell*0.65,b-a)
		_box("Seats",rect,-_cell*PLATFORM_DROP_CELLS,_cell*(0.10+float(tier)*0.20),true)
		var lip:Rect2 = rect.grow(-_cell*0.09)
		_box("Carved",lip,_cell*(0.10+float(tier)*0.20),_cell*(0.14+float(tier)*0.20))

func _model_bounds(model:Node3D) -> AABB:
	var bounds:AABB
	var first:bool = true
	var inverse:Transform3D = model.global_transform.affine_inverse()
	for detail:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var local:AABB = (inverse*detail.global_transform)*detail.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	return bounds

func build(ground:Array[Rect2],walls:Array[Rect2],cell_size:Vector2,background_layer:int = 1,floor_layer:int = 1) -> void:
	if ground.is_empty(): return
	_cell = minf(cell_size.x,cell_size.y)
	floor_regions = ground.duplicate()
	_surface("ArenaFloor",STONE,Color(0.77,0.80,0.83))
	_surface("Weathered",CRACKED,Color(0.71,0.75,0.79))
	_surface("Moss",MOSS,Color(0.68,0.74,0.68))
	_surface("Seats",STONE,Color(0.66,0.72,0.78))
	_surface("Platform",STONE,Color(0.66,0.72,0.78))
	_surface("Carved",CARVED,Color(0.68,0.72,0.77))
	var bounds:Rect2 = ground[0]
	for rect:Rect2 in ground: bounds = bounds.merge(rect)
	# Keep the fixed scene wholly below the playable Y=0 plane. No double floor.
	mountain = MOUNTAIN.instantiate() as Node3D
	mountain.name = "OriginalSummitMountain"
	add_child(mountain)
	mountain_source_bounds = _model_bounds(mountain)
	var scale_factor:float = maxf(maxf(bounds.size.x,bounds.size.y)/44.0,_cell*0.24)
	mountain.scale = Vector3.ONE*scale_factor
	mountain_highest_y = -maxf(_cell*6.0,maxf(bounds.size.x,bounds.size.y)*0.18)
	var center:Vector2 = bounds.get_center()
	mountain.position = Vector3(center.x-9.5*scale_factor,mountain_highest_y-mountain_source_bounds.end.y*scale_factor,center.y+14.5*scale_factor-bounds.size.y*0.5-_cell*6.0)
	# Reuse the same meshes for a rear ridge, visible beyond the arena in top-down play.
	backdrop = MOUNTAIN.instantiate() as Node3D
	backdrop.name = "DistantSummitRidge"
	for detail:MeshInstance3D in backdrop.find_children("*","MeshInstance3D",true,false):
		if String(detail.name).to_lower().contains("landmark"): detail.hide()
	add_child(backdrop)
	var distant_scale:float = scale_factor*0.62
	var valley_base:float = mountain.position.y+mountain_source_bounds.position.y*scale_factor
	backdrop_highest_y = valley_base+mountain_source_bounds.size.y*distant_scale
	backdrop.scale = Vector3.ONE*distant_scale
	backdrop.rotation.y = PI*0.5
	backdrop.position = Vector3(mountain.position.x-bounds.size.x*0.95,valley_base-mountain_source_bounds.position.y*distant_scale,mountain.position.z-bounds.size.y*1.3)
	for rect:Rect2 in ground:
		_box("Platform",rect,-_cell*PLATFORM_DROP_CELLS,-0.02)
		_plane("ArenaFloor",rect,0.015)
		# Deterministic weathering has bounded geometry even on 50x50 maps.
		var nx:int = maxi(1,ceili(rect.size.x/_cell))
		var ny:int = maxi(1,ceili(rect.size.y/_cell))
		var stride:int = maxi(1,ceili(sqrt(float(nx*ny)/450.0)))
		for x:int in range(0,nx,stride):
			for y:int in range(0,ny,stride):
				var pattern:int = posmod(x*73+y*137,17)
				if pattern>2: continue
				var tile:Rect2 = Rect2(rect.position+Vector2(x,y)*_cell,Vector2.ONE*_cell).intersection(rect)
				_plane("Moss" if pattern==0 else "Weathered",tile,0.025)
		var edge:float = _cell*0.28
		for trim:Rect2 in [Rect2(rect.position,Vector2(rect.size.x,edge)),Rect2(Vector2(rect.position.x,rect.end.y-edge),Vector2(rect.size.x,edge)),Rect2(rect.position,Vector2(edge,rect.size.y)),Rect2(Vector2(rect.end.x-edge,rect.position.y),Vector2(edge,rect.size.y))]:
			_plane("Platform",trim,0.035)
	# Only a narrow lip, not the former five-cell-wide paved deck.
	var deck:Rect2=bounds.grow(_cell*0.55)
	var bands:Array[Rect2]=[
		Rect2(deck.position,Vector2(deck.size.x,bounds.position.y-deck.position.y)),
		Rect2(Vector2(deck.position.x,bounds.end.y),Vector2(deck.size.x,deck.end.y-bounds.end.y)),
		Rect2(Vector2(deck.position.x,bounds.position.y),Vector2(bounds.position.x-deck.position.x,bounds.size.y)),
		Rect2(Vector2(bounds.end.x,bounds.position.y),Vector2(deck.end.x-bounds.end.x,bounds.size.y))]
	for band:Rect2 in bands: _box("Platform",band,-_cell*PLATFORM_DROP_CELLS,-_cell*0.12)
	# Merge touching wall spans into long benches, never a stack of individual cubes.
	var sides:Array = [[],[],[],[]]
	for wall:Rect2 in walls:
		var side:int = -1
		if wall.end.y<=bounds.position.y+0.01: side = 0
		elif wall.position.y>=bounds.end.y-0.01: side = 1
		elif wall.end.x<=bounds.position.x+0.01: side = 2
		elif wall.position.x>=bounds.end.x-0.01: side = 3
		if side<0: continue
		var a:float = maxf(wall.position.x,bounds.position.x) if side<2 else maxf(wall.position.y,bounds.position.y)
		var b:float = minf(wall.end.x,bounds.end.x) if side<2 else minf(wall.end.y,bounds.end.y)
		if b>a: sides[side].append(Vector2(a,b))
	for side:int in range(4):
		var spans:Array = sides[side]
		spans.sort_custom(func(a:Vector2,b:Vector2)->bool: return a.x<b.x)
		var merged:Array[Vector2] = []
		for span:Vector2 in spans:
			if not merged.is_empty() and span.x<=merged[-1].y+0.01: merged[-1].y=maxf(merged[-1].y,span.y)
			else: merged.append(span)
		var midpoint:float = center.x if side<2 else center.y
		var line:float = [bounds.position.y,bounds.end.y,bounds.position.x,bounds.end.x][side]
		for span:Vector2 in merged:
			_stand(side,span.x,minf(span.y,midpoint-_cell*1.6),line)
			_stand(side,maxf(span.x,midpoint+_cell*1.6),span.y,line)
	# Exactly four slender, full-height corner columns, rather than low piles of blocks.
	var outer:Rect2 = bounds.grow(_cell*0.9)
	var corners:Array[Vector2] = [outer.position,Vector2(outer.end.x,outer.position.y),outer.end,Vector2(outer.position.x,outer.end.y)]
	for p:Vector2 in corners:
		_box("Seats",Rect2(p-Vector2.ONE*_cell*0.5,Vector2.ONE*_cell),-_cell*PLATFORM_DROP_CELLS,_cell*0.10,true)
		var height:float = _cell*3.0
		_box("Carved",Rect2(p-Vector2.ONE*_cell*0.24,Vector2.ONE*_cell*0.48),_cell*0.10,height,true)
		_box("Seats",Rect2(p-Vector2.ONE*_cell*0.38,Vector2.ONE*_cell*0.76),height,height+_cell*0.14,true)
		column_count += 1
	for key:String in _tools:
		if not _used.has(key): continue
		var mesh:ArrayMesh = (_tools[key] as SurfaceTool).commit()
		if mesh == null: continue
		mesh.surface_set_material(0,_materials[key])
		var item:=MeshInstance3D.new()
		item.name = key
		item.mesh = mesh
		# Surface/platform and standing architecture must not share one opaque
		# 2D foreground image: silverfish/ice/rails retain their original depths.
		item.layers = floor_layer if key in ["ArenaFloor","Weathered","Moss","Platform"] else 1
		add_child(item)
		mesh_count += 1
	_tools.clear()
	landscape = MOUNTAIN_RANGE.new()
	landscape.name = "MountainsBelowFloatingArena"
	add_child(landscape)
	var authored_peaks:Array[Node3D] = [mountain,backdrop]
	landscape.build(ground,_cell,get_parent().get_node_or_null("MovingPerspectiveWallCamera") as Camera3D,authored_peaks,mountain_source_bounds)
	# Keep the exact authored meshes in the same World3D, but below the 2D cloud plane.
	# Arena architecture and low walls remain on the foreground layer.
	for scenery:Node3D in [mountain,backdrop,landscape]:
		for detail:MeshInstance3D in scenery.find_children("*","MeshInstance3D",true,false):
			detail.layers = background_layer
