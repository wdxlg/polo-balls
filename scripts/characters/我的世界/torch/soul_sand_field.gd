extends Node2D
## 灵魂沙地形（火把）：World 下的单例。说明见 MCP_CONTEXT（火把条目）。
const GEOMETRY = preload("res://classes/map_tile_geometry.gd")
const TEXTURE:Texture2D = preload("res://Images/effects/我的世界/草方块背景/soul_sand.png")
const SCRIPT_PATH:String = "res://scripts/characters/我的世界/torch/soul_sand_field.gd"
const NODE_NAME:String = "MCSoulSandField"
const GROUND_Z:int = -3 # 与苔藓/雪地同层：地面之上、角色之下
const RING_Z:int = -4 # 与立体墙同层：墙/墙影/云是 top_level，同层排在普通节点之后画，所以外圈在云(-5)之上、墙之下
## 有立体墙的主题：外圈向内收进墙下的格数，墙外只露出 1 - 该值。
const RING_INSET_CELLS:float = 0.5
## 新格在这么多秒内按像素随机长满；整格长满才是正式灵魂沙（减速、火把充能、灵魂火）。
const GROW_SECONDS:float = 2.0
## 每长一个像素，有这个概率顺带向相邻、还没轮到的格子溢出一个像素；溢出最多占那格的比例（不算正式灵魂沙）。
const SPILL_CHANCE:float = 0.35
const SPILL_CAP:float = 0.35
## 像素覆盖图分块：每块 CHUNK_CELLS×CHUNK_CELLS 格，只上传有变化的块。
const CHUNK_CELLS:int = 8
const MASK_SHADER:Shader = preload("res://scripts/characters/我的世界/torch/soul_sand_mask.gdshader")
const SLOW_KEY:StringName = &"mc_soul_sand"
const SLOW_CHECK_INTERVAL:float = 0.1
const ENCHANTS_PATH:String = "res://scripts/effects/我的世界/mc_enchantments.gd"
const SEND_INTERVAL:float = 0.1
const FADE_SECONDS:float = 0.8
const DIRS:Array[Vector2i] = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]

## 从开始蔓延到铺满全图大约需要的战斗秒数。
@export var full_cover_seconds:float = 150.0
## 每次从前沿随机抽几个候选、取阻力最低者：1 为均匀随机，越大越容易长出伸向内部的细枝。
@export var tournament_size:int = 3

var grid_size:Vector2 = Vector2.ONE * 16.0
var grid_origin:Vector2 = Vector2.ZERO
var cells:Dictionary = {}
var floor_cells:Dictionary = {}
var ring_rects:Array[Rect2] = []
var _frontier:Array[Vector2i] = []
var _frontier_at:Dictionary = {}
var _resistance:Dictionary = {}
var _budget:float = 0.0
var _pending:PackedInt32Array = PackedInt32Array()
var _send_left:float = 0.0
var _grid_key:String = ""
var _grid_check_left:float = 0.5
var _owner_check_left:float = 0.5
var _retiring:bool = false
var _fade:float = 1.0
var _rng := RandomNumberGenerator.new()
var _ring_view:Node2D
var _mask_view:Node2D
## 本地战斗时钟：cells 里存每格出现时刻，长满判断与生长动画都用它。
var _clock:float = 0.0
var _growing:Array[Vector2i] = []
var _grow_from:Dictionary = {}
## 像素覆盖（纯视觉，各端本地随机）：_covered 覆盖地面包围盒，每格 _px×_px 个像素。
var _px_rng := RandomNumberGenerator.new()
var _px:int = 16
var _px_origin:Vector2i = Vector2i.ZERO
var _px_w:int = 0
var _px_h:int = 0
var _covered:PackedByteArray = PackedByteArray()
var _cell_count:Dictionary = {}
var _px_frontier:Dictionary = {}
var _grow_start:Dictionary = {}
var _chunks:Dictionary = {}
var _slow_left:float = 0.0


