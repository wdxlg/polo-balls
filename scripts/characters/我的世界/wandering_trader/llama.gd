extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## 流浪商人的羊驼 (trader llama, docs/WANDERING_TRADER.md).
## * Killable summon: Type Creature + Master = trader, so World never counts it as a battle
##   character (no victory weight) and it never respawns. Dies with its trader (vanilla trader
##   llamas despawn with him).
## * Leashed: follows the trader; beyond leash_pull_start the leash yanks it back at high speed
##   and it ignores character collision (layer 0 / mask 1) until it is close again.
## * Speed damage: ONLY this body, from its own actual speed (>= speed_damage_min_speed),
##   knockback along its own motion direction.
## * Spit: medium interval, medium-fast projectile; also retaliates after a short delay when hit.
## * While the trader hides in a wall the leash is broken and the llama roams/chases/spits freely.
const AUDIO = preload("res://scripts/characters/我的世界/wandering_trader/audio.gd")
const VISUAL = preload("res://scripts/characters/我的世界/wandering_trader/visual.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const HIT_AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const WALL_CLIP = preload("res://scripts/characters/我的世界/wandering_trader/wall_clip.gd")
const SPIT_SCENE_PATH:String = "res://scenes/shooter/我的世界/羊驼口水.tscn"
const FRAME_SETS:Array[StringName] = [&"llama_creamy",&"llama_brown"]
const NORMAL_LAYER:int = 2
const NORMAL_MASK:int = 3

@export_category("羊驼 / 移动")
@export var follow_speed:float = 62.0
@export var roam_speed:float = 38.0
@export var chase_speed:float = 56.0
@export var yank_speed_min:float = 170.0
@export var yank_speed_max:float = 340.0
@export var yank_speed_per_px:float = 6.0
@export_category("羊驼 / 口水")
@export var spit_range:float = 135.0
@export var spit_interval:float = 2.0
@export var spit_interval_jitter:float = 0.35
@export var spit_speed:float = 300.0
@export var spit_knockback:float = 6.0
@export var retaliate_delay:float = 0.45
@export var retaliate_min_gap:float = 0.9
@export_category("羊驼 / 速度伤害")
@export var speed_damage_min_speed:float = 130.0
@export var speed_damage_ratio:float = 0.09
@export var speed_damage_max:float = 40.0
@export var speed_knockback_ratio:float = 0.1
@export var speed_hit_cooldown:float = 0.45

var slot_index:int = 0
var leash_connected:bool = false
var yanking:bool = false
var ghost:bool = false
var visual:Node
var last_speed:float = 0.0
var speed_hits_dealt:int = 0
var spits_fired:int = 0
var retaliations:int = 0
var _spit_wait:float = 1.0
var _spit_anim:float = 0.0
var _spit_serial:int = 0
var _retaliate_wait:float = -1.0
var _retaliate_ref:WeakRef
var _last_retaliate_msec:int = -100000
var _attacker_ref:WeakRef
var _attacker_msec:int = -100000
var _roam_point:Vector2
var _roam_wait:float = 0.0
var _speed_hits:Dictionary = {}
var _desired_direction:Vector2 = Vector2.ZERO
var _desired_speed:float = 0.0
var _stuck_time:float = 0.0
var _ghost_time:float = 0.0
var _step_wait:float = 0.3
var _retired:bool = false
var free_moving:bool = false
var _last_motion_dir:Vector2 = Vector2.ZERO
var free_start_direction:Vector2 = Vector2.ZERO # direction chosen when the leash went off
var free_start_motion:Vector2 = Vector2.ZERO # its last motion direction at that moment
## Returning llama walking out of the wall next to the trader (driven here, clipped like him).
var emerging:bool = false
var _emerge_from:Vector2
var _emerge_to:Vector2
var _emerge_time:float = 0.0
var _emerge_duration:float = 0.3
var _wall_clip:Node

func _ready() -> void:
	Type = Ball_Type.Creature
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	Has_Collision_Damage = false
	side_status_ui_enabled = false
	hurt_voice_chance = 0.8
	mc_audio_role = "trader_llama"
	slot_index = _slot_from_name()
	super._ready()
	collision_layer = NORMAL_LAYER
	collision_mask = NORMAL_MASK
	visual = VISUAL.attach(self,FRAME_SETS[slot_index % FRAME_SETS.size()])
	_spit_wait = _mc_rng.randf_range(0.8,1.6)
	add_to_group(&"MCTraderLlama")

## Llama names are "<trader>_Llama<i>" so every peer (MultiplayerSpawner keeps names)
## derives the same slot/colour without extra synced properties.
func _slot_from_name() -> int:
	var text:String = str(name)
	var at:int = text.rfind("_Llama")
	return maxi(int(text.substr(at + 6)),0) if at >= 0 else 0

## The owning wandering trader, or null. Only a real trader (leash API) counts: a Haochen copy
## of a llama is owned by the copier (a plain ball without leash properties).
func trader() -> Node2D:
	if master_alive() and Master.has_method(&"wt_leash_active"): return Master
	return null

func master_alive() -> bool:
	return is_instance_valid(Master) and not Master.is_queued_for_deletion() and Master.health > 0

## A llama that is not on a trader's herd (Haochen copy): lives on its own, free movement.
func is_free_agent() -> bool:
	return bool(get_meta(&"haochen_copy",false)) or (master_alive() and not Master.has_method(&"wt_leash_active"))

func has_collision_damage() -> bool: return false

# ------------------------------------------------------------------ audio
func wt_sound(event:StringName,volume:float = 0.0,pitch:float = -1.0) -> AudioStreamPlayer2D:
	var index:int = AUDIO.variant(event)
	if pitch <= 0.0: pitch = _mc_voice_rng.randf_range(0.9,1.1)
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_wt_sound_remote.rpc(event,index,global_position,volume,pitch)
	return AUDIO.play(self,event,global_position,volume,pitch,index)

@rpc("authority","call_remote","unreliable")
func _wt_sound_remote(event:StringName,index:int,point:Vector2,volume:float,pitch:float) -> void:
	AUDIO.play(self,event,point,volume,pitch,index)

func mc_play(event:String,_volume:float = -4.0) -> AudioStreamPlayer2D:
	var key:StringName = StringName("llama_" + event)
	if not AUDIO.EVENTS.has(key): return null
	return wt_sound(key)
func mc_ambient_event() -> String: return "ambient"
func mc_ambient_allowed() -> bool: return is_multiplayer_authority() and not _retired
func mc_ambient_gap() -> Vector2: return Vector2(5.0,11.0)

# ------------------------------------------------------------------ AI
func tick_physics(state:State,delta:float) -> void:
	if _retired: return
	if health <= 0:
		retire()
		return
	var owner_trader:Node2D = trader()
	if owner_trader == null and not is_free_agent():
		if is_multiplayer_authority():
			health = 0
			retire()
		return
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return
	if emerging:
		_tick_emerge(delta)
		return
	if not is_combat_runtime_active():
		_hold_beside(owner_trader)
		mc_tick_ambient(delta)
		return
	_think(owner_trader,delta)
	super.tick_physics(state,delta)

func _hold_beside(owner_trader:Node2D) -> void:
	if owner_trader == null:
		velocity = Vector2.ZERO
		return
	# Placement/pre-start: stay packed next to the trader so dragging him keeps the herd together.
	var point:Vector2 = owner_trader.global_position + Vector2(-16.0 if slot_index % 2 == 0 else 16.0,5.0)
	if global_position.distance_to(point) > 3.0: global_position = point
	velocity = Vector2.ZERO

func leash_active(owner_trader:Node2D) -> bool:
	return leash_connected and owner_trader != null and owner_trader.has_method(&"wt_leash_active") and bool(owner_trader.call(&"wt_leash_active"))

func _think(owner_trader:Node2D,delta:float) -> void:
	_spit_wait -= delta
	_spit_anim = maxf(_spit_anim - delta,0.0)
	var connected:bool = leash_active(owner_trader)
	var to_owner:Vector2 = owner_trader.global_position - global_position if owner_trader != null else Vector2.ZERO
	var distance:float = to_owner.length()
	var slack:float = float(owner_trader.get(&"leash_slack")) if connected else 0.0
	var pull_end:float = float(owner_trader.get(&"leash_pull_end")) if connected else 0.0
	if connected and distance > float(owner_trader.get(&"leash_pull_start")): _set_yanking(true)
	elif yanking and (not connected or distance <= pull_end): _set_yanking(false)
	_update_ghost(delta)
	var target:ball = mc_nearest(delta)
	var target_distance:float = INF if target == null else global_position.distance_to(ball.body_point(target,global_position))
	if _retaliate_wait >= 0.0:
		_retaliate_wait -= delta
		if _retaliate_wait < 0.0: _do_retaliate()
	if not yanking and _spit_anim <= 0.0 and _spit_wait <= 0.0 and target != null and target_distance <= spit_range and mc_live() and mc_line_clear(global_position,ball.body_point(target,global_position)):
		spit_at(target)
		_spit_wait = spit_interval + _mc_rng.randf_range(-spit_interval_jitter,spit_interval_jitter)
	var desired:Vector2 = Vector2.ZERO
	var speed:float = 0.0
	if yanking:
		desired = to_owner/maxf(distance,0.001)
		speed = clampf(yank_speed_min + (distance - pull_end)*yank_speed_per_px,yank_speed_min,yank_speed_max)
	elif connected:
		if distance > slack*0.75:
			desired = to_owner/maxf(distance,0.001)
			speed = follow_speed*clampf((distance - slack*0.5)/(slack*0.5),0.4,1.3)
		elif target != null and target_distance > spit_range*0.85 and distance < slack*0.6:
			desired = global_position.direction_to(ball.body_point(target,global_position))
			speed = chase_speed*0.6
		else:
			var point:Vector2 = owner_trader.global_position + Vector2(-18.0 if slot_index % 2 == 0 else 18.0,6.0)
			if global_position.distance_to(point) > 7.0:
				desired = global_position.direction_to(point)
				speed = roam_speed
	else:
		# Leash off (trader in the wall) or no trader: normal ball movement. Keeps going the way it
		# was just moving, at its own Speed, and bounces off walls/characters (when_collide).
		if not free_moving:
			free_moving = true
			direction = _last_motion_dir if _last_motion_dir != Vector2.ZERO else Vector2.RIGHT.rotated(_mc_rng.randf_range(0.0,TAU))
			free_start_direction = direction
			free_start_motion = _last_motion_dir
		desired = direction
		speed = maxf(float(default_properties.get("Speed",Speed)),1.0)
	if yanking or connected: free_moving = false
	if _spit_anim > 0.0: speed *= 0.2
	if target != null and _spit_anim > 0.0: _face((ball.body_point(target,global_position) - global_position).x)
	_desired_direction = desired
	_desired_speed = speed

func _set_yanking(on:bool) -> void:
	if yanking == on: return
	yanking = on
	_stuck_time = 0.0
	if on:
		_set_ghost(true)
		_speed_hits.clear()

func _set_ghost(on:bool) -> void:
	ghost = on
	_ghost_time = 0.0
	collision_layer = 0 if on else NORMAL_LAYER
	collision_mask = 1 if on else NORMAL_MASK

func _update_ghost(delta:float) -> void:
	if not ghost or yanking: return
	_ghost_time += delta
	# Leave ghost mode only where the body does not overlap a character (no depenetration shove).
	if _ghost_time > 1.5 or herd_position_clear(global_position): _set_ghost(false)

## mc_body_position_clear, but the trader and the other llamas do not count: they are collision
## exceptions of this body, so overlapping them never causes a depenetration shove.
func herd_position_clear(point:Vector2) -> bool:
	if collision_shape_2d == null or collision_shape_2d.shape == null: return mc_position_clear(point,18.0)
	var exclude:Array[RID] = [get_rid()]
	if is_instance_valid(Master): exclude.append(Master.get_rid())
	for other:Node in get_tree().get_nodes_in_group(&"MCTraderLlama"):
		if other != self and other is CollisionObject2D and other.get(&"Master") == Master: exclude.append((other as CollisionObject2D).get_rid())
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape_2d.shape
	query.transform = collision_shape_2d.global_transform
	query.transform.origin += point - global_position
	query.collision_mask = NORMAL_MASK
	query.exclude = exclude
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func move(speed:float,delta:float) -> void:
	var from:Vector2 = global_position
	var reference:float = maxf(float(default_properties.get("Speed",Speed)),1.0)
	var ratio:float = maxf(speed,0.0)/reference
	if yanking: ratio = maxf(ratio,1.0) # the leash pulls; slows do not cancel it
	var locked:bool = dizziness or (has_method(&"is_direction_change_locked") and bool(call(&"is_direction_change_locked")))
	# Free movement owns `direction` (ball bounce); the leashed AI steers it every frame.
	if not locked and not free_moving: direction = _desired_direction if _desired_speed > 0.01 else Vector2.ZERO
	super.move(0.0 if locked else _desired_speed*ratio,delta)
	var arena:Rect2 = mc_arena_rect().grow(-6.0)
	if arena.has_area() and not arena.has_point(global_position):
		var clamped:Vector2 = global_position.clamp(arena.position,arena.end)
		# Free movement: the arena edge is a wall too (bounce instead of sliding along it).
		if free_moving and not locked:
			if clamped.x > global_position.x: direction.x = absf(direction.x)
			elif clamped.x < global_position.x: direction.x = -absf(direction.x)
			if clamped.y > global_position.y: direction.y = absf(direction.y)
			elif clamped.y < global_position.y: direction.y = -absf(direction.y)
		global_position = clamped
	var moved:Vector2 = global_position - from
	last_speed = moved.length()/maxf(delta,0.0001)
	if moved.length_squared() > 0.0025: _last_motion_dir = moved.normalized()
	if yanking:
		# An internal wall between llama and trader: after a short stall let the leash drag it through.
		_stuck_time = _stuck_time + delta if last_speed < yank_speed_min*0.25 else 0.0
		if _stuck_time > 1.0: collision_mask = 0
	if absf(moved.x) > 0.02 and _spit_anim <= 0.0: _face(moved.x)
	_speed_damage_sweep(from,global_position,delta)
	if last_speed > 12.0:
		_step_wait -= delta
		if _step_wait <= 0.0:
			_step_wait = clampf(18.0/last_speed,0.14,0.5)
			wt_sound(&"llama_step")

func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	# Leashed: the AI re-steers every frame (no pinball bounce). Free: normal ball bounce.
	if free_moving: super.when_collide(speed,collision)

func _face(dx:float) -> void:
	if absf(dx) < 0.001: return
	set_character_visual_flip_h(dx > 0.0 if dir_left else dx < 0.0)

func facing_sign() -> float:
	var right:bool = is_character_visual_flipped_h() if dir_left else not is_character_visual_flipped_h()
	return 1.0 if right else -1.0

## Leash attachment at the neck (world space), used by the trader's leash view.
func wt_neck_point() -> Vector2:
	return to_global(Vector2(facing_sign()*18.0,-11.0))

func wt_visual_clip(observed_speed:float) -> StringName:
	if emerging: return &"walk"
	if _spit_anim > 0.0: return &"spit"
	if observed_speed > 110.0: return &"run"
	if observed_speed > 6.0: return &"walk"
	return &"idle"

# ------------------------------------------------------------------ speed damage
func speed_damage_for(speed:float) -> float:
	if speed < speed_damage_min_speed: return 0.0
	return clampf(speed*speed_damage_ratio,1.0,speed_damage_max)

func _speed_damage_sweep(from:Vector2,to:Vector2,delta:float) -> void:
	if not mc_live() or delta <= 0.0: return
	var speed:float = from.distance_to(to)/delta
	var amount:float = speed_damage_for(speed)
	if amount <= 0.0: return
	var heading:Vector2 = (to - from).normalized()
	var radius:float = maxf(get_crowd_separation_radius_world(),4.0)
	var shape := CapsuleShape2D.new()
	shape.radius = radius
	shape.height = from.distance_to(to) + radius*2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(heading.angle() + PI*0.5,from.lerp(to,0.5))
	query.collision_mask = 2
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var now:int = Time.get_ticks_msec()
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,32):
		var area:Variant = hit.get("collider")
		if not (area is Area2D) or not is_instance_valid(area): continue
		var target:Variant = (area as Area2D).get_parent()
		if not wt_enemy(target): continue
		var id:int = (target as Node).get_instance_id()
		if now - int(_speed_hits.get(id,-100000)) < int(speed_hit_cooldown*1000.0): continue
		_speed_hits[id] = now
		apply_speed_hit(target as ball,speed,heading)

