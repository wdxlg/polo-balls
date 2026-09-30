extends "res://scripts/characters/我的世界/new5/base.gd"
## One active move: two real stone-sword sweeps. Shared hurt-shape geometry,
## classified damage, status potency/source lifetimes, audio and death effects.
## One continuous original-model pose: raise, downward cut, upward cut, recover.
## Attack aiming never steers locomotion; the shared movement/collision chain owns it.
## Ranged head bolt (2026-09-28): while the nearest enemy is OUTSIDE melee range (the sword
## acquisition radius), a medium cooldown ticks; when ready the head fires a slightly homing
## bolt made of the Wither-skull trail smoke particles (same trail). 5 damage + stacking Wither.
## The cooldown is frozen whenever the enemy is inside melee range (or there is no enemy).
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const BOLT = preload("res://scripts/characters/我的世界/wither_skeleton/wither_bolt.gd")
# Vanilla Wither shoot (entity.wither.shoot, Java 1.21.11 OGG already verified in wither/SOURCE_MANIFEST.json).
const BOLT_SHOOT_SOUND:AudioStream = preload("res://audio/characters/我的世界/wither/shoot.ogg")
const BOLT_SHOOT_GAIN_DB:float = -6.0 # Smaller mob than the Wither boss.
const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/wither_skeleton/frames.tres")
const ATTACK_PARTS:SpriteFrames = preload("res://Images/characters/我的世界/wither_skeleton/attack_parts.tres")
const POSES = preload("res://Images/characters/我的世界/wither_skeleton/poses.gd")
const STONE:Texture2D = preload("res://Images/characters/我的世界/wither_skeleton/stone_sword.png")
const VOICE = preload("res://scripts/effects/我的世界/mc_creature_voice.gd")
const SOUNDS = preload("res://scripts/characters/我的世界/wither_skeleton/sounds.gd")
const GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const COPY_SCALE = preload("res://scripts/characters/我的世界/haochen/copy_body_scale.gd")
const WITHER_SECONDS:float = 3.0
const MAX_WITHER_LEVEL:int = 255 # Existing public potency limit, not a new balance cap.
const WINDOWS:Array[Vector2] = [Vector2(0.15,0.31),Vector2(0.41,0.57)]
const COMBO_DURATION:float = 0.74
const BAKED_CLIP_END:float = 0.98 # Original projection timestamps; do not retime either damaging slash.
const RECOVER_END:float = 1.18 # 0.44s visual recovery, still inside the existing 1.2s attack interval.
const ATTACK_MOVE_MULTIPLIER:float = 0.3
const SIZE_SCALE:float = 0.9 # 2026-09-28: whole character (body, colliders, sword, reach, melee range) x0.9.
const ATTACK_HAND_REACH:float = 5.0*SIZE_SCALE # Extra world-space reach, shared by the arm, grip and actual sword sweep.
const BODY_ENLARGEMENT:float = 20.0/14.0 # Match the previous sword enlargement ONCE (historical ratio).
const BODY_SCALE:float = 0.85*BODY_ENLARGEMENT*SIZE_SCALE # Scene body, shoulder/hand anchors and colliders share this ratio.
const BODY_OFFSET_Y:float = -13.5*BODY_ENLARGEMENT*SIZE_SCALE # Feet pixel 202 lands on the collider bottom (+81).
const BASE_ATTACK_DAMAGE:float = 20.0 # Scene Damage; bolt damage scales with live Damage buffs.
const BOLT_DAMAGE:float = 5.0
const BOLT_COOLDOWN:float = 3.0 # Medium; only counts down while the enemy is outside melee range.
const BOLT_SPEED:float = 120.0 # Cruise speed after the arc.
const BOLT_LAUNCH_SPEED:float = 100.0 # Initial pop backward-and-up.
const BOLT_LAUNCH_ANGLE:float = deg_to_rad(40.0) # Off straight-back, toward the screen-up side.
const BOLT_PULL:float = 240.0 # Constant pull along the aim: the path is a parabola until cruise.
const BOLT_TURN_RATE:float = 1.4 # rad/s: slight homing, easy to sidestep at range.
const BOLT_LIFE:float = 4.0
const BOLT_MUZZLE_PIXEL:Vector2 = Vector2(80.0,86.0) # Face centre in the 160x224 original frame.
const BOLT_AIM_ASSIST:float = 160.0 # Manual: home on the enemy nearest the cursor within this radius.
@export var blade_length:float = 20.0*SIZE_SCALE
@export var blade_radius:float = 2.5*SIZE_SCALE
@export var acquisition_range:float = 58.0*SIZE_SCALE
var combo_time:float = -1.0
var combo_heading:Vector2 = Vector2.RIGHT
var cooldown_left:float = 0.0
var swings_started:int = 0
var hits_landed:int = 0
var _hit_sets:Array[Dictionary] = [{},{}]
var _sounded:Array[bool] = [false,false]
var _damage_regions:Array[Dictionary] = []
var _revision:int = 0
var _accepted_revision:int = -1
var _accepted_clock:float = -1.0
var _wither_serial:int = 0
var _received_wither:int = 0
var _status_targets:Dictionary = {}
var _body_clip:StringName = &"idle"
var _body_frame:int = 0
var _prev_clip:StringName = &""
var _fade_t:float = 1.0
var _fade_sprite:Sprite2D
var _last_position:Vector2
var _walking:bool = false
var _render_process:bool = false
var _recovery_draw_time:float = -1.0
var _recovery_draw_revision:int = -1
var _arm:Sprite2D
var _sword:Sprite2D
var _body_copy_scale:float = 1.0
var voice:Node
var bolt_cooldown_left:float = BOLT_COOLDOWN
var bolts_fired:int = 0
var bolt_hits:int = 0
var _bolt_serial:int = 0
var _visual_bolts:Dictionary = {}

