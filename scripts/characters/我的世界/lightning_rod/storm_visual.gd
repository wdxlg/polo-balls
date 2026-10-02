extends Node2D
## 避雷针的乌云、雨、电网与放电表现（纯视觉，不结算伤害，不持有玩法随机数）。
## 云：minecraft_clouds.gd 的局部云块（原版 clouds.png 的一块，同天空云的着色器与厚度），染成乌云色；
## 左右两侧的云转置 90°，让长边正对避雷针。闪电走共享雷电，电网与放电走共享电弧连线，放电圈走共享扩散环。
const CLOUDS = preload("res://scripts/effects/我的世界/minecraft_clouds.gd")
const ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const ARC = preload("res://scripts/effects/我的世界/trident_arc.gd")
const PALETTE = preload("res://scripts/effects/我的世界/mc_electric_palette.gd")
const ROD_AUDIO = preload("res://scripts/characters/我的世界/lightning_rod/lightning_rod_audio.gd")
const RAIN_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/lightning_rod/rain.png")
## clouds.png 里取作乌云的那一块（7×4 格）。
const CLOUD_REGION:Rect2i = Rect2i(155,56,7,4)
const CLOUD_TINT:Color = Color(0.36,0.38,0.44,0.95)
const CLOUD_FLASH:Color = Color(0.82,0.9,1.0,1.0)
const RAIN_TINT:Color = Color(0.72,0.8,1.0,0.5)
const RAIN_FALL:float = 60.0
const CLOUD_FADE:float = 0.9
const NET_FADE:float = 0.25
const DISCHARGE_TIME:float = 0.26
const DIRS:Array[Vector2] = [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]

static var _masks:Array[Image] = []

## 所属避雷针（动态访问它的云、电网与能量字段）。
var rod
var _time:float = 0.0
var _patch:Polygon2D
var _patch_dir:int = -1
var _fading:Array[Dictionary] = []
var _discharges:Array[Dictionary] = []
var _old_nets:Array[Dictionary] = []
var _flash:float = 0.0
var _rain_wait:float = 0.0
var _dissipating:bool = false


## 云的格子掩码：0 = 长边水平（上/下），1 = 转置（左/右）。四周各有一圈空格。
static func cloud_mask(dir_index:int) -> Image:
	if _masks.is_empty():
		_masks.append(CLOUDS.cloud_piece(CLOUD_REGION,false))
		_masks.append(CLOUDS.cloud_piece(CLOUD_REGION,true))
	return _masks[1 if dir_index >= 2 else 0]


## 云块中心（相对云心，单位世界像素）。
static func cloud_cells(dir_index:int) -> Array[Vector2]:
	var result:Array[Vector2] = []
	var mask:Image = cloud_mask(dir_index)
	if mask == null: return result
	var size := Vector2(mask.get_size())
	for y:int in range(mask.get_height()):
		for x:int in range(mask.get_width()):
			if mask.get_pixel(x,y).a > 0.5: result.append((Vector2(x,y) + Vector2(0.5,0.5) - size * 0.5) * CLOUDS.CELL_SIZE)
	return result


## 云的实际占地半尺寸（不含空格圈）。
static func cloud_half_extent(dir_index:int) -> Vector2:
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for cell:Vector2 in cloud_cells(dir_index):
		low = low.min(cell)
		high = high.max(cell)
	if low.x > high.x: return Vector2.ONE * CLOUDS.CELL_SIZE
	return (high - low) * 0.5 + Vector2.ONE * CLOUDS.CELL_SIZE * 0.5


## 云朝避雷针一侧的边缘点：每一列（垂直于方向的坐标）离针最近的云块外沿中点（朝下时含云的厚度）。
static func facing_points(dir_index:int,toward:Vector2) -> Array[Vector2]:
	var best:Dictionary = {}
	for cell:Vector2 in cloud_cells(dir_index):
		var lane:float = cell.y if absf(toward.x) > 0.5 else cell.x
		var key:int = int(roundf(lane / CLOUDS.CELL_SIZE * 2.0))
		if not best.has(key) or cell.dot(toward) > Vector2(best[key]).dot(toward): best[key] = cell
	var result:Array[Vector2] = []
	var edge:float = CLOUDS.CELL_SIZE * 0.5 + (CLOUDS.THICKNESS if toward.y > 0.5 else 0.0)
	for key:Variant in best: result.append(Vector2(best[key]) + toward * edge)
	return result


func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 150
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
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
	if _running(): _advance(delta)
	_sync_patches()
	queue_redraw()


