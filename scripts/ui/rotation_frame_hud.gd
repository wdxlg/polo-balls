extends Node2D
## World-space queue HUD: one block per slot; clipped at the map's right edge.
const ROW_SCRIPT = preload("res://scripts/ui/rotation_frame_row.gd")
const PORTRAITS = preload("res://scripts/ui/rotation_portraits.gd")
var world:Node
var rows:Dictionary = {}
var portraits:RefCounted = PORTRAITS.new()
var _network_signature:String = ""
var _network_elapsed:float = 0.0

func _ready() -> void:
	name = "RotationItemFrames"
	z_index = 102
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	for side:String in ["left","right"]:
		var row:Control = ROW_SCRIPT.new()
		row.name = "BlueQueue" if side == "left" else "RedQueue"
		row.world = world
		row.side = side
		row.portraits = portraits
		rows[side] = row
		add_child(row)

func _process(delta:float) -> void:
	sync()
	_network_elapsed += delta
	if not visible or _network_elapsed < 0.10: return
	_network_elapsed = 0.0
	if world.is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		var signature:String = str([world._rotation_rosters,world._rotation_results,world._rotation_active_setup,multiplayer.get_peers()])
		if signature != _network_signature:
			_network_signature = signature
			world._receive_rotation_frame_state.rpc(world._rotation_rosters,world._rotation_results,world._rotation_active_setup)

func sync() -> void:
	visible = is_instance_valid(world) and Game.is_rotation_training_mode()
	if not visible: return
	visible = not world._dead_save_ui_override_active and not world._armor_stand_test_hud_active
	if not visible or not world.map_group.has(world.now_choose_map): return
	var map_node:Node = world.map_group[world.now_choose_map]
	var rect:Rect2 = world.return_map_visual_rect(map_node)
	var block:Vector2 = world.map_visual_cell_size(map_node)
	var cell:float = maxf(minf(block.x,block.y),1.0)
	var gap:float = cell * 0.12
	var bar:float = cell * 0.10
	for side:String in ["left","right"]:
		var row:Control = rows[side]
		row.position = Vector2(rect.position.x,rect.position.y - gap - bar - cell if side == "left" else rect.end.y + gap)
		row.size = Vector2(rect.size.x,cell + bar)
		row.configure(world._rotation_rosters[side],world._rotation_results,int(world._rotation_active_setup[side]),cell,bar)

func reset_scroll() -> void:
	for row:Control in rows.values(): row.reset_scroll()
