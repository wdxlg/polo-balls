extends "res://scripts/characters/我的世界/new5/base.gd"
## Slow construction attacks + permanent bidirectional rail infrastructure.
const CART_FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/矿车/minecart_turns.tres")
const RAILS = preload("res://scripts/characters/我的世界/minecart/powered_rails.gd")
const CART_FX = preload("res://scripts/characters/我的世界/minecart/minecart_fx.gd")
const ROLL_AUDIO = preload("res://scripts/characters/我的世界/frontier/audio.gd")
enum RushPhase { IDLE, CHARGING, DASHING, COASTING }
@export var rush_interval:float = 5.0
@export var charge_duration:float = 1.0
@export var rush_speed:float = 620.0 # Damage/knockback reference speed only, NOT a speed cap.
@export var speed_damage_factor:float = 4.70 # Doubled from 2.35; quadratic bonus has no speed clamp.
@export var start_speed:float = 120.0
@export var acceleration:float = 140.0
@export var powered_acceleration:float = 900.0
@export var brake_acceleration:float = 1200.0
@export var coast_deceleration:float = 360.0
@export var launch_distance:float = 65.0
@export var launch_speed:float = 420.0
@export var turn_response:float = 18.0
var rush_phase:int = RushPhase.IDLE
var rail_powered:bool = false
var rush_direction:Vector2 = Vector2.RIGHT
var track_id:int = 0 # Current physical graph edge.
var drive_endpoint:Vector2 = Vector2.ZERO
var drive_speed:float = 0.0
var route_braking:bool = false
var idle_left:float = 5.0 # Construction cooldown; boarding old rails does not reset it.
var charge_left:float = 0.0
var planning_points:PackedVector2Array = PackedVector2Array()
var turn_used:bool = false
var _plan_axis:Vector2 = Vector2.RIGHT
var _goal_point:Vector2 = Vector2.ZERO
var _construction_queued:bool = false
var _travel_from:int = 0
var _travel_to:int = 0
var _visited_edges:Dictionary = {}
var _boarding_lock:float = 0.0
var _hit_until:Dictionary = {}
var _normal_mask:int = 3
var _event_id:int = 0
var _last_remote_event:int = 0
var rails:Node2D
var cart_fx:Node2D
var _roll_sound:AudioStreamPlayer2D
var completed_routes:int = 0
var laid_routes:int = 0
var boarded_routes:int = 0
var junctions_passed:int = 0
var turns_taken:int = 0
var powered_entries:int = 0
var _look_angle:float = 0.0
var _view_index:int = 0
var _roll_phase:float = 0.0
var _roll_frame:int = 0
var _motion_hold:float = 0.0
var _visual_move_speed:float = 0.0
var _remote_moving:bool = false
var _received_model_state:bool = false
var laps_completed:int = 0
var _loop_anchor:int = 0
var _loop_first_edge:int = 0
var _loop_edges:Dictionary = {}
var _loop_revision:int = -1
var entry_needs_exit:bool = false
var departure_count:int = 0
var _exit_point:Vector2 = Vector2.ZERO
var _curve_active:bool = false
var _curve_center:Vector2 = Vector2.ZERO
var _curve_radius:Vector2 = Vector2.ZERO
var _curve_incoming:Vector2 = Vector2.RIGHT
var _curve_angle:float = 0.0
var _curve_progress:float = 0.0
var _curve_length:float = 1.0
func get_preview_texture() -> Texture2D: return CART_FRAMES.get_frame_texture(&"v56",0)
func _ready() -> void:
	super._ready()
	_normal_mask = _large_battle_original_collision_mask
	_ensure_visual_layer()
	idle_left = rush_interval
	_snap_facing(direction)
	add_to_group("MCMinecart")
	cart_fx = CART_FX.new()
	cart_fx.cart = self
	add_child(cart_fx)
	call_deferred("_ensure_rails")
func _ensure_rails() -> void:
	if not is_inside_tree() or health <= 0: return
	var world:Node = get_tree().current_scene
	if not is_instance_valid(world): return
	rails = world.get_node_or_null("MinecartRails") as Node2D
	if not is_instance_valid(rails):
		rails = RAILS.new()
		rails.name = "MinecartRails"
		world.add_child(rails)
		rails.add_to_group("BattleTransient")
