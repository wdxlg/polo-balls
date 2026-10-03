extends "res://scripts/characters/我的世界/new5/base.gd"
## Heavy vanilla anvil: gravity, speed-dependent contact damage, hit-confirmed chain slams.
const TEXTURE:Texture2D = preload("res://Images/characters/我的世界/anvil/anvil.png")
const LAND_SOUND:AudioStream = preload("res://audio/characters/我的世界/anvil/anvil_land.ogg")
const BREAK_SOUND:AudioStream = preload("res://audio/characters/我的世界/anvil/anvil_break.ogg")
const ESCAPE_LEASE:Script = preload("res://scripts/characters/我的世界/anvil_escape_lease.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
@export_category("铁砧 / 重力")
@export_range(100.0,4000.0,25.0) var gravity_acceleration:float = 1200.0
@export_range(100.0,2400.0,25.0) var terminal_speed:float = 1100.0
@export_range(0.0,250.0,5.0) var minimum_impact_speed:float = 80.0
@export_range(60.0,600.0,10.0) var reference_damage_speed:float = 240.0
@export_category("铁砧 / 持续压伤")
@export_range(0.05,1.0,0.01) var crush_interval:float = 0.20 # Sustained damage normalization/feedback interval, not a damage lockout.
@export_range(1.0,6.0,0.5) var underside_contact_depth:float = 3.0
@export_range(0.0,1.0,0.05) var sustained_knockback_ratio:float = 0.25
@export_category("铁砧 / 砸击击退")
@export_range(0.0,0.15,0.005) var knockback_per_speed:float = 0.06
@export_range(0.0,160.0,1.0) var maximum_knockback_distance:float = 60.0
@export_range(80.0,1000.0,10.0) var impact_knockback_speed:float = 420.0
@export_category("铁砧 / 顶部连砸")
@export_range(0.20,1.50,0.05) var jump_duration:float = 0.65
@export_range(12.0,180.0,2.0) var jump_clearance:float = 48.0
@export_range(0.03,0.40,0.01) var chain_delay:float = 0.08
@export_range(0.2,10.0,0.1) var miss_cooldown:float = 2.8
@export_range(0.0,20.0,1.0) var top_padding:float = 4.0
@export_range(0.0,160.0,1.0) var fall_track_speed:float = 80.0 # Base speed before tracking_speed_scale.
@export_range(0.0,1.0,0.05) var tracking_speed_scale:float = 0.5
@export_range(0.0,10.0,0.5) var fall_track_deadzone:float = 2.0
@export_range(0.0,1600.0,25.0) var fall_track_acceleration:float = 600.0

# HOVER keeps its old numeric slot for legacy snapshots; new jumps never enter it.
enum SlamPhase {FALLING,RISING,HOVER,CHAIN_WAIT,GROUND}
var slam_phase:SlamPhase = SlamPhase.FALLING:
	set(value):
		slam_phase = value
		_sync_jump_character_collision()
var fall_speed:float = 0.0
var phase_elapsed:float = 0.0
var cooldown_left:float = 0.35
var chain_hits:int = 0
var slam_count:int = 0
var combo_slams:int = 0 # Actual descents in this combo, NOT victims or pressure ticks.
var hit_count:int = 0 # First successful impacts, once per enemy per descent.
var crush_tick_count:int = 0
var miss_count:int = 0
var last_impact_speed:float = 0.0
var last_impact_damage:float = 0.0
var _active_slam:bool = false
var _drop_connected:bool = false
var landing_count:int = 0
var _fall_hits:Dictionary = {} # Per-victim time-integrated pressure, impact and escape state.
var _crush_clock:float = 0.0
var _target_ref:WeakRef
var _fall_track_point:Vector2
var _fall_track_valid:bool = false
var _fall_track_velocity:float = 0.0
# Initial impulse and pursuit use ONE velocity, including both jump and fall.
var _launch_horizontal_speed:float = 0.0
var _jump_from:Vector2
var _jump_to:Vector2
var _jump_arc_height:float = 48.0
var _jump_total_time:float = 0.65
var _drop_bounds:Rect2
var _body:CollisionShape2D
var _rest_scale:Vector2 = Vector2.ONE
var _landing_flash:float = 0.0
var _anvil_sounds:Array[WeakRef] = []
var horizontal_bounces:int = 0
var obstacle_impact_count:int = 0
var _horizontal_contact:String = ""
var _jump_ignores_characters:bool = false
var _jump_restore_character_layer:bool = false
var _jump_restore_character_mask:bool = false

func _ready() -> void:
	dir_left = false
	Has_Collision_Damage = false
	Skill_Cooling = miss_cooldown
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	Unique_Hurt_Audio = AUDIO.EVENTS["entity.player.hurt"][0].stream
	Unique_Death_Audio = BREAK_SOUND
	# Normal project collision feedback, with a vanilla non-clang block impact.
	Unique_Collide_Audio = AUDIO.EVENTS["block.metal.place"][0].stream
	When_Coliide_Tween = true
	_rest_scale = image.scale
	super._ready()
	direction = Vector2.RIGHT if direction.x>=0.0 else Vector2.LEFT
	_body = get_node("CollisionShape2D")
	collision_mask = 1 # Solid terrain; hurtbox sweeps handle characters, including large-battle mode.
	_rest_scale = image.scale
	_face_right = true
	image.z_as_relative = false
	image.z_index = 3
	add_to_group("MinecraftAnvil")
	visual_mob()

# Ignore character BODY collisions in both directions while on the jump arc.
# Removing only our mask is insufficient: another moving character still scans
# our body layer. Hurtbox/Hitbox and terrain scanning must stay untouched.
func _set_jump_character_collision_ignored(ignored:bool) -> void:
	if ignored:
		if not _jump_ignores_characters:
			_jump_restore_character_layer = get_collision_layer_value(2)
			_jump_restore_character_mask = get_collision_mask_value(2)
			_jump_ignores_characters = true
		set_collision_layer_value(2,false)
		set_collision_mask_value(2,false)
	elif _jump_ignores_characters:
		set_collision_layer_value(2,_jump_restore_character_layer)
		set_collision_mask_value(2,_jump_restore_character_mask and not is_large_battle_performance_mode())
		_jump_ignores_characters = false

func _sync_jump_character_collision() -> void:
	if not is_node_ready(): return
	_set_jump_character_collision_ignored(slam_phase==SlamPhase.RISING and health>0 and not is_queued_for_deletion())

func set_large_battle_performance_mode(enabled:bool) -> void:
	super.set_large_battle_performance_mode(enabled)
	if _jump_ignores_characters:
		# Base mode switches may restore a mask; remember the new ordinary state,
		# then reapply temporary jump immunity without changing area collisions.
		_jump_restore_character_mask = get_collision_mask_value(2)
	_sync_jump_character_collision()

func get_preview_texture() -> Texture2D: return TEXTURE
func move(_speed:float,_delta:float): pass # step_mob owns the gravity integration exactly once.
func stand(_delta:float): Repel = Vector2.ZERO # Do not apply displacement a second time while stunned.
func mc_enemy(target:Variant) -> bool:
	if not U.enemy(self,target) or target.health<=0 or target.is_queued_for_deletion(): return false
	if target.Type not in [Ball_Type.Ball,Ball_Type.Creature]: return false
	if target==Master or target.Master==self: return false
	if is_instance_valid(Master) and target.Master==Master: return false
	return true
func can_slam() -> bool:
	return active() and Can_Skill and not dizziness and not is_damage_output_disabled()
func _nearest_enemy() -> ball:
	var result:ball
	var distance:float = INF
	for raw:Node in SubmissionCharacterTools.targeting_candidates(self):
		if not mc_enemy(raw) or not raw.is_combat_lockable(): continue
		var d:float = global_position.distance_squared_to(ball.body_point(raw,global_position))
		if d<distance:
			distance = d
			result = raw as ball
	return result
func _target() -> ball:
	var target:Variant = _target_ref.get_ref() if _target_ref!=null else null
	return target as ball if mc_enemy(target) and target.is_combat_lockable() else null

func map_bounds_for(point:Vector2) -> Rect2:
	var world:Node = get_tree().current_scene
	if world==null or not world.has_method("_current_map_node"): return Rect2()
	var map:Node = world._current_map_node()
	if map==null: return Rect2()
	# Resolve one real island, never the empty union between disconnected islands.
	if map.has_method("island_entries"):
		var best:Rect2
		var distance:float = INF
		for entry:Dictionary in map.island_entries():
			var rect:Rect2 = entry.rect
			if rect.has_point(point): return rect
			var nearest:Vector2 = point.clamp(rect.position,rect.end)
			if point.distance_squared_to(nearest)<distance:
				distance = point.distance_squared_to(nearest)
				best = rect
		return best
	return world.return_map_world_rect(map)
func body_half_size() -> Vector2:
	if not is_instance_valid(_body) or _body.shape==null: return Vector2(12,14)
	return _body.shape.get_rect().size*_body.global_scale.abs()*0.5
func top_position(target:ball) -> Vector2:
	# A physical jump stays on its launch island; it cannot fly through the void
	# toward an enemy on another island instead of using the actual portals.
	var bounds:Rect2 = map_bounds_for(global_position)
	var half:Vector2 = body_half_size()
	var x:float = bounds.get_center().x if bounds.size.x<=half.x*2.0 else clampf(target.global_position.x,bounds.position.x+half.x+0.5,bounds.end.x-half.x-0.5)
	return Vector2(x,clampf(bounds.position.y+half.y+maxf(top_padding,0.5),bounds.position.y+half.y,bounds.end.y-half.y))

func jump_position(progress:float) -> Vector2:
	# Reference trajectory with pursuit disabled. Runtime X is velocity-integrated.
	var t:float = clampf(progress,0.0,1.0)
	return Vector2(_jump_from.x+_launch_horizontal_speed*_jump_total_time*t,lerpf(_jump_from.y,_jump_to.y,t)-4.0*_jump_arc_height*t*(1.0-t))
func jump_velocity(progress:float) -> Vector2:
	var t:float = clampf(progress,0.0,1.0)
	var delta:Vector2 = _jump_to-_jump_from
	return Vector2(_launch_horizontal_speed,(delta.y-4.0*_jump_arc_height+8.0*_jump_arc_height*t)/maxf(_jump_total_time,0.001))
func _configure_jump_arc() -> void:
	_jump_total_time = maxf(jump_duration,0.05)
	var gap:float = absf(_jump_to.y-_jump_from.y)
	# Limit the analytical apex, not just the endpoint: the whole body must fit
	# below the map ceiling. Near the ceiling the requested clearance shrinks.
	var ceiling:float = _drop_bounds.position.y+body_half_size().y+0.5
	var headroom:float = maxf(minf(_jump_from.y,_jump_to.y)-ceiling,0.0)
	var clearance:float = clampf(jump_clearance,0.0,headroom)
	_jump_arc_height = (gap+2.0*clearance+2.0*sqrt(clearance*(gap+clearance)))*0.25

func _refresh_fall_tracking() -> void:
	# Track the current target throughout BOTH phases: no prediction or late lock.
	if not is_multiplayer_authority(): return
	_fall_track_valid = false
	if not _active_slam or slam_phase not in [SlamPhase.RISING,SlamPhase.FALLING] or not can_slam(): return
	var target:ball = _target()
	if target==null: return
	if not map_bounds_for(global_position).has_point(target.global_position): return
	_fall_track_point = target.global_position
	_fall_track_valid = true

func _fall_tracking_velocity(dt:float) -> float:
	# Return mean velocity for displacement, retaining END velocity for the next step.
	# This single momentum must be cancelled by acceleration before reversing.
	if not _active_slam or slam_phase not in [SlamPhase.RISING,SlamPhase.FALLING] or dt<=0.0: return 0.0
	var previous:float = _fall_track_velocity
	var acceleration:float = maxf(fall_track_acceleration,0.0)
	if acceleration<=0.000001: return previous
	var desired:float = 0.0
	if _fall_track_valid:
		var offset:float = _fall_track_point.x-global_position.x
		var remaining:float = maxf(absf(offset)-maxf(fall_track_deadzone,0.0),0.0)
		# A distant launch must not be hard-clamped to the ordinary pursuit speed.
		var cap:float = maxf(absf(_launch_horizontal_speed),maxf(fall_track_speed,0.0)*clampf(tracking_speed_scale,0.0,1.0))
		desired = signf(offset)*minf(cap,minf(sqrt(2.0*acceleration*remaining),remaining*10.0))
	var change:float = clampf(desired-previous,-acceleration*dt,acceleration*dt)
	_fall_track_velocity = previous+change
	# Exact constant-acceleration integral followed by coast if desired is reached
	# inside this step; includes an actual zero crossing when braking to reverse.
	var accelerating_time:float = absf(change)/acceleration
	var displacement:float = (previous+_fall_track_velocity)*0.5*accelerating_time+_fall_track_velocity*(dt-accelerating_time)
	return displacement/dt

func _sweep_drop_motion(motion:Vector2) -> Dictionary:
	# Track each actual segment: a side wall must not suspend gravity or allow
	# a diagonal shortcut in the hurtbox sweep. No sound/damage/targeting here.
	var points:Array[Vector2] = [global_position]
	var collision:KinematicCollision2D = move_and_collide(motion,false,0.001,true)
	points.append(global_position)
	if collision!=null and absf(collision.get_normal().x)>0.5 and motion.y>0.0:
		velocity.x = 0.0
		_fall_track_velocity = 0.0
		var remaining_y:float = maxf(motion.y-(global_position.y-points[0].y),0.0)
		if remaining_y>0.000001:
			collision = move_and_collide(Vector2(0.0,remaining_y),false,0.001,true)
			points.append(global_position)
	return {"points":points,"collision":collision}

func _begin_drop(sync_state:bool = true,initial_speed:float = 0.0) -> void:
	# Keep horizontal momentum across phases, plus the completed vertical arc speed.
	# A ceiling stops upward motion only; neither path inserts a hover or position snap.
	phase_elapsed = 0.0
	fall_speed = clampf(initial_speed,0.0,terminal_speed)
	velocity = Vector2(_fall_track_velocity,fall_speed)
	_fall_hits.clear()
	slam_phase = SlamPhase.FALLING
	if is_multiplayer_authority(): _refresh_fall_tracking()
	if sync_state: _sync_anvil()

func _jump_step(dt:float,sync_state:bool = true) -> void:
	_sync_jump_character_collision()
	if is_multiplayer_authority(): _refresh_fall_tracking()
	var horizontal:float = _fall_tracking_velocity(dt)
	phase_elapsed = minf(phase_elapsed+dt,_jump_total_time)
	var t:float = clampf(phase_elapsed/_jump_total_time,0.0,1.0)
	var wanted:Vector2 = Vector2(global_position.x+horizontal*dt,jump_position(t).y)
	var bounds:Rect2 = map_bounds_for(global_position)
	var half:Vector2 = body_half_size()
	if bounds.size.x<=half.x*2.0 or bounds.size.y<=half.y*2.0:
		_begin_drop(sync_state)
		return
	var clipped:Vector2 = wanted.clamp(bounds.position+half,bounds.end-half)
	velocity = Vector2(_fall_track_velocity,jump_velocity(t).y)
	# Sweep the real body through solid terrain. Even a thin obstacle/high speed
	# stops at first contact. Recovery alone must not count as hitting the floor
	# that the anvil is just taking off from.
	var collision:KinematicCollision2D = move_and_collide(clipped-global_position,false,0.001,false)
	if collision!=null or not wanted.is_equal_approx(clipped):
		if (collision!=null and absf(collision.get_normal().x)>0.5) or (not is_equal_approx(wanted.x,clipped.x) and absf(global_position.x-clipped.x)<0.02):
			_fall_track_velocity = 0.0 # Real side contact removes blocked momentum.
		_begin_drop(sync_state)
		return
	if phase_elapsed>=_jump_total_time-0.000001:
		_begin_drop(sync_state,velocity.y)

func begin_slam(target:ball = null,chained:bool = false) -> bool:
	if not can_slam(): return false
	if chained:
		if slam_phase!=SlamPhase.CHAIN_WAIT or cooldown_left>0.00001: return false
	elif _active_slam or cooldown_left>0.00001: return false
	if not mc_enemy(target) or not target.is_combat_lockable(): target = _nearest_enemy()
	if target==null: return false
	var bounds:Rect2 = map_bounds_for(global_position)
	var half:Vector2 = body_half_size()
	if bounds.size.x<=half.x*2.0 or bounds.size.y<=half.y*2.0: return false
	if not bounds.grow(0.01).encloses(Rect2(global_position-half,half*2.0)): return false
	if not chained:
		chain_hits = 0
		combo_slams = 0
	combo_slams += 1
	_target_ref = weakref(target)
	_horizontal_contact = ""
	_drop_bounds = bounds
	_jump_from = global_position
	_jump_to = top_position(target) # Reference launch-time X; pursuit changes actual X by velocity integration.
	_configure_jump_arc()
	_launch_horizontal_speed = (_jump_to.x-_jump_from.x)/_jump_total_time*clampf(tracking_speed_scale,0.0,1.0)
	_fall_track_velocity = _launch_horizontal_speed
	_fall_track_valid = false
	fall_speed = 0.0
	velocity = Vector2(_fall_track_velocity,jump_velocity(0.0).y)
	phase_elapsed = 0.0
	cooldown_left = 0.0
	_fall_hits.clear()
	_drop_connected = false
	_active_slam = true
	Using_Skill = true
	slam_phase = SlamPhase.RISING
	slam_count += 1
	_sync_anvil()
	return true
func _cancel_slam() -> void:
	_fall_track_velocity = 0.0
	_launch_horizontal_speed = 0.0
	_fall_track_valid = false
	_drop_connected = false
	_active_slam = false
	Using_Skill = false
	slam_phase = SlamPhase.FALLING
	phase_elapsed = 0.0
	fall_speed = 0.0
	velocity = Vector2.ZERO
	chain_hits = 0
	combo_slams = 0
	cooldown_left = maxf(Skill_Cooling,0.0)
	_sync_anvil()

func step_mob(delta:float) -> void:
	if not active(): return
	var remaining:float = maxf(delta,0.0)
	# Small physics steps preserve acceleration and avoid skipping narrow terrain.
	for _guard:int in range(2048):
		if remaining<=0.000001: break
		var dt:float = minf(remaining,1.0/120.0)
		remaining -= dt
		_advance_one(dt)
	visual_mob()
func _advance_one(dt:float) -> void:
	cooldown_left = maxf(cooldown_left-dt,0.0)
	_landing_flash = maxf(_landing_flash-dt,0.0)
	if _active_slam and not can_slam(): _cancel_slam()
	if not _active_slam and not is_player_controlled() and cooldown_left<=0.0 and can_slam():
		begin_slam()
	match slam_phase:
		SlamPhase.RISING:
			var motion_dt:float = motion_scaled_delta(dt)
			var travel_dt:float = minf(motion_dt,maxf(_jump_total_time-phase_elapsed,0.0))
			_jump_step(travel_dt)
			# Consume the rest of this physics step as falling, not as a dead frame.
			if slam_phase==SlamPhase.FALLING and motion_dt-travel_dt>0.000001:
				_fall_step(motion_dt-travel_dt)
		SlamPhase.HOVER:
			# Old saved/network state must not reintroduce the removed top delay.
			_begin_drop()
			_fall_step(motion_scaled_delta(dt))
		SlamPhase.CHAIN_WAIT:
			phase_elapsed += dt
			if phase_elapsed>=chain_delay:
				if not begin_slam(_target(),true): _cancel_slam()
		SlamPhase.GROUND:
			velocity = Vector2(_horizontal_step(motion_scaled_delta(dt),true),0.0)
			var bounds:Rect2 = map_bounds_for(global_position)
			var at_bottom:bool = bounds.size.y>0.0 and global_position.y+body_half_size().y>=bounds.end.y-0.1
			if not at_bottom and move_and_collide(Vector2(0,0.25),true,0.001,true)==null:
				slam_phase = SlamPhase.FALLING
				_fall_hits.clear()
				_drop_connected = false
				_fall_step(motion_scaled_delta(dt),true)
		SlamPhase.FALLING:
			_fall_step(motion_scaled_delta(dt))

func cruising_velocity() -> float:
	if _active_slam or dizziness or not bool(Game.Game_Settings.get("Ball_Can_Move",true)): return 0.0
	var heading:float = clampf(player_control_direction.x,-1.0,1.0) if is_player_controlled() else signf(direction.x)
	if not is_player_controlled() and is_zero_approx(heading): heading = 1.0
	return heading*maxf(Speed,0.0)*CHARACTER_BASE_MOVE_SPEED_MULTIPLIER

func _horizontal_step(dt:float,include_repel:bool = false) -> float:
	if _active_slam:
		_horizontal_contact = ""
		return 0.0 # Skill drop owns its limited tracking movement, not normal input.
	var drive:float = cruising_velocity()
	var requested:float = drive+(Repel.x if include_repel else 0.0)
	if absf(requested)<0.0001:
		_horizontal_contact = ""
		return 0.0
	var bounds:Rect2 = map_bounds_for(global_position)
	if bounds.size.x<=body_half_size().x*2.0: return 0.0
	var left:float = bounds.position.x+body_half_size().x
	var right:float = bounds.end.x-body_half_size().x
	var wanted:float = global_position.x+requested*dt
	var clipped:float = clampf(wanted,left,right)
	var old_mask:int = collision_mask
	# Horizontal rebounds are gameplay, including crowd mode. Only this sweep
	# scans character bodies; vertical crush and jump passthrough stay unchanged.
	collision_mask = 3
	var collision:KinematicCollision2D = move_and_collide(Vector2(clipped-global_position.x,0),false,0.001,false)
	collision_mask = old_mask
	var normal_x:float = 0.0
	var key:String = ""
	var obstacle:bool = false
	if collision!=null and absf(collision.get_normal().x)>0.5 and requested*collision.get_normal().x<0.0:
		normal_x = signf(collision.get_normal().x)
		key = str(collision.get_collider_id())+":"+str(normal_x)
		var other:Node = collision.get_collider()
		obstacle = not other is ball or (U.wall_node(other) and other.Type not in [Ball_Type.Ball,Ball_Type.Creature])
	elif wanted<left and global_position.x<=left+0.01:
		normal_x = 1.0
		key = "map_left"
		obstacle = true
	elif wanted>right and global_position.x>=right-0.01:
		normal_x = -1.0
		key = "map_right"
		obstacle = true
	if normal_x==0.0:
		_horizontal_contact = ""
		return requested
	var result:float = 0.0
	if not is_player_controlled() and drive*normal_x<0.0:
		direction = Vector2(normal_x,0.0)
		horizontal_bounces += 1
		result = cruising_velocity()
	if key!=_horizontal_contact:
		_last_requested_velocity = Vector2(requested,0.0)
		if collision!=null:
			# Reuse normal audio/deformation/noise/other-body feedback, not a bespoke mute bounce.
			when_collide(absf(requested),collision)
			if obstacle: _try_wall_hit_burst_from_collision(collision,absf(requested))
		else:
			notify_bounce_feedback(Vector2(signf(requested),0.0),absf(requested))
			notify_wall_impact_feedback(global_position-Vector2(normal_x*body_half_size().x,0),Vector2(normal_x,0),absf(requested))
	_horizontal_contact = key # Supporting contact must not replay normal effects every substep.
	return result

func falling_damage(speed:float) -> float:
	return attack_damage(maxf(speed,0.0)/maxf(reference_damage_speed,1.0))
func _fall_step(dt:float,horizontal_done:bool = false) -> void:
	_crush_clock += maxf(dt,0.0)
	_refresh_fall_tracking()
	var tracking:bool = _active_slam
	var horizontal:float = _fall_tracking_velocity(dt) if tracking else velocity.x if horizontal_done else _horizontal_step(dt)
	var recoil:Vector2 = Repel
	if horizontal_done: recoil.x = 0.0
	var bounds:Rect2 = map_bounds_for(global_position)
	if bounds.size.x<=0.0 or bounds.size.y<=0.0: return
	var half:Vector2 = body_half_size()
	var v0:float = fall_speed
	fall_speed = minf(fall_speed+gravity_acceleration*dt,terminal_speed)
	var motion:Vector2 = Vector2(horizontal*dt if tracking else 0.0,(v0+fall_speed)*0.5*dt)+recoil*dt
	velocity = Vector2(_fall_track_velocity if tracking else horizontal,fall_speed)+recoil
	var from:Vector2 = global_position
	var wanted_x:float = from.x+motion.x
	var clipped_x:float = clampf(wanted_x,bounds.position.x+half.x,bounds.end.x-half.x)
	if tracking: motion.x = clipped_x-from.x
	var floor_y:float = bounds.end.y-half.y
	var boundary_floor:bool = from.y+motion.y>=floor_y
	if boundary_floor: motion.y = maxf(floor_y-from.y,0.0)
	var sweep:Dictionary = _sweep_drop_motion(motion)
	var collision:KinematicCollision2D = sweep.collision
	var points:Array = sweep.points
	if tracking and not is_equal_approx(wanted_x,clipped_x) and absf(global_position.x-clipped_x)<0.01:
		velocity.x = 0.0
		_fall_track_velocity = 0.0
	# Sweep real hurtboxes along only the terrain-clipped path. No ray-through-wall hit.
	if motion.y>0.0 and velocity.y>=minimum_impact_speed and can_act():
		var traveled:float = 0.0
		for segment:int in range(points.size()-1):
			var segment_from:Vector2 = points[segment]
			var segment_to:Vector2 = points[segment+1]
			var length:float = segment_from.distance_to(segment_to)
			var count:int = maxi(1,int(ceil(length/2.0)))
			for i:int in range(count+1):
				var t:float = float(i)/float(count)
				var point:Vector2 = segment_from.lerp(segment_to,t)
				var fraction:float = clampf((traveled+length*t)/maxf(motion.length(),0.001),0.0,1.0)
				var impact_speed:float = maxf(lerpf(v0,fall_speed,fraction)+Repel.y,0.0)
				if impact_speed<minimum_impact_speed: continue
				for target:ball in _contacts_at(point):
					_press_contact(target,impact_speed,point,dt)
			traveled += length
	if boundary_floor and global_position.y>=floor_y-0.1:
		global_position.y = floor_y
		_land()
	elif collision!=null and collision.get_normal().y<-0.1:
		_land(collision)
func _press_contact(target:ball,impact_speed:float,point:Vector2,dt:float) -> void:
	if dt<=0.0 or slam_phase!=SlamPhase.FALLING or impact_speed<minimum_impact_speed or not can_act() or not mc_enemy(target): return
	if target not in _contacts_at(point): return
	var id:int = target.get_instance_id()
	var press:Dictionary = _fall_hits.get(id,{"next":-1.0,"connected":false,"remainder":0.0,"step":-1.0})
	# Many samples can find the same hurtbox in one 120-Hz movement step.
	if float(press.get("step",-1.0))==_crush_clock: return
	press.step = _crush_clock
	_fall_hits[id] = press
	var first:bool = not bool(press.connected)
	var feedback_due:bool = _crush_clock+0.000001>=float(press.next)
	if first and not feedback_due: return # Blocked/immune first impacts do not spam retries.
	var amount:float = falling_damage(impact_speed)
	if not first:
		# Budget time only while actually touching. Never bank off-contact time,
		# and never let integer HP rounding turn every tiny physics step into a full hit.
		press.remainder = float(press.get("remainder",0.0))+amount*dt/maxf(crush_interval,0.05)
		amount = floorf(float(press.remainder)+0.000001)
		if amount<1.0: return
		press.remainder = maxf(float(press.remainder)-amount,0.0)
	if first: press.next = _crush_clock+maxf(crush_interval,0.05)
	if not _damage_with_feedback(target,amount,point,first or feedback_due): return
	# Every confirmed pressure settlement also pushes. Only sound/flash are
	# throttled; each ordinary impulse composes with existing momentum without
	# forcing a remaining travel distance. No damage/contact means no new impulse.
	_apply_impact_knockback(target,impact_speed,point,not first)
	if first or feedback_due:
		press.next = _crush_clock+maxf(crush_interval,0.05)
		last_impact_speed = impact_speed
		_landing_flash = 0.12
	if not first:
		crush_tick_count += 1
		return # Continuation damage cannot enqueue another slam.
	hit_count += 1
	chain_hits += 1
	press.connected = true
	_drop_connected = true
	# Natural falls can begin a combo only outside cooldown. Multiple victims
	# and pressure settlements cannot reset a spent combo or bypass its recovery.
	if can_slam() and (_active_slam or cooldown_left<=0.00001):
		if not _active_slam: combo_slams = 1
		else: combo_slams = maxi(combo_slams,1)
		_target_ref = weakref(target) if mc_enemy(target) else null
		_active_slam = true
		Using_Skill = true
		cooldown_left = 0.0
	_sync_anvil()

func _underside_rect(point:Vector2) -> Rect2:
	var rect:Rect2 = _body.global_transform*_body.shape.get_rect()
	rect.position += point-global_position
	# A thin strip across the real bottom, not the whole moving body.
	return Rect2(Vector2(rect.position.x+0.5,rect.end.y-1.0),Vector2(maxf(rect.size.x-1.0,0.1),maxf(underside_contact_depth,1.0)+1.0))

func _contacts_at(point:Vector2) -> Array[ball]:
	var strip:Rect2 = _underside_rect(point)
	var shape := RectangleShape2D.new()
	shape.size = strip.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,strip.get_center())
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result:Array[ball] = []
	for contact:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,128):
		var collider:Node = contact.collider
		var target:Node = collider
		while is_instance_valid(target) and not target is ball: target = target.get_parent()
		if not target is ball or collider!=target.self_hurtbox or not mc_enemy(target): continue
		# Once the bottom has passed the victim's center it is no longer pressing
		# from above. Side/rear/deeply overlapped bodies cannot take crush ticks.
		if target.self_hurtbox.global_position.y<strip.position.y: continue
		if not U.line_clear(self,point,ball.body_point(target,point)): continue
		if target not in result: result.append(target as ball)
	return result