func apply_speed_hit(target:ball,speed:float,heading:Vector2) -> bool:
	var amount:float = speed_damage_for(speed)
	if amount <= 0.0 or not wt_enemy(target): return false
	speed_hits_dealt += 1
	var applied:bool = wt_damage(target,effective_outgoing_damage(amount),global_position)
	if is_instance_valid(target) and target.health > 0:
		target.apply_knockback(heading,clampf(speed*speed_knockback_ratio,6.0,38.0),maxf(speed*1.15,200.0),0.0,0.0,{"source":self})
	VISUAL.burst(self,target.global_position if is_instance_valid(target) else global_position,Color(0.93,0.86,0.72),8,50.0,1.2,0.4)
	return applied

func wt_enemy(target:Variant) -> bool:
	if not mc_enemy(target): return false
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false
	return true

func wt_damage(target:ball,amount:float,point:Vector2) -> bool:
	if has_method(&"mc_damage_with_impact"): return bool(call(&"mc_damage_with_impact",target,amount,point))
	if not is_multiplayer_authority() or not wt_enemy(target) or amount <= 0.0 or is_damage_output_disabled(): return false
	var before:float = maxf(float(target.health),0.0)
	var hit_point:Vector2 = ball.body_point(target,global_position)
	var applied:bool = target.receive_positional_damage(amount,point,false,self)
	var actual:float = before - (maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0)
	if actual > 0.0: wt_hit_sound(actual,hit_point)
	return applied

