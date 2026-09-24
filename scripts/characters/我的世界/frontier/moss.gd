extends "res://scripts/characters/我的世界/frontier/base.gd"
## Persistent, non-colliding moss obstacles; four-neighbour burrow ambush.
const BODY:Texture2D = preload("res://Images/characters/我的世界/frontier/moss_block.png")
const CELL:float = 24.0
const FOOTSTEPS = preload("res://scripts/characters/我的世界/frontier/moss_footsteps.gd")
const MAX_LAYERS:int = 3
const GROWTH_TILES:int = 6
const NEIGHBOURS:Array[Vector2i] = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
@export var growth_interval:float = 3.6
@export var damage_interval:float = 0.8
@export var moss_damage_multiplier:float = 0.625
@export var burrow_heal_per_layer:float = 4.0
@export var healing_per_second:float = 6.0
@export var burrow_delay:float = 0.65
@export var burrow_cooldown:float = 5.0
@export var burrow_damage_multiplier:float = 3.75 # 16 base attack -> 60 emergence damage.
@export var moss_sound_gain_db:float = 16.0
@export var burrow_radius:float = 42.0
@export var burrow_knockback:float = 18.0
@export var burrow_knockback_speed:float = 180.0
@export_category("Moss / Burrow animation")
@export var burrow_sink_time:float = 0.28
@export var burrow_rise_time:float = 0.2
@export var burrow_fall_time:float = 0.24
@export var burrow_settle_time:float = 0.3
@export var burrow_jump_height:float = 34.0
var _moss_pose_phase:String = ""
var _moss_pose_started:float = 0.0
var _moss_rest_scale:Vector2 = Vector2.ONE
var _moss_rest_position:Vector2 = Vector2.ZERO
var _moss_rest_alpha:float = 1.0
var _moss_body_height:float = 16.0
var _moss_pose_applied:bool = false
@export_category("Moss / Placement animation")
@export var placement_shrink_time:float = 0.22
@export var placement_spring_time:float = 0.42
@export_range(0.05,1.0,0.05) var placement_move_ratio:float = 0.45
@export_range(0.0,1.0) var placement_preview_alpha:float = 0.28
var _growth_pending:Array[Dictionary] = []
var _growth_winding:bool = false
var patches:Array[Dictionary] = []
var growth_left:float = 0.6
var growth_count:int = 0
var _field_left:float = 0.0
var _heal_left:float = 1.0
var _damage_until:Dictionary = {}
var _patch_serial:int = 0
var burrowing:bool = false
var burrow_left:float = 0.0
var burrow_wait:float = 0.0
var burrow_origin:Vector2 = Vector2.ZERO
var burrow_destination:Vector2 = Vector2.ZERO
var _exit_owner:Node
var _exit_serial:int = -1
var _moss_sound_serial:int = 0
var _last_moss_sound:int = 0
var _saved_collision_layer:int = 0
var _saved_collision_mask:int = 0
func role_key() -> String: return "moss"
func get_preview_texture() -> Texture2D: return BODY
func _ready() -> void:
	super._ready()
	_moss_rest_scale = image.scale
	_moss_rest_position = image.position
	_moss_rest_alpha = image.self_modulate.a
	_moss_body_height = image.get_rect().size.y*absf(image.scale.y)
	add_to_group("MCMossOwner")
	# The obstacle manager queries these data-backed obstacles without physics shapes.
	add_to_group("MCNonCollidingObstacleOwner")
	FOOTSTEPS.ensure(self)
func emit_moss_sound(event:String,point:Vector2,volume:float,target:Node2D = null) -> void:
	if not is_multiplayer_authority(): return
	if event.begins_with("block.moss."): volume += moss_sound_gain_db
	var path:NodePath = NodePath("")
	if is_instance_valid(target): path = get_tree().current_scene.get_path_to(target)
	_moss_sound_serial += 1
	if multiplayer.has_multiplayer_peer(): _moss_sound.rpc(_moss_sound_serial,event,point,volume,path)
	_moss_sound(_moss_sound_serial,event,point,volume,path)
