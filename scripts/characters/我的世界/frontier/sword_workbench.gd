extends StaticBody2D
## One fixed, solid obstacle bench per sword family. No global/shared repair pairing.
## Native single-block 3D crafting table (mc_block_3d.gd); its collision is exactly one map cell.
const BLOCK = preload("res://scripts/effects/我的世界/mc_block_3d.gd")
const BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
var bench_size:float = BLOCK.DEFAULT_CELL
var block:Node2D
var obstacle_shape:CollisionShape2D
var _solid:bool = false
var image:Sprite2D
var _pair_bound:bool = false
var _shattered:bool = false
var family:String = ""
var pieces:Array[WeakRef] = []
var repair_duration:float = 2.4
var heal_ratio:float = 0.05
var progress:float = 0.0
var materialize_duration:float = 3.0
var age:float = 0.0
var _heal_credit:Dictionary = {}
var _heal_elapsed:Dictionary = {}
var _consumed:bool = false
var _empty_time:float = 0.0
func _ready() -> void:
	collision_layer=0
	collision_mask=2
	bench_size=BLOCK.map_cell(self)
	obstacle_shape=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=Vector2.ONE*bench_size
	obstacle_shape.shape=shape
	obstacle_shape.disabled=true
	add_child(obstacle_shape)
	add_to_group("MCSwordWorkbench")
	add_to_group("BattleTransient")
	process_physics_priority = 250
	z_as_relative = false
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	block = BLOCK.create(&"crafting_table",bench_size)
	add_child(block)
	# Transparent native particle sample: shared block debris still cuts the crafting table.
	image = block.debris_sample
	update_opacity()
func is_materialized() -> bool:
	return age >= materialize_duration
func update_opacity() -> void:
	var solid:bool=is_materialized() and not _consumed
	if solid!=_solid:
		_solid=solid
		set_deferred("collision_layer",1 if solid else 0)
		obstacle_shape.set_deferred("disabled",not solid)
	modulate.a = lerpf(0.2,1.0,clampf(age/maxf(materialize_duration,0.001),0.0,1.0))
	if is_instance_valid(block): block.set_alpha(modulate.a)
func bind_piece(piece:Node2D) -> void:
	for ref:WeakRef in pieces:
		if ref.get_ref() == piece: return
	pieces.append(weakref(piece))
	_pair_bound = pieces.size() >= 2
func living_pieces() -> Array[ball]:
	var result:Array[ball] = []
	for ref:WeakRef in pieces:
		var piece:Node = ref.get_ref()
		if is_instance_valid(piece) and not piece.is_queued_for_deletion() and piece.health > 0 and piece.is_broken() and piece.sword_family == family:
			result.append(piece)
	return result
func touching(piece:ball) -> bool:
	if _consumed or piece.health<=0 or piece.sword_family!=family or piece.dock_delay>0.0: return false
	var half:Vector2=Vector2.ONE*bench_size*0.5
	var closest:Vector2=global_position+ (piece.global_position-global_position).clamp(-half,half)
	if piece.global_position.distance_to(closest)>U.radius(piece)+2.0: return false
	# The bench itself must not occlude its own repair contact; other walls still do.
	var query:=PhysicsRayQueryParameters2D.create(piece.global_position,global_position,1,[piece.get_rid(),get_rid()])
	query.hit_from_inside=true
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()
func _physics_process(delta:float) -> void:
	advance(delta)
func advance(delta:float) -> void:
	if _consumed: return
	var live:Array[ball] = living_pieces()
	if _pair_bound and live.size() < 2 and is_multiplayer_authority():
		break_bench()
		return
	if live.is_empty():
		_empty_time += delta
		if _empty_time > 1.0: queue_free()
		return
	_empty_time = 0.0
	if not is_multiplayer_authority():
		if live[0].is_combat_runtime_active(): age = minf(materialize_duration,age+delta)
		update_opacity()
		progress = maxf(0,repair_duration-live[0].repair_left) if live[0].repairing else 0.0
		queue_redraw()
		return
	if not live[0].is_combat_runtime_active(): return
	var old_age:float = age
	age = minf(materialize_duration,age+delta)
	update_opacity()
	var repair_delta:float = maxf(0.0,delta-maxf(0.0,materialize_duration-old_age))
	var together:bool = is_materialized() and live.size() == 2 and live[0].part_kind != live[1].part_kind
	for piece:ball in live:
		var contact:bool = touching(piece)
		together = together and contact
		var id:int = piece.get_instance_id()
		if contact:
			_heal_credit[id] = float(_heal_credit.get(id,0.0))+piece.Max_health*heal_ratio*delta
			_heal_elapsed[id] = float(_heal_elapsed.get(id,0.0))+delta
			var whole:int = int(floor(float(_heal_credit[id]))) if float(_heal_elapsed[id]) >= 0.5 else 0
			if whole > 0:
				piece.heal(whole)
				_heal_elapsed[id] = fmod(float(_heal_elapsed[id]),0.5)
				_heal_credit[id] = float(_heal_credit[id])-whole
		else:
			_heal_credit.erase(id)
			_heal_elapsed.erase(id)
	progress = progress+repair_delta if together else 0.0
	for piece:ball in live:
		piece.repairing = together
		piece.repair_left = maxf(0,repair_duration-progress) if together else 0.0
	if together and progress >= repair_duration: complete_repair()
	queue_redraw()
func complete_repair() -> void:
	if _consumed or not is_materialized() or not is_multiplayer_authority() or progress < repair_duration: return
	var live:Array[ball] = living_pieces()
	if live.size() != 2 or not touching(live[0]) or not touching(live[1]): return
	var hilt:ball = live[0] if live[0].part_kind == 1 else live[1]
	var blade:ball = live[1] if hilt == live[0] else live[0]
	if hilt.part_kind != 1 or blade.part_kind != 2: return
	_consumed = true
	hilt.reform_with(blade)
func _draw() -> void:
	if progress <= 0.0: return
	var ratio:float = clampf(progress/repair_duration,0,1)
	BAR.paint(self,Rect2(-15,bench_size*0.5+8.0,30,30*16.0/110.0),ratio,ratio)

func is_character_visual_flipped_h() -> bool: return false
func break_bench() -> void:
	if _consumed or not is_multiplayer_authority(): return
	_consumed = true
	progress = 0.0
	for ref:WeakRef in pieces:
		var piece:Node = ref.get_ref()
		if is_instance_valid(piece): piece.lose_workbench()
	shatter_local()
func shatter_local() -> void:
	if _shattered or not is_inside_tree(): return
	_shattered = true
	_consumed = true
	progress = 0.0
	var debris:Node2D = preload("res://scripts/effects/我的世界/block_fragments.gd").spawn_obstacle(self)
	debris.modulate.a = modulate.a
	debris.add_to_group("MCSwordBenchDebris")
	hide()
	queue_free()

func on_obstacle_destroyed() -> void:
	# The common obstacle system already spawned debris. Notify the family without duplicating it.
	_shattered=true
	break_bench()
	set_deferred("collision_layer",0)
	obstacle_shape.set_deferred("disabled",true)