func active() -> bool: return super.active() and not Game.now_stop_state and not get_tree().paused
func _can_rush() -> bool: return active() and can_act()
func _enemy(target:Variant) -> bool: return U.enemy(self,target) and target.health > 0
func _aim_point() -> Vector2:
	if is_player_controlled() and has_player_control_aim(): return player_control_aim_world_position()
	var target:ball = U.nearest(self)
	if _enemy(target): return ball.body_point(target,global_position)
	var axis:Vector2 = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	return global_position+axis*280.0
func _cardinal(heading:Vector2) -> Vector2:
	if absf(heading.x) >= absf(heading.y): return Vector2.RIGHT if heading.x >= 0 else Vector2.LEFT
	return Vector2.DOWN if heading.y >= 0 else Vector2.UP
func _raw_plan(axis:Vector2,use_turn:bool,goal:Vector2) -> PackedVector2Array:
	var offset:Vector2 = goal-global_position
	if not use_turn:
		var length:float = clampf(offset.dot(axis)+160.0,180.0,520.0)
		return PackedVector2Array([global_position,global_position+axis*length])
	var first:float = clampf(offset.dot(axis),72.0,360.0)
	var side:Vector2 = axis.orthogonal()
	if offset.dot(side) < 0.0: side = -side
	var second:float = clampf(absf(offset.dot(side))+140.0,100.0,520.0-first)
	var corner:Vector2 = global_position+axis*first
	return PackedVector2Array([global_position,corner,corner+side*second])
func start_charge() -> bool:
	if not _can_rush() or rush_phase != RushPhase.IDLE or idle_left > 0.0: return false
	if not is_player_controlled() and not _enemy(U.nearest(self)): return false
	if not is_instance_valid(rails): _ensure_rails()
	if not is_instance_valid(rails): return false
	_goal_point = _aim_point()
	_plan_axis = _cardinal(_goal_point-global_position)
	var use_turn:bool = not is_player_controlled() # AI visibly uses its one legal elbow whenever space allows.
	planning_points = rails.prepare_path(self,_raw_plan(_plan_axis,use_turn,_goal_point))
	# If a wall prevents the primary elbow, try the other cardinal ordering once.
	if use_turn and planning_points.size() < 3:
		var alternative:Vector2 = _plan_axis.orthogonal()
		if (_goal_point-global_position).dot(alternative) < 0: alternative = -alternative
		var candidate:PackedVector2Array = rails.prepare_path(self,_raw_plan(alternative,true,_goal_point))
		if candidate.size() == 3:
			planning_points = candidate
			_plan_axis = alternative
	if planning_points.size() < 2: return false
	turn_used = planning_points.size() == 3
	_plan_axis = planning_points[0].direction_to(planning_points[1])
	rush_direction = _plan_axis
	rush_phase = RushPhase.CHARGING
	charge_left = charge_duration
	idle_left = rush_interval
	_construction_queued = true
	drive_speed = 0.0
	rail_powered = false
	route_braking = false
	velocity = Vector2.ZERO
	_restore_body_mask()
	_sync_preview()
	_emit_cart_fx("charge",global_position,rush_direction)
	play_sound("block.piston.contract",-12.0)
	return true
func request_turn() -> bool:
	if not _can_rush() or rush_phase != RushPhase.CHARGING or not _construction_queued or turn_used or charge_left <= 0.0: return false
	var goal:Vector2 = _aim_point() if is_player_controlled() else _goal_point
	var candidate:PackedVector2Array = rails.prepare_path(self,_raw_plan(_plan_axis,true,goal))
	if candidate.size() != 3: return false
	planning_points = candidate
	turn_used = true
	_sync_preview()
	_emit_cart_fx("rail",planning_points[1],planning_points[1].direction_to(planning_points[2]))
	return true
func step_mob(delta:float) -> void:
	if not _can_rush():
		if rush_phase != RushPhase.IDLE: end_rush()
		return
	idle_left = maxf(0,idle_left-delta)
	_boarding_lock = maxf(0,_boarding_lock-delta)
	for id:Variant in _hit_until.keys():
		if float(_hit_until[id]) <= clock: _hit_until.erase(id)
	if rush_phase == RushPhase.CHARGING:
		charge_left = maxf(0,charge_left-delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self))
		if charge_left <= 0.0: launch_rush()
	elif rush_phase in [RushPhase.IDLE,RushPhase.COASTING]:
		_check_rails(global_position,global_position)
		if rush_phase == RushPhase.IDLE and idle_left <= 0.0 and not is_player_controlled():
			if not start_charge(): idle_left = 0.8 # Failed terrain placement never causes a per-frame build storm.