func _ready() -> void:
	Can_Attack = true
	Can_Skill = false
	set_meta("mc_hook_hurt_only",true)
	super._ready()
	# The top_level sword and its world-space reach are part of the body: a shrunken
	# copy holds a proportionally smaller sword (visual, damage segment, acquisition).
	_body_copy_scale = COPY_SCALE.of(self)
	if not is_equal_approx(_body_copy_scale,1.0):
		blade_length *= _body_copy_scale
		blade_radius *= _body_copy_scale
		acquisition_range *= _body_copy_scale
	_last_position = global_position
	add_to_group("MinecraftWitherSkeleton")
	voice = VOICE.new()
	voice.name = "NativeVoice"
	voice.unit = self
	voice.events = SOUNDS.EVENTS.duplicate()
	voice.events["swing"] = AUDIO.EVENTS["entity.player.attack.sweep"]
	voice.events["hit"] = AUDIO.EVENTS["entity.player.hurt"]
	voice.events["crit"] = AUDIO.EVENTS["entity.player.attack.crit"]
	voice.events["shoot"] = [{"stream":BOLT_SHOOT_SOUND,"pitch":0.9},{"stream":BOLT_SHOOT_SOUND,"pitch":1.0},{"stream":BOLT_SHOOT_SOUND,"pitch":1.1}]
	add_child(voice)
	_sword = Sprite2D.new()
	_sword.name = "StoneSword"
	_sword.texture = STONE
	_sword.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sword.offset = Vector2(4.5,-4.5) # Original 16px sword: grip (3.5,12.5), tip (14,2).
	_sword.z_index = 3
	add_child(_sword)
	_sword.top_level = true
	_arm = Sprite2D.new()
	_arm.name = "AimedSwordArm"
	_arm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_arm.z_index = 2
	add_child(_arm)
	_arm.top_level = true
	_arm.hide()
	_fade_sprite = Sprite2D.new()
	_fade_sprite.name = "BodyFade"
	_fade_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fade_sprite.visible = false
	image.add_child(_fade_sprite)
	visual_mob()

func player_control_action_ids() -> Array[StringName]: return [&"controlled_attack_action",&"controlled_skill_action"]
func controlled_attack_action() -> void:
	if is_player_controlled(): begin_combo(player_control_aim_direction(direction))
func controlled_skill_action() -> void:
	# Manual bolt keeps the same rule: ready cooldown and no enemy inside melee range.
	if not is_player_controlled() or not can_act() or not is_combat_runtime_active() or bolt_cooldown_left > 0.0: return
	if not enemy_outside_melee(U.nearest(self)): return
	var aim_point:Vector2 = player_control_aim_world_position() if has_player_control_aim() else global_position+player_control_aim_direction(direction)*100.0
	var homing:ball = null
	var best:float = BOLT_AIM_ASSIST*BOLT_AIM_ASSIST
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and node.health > 0 and U.enemy(self,node) and node.is_combat_lockable():
			var d:float = ball.body_point((node as Node2D),aim_point).distance_squared_to(aim_point)
			if d < best:
				best = d
				homing = node
	fire_bolt(aim_point-bolt_muzzle_position(),homing)
func Attack() -> void:
	if is_player_controlled(): controlled_attack_action()
	else: _try_start_ai_combo()

func begin_combo(heading:Vector2) -> bool:
	if not can_act() or not is_combat_runtime_active() or combo_time >= 0.0 or cooldown_left > 0.0 or heading.is_zero_approx(): return false
	combo_heading = heading.normalized()
	combo_time = 0.0
	cooldown_left = maxf(Attack_Cooling,RECOVER_END)
	_hit_sets = [{},{}]
	_sounded = [false,false]
	Attacking = true
	_face_right = _geometry_face_right(combo_heading)
	_revision += 1
	_publish_pose()
	return true

