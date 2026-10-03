extends StaticBody2D
const BLOCK = preload("res://scripts/effects/我的世界/mc_block_3d.gd")
const FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const PAIRS = preload("res://classes/body_collision_exclusions.gd")
const AUDIO = preload("res://scripts/characters/我的世界/bucket/bucket_audio.gd")
const HIT_FEEDBACK = preload("res://scripts/effects/我的世界/mc_hit_feedback.gd")
const DIR:String = "res://Images/characters/我的世界/bucket/"
const CRACKS:Array[Texture2D] = [
	preload(DIR + "destroy_stage_0.png"),preload(DIR + "destroy_stage_1.png"),preload(DIR + "destroy_stage_2.png"),
	preload(DIR + "destroy_stage_3.png"),preload(DIR + "destroy_stage_4.png"),preload(DIR + "destroy_stage_5.png"),
	preload(DIR + "destroy_stage_6.png"),preload(DIR + "destroy_stage_7.png"),preload(DIR + "destroy_stage_8.png"),
	preload(DIR + "destroy_stage_9.png"),
]
const STONE:int = 0
const OBSIDIAN:int = 1
const MODELS:Array[StringName] = [&"stone",&"obsidian"]
const CRACK_SECONDS:float = 1.2
const SUFFOCATION_TICK:float = 0.5
const SUFFOCATION_RATIO:float = 0.02
const TRAP_KEY:StringName = &"mc_fluid_block_trap"

var kind:int = STONE
var cell:Vector2i = Vector2i.ZERO
var duration:float = 5.0
var age:float = 0.0
var size:float = 16.0
var field:Node
var block:Node2D
var shape_node:CollisionShape2D
var _trapped:Array[Dictionary] = []
var _broken:bool = false


func setup(owner_field:Node,at:Vector2i,block_kind:int,seconds:float,rect:Rect2,start_age:float = 0.0) -> void:
	field = owner_field
	cell = at
	kind = clampi(block_kind,STONE,OBSIDIAN)
	duration = maxf(seconds,0.1)
	age = clampf(start_age,0.0,duration)
	size = minf(rect.size.x,rect.size.y)
	position = rect.get_center()


func _ready() -> void:
	name = "MCFluidBlock_%d_%d" % [cell.x,cell.y]
	collision_layer = 1
	collision_mask = 0
	add_to_group("BattleTransient")
	add_to_group("MCFluidBlock")
	set_meta(&"mc_fluid_block",true)
	process_physics_priority = 250
	z_as_relative = false
	z_index = 2
	shape_node = CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2.ONE * size
	shape_node.shape = box
	add_child(shape_node)
	block = BLOCK.create(MODELS[kind],size)
	add_child(block)
	_update_cracks()
	if is_multiplayer_authority(): _trap_units()


func block_rect() -> Rect2:
	return Rect2(global_position - Vector2.ONE * size * 0.5,Vector2.ONE * size)


func trapped_units() -> Array:
	var result:Array = []
	for entry:Dictionary in _trapped:
		var unit:Variant = (entry.unit as WeakRef).get_ref()
		if is_instance_valid(unit): result.append(unit)
	return result


func _trap_units() -> void:
	var rect:Rect2 = block_rect()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not (node is ball) or node.is_queued_for_deletion() or float(node.health) <= 0.0: continue
		var unit:ball = node as ball
		if not rect.has_point(unit.global_position): continue
		PAIRS.acquire(self,unit,self)
		_trapped.append({"unit":weakref(unit),"pos":unit.global_position,"wait":SUFFOCATION_TICK})


func _runtime_active() -> bool:
	if is_instance_valid(field) and field.has_method("runtime_active"): return bool(field.call("runtime_active"))
	return get_tree() != null and not get_tree().paused


func _physics_process(delta:float) -> void:
	if _broken or not _runtime_active(): return
	age += delta
	_update_cracks()
	if is_multiplayer_authority(): _hold_trapped(delta)
	if age >= duration: shatter()


func _hold_trapped(delta:float) -> void:
	for entry:Dictionary in _trapped:
		var unit:Variant = (entry.unit as WeakRef).get_ref()
		if not is_instance_valid(unit) or unit.is_queued_for_deletion() or float(unit.health) <= 0.0: continue
		unit.global_position = entry.pos
		unit.velocity = Vector2.ZERO
		unit.set_motion_speed_factor(TRAP_KEY,self,0.0,0.2)
		entry.wait = float(entry.wait) - delta
		if float(entry.wait) > 0.0: continue
		entry.wait = float(entry.wait) + SUFFOCATION_TICK
		var before:float = float(unit.health)
		unit.receive_spatial_damage(float(unit.Max_health) * SUFFOCATION_RATIO,{"element":"suffocation","point":entry.pos,"source":self},true,true)
		HIT_FEEDBACK.finish(self,unit,before,entry.pos)


func _update_cracks() -> void:
	if not is_instance_valid(block): return
	var left:float = duration - age
	if left > CRACK_SECONDS:
		block.set_cracks(null)
		return
	var stage:int = clampi(int(floor((1.0 - left / CRACK_SECONDS) * float(CRACKS.size()))),0,CRACKS.size() - 1)
	block.set_cracks(CRACKS[stage])


func shatter() -> void:
	if _broken: return
	_broken = true
	_release_all()
	if is_inside_tree():
		FRAGMENTS.spawn_obstacle(self)
		AUDIO.play(self,AUDIO.KIND_STONE,randi() % AUDIO.variant_count(AUDIO.KIND_STONE),global_position,0.8 if kind == OBSIDIAN else 1.0)
	if is_instance_valid(field) and field.has_method("block_removed"): field.call("block_removed",cell,self)
	hide()
	collision_layer = 0
	if is_instance_valid(shape_node): shape_node.set_deferred("disabled",true)
	queue_free()


func _release_all() -> void:
	for entry:Dictionary in _trapped:
		var unit:Variant = (entry.unit as WeakRef).get_ref()
		if not is_instance_valid(unit): continue
		PAIRS.release(self,unit,self)
		unit.set_motion_speed_factor(TRAP_KEY,self,1.0,0.0)
	_trapped.clear()


func _exit_tree() -> void:
	_release_all()