func launch_rush() -> void:
	if not _can_rush() or rush_phase != RushPhase.CHARGING or charge_left > 0.0 or not _construction_queued: return
	_construction_queued = false # A charge can commit exactly once.
	var final_points:PackedVector2Array = rails.prepare_path(self,planning_points) if is_instance_valid(rails) else PackedVector2Array()
	var built:Dictionary = rails.commit_path(self,final_points) if is_instance_valid(rails) else {}
	planning_points.clear()
	if built.is_empty(): end_rush(); return
	_sync_preview()
	laid_routes += 1
	var start:int = int(built.nodes[0])
	var first:int = rails.choose_edge(start,{},_goal_point,_plan_axis)
	if first == 0: end_rush(); return
	_begin_trip(start,first)
func entry_motion() -> Vector2:
	if rush_phase==RushPhase.COASTING: return rush_direction*drive_speed
	if is_player_controlled() and player_control_direction.is_zero_approx(): return Vector2.ZERO
	return velocity
func board_port(port:int,approach:Vector2 = Vector2.ZERO) -> bool:
	if entry_needs_exit: return false
	if not _can_rush() or rush_phase not in [RushPhase.IDLE,RushPhase.COASTING] or _boarding_lock > 0.0 or not is_instance_valid(rails): return false
	var point:Vector2 = rails.node_point(port)
	if not point.is_finite() or global_position.distance_to(point) > RAILS.ENTRY_RADIUS+0.1: return false
	_goal_point = _aim_point()
	var first:int = rails.entry_edge(port,entry_motion() if approach.is_zero_approx() else approach,global_position)
	if first == 0: return false
	if _begin_trip(port,first):
		boarded_routes += 1
		return true
	return false
func _begin_trip(start:int,first:int) -> bool:
	if not _can_rush() or not is_instance_valid(rails) or rails.edge(first).is_empty(): end_rush(); return false
	var point:Vector2 = rails.node_point(start)
	if not point.is_finite() or global_position.distance_to(point) > RAILS.CONNECT_RADIUS+0.5: end_rush(); return false
	if not bool(Game.Game_Settings.get("Ball_Can_Move",true)): end_rush(); return false
	var inherited:float = drive_speed if drive_speed>0.0 else maxf(start_speed,velocity.length())
	rush_phase = RushPhase.DASHING
	drive_speed = inherited
	route_braking = false
	rail_powered = false
	collision_mask = _normal_mask & ~2
	_visited_edges.clear()
	laps_completed = 0
	_loop_anchor = 0
	_loop_edges.clear()
	_setup_loop(start,first)
	_curve_active = false
	var from:Vector2 = global_position
	if point.distance_to(from) > 0.01:
		var contact:KinematicCollision2D = move_and_collide(point-from)
		if contact != null or global_position.distance_to(point) > 0.2: end_rush(); return false
	if not _select_leg(first,start): end_rush(); return false
	_sweep_enemies(from,global_position)
	_roll_sound = ROLL_AUDIO.play(self,"minecart",global_position,-16.0)
	_emit_cart_fx("launch",global_position,rush_direction)
	return true
func _select_leg(edge_id:int,from_node:int) -> bool:
	var destination:int = rails.other_end(edge_id,from_node)
	if destination == 0 or _visited_edges.has(edge_id): return false
	var heading:Vector2 = rails.node_point(from_node).direction_to(rails.node_point(destination))
	if heading.length_squared() < 0.001: return false
	if _visited_edges.size() > 0 and absf(heading.dot(rush_direction)) < 0.001: turns_taken += 1
	track_id = edge_id
	_travel_from = from_node
	_travel_to = destination
	_visited_edges[edge_id] = true
	drive_endpoint = rails.node_point(destination)
	rush_direction = heading
	direction = heading
	_snap_facing(heading)
	return true
func _arrive_node() -> void:
	if not is_instance_valid(rails): end_rush(); return
	if _finish_loop_lap(_travel_to): return
	# Connected segments are traversed in the same trip, with speed conserved across the elbow.
	var next:int = _next_leg_at(_travel_to)
	if next == 0:
		completed_routes += 1
		end_rush(true)
		return
	junctions_passed += 1
	if not _select_leg(next,_travel_to): end_rush()