## MC_CONTEXT §1 hit feedback (<=50 hurt, >50 crit, damage_gain from 0 dB). These events live in the
## shared new5 table (mc_native_audio has none of them), played at the victim and kept after the
## source is gone (the spit frees itself on hit), unthrottled so separate hits never swallow each other.
func wt_hit_sound(actual:float,point:Vector2) -> AudioStreamPlayer2D:
	if not is_finite(actual) or actual <= 0.0: return null
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _wt_hit_sound_remote.rpc(actual,point)
	return _wt_hit_sound_local(actual,point)

@rpc("authority","call_remote","reliable")
func _wt_hit_sound_remote(actual:float,point:Vector2) -> void:
	_wt_hit_sound_local(actual,point)

func _wt_hit_sound_local(actual:float,point:Vector2) -> AudioStreamPlayer2D:
	var player:AudioStreamPlayer2D = HIT_AUDIO.play(self,HIT_GAIN.damage_event(actual),point,HIT_GAIN.damage_gain(actual),false,true,true,true)
	if is_instance_valid(player):
		player.set_meta(&"mc_damage_source",get_instance_id())
		player.set_meta(&"mc_actual_damage",actual)
	return player

# ------------------------------------------------------------------ spit
func spit_at(target:ball) -> void:
	if not is_instance_valid(target) or not is_multiplayer_authority(): return
	var mouth:Vector2 = wt_neck_point() + Vector2(facing_sign()*1.6,-2.4)
	var travel:float = mouth.distance_to(ball.body_point(target,mouth))/maxf(spit_speed,1.0)
	var aim:Vector2 = ball.body_point(target,global_position) + target.velocity*clampf(travel,0.0,0.6)*0.5
	var heading:Vector2 = mouth.direction_to(aim)
	if heading == Vector2.ZERO: heading = Vector2(facing_sign(),0.0)
	_face(heading.x)
	_spit_serial += 1
	spits_fired += 1
	var shot_name:String = "%s_Spit%d" % [str(name),_spit_serial]
	var damage:float = attack_damage()
	_spawn_spit(shot_name,mouth,heading,damage)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _spawn_spit.rpc(shot_name,mouth,heading,damage)
	wt_sound(&"llama_spit")

