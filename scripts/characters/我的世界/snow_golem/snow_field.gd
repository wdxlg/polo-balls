extends Node2D
## A single battle-scoped sparse grid: no Area2D or timer per snow tile.
const CELL:float = 24.0
# Combat seconds: full snow first melts to harmless mini snow, then disappears.
@export_range(0.1,120.0,0.1) var full_snow_lifetime:float = 8.0
@export_range(0.1,120.0,0.1) var half_snow_lifetime:float = 4.0
const SNOW:Texture2D = preload("res://Images/characters/我的世界/snow_golem/snow.png")
const COLD = preload("res://scripts/characters/我的世界/snow_golem/cold.gd")
const RULES = preload("res://scripts/characters/我的世界/snow_golem/rules.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const AUDIO = preload("res://scripts/characters/我的世界/snow_golem/audio.gd")
const HEADS_VIEW = preload("res://scripts/characters/我的世界/snow_golem/heads_view.gd")
var patches:Dictionary = {} # Vector2i -> level 1 (half size, harmless) / 2 (full tile)
var heads:Dictionary = {} # int -> falling pumpkin and 0/1/2 snow blocks
var _serial:int = 0
var _clock:float = 0.0
var _next_melt:float = INF
var _ground_left:float = 0.0
var _sync_left:float = 0.0
var _damage_until:Dictionary = {}
var _positions:Dictionary = {}
var _dirty_cells:Dictionary = {}
var _heads_dirty:bool = false
var _head_view:Node2D

static func ensure(context:Node) -> Node2D:
	var world:Node = context.get_tree().current_scene
	var existing:Node = world.get_node_or_null("MCSnowField")
	if is_instance_valid(existing):
		if not existing.is_queued_for_deletion(): return existing as Node2D
		# Reset/rematch may create the next battle before queued deletion is flushed.
		# Retire the old name so the replacement keeps its stable lookup/RPC path.
		existing.name = "RetiredMCSnowField_"+str(existing.get_instance_id())
	var field:Node2D = load("res://scenes/effects/我的世界/雪傀儡雪地.tscn").instantiate()
	field.name = "MCSnowField"
	field.set_multiplayer_authority(world.get_multiplayer_authority())
	world.add_child(field)
	return field

static func cell_at(point:Vector2) -> Vector2i: return Vector2i((point/CELL).round())
static func point_at(cell:Vector2i) -> Vector2: return Vector2(cell)*CELL

func _ready() -> void:
	add_to_group("BattleTransient")
	# World defaults to z=-2; floor is -4/-5 and normal bodies/shots are -2.
	# Keep ground RELATIVE below its world, not absolute above ordinary actors.
	z_as_relative = true
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_head_view = HEADS_VIEW.new()
	_head_view.field = self
	add_child(_head_view)
	if not is_multiplayer_authority(): call_deferred("_request_state")

func runtime_active() -> bool:
	if get_tree() == null or get_tree().paused or Game.now_stop_state or Engine.time_scale <= 0.000001: return false
	var world:Node = get_tree().current_scene
	return bool(world.call("is_combat_runtime_active")) if world.has_method("is_combat_runtime_active") else true

func can_place(source:Node2D,cell:Vector2i) -> bool:
	var point:Vector2 = point_at(cell)
	var world:Node = get_tree().current_scene
	if world.has_method("_current_map_node") and world.has_method("return_map_world_rect"):
		var map:Node = world.call("_current_map_node")
		if is_instance_valid(map):
			var bounds:Rect2 = world.call("return_map_world_rect",map)
			if not bounds.grow(-CELL*0.49).has_point(point): return false
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE*(CELL-1.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 1
	query.collide_with_areas = false
	if not get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return not is_instance_valid(source) or U.line_clear(source,source.global_position,point)

func _same_side(source:ball,entry:Dictionary) -> bool:
	return str(entry.family) == str(source.get_meta("mc_snow_family","")) or (not source.Team.is_empty() and source.Team == str(entry.team))

func deposit(source:ball,cell:Vector2i,half_size:bool = false) -> bool:
	if not is_multiplayer_authority() or not runtime_active() or not is_instance_valid(source) or source.health <= 0: return false
	if source.dizziness or source.is_damage_output_disabled() or not can_place(source,cell): return false
	# A settled pumpkin consumes this pass instead of also leaving a damaging tile.
	for head:Dictionary in heads.values():
		if head.cell != cell or not bool(head.landed) or not _same_side(source,head): continue
		if bool(head.pending): return false
		head.blocks = mini(2,int(head.blocks)+1)
		_heads_dirty = true
		emit_sound("block.snow.place",point_at(cell),-8.0)
		if int(head.blocks) >= 2: _queue_birth(int(head.id),source)
		_head_view.queue_redraw()
		return true
	var level:int = 1 if half_size else 2
	if patches.has(cell):
		var old:Dictionary = patches[cell]
		if not _same_side(source,old): return false
		if int(old.level) >= 2:
			# Only an actual new visit reaches deposit(); standing never refreshes it.
			_stamp_lifetime(old)
			_dirty_cells[cell] = true
			return true
		# A second distinct pass by a little snowman completes its half-sized patch.
		level = 2
	patches[cell] = {"level":level,"source":weakref(source),"family":str(source.get_meta("mc_snow_family","")),"team":source.Team}
	_stamp_lifetime(patches[cell])
	_dirty_cells[cell] = true
	queue_redraw()
	return true

func _stamp_lifetime(patch:Dictionary) -> void:
	var lifetime:float = full_snow_lifetime if int(patch.level) >= 2 else half_snow_lifetime
	patch["expires_at"] = _clock+maxf(lifetime,0.1)
	patch["half_lifetime"] = maxf(half_snow_lifetime,0.1)
	_next_melt = minf(_next_melt,float(patch.expires_at))

func _snow_present_at(patch:Dictionary,at_time:float) -> bool:
	var until:float = float(patch.get("expires_at",INF))
	if int(patch.level) >= 2: until += float(patch.get("half_lifetime",half_snow_lifetime))
	return at_time < until

func _melt_patches() -> void:
	if _clock < _next_melt: return
	_next_melt = INF
	var changed:bool = false
	for cell:Vector2i in patches.keys():
		var patch:Dictionary = patches[cell]
		if not patch.has("expires_at"): _stamp_lifetime(patch)
		if _clock >= float(patch.expires_at):
			if int(patch.level) >= 2:
				# A melted tile becomes EXACTLY the mini's harmless 12x12 snow.
				# Preserve overshoot so a long frame cannot extend its lifetime.
				patch.level = 1
				patch.expires_at = float(patch.expires_at)+float(patch.get("half_lifetime",half_snow_lifetime))
			if _clock >= float(patch.expires_at): patches.erase(cell)
			if is_multiplayer_authority(): _dirty_cells[cell] = true
			changed = true
		if patches.has(cell): _next_melt = minf(_next_melt,float(patch.expires_at))
	if changed: queue_redraw()

func choose_drop_cell(source:ball) -> Vector2i:
	var heading:Vector2 = source.direction.normalized()
	if heading == Vector2.ZERO: heading = Vector2.RIGHT
	var preferred:Vector2i = cell_at(source.global_position-heading*CELL)
	var candidates:Array[Vector2i] = [preferred,cell_at(source.global_position)]
	for offset:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		candidates.append(cell_at(source.global_position)+offset)
	for cell:Vector2i in candidates:
		if not can_place(source,cell): continue
		var occupied:bool = false
		for head:Dictionary in heads.values():
			if head.cell == cell: occupied = true
		if not occupied: return cell
	return cell_at(source.global_position)

func drop_head(source:ball) -> int:
	if not is_multiplayer_authority() or not is_instance_valid(source): return -1
	_serial += 1
	var cell:Vector2i = choose_drop_cell(source)
	var visual_scale:float = clampf(absf(source.image.global_scale.x)/0.2,0.25,4.0)
	var head_center:Vector2 = source.image.to_global(source.image.offset+Vector2(0,-32))
	heads[_serial] = {"id":_serial,"cell":cell,"point":point_at(cell),"start":head_center,"visual_scale":visual_scale,"face_right":source.is_character_visual_flipped_h(),"elapsed":0.0,"duration":0.32,"landed":false,"blocks":0,"pending":false,"family":str(source.get_meta("mc_snow_family","")),"team":source.Team,"source":weakref(source)}
	_heads_dirty = true
	emit_sound("entity.snow_golem.shear",source.global_position,-4.0)
	return _serial

func _land_head(head:Dictionary,landed_at:float = -1.0) -> void:
	if bool(head.landed): return
	head.landed = true
	head.elapsed = head.duration
	var landing_time:float = _clock if landed_at < 0.0 else landed_at
	if patches.has(head.cell) and _snow_present_at(patches[head.cell],landing_time):
		# Resolve against the actual landing time, even if this tick skips a melt.
		# Either full or half snow at the landing cell becomes the first block.
		patches.erase(head.cell)
		_dirty_cells[head.cell] = true
		head.blocks = 1
	_heads_dirty = true
	emit_sound("block.snow.place",head.point,-8.0)
	queue_redraw()

func _source(entry:Dictionary) -> ball:
	var ref:WeakRef = entry.get("source")
	var unit:Variant = ref.get_ref() if ref != null else null
	if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.health > 0: return unit as ball
	# Existing snow can be maintained by a surviving mini from the same family.
	for candidate:Node in get_tree().get_nodes_in_group("MCSnowGolem"):
		if not candidate.is_queued_for_deletion() and candidate.health > 0 and str(candidate.get_meta("mc_snow_family","")) == str(entry.family): return candidate as ball
	return null

func _queue_birth(id:int,source:ball) -> void:
	if not heads.has(id) or bool(heads[id].pending): return
	heads[id].pending = true
	_birth.call_deferred(id,weakref(source))

func _birth(id:int,source_ref:WeakRef) -> void:
	if not is_inside_tree() or not heads.has(id): return
	var head:Dictionary = heads[id]
	var source:Variant = _source(head)
	if not is_instance_valid(source): source = source_ref.get_ref()
	if not is_instance_valid(source) or source.health <= 0 or not runtime_active() or not can_place(null,head.cell):
		head.pending = false
		return
	var settings:Dictionary = source.mini_spawn_settings()
	settings["family"] = head.family
	settings["team"] = head.team
	var child_name:String = "MCSnowMini_"+str(Time.get_ticks_usec())+"_"+str(id)
	_spawn_mini(child_name,head.point,settings)
	if multiplayer.has_multiplayer_peer(): _spawn_mini.rpc(child_name,head.point,settings)
	heads.erase(id)
	_heads_dirty = true
	_head_view.queue_redraw()
	emit_phase("mini_birth",head.point)

@rpc("authority","call_remote","reliable")
func _spawn_mini(child_name:String,point:Vector2,settings:Dictionary) -> void:
	var world:Node = get_tree().current_scene
	if world.has_node(NodePath(child_name)): return
	var child:ball = load("res://scenes/creatures/我的世界/小雪人.tscn").instantiate()
	child.name = child_name
	child.Team = str(settings.team)
	child.family = str(settings.family)
	child.set_meta("mc_snow_family",child.family)
	child.set_multiplayer_authority(get_multiplayer_authority())
	for key:String in ["victory","presentation","setup"]:
		if not settings.has(key): continue
		if key == "victory":
			child.set_meta("battle_continuation_victory_side_key",settings[key])
			child.set_meta("victory_side_key",settings[key])
		elif key == "presentation": child.set_meta("battle_continuation_presentation_side_key",settings[key])
		else: child.set_meta("battle_setup_id",settings[key])
	var base_combat:Dictionary = settings.get("base_combat",{})
	for key:String in ["Damage","Speed","max_block","max_energy","Attack_Cooling","Skill_Cooling","Health_Restore","Damage_reduction"]:
		if base_combat.has(key): child.set(key,base_combat[key])
	for key:String in ["snowball_speed","shot_cold","snow_cold","freeze_duration","snow_tick_interval","snow_damage_multiplier","snowball_knockback","attack_range","aim_hold_duration"]:
		if settings.has(key): child.set(key,settings[key])
	child.position = world.to_local(point) if world is Node2D else point
	child.direction = settings.get("direction",Vector2.RIGHT).rotated(0.8)
	child.add_to_group("BattleTransient")
	world.add_child(child,true)
	# No Master lifetime dependency: this is an autonomous small snow golem.

func _patch_on_path(source_position:Vector2,target:ball) -> Dictionary:
	var destination:Vector2 = target.global_position
	var distance:float = source_position.distance_to(destination)
	if distance > CELL*8.0: source_position = destination # Teleports must not sweep an entire arena.
	var steps:int = clampi(int(ceil(source_position.distance_to(destination)/(CELL*0.4))),1,32)
	for index:int in range(steps+1):
		var cell:Vector2i = cell_at(source_position.lerp(destination,float(index)/float(steps)))
		if not patches.has(cell) or int(patches[cell].level) < 2: continue
		var entry:Dictionary = patches[cell]
		var owner_unit:ball = _source(entry)
		if RULES.enemy(owner_unit,target) and U.line_clear(self,point_at(cell),destination): return {"source":owner_unit,"point":point_at(cell)}
	return {}

func check_ground() -> void:
	if not runtime_active() or not is_multiplayer_authority(): return
	var live_ids:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or node.is_queued_for_deletion() or not node.is_combat_targetable(): continue
		var target:ball = node as ball
		var id:int = target.get_instance_id()
		live_ids[id] = true
		var previous:Vector2 = _positions.get(id,target.global_position)
		_positions[id] = target.global_position
		if _clock < float(_damage_until.get(id,-1.0)): continue
		var contact:Dictionary = _patch_on_path(previous,target)
		if contact.is_empty(): continue
		var source:ball = contact.source
		if not source.is_combat_runtime_active() or source.is_damage_output_disabled(): continue
		_damage_until[id] = _clock+maxf(source.snow_tick_interval,0.1)
		# Health is integer-valued in this project. Quantize once before subtraction
		# so 6 * 0.33333334 cannot accidentally remove three HP via truncation.
		var outgoing:float = source.attack_damage(source.snow_damage_multiplier)
		var damage:float = maxf(1.0,roundf(outgoing)) if outgoing > 0.0 else 0.0
		var before:float = maxf(float(target.health),0.0)
		var point:Vector2 = target.global_position
		var accepted:bool = target.receive_positional_damage(damage,contact.point,false,source)
		var remaining:float = maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0
		var actual:float = maxf(before-remaining,0.0)
		if actual > 0.0: emit_impact(actual,point,false)
		if accepted and is_instance_valid(target) and target.health > 0:
			if target.can_receive_negative_effects(): COLD.ensure(target).add_cold(source.snow_cold,source.freeze_duration,source)
	for id:Variant in _positions.keys():
		if not live_ids.has(id):
			_positions.erase(id)
			_damage_until.erase(id)

func advance(delta:float) -> void:
	if not runtime_active() or not is_multiplayer_authority(): return
	_clock += delta
	for head:Dictionary in heads.values():
		if not bool(head.landed):
			var elapsed:float = float(head.elapsed)+delta
			head.elapsed = minf(float(head.duration),elapsed)
			if elapsed >= float(head.duration): _land_head(head,_clock-(elapsed-float(head.duration)))
		elif int(head.blocks) >= 2 and not bool(head.pending):
			var source:ball = _source(head)
			if is_instance_valid(source): _queue_birth(int(head.id),source)
	if not heads.is_empty(): _head_view.queue_redraw()
	# Melt before collision damage: level-1 snow is immediately harmless.
	_melt_patches()
	_ground_left -= delta
	if _ground_left <= 0.0:
		_ground_left = 0.1
		check_ground()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = 0.15
		_send_changes()

func _physics_process(delta:float) -> void:
	if is_multiplayer_authority(): advance(delta)
	elif runtime_active():
		_clock += delta
		_melt_patches()
		for head:Dictionary in heads.values(): head.elapsed = minf(float(head.duration),float(head.elapsed)+delta)
		if not heads.is_empty(): _head_view.queue_redraw()

func _process(_delta:float) -> void:
	var paused:bool = not runtime_active()
	for player:Node in get_tree().get_nodes_in_group("MCSnowSound"):
		if is_instance_valid(player): player.stream_paused = paused

func _draw() -> void:
	for cell:Vector2i in patches:
		var size:Vector2 = Vector2.ONE*CELL*(0.5 if int(patches[cell].level) == 1 else 1.0)
		draw_texture_rect(SNOW,Rect2(point_at(cell)-size*0.5,size),false)

func emit_sound(event:String,point:Vector2,volume:float) -> void:
	if multiplayer.has_multiplayer_peer(): _sound.rpc(event,point,volume)
	_sound(event,point,volume)
@rpc("authority","call_remote","reliable")
func _sound(event:String,point:Vector2,volume:float) -> void: AUDIO.play(self,event,point,volume)

func emit_phase(phase:String,point:Vector2) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.get_peers().size() > 0: _phase_sound.rpc(phase,point)
	_phase_sound(phase,point)
@rpc("authority","call_remote","reliable")
func _phase_sound(phase:String,point:Vector2) -> void:
	AUDIO.play_phase(self,phase,point)

func emit_impact(actual:float,point:Vector2,include_snow:bool = true) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.get_peers().size() > 0: _impact_sound.rpc(actual,point,include_snow)
	_impact_sound(actual,point,include_snow)
@rpc("authority","call_remote","reliable")
func _impact_sound(actual:float,point:Vector2,include_snow:bool) -> void:
	AUDIO.play_impact(self,actual,point,include_snow)

func sync_cold(target:ball,value:float,frozen:float,total:float = 0.0) -> void:
	if multiplayer.has_multiplayer_peer(): _cold_state.rpc(get_tree().current_scene.get_path_to(target),value,frozen,total)
@rpc("authority","call_remote","reliable")
func _cold_state(path:NodePath,value:float,frozen:float,total:float = 0.0) -> void:
	var target:Node = get_tree().current_scene.get_node_or_null(path)
	if target is ball and target.health > 0: COLD.ensure(target).accept_state(value,frozen,total)

func _head_snapshot() -> Array:
	var result:Array = []
	for head:Dictionary in heads.values():
		var item:Dictionary = head.duplicate()
		item.erase("source")
		result.append(item)
	return result
func _cell_snapshot(cells:Array) -> Array:
	var result:Array = []
	for cell:Vector2i in cells:
		if patches.has(cell):
			var patch:Dictionary = patches[cell]
			var fallback:float = full_snow_lifetime if int(patch.level) >= 2 else half_snow_lifetime
			result.append({"cell":cell,"level":patch.level,"family":patch.family,"team":patch.team,"remaining":maxf(0.0,float(patch.get("expires_at",_clock+fallback))-_clock),"half_lifetime":float(patch.get("half_lifetime",half_snow_lifetime))})
		else: result.append({"cell":cell,"level":0})
	return result
func _send_changes() -> void:
	if not multiplayer.has_multiplayer_peer():
		_dirty_cells.clear()
		_heads_dirty = false
		return
	if not _dirty_cells.is_empty() or _heads_dirty:
		_field_state.rpc(_cell_snapshot(_dirty_cells.keys()),_head_snapshot(),false)
	_dirty_cells.clear()
	_heads_dirty = false
@rpc("authority","call_remote","reliable")
func _field_state(cells:Array,head_records:Array,full:bool) -> void:
	if full:
		patches.clear()
		_next_melt = INF
	for item:Dictionary in cells:
		if int(item.level) <= 0: patches.erase(item.cell)
		else:
			var patch:Dictionary = item.duplicate()
			var fallback:float = full_snow_lifetime if int(item.level) >= 2 else half_snow_lifetime
			# Send remaining time, never the host's absolute battle clock.
			patch["expires_at"] = _clock+maxf(0.0,float(item.get("remaining",fallback)))
			patch["half_lifetime"] = maxf(0.1,float(item.get("half_lifetime",half_snow_lifetime)))
			patches[item.cell] = patch
			_next_melt = minf(_next_melt,float(patch.expires_at))
	heads.clear()
	for head:Dictionary in head_records: heads[int(head.id)] = head
	queue_redraw()
	_head_view.queue_redraw()
func _request_state() -> void:
	if multiplayer.has_multiplayer_peer(): _request_field.rpc_id(get_multiplayer_authority())
@rpc("any_peer","call_remote","reliable")
func _request_field() -> void:
	if not is_multiplayer_authority(): return
	var peer:int = multiplayer.get_remote_sender_id()
	_field_state.rpc_id(peer,_cell_snapshot(patches.keys()),_head_snapshot(),true)
	for cold:Node in get_tree().get_nodes_in_group("MCSnowCold"):
		if is_instance_valid(cold.target): _cold_state.rpc_id(peer,get_tree().current_scene.get_path_to(cold.target),cold.amount,cold.frozen_left,cold.freeze_total)