func step_mob(delta:float) -> void:
	_damage_regions.clear()
	if not is_combat_runtime_active(): return
	cooldown_left = maxf(0.0,cooldown_left-delta)
	if not can_act():
		cancel_combo()
		return
	_tick_bolt(delta)
	if combo_time >= 0.0:
		advance_combo(delta)
		return
	if is_player_controlled(): return
	_try_start_ai_combo()

func _try_start_ai_combo() -> void:
	if is_player_controlled() or not can_act() or combo_time >= 0.0 or cooldown_left > 0.0: return
	var target:ball = U.nearest(self)
	if can_reach_target(target): begin_combo(global_position.direction_to(target_point(target)))

func can_reach_target(target:ball) -> bool:
	# Discovery radius is NOT a damage radius. Preview only the actual two sword
	# windows against current hurt shapes and walls, via the shared contact service.
	# Optional aim is pure geometry: no turn, cooldown, audio, RNG, damage or RPC.
	if not is_instance_valid(target) or target.health <= 0 or not U.enemy(self,target): return false
	var point:Vector2 = target_point(target)
	if global_position.distance_squared_to(point) > acquisition_range*acquisition_range: return false
	var aim:Vector2 = global_position.direction_to(point)
	if aim.is_zero_approx() or not U.line_clear(self,global_position,point): return false
	var area:Area2D = target.self_hurtbox
	if area == null: return false
	var bounds:Rect2
	var has_shape:bool = false
	for child:Node in area.get_children():
		if child is CollisionShape2D and not child.disabled and child.shape != null:
			var world_bounds:Rect2 = child.global_transform*child.shape.get_rect()
			bounds = bounds.merge(world_bounds) if has_shape else world_bounds
			has_shape = true
	if not has_shape: return false
	for window:Vector2 in WINDOWS:
		for sample:int in range(25):
			var geometry:Dictionary = blade_segment(lerpf(window.x,window.y,float(sample)/24.0),aim)
			# Conservative broad phase only; shared exact shapes/walls still decide.
			# Out-of-reach enemies do not trigger 50 full candidate/physics queries.
			var blade_bounds:Rect2 = Rect2(geometry.start,Vector2.ZERO).expand(geometry.end).grow(blade_radius)
			if not blade_bounds.intersects(bounds,true): continue
			for contact:Dictionary in SWEEP.contacts(self,geometry.start,geometry.end,blade_radius,{},global_position):
				if contact.target == target: return true
	return false

## Melee range = the sword acquisition radius (the same radius that gates both slashes).
func enemy_outside_melee(target:ball) -> bool:
	if not is_instance_valid(target) or target.health <= 0 or not U.enemy(self,target): return false
	return global_position.distance_squared_to(target_point(target)) > acquisition_range*acquisition_range

## Aim / range point: tall multi-part bodies (grown cactus) offer their part nearest to us.
func target_point(target:ball) -> Vector2:
	if target.has_method(&"combat_distance_point_for"): return target.call(&"combat_distance_point_for",self)
	return ball.body_point(target,global_position)

func _tick_bolt(delta:float) -> void:
	var target:ball = U.nearest(self)
	if not enemy_outside_melee(target): return # Frozen: enemy in melee range (or none).
	bolt_cooldown_left = maxf(0.0,bolt_cooldown_left-delta)
	if bolt_cooldown_left > 0.0 or is_player_controlled() or combo_time >= 0.0: return
	var muzzle:Vector2 = bolt_muzzle_position()
	var point:Vector2 = target_point(target)
	if not U.line_clear(self,muzzle,point): return # Hold a ready shot until the line opens.
	fire_bolt(point-muzzle,target)

func bolt_muzzle_position() -> Vector2:
	var pixel:Vector2 = BOLT_MUZZLE_PIXEL-Vector2(80.0,112.0)+image.offset
	if _face_right: pixel.x = -pixel.x
	return image.global_transform*pixel

func bolt_damage() -> float: return attack_damage(BOLT_DAMAGE/BASE_ATTACK_DAMAGE)
func is_bolt_enemy(target:Variant) -> bool: return target is ball and U.enemy(self,target)

func fire_bolt(aim:Vector2,homing:ball) -> Node2D:
	if not can_act() or aim.is_zero_approx(): return null
	bolt_cooldown_left = BOLT_COOLDOWN
	bolts_fired += 1
	_bolt_serial += 1
	var origin:Vector2 = bolt_muzzle_position()
	var bolt:Node2D = _spawn_bolt(_bolt_serial,origin,aim.normalized(),homing,false)
	voice.request("shoot",origin,BOLT_SHOOT_GAIN_DB)
	if multiplayer.has_multiplayer_peer():
		var path:NodePath = get_tree().current_scene.get_path_to(homing) if is_instance_valid(homing) else NodePath()
		_spawn_bolt_visual.rpc(_bolt_serial,origin,aim.normalized(),path)
	return bolt