@rpc("authority","call_remote","reliable")
func _spawn_spit(shot_name:String,point:Vector2,heading:Vector2,damage:float) -> void:
	_spit_anim = 0.34
	var parent:Node = get_parent()
	if parent == null or parent.has_node(NodePath(shot_name)): return
	var shot:ball = (load(SPIT_SCENE_PATH) as PackedScene).instantiate()
	shot.name = shot_name
	shot.Master = self
	shot.Master_name = str(name)
	shot.Team = Team
	shot.Damage = int(round(damage))
	shot.Speed = spit_speed
	shot.set(&"knockback",spit_knockback)
	shot.direction = heading
	shot.position = (parent as Node2D).to_local(point) if parent is Node2D else point
	shot.set_multiplayer_authority(get_multiplayer_authority())
	parent.add_child(shot,true)

# ------------------------------------------------------------------ retaliation
func _resolve_attacker(source:Variant) -> ball:
	var node:Variant = source
	for i:int in range(6):
		if not is_instance_valid(node) or not (node is ball): return null
		var unit:ball = node as ball
		if unit.Type in [Ball_Type.Ball,Ball_Type.Creature] and unit.is_combat_targetable(): return unit
		node = unit.Master
	return null

func _note_attacker(source:Variant) -> void:
	var attacker:ball = _resolve_attacker(source)
	if attacker != null and wt_enemy(attacker):
		_attacker_ref = weakref(attacker)
		_attacker_msec = Time.get_ticks_msec()