func _land(collision:KinematicCollision2D = null) -> void:
	if slam_phase in [SlamPhase.GROUND,SlamPhase.CHAIN_WAIT]: return
	var impact_speed:float = maxf(velocity.y,0.0)
	var struck:bool = impact_speed>=minimum_impact_speed
	var repeat:bool = _drop_connected and _active_slam and can_slam()
	landing_count += 1
	_fall_track_velocity = 0.0
	_fall_track_valid = false
	_launch_horizontal_speed = 0.0
	if _active_slam and not repeat:
		if not _drop_connected: miss_count += 1
		cooldown_left = maxf(Skill_Cooling,0.0)
		chain_hits = 0
	fall_speed = 0.0
	velocity = Vector2.ZERO
	phase_elapsed = 0.0
	_active_slam = repeat
	Using_Skill = repeat
	slam_phase = SlamPhase.CHAIN_WAIT if repeat else SlamPhase.GROUND
	if repeat: cooldown_left = 0.0
	if struck:
		_landing_flash = 0.12
		_last_requested_velocity = Vector2(0,impact_speed)
		# The same normal impact visuals, but the downward landing uses its dedicated clang.
		notify_bounce_feedback(Vector2.DOWN,impact_speed,collision,true)
		if collision!=null: _try_wall_hit_burst_from_collision(collision,impact_speed)
		else: notify_wall_impact_feedback(global_position+Vector2(0,body_half_size().y),Vector2.UP,impact_speed)
		_emit_land(global_position)
	_sync_anvil()