func _spawn_bolt(id:int,origin:Vector2,heading:Vector2,homing:Node,only_visual:bool) -> Node2D:
	var bolt:Node2D = BOLT.new()
	bolt.name = "WitherSkeletonBolt_%d" % id
	bolt.call("configure",self,heading,homing,BOLT_SPEED,BOLT_TURN_RATE,BOLT_LIFE,id,only_visual,BOLT_LAUNCH_SPEED,BOLT_LAUNCH_ANGLE,BOLT_PULL)
	get_tree().current_scene.add_child(bolt,true)
	bolt.global_position = origin
	return bolt

@rpc("authority","call_remote","reliable")
func _spawn_bolt_visual(id:int,origin:Vector2,heading:Vector2,path:NodePath) -> void:
	var homing:Node = get_tree().current_scene.get_node_or_null(path) if not path.is_empty() else null
	_visual_bolts[id] = weakref(_spawn_bolt(id,origin,heading,homing,true))

func _finish_bolt(bolt:Node2D,point:Vector2,_hit:bool) -> void:
	if multiplayer.has_multiplayer_peer() and is_instance_valid(bolt): _end_bolt_visual.rpc(int(bolt.get("serial")),point)

@rpc("authority","call_remote","reliable")
func _end_bolt_visual(id:int,point:Vector2) -> void:
	var ref:WeakRef = _visual_bolts.get(id)
	_visual_bolts.erase(id)
	var bolt:Node2D = ref.get_ref() as Node2D if ref != null else null
	if is_instance_valid(bolt):
		bolt.global_position = point
		bolt.call("dissipate",point)

func deal_bolt_hit(target:ball,point:Vector2) -> bool:
	if not active() or is_damage_output_disabled() or not U.enemy(self,target) or target.health <= 0: return false
	var amount:float = bolt_damage()
	var before:float = maxf(float(target.health),0.0)
	set_meta("blood_damage_kind","pierce")
	var accepted:bool = target.receive_classified_positional_damage(amount,point,&"ordinary",false,self)
	set_meta("blood_damage_kind","slash")
	var actual:float = maxf(before-(maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0),0.0)
	if not accepted or actual <= 0.0: return false
	bolt_hits += 1
	voice.request("crit" if actual > 50.0 else "hit",point,GAIN.damage_gain(actual))
	if is_instance_valid(target) and target.health > 0: apply_stacking_wither(target)
	return true

func advance_combo(delta:float) -> void:
	_damage_regions.clear()
	if combo_time < 0.0 or not is_combat_runtime_active(): return
	if not can_act():
		cancel_combo()
		return
	var previous:float = combo_time
	var next:float = minf(combo_time+maxf(delta,0.0),RECOVER_END)
	# Interval intersection means even a long frame crosses each slash exactly once.
	for slash:int in range(2):
		var window:Vector2 = WINDOWS[slash]
		if next < window.x or previous > window.y: continue
		if not _sounded[slash]:
			_sounded[slash] = true
			swings_started += 1
			voice.request("swing",global_position,0.0)
		var a:float = clampf((previous-window.x)/(window.y-window.x),0.0,1.0)
		var b:float = clampf((next-window.x)/(window.y-window.x),0.0,1.0)
		var steps:int = maxi(1,ceili((b-a)*24.0))
		for i:int in range(steps+1):
			var progress:float = lerpf(a,b,float(i)/float(steps))
			var sample:float = lerpf(window.x,window.y,progress)
			var geometry:Dictionary = blade_segment(sample)
			_damage_regions.append(geometry)
			for contact:Dictionary in SWEEP.contacts(self,geometry.start,geometry.end,blade_radius,_hit_sets[slash],global_position):
				var target:ball = contact.target
				_hit_sets[slash][target.get_instance_id()] = true
				deal_sword_hit(target,contact.point)
	combo_time = next
	if combo_time >= RECOVER_END: cancel_combo()

func deal_sword_hit(target:ball,point:Vector2) -> bool:
	if not can_act() or not U.enemy(self,target) or target.health <= 0: return false
	var amount:float = attack_damage(1.0)
	var before:float = maxf(float(target.health),0.0)
	set_meta("blood_damage_kind","slash")
	var accepted:bool = target.receive_classified_positional_damage(amount,point,&"ordinary",false,self)
	var actual:float = maxf(before-(maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0),0.0)
	if not accepted or actual <= 0.0: return false
	hits_landed += 1
	voice.request("crit" if actual > 50.0 else "hit",point,GAIN.damage_gain(actual))
	if is_instance_valid(target) and target.health > 0: apply_stacking_wither(target)
	return true