func end_rush(keep_momentum:bool = false,exit_heading:Vector2 = Vector2.ZERO) -> void:
	var was_driving:bool = rush_phase == RushPhase.DASHING
	var retained:float = drive_speed
	var last_heading:Vector2 = rush_direction
	rush_phase = RushPhase.COASTING if keep_momentum and retained>normal_travel_speed() and health>0 else RushPhase.IDLE
	rail_powered = false
	route_braking = false
	track_id = 0
	drive_speed = retained if keep_momentum else 0.0
	_boarding_lock = 0.0 if keep_momentum else 0.9
	charge_left = 0.0
	planning_points.clear()
	_construction_queued = false
	_curve_active = false
	velocity = last_heading*drive_speed if keep_momentum else Vector2.ZERO
	_sync_preview()
	if was_driving:
		_exit_point = global_position
		entry_needs_exit = true
		if keep_momentum:
			_pick_departure_direction(last_heading,exit_heading)
			rush_direction = direction
			velocity = direction*drive_speed
		elif health > 0: _pick_departure_direction(last_heading)
	if is_instance_valid(_roll_sound): _roll_sound.stop(); _roll_sound.queue_free()
	_roll_sound = null
	_restore_body_mask()
func _pick_departure_direction(last_heading:Vector2,outward:Vector2 = Vector2.ZERO) -> void:
	var selected:Vector2 = last_heading.orthogonal()
	if not outward.is_zero_approx() and selected.dot(outward)<0.0: selected = -selected
	for i:int in range(20):
		var candidate:Vector2 = Vector2.RIGHT.rotated(rng.randf_range(-PI,PI))
		if absf(candidate.dot(last_heading)) > 0.65: continue
		if not outward.is_zero_approx() and candidate.dot(outward.normalized()) < 0.25: continue
		selected = candidate
		if not is_instance_valid(rails) or rails._clearance(self,global_position,global_position+candidate*40.0) > 0.95: break
	direction = selected.normalized()
	departure_count += 1
	# Random release changes heading, never speed. Closed loops additionally constrain it outward.
func _sync_preview() -> void:
	if not is_instance_valid(rails): return
	if rush_phase == RushPhase.CHARGING: rails.set_preview(get_instance_id(),planning_points)
	else: rails.clear_preview(get_instance_id())
func _ensure_visual_layer() -> void:
	if not is_instance_valid(image): return
	image.z_as_relative = false
	image.z_index = RAILS.BODY_Z
func _restore_body_mask() -> void:
	collision_mask = (_normal_mask & ~2) if rush_phase in [RushPhase.DASHING,RushPhase.COASTING] or is_large_battle_performance_mode() else _normal_mask
func set_large_battle_performance_mode(enabled:bool) -> void:
	super.set_large_battle_performance_mode(enabled)
	if rush_phase in [RushPhase.DASHING,RushPhase.COASTING]: collision_mask = _normal_mask & ~2
func wall_contact(_normal:Vector2,point:Vector2) -> void:
	if rush_phase != RushPhase.DASHING or not _can_rush(): return
	_emit_cart_fx("wall",point,-rush_direction)
	end_rush() # The track remains for later use; a newly built wall does not erase infrastructure.
func rush_attack_damage() -> float:
	var ratio:float = maxf(drive_speed,0.0)/maxf(rush_speed,1.0)
	return attack_damage(0.35+speed_damage_factor*ratio*ratio)
static func impact_sound_event(actual_damage:float) -> String:
	return "entity.player.attack.crit" if actual_damage > 50.0 else "entity.player.hurt"
static func impact_volume(actual_damage:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual_damage)
func emit_impact_sound(actual_damage:float,point:Vector2) -> void:
	if actual_damage <= 0.0 or not is_multiplayer_authority(): return
	var event:String = impact_sound_event(actual_damage)
	var volume:float = impact_volume(actual_damage)
	if multiplayer.has_multiplayer_peer(): _cart_impact_sound.rpc(event,point,volume)
	_cart_impact_sound(event,point,volume)
@rpc("authority","call_remote","reliable")
func _cart_impact_sound(event:String,point:Vector2,volume:float) -> void:
	# Per-cart throttling prevents one minecart's hit from muting another cart.
	AUDIO.play(self,event,point,volume,false,false,true)
