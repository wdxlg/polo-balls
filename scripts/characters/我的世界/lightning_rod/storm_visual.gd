extends Node2D
## 避雷针的乌云、闪电、电网、放电与火花表现（纯视觉，不结算伤害，不持有玩法随机数）。
## 云形取自原版 environment/clouds.png 的一块（storm_cloud.png），按原版云的方式画成
## 顶面 + 厚度的方块云；左右两侧的云转置 90°，让长边始终正对避雷针。
const PALETTE = preload("res://scripts/effects/我的世界/mc_electric_palette.gd")
const ARC = preload("res://scripts/effects/我的世界/pixel_arc.gd")
const ROD_AUDIO = preload("res://scripts/characters/我的世界/lightning_rod/lightning_rod_audio.gd")
const CLOUD_MASK:Texture2D = preload("res://Images/characters/我的世界/lightning_rod/storm_cloud.png")
const RAIN_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/lightning_rod/rain.png")
const GLOW_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/lightning_rod/glow.png")
const CELL:float = 16.0
const THICKNESS:float = CELL / 3.0
const CLOUD_TOP:Color = Color(0.43,0.45,0.51,0.93)
const CLOUD_SIDE:Color = Color(0.25,0.26,0.31,0.95)
const CLOUD_FLASH:Color = Color(0.78,0.86,1.0,0.95)
const RAIN_TINT:Color = Color(0.72,0.8,1.0,0.5)
const RAIN_FALL:float = 44.0
const CELL_GROW:float = 0.35
const CLOUD_FADE:float = 0.9
const BOLT_TIME:float = 0.24
const NET_FADE:float = 0.25
const IMPACT_RING_TIME:float = 0.42
const DISCHARGE_TIME:float = 0.26
const SPARK_LIMIT:int = 90
const DIRS:Array[Vector2] = [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]

static var _mask_cells:Array[Vector2] = []

## 所属避雷针（动态访问它的云、电网与能量字段）。
var rod
var _time:float = 0.0
var _fading:Array = []
var _bolts:Array = []
var _impacts:Array = []
var _discharges:Array = []
var _sparks:Array = []
var _old_nets:Array = []
var _flash:float = 0.0
var _spark_carry:float = 0.0
var _rain_wait:float = 0.0
var _dissipating:bool = false
var _gather:float = 3.0
var _random := RandomNumberGenerator.new()


## 云块中心（相对云心，单位像素）。dir_index 0/1 = 上/下：长边水平；2/3 = 左/右：转置。
static func cloud_cells(dir_index:int) -> Array[Vector2]:
	if _mask_cells.is_empty():
		var image:Image = CLOUD_MASK.get_image()
		if image != null:
			if image.is_compressed(): image.decompress()
			var size:Vector2 = Vector2(image.get_width(),image.get_height())
			for y:int in range(image.get_height()):
				for x:int in range(image.get_width()):
					if image.get_pixel(x,y).a > 0.5:
						_mask_cells.append((Vector2(x,y) + Vector2(0.5,0.5) - size * 0.5) * CELL)
	var result:Array[Vector2] = []
	for cell:Vector2 in _mask_cells:
		result.append(Vector2(cell.y,cell.x) if dir_index >= 2 else cell)
	return result


## 云朝向避雷针一侧的边缘点：每一列（垂直于方向的坐标）离针最近的云块外沿中点。
static func facing_points(dir_index:int,toward:Vector2) -> Array[Vector2]:
	var best:Dictionary = {}
	for cell:Vector2 in cloud_cells(dir_index):
		var lane:float = cell.y if dir_index >= 2 else cell.x
		var depth:float = cell.dot(toward)
		var key:int = int(roundf(lane / CELL * 2.0))
		if not best.has(key) or depth > float(best[key].dot(toward)): best[key] = cell
	var result:Array[Vector2] = []
	for key:Variant in best: result.append(Vector2(best[key]) + toward * CELL * 0.5)
	return result


## 两点间的折线闪电路径：中段随机折角，两端收拢；同一 seed 各端一致。
static func bolt_path(a:Vector2,b:Vector2,seed_value:int,bend:float = 24.0) -> PackedVector2Array:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(absi(seed_value),1)
	var length:float = a.distance_to(b)
	var count:int = clampi(int(length / 22.0),5,14)
	var normal:Vector2 = (b - a).normalized().orthogonal() if length > 0.01 else Vector2.RIGHT
	var limit:float = minf(bend,length * 0.16)
	var walk:float = 0.0
	var points := PackedVector2Array([a])
	for i:int in range(1,count):
		var f:float = float(i) / float(count)
		walk = clampf(walk + random.randf_range(-1.0,1.0) * limit * 0.9,-limit,limit)
		points.append(a.lerp(b,f) + normal * walk * sin(PI * f))
	points.append(b)
	return points