func impact_knockback_distance(speed:float) -> float:
	if knockback_per_speed<=0.0 or maximum_knockback_distance<=0.0: return 0.0
	return clampf(maxf(speed,0.0)*knockback_per_speed,minf(12.0,maximum_knockback_distance),maximum_knockback_distance)
func _free_push_distance(target:ball,heading:Vector2,distance:float) -> float:
	var body:CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body==null or body.shape==null: return 0.0
	var rect:Rect2 = body.global_transform*body.shape.get_rect()
	var bounds:Rect2 = map_bounds_for(target.global_position)
	if bounds.size.x<=0.0 or bounds.size.y<=0.0: return 0.0
	var limit:float = distance
	if heading.x<0.0: limit = minf(limit,rect.position.x-bounds.position.x)
	elif heading.x>0.0: limit = minf(limit,bounds.end.x-rect.end.x)
	elif heading.y>0.0: limit = minf(limit,bounds.end.y-rect.end.y)
	if limit<=0.1: return 0.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.shape
	query.transform = body.global_transform
	query.motion = heading*limit
	query.margin = 0.001
	query.collision_mask = target.collision_mask | 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [target.get_rid(),get_rid()]
	var fractions:PackedFloat32Array = get_world_2d().direct_space_state.cast_motion(query)
	return maxf(limit*(fractions[0] if fractions.size()>0 else 0.0)-0.1,0.0)