@rpc("authority","call_remote","reliable")
func _moss_sound(id:int,event:String,point:Vector2,volume:float,target_path:NodePath) -> void:
	if id <= _last_moss_sound: return
	_last_moss_sound = id
	var context:Node = self
	if not target_path.is_empty():
		context = get_tree().current_scene.get_node_or_null(target_path)
		if not is_instance_valid(context): return
	# Steps are throttled per walker, not per terrain owner or global sound event.
	if event == "block.moss.step":
		var previous:Variant = context.get_meta("mc_moss_step_player",false)
		var sound:Variant = previous.get_ref() if previous is WeakRef else null
		if is_instance_valid(sound) and sound.playing: return
	# Actual damage is already gameplay-gated. Do not drop hit feedback at the
	# ambient voice cap or merge separate victims/ticks in the 75ms sound debounce.
	var impact:bool = event.begins_with("entity.player.")
	var player:AudioStreamPlayer2D = AUDIO.play(context,event,point,volume,false,impact,true,impact)
	if is_instance_valid(player):
		# Moss-only mix: the shared +2 dB ceiling otherwise swallows the extra gain.
		# Retain the selected native variant gain without raising other characters.
		if event.begins_with("block.moss."):
			for record:Dictionary in AUDIO.EVENTS.get(event,[]):
				if record.stream == player.stream:
					player.volume_db = clampf(volume+linear_to_db(maxf(float(record.volume),0.01)),-24.0,6.0)
					break
		player.max_distance = 2200.0
		player.attenuation = 0.3
		_cue_players.append(player)
		if event == "block.moss.step": context.set_meta("mc_moss_step_player",weakref(player))
static func impact_sound_event(actual_damage:float) -> String:
	return "entity.player.attack.crit" if actual_damage > 50.0 else "entity.player.hurt"
static func impact_volume(actual_damage:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual_damage)
func damage_with_moss_sound(target:ball,amount:float,point:Vector2,per_victim:bool = false) -> bool:
	if not is_instance_valid(target): return false
	var before:float = maxf(float(target.health),0.0)
	var sound_point:Vector2 = target.global_position
	var victim_ref:WeakRef = weakref(target)
	var accepted:bool = U.damage(self,target,amount,point)
	var victim:Variant = victim_ref.get_ref()
	var remaining:float = maxf(float(victim.health),0.0) if is_instance_valid(victim) else 0.0
	var actual:float = maxf(before-remaining,0.0)
	if accepted and actual > 0.0:
		emit_moss_sound(impact_sound_event(actual),sound_point,impact_volume(actual),victim as Node2D if per_victim and is_instance_valid(victim) else null)
	return accepted
func cell_at(point:Vector2) -> Vector2i:
	return Vector2i((point/CELL).round())
func patch_at(point:Vector2) -> Dictionary:
	var cell:Vector2i = cell_at(point)
	for patch:Dictionary in patches:
		if cell_at(patch.point) == cell: return patch
	return {}
func moss_field() -> Dictionary:
	var field:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("MCMossOwner"):
		if not is_instance_valid(node) or node.health <= 0: continue
		for patch:Dictionary in node.patches:
			field[cell_at(patch.point)] = {"owner":node,"patch":patch}
	return field
func can_plant_at(point:Vector2) -> bool:
	var cell:Vector2i = cell_at(point)
	var offset:Vector2i = cell-cell_at(global_position)
	if absi(offset.x) > 2 or absi(offset.y) > 2: return false
	var snapped:Vector2 = Vector2(cell)*CELL
	if not floor_clear(snapped,CELL*0.42) or not U.line_clear(self,global_position,snapped): return false
	var field:Dictionary = moss_field()
	return not field.has(cell) or int(field[cell].patch.layers) < MAX_LAYERS
func plant(point:Vector2) -> bool:
	if not can_act() or burrowing: return false
	var cell:Vector2i = cell_at(point)
	var offset:Vector2i = cell-cell_at(global_position)
	if absi(offset.x) > 2 or absi(offset.y) > 2: return false
	var snapped:Vector2 = Vector2(cell)*CELL
	if not floor_clear(snapped,CELL*0.42) or not U.line_clear(self,global_position,snapped): return false
	var field:Dictionary = moss_field()
	if field.has(cell):
		var patch:Dictionary = field[cell].patch
		if int(patch.layers) >= MAX_LAYERS: return false
		patch.layers = int(patch.layers)+1
	else:
		_patch_serial += 1
		patches.append({"point":snapped,"layers":1,"serial":_patch_serial})
	emit_moss_sound("block.moss.place",snapped,-11.0)
	emit_effect("moss_place",snapped)
	return true