func apply_stacking_wither(target:ball) -> bool:
	if not can_act() or not U.enemy(self,target): return false
	var level:int = mini(EFFECTS.level_of(target,"wither")+1,MAX_WITHER_LEVEL)
	if not EFFECTS.apply_effect(target,"wither",level,WITHER_SECONDS,self): return false
	_status_targets[target.get_instance_id()] = weakref(target)
	_wither_serial += 1
	if multiplayer.has_multiplayer_peer(): _receive_wither.rpc(_wither_serial,get_tree().current_scene.get_path_to(target),level,WITHER_SECONDS)
	return true

@rpc("authority","call_remote","reliable")
func _receive_wither(serial:int,path:NodePath,level:int,remaining:float) -> void:
	if serial <= _received_wither: return
	_received_wither = serial
	var target:ball = get_tree().current_scene.get_node_or_null(path) as ball
	if is_instance_valid(target): EFFECTS.apply_effect(target,"wither",clampi(level,1,MAX_WITHER_LEVEL),clampf(remaining,0.0,WITHER_SECONDS),self)

func cancel_combo() -> void:
	_damage_regions.clear()
	if combo_time < 0.0: return
	combo_time = -1.0
	Attacking = false
	_revision += 1
	_publish_pose()

func move(speed:float,delta:float) -> void:
	# Slow self-propulsion only; shared WASD, wall bounce, pull and Repel stay intact.
	super.move(speed*(ATTACK_MOVE_MULTIPLIER if combo_time >= 0.0 else 1.0),delta)

func tick_physics(state:State,delta:float) -> void:
	if health <= 0 or dizziness or is_damage_output_disabled() or not Can_Attack: cancel_combo()
	_walking = global_position.distance_squared_to(_last_position) > 0.0009
	_last_position = global_position
	if _fade_t < 1.0:
		_fade_t = minf(1.0,_fade_t+delta/0.12)
		if is_instance_valid(_fade_sprite):
			_fade_sprite.modulate.a = 1.0-_fade_t*_fade_t
			_fade_sprite.visible = _fade_t < 1.0
	super.tick_physics(state,delta)

func _process(delta:float) -> void:
	_render_process = true
	super._process(delta)
	_render_process = false

func _draw_combo_time(subframe:float = -1.0) -> float:
	# Only the harmless recovery may advance between physics ticks. Damage clocks,
	# contacts, RPC snapshots and pause state are never changed by this render clock.
	if not _render_process: return combo_time
	if combo_time < COMBO_DURATION or combo_time >= RECOVER_END:
		_recovery_draw_time = -1.0
		return combo_time
	var revision:int = _revision if is_multiplayer_authority() else _accepted_revision
	if revision != _recovery_draw_revision or _recovery_draw_time < 0.0:
		_recovery_draw_revision = revision
		_recovery_draw_time = combo_time
	if is_combat_runtime_active():
		var candidate:float = combo_time
		if is_multiplayer_authority():
			var fraction:float = Engine.get_physics_interpolation_fraction() if subframe < 0.0 else clampf(subframe,0.0,1.0)
			candidate += fraction*get_physics_process_delta_time()
		_recovery_draw_time = maxf(_recovery_draw_time,candidate)
	return minf(_recovery_draw_time,RECOVER_END-0.00001)

func body_pose(time:float) -> Dictionary:
	if time >= 0.0 and time < RECOVER_END:
		return {"clip":&"attack","index":_attack_index(time)}
	var clip:StringName = &"walk" if _walking else &"idle"
	return {"clip":clip,"index":int(_view_clock*FRAMES.get_animation_speed(clip))%FRAMES.get_frame_count(clip)}

func _geometry_aim(aim:Vector2) -> Vector2:
	return combo_heading if aim.is_zero_approx() else aim.normalized()

func _geometry_face_right(aim:Vector2) -> bool:
	# Canonical vertical facing: tiny trig/position-rounding X must not mirror
	# a preview differently from the real direction_to() attack.
	return _face_right if aim.is_zero_approx() else aim.x >= -0.00001

func _hand_pixel(xy:Array,aim:Vector2 = Vector2.ZERO) -> Vector2:
	var pixel:Vector2 = Vector2(float(xy[0])-80.0,float(xy[1])-112.0)+image.offset
	if _geometry_face_right(aim): pixel.x = -pixel.x # Original orthographic model faces left.
	return image.global_transform * pixel

func _attack_frame_position(time:float) -> float:
	var source_time:float = time
	if time >= COMBO_DURATION:
		source_time = lerpf(COMBO_DURATION,BAKED_CLIP_END,_recovery_progress((time-COMBO_DURATION)/(RECOVER_END-COMBO_DURATION)))
	return clampf(source_time/BAKED_CLIP_END*float(FRAMES.get_frame_count(&"attack")-1),0.0,float(FRAMES.get_frame_count(&"attack")-1))