func _apply_impact_knockback(target:Variant,speed:float,contact_point:Vector2 = global_position,sustained:bool = false) -> Node:
	if slam_phase!=SlamPhase.FALLING or not can_act() or not mc_enemy(target) or not target.can_receive_negative_effects(): return null
	if target not in _contacts_at(contact_point): return null
	var distance:float = impact_knockback_distance(speed)*(clampf(sustained_knockback_ratio,0.0,1.0) if sustained else 1.0)
	if distance<=0.0: return null
	var heading:Vector2 = Vector2.DOWN
	var escaping:bool = _free_push_distance(target,Vector2.DOWN,minf(distance,8.0))<minf(distance,8.0)-0.2
	if escaping:
		var left:float = _free_push_distance(target,Vector2.LEFT,distance)
		var right:float = _free_push_distance(target,Vector2.RIGHT,distance)
		if maxf(left,right)<=0.2: return null # Never push into a fully closed wall pocket.
		var state:Dictionary = _fall_hits.get(target.get_instance_id(),{})
		var preferred:float = float(state.get("escape_sign",signf(target.global_position.x-contact_point.x)))
		if is_zero_approx(preferred): preferred = -1.0 if target.get_instance_id()%2==0 else 1.0
		if (preferred<0.0 and left<=0.2) or (preferred>0.0 and right<=0.2): preferred = -preferred
		if not state.has("escape_sign") and absf(left-right)>1.0: preferred = -1.0 if left>right else 1.0
		heading = Vector2(preferred,0.0)
		distance = left if preferred<0.0 else right
		state["escape_sign"] = preferred
		if _fall_hits.has(target.get_instance_id()): _fall_hits[target.get_instance_id()]["escape_sign"] = preferred
	var effect:Node = target.apply_knockback(heading,distance,impact_knockback_speed,0.0,0.0,{
		"source":self,"lock_control":not sustained,"stop_on_character":true,"redirect_blend_time":0.0 if escaping else 0.06,
		"collision_damage":0.0,"max_wall_bounces":0,"control_recovery_time":0.0})
	if escaping and is_instance_valid(effect):
		var lease_name:String = "AnvilEscape_"+str(get_instance_id())
		var lease:Node = target.get_node_or_null(lease_name)
		if lease==null:
			lease = ESCAPE_LEASE.new()
			lease.name = lease_name
			target.add_child(lease)
			lease.setup(self,effect)
		else: lease.effect_ref = weakref(effect)
	return effect