static func ensure(context:Node) -> Node2D:
	var world:Node = _world_of(context)
	if world == null: return null
	var existing:Node = world.get_node_or_null(NODE_NAME)
	if is_instance_valid(existing):
		if not existing.is_queued_for_deletion() and not bool(existing.get("_retiring")): return existing as Node2D
		# 重开/复活时旧地形可能还在淡出：让出固定名字，新地形保持稳定的查找与 RPC 路径。
		existing.name = "RetiredMCSoulSandField_" + str(existing.get_instance_id())
	var field:Node2D = load(SCRIPT_PATH).new()
	field.name = NODE_NAME
	field.set_multiplayer_authority(world.get_multiplayer_authority())
	world.add_child(field)
	return field


static func find(context:Node) -> Node2D:
	var world:Node = _world_of(context)
	if world == null: return null
	var existing:Node = world.get_node_or_null(NODE_NAME)
	return existing as Node2D if is_instance_valid(existing) and not existing.is_queued_for_deletion() else null


static func _world_of(context:Node) -> Node:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var world:Node = context
	while is_instance_valid(world) and not world.has_method("_current_map_node"): world = world.get_parent()
	return world if is_instance_valid(world) else context.get_tree().current_scene


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MCSoulSandField")
	z_as_relative = false
	z_index = GROUND_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ring_view = Node2D.new()
	_ring_view.name = "OuterRing"
	_ring_view.z_as_relative = false
	_ring_view.z_index = RING_Z
	_ring_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ring_view.draw.connect(_draw_ring)
	add_child(_ring_view)
	_mask_view = Node2D.new()
	_mask_view.name = "SandPixels"
	_mask_view.z_as_relative = false
	_mask_view.z_index = GROUND_Z
	_mask_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mask_material := ShaderMaterial.new()
	mask_material.shader = MASK_SHADER
	mask_material.set_shader_parameter("sand_texture",TEXTURE)
	mask_material.set_shader_parameter("cells_per_chunk",float(CHUNK_CELLS))
	_mask_view.material = mask_material
	_mask_view.draw.connect(_draw_mask)
	add_child(_mask_view)
	_px_rng.randomize()
	_rng.seed = Game.battle_rng_seed_or("mc_torch_soul_sand",int(Time.get_ticks_usec()) ^ get_instance_id())
	_rebuild_grid()
	if not is_multiplayer_authority(): get_tree().create_timer(0.5,false).timeout.connect(_request_state)


func runtime_active() -> bool:
	if get_tree() == null or get_tree().paused or Game.now_stop_state or Engine.time_scale <= 0.000001: return false
	var world:Node = get_parent()
	return bool(world.call("is_combat_runtime_active")) if world != null and world.has_method("is_combat_runtime_active") else true


func cell_of(point:Vector2) -> Vector2i:
	return Vector2i(((point - grid_origin) / grid_size).floor())


func cell_center(cell:Vector2i) -> Vector2:
	return grid_origin + (Vector2(cell) + Vector2(0.5,0.5)) * grid_size


func cell_rect(cell:Vector2i) -> Rect2:
	return Rect2(grid_origin + Vector2(cell) * grid_size,grid_size)


## 正式灵魂沙 = 整格长满（火把充能、灵魂火落点、减速都只认它）。
func has_sand_at(point:Vector2) -> bool:
	return has_full_sand_at(point)


func is_cell_full(cell:Vector2i) -> bool:
	return cells.has(cell) and _clock - float(cells[cell]) >= GROW_SECONDS


func has_full_sand_at(point:Vector2) -> bool:
	return not _retiring and is_cell_full(cell_of(point))


## 站在长满的灵魂沙上（以身体中心为准）。附魔组件用它决定灵魂疾行加速。
static func full_sand_under(actor:Node) -> bool:
	if not (actor is Node2D): return false
	var field:Node2D = find(actor)
	return field != null and bool(field.call("has_full_sand_at",(actor as Node2D).global_position))


## 灵魂沙上的移速倍率：无灵魂疾行 0.8；灵魂疾行由附魔规则给出（1 级 1.0，之后每级 +0.2）。
static func speed_factor_for(actor:Node) -> float:
	var resolved:Dictionary = load(ENCHANTS_PATH).resolve_event(actor,"move",{"on_soul":true})
	return float(resolved.get("speed_multiplier",1.0))


func is_floor_at(point:Vector2) -> bool:
	return floor_cells.has(cell_of(point))