func _advance(delta:float) -> void:
	_time += delta
	_flash = maxf(_flash - delta,0.0)
	for list:Array in [_fading,_discharges,_old_nets]:
		for item:Dictionary in list: item.age = float(item.age) + delta
	for cloud:Dictionary in _fading:
		if float(cloud.age) >= CLOUD_FADE and is_instance_valid(cloud.patch): (cloud.patch as Node).queue_free()
	_fading.assign(_fading.filter(func(c:Dictionary) -> bool: return float(c.age) < CLOUD_FADE))
	_discharges.assign(_discharges.filter(func(d:Dictionary) -> bool: return float(d.age) < DISCHARGE_TIME))
	_old_nets.assign(_old_nets.filter(func(n:Dictionary) -> bool: return float(n.age) < NET_FADE))
	if _dissipating:
		if _fading.is_empty() and _old_nets.is_empty() and _discharges.is_empty(): queue_free()
		return
	_tick_rain(delta)


## 本端是否能看到当前的云（与 rod 的方向同步）。
func _current_visible() -> bool:
	return not _dissipating and is_instance_valid(rod) and rod.cloud_visible()


func _new_patch(dir_index:int) -> Polygon2D:
	var mask:Image = cloud_mask(dir_index)
	if mask == null: return null
	var patch:Polygon2D = CLOUDS.make_patch(mask,CLOUD_TINT)
	patch.name = "StormCloud"
	add_child(patch)
	return patch


func _sync_patches() -> void:
	if _current_visible():
		if _patch_dir != int(rod.dir_index) or not is_instance_valid(_patch):
			if is_instance_valid(_patch): _patch.queue_free()
			_patch = _new_patch(int(rod.dir_index))
			_patch_dir = int(rod.dir_index)
		if is_instance_valid(_patch):
			CLOUDS.place_patch(_patch,rod.cloud_position)
			# 聚云：前 60% 的聚云时间里渐显；临近落雷时云底闪烁。
			var grow:float = clampf(float(rod.cycle_age) / maxf(float(rod.gather_time) * 0.6,0.05),0.0,1.0)
			var flash:float = _flash / 0.12
			var until:float = rod.time_to_next_volley()
			if until >= 0.0 and until < 0.45 and int(floor(_time * 14.0)) % 2 == 0: flash = maxf(flash,0.35)
			var tint:Color = CLOUD_TINT.lerp(CLOUD_FLASH,clampf(flash,0.0,1.0))
			_set_cloud(_patch,tint,grow)
	elif is_instance_valid(_patch):
		_patch.queue_free()
		_patch = null
		_patch_dir = -1
	for cloud:Dictionary in _fading:
		if not is_instance_valid(cloud.patch): continue
		var fade:float = 1.0 - float(cloud.age) / CLOUD_FADE
		CLOUDS.place_patch(cloud.patch,Vector2(cloud.pos) + DIRS[int(cloud.dir)] * float(cloud.age) * 40.0)
		_set_cloud(cloud.patch,CLOUD_TINT,float(cloud.alpha) * fade * fade)


func _set_cloud(patch:Polygon2D,tint:Color,alpha:float) -> void:
	var material_value:ShaderMaterial = patch.material as ShaderMaterial
	material_value.set_shader_parameter("cloud_tint",tint)
	material_value.set_shader_parameter("cloud_alpha",clampf(alpha,0.0,1.0))


func _tick_rain(delta:float) -> void:
	_rain_wait -= delta
	if _rain_wait > 0.0 or not rod.cloud_visible(): return
	var ticket:Dictionary = ROD_AUDIO.play(rod,ROD_AUDIO.Kind.RAIN,rod.cloud_position,-17.0)
	var stream:AudioStream = ticket.get("stream") as AudioStream
	_rain_wait = stream.get_length() * 0.92 if stream != null else 1.0


## 闪电落点追踪针尖（共享雷电在命中前读取父节点的这个方法）。
func _self_foot_world_position() -> Vector2:
	return rod.tip_world_position() if is_instance_valid(rod) else global_position


## 共享雷电：从云边 start 劈向针尖；落点小范围冲击圈就是伤害半径。
func add_bolt(start:Vector2,end:Vector2,seed_value:int,radius:float,first:bool) -> Node2D:
	_flash = 0.12
	return ABILITIES.lightning(self,end,seed_value,radius,0.001,{"name":"LightningRodBolt",
		"fields":{"origin_world":start,"pause_with_battle":true},
		"tuning":{"thunder_volume_db":-8.0 if first else -40.0,"explosion_volume_db":-13.0 if first else -17.0}})


