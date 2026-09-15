extends Node2D

# 有限的方向/形态图集缓存。每滴只提交一张像素贴图和最多三段无抗锯齿短尾。
# 不再逐帧扫描方形包围盒，也不逐像素提交 draw_rect。
const PATTERNS:Array[String] = [
	"......##../....#####./..########/#########./..######../....###...",
	".......#./.....###./...#####./#########/.#######./...####../.....#...",
	".....###./...######/.########/########./.######../...###...",
	"....##../..#####./########/.#######/..#####./....##..",
	".......##/.....####/...######/########./.######../...###...",
	".....##./...#####/.#######/########/..#####./....##..",
	".##/###/.#.", "##/#.", "#"]
static var _atlas:Dictionary = {}
static var _atlas_pixels:Dictionary = {}
var travel_direction:Vector2 = Vector2.RIGHT
var _trail:Array[Vector2] = []
var _clock:float = 0.0
var _variant:int = 0
var _size_class:int = 1
var _texture:Texture2D
var _key:int = -1
var _radius:float = 12.0
var _tail_width:float = 2.0
var _contact:bool = false
var _landing:bool = false
var _landing_age:float = 0.0
var _handoff:bool = false
var _handoff_age:float = 0.0

func configure(_length_value:float,width_value:float,_tint:Color,seed_value:int = 1) -> void:
	_variant = posmod(seed_value,6) if width_value >= 3.0 else (6 if width_value >= 1.5 else 7)
	_size_class = 2 if width_value >= 5.5 else (1 if width_value >= 3.0 else 0)
	_radius = 15.0 if _size_class == 2 else (12.0 if _size_class == 1 else 4.0)
	_tail_width = 3.0 if _size_class == 2 else (2.0 if _size_class == 1 else 1.0)
	_select_texture()

func collision_radius() -> float:
	return _radius

func advance(point:Vector2,direction_value:Vector2) -> void:
	if _trail.is_empty() or _trail.back().distance_squared_to(global_position) > 1.0:
		_trail.append(global_position)
	while _trail.size() > 3: _trail.pop_front()
	global_position = point
	travel_direction = direction_value
	_select_texture()
	queue_redraw()

func contact(point:Vector2,normal:Vector2) -> void:
	_contact = true
	_trail.clear()
	global_position = point + normal * 2.5
	travel_direction = normal.orthogonal()
	_select_texture()
	visible = true
	queue_redraw()

func _select_texture() -> void:
	var bin:int = posmod(int(round(travel_direction.angle() * 16.0 / TAU)),16)
	var key:int = _variant * 96 + _size_class * 32 + bin + (1024 if _contact else 0)
	if key == _key and _atlas_pixels.has(key): return
	_key = key
	if not _atlas.has(key) or not _atlas_pixels.has(key):
		var rows:PackedStringArray = PATTERNS[_variant].split("/")
		var scale_value:Vector2 = Vector2(1.7,1.55) if _size_class == 2 else (Vector2(1.4,1.25) if _size_class == 1 else Vector2.ONE)
		if _contact: scale_value = Vector2(1.3,0.45)
		var half := Vector2(rows[0].length(),rows.size()) * 0.5
		# 坐标逐像素逆取样只在缓存缺失时做一次；RGBA 图集最多 864 个小块。
		var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var angle:float = TAU * float(bin) / 16.0
		for y:int in range(32):
			for x:int in range(32):
				var p:Vector2 = (Vector2(x,y) + Vector2(0.5,0.5) - Vector2(16,16)).rotated(-angle) / scale_value + half
				var sx:int = int(floorf(p.x))
				var sy:int = int(floorf(p.y))
				if sy < 0 or sy >= rows.size() or sx < 0 or sx >= rows[sy].length() or rows[sy][sx] != "#": continue
				var color:Color = Color("a7192c")
				if sy > rows.size() / 2: color = Color("710e24")
				elif sy == 0: color = Color("c32b38")
				image.set_pixel(x,y,color)
				points.append(Vector2(x - 16,y - 16))
				colors.append(color)
		_atlas[key] = ImageTexture.create_from_image(image)
		_atlas_pixels[key] = {"pixels":points,"colors":colors}
	_texture = _atlas[key]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func landing_snapshot() -> Dictionary:
	var data:Dictionary = _atlas_pixels.get(_key,{})
	return {"pixels":data.get("pixels",PackedVector2Array()),"colors":data.get("colors",PackedColorArray()),"position":global_position.floor(),"direction":travel_direction,"source":weakref(self)}

func start_landing() -> void:
	_landing = true
	_landing_age = 0.0

func landing_resolved() -> void:
	_handoff = true
	_handoff_age = 0.0

func release_droplet() -> void:
	_tail_width = maxf(_tail_width * 0.85,1.0)

func _process(delta:float) -> void:
	_clock += delta
	if _landing:
		_landing_age += delta
		if _landing_age <= 0.12: queue_redraw()
	if _handoff:
		_handoff_age += delta
		self_modulate.a = clampf(1.0 - _handoff_age / 0.08,0.0,1.0)
		if _handoff_age >= 0.08:
			queue_free()
			return
	if _clock > 1.8: queue_free()

func _draw() -> void:
	if _texture == null: return
	var end:Vector2 = global_position
	var remaining:float = 22.0
	for i:int in range(_trail.size() - 1,-1,-1):
		var p:Vector2 = end.move_toward(_trail[i],remaining)
		var distance:float = end.distance_to(p)
		if distance > 0.1:
			draw_line(end.round() - global_position,p.round() - global_position,Color(0.54,0.078,0.157,clampf(1.0 - _landing_age / 0.10,0.0,1.0) if _landing else 1.0),maxf(1.0,roundf(_tail_width * remaining / 22.0)),false)
		remaining -= distance
		end = p
		if remaining <= 0.0: break
	draw_texture(_texture,global_position.floor() - global_position - Vector2(16,16))
