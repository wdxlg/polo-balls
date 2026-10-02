extends Node2D
## 苔藓地面上长出的原版单格 3D 植物；苔藓地面、伤害与层数仍在原有地面层。
## 层数加深不叠苔藓，而是长出植物：2 层 = 杜鹃花丛，3 层 = 盛开的杜鹃花丛；1 层只有苔藓地面。
## 植物是 mc_block_3d.gd 的原版模型，与地图墙同一太阳受光；花丛画在苔藓地皮和角色之上（血条之下），
## 地影落在苔藓地皮上、角色之下。
const BLOCK = preload("res://scripts/effects/我的世界/mc_block_3d.gd")
const AZALEA:StringName = &"azalea"
const FLOWERING:StringName = &"flowering_azalea"
const MODELS_USED:Array[StringName] = [AZALEA,FLOWERING]
var moss:Node2D
var _blocks:Dictionary = {} # cell -> mc_block_3d 节点

func _ready() -> void:
	moss = get_parent() as Node2D
	top_level = true
	global_position = Vector2.ZERO
	global_scale = Vector2.ONE

func _exit_tree() -> void:
	_blocks.clear()

func _process(_delta:float) -> void:
	if not is_instance_valid(moss) or moss.is_queued_for_deletion():
		queue_free()
		return
	# A dead owner deletes its terrain: do not leave plants behind.
	visible = moss.health > 0
	_sync_blocks(_plant_cells() if visible else {})

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