func _damage_with_feedback(target:ball,amount:float,point:Vector2,emit_feedback:bool = true) -> bool:
	if slam_phase!=SlamPhase.FALLING or not can_act() or not mc_enemy(target) or amount<=0.0: return false
	if target not in _contacts_at(point): return false
	var before:float = maxf(target.health,0.0)
	var accepted:bool = U.damage(self,target,amount,point)
	var remaining:float = maxf(target.health,0.0) if is_instance_valid(target) else 0.0
	var actual:float = maxf(before-remaining,0.0)
	if not accepted or actual<=0.0: return false
	if not emit_feedback: return true
	last_impact_damage = actual
	var event:String = HIT_GAIN.damage_event(actual)
	var gain:float = HIT_GAIN.damage_gain(actual)
	_play_damage_sound(event,point,gain)
	if multiplayer.has_multiplayer_peer(): _play_damage_sound.rpc(event,point,gain)
	return true
@rpc("authority","call_remote","reliable")
func _play_damage_sound(event:String,point:Vector2,gain:float) -> void:
	var player:AudioStreamPlayer2D = AUDIO.play(self,event,point,gain,false,true,true,true)
	if is_instance_valid(player):
		player.set_meta("mc_damage_source",get_instance_id())
		_anvil_sounds.append(weakref(player))