func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 150
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_random.randomize()
	add_to_group("BattleTransient")


func _running() -> bool:
	if Game.now_stop_state or get_tree().paused: return false
	# 避雷针死亡后残云和电网照常散完。
	return _dissipating or (is_instance_valid(rod) and rod.is_combat_runtime_active())


func _process(delta:float) -> void:
	global_transform = Transform2D.IDENTITY
	if not is_instance_valid(rod) and not _dissipating:
		queue_free()
		return
	if _running():
		_advance(delta)
	queue_redraw()


func _advance(delta:float) -> void:
	_time += delta
	_flash = maxf(_flash - delta,0.0)
	for list:Array in [_fading,_bolts,_impacts,_discharges,_old_nets]:
		for item:Dictionary in list: item.age = float(item.age) + delta
	_fading = _fading.filter(func(c:Dictionary) -> bool: return float(c.age) < CLOUD_FADE)
	_bolts = _bolts.filter(func(b:Dictionary) -> bool: return float(b.age) < BOLT_TIME)
	_impacts = _impacts.filter(func(i:Dictionary) -> bool: return float(i.age) < IMPACT_RING_TIME)
	_discharges = _discharges.filter(func(d:Dictionary) -> bool: return float(d.age) < DISCHARGE_TIME)
	_old_nets = _old_nets.filter(func(n:Dictionary) -> bool: return float(n.age) < NET_FADE)
	for spark:Dictionary in _sparks:
		spark.age = float(spark.age) + delta
		spark.pos = Vector2(spark.pos) + Vector2(spark.vel) * delta
		spark.vel = Vector2(spark.vel) * pow(0.04,delta)
	_sparks = _sparks.filter(func(s:Dictionary) -> bool: return float(s.age) < float(s.life))
	if _dissipating:
		if _fading.is_empty() and _bolts.is_empty() and _old_nets.is_empty() and _sparks.is_empty() and _discharges.is_empty(): queue_free()
		return
	_emit_ambient_sparks(delta)
	_tick_rain(delta)


func _emit_ambient_sparks(delta:float) -> void:
	var rate:float = 0.0
	var tip:Vector2 = rod.tip_world_position()
	var until:float = rod.time_to_next_volley()
	if until >= 0.0 and until < 0.45: rate += 34.0
	var ratio:float = rod.storm_charge_ratio()
	if ratio > rod.tremble_start: rate += 46.0 * (ratio - rod.tremble_start) / maxf(1.0 - rod.tremble_start,0.01)
	_spark_carry += rate * delta
	while _spark_carry >= 1.0:
		_spark_carry -= 1.0
		add_spark(tip,70.0)
		if until >= 0.0 and until < 0.45 and rod.cloud_visible():
			var points:Array[Vector2] = facing_points(rod.dir_index,-rod.direction_vector())
			if not points.is_empty(): add_spark(rod.cloud_position + points[_random.randi_range(0,points.size() - 1)],50.0)


func _tick_rain(delta:float) -> void:
	_rain_wait -= delta
	if _rain_wait > 0.0 or not rod.cloud_visible(): return
	var ticket:Dictionary = ROD_AUDIO.play(rod,ROD_AUDIO.Kind.RAIN,rod.cloud_position,-17.0)
	var stream:AudioStream = ticket.get("stream") as AudioStream
	_rain_wait = stream.get_length() * 0.92 if stream != null else 1.0


func add_spark(point:Vector2,speed:float) -> void:
	if _sparks.size() >= SPARK_LIMIT: _sparks.pop_front()
	var angle:float = _random.randf_range(0.0,TAU)
	_sparks.append({"pos":point + Vector2.from_angle(angle) * _random.randf_range(0.0,6.0),"vel":Vector2.from_angle(angle) * _random.randf_range(speed * 0.35,speed),
		"age":0.0,"life":_random.randf_range(0.22,0.42),"size":_random.randf_range(3.0,6.0)})


func add_bolt(start:Vector2,end:Vector2,seed_value:int) -> void:
	_bolts.append({"a":start,"b":end,"seed":seed_value,"age":0.0})
	_impacts.append({"pos":rod.global_position,"age":0.0})
	_flash = 0.12
	for i:int in range(6): add_spark(end,120.0)


func add_discharge(seed_value:int,radius:float) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(absi(seed_value),1)
	var arcs:Array[Dictionary] = []
	var count:int = random.randi_range(6,8)
	for i:int in range(count):
		var angle:float = TAU * (float(i) + random.randf_range(-0.3,0.3)) / float(count)
		arcs.append({"angle":angle,"reach":random.randf_range(0.75,1.0) * radius,"seed":random.randi()})
	_discharges.append({"age":0.0,"arcs":arcs,"radius":radius})
	for i:int in range(10): add_spark(rod.global_position,160.0)