func cultivate() -> bool:
	if not can_act() or burrowing or growth_left > 0.0 or placement_active(): return false
	if bool(burrow_pose(_moss_pose_phase,maxf(clock-_moss_pose_started,0.0)).active): return false
	var candidates:Array[Vector2i] = []
	var root_cell:Vector2i = cell_at(global_position)
	for x:int in range(-2,3):
		for y:int in range(-2,3): candidates.append(root_cell+Vector2i(x,y))
	# Seeded Fisher-Yates; no repeated cell in one growth, including stacked cells.
	for i:int in range(candidates.size()-1,0,-1):
		var j:int = rng.randi_range(0,i)
		var swap:Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	_growth_pending.clear()
	var field:Dictionary = moss_field()
	for cell:Vector2i in candidates:
		if _growth_pending.size() >= GROWTH_TILES: break
		var point:Vector2 = Vector2(cell)*CELL
		if can_plant_at(point):
			_growth_pending.append({"point":point,"layer":int(field[cell].patch.layers) if field.has(cell) else 0})
	growth_left = maxf(growth_interval,0.05)
	if _growth_pending.is_empty(): return false
	_growth_winding = true
	_moss_pose_phase = "plant"
	_moss_pose_started = clock
	apply_burrow_pose()
	frontier_fx.queue_redraw()
	return true
func placement_active() -> bool:
	return _growth_winding or (_moss_pose_phase == "plant" and clock-_moss_pose_started < maxf(placement_shrink_time,0.05)+maxf(placement_spring_time,0.05))
func finish_cultivation() -> bool:
	if not _growth_winding or clock-_moss_pose_started < maxf(placement_shrink_time,0.05): return false
	if not can_act() or burrowing:
		cancel_cultivation()
		return false
	var chosen:Array[Dictionary] = _growth_pending.duplicate(true)
	_growth_pending.clear()
	_growth_winding = false
	var made:int = 0
	# Commit only the previewed cells, rechecking blockers/full layers; never reroll.
	for entry:Dictionary in chosen:
		if plant(entry.point): made += 1
	if made > 0: growth_count += 1
	apply_burrow_pose()
	frontier_fx.queue_redraw()
	return made > 0
func cancel_cultivation() -> void:
	_growth_pending.clear()
	_growth_winding = false
	if _moss_pose_phase == "plant":
		_moss_pose_phase = ""
		reset_burrow_pose()
	if is_instance_valid(frontier_fx): frontier_fx.queue_redraw()
func slow_ratio(layers:int) -> float:
	return [0.75,0.5,0.3][clampi(layers,1,MAX_LAYERS)-1]
func check_trampling() -> void:
	if not can_act(): return
	var own_cells:Dictionary = {}
	for patch:Dictionary in patches: own_cells[cell_at(patch.point)] = patch
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,node): continue
		var target:ball = node as ball
		var cell:Vector2i = cell_at(target.global_position)
		if not own_cells.has(cell): continue
		var patch:Dictionary = own_cells[cell]
		var layers:int = int(patch.layers)
		U.slow(self,target,slow_ratio(layers),0.25,"苔藓缠足")
		var id:int = target.get_instance_id()
		if float(_damage_until.get(id,0.0)) > clock: continue
		_damage_until[id] = clock+maxf(damage_interval,0.1)
		damage_with_moss_sound(target,attack_damage(float(layers)*moss_damage_multiplier),patch.point,true)
func connected_cells(start:Vector2i,field:Dictionary) -> Dictionary:
	var seen:Dictionary = {}
	if not field.has(start): return seen
	var pending:Array[Vector2i] = [start]
	seen[start] = true
	var cursor:int = 0
	while cursor < pending.size():
		var cell:Vector2i = pending[cursor]
		cursor += 1
		for offset:Vector2i in NEIGHBOURS:
			var neighbour:Vector2i = cell+offset
			if field.has(neighbour) and not seen.has(neighbour):
				seen[neighbour] = true
				pending.append(neighbour)
	return seen
func begin_burrow() -> bool:
	if not can_act() or not Can_Skill or burrowing or burrow_wait > 0.0 or placement_active(): return false
	var field:Dictionary = moss_field()
	var connected:Dictionary = connected_cells(cell_at(global_position),field)
	if connected.is_empty(): return false
	var chosen:ball
	var best:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,node) or not node.is_combat_lockable(): continue
		if not connected.has(cell_at(node.global_position)): continue
		var distance:float = global_position.distance_squared_to(node.global_position)
		if distance < best:
			chosen = node as ball
			best = distance
	if not is_instance_valid(chosen): return false
	var exit_entry:Dictionary = field[cell_at(chosen.global_position)]
	burrow_destination = exit_entry.patch.point # Snapshot, never follow the enemy.
	_exit_owner = exit_entry.owner
	_exit_serial = int(exit_entry.patch.serial)
	burrow_origin = global_position
	burrowing = true
	burrow_left = maxf(burrow_delay,0.01)
	burrow_wait = maxf(burrow_cooldown,burrow_left)
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_moss_pose_phase = "dig"
	_moss_pose_started = clock
	apply_burrow_pose()
	emit_effect("moss_dig",Vector2(cell_at(burrow_origin))*CELL)
	return true
