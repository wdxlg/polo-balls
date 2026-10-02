extends Node2D
## 苔藓地面上长出的原版单格 3D 植物；苔藓地面、伤害与层数仍在原有地面层。
## 层数加深不叠苔藓，而是长出植物：2 层 = 杜鹃花丛，3 层 = 盛开的杜鹃花丛；1 层只有苔藓地面。
## 植物是 mc_block_3d.gd 的原版模型，与地图墙同一太阳受光；花丛画在苔藓地皮和角色之上（血条之下），
## 地影落在苔藓地皮上、角色之下。有人/投射物靠近（5×5 去四角）时花丛平滑淡到 40% 不透明度。
const BLOCK = preload("res://scripts/effects/我的世界/mc_block_3d.gd")
const AZALEA:StringName = &"azalea"
const FLOWERING:StringName = &"flowering_azalea"
const MODELS_USED:Array[StringName] = [AZALEA,FLOWERING]
@export_range(0.10,0.80,0.01) var opacity_transition_time:float = 0.28
var moss:Node2D
var _fade_states:Dictionary = {} # cell -> {see, start, target, elapsed}
var _blocks:Dictionary = {} # cell -> mc_block_3d 节点

func _ready() -> void:
	moss = get_parent() as Node2D
	top_level = true
	global_position = Vector2.ZERO
	global_scale = Vector2.ONE

func _exit_tree() -> void:
	_blocks.clear()
	_fade_states.clear()

func _process(delta:float) -> void:
	if not is_instance_valid(moss) or moss.is_queued_for_deletion():
		queue_free()
		return
	# A dead owner deletes its terrain: do not leave plants behind.
	visible = moss.health > 0
	var plant_cells:Dictionary = _plant_cells() if visible else {}
	_sync_blocks(plant_cells)
	_update_see_through(plant_cells,delta)


## 有人/投射物在附近的花丛变半透明；进出都从当前显示值缓动（ease-out cubic）。
func _update_see_through(plant_cells:Dictionary,delta:float) -> void:
	for cell:Vector2i in _fade_states.keys():
		if not plant_cells.has(cell): _fade_states.erase(cell)
	if plant_cells.is_empty(): return
	var near:Dictionary = _faded_cells(plant_cells)
	var duration:float = maxf(opacity_transition_time,0.001)
	var step:float = maxf(delta,0.0)
	var game:Node = get_node_or_null("/root/Game")
	if get_tree().paused or Engine.time_scale <= 0.000001 or (game != null and bool(game.get("now_stop_state"))):
		step = 0.0
	for cell:Vector2i in plant_cells:
		var target:float = 1.0 if near.has(cell) else 0.0
		if not _fade_states.has(cell):
			_fade_states[cell] = {"see":0.0,"start":0.0,"target":0.0,"elapsed":duration}
		var state:Dictionary = _fade_states[cell]
		if not is_equal_approx(float(state.target),target):
			state.start = float(state.see)
			state.target = target
			state.elapsed = 0.0
		if float(state.elapsed) < duration:
			state.elapsed = minf(float(state.elapsed)+step,duration)
			var remaining:float = 1.0-float(state.elapsed)/duration
			state.see = lerpf(float(state.start),target,1.0-remaining*remaining*remaining)
		else:
			state.see = target
		var block:Node2D = _blocks.get(cell)
		if is_instance_valid(block): block.set_see_through(float(state.see))


static func shades_cell(bush_cell:Vector2i,object_cell:Vector2i) -> bool:
	var offset:Vector2i = bush_cell-object_cell
	return absi(offset.x) <= 2 and absi(offset.y) <= 2 and not (absi(offset.x) == 2 and absi(offset.y) == 2)


func _faded_cells(canopy_cells:Dictionary) -> Dictionary:
	var faded:Dictionary = {}
	var seen:Dictionary = {}
	# Ball includes fighters and ball-based projectiles. The other two groups
	# cover Area2D projectiles and physical world objects without pulling audio,
	# ephemeral particles or UI into the occlusion calculation.
	for group_name:String in ["Ball","AllayExtendedProjectile","BattleTransient"]:
		for node:Node in get_tree().get_nodes_in_group(group_name):
			if not node is Node2D or not node.is_inside_tree() or node.is_queued_for_deletion(): continue
			var object:Node2D = node as Node2D
			if not object.is_visible_in_tree() or seen.has(object.get_instance_id()): continue
			if group_name == "BattleTransient" and not (object is CollisionObject2D or object is Sprite2D or object.has_node("CollisionShape2D")): continue
			seen[object.get_instance_id()] = true
			var object_cell:Vector2i = moss.cell_at(object.global_position)
			for bush_cell:Vector2i in canopy_cells:
				if shades_cell(bush_cell,object_cell): faded[bush_cell] = true
			if faded.size() == canopy_cells.size(): return faded
	return faded


func see_through_for_cell(cell:Vector2i) -> float:
	return float(_fade_states[cell].see) if _fade_states.has(cell) else 0.0

static func plant_for_layers(layers:int) -> StringName:
	if layers >= 3: return FLOWERING
	if layers == 2: return AZALEA
	return &""

## 所有长植物的格子：cell -> 原版模型名。
func _plant_cells() -> Dictionary:
	var cells:Dictionary = {}
	for patch:Dictionary in moss.patches:
		var plant:StringName = plant_for_layers(int(patch.get("layers",0)))
		if plant != &"" and patch.has("point"): cells[moss.cell_at(patch.point)] = plant
	return cells

func plant_block(cell:Vector2i) -> Node2D:
	var block:Node2D = _blocks.get(cell)
	return block if is_instance_valid(block) else null

func _sync_blocks(plant_cells:Dictionary) -> void:
	for cell:Vector2i in _blocks.keys():
		var block:Node2D = _blocks[cell]
		if plant_cells.has(cell) and is_instance_valid(block): continue
		if is_instance_valid(block): block.queue_free()
		_blocks.erase(cell)
	for cell:Vector2i in plant_cells:
		var plant:StringName = plant_cells[cell]
		var block:Node2D = _blocks.get(cell)
		if block == null:
			block = BLOCK.create(plant,moss.CELL)
			block.name = "MossPlant_%d_%d" % [cell.x,cell.y]
			add_child(block)
			_blocks[cell] = block
		elif block.model != plant:
			block.set_model(plant)
		var point:Vector2 = moss.point_for_cell(cell)
		if not block.global_position.is_equal_approx(point): block.global_position = point
