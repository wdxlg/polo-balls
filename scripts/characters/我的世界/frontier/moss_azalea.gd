extends Node2D
## World-space bush canopy only; moss tiles, damage and stacking remain on their
## existing ground layer. The texture uses vanilla azalea block pixels.
const AZALEA:Texture2D = preload("res://Images/characters/我的世界/frontier/azalea_bush.png")
const FLOWERING:Texture2D = preload("res://Images/characters/我的世界/frontier/flowering_azalea_bush.png")
# Above normal fighters and the flying elytra graphics (z=101), below HUD z=104.
const CANOPY_Z:int = 103
@export_range(0.05,0.95,0.05) var nearby_alpha:float = 0.35
@export_range(0.10,0.80,0.01) var opacity_transition_time:float = 0.28
var moss:Node2D
var _alpha_states:Dictionary = {}

func _ready() -> void:
	moss = get_parent() as Node2D
	top_level = true
	global_position = Vector2.ZERO
	global_scale = Vector2.ONE
	z_as_relative = false
	z_index = CANOPY_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta:float) -> void:
	if not is_instance_valid(moss) or moss.is_queued_for_deletion():
		queue_free()
		return
	# A dead owner deletes its terrain: do not leave an overhead bush silhouette.
	visible = moss.health > 0
	if not visible:
		_alpha_states.clear()
		return
	var canopy_cells:Dictionary = _canopy_cells()
	var faded:Dictionary = _faded_cells(canopy_cells) if not canopy_cells.is_empty() else {}
	for cell:Vector2i in _alpha_states.keys():
		if not canopy_cells.has(cell): _alpha_states.erase(cell)
	var duration:float = maxf(opacity_transition_time,0.001)
	var transition_delta:float = maxf(delta,0.0)
	var game:Node = get_node_or_null("/root/Game")
	if get_tree().paused or Engine.time_scale <= 0.000001 or (game != null and bool(game.get("now_stop_state"))):
		transition_delta = 0.0
	for cell:Vector2i in canopy_cells:
		var target:float = nearby_alpha if faded.has(cell) else 1.0
		if not _alpha_states.has(cell):
			_alpha_states[cell] = {"alpha":1.0,"start":1.0,"target":1.0,"elapsed":duration}
		var state:Dictionary = _alpha_states[cell]
		# Restart from the displayed alpha when a fighter/projectile enters or leaves.
		if not is_equal_approx(float(state.target),target):
			state.start = float(state.alpha)
			state.target = target
			state.elapsed = 0.0
		if float(state.elapsed) < duration:
			state.elapsed = minf(float(state.elapsed)+transition_delta,duration)
			var remaining:float = 1.0-float(state.elapsed)/duration
			state.alpha = lerpf(float(state.start),target,1.0-remaining*remaining*remaining)
		else:
			state.alpha = target
	queue_redraw()

static func shades_cell(bush_cell:Vector2i,object_cell:Vector2i) -> bool:
	var offset:Vector2i = bush_cell-object_cell
	return absi(offset.x) <= 2 and absi(offset.y) <= 2 and not (absi(offset.x) == 2 and absi(offset.y) == 2)

func _canopy_cells() -> Dictionary:
	var cells:Dictionary = {}
	for patch:Dictionary in moss.patches:
		if int(patch.layers) >= 2:
			cells[moss.cell_at(patch.point)] = true
	return cells

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

func _alpha_for_cell(cell:Vector2i) -> float:
	return float(_alpha_states[cell].alpha) if _alpha_states.has(cell) else 1.0

func _draw() -> void:
	if not is_instance_valid(moss) or moss.health <= 0: return
	var canopy_cells:Dictionary = _canopy_cells()
	if canopy_cells.is_empty(): return
	var width:float = moss.CELL
	var size:Vector2 = Vector2(width,width*22.0/16.0)
	for patch:Dictionary in moss.patches:
		var layers:int = int(patch.layers)
		if layers < 2: continue
		var cell:Vector2i = moss.cell_at(patch.point)
		var texture:Texture2D = FLOWERING if layers >= 3 else AZALEA
		var p:Vector2 = to_local(patch.point)
		# Both kinds grow from the same single ground tile, not from a moss stack.
		var origin:Vector2 = p+Vector2(-width*0.5,width*0.25-size.y)
		draw_texture_rect(texture,Rect2(origin,size),false,Color(1,1,1,_alpha_for_cell(cell)))