func cancel_burrow() -> void:
	if not burrowing: return
	burrowing = false
	burrow_left = 0.0
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	_exit_owner = null
	_moss_pose_phase = ""
	reset_burrow_pose()
func finish_burrow() -> bool:
	if not burrowing or burrow_left > 0.0: return false
	var valid_exit:bool = can_act() and is_instance_valid(_exit_owner) and _exit_owner.health > 0
	var patch:Dictionary = _exit_owner.patch_at(burrow_destination) if valid_exit else {}
	valid_exit = valid_exit and not patch.is_empty() and int(patch.get("serial",-2)) == _exit_serial
	# Destroyed/replanted exits and newly blocked terrain cancel rather than retarget.
	valid_exit = valid_exit and floor_clear(burrow_destination,U.radius(self))
	if not valid_exit:
		cancel_burrow()
		return false
	var consumed:int = _consume_burrow_area(burrow_destination)
	if consumed > 0: heal(float(consumed)*maxf(burrow_heal_per_layer,0.0))
	global_position = burrow_destination
	cancel_burrow()
	_moss_pose_phase = "emerge"
	_moss_pose_started = clock
	apply_burrow_pose()
	emit_effect("moss_emerge",global_position)
	for target:ball in foes(global_position,burrow_radius):
		if not U.line_clear(self,global_position,target.global_position): continue
		if damage_with_moss_sound(target,attack_damage(burrow_damage_multiplier),global_position) and is_instance_valid(target) and target.can_receive_negative_effects():
			var away:Vector2 = global_position.direction_to(target.global_position)
			if away.is_zero_approx(): away = burrow_origin.direction_to(burrow_destination)
			if away.is_zero_approx(): away = Vector2.RIGHT
			target.apply_knockback(away,burrow_knockback,burrow_knockback_speed)
	return true
func _consume_burrow_area(point:Vector2) -> int:
	# Resolve the current field at emergence, not the terrain that existed at entry.
	# A 3x3 square includes diagonal cells; connectivity only gates entering burrow.
	var field:Dictionary = moss_field()
	var center:Vector2i = cell_at(point)
	var consumed:int = 0
	for x:int in range(-1,2):
		for y:int in range(-1,2):
			var cell:Vector2i = center+Vector2i(x,y)
			if not field.has(cell): continue
			var entry:Dictionary = field[cell]
			if entry.owner.consume_moss_layer(entry.patch.point,int(entry.patch.serial)):
				consumed += 1
	return consumed
func consume_moss_layer(point:Vector2,serial:int) -> bool:
	for i:int in range(patches.size()):
		if patches[i].point != point or int(patches[i].serial) != serial: continue
		if int(patches[i].layers) <= 0: return false
		patches[i].layers = int(patches[i].layers)-1
		if int(patches[i].layers) <= 0: patches.remove_at(i)
		emit_effect("moss_break",point)
		emit_moss_sound("block.moss.break",point,-9.0)
		return true
	return false
func collect_obstacle_blast(point:Vector2,radius:float) -> Array:
	var result:Array = []
	for patch:Dictionary in patches:
		var nearest:Vector2 = point.clamp(patch.point-Vector2.ONE*CELL*0.5,patch.point+Vector2.ONE*CELL*0.5)
		if point.distance_squared_to(nearest) <= radius*radius:
			result.append({"point":patch.point,"serial":patch.serial})
	return result
func destroy_moss_obstacle(point:Vector2,serial:int) -> void:
	for i:int in range(patches.size()-1,-1,-1):
		if patches[i].point == point and int(patches[i].serial) == serial:
			patches.remove_at(i)
			emit_effect("moss_break",point)
			emit_moss_sound("block.moss.break",point,-9.0)
			return