func _emit_land(point:Vector2) -> void:
	if not active(): return
	obstacle_impact_count += 1
	_play_land(point)
	if multiplayer.has_multiplayer_peer(): _play_land.rpc(point)
@rpc("authority","call_remote","reliable")
func _play_land(point:Vector2) -> void:
	if not is_combat_runtime_active() or get_tree().get_nodes_in_group("MCNativeSFX").size()>=24: return
	var player := AudioStreamPlayer2D.new()
	player.stream = LAND_SOUND
	player.volume_db = 0.0
	player.max_distance = 1700.0
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("MCNativeSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sound_event","block.anvil.land")
	player.set_meta("mc_anvil_obstacle_source",get_instance_id())
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	_anvil_sounds.append(weakref(player))
	player.play()
func _process(delta:float) -> void:
	super._process(delta)
	for i:int in range(_anvil_sounds.size()-1,-1,-1):
		var player:Variant = _anvil_sounds[i].get_ref()
		if not is_instance_valid(player): _anvil_sounds.remove_at(i)
		else: player.stream_paused = not is_combat_runtime_active()

func Skill() -> void:
	if not begin_slam(): Using_Skill = _active_slam
func Attack() -> void: Attacking = false
func controlled_skill_action() -> void: Skill()
func player_control_action_ids() -> Array[StringName]:
	# Attack() is inert; slam is the only active action and therefore uses left click.
	return [&"controlled_skill_action"]