func can_receive_hit_contact(incoming:hitbox,_contact:hurtbox) -> bool:
	if _retired: return false
	if incoming != null: _note_attacker(incoming.get_parent())
	return true

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if _retired: return false
	_note_attacker(source)
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)

func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	super.on_actual_health_damage_received(actual_health_damage,health_before)
	if actual_health_damage <= 0.0 or not is_multiplayer_authority() or health <= 0 or _retaliate_wait >= 0.0: return
	if Time.get_ticks_msec() - _last_retaliate_msec < int(retaliate_min_gap*1000.0): return
	var fresh:bool = Time.get_ticks_msec() - _attacker_msec <= 300
	_retaliate_ref = _attacker_ref if fresh else null
	_retaliate_wait = retaliate_delay

func _do_retaliate() -> void:
	var target:Variant = _retaliate_ref.get_ref() if _retaliate_ref != null else null
	if not wt_enemy(target): target = mc_nearest(0.0)
	_retaliate_ref = null
	if not mc_live() or not wt_enemy(target): return
	var unit:ball = target as ball
	if global_position.distance_to(ball.body_point(unit,global_position)) > spit_range*2.0 or not mc_line_clear(global_position,ball.body_point(unit,global_position)): return
	_last_retaliate_msec = Time.get_ticks_msec()
	retaliations += 1
	wt_sound(&"llama_angry",-2.0)
	spit_at(unit)
	_spit_wait = maxf(_spit_wait,spit_interval*0.5)

