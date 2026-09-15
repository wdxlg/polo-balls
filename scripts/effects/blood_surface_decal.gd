extends Node2D

# 同一滴血的像素从飞行轮廓缓慢渗开；不在落地时随机换成叉形/扇形图案。
# 墙面只铺薄膜，额外血量主要加深颜色，不向墙外增厚。
var _cells:Array[Dictionary] = []
var _masks:Array[PackedVector2Array] = []
var _blocked:Array[PackedVector2Array] = []
var _frames:Array[Texture2D] = []
var _elapsed:float = 0.0
var _volume:float = 1.0
var _unit:float = 1.0
var _seed:int = 1
var _wall:bool = false
var _heap:bool = false
var _down := Vector2.ZERO
var _shear:float = 0.0
var _deposits:Array[Dictionary] = []
var _floor_filter:Callable
var _valid_cells:Dictionary = {}
var _old_texture:Texture2D
var _old_blend:float = 1.0
const EXTENT:int = 28

func configure(masks:Array[PackedVector2Array],seed_value:int,scale_value:float,shear:float,local_down:Vector2) -> void:
	_masks = masks
	_seed = seed_value
	_unit = clampf(scale_value,0.35,0.85)
	_shear = shear
	_down = local_down
	_wall = true
	_rebuild()

func configure_ground(seed_value:int,scale_value:float,cell_filter:Callable = Callable(),masks:Array[PackedVector2Array] = [],heap:bool = false,blocked:Array[PackedVector2Array] = [],landings:Array = []) -> void:
	_seed = seed_value
	_unit = clampf(scale_value,0.3,1.1)
	_floor_filter = cell_filter
	_masks = masks
	_blocked = blocked
	_heap = heap
	_append_landings(landings)
	_rebuild()
	_floor_filter = Callable()

func _append_landings(landings:Array) -> bool:
	var changed:bool = false
	for landing:Dictionary in landings:
		if _deposits.size() >= 4: break
		var position_value:Vector2 = landing.get("position",global_position)
		_deposits.append({"offset":to_local(position_value),"pixels":landing["pixels"],"colors":landing["colors"],"direction":landing.get("direction",Vector2.RIGHT)})
		changed = true
	return changed

func add_volume(amount:float,landings:Array = []) -> void:
	var value:float = minf(_volume + maxf(amount,0.0) * 0.5,2.0)
	var changed:bool = _append_landings(landings)
	if value - _volume < 0.10 and not changed: return
	if not _frames.is_empty(): _old_texture = _frames[clampi(int(_elapsed / 0.28 * 4.0),0,4)]
	_volume = value
	_rebuild()

func _cell_allowed(p:Vector2) -> bool:
	if _valid_cells.has(p): return bool(_valid_cells[p])
	var allowed:bool = true
	for offset:Vector2 in [Vector2(0.02,0.02),Vector2(0.98,0.02),Vector2(0.98,0.98),Vector2(0.02,0.98)]:
		if not _masks.is_empty():
			var inside:bool = false
			for mask:PackedVector2Array in _masks:
				if Geometry2D.is_point_in_polygon(p + offset,mask):
					inside = true
					break
			if not inside:
				allowed = false
				break
		for polygon:PackedVector2Array in _blocked:
			if Geometry2D.is_point_in_polygon(p + offset,polygon):
				allowed = false
				break
		if not allowed: break
		if _floor_filter.is_valid() and not bool(_floor_filter.call(to_global(p + offset))):
			allowed = false
			break
	_valid_cells[p] = allowed
	return allowed

func _paint(image:Image,p:Vector2,color:Color,cells:Dictionary) -> void:
	p = p.floor()
	if absf(p.x) >= EXTENT or absf(p.y) >= EXTENT or not _cell_allowed(p): return
	image.set_pixel(int(p.x) + EXTENT,int(p.y) + EXTENT,color)
	cells[p] = color