func hit_enemy(target:Variant,point:Vector2) -> bool:
	if not has_momentum_attack() or not _enemy(target): return false
	var id:int = target.get_instance_id()
	if _hit_until.has(id) or not U.line_clear(self,point,ball.body_point(target,point)): return false
	_hit_until[id] = clock+1.0
	var ratio:float = clampf(drive_speed/maxf(rush_speed,1.0),0,1)
	var victim_ref:WeakRef = weakref(target)
	var health_before:float = maxf(float(target.health),0.0)
	var sound_point:Vector2 = ball.body_point(target,global_position)
	if not target.receive_positional_damage(rush_attack_damage(),point,false,self): return false
	# This revision keeps gaining speed through hits; the per-victim cooldown prevents overlap spam.
	var victim:Variant = victim_ref.get_ref()
	var health_after:float = maxf(float(victim.health),0.0) if is_instance_valid(victim) else 0.0
	var actual_damage:float = maxf(health_before-health_after,0.0)
	if is_instance_valid(victim) and victim.health > 0 and victim.can_receive_negative_effects():
		victim.apply_knockback(rush_direction,launch_distance*ratio,launch_speed,0.0,0.1,{"source":self,"stop_on_character":false,"collision_damage":0.0})
	_emit_cart_fx("hit",point,rush_direction)
	emit_impact_sound(actual_damage,sound_point)
	return true
func _sweep_enemies(from:Vector2,to:Vector2) -> void:
	var steps:int = clampi(int(ceil(from.distance_to(to)/6.0)),1,32)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape_2d.shape
	query.collision_mask = 2
	query.collide_with_bodies = false
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	for i:int in range(steps+1):
		var point:Vector2 = from.lerp(to,float(i)/float(steps))
		query.transform = collision_shape_2d.global_transform
		query.transform.origin += point-global_position
		for entry:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,128):
			var area:Variant = entry.get("collider")
			if area is hurtbox: hit_enemy(area.get_parent(),point)
func _check_rails(from:Vector2,to:Vector2) -> void:
	if not _can_rush() or rush_phase not in [RushPhase.IDLE,RushPhase.COASTING]: return
	if not is_instance_valid(rails): _ensure_rails()
	if not is_instance_valid(rails): return
	if entry_needs_exit:
		# Suppress only the exit just used; a different nearby entrance must remain catchable at speed.
		if to.distance_to(_exit_point)<=RAILS.EXIT_RADIUS: return
		entry_needs_exit = false
	if _boarding_lock > 0.0: return
	var port:int = rails.nearby_port(self,from,to)
	if port != 0: board_port(port,to-from if from.distance_squared_to(to)>0.000001 else entry_motion())
func move(speed_value:float,delta:float) -> void:
	var from:Vector2 = global_position
	_move_cart(speed_value,delta)
	var distance:float = from.distance_to(global_position)
	if distance > 0.001 and delta > 0.0:
		_visual_move_speed = distance/delta
		_motion_hold = 0.10
func _move_cart(speed_value:float,delta:float) -> void:
	if not active(): return
	if rush_phase == RushPhase.CHARGING:
		velocity = Vector2.ZERO
		return
	if rush_phase == RushPhase.COASTING:
		_move_coast(delta)
		return
	if rush_phase != RushPhase.DASHING:
		var from:Vector2 = global_position
		super.move(speed_value,delta)
		_check_rails(from,global_position)
		return
	if not _can_rush(): end_rush(); return
	if not bool(Game.Game_Settings.get("Ball_Can_Move",true)): return
	if not is_instance_valid(rails) or rails.edge(track_id).is_empty(): end_rush(); return
	var a:Vector2 = rails.node_point(_travel_from)
	var b:Vector2 = rails.node_point(_travel_to)
	if not _curve_active and U.segment_distance(global_position,a,b) > RAILS.CELL: end_rush(); return
	collision_mask = _normal_mask & ~2
	var dt:float = clampf(delta,0.0,0.1)
	var peak_speed:float = drive_speed+maxf(acceleration,powered_acceleration)*dt
	var steps:int = maxi(1,int(ceil(peak_speed*dt/6.0)))
	for i:int in range(steps):
		if rush_phase != RushPhase.DASHING: break
		_drive_step(dt/float(steps))
func _next_corner_edge() -> int:
	var next:int = _next_leg_at(_travel_to)
	if next == 0: return 0
	var out_dir:Vector2 = rails.node_point(_travel_to).direction_to(rails.node_point(rails.other_end(next,_travel_to)))
	return next if absf(out_dir.dot(rush_direction)) < 0.001 else 0