func touches_rect(rect:Rect2) -> bool:
	if _retiring or cells.is_empty(): return false
	var a:Vector2i = cell_of(rect.position)
	var b:Vector2i = cell_of(rect.end - Vector2.ONE * 0.001)
	for y:int in range(a.y,b.y + 1):
		for x:int in range(a.x,b.x + 1):
			if is_cell_full(Vector2i(x,y)): return true
	return false


func coverage() -> float:
	return float(cells.size()) / maxf(float(floor_cells.size()),1.0)


func frontier_size() -> int:
	return _frontier.size()


func _rebuild_grid() -> void:
	var world:Node = get_parent()
	var size:Vector2 = Vector2.ONE * 16.0
	var islands:Array = []
	if world != null and world.has_method("_current_map_node"):
		var map:Node = world.call("_current_map_node")
		if is_instance_valid(map):
			if world.has_method("map_visual_cell_size"): size = world.call("map_visual_cell_size",map)
			if world.has_method("map_islands"): islands = world.call("map_islands",map)
	size = size.max(Vector2.ONE)
	var regions:Array[Rect2] = []
	var visuals:Array[Rect2] = []
	var physical:Array[Rect2] = []
	for island:Dictionary in islands:
		for region:Variant in island.get("regions",[]):
			if region is Rect2: regions.append(region)
		var rect:Rect2 = island.get("rect",Rect2())
		physical.append(rect)
		visuals.append(world.call("_island_visual_rect",rect,size) if world.has_method("_island_visual_rect") else rect)
	var key:String = var_to_str([size,regions,visuals])
	if key == _grid_key: return
	_grid_key = key
	grid_size = size
	grid_origin = regions[0].position if not regions.is_empty() else Vector2.ZERO
	cells.clear()
	_growing.clear()
	_grow_from.clear()
	floor_cells.clear()
	_frontier.clear()
	_frontier_at.clear()
	_resistance.clear()
	_pending = PackedInt32Array()
	_budget = 0.0
	for region:Rect2 in regions:
		var a:Vector2i = cell_of(region.position + Vector2.ONE * 0.01)
		var b:Vector2i = cell_of(region.end - Vector2.ONE * 0.01)
		for y:int in range(a.y,b.y + 1):
			for x:int in range(a.x,b.x + 1):
				var cell := Vector2i(x,y)
				if floor_cells.has(cell): continue
				var area:Array[Rect2] = [cell_rect(cell).grow(-0.01)]
				if GEOMETRY.subtract(area,regions).is_empty(): floor_cells[cell] = true
	_reset_pixels()
	_build_ring(visuals,physical)
	if is_multiplayer_authority(): _seed_frontier()
	queue_redraw()
	if is_instance_valid(_ring_view): _ring_view.queue_redraw()


## 每个岛的显示外框（含方块主题的一格外墙）外侧再铺一圈；会压到别的岛的格子不画。
## 显示外框比地面大（有立体墙）时整圈向内收 RING_INSET_CELLS 格，收进去的部分在墙下。
func _build_ring(visuals:Array[Rect2],physical:Array[Rect2] = []) -> void:
	ring_rects.clear()
	for i:int in range(visuals.size()):
		var v:Rect2 = visuals[i]
		if not v.has_area(): continue
		var walled:bool = i < physical.size() and v.size.x > physical[i].size.x + 0.5
		var inset:Vector2 = grid_size * RING_INSET_CELLS if walled else Vector2.ZERO
		var cols:int = maxi(int(round(v.size.x / grid_size.x)),1)
		var rows:int = maxi(int(round(v.size.y / grid_size.y)),1)
		var candidates:Array[Rect2] = []
		for x:int in range(-1,cols + 1):
			var shift_x:float = inset.x if x < 0 else -inset.x if x >= cols else 0.0
			candidates.append(Rect2(v.position + Vector2(x * grid_size.x + shift_x,-grid_size.y + inset.y),grid_size))
			candidates.append(Rect2(v.position + Vector2(x * grid_size.x + shift_x,rows * grid_size.y - inset.y),grid_size))
		for y:int in range(rows):
			candidates.append(Rect2(v.position + Vector2(-grid_size.x + inset.x,y * grid_size.y),grid_size))
			candidates.append(Rect2(v.position + Vector2(cols * grid_size.x - inset.x,y * grid_size.y),grid_size))
		for rect:Rect2 in candidates:
			var blocked:bool = false
			for j:int in range(visuals.size()):
				if j != i and visuals[j].grow(-0.5).intersects(rect):
					blocked = true
					break
			if not blocked: ring_rects.append(rect)