func player_control_action(index:int) -> void:
	if index==0 and is_player_controlled() and is_multiplayer_authority(): Skill()
func visual_mob() -> void:
	if not is_instance_valid(image): return
	set_character_visual_flip_h(false)
	image.rotation = 0.0
	var impact:float = clampf(_landing_flash/0.12,0.0,1.0)
	image.scale = _rest_scale*Vector2(1.0+0.06*impact,1.0-0.05*impact)
func _sync_anvil() -> void:
	if multiplayer.has_multiplayer_peer(): _new5_visual.rpc(network_visual_state())
func visual_state() -> Dictionary:
	if is_multiplayer_authority(): _refresh_fall_tracking()
	return {"time":clock,"phase":int(slam_phase),"phase_time":phase_elapsed,"fall_speed":fall_speed,"chain":chain_hits,"combo_slams":combo_slams,"cooldown":cooldown_left,"active":_active_slam,"flash":_landing_flash,"connected":_drop_connected,
		"jump_from":_jump_from,"jump_to":_jump_to,"jump_height":_jump_arc_height,"jump_time":_jump_total_time,"jump_bounds":_drop_bounds,"slam_position":global_position,"fall_track_point":_fall_track_point,"fall_track_valid":_fall_track_valid,"fall_track_speed":fall_track_speed,"tracking_speed_scale":tracking_speed_scale,"fall_track_deadzone":fall_track_deadzone,"track_velocity":_fall_track_velocity,"launch_horizontal_speed":_launch_horizontal_speed,"track_acceleration":fall_track_acceleration}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	slam_phase = clampi(int(data.get("phase",0)),0,SlamPhase.GROUND) as SlamPhase
	phase_elapsed = maxf(float(data.get("phase_time",0.0)),0.0)
	fall_speed = maxf(float(data.get("fall_speed",0.0)),0.0)
	chain_hits = maxi(int(data.get("chain",0)),0)
	combo_slams = maxi(int(data.get("combo_slams",0)),0)
	cooldown_left = maxf(float(data.get("cooldown",0.0)),0.0)
	_active_slam = bool(data.get("active",false))
	_drop_connected = bool(data.get("connected",false))
	_landing_flash = maxf(float(data.get("flash",0.0)),0.0)
	_jump_from = data.get("jump_from",global_position)
	_jump_to = data.get("jump_to",global_position)
	_jump_arc_height = maxf(float(data.get("jump_height",jump_clearance)),0.0)
	_jump_total_time = maxf(float(data.get("jump_time",jump_duration)),0.05)
	_drop_bounds = data.get("jump_bounds",map_bounds_for(global_position))
	_fall_track_point = data.get("fall_track_point",global_position)
	_fall_track_valid = bool(data.get("fall_track_valid",false))
	fall_track_speed = maxf(float(data.get("fall_track_speed",fall_track_speed)),0.0)
	tracking_speed_scale = clampf(float(data.get("tracking_speed_scale",tracking_speed_scale)),0.0,1.0)
	fall_track_deadzone = maxf(float(data.get("fall_track_deadzone",fall_track_deadzone)),0.0)
	_fall_track_velocity = float(data.get("track_velocity",0.0))
	_launch_horizontal_speed = float(data.get("launch_horizontal_speed",0.0))
	fall_track_acceleration = maxf(float(data.get("track_acceleration",fall_track_acceleration)),0.0)
	# A blocked arc ends at its authoritative contact point, not its old endpoint.
	global_position = data.get("slam_position",global_position)
	velocity = Vector2(_fall_track_velocity,jump_velocity(phase_elapsed/_jump_total_time).y if slam_phase==SlamPhase.RISING else fall_speed)