func _begin_corner(next:int) -> void:
	if _finish_loop_lap(_travel_to): return
	var corner:Vector2 = drive_endpoint
	var from_node:int = _travel_to
	var destination:int = rails.other_end(next,from_node)
	var out_dir:Vector2 = corner.direction_to(rails.node_point(destination))
	var radius:float = RAILS.CELL*0.5
	_curve_incoming = rush_direction
	_curve_center = corner-rush_direction*radius+out_dir*radius
	_curve_radius = -out_dir*radius
	_curve_angle = signf(rush_direction.cross(out_dir))*PI*0.5
	_curve_progress = 0.0
	_curve_length = radius*PI*0.5
	_curve_active = true
	track_id = next
	_travel_from = from_node
	_travel_to = destination
	_visited_edges[next] = true
	drive_endpoint = rails.node_point(destination)
	turns_taken += 1
	junctions_passed += 1
func _drive_step(delta:float) -> void:
	var was_powered:bool = rail_powered
	rail_powered = rails.is_powered_at(track_id,global_position)
	if rail_powered and not was_powered:
		powered_entries += 1
		_emit_cart_fx("rail",global_position,rush_direction)
	if route_braking:
		drive_speed = move_toward(drive_speed,0.0,brake_acceleration*delta)
		if drive_speed <= 1.0: end_rush(); return
	else: drive_speed += (powered_acceleration if rail_powered else acceleration)*delta
	var remaining:float = drive_speed*delta
	for pass_index:int in range(6):
		if rush_phase != RushPhase.DASHING or remaining <= 0.0001: return
		var from:Vector2 = global_position
		var destination:Vector2
		var amount:float
		if _curve_active:
			amount = minf(remaining,(1.0-_curve_progress)*_curve_length)
			_curve_progress = minf(1.0,_curve_progress+amount/_curve_length)
			destination = _curve_center+_curve_radius.rotated(_curve_angle*_curve_progress)
			rush_direction = _curve_incoming.rotated(_curve_angle*_curve_progress).normalized()
			direction = rush_direction
			_snap_facing(rush_direction)
		else:
			var distance:float = global_position.distance_to(drive_endpoint)
			var next_corner:int = _next_corner_edge()
			if next_corner != 0:
				if distance <= RAILS.CELL*0.5+0.02:
					_begin_corner(next_corner)
					continue
				distance -= RAILS.CELL*0.5
			elif distance <= 0.05:
				_arrive_node()
				continue
			amount = minf(distance,remaining)
			destination = global_position+rush_direction*amount
		velocity = rush_direction*drive_speed
		_last_requested_velocity = velocity
		var contact:KinematicCollision2D = move_with_body_collision(destination-global_position,amount/maxf(drive_speed,0.001))
		_sweep_enemies(from,global_position)
		remaining -= amount
		if contact != null: wall_contact(contact.get_normal(),contact.get_position()); return
		if _curve_active and _curve_progress >= 0.99999:
			_curve_active = false
			rush_direction = rails.node_point(_travel_from).direction_to(drive_endpoint)
			direction = rush_direction
			_snap_facing(rush_direction)
		elif not _curve_active and global_position.distance_to(drive_endpoint) <= 0.05: _arrive_node()
func stand(delta:float) -> void:
	if not active(): return
	if rush_phase == RushPhase.CHARGING and not dizziness: velocity = Vector2.ZERO; return
	super.stand(delta)
func Attack() -> void:
	Attacking = false
	start_charge()
func Skill() -> void:
	Using_Skill = false
	if rush_phase == RushPhase.CHARGING: request_turn()
	elif rush_phase in [RushPhase.DASHING,RushPhase.COASTING] and _can_rush(): route_braking = true
func player_control_action_hold_repeat_allowed(action_index:int) -> bool:
	return action_index == 0 # Holding the turn key must not turn into braking on launch.
func player_control_action(action_index:int) -> void:
	if action_index == 0: start_charge()
	elif action_index == 1: Skill()

func _snap_facing(heading:Vector2) -> void:
	if heading.length_squared() <= 0.001: return
	_look_angle = heading.angle()
	_view_index = posmod(roundi(_look_angle/TAU*64.0),64)