func _rebuild() -> void:
	_frames.clear()
	_cells.clear()
	_valid_cells.clear()
	self_modulate = Color.WHITE
	for stage:int in range(5):
		var progress:float = float(stage) / 4.0
		var image := Image.create(EXTENT * 2,EXTENT * 2,false,Image.FORMAT_RGBA8)
		var cells:Dictionary = {}
		if not _deposits.is_empty() and not _wall and not _heap:
			for deposit:Dictionary in _deposits:
				var pixels:PackedVector2Array = deposit["pixels"]
				var colors:PackedColorArray = deposit["colors"]
				var axis:Vector2 = (deposit["direction"] as Vector2).normalized()
				var side:Vector2 = axis.orthogonal()
				for i:int in range(pixels.size()):
					var p:Vector2 = deposit["offset"] + pixels[i]
					# 始终保留源轮廓，最多向外渗开一两像素；初始帧与飞行末帧逐像素相同。
					_paint(image,p,colors[i],cells)
					var growth:Vector2 = (axis * pixels[i].dot(axis) * 0.06 + side * pixels[i].dot(side) * 0.20) * progress
					var end:Vector2 = p + growth
					var steps:int = maxi(int(ceilf(growth.length())),1)
					for step:int in range(1,steps + 1):
						_paint(image,p.lerp(end,float(step) / steps),colors[i].darkened(progress * 0.035),cells)
		else:
			_draw_film(image,progress,cells)
		_frames.append(ImageTexture.create_from_image(image))
		if stage == 4:
			for p:Vector2 in cells: _cells.append({"point":p,"color":cells[p],"delay":0.0})
	_elapsed = 0.0
	_old_blend = 0.0 if _old_texture != null else 1.0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)
	queue_redraw()

func _draw_film(image:Image,progress:float,cells:Dictionary) -> void:
	var lateral:float = (6.0 + float(posmod(_seed,4)) * 0.7) * _unit * (1.0 + (_volume - 1.0) * 0.08)
	var depth:float = (1.2 if _heap else 1.7) if _wall or _heap else 3.0 * _unit
	var center_y:float = 1.8 if _wall else (0.9 if _heap else 0.0)
	var phase:float = float(posmod(_seed,100)) * 0.061
	for y:int in range(-10,11):
		for x:int in range(-15,16):
			var p := Vector2(x,y)
			var xx:float = (p.x - _shear * 1.0) / maxf(lateral,1.0)
			var yy:float = (p.y - center_y - sin(p.x * 0.48 + phase) * 0.35) / depth
			# 偏心弯边、短尾与不同长宽比，取消梳齿、巨型分叉和厚实墙前岸。
			var field:float = xx * xx + yy * yy
			var edge:float = 1.0 + sin(p.x * 0.8 + phase) * 0.13
			if field > edge * lerpf(0.88,1.0,progress): continue
			if (_wall or _heap) and p.y < 0.0: continue
			var color:Color = Color("9b1a2b")
			if field > 0.65: color = Color("711126")
			elif p.y > center_y: color = Color("871528")
			color.a = 0.84 if _heap else (0.90 if _wall else 0.96)
			color = color.darkened((_volume - 1.0) * 0.08)
			_paint(image,p,color,cells)
	# 一条短渗流即可；深度严格受实体几何与小长度约束。
	if _wall and progress > 0.55 and _down.length_squared() > 0.01:
		for i:int in range(1 + int(progress * 3.0)):
			_paint(image,Vector2(float(posmod(_seed,5)) - 2.0,2.0) + _down.normalized() * i,Color("861426"),cells)

func _process(delta:float) -> void:
	_elapsed += delta
	_old_blend = minf(_old_blend + delta / 0.12,1.0)
	if _elapsed <= 0.40: queue_redraw()
	if _old_blend >= 1.0: _old_texture = null
	if _elapsed >= 1.8:
		self_modulate = Color(0.90,0.90,0.90,1.0)
		set_process(false)

func _draw() -> void:
	if _frames.is_empty(): return
	var phase:float = clampf(_elapsed / 0.28,0.0,1.0) * 4.0
	var index:int = mini(int(phase),4)
	var blend:float = phase - index
	if _old_texture != null: draw_texture(_old_texture,Vector2(-EXTENT,-EXTENT))
	draw_texture(_frames[index],Vector2(-EXTENT,-EXTENT),Color(1,1,1,_old_blend))
	if index < 4 and blend > 0.0:
		draw_texture(_frames[index + 1],Vector2(-EXTENT,-EXTENT),Color(1,1,1,blend * _old_blend))