func step_mob(delta:float) -> void:
	if not can_act():
		cancel_cultivation()
		cancel_burrow()
		return
	burrow_wait = maxf(0.0,burrow_wait-delta)
	for id:Variant in _damage_until.keys():
		if float(_damage_until[id]) <= clock: _damage_until.erase(id)
	_field_left -= delta
	if _field_left <= 0.0:
		_field_left = 0.1
		check_trampling()
	_heal_left -= delta
	if _heal_left <= 0.0:
		_heal_left = 1.0
		if moss_field().has(cell_at(global_position)): heal(healing_per_second)
	if burrowing:
		burrow_left = maxf(0.0,burrow_left-delta)
		if burrow_left <= 0.0: finish_burrow()
		return
	growth_left = maxf(0.0,growth_left-delta)
	if _growth_winding: finish_cultivation()
	if placement_active(): return
	if growth_left <= 0.0: cultivate()
	# Keep ball's ordinary direction/bounce movement; target selection is skill-only.
	if not is_player_controlled(): begin_burrow()
func move(speed:float,delta:float):
	if burrowing:
		velocity = Vector2.ZERO
		return
	# Slow ordinary locomotion throughout anticipation and rebound; do not
	# freeze movement or alter permanent Speed / external knockback.
	var ratio:float = clampf(placement_move_ratio,0.05,1.0) if placement_active() else 1.0
	super.move(speed*ratio,delta)
func stand(delta:float):
	if burrowing:
		velocity = Vector2.ZERO
		return
	super.stand(delta)
func Attack() -> void:
	Attacking = false
	cultivate()
func Skill() -> void:
	Using_Skill = false
	begin_burrow()
func player_control_action(action_index:int) -> void:
	if action_index == 0: cultivate()
	elif action_index == 1: begin_burrow()
func visual_mob() -> void:
	if not is_instance_valid(image): return
	image.texture = BODY
	image.rotation = 0.0
	apply_burrow_pose()
	# Match ball movement (including direct control), preserving the last side
	# for vertical/stationary movement. UV mirroring must not negate pose scale.
	face_horizontal(player_control_direction if is_player_controlled() else direction,dir_left)
	# No extra moss-count/layer/cooldown text above the body; keep normal HUD.
	side_status_remove_permanent("left","mc_frontier")
	_status_text = ""
func burrow_pose(phase:String,elapsed:float) -> Dictionary:
	var result:Dictionary = {"scale":Vector2.ONE,"offset":Vector2.ZERO,"alpha":1.0,"visible":true,"active":false}
	if phase == "plant":
		var shrink:float = maxf(placement_shrink_time,0.05)
		var spring:float = maxf(placement_spring_time,0.05)
		result.active = elapsed < shrink+spring
		if elapsed < shrink:
			var t:float = clampf(elapsed/shrink,0.0,1.0)
			result.scale = Vector2.ONE*lerpf(1.0,0.68,smoothstep(0.0,1.0,t))
		elif elapsed < shrink+spring:
			var t:float = clampf((elapsed-shrink)/spring,0.0,1.0)
			# Rebound starts exactly at the placement commit; overshoot, then settle.
			result.scale = Vector2.ONE*(1.0-0.32*cos(t*TAU*1.5)*exp(-4.0*t)*(1.0-t))
	elif phase == "dig":
		var duration:float = minf(maxf(burrow_sink_time,0.05),maxf(burrow_delay,0.01))
		var t:float = clampf(elapsed/duration,0.0,1.0)
		result.active = true
		result.scale = Vector2(lerpf(1.0,0.12,t*t),lerpf(1.0,1.3,sin(t*PI*0.5)))
		result.offset = Vector2(0,_moss_body_height*0.75*t*t)
		result.alpha = 1.0-smoothstep(0.5,1.0,t)
		result.visible = t < 1.0
	elif phase == "emerge":
		var rise:float = maxf(burrow_rise_time,0.05)
		var fall:float = maxf(burrow_fall_time,0.05)
		var settle:float = maxf(burrow_settle_time,0.05)
		result.active = elapsed < rise+fall+settle
		var jump:float = burrow_jump_height/maxf(absf(image.get_parent().global_scale.y),0.01)
		if elapsed < rise:
			var t:float = clampf(elapsed/rise,0.0,1.0)
			var lift:float = 1.0-pow(1.0-t,3.0)
			result.scale = Vector2(lerpf(0.2,0.55,lift),lerpf(1.45,1.25,lift))
			result.offset = Vector2(0,lerpf(_moss_body_height*0.5,-jump,lift))
			result.alpha = smoothstep(0.0,0.2,t)
		elif elapsed < rise+fall:
			var t:float = clampf((elapsed-rise)/fall,0.0,1.0)
			result.scale = Vector2(lerpf(0.55,0.8,t*t),lerpf(1.25,1.12,t*t))
			result.offset = Vector2(0,-jump*(1.0-t*t))
		elif elapsed < rise+fall+settle:
			var t:float = clampf((elapsed-rise-fall)/settle,0.0,1.0)
			# Landing squash, then a decaying stretch/squash bounce, exact rest at the end.
			var spring:float = cos(t*TAU*1.5)*exp(-5.0*t)*(1.0-t)
			result.scale = Vector2(1.0+0.32*spring,1.0-0.28*spring)
			result.offset = Vector2(0,_moss_body_height*0.5*(1.0-result.scale.y))
	return result