func release_cloud(position_value:Vector2,dir_index:int,cycle_age:float) -> void:
	if dir_index < 0: return
	_fading.append({"pos":position_value,"dir":dir_index,"age":0.0,"grown":cycle_age})


func release_nets(nets:Array,cloud_at:Vector2,tip:Vector2) -> void:
	for net:Dictionary in nets:
		_old_nets.append({"a":cloud_at + Vector2(net.offset),"b":tip,"seed":int(net.seed),"age":0.0})


func dissipate() -> void:
	if _dissipating: return
	_dissipating = true
	_gather = float(rod.gather_time)
	_impacts.clear()
	_discharges.clear()
	release_nets(rod.nets,rod.cloud_position,rod.tip_world_position())
	release_cloud(rod.cloud_position,rod.dir_index,rod.cycle_age)


func _draw() -> void:
	for cloud:Dictionary in _fading:
		var fade:float = 1.0 - float(cloud.age) / CLOUD_FADE
		var drift:Vector2 = DIRS[int(cloud.dir)] * float(cloud.age) * 40.0
		_draw_cloud(Vector2(cloud.pos) + drift,int(cloud.dir),float(cloud.grown),fade * fade,0.0)
	if not _dissipating and is_instance_valid(rod) and rod.cloud_visible():
		_draw_cloud(rod.cloud_position,rod.dir_index,rod.cycle_age,1.0,_flash / 0.12)
	_draw_nets()
	for bolt:Dictionary in _bolts: _draw_bolt(bolt)
	if is_instance_valid(rod):
		for impact:Dictionary in _impacts: _draw_impact(impact)
		for discharge:Dictionary in _discharges: _draw_discharge(discharge)
	for spark:Dictionary in _sparks:
		var life:float = float(spark.life)
		var alpha:float = clampf(1.0 - float(spark.age) / life,0.0,1.0)
		var size:float = float(spark.size)
		draw_texture_rect(GLOW_TEXTURE,Rect2(Vector2(spark.pos) - Vector2(size,size) * 0.5,Vector2(size,size)),false,Color(0.82,0.92,1.0,alpha))


## 聚云：云块按离中心远近依次长出（带固定扰动），每块 CELL_GROW 秒从小变大、渐显。
func _draw_cloud(center:Vector2,dir_index:int,age:float,alpha:float,flash:float) -> void:
	var cells:Array[Vector2] = cloud_cells(dir_index)
	if cells.is_empty(): return
	if is_instance_valid(rod): _gather = float(rod.gather_time)
	var gather:float = maxf(_gather - CELL_GROW,0.05)
	var reach:float = 1.0
	for cell:Vector2 in cells: reach = maxf(reach,cell.length())
	var faces:Array[Dictionary] = []
	for i:int in range(cells.size()):
		var cell:Vector2 = cells[i]
		var order:float = clampf(cell.length() / reach * 0.8 + fposmod(sin(float(i) * 12.9898) * 43758.5453,1.0) * 0.2,0.0,1.0)
		var grow:float = clampf((age - order * gather) / CELL_GROW,0.0,1.0)
		if grow <= 0.0: continue
		var size:float = CELL * lerpf(0.45,1.0,1.0 - pow(1.0 - grow,3.0))
		faces.append({"rect":Rect2(center + cell - Vector2(size,size) * 0.5,Vector2(size,size)),"alpha":grow * alpha,"index":i})
	for face:Dictionary in faces:
		var rect:Rect2 = face.rect
		var rain_rect := Rect2(rect.position + Vector2(0.0,rect.size.y * 0.5),Vector2(rect.size.x,rect.size.y * 0.5 + THICKNESS + RAIN_FALL))
		var source := Rect2(float(int(face.index) * 7 % 56),fposmod(-_time * 96.0 + float(int(face.index) * 37),256.0),rect.size.x * 0.5,rain_rect.size.y * 0.5)
		draw_texture_rect_region(RAIN_TEXTURE,rain_rect,source,Color(RAIN_TINT,RAIN_TINT.a * float(face.alpha)))
	for face:Dictionary in faces:
		var rect:Rect2 = face.rect
		draw_rect(Rect2(rect.position + Vector2(0.0,THICKNESS),rect.size),Color(CLOUD_SIDE,CLOUD_SIDE.a * float(face.alpha)))
	for face:Dictionary in faces:
		var top:Color = CLOUD_TOP.lerp(CLOUD_FLASH,clampf(flash,0.0,1.0))
		draw_rect(face.rect,Color(top,top.a * float(face.alpha)))