func _attack_index(time:float) -> int:
	return roundi(_attack_frame_position(time))

func _arm_source_index(time:float) -> int:
	# One original limb texture during the spin; continuous transforms replace
	# discrete texture/hand-anchor swaps that used to make the wrist chatter.
	return _attack_index(COMBO_DURATION) if time >= COMBO_DURATION else _attack_index(time)

func _posed_hand(time:float,aim:Vector2 = Vector2.ZERO) -> Vector2:
	if time < COMBO_DURATION: return _hand_pixel(POSES.HANDS["attack"][_attack_index(time)],aim)
	var frame:float = _attack_frame_position(time)
	var first:int = floori(frame)
	var second:int = mini(first+1,FRAMES.get_frame_count(&"attack")-1)
	return _hand_pixel(POSES.HANDS["attack"][first],aim).lerp(_hand_pixel(POSES.HANDS["attack"][second],aim),frame-float(first))

func shoulder_position(time:float,aim:Vector2 = Vector2.ZERO) -> Vector2:
	return _hand_pixel(POSES.SHOULDERS[_attack_index(time)],aim)

func arm_aim_rotation(time:float,aim:Vector2 = Vector2.ZERO) -> float:
	if time < 0.0: return 0.0
	var turn:float = wrapf(_geometry_aim(aim).angle()-(0.0 if _geometry_face_right(aim) else PI),-PI,PI)
	# Enter and leave from the held pose, with no disconnected wrist/shoulder jump.
	if time < WINDOWS[0].x: return turn*_ss(time/WINDOWS[0].x)
	if time >= COMBO_DURATION: return turn*(1.0-_recovery_progress((time-COMBO_DURATION)/(RECOVER_END-COMBO_DURATION)))
	return turn

func attack_hand_extension(time:float) -> float:
	if time < 0.0 or time >= RECOVER_END: return 0.0
	if time < WINDOWS[0].x: return ATTACK_HAND_REACH*_body_copy_scale*_ss(time/WINDOWS[0].x)
	if time >= COMBO_DURATION: return ATTACK_HAND_REACH*_body_copy_scale*(1.0-_recovery_progress((time-COMBO_DURATION)/(RECOVER_END-COMBO_DURATION)))
	return ATTACK_HAND_REACH*_body_copy_scale

func _attack_hand(time:float,aim:Vector2 = Vector2.ZERO) -> Vector2:
	var shoulder:Vector2 = shoulder_position(time,aim)
	var posed:Vector2 = (_posed_hand(time,aim)-shoulder).rotated(arm_aim_rotation(time,aim))
	var hand:Vector2 = shoulder+posed+_geometry_aim(aim)*attack_hand_extension(time)
	if time >= COMBO_DURATION:
		var progress:float = (time-COMBO_DURATION)/(RECOVER_END-COMBO_DURATION)
		hand = hand.lerp(_rest_hand(aim),_ss((progress-0.85)/0.15))
	return hand

func attack_arm_transform(time:float) -> Transform2D:
	# Keep the real shoulder fixed and preserve limb thickness. Stretch only along
	# the posed limb axis so the extended hand, not a detached sword, gains reach.
	var shoulder:Vector2 = shoulder_position(time)
	var raw:Vector2 = _hand_pixel(POSES.HANDS["attack"][_arm_source_index(time)])-shoulder
	var extended:Vector2 = _attack_hand(time)-shoulder
	var transform:Transform2D = image.global_transform
	transform.origin = shoulder
	if _face_right: transform.x = -transform.x
	if raw.length_squared() < 0.000001 or extended.length_squared() < 0.000001: return transform
	var source_basis:Transform2D = Transform2D(raw.normalized(),raw.normalized().orthogonal(),Vector2.ZERO)
	var reach_basis:Transform2D = Transform2D(extended/raw.length(),extended.normalized().orthogonal(),Vector2.ZERO)
	var deformation:Transform2D = reach_basis*source_basis.affine_inverse()
	transform.x = deformation.basis_xform(transform.x)
	transform.y = deformation.basis_xform(transform.y)
	return transform

func _rest_hand(aim:Vector2 = Vector2.ZERO) -> Vector2:
	var clip:StringName = &"walk" if _walking else &"idle"
	var index:int = int(_view_clock*FRAMES.get_animation_speed(clip))%FRAMES.get_frame_count(clip)
	return _hand_pixel(POSES.HANDS[str(clip)][index],aim)

func hand_position(time:float,aim:Vector2 = Vector2.ZERO) -> Vector2:
	# The same shoulder-anchored arm extension supplies the visible and damage grip.
	# Query previews and real contacts use the same extended hand and longer blade.
	return _rest_hand(aim) if time < 0.0 else _attack_hand(time,aim)

func _ss(t:float) -> float:
	t = clampf(t,0.0,1.0)
	return t*t*(3.0-2.0*t)