func advance_cart_visual(delta:float) -> void:
	if health <= 0 or Game.now_stop_state or get_tree().paused or not is_combat_runtime_active(): return
	var dt:float = maxf(delta,0.0)
	var heading:Vector2 = rush_direction if rush_phase != RushPhase.IDLE else direction
	if heading.length_squared() > 0.001:
		if rush_phase == RushPhase.DASHING:
			_snap_facing(heading) # Align immediately when the next graph edge turns 90 degrees.
		else:
			_look_angle = lerp_angle(_look_angle,heading.angle(),1.0-exp(-dt*turn_response))
			_view_index = posmod(roundi(_look_angle/TAU*64.0),64)
	_motion_hold = maxf(_motion_hold-dt,0.0)
	var moving:bool = _motion_hold > 0.0 if is_multiplayer_authority() else _remote_moving
	moving = moving and bool(Game.Game_Settings.get("Ball_Can_Move",true)) and not dizziness
	if rush_phase == RushPhase.CHARGING or moving:
		var rate:float = 1.5 if rush_phase == RushPhase.CHARGING else clampf(_visual_move_speed/48.0,0.0,2.5)
		_roll_phase = fposmod(_roll_phase+dt*rate,1.0)
		_roll_frame = 1+clampi(int(_roll_phase*8.0),0,7)
	else:
		_roll_frame = 0
func _process(delta:float) -> void:
	if is_instance_valid(_roll_sound):
		_roll_sound.global_position = global_position
		_roll_sound.stream_paused = not is_combat_runtime_active()
	advance_cart_visual(delta)
	super._process(delta)
func visual_mob() -> void:
	if not is_instance_valid(image): return
	_ensure_visual_layer()
	image.texture = CART_FRAMES.get_frame_texture(StringName("v%02d" % _view_index),_roll_frame)
	# Model yaw selects the perspective. Mirroring/rotating a flat item is not a turn.
	set_character_visual_flip_h(false)
	image.flip_h = false
	image.rotation = 0.0
	image.offset = Vector2.ZERO
	if is_instance_valid(cart_fx): cart_fx.queue_redraw()
	side_status_remove_permanent("left","minecart_momentum")
func _emit_cart_fx(kind:String,point:Vector2,heading:Vector2) -> void:
	_event_id += 1
	if multiplayer.has_multiplayer_peer(): _cart_event.rpc(_event_id,kind,point,heading)
	_cart_event(_event_id,kind,point,heading)
@rpc("authority","call_remote","reliable")
func _cart_event(id:int,kind:String,point:Vector2,heading:Vector2) -> void:
	if id <= _last_remote_event: return
	_last_remote_event = id
	if is_instance_valid(cart_fx): cart_fx.burst(kind,point,heading)

func visual_state() -> Dictionary:
	return {"time":clock,"phase":rush_phase,"powered":rail_powered,"heading":rush_direction,"charge":charge_left,"cooldown":idle_left,"plan":planning_points,"turn_used":turn_used,"track":track_id,"speed":drive_speed,"braking":route_braking,"needs_exit":entry_needs_exit,"exit_point":_exit_point,"laps":laps_completed,"move_heading":direction,"look_angle":_look_angle,"roll_phase":_roll_phase,"roll_frame":_roll_frame,"moving":_motion_hold>0.0,"visual_speed":_visual_move_speed}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	rush_phase = clampi(int(data.get("phase",0)),0,3)
	rail_powered = bool(data.get("powered",false))
	rush_direction = data.get("heading",Vector2.RIGHT)
	charge_left = float(data.get("charge",0.0))
	idle_left = float(data.get("cooldown",0.0))
	planning_points = PackedVector2Array(data.get("plan",[]))
	turn_used = bool(data.get("turn_used",false))
	track_id = int(data.get("track",0))
	var received_speed:float = float(data.get("speed",0))
	drive_speed = maxf(received_speed,0.0) if is_finite(received_speed) else 0.0
	route_braking = bool(data.get("braking",false))
	entry_needs_exit = bool(data.get("needs_exit",false))
	_exit_point = data.get("exit_point",global_position)
	laps_completed = clampi(int(data.get("laps",0)),0,2)
	_sync_preview()
	direction = data.get("move_heading",direction)
	_remote_moving = bool(data.get("moving",false))
	_visual_move_speed = maxf(float(data.get("visual_speed",0)),0)
	_roll_phase = fposmod(float(data.get("roll_phase",_roll_phase)),1.0)
	_roll_frame = clampi(int(data.get("roll_frame",0)),0,8)
	if not _received_model_state:
		_look_angle = float(data.get("look_angle",direction.angle()))
		_received_model_state = true
	if rush_phase == RushPhase.DASHING: _snap_facing(rush_direction)
	else: _view_index = posmod(roundi(_look_angle/TAU*64.0),64)