# ------------------------------------------------------------------ return through the wall
## Authority: the replacement llama starts completely inside the wall and walks straight out along
## the wall normal in the same time as the trader. Non-solid, untargetable and exempt from the
## map-escape rescue until it is out; the body is cut at the wall surface on every peer.
func wt_begin_emerge(from:Vector2,to:Vector2,duration:float,face:Vector2,normal:Vector2) -> void:
	emerging = true
	_emerge_from = from
	_emerge_to = to
	_emerge_time = 0.0
	_emerge_duration = maxf(duration,0.05)
	global_position = from
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	set_meta(&"ignore_combat_targeting",true)
	set_meta(&"submission_allow_map_escape",true)
	if self_hurtbox != null: self_hurtbox.set_deferred("monitorable",false)
	if absf(to.x - from.x) > 0.01: _face(to.x - from.x)
	emerge_clip(true,face,normal) # peers: the trader relays it (this node may not be spawned there yet)

func _tick_emerge(delta:float) -> void:
	_emerge_time += delta
	var k:float = clampf(_emerge_time/_emerge_duration,0.0,1.0)
	global_position = _emerge_from.lerp(_emerge_to,k)
	last_speed = _emerge_from.distance_to(_emerge_to)/_emerge_duration
	if k >= 1.0: wt_finish_emerge()