func _draw_layers(points:PackedVector2Array,widths:Array,alpha:float) -> void:
	var colors:Array[Color] = [Color(PALETTE.OUTER,0.3),Color(PALETTE.MIDDLE,0.55),Color(PALETTE.CORE,0.85),Color(PALETTE.CORE,1.0)]
	var offset:int = colors.size() - widths.size()
	for layer:int in range(widths.size()):
		var color:Color = colors[layer + offset]
		draw_polyline(points,Color(color,color.a * alpha),float(widths[layer]),false)


## 原版闪电的两次闪烁：0–0.09 秒第一笔，0.09–0.13 秒熄灭，之后换一条折线再闪一次。
func _draw_bolt(bolt:Dictionary) -> void:
	var age:float = float(bolt.age)
	if age > 0.09 and age < 0.13: return
	var stroke:int = 0 if age <= 0.09 else 1
	var points:PackedVector2Array = bolt_path(bolt.a,bolt.b,int(bolt.seed) + stroke * 104729)
	var alpha:float = 1.0 if stroke == 0 else 0.85 * (1.0 - (age - 0.13) / (BOLT_TIME - 0.13))
	_draw_layers(points,[20.0,10.0,5.0,2.5],alpha)
	if points.size() > 4:
		var random := RandomNumberGenerator.new()
		random.seed = int(bolt.seed) * 31 + stroke
		var root:int = random.randi_range(1,points.size() / 2)
		var heading:Vector2 = (Vector2(bolt.b) - Vector2(bolt.a)).normalized()
		var side:Vector2 = heading.orthogonal() * (1.0 if random.randf() < 0.5 else -1.0)
		var fork := PackedVector2Array([points[root]])
		for i:int in range(3): fork.append(fork[-1] + (heading + side * random.randf_range(0.5,1.2)).normalized() * random.randf_range(12.0,20.0))
		_draw_layers(fork,[8.0,3.5,1.5],alpha * 0.8)


func _draw_nets() -> void:
	var flicker:int = int(floor(_time * 20.0))
	if not _dissipating and is_instance_valid(rod):
		var tip:Vector2 = rod.tip_world_position()
		for net:Dictionary in rod.nets:
			var left:float = float(rod.net_lifetime) - float(net.age)
			if left <= 0.0: continue
			var alpha:float = clampf(left / NET_FADE,0.0,1.0) * (0.72 + 0.28 * sin(float(flicker) * 2.3 + float(net.seed % 97)))
			_draw_net(rod.cloud_position + Vector2(net.offset),tip,int(net.seed) + flicker * 7919,alpha)
	for net:Dictionary in _old_nets:
		_draw_net(net.a,net.b,int(net.seed) + flicker * 7919,0.6 * (1.0 - float(net.age) / NET_FADE))


func _draw_net(a:Vector2,b:Vector2,seed_value:int,alpha:float) -> void:
	if alpha <= 0.0: return
	var jitter:float = maxf(float(rod.net_width) - 2.0,1.0) if is_instance_valid(rod) else 5.0
	var points:PackedVector2Array = bolt_path(a,b,seed_value,jitter)
	_draw_layers(points,[9.0,4.0,1.6],alpha)


func _draw_impact(impact:Dictionary) -> void:
	var p:float = clampf(float(impact.age) / IMPACT_RING_TIME,0.0,1.0)
	var fade:float = pow(1.0 - p,1.25)
	var radius:float = float(rod.impact_radius)
	var center:Vector2 = impact.pos
	ARC.draw(self,center,radius,0.0,TAU,64,Color(PALETTE.OUTER,0.3 * fade),5.5,true)
	ARC.draw(self,center,radius,0.0,TAU,64,Color(PALETTE.MIDDLE,0.75 * fade),3.0,true)
	ARC.draw(self,center,radius,0.0,TAU,64,Color(PALETTE.CORE,fade),1.6,true)
	draw_circle(center,10.0,Color(PALETTE.CORE,0.45 * pow(1.0 - p,4.0)))


func _draw_discharge(discharge:Dictionary) -> void:
	var p:float = clampf(float(discharge.age) / DISCHARGE_TIME,0.0,1.0)
	var alpha:float = 1.0 - p
	var center:Vector2 = rod.global_position
	var radius:float = float(discharge.radius)
	ARC.draw(self,center,radius,0.0,TAU,64,Color(PALETTE.MIDDLE,0.6 * alpha),3.0,true)
	ARC.draw(self,center,radius,0.0,TAU,64,Color(PALETTE.CORE,0.9 * alpha),1.4,true)
	var tip:Vector2 = rod.tip_world_position()
	var flicker:int = int(floor(float(discharge.age) * 30.0))
	for arc:Dictionary in discharge.arcs:
		var end:Vector2 = center + Vector2.from_angle(float(arc.angle)) * float(arc.reach)
		_draw_layers(bolt_path(tip,end,int(arc.seed) + flicker * 131,10.0),[7.0,3.0,1.4],alpha)