func _recovery_progress(t:float) -> float:
	t = clampf(t,0.0,1.0)
	return sin(t*PI*0.5) # Positive, decreasing speed; zero velocity at the resting end.

func rest_angle(aim:Vector2 = Vector2.ZERO) -> float:
	# Rest the 20-unit sword diagonally: 45deg up-forward from each hand, not straight vertical.
	return -PI*0.25 if _geometry_face_right(aim) else -PI*0.75

func blade_angle(time:float,aim:Vector2 = Vector2.ZERO) -> float:
	if time < 0.0: return rest_angle(aim)
	var base:float = _geometry_aim(aim).angle()
	# Mirror the arc on the left: first cut must travel down, not reverse into an upcut.
	var side:float = 1.0 if _geometry_face_right(aim) else -1.0
	if time >= COMBO_DURATION:
		var start:float = base+side*deg_to_rad(-125.0)
		# Unwrapped angle: continue the upward cut for one FULL turn, then align
		# to the resting grip in the SAME direction. lerp_angle would erase the turn.
		var travel:float = TAU+fposmod((start-rest_angle(aim))*side,TAU)
		return start-side*travel*_recovery_progress((time-COMBO_DURATION)/(RECOVER_END-COMBO_DURATION))
	var degrees:float
	if time < WINDOWS[0].x:
		var start_rel:float = rad_to_deg(wrapf(rest_angle(aim)-base,-PI,PI))/side
		degrees = lerpf(start_rel,-110.0,_ss(time/WINDOWS[0].x))
	elif time <= WINDOWS[0].y:
		degrees = lerpf(-110.0,80.0,_ss((time-WINDOWS[0].x)/(WINDOWS[0].y-WINDOWS[0].x)))
	elif time < WINDOWS[1].x:
		degrees = lerpf(80.0,90.0,_ss((time-WINDOWS[0].y)/(WINDOWS[1].x-WINDOWS[0].y)))
	elif time <= WINDOWS[1].y:
		degrees = lerpf(90.0,-110.0,_ss((time-WINDOWS[1].x)/(WINDOWS[1].y-WINDOWS[1].x)))
	else:
		degrees = lerpf(-110.0,-125.0,_ss((time-WINDOWS[1].y)/(COMBO_DURATION-WINDOWS[1].y)))
	return base+side*deg_to_rad(degrees)

func blade_segment(time:float,aim:Vector2 = Vector2.ZERO) -> Dictionary:
	var grip:Vector2 = hand_position(time,aim)
	var heading:Vector2 = Vector2.RIGHT.rotated(blade_angle(time,aim))
	return {"shape":"segment","start":grip+heading*4.0,"end":grip+heading*blade_length,"radius":blade_radius,"damage":attack_damage(1.0),"source":self,"kind":"wither_skeleton_sword"}

func visual_mob() -> void:
	if not is_instance_valid(_sword) or health <= 0: return
	if combo_time < 0.0 and absf(direction.x) > 0.01: _face_right = direction.x > 0.0
	set_character_visual_flip_h(_face_right)
	var draw_time:float = _draw_combo_time()
	var pose:Dictionary = body_pose(draw_time)
	if _prev_clip == &"attack" and pose.clip != &"attack" and is_instance_valid(_fade_sprite):
		# Cross-fade the last attack frame out so the body never pops back to idle.
		_fade_sprite.texture = FRAMES.get_frame_texture(&"attack",FRAMES.get_frame_count(&"attack")-1)
		_fade_sprite.modulate.a = 1.0
		_fade_sprite.visible = true
		_fade_t = 0.0
	_prev_clip = pose.clip
	_body_clip = pose.clip
	_body_frame = pose.index
	image.texture = ATTACK_PARTS.get_frame_texture(&"body",_body_frame) if _body_clip == &"attack" else FRAMES.get_frame_texture(_body_clip,_body_frame)
	_arm.visible = _body_clip == &"attack"
	if _arm.visible:
		var arm_index:int = _arm_source_index(draw_time)
		var shoulder:Array = POSES.SHOULDERS[arm_index]
		_arm.texture = ATTACK_PARTS.get_frame_texture(&"arm",arm_index)
		_arm.offset = Vector2(80.0-float(shoulder[0]),112.0-float(shoulder[1]))
		_arm.global_transform = attack_arm_transform(draw_time)
		_arm.modulate = image.modulate
	if is_instance_valid(_fade_sprite) and image is Sprite2D: _fade_sprite.flip_h = (image as Sprite2D).flip_h
	_sword.global_position = hand_position(draw_time)
	_sword.global_rotation = blade_angle(draw_time)+PI/4.0
	_sword.global_scale = Vector2.ONE*(blade_length/Vector2(10.5,-10.5).length())