func add_discharge(seed_value:int,radius:float) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(absi(seed_value),1)
	var arcs:Array[Dictionary] = []
	var count:int = random.randi_range(6,8)
	for i:int in range(count):
		var angle:float = TAU * (float(i) + random.randf_range(-0.3,0.3)) / float(count)
		arcs.append({"angle":angle,"reach":random.randf_range(0.75,1.0) * radius,"seed":random.randi_range(1,1 << 30)})
	_discharges.append({"age":0.0,"arcs":arcs})
	var world:Node = get_tree().current_scene if is_inside_tree() else null
	if world != null and is_instance_valid(rod):
		ABILITIES.expanding_ring(world,rod.global_position,radius,{"name":"LightningRodDischargeRing","lifetime":DISCHARGE_TIME,"end_scale":1.08,
			"palette":[PALETTE.OUTER,PALETTE.MIDDLE,PALETTE.CORE],"z_index":149})


func release_cloud(position_value:Vector2,dir_index:int,cycle_age:float) -> void:
	if dir_index < 0 or not is_instance_valid(_patch): return
	var alpha:float = 1.0
	if is_instance_valid(rod): alpha = clampf(cycle_age / maxf(float(rod.gather_time) * 0.6,0.05),0.0,1.0)
	_fading.append({"pos":position_value,"dir":dir_index,"age":0.0,"alpha":alpha,"patch":_patch})
	_patch = null
	_patch_dir = -1


func release_nets(nets:Array,cloud_at:Vector2,tip:Vector2) -> void:
	for net:Dictionary in nets:
		_old_nets.append({"a":cloud_at + Vector2(net.offset),"b":tip,"seed":int(net.seed),"age":0.0})


func dissipate() -> void:
	if _dissipating: return
	release_nets(rod.nets,rod.cloud_position,rod.tip_world_position())
	release_cloud(rod.cloud_position,rod.dir_index,rod.cycle_age)
	_dissipating = true
	_discharges.clear()


func _draw() -> void:
	if is_instance_valid(_patch) and _current_visible():
		_draw_rain(rod.cloud_position,int(rod.dir_index),float((_patch.material as ShaderMaterial).get_shader_parameter("cloud_alpha")))
	for cloud:Dictionary in _fading:
		var fade:float = 1.0 - float(cloud.age) / CLOUD_FADE
		_draw_rain(Vector2(cloud.pos) + DIRS[int(cloud.dir)] * float(cloud.age) * 40.0,int(cloud.dir),float(cloud.alpha) * fade * fade)
	_draw_nets()
	if is_instance_valid(rod):
		for discharge:Dictionary in _discharges: _draw_discharge(discharge)


## 原版 rain.png 从每块云底往下落。
func _draw_rain(center:Vector2,dir_index:int,alpha:float) -> void:
	if alpha <= 0.0: return
	var cells:Array[Vector2] = cloud_cells(dir_index)
	var cell_size:float = CLOUDS.CELL_SIZE
	for i:int in range(cells.size()):
		var top:Vector2 = center + cells[i] + Vector2(-cell_size * 0.5,0.0)
		var rect := Rect2(top,Vector2(cell_size,cell_size * 0.5 + CLOUDS.THICKNESS + RAIN_FALL))
		var source := Rect2(float(i * 7 % 56),fposmod(-_time * 96.0 + float(i * 37),256.0),cell_size * 0.5,rect.size.y * 0.5)
		draw_texture_rect_region(RAIN_TEXTURE,rect,source,Color(RAIN_TINT,RAIN_TINT.a * alpha))


func _draw_nets() -> void:
	if not _dissipating and is_instance_valid(rod):
		var tip:Vector2 = rod.tip_world_position()
		var jitter:float = maxf(float(rod.net_width),3.0)
		for net:Dictionary in rod.nets:
			var left:float = float(rod.net_lifetime) - float(net.age)
			if left <= 0.0: continue
			var start:Vector2 = rod.cloud_position + Vector2(net.offset)
			ARC.paint(self,start,tip,int(net.seed),_time,clampf(left / NET_FADE,0.0,1.0),jitter,_segments(start,tip))
	for net:Dictionary in _old_nets:
		ARC.paint(self,net.a,net.b,int(net.seed),_time,0.6 * (1.0 - float(net.age) / NET_FADE),5.0,_segments(net.a,net.b))


func _segments(a:Vector2,b:Vector2) -> int:
	return clampi(int(a.distance_to(b) / 28.0),6,32)


func _draw_discharge(discharge:Dictionary) -> void:
	var alpha:float = 1.0 - clampf(float(discharge.age) / DISCHARGE_TIME,0.0,1.0)
	var tip:Vector2 = rod.tip_world_position()
	var center:Vector2 = rod.global_position
	for arc:Dictionary in discharge.arcs:
		var end:Vector2 = center + Vector2.from_angle(float(arc.angle)) * float(arc.reach)
		ARC.paint(self,tip,end,int(arc.seed),float(discharge.age) + float(arc.angle),alpha,6.0,8)