## 蔓延起点：与“地图外”相邻的地面格。地图外 = 从包围盒外沿出发只经过非地面格能到达的格，
## 所以被地面围住的内部墙不会成为起点。每格一个固定随机阻力。
func _seed_frontier() -> void:
	if floor_cells.is_empty(): return
	var lo := Vector2i(1 << 30,1 << 30)
	var hi := Vector2i(-(1 << 30),-(1 << 30))
	for cell:Vector2i in floor_cells:
		lo = Vector2i(mini(lo.x,cell.x),mini(lo.y,cell.y))
		hi = Vector2i(maxi(hi.x,cell.x),maxi(hi.y,cell.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var outside:Dictionary = {}
	var queue:Array[Vector2i] = []
	for x:int in range(lo.x,hi.x + 1):
		queue.append(Vector2i(x,lo.y))
		queue.append(Vector2i(x,hi.y))
	for y:int in range(lo.y,hi.y + 1):
		queue.append(Vector2i(lo.x,y))
		queue.append(Vector2i(hi.x,y))
	var head:int = 0
	while head < queue.size():
		var cell:Vector2i = queue[head]
		head += 1
		if outside.has(cell) or floor_cells.has(cell) or cell.x < lo.x or cell.y < lo.y or cell.x > hi.x or cell.y > hi.y: continue
		outside[cell] = true
		for dir:Vector2i in DIRS: queue.append(cell + dir)
	for cell:Vector2i in floor_cells: _resistance[cell] = _rng.randf()
	for cell:Vector2i in floor_cells:
		for dir:Vector2i in DIRS:
			if outside.has(cell + dir):
				_push_frontier(cell)
				break


func _push_frontier(cell:Vector2i) -> void:
	_frontier_at[cell] = _frontier.size()
	_frontier.append(cell)


func _take_frontier(index:int) -> Vector2i:
	var cell:Vector2i = _frontier[index]
	var last:Vector2i = _frontier[_frontier.size() - 1]
	_frontier[index] = last
	_frontier_at[last] = index
	_frontier.pop_back()
	_frontier_at.erase(cell)
	return cell


func _spread_one() -> bool:
	if _frontier.is_empty(): return false
	var best:int = _rng.randi_range(0,_frontier.size() - 1)
	for i:int in range(1,maxi(tournament_size,1)):
		var pick:int = _rng.randi_range(0,_frontier.size() - 1)
		if float(_resistance.get(_frontier[pick],0.0)) < float(_resistance.get(_frontier[best],0.0)): best = pick
	var cell:Vector2i = _take_frontier(best)
	_add_cell(cell,_clock)
	_pending.append(cell.x)
	_pending.append(cell.y)
	for dir:Vector2i in DIRS:
		var next:Vector2i = cell + dir
		if floor_cells.has(next) and not cells.has(next) and not _frontier_at.has(next): _push_frontier(next)
	return true


## 新格记下出现时刻和来源方向（朝向已有灵魂沙，边缘格朝向地图外），之后按像素随机长满；
## 已经过了生长时间的格（迟到全量、测试）直接整格填满。
func _add_cell(cell:Vector2i,born:float) -> void:
	if cells.has(cell): return
	cells[cell] = born
	if _clock - born < GROW_SECONDS:
		_grow_from[cell] = _pick_grow_from(cell)
		_grow_start[cell] = int(_cell_count.get(cell,0))
		_growing.append(cell)
	else:
		_fill_cell(cell)


## 立即把一格变成正式灵魂沙（像素填满）。
func force_full(cell:Vector2i) -> void:
	if not floor_cells.has(cell): return
	cells.erase(cell)
	_growing.erase(cell)
	_add_cell(cell,_clock - GROW_SECONDS - 0.01)


## 清空所有灵魂沙（格子与像素）。
func clear_sand() -> void:
	cells.clear()
	_growing.clear()
	_grow_from.clear()
	_reset_pixels()


func cell_pixel_count(cell:Vector2i) -> int:
	return int(_cell_count.get(cell,0))


func pixels_per_cell() -> int:
	return _px * _px


func _reset_pixels() -> void:
	_px = maxi(TEXTURE.get_width(),1)
	_cell_count.clear()
	_px_frontier.clear()
	_grow_start.clear()
	_chunks.clear()
	_covered = PackedByteArray()
	_px_w = 0
	_px_h = 0
	if not floor_cells.is_empty():
		var lo := Vector2i(1 << 30,1 << 30)
		var hi := Vector2i(-(1 << 30),-(1 << 30))
		for cell:Vector2i in floor_cells:
			lo = Vector2i(mini(lo.x,cell.x),mini(lo.y,cell.y))
			hi = Vector2i(maxi(hi.x,cell.x),maxi(hi.y,cell.y))
		_px_origin = lo
		_px_w = (hi.x - lo.x + 1) * _px
		_px_h = (hi.y - lo.y + 1) * _px
		_covered.resize(_px_w * _px_h)
		_covered.fill(0)
	if is_instance_valid(_mask_view): _mask_view.queue_redraw()


func _cell_pixel(cell:Vector2i,x:int,y:int) -> int:
	return ((cell.y - _px_origin.y) * _px + y) * _px_w + (cell.x - _px_origin.x) * _px + x


func _cover(index:int) -> void:
	if _covered[index] != 0: return
	_covered[index] = 255
	var gx:int = index % _px_w
	var gy:int = index / _px_w
	var cell:Vector2i = _px_origin + Vector2i(gx / _px,gy / _px)
	_cell_count[cell] = int(_cell_count.get(cell,0)) + 1
	var span:int = _px * CHUNK_CELLS
	var chunk:Dictionary = _chunk(Vector2i(gx / span,gy / span))
	(chunk.image as Image).set_pixel(gx % span,gy % span,Color.WHITE)
	chunk.dirty = true
	for dir:Vector2i in DIRS:
		var nx:int = gx + dir.x
		var ny:int = gy + dir.y
		if nx < 0 or ny < 0 or nx >= _px_w or ny >= _px_h: continue
		var next:int = ny * _px_w + nx
		if _covered[next] != 0: continue
		var next_cell:Vector2i = _px_origin + Vector2i(nx / _px,ny / _px)
		if not floor_cells.has(next_cell) or is_cell_full(next_cell): continue
		if not _px_frontier.has(next_cell): _px_frontier[next_cell] = []
		(_px_frontier[next_cell] as Array).append(next)


func _chunk(key:Vector2i) -> Dictionary:
	if _chunks.has(key): return _chunks[key]
	var span:int = _px * CHUNK_CELLS
	var image:Image = Image.create(span,span,false,Image.FORMAT_L8)
	var chunk:Dictionary = {"image":image,"texture":ImageTexture.create_from_image(image),"dirty":true}
	_chunks[key] = chunk
	if is_instance_valid(_mask_view): _mask_view.queue_redraw()
	return chunk


## 随机取一个与已覆盖像素相邻的未覆盖像素（Eden 随机生长）。
func _pop_pixel(cell:Vector2i) -> int:
	var list:Array = _px_frontier.get(cell,[])
	while not list.is_empty():
		var pick:int = _px_rng.randi_range(0,list.size() - 1)
		var index:int = list[pick]
		list[pick] = list[list.size() - 1]
		list.pop_back()
		if _covered[index] == 0: return index
	return -1


## 前沿为空时补种：贴着已覆盖像素或非地面（地图外/墙）的像素；仍没有就取来源一侧的边。
func _seed_cell(cell:Vector2i) -> void:
	var list:Array = []
	for y:int in range(_px):
		for x:int in range(_px):
			var index:int = _cell_pixel(cell,x,y)
			if _covered[index] != 0: continue
			var gx:int = index % _px_w
			var gy:int = index / _px_w
			for dir:Vector2i in DIRS:
				var nx:int = gx + dir.x
				var ny:int = gy + dir.y
				if nx < 0 or ny < 0 or nx >= _px_w or ny >= _px_h or _covered[ny * _px_w + nx] != 0 or not floor_cells.has(_px_origin + Vector2i(nx / _px,ny / _px)):
					list.append(index)
					break
	if list.is_empty():
		var from:Vector2i = _grow_from.get(cell,Vector2i.LEFT)
		for k:int in range(_px):
			var x:int = 0 if from.x < 0 else _px - 1 if from.x > 0 else k
			var y:int = 0 if from.y < 0 else _px - 1 if from.y > 0 else k
			list.append(_cell_pixel(cell,x,y))
	_px_frontier[cell] = list


## 整格补满：直接写覆盖与贴图块，只给四周未长满的格补上贴边的前沿像素。
func _fill_cell(cell:Vector2i) -> void:
	if _covered.is_empty() or not floor_cells.has(cell): return
	_px_frontier.erase(cell)
	var added:int = 0
	for y:int in range(_px):
		var row:int = _cell_pixel(cell,0,y)
		for x:int in range(_px):
			if _covered[row + x] == 0:
				_covered[row + x] = 255
				added += 1
	if added == 0: return
	_cell_count[cell] = int(_cell_count.get(cell,0)) + added
	var gx:int = (cell.x - _px_origin.x) * _px
	var gy:int = (cell.y - _px_origin.y) * _px
	var span:int = _px * CHUNK_CELLS
	var chunk:Dictionary = _chunk(Vector2i(gx / span,gy / span))
	(chunk.image as Image).fill_rect(Rect2i(gx % span,gy % span,_px,_px),Color.WHITE)
	chunk.dirty = true
	for dir:Vector2i in DIRS:
		var next:Vector2i = cell + dir
		if not floor_cells.has(next) or is_cell_full(next): continue
		if not _px_frontier.has(next): _px_frontier[next] = []
		var list:Array = _px_frontier[next]
		for k:int in range(_px):
			var x:int = 0 if dir.x > 0 else _px - 1 if dir.x < 0 else k
			var y:int = 0 if dir.y > 0 else _px - 1 if dir.y < 0 else k
			var index:int = _cell_pixel(next,x,y)
			if _covered[index] == 0: list.append(index)


func _spill_from(cell:Vector2i) -> void:
	var next:Vector2i = cell + DIRS[_px_rng.randi_range(0,DIRS.size() - 1)]
	if not floor_cells.has(next) or cells.has(next): return
	if float(_cell_count.get(next,0)) >= SPILL_CAP * float(_px * _px): return
	var index:int = _pop_pixel(next)
	if index >= 0: _cover(index)


func _pick_grow_from(cell:Vector2i) -> Vector2i:
	var sand:Array[Vector2i] = []
	var open:Array[Vector2i] = []
	for dir:Vector2i in DIRS:
		if cells.has(cell + dir): sand.append(dir)
		elif not floor_cells.has(cell + dir): open.append(dir)
	var pool:Array[Vector2i] = sand if not sand.is_empty() else open if not open.is_empty() else DIRS
	return pool[absi(_cell_hash(cell,7)) % pool.size()]


static func _cell_hash(cell:Vector2i,lane:int) -> int:
	return ((cell.x * 73856093) ^ (cell.y * 19349663) ^ (lane * 83492791)) & 0x7fffffff


## 每个生长中的格按时间线性补足像素数：从已覆盖的边缘随机往外长，并随机溢到相邻格；
## 到 GROW_SECONDS 时把剩下的像素补满，从这一刻起才是正式灵魂沙。
func _update_growth() -> void:
	if _growing.is_empty() or _covered.is_empty(): return
	var total:int = _px * _px
	var index:int = _growing.size() - 1
	while index >= 0:
		var cell:Vector2i = _growing[index]
		index -= 1
		if not cells.has(cell) or is_cell_full(cell):
			if cells.has(cell): _fill_cell(cell)
			_growing.erase(cell)
			_grow_from.erase(cell)
			_grow_start.erase(cell)
			continue
		var progress:float = clampf((_clock - float(cells[cell])) / GROW_SECONDS,0.0,1.0)
		var start:int = int(_grow_start.get(cell,0))
		var need:int = start + int(ceil(float(total - start) * progress)) - int(_cell_count.get(cell,0))
		var reseeded:bool = false
		while need > 0:
			var pixel:int = _pop_pixel(cell)
			if pixel < 0:
				if reseeded: break
				reseeded = true
				_seed_cell(cell)
				continue
			_cover(pixel)
			need -= 1
			if _px_rng.randf() < SPILL_CHANCE: _spill_from(cell)


func _flush_mask() -> void:
	for chunk:Dictionary in _chunks.values():
		if not bool(chunk.dirty): continue
		chunk.dirty = false
		(chunk.texture as ImageTexture).update(chunk.image)


## 长满的灵魂沙上，本端拥有的所有角色按 speed_factor_for 减速（公共运动减速租约，离开即撤销）。
func _apply_slow() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not (node is Node2D) or not node.has_method("set_motion_speed_factor") or not node.is_multiplayer_authority(): continue
		if node.is_queued_for_deletion() or (node.get("health") != null and float(node.get("health")) <= 0.0): continue
		var factor:float = 1.0
		if has_full_sand_at((node as Node2D).global_position): factor = speed_factor_for(node)
		node.call("set_motion_speed_factor",SLOW_KEY,self,factor,0.25)


func _physics_process(delta:float) -> void:
	_grid_check_left -= delta
	if _grid_check_left <= 0.0:
		_grid_check_left = 0.5
		_rebuild_grid()
	if not _retiring and runtime_active():
		_clock += delta
		_update_growth()
	_flush_mask()
	_slow_left -= delta
	if _slow_left <= 0.0:
		_slow_left = SLOW_CHECK_INTERVAL
		_apply_slow()
	if _retiring:
		_fade = maxf(_fade - delta / FADE_SECONDS,0.0)
		modulate.a = _fade
		if _fade <= 0.0: queue_free()
		return
	if not is_multiplayer_authority(): return
	_owner_check_left -= delta
	if _owner_check_left <= 0.0:
		_owner_check_left = 0.5
		if not _any_live_torch():
			retire()
			return
	if runtime_active() and not _frontier.is_empty():
		_budget += float(floor_cells.size()) / maxf(full_cover_seconds,1.0) * delta
		while _budget >= 1.0 and _spread_one():
			_budget -= 1.0
	_send_left -= delta
	if _send_left <= 0.0:
		_send_left = SEND_INTERVAL
		_flush()


func _any_live_torch() -> bool:
	for node:Node in get_tree().get_nodes_in_group("MCTorch"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.get("health") != null and float(node.get("health")) > 0.0: return true
	return false


func _flush() -> void:
	if _pending.is_empty(): return
	if multiplayer.has_multiplayer_peer(): _receive_cells.rpc(_pending)
	_pending = PackedInt32Array()


@rpc("authority","call_remote","reliable")
func _receive_cells(packed:PackedInt32Array) -> void:
	for i:int in range(0,packed.size() - 1,2): _add_cell(Vector2i(packed[i],packed[i + 1]),_clock)


func _request_state() -> void:
	if is_inside_tree() and multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_request_full.rpc_id(get_multiplayer_authority())


@rpc("any_peer","call_remote","reliable")
func _request_full() -> void:
	if not is_multiplayer_authority(): return
	var packed := PackedInt32Array()
	for cell:Vector2i in cells:
		packed.append(cell.x)
		packed.append(cell.y)
	_receive_full.rpc_id(multiplayer.get_remote_sender_id(),packed,_retiring)


@rpc("authority","call_remote","reliable")
func _receive_full(packed:PackedInt32Array,retiring:bool) -> void:
	clear_sand()
	# 迟到的全量直接视为长满，不重播生长。
	for i:int in range(0,packed.size() - 1,2): _add_cell(Vector2i(packed[i],packed[i + 1]),_clock - GROW_SECONDS)
	if retiring: _retiring = true


func retire() -> void:
	if _retiring: return
	_retiring = true
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _receive_retire.rpc()


@rpc("authority","call_remote","reliable")
func _receive_retire() -> void:
	_retiring = true


func _draw_mask() -> void:
	var span:Vector2 = grid_size * float(CHUNK_CELLS)
	for key:Vector2i in _chunks:
		var origin:Vector2 = grid_origin + Vector2(_px_origin + key * CHUNK_CELLS) * grid_size
		_mask_view.draw_texture_rect(_chunks[key].texture,Rect2(origin,span),false)


func _draw_ring() -> void:
	for rect:Rect2 in ring_rects: _ring_view.draw_texture_rect(TEXTURE,rect,false)