func get_preview_texture() -> Texture2D: return FRAMES.get_frame_texture(&"idle",0)
func get_debug_attack_regions() -> Array[Dictionary]:
	if health <= 0 or dizziness or not Can_Attack or is_damage_output_disabled() or not is_combat_runtime_active(): return []
	return _damage_regions
func get_ai_attack_threats(_receiver:ball) -> Array: return get_debug_attack_regions()
func get_debug_detection_regions() -> Array[Dictionary]:
	if health <= 0 or dizziness or not Can_Attack or not is_combat_runtime_active(): return []
	if combo_time >= COMBO_DURATION: return []
	if combo_time >= 0.0:
		if not _damage_regions.is_empty(): return []
		var region:Dictionary = blade_segment(combo_time)
		region.damage = 0.0
		return [region]
	return [{"shape":"circle","position":global_position,"radius":acquisition_range}]

func visual_state() -> Dictionary:
	return {"time":clock,"revision":_revision,"combo":combo_time,"heading":combo_heading,"cooldown":cooldown_left,"walking":_walking,"face_right":_face_right}
func accept_visual(data:Dictionary) -> void:
	var rev:int = int(data.get("revision",-1))
	var stamp:float = float(data.get("time",0.0))
	if rev < _accepted_revision or (rev == _accepted_revision and stamp < _accepted_clock): return
	_accepted_revision = rev
	_accepted_clock = stamp
	super.accept_visual(data)
	combo_time = float(data.get("combo",-1.0))
	combo_heading = data.get("heading",Vector2.RIGHT)
	cooldown_left = float(data.get("cooldown",0.0))
	_walking = bool(data.get("walking",false))
	_damage_regions.clear()
	for window:Vector2 in WINDOWS:
		if combo_time >= window.x and combo_time <= window.y: _damage_regions.append(blade_segment(combo_time))
func client_visual_step(delta:float) -> void:
	if not is_combat_runtime_active(): return
	_damage_regions.clear()
	if combo_time >= 0.0:
		combo_time += delta
		if combo_time >= RECOVER_END: combo_time = -1.0
		for window:Vector2 in WINDOWS:
			if combo_time >= window.x and combo_time <= window.y: _damage_regions.append(blade_segment(combo_time))
func _publish_pose() -> void:
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _receive_pose.rpc(visual_state())
@rpc("authority","call_remote","reliable")
func _receive_pose(data:Dictionary) -> void: accept_visual(data)
func _request_initial_state() -> void:
	if multiplayer.has_multiplayer_peer(): _request_combat_snapshot.rpc_id(get_multiplayer_authority())
@rpc("any_peer","call_remote","reliable")
func _request_combat_snapshot() -> void:
	if not is_multiplayer_authority(): return
	var layers:Array = []
	for ref:WeakRef in _status_targets.values():
		var target:ball = ref.get_ref() as ball
		if not is_instance_valid(target): continue
		var status:Node = EFFECTS.current(target,"wither")
		if status == null or status.is_queued_for_deletion(): continue
		var own:Dictionary = status.applications.get(get_instance_id(),{})
		if own.is_empty(): continue
		layers.append({"path":get_tree().current_scene.get_path_to(target),"level":own.grade,"remaining":own.time})
	_receive_combat_snapshot.rpc_id(multiplayer.get_remote_sender_id(),visual_state(),_wither_serial,layers)
@rpc("authority","call_remote","reliable")
func _receive_combat_snapshot(pose:Dictionary,serial:int,layers:Array) -> void:
	accept_visual(pose)
	if serial < _received_wither: return
	_received_wither = serial
	for layer:Dictionary in layers:
		var target:ball = get_tree().current_scene.get_node_or_null(layer.path) as ball
		if is_instance_valid(target): EFFECTS.apply_effect(target,"wither",clampi(int(layer.level),1,MAX_WITHER_LEVEL),clampf(float(layer.remaining),0.0,WITHER_SECONDS),self)

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if is_instance_valid(voice) and health > 0 and amount > 0.0 and _voice_rng.randf() < hurt_voice_chance:
		voice.request("hurt",global_position,-3.0)
func Die() -> void:
	cancel_combo()
	if is_instance_valid(voice): voice.request("death",global_position,0.0)
	if is_instance_valid(_sword): _sword.hide()
	if is_instance_valid(_arm): _arm.hide()
	if is_instance_valid(_fade_sprite): _fade_sprite.hide()
	super.Die() # Retains project default death sound/lifecycle.
@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	if is_instance_valid(_sword): _sword.hide()
	if is_instance_valid(_fade_sprite): _fade_sprite.hide()
	if is_instance_valid(_arm): _arm.hide()
	# The death-pose snapshot needs the complete original model, not the arm-less torso.
	image.texture = FRAMES.get_frame_texture(_body_clip,_body_frame)
	DEATH_FX.death_pose(self,image,_face_right)
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_WITHER_SKELETON")