func wt_finish_emerge() -> void:
	if not emerging: return
	emerging = false
	global_position = _emerge_to
	collision_layer = NORMAL_LAYER
	collision_mask = NORMAL_MASK
	for key:StringName in [&"ignore_combat_targeting",&"submission_allow_map_escape"]:
		if has_meta(key): remove_meta(key)
	if self_hurtbox != null: self_hurtbox.set_deferred("monitorable",true)
	emerge_clip(false,Vector2.ZERO,Vector2.UP)

func emerge_clip(active:bool,face:Vector2,normal:Vector2) -> void:
	if active:
		if image == null or not is_instance_valid(image): return
		if _wall_clip == null or not is_instance_valid(_wall_clip):
			_wall_clip = WALL_CLIP.new()
			_wall_clip.name = "WallClip"
			add_child(_wall_clip)
		_wall_clip.call(&"start",image,face,normal)
	elif _wall_clip != null and is_instance_valid(_wall_clip):
		_wall_clip.call(&"stop")

func wall_clip_active() -> bool:
	return _wall_clip != null and is_instance_valid(_wall_clip) and bool(_wall_clip.get(&"active"))

# ------------------------------------------------------------------ life
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _retired: return
	super.take_damage(damage,ignore_block)
	if health <= 0: retire()

func owner_lost() -> void:
	if _retired: return
	health = 0
	retire()

func retire() -> void:
	if _retired: return
	_retired = true
	if is_multiplayer_authority(): wt_sound(&"llama_death")
	mc_death_visual()
	VISUAL.burst(self,global_position,Color(0.92,0.92,0.92),12,40.0,1.8,0.6)
	var owner_trader:Variant = Master
	if is_instance_valid(owner_trader) and owner_trader.has_method(&"wt_on_llama_lost"): owner_trader.call(&"wt_on_llama_lost",self)
	hide()
	collision_layer = 0
	collision_mask = 0
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	if self_hurtbox != null: self_hurtbox.set_deferred("monitorable",false)
	for group:StringName in [&"Ball",&"MCTraderLlama"]:
		if is_in_group(group): remove_from_group(group)
	var herd:Array = get_tree().get_nodes_in_group(&"MCTraderLlama")
	if is_instance_valid(owner_trader): herd.append(owner_trader)
	for body:Variant in herd:
		if is_instance_valid(body) and body is PhysicsBody2D and body != self: (body as PhysicsBody2D).remove_collision_exception_with(self)
	queue_free()

func Die() -> void: retire()

func is_combat_targetable() -> bool:
	# Killable summon (like the Vex), not a decorative Creature.
	if _retired or health <= 0 or is_queued_for_deletion(): return false
	if bool(get_meta(&"ignore_combat_targeting",false)): return false
	return state_machine == null or state_machine.current_state != State.Die