func client_visual_step(delta:float) -> void:
	if health<=0 or not is_combat_runtime_active(): return
	var dt:float = maxf(delta,0.0)
	_landing_flash = maxf(_landing_flash-dt,0.0)
	var remaining:float = dt
	for _guard:int in range(2048):
		if remaining<=0.000001: break
		var step:float = minf(remaining,1.0/120.0)
		remaining -= step
		if slam_phase==SlamPhase.RISING:
			var travel_dt:float = minf(step,maxf(_jump_total_time-phase_elapsed,0.0))
			_jump_step(travel_dt,false)
			if slam_phase==SlamPhase.FALLING and step-travel_dt>0.000001:
				_client_drop_step(step-travel_dt)
		elif slam_phase==SlamPhase.HOVER:
			_begin_drop(false)
			_client_drop_step(step)
		elif slam_phase==SlamPhase.FALLING and _active_slam:
			_client_drop_step(step)
		else: break

func _client_drop_step(dt:float) -> void:
	# Continue visual gravity between snapshots instead of freezing at release.
	# This path never applies damage, sound, chain logic, or outgoing RPCs.
	var bounds:Rect2 = map_bounds_for(global_position)
	if bounds.size.y<=body_half_size().y*2.0: return
	var v0:float = fall_speed
	fall_speed = minf(fall_speed+gravity_acceleration*dt,terminal_speed)
	var horizontal:float = _fall_tracking_velocity(dt)
	velocity = Vector2(_fall_track_velocity,fall_speed)
	var wanted_x:float = global_position.x+horizontal*dt
	var clipped_x:float = clampf(wanted_x,bounds.position.x+body_half_size().x,bounds.end.x-body_half_size().x)
	var floor_y:float = bounds.end.y-body_half_size().y
	var distance:float = (v0+fall_speed)*0.5*dt
	var at_bottom:bool = global_position.y+distance>=floor_y
	if at_bottom: distance = maxf(floor_y-global_position.y,0.0)
	var sweep:Dictionary = _sweep_drop_motion(Vector2(clipped_x-global_position.x,distance))
	var collision:KinematicCollision2D = sweep.collision
	if not is_equal_approx(wanted_x,clipped_x) and absf(global_position.x-clipped_x)<0.01:
		velocity.x = 0.0
		_fall_track_velocity = 0.0
	if (at_bottom and global_position.y>=floor_y-0.1) or (collision!=null and collision.get_normal().y<-0.1):
		fall_speed = 0.0
		velocity = Vector2.ZERO
		_fall_track_velocity = 0.0
		_fall_track_valid = false
		slam_phase = SlamPhase.GROUND # Wait for the authority to confirm landing/repeat.
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_ANVIL")

@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	ITEM_DEATH.spawn(self)
func Die() -> void:
	_set_jump_character_collision_ignored(false)
	_fall_track_velocity = 0.0
	_launch_horizontal_speed = 0.0
	_fall_track_valid = false
	_drop_connected = false
	_active_slam = false
	Using_Skill = false
	fall_speed = 0.0
	velocity = Vector2.ZERO
	super.Die()
func _exit_tree() -> void:
	_set_jump_character_collision_ignored(false)
	for ref:WeakRef in _anvil_sounds:
		var player:Variant = ref.get_ref()
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	super._exit_tree()