func get_debug_attack_regions() -> Array:
	if not has_momentum_attack(): return []
	return [{"shape":"rect","position":collision_shape_2d.global_position,"half_extents":collision_shape_2d.shape.size*collision_shape_2d.global_scale.abs()*0.5,"rotation":global_rotation,"damage":rush_attack_damage(),"kind":"minecart_rail_speed"}]
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_MINECART")

func Die() -> void:
	if _death_sound_done: return
	end_rush()
	ITEM_DEATH.spawn(self)
	super.Die()

func _exit_tree() -> void:
	if is_instance_valid(rails): rails.clear_preview(get_instance_id())
	super._exit_tree()

func normal_travel_speed() -> float:
	return maxf(Speed,0.0)*(CHARACTER_BASE_MOVE_SPEED_MULTIPLIER if Type==Ball_Type.Ball else 1.0)
func has_momentum_attack() -> bool:
	if not _can_rush(): return false
	if rush_phase == RushPhase.COASTING: return drive_speed>normal_travel_speed()+0.001
	return rush_phase == RushPhase.DASHING and drive_speed>=90.0
func _move_coast(delta:float) -> void:
	if not _can_rush(): end_rush(); return
	if not bool(Game.Game_Settings.get("Ball_Can_Move",true)): return
	var dt:float = clampf(delta,0.0,0.1)
	var steps:int = maxi(1,int(ceil(drive_speed*dt/6.0)))
	var step:float = dt/float(steps)
	collision_mask = _normal_mask & ~2
	for i:int in range(steps):
		if rush_phase != RushPhase.COASTING: break
		var normal:float = normal_travel_speed()
		drive_speed = move_toward(drive_speed,normal,(brake_acceleration if route_braking else coast_deceleration)*step)
		if drive_speed<=normal+0.001:
			rush_phase = RushPhase.IDLE
			route_braking = false
			_restore_body_mask()
			break
		var from:Vector2 = global_position
		velocity = rush_direction*drive_speed
		_last_requested_velocity = velocity
		var collision:KinematicCollision2D = move_with_body_collision(velocity*step,step)
		_sweep_enemies(from,global_position)
		if collision != null:
			rush_direction = rush_direction.bounce(collision.get_normal()).normalized()
			direction = rush_direction
			_emit_cart_fx("wall",global_position,rush_direction)
		_snap_facing(rush_direction)
		_check_rails(from,global_position)
func _setup_loop(node:int,first:int) -> void:
	var cycle:Array = rails.loop_nodes(node)
	if cycle.is_empty(): return
	_loop_anchor = node
	_loop_first_edge = first
	_loop_revision = rails.revision
	_loop_edges.clear()
	for id:Variant in cycle:
		for link:Variant in rails.physical_neighbors(int(id)): _loop_edges[int(link)] = true
func _lap_finished(node:int) -> bool:
	if node!=_loop_anchor or _loop_edges.is_empty() or _loop_revision!=rails.revision: return false
	for id:Variant in _loop_edges:
		if not _visited_edges.has(id): return false
	return true
func _next_leg_at(node:int) -> int:
	if _loop_anchor!=0 and _loop_revision!=rails.revision:
		_loop_anchor = 0
		_loop_edges.clear()
		laps_completed = 0
	var next:int = rails.choose_edge(node,_visited_edges,_goal_point,rush_direction)
	if _loop_anchor==0 and next!=0: _setup_loop(node,next)
	if _lap_finished(node): return _loop_first_edge if laps_completed==0 else 0
	return next
func _finish_loop_lap(node:int) -> bool:
	if not _lap_finished(node): return false
	laps_completed += 1
	if laps_completed<2:
		_visited_edges.clear()
		return false
	var center:Vector2 = Vector2.ZERO
	var cycle:Array = rails.loop_nodes(node)
	for id:Variant in cycle: center += rails.node_point(int(id))
	center /= maxf(float(cycle.size()),1.0)
	var outward:Vector2 = (rails.node_point(node)-center).normalized()
	if outward.is_zero_approx(): outward = rush_direction.orthogonal()
	completed_routes += 1
	end_rush(true,outward)
	return true