func apply_burrow_pose() -> void:
	if not is_instance_valid(image): return
	var visual_time:float = clock if is_multiplayer_authority() else _view_clock
	var pose:Dictionary = burrow_pose(_moss_pose_phase,maxf(visual_time-_moss_pose_started,0.0))
	if pose.active:
		image.scale = _moss_rest_scale*pose.scale
		image.position = _moss_rest_position+pose.offset
		image.self_modulate.a = _moss_rest_alpha*float(pose.alpha)
		image.visible = bool(pose.visible)
		_moss_pose_applied = true
	elif _moss_pose_applied:
		reset_burrow_pose()
func reset_burrow_pose() -> void:
	if not is_instance_valid(image): return
	image.scale = _moss_rest_scale
	image.position = _moss_rest_position
	image.self_modulate.a = _moss_rest_alpha
	image.visible = true
	_moss_pose_applied = false
func visual_state() -> Dictionary:
	return {"time":clock,"growth_pending":_growth_pending.duplicate(true),"growth_winding":_growth_winding,"patches":patches.duplicate(true),"growth":growth_left,"burrowing":burrowing,"burrow_left":burrow_left,"burrow_wait":burrow_wait,"burrow_origin":burrow_origin,"burrow_destination":burrow_destination,"moss_pose_phase":_moss_pose_phase,"moss_pose_started":_moss_pose_started}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	patches.assign(data.get("patches",[]))
	_growth_pending.assign(data.get("growth_pending",[]))
	_growth_winding = bool(data.get("growth_winding",false))
	growth_left = float(data.get("growth",0.0))
	burrowing = bool(data.get("burrowing",false))
	burrow_left = float(data.get("burrow_left",0.0))
	burrow_wait = float(data.get("burrow_wait",0.0))
	burrow_origin = data.get("burrow_origin",global_position)
	burrow_destination = data.get("burrow_destination",global_position)
	_moss_pose_phase = str(data.get("moss_pose_phase","dig" if burrowing else ""))
	_moss_pose_started = float(data.get("moss_pose_started",_view_clock))
func get_debug_attack_regions() -> Array:
	var result:Array = []
	if not can_act(): return result
	for patch:Dictionary in patches:
		result.append({"shape":"circle","position":patch.point,"radius":CELL*0.5,"damage":attack_damage(float(patch.layers)*moss_damage_multiplier),"kind":"stacked_moss"})
	return result
func get_armor_test_effect_summary() -> String:
	if english():
		return "Periodically spread persistent moss nearby, stacking to a limit. Deeper moss deals more trampling damage and slows enemies more; standing on moss heals the owner. Trampling does not consume it.\nBurrow through connected moss to the enemy position recorded on entry, then emerge with damage and knockback. Consume nearby moss layers to heal; destroyed or blocked exits cancel the ambush. Moss does not block movement and can be destroyed by ghast blasts."
	return "定期在周围随机铺设苔藓，可叠层但有上限；层数越高，踩踏伤害与减速越强。自身站在苔藓上回血，踩踏不消耗苔藓。\n与敌人处于同片横纵相连的苔藓时，可钻地突袭敌人入地时的位置，造成伤害并击退；出土消耗附近苔藓，消耗越多，回血越多。\n苔藓不阻挡移动，也不会自然消失，但可被恶魂爆炸破坏；出口被毁或受阻会取消突袭。"

func Die() -> void:
	if _death_sound_done: return
	cancel_cultivation()
	cancel_burrow()
	_moss_pose_phase = ""
	reset_burrow_pose()
	patches.clear()
	ITEM_DEATH.spawn(self)
	super.Die()
