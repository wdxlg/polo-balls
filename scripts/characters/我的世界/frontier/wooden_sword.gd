extends "res://scripts/characters/我的世界/frontier/base.gd"
## 60 durability, two independently living fragments, family-bound workbench repair.
const SWORD:Texture2D = preload("res://Images/characters/我的世界/frontier/wood_sword.png")
const STICK:Texture2D = preload("res://Images/characters/我的世界/frontier/stick.png")
const MAX_DURABILITY:int = 60
const HILT:Texture2D = preload("res://Images/characters/我的世界/frontier/wood_hilt.png")
const BLADE:Texture2D = preload("res://Images/characters/我的世界/frontier/wood_blade.png")
const BENCH = preload("res://scripts/characters/我的世界/frontier/sword_workbench.gd")
@export var part_kind:int = 0 # 0 sword, 1 hilt, 2 blade
@export var durability_damage_step:float = 5.0
@export var bench_heal_ratio:float = 0.05
var sword_family:String = ""
var workbench:Node2D
var bench_destroyed:bool = false
var _rest_image_position:Vector2
var _rest_image_cached:bool = false
var full_max_health:int = 750
var dock_delay:float = 0.0
var _split_requested:bool = false
var _geometry_kind:int = -1
var _idle_left:bool = false
var _swing_left_facing:bool = false
var _shape_left:bool = false
var _blade_heading:Vector2 = Vector2.RIGHT
@export var charge_duration:float = 2.0
@export var minimum_charge_time:float = 0.5
@export var trail_charge_threshold:float = 0.65
@export var charge_min_damage:float = 0.35
@export var charge_max_damage:float = 2.0
@export var charge_min_push:float = 0.35
@export var charge_max_push:float = 3.0
var _manual_charging:bool = false
var _manual_release_pending:bool = false
var _part_recovery_left:float = 0.0
var _status_removed:bool = false
@export var sword_reach:float = 62.0
@export var repair_duration:float = 2.4
var durability:int = MAX_DURABILITY
var sword_charge:float = 0.0
var repairing:bool = false
var repair_left:float = 0.0
var repair_anchor:Vector2 = Vector2.ZERO
var repair_lock:float = 0.0
var swing_left:float = 0.0
var swing_visual_left:float = 0.0
var swing_cooldown:float = 0.0
var swing_heading:Vector2 = Vector2.RIGHT
var _swing_charge:float = 0.0
var _swing_was_broken:bool = false
var _swing_pending:bool = false
@export var sword_knockback:float = 12.0
@export var hilt_knockback:float = 55.0
@export var hilt_damage_multiplier:float = 0.2
@export var blade_damage_multiplier:float = 1.25
@export var blade_recovery:float = 0.28
@export var blade_attack_duration:float = 0.20
var attack_area:Area2D
var attack_collider:CollisionShape2D
var attack_shape:ConvexPolygonShape2D
var _attack_texture:Texture2D
var _swing_hit_ids:Dictionary = {}
var _swing_elapsed:float = 0.0
var _last_attack_phase:float = 0.0
var _last_attack_pose:Transform2D
var successful_repairs:int = 0
func role_key() -> String: return "wooden_sword"
func get_preview_texture() -> Texture2D: return SWORD
func is_broken() -> bool: return part_kind != 0
func _ready() -> void:
	super._ready()
	Can_Skill = false
	default_properties["Can_Skill"] = false
const TRANSFORM_FX = preload("res://scripts/characters/我的世界/bat/bat_transform_fx.gd")
var transformation_count:int = 0
var _wood_sound_serial:int = 0
var _last_wood_sound:int = 0
func attack_sound_event() -> String:
	return "entity.player.attack.weak" if part_kind == 2 else "entity.player.attack.sweep"
static func impact_sound_event(actual_damage:float) -> String:
	return "entity.player.attack.crit" if actual_damage > 50.0 else "entity.player.hurt"
static func impact_volume(actual_damage:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual_damage)
func emit_sword_audio(event:String,point:Vector2,volume:float) -> void:
	if not is_multiplayer_authority(): return
	_wood_sound_serial += 1
	if multiplayer.has_multiplayer_peer(): _sword_audio.rpc(_wood_sound_serial,event,point,volume)
	_sword_audio(_wood_sound_serial,event,point,volume)
@rpc("authority","call_remote","reliable")
func _sword_audio(id:int,event:String,point:Vector2,volume:float) -> void:
	if id <= _last_wood_sound: return
	_last_wood_sound = id
	var important:bool = event in ["entity.item.break","block.crafter.craft","entity.breeze.deflect"]
	var player:AudioStreamPlayer2D = AUDIO.play(self,event,point,volume,false,important,true)
	if is_instance_valid(player): _cue_players.append(player)
func damage_with_impact_sound(target:ball,amount:float,point:Vector2) -> bool:
	if not is_instance_valid(target): return false
	var before:float = maxf(float(target.health),0.0)
	var victim_ref:WeakRef = weakref(target)
	var accepted:bool = U.damage(self,target,amount,point)
	var victim:Variant = victim_ref.get_ref()
	var remaining:float = maxf(float(victim.health),0.0) if is_instance_valid(victim) else 0.0
	var actual:float = maxf(before-remaining,0.0)
	if accepted and actual > 0.0:
		emit_sword_audio(impact_sound_event(actual),point,impact_volume(actual))
	return accepted
func play_sword_transformation(point:Vector2) -> void:
	if multiplayer.has_multiplayer_peer(): _sword_transformation.rpc(point)
	else: _sword_transformation(point)
@rpc("authority","call_local","reliable")
func _sword_transformation(point:Vector2) -> void:
	transformation_count += 1
	var effect:Node2D = TRANSFORM_FX.new()
	effect.position = point
	effect.visual_seed = int(get_instance_id()) ^ int(Engine.get_physics_frames())
	effect.set_meta("wood_sword_transformation",true)
	TRANSFORM_FX.runtime_container(self).add_child(effect)
func has_reachable_swing_target() -> bool:
	if sword_charge+0.00001 < minimum_charge_time/maxf(charge_duration,0.1): return false
	update_idle_facing()
	ensure_attack_shape()
	var stored:float = _swing_charge
	_swing_charge = sword_charge
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = attack_shape
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var found:bool = false
	for sample:int in range(20):
		query.transform = weapon_transform(lerpf(0.12,0.85,float(sample)/19.0))
		for contact:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,64):
			var collider:Node = contact.collider
			var node:Node = collider
			while is_instance_valid(node) and not node is ball: node = node.get_parent()
			if node is ball and collider == node.self_hurtbox and U.enemy(self,node) and not same_family(node) and U.line_clear(self,global_position,ball.body_point(node,global_position)):
				found = true
				break
		if found: break
	_swing_charge = stored
	return found
# Only the displacement/recovery lock is exempt. Do not release the actual
# movement lock, change Repel, or turn a real stun/other control into immunity.
func can_keep_charging_through_knockback() -> bool:
	if is_broken() or not active() or not Can_Attack or is_damage_output_disabled(): return false
	if not dizziness or _stun_visual_ref_count > 0: return false
	if bool(get_meta(KNOCKBACK_EFFECT_SCRIPT.CONTROL_BASELINE_META,false)): return false
	var displacement_locks:int = 0
	for effect:Node in get_children():
		if not effect is KNOCKBACK_EFFECT_SCRIPT: continue
		if not effect.is_active_effect() or not effect._lock_acquired: continue
		if effect._stage not in [0,2]: return false
		displacement_locks += 1
	return displacement_locks > 0 and displacement_locks == int(get_meta(KNOCKBACK_EFFECT_SCRIPT.CONTROL_LOCK_META,0))

func step_mob(delta:float) -> void:
	if is_broken():
		step_part(delta)
		return
	swing_cooldown = maxf(0,swing_cooldown-delta)
	if not can_act():
		cancel_attack()
		if can_keep_charging_through_knockback():
			if not is_player_controlled() or _manual_charging:
				sword_charge = minf(1.0,sword_charge+delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self)/maxf(charge_duration,0.1))
		else:
			player_control_action_cancelled(0)
		if _split_requested: call_deferred("split_sword")
		return
	if _swing_pending:
		advance_attack(delta)
		return
	advance_attack(delta)
	if is_player_controlled():
		if _manual_release_pending:
			_manual_release_pending = false
			if not begin_swing(): sword_charge = 0.0
			return
		if _manual_charging: sword_charge = minf(1.0,sword_charge+delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self)/maxf(charge_duration,0.1))
		return
	if _manual_charging or _manual_release_pending:
		player_control_action_cancelled(0)
	sword_charge = minf(1.0,sword_charge+delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self)/maxf(charge_duration,0.1))
	var target:ball = nearest_foe()
	if is_instance_valid(target) and global_position.distance_to(ball.body_point(target,global_position)) <= attack_trigger_reach()+U.radius(target) and has_reachable_swing_target():
		begin_swing()
func begin_swing() -> bool:
	if not is_broken() and sword_charge+0.00001 < minimum_charge_time/maxf(charge_duration,0.1): return false
	if not can_act() or _split_requested or repairing or swing_left > 0.0 or swing_cooldown > 0.0 or (is_broken() and _part_recovery_left > 0.0): return false
	update_idle_facing()
	_swing_left_facing = _idle_left
	swing_heading = blade_motion_direction() if part_kind == 2 else Vector2.LEFT if _swing_left_facing else Vector2.RIGHT
	_swing_pending = true
	_swing_charge = sword_charge if part_kind == 0 else 1.0
	_manual_charging = false
	_manual_release_pending = false
	if is_broken(): _part_recovery_left = attack_duration()+attack_recovery()
	_swing_was_broken = is_broken()
	sword_charge = 0.0
	ensure_attack_shape()
	_swing_elapsed = 0.0
	_swing_hit_ids.clear()
	_last_attack_phase = 0.0
	_last_attack_pose = weapon_transform(0.0)
	swing_left = attack_duration()
	swing_visual_left = attack_duration()
	swing_cooldown = attack_duration()
	if part_kind == 0: spend_durability(1)
	emit_sword_audio(attack_sound_event(),global_position,-8.0)
	return true
func attack_duration() -> float:
	return blade_attack_duration if part_kind == 2 else 0.34 if part_kind == 1 else lerpf(0.40,0.16,clampf(_swing_charge,0,1))
func attack_recovery() -> float:
	return blade_recovery if part_kind == 2 else 0.7 if part_kind == 1 else charge_duration
func ensure_attack_shape() -> void:
	if not is_instance_valid(image): return
	if not _rest_image_cached:
		_rest_image_position = image.position
		_rest_image_cached = true
	if not is_instance_valid(attack_area):
		attack_area = Area2D.new()
		attack_area.name = "WoodAttackHitbox"
		attack_area.collision_layer = 0
		attack_area.collision_mask = 0
		attack_area.monitoring = false
		attack_area.monitorable = false
		image.add_child(attack_area)
		attack_collider = CollisionShape2D.new()
		attack_collider.name = "WeaponShape"
		attack_collider.disabled = true
		attack_area.add_child(attack_collider)
	var mirrored:bool = part_kind != 2 and presentation_left()
	if _attack_texture == image.texture and _shape_left == mirrored: return
	_attack_texture = image.texture
	_shape_left = mirrored
	var world:Node = get_tree().current_scene
	if not world.has_meta("wood_weapon_shapes"): world.set_meta("wood_weapon_shapes",{})
	var _weapon_shapes:Dictionary = world.get_meta("wood_weapon_shapes")
	var key:String = image.texture.resource_path+(":left" if mirrored else ":right")
	if not _weapon_shapes.has(key):
		var pixels:Image = image.texture.get_image()
		var points:PackedVector2Array = []
		for y:int in range(pixels.get_height()):
			for x:int in range(pixels.get_width()):
				if pixels.get_pixel(x,y).a <= 0.1: continue
				for corner:Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
					points.append(Vector2(x,y)+corner-image.texture.get_size()*0.5+image.offset)
		var hull:PackedVector2Array = Geometry2D.convex_hull(points)
		if hull.size()>1 and hull[0]==hull[-1]: hull.remove_at(hull.size()-1)
		if mirrored:
			for i:int in range(hull.size()): hull[i].x = -hull[i].x
			hull.reverse()
		var shape := ConvexPolygonShape2D.new()
		shape.points = hull
		_weapon_shapes[key] = shape
	attack_shape = _weapon_shapes[key]
	attack_collider.set_deferred("shape",attack_shape)
func update_idle_facing() -> void:
	if not is_multiplayer_authority(): return
	var travel:Vector2 = velocity if velocity.length_squared()>1.0 else direction
	if absf(travel.x)>0.01: _idle_left = travel.x<0.0
func presentation_left() -> bool:
	return _swing_left_facing if _swing_pending or swing_visual_left>0.0 else _idle_left
func blade_motion_direction() -> Vector2:
	if is_multiplayer_authority():
		var travel:Vector2 = velocity if velocity.length_squared()>1.0 else direction
		if travel.length_squared()>0.001: _blade_heading = travel.normalized()
	return _blade_heading
func weapon_rotation(phase:float) -> float:
	if part_kind == 2: return blade_motion_direction().angle()+PI*0.25
	var angle:float = PI*0.25+lerpf(-1.2,0.8,phase)
	if part_kind == 0: angle = lerpf(-0.9*_swing_charge,angle,smoothstep(0.0,0.35,phase))
	return (-1.0 if presentation_left() else 1.0)*angle
func weapon_transform(phase:float) -> Transform2D:
	ensure_attack_shape()
	var parent:Node2D = image.get_parent()
	var position_local:Vector2 = _rest_image_position
	if part_kind == 0:
		position_local += parent.to_local(parent.to_global(Vector2.ZERO)+Vector2.UP*6.0*_swing_charge*(1.0-smoothstep(0.0,0.35,phase)))
	if part_kind == 2:
		position_local += parent.to_local(parent.to_global(Vector2.ZERO)+blade_motion_direction()*14.0*sin(PI*phase))
	return parent.global_transform*Transform2D(weapon_rotation(phase),image.scale,0.0,position_local)
func attack_trigger_reach() -> float:
	ensure_attack_shape()
	var radius:float = 0.0
	for point:Vector2 in attack_shape.points:
		radius = maxf(radius,(point*image.global_scale).length())
	return minf(sword_reach,radius+(14.0 if part_kind == 2 else 0.0))
func phase_can_hit(phase:float) -> bool:
	return phase >= 0.12 and phase <= (0.68 if part_kind == 2 else 0.85)
func cancel_attack() -> void:
	_swing_pending = false
	swing_left = 0.0
	if is_instance_valid(attack_collider): attack_collider.set_deferred("disabled",true)
func swing_damage_multiplier() -> float:
	if part_kind == 1: return hilt_damage_multiplier
	if part_kind == 2: return blade_damage_multiplier
	return lerpf(charge_min_damage,charge_max_damage,pow(clampf(_swing_charge,0,1),2.0))
func query_weapon_pose(pose:Transform2D) -> int:
	if not _swing_pending or not can_act() or repairing: return 0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = attack_shape
	query.transform = pose
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var hits:int = 0
	for contact:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,128):
		var collider:Node = contact.collider
		var node:Node = collider
		while is_instance_valid(node) and not node is ball: node = node.get_parent()
		if not node is ball: continue
		var target:ball = node as ball
		# Only actual hurtboxes count, never another weapon's attack area or body-radius fallback.
		if collider != target.self_hurtbox or not U.enemy(self,target) or same_family(target): continue
		var id:int = target.get_instance_id()
		if _swing_hit_ids.has(id): continue
		if not U.line_clear(self,global_position,ball.body_point(target,global_position)): continue
		var multiplier:float = swing_damage_multiplier()
		if part_kind == 0 and _swing_hit_ids.size()>0: multiplier *= 0.35
		_swing_hit_ids[id] = true
		var hit_point:Vector2 = ball.body_point(target,global_position)
		if damage_with_impact_sound(target,attack_damage(multiplier),hit_point):
			hits += 1
			var push:float = hilt_knockback if part_kind == 1 else 0.0 if part_kind == 2 else sword_knockback*lerpf(charge_min_push,charge_max_push,clampf(_swing_charge,0,1))
			if push>0 and is_instance_valid(target) and target.health>0 and target.can_receive_negative_effects():
				target.apply_knockback(swing_heading,push,300.0,0.0,0.0,{"lock_control":false,"source":self,"stop_on_character":false,"collision_damage":0.0})
			emit_effect("swing",hit_point)
	return hits
func sample_attack_motion(next_phase:float) -> int:
	var pose:Transform2D = weapon_transform(next_phase)
	var previous_phase:float = _last_attack_phase
	var travel:float = _last_attack_pose.origin.distance_to(pose.origin)
	var turn:float = absf(angle_difference(_last_attack_pose.get_rotation(),pose.get_rotation()))
	# Adaptive substeps preserve thin weapon contact during rotation and fast translation.
	var count:int = maxi(1,int(ceil(maxf(maxf(travel/2.0,turn/0.04),absf(next_phase-previous_phase)/0.04))))
	count = mini(count,256)
	var hits:int = 0
	var previous_root_shift:Vector2 = _last_attack_pose.origin-weapon_transform(previous_phase).origin
	for index:int in range(count+1):
		var fraction:float = float(index)/float(count)
		var phase:float = lerpf(previous_phase,next_phase,fraction)
		if phase_can_hit(phase):
			var sample:Transform2D = weapon_transform(phase)
			sample.origin += previous_root_shift*(1.0-fraction)
			hits += query_weapon_pose(sample)
	_last_attack_pose = pose
	_last_attack_phase = next_phase
	attack_collider.set_deferred("disabled",not phase_can_hit(next_phase))
	return hits
func advance_attack(delta:float) -> void:
	if not _swing_pending:
		swing_visual_left = maxf(0.0,swing_visual_left-delta)
		return
	if not can_act() or repairing:
		cancel_attack()
		return
	_swing_elapsed = minf(attack_duration(),_swing_elapsed+delta)
	var phase:float = clampf(_swing_elapsed/attack_duration(),0.0,1.0)
	swing_left = maxf(0.0,attack_duration()-_swing_elapsed)
	swing_visual_left = swing_left
	sample_attack_motion(phase)
	if phase >= 1.0:
		cancel_attack()
		if _split_requested: call_deferred("split_sword")
func resolve_swing() -> int:
	# Compatibility/debug entry: test only the current active collision pose, never all enemies in a cone.
	if not _swing_pending or not phase_can_hit(_last_attack_phase): return 0
	return query_weapon_pose(weapon_transform(_last_attack_phase))
func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if _swing_pending and can_act() and not repairing:
		sample_attack_motion(_last_attack_phase)

func get_debug_attack_regions() -> Array[Dictionary]:
	if health <= 0 or repairing or swing_visual_left <= 0.0: return []
	if is_multiplayer_authority() and not _swing_pending: return []
	var phase:float = clampf(1.0-swing_visual_left/attack_duration(),0.0,1.0)
	if not phase_can_hit(phase): return []
	var pose:Transform2D = weapon_transform(phase)
	var points:PackedVector2Array = []
	for point:Vector2 in attack_shape.points: points.append(pose*point)
	return [{"shape":"polygon","points":points,"damage":attack_damage(swing_damage_multiplier()),"kind":"wood_weapon_collision"}]
func take_damage(amount:float,ignore_block:bool = false) -> void:
	if is_broken() and touching_workbench(): amount *= 0.5
	super.take_damage(amount,ignore_block)
func spend_durability(amount:int) -> void:
	if is_broken() or durability <= 0 or amount <= 0: return
	durability = maxi(0,durability-amount)
	if durability == 0:
		_split_requested = true
		if not _swing_pending: call_deferred("split_sword")
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if health <= 0 and is_broken() and is_instance_valid(workbench): workbench.break_bench()
	if is_multiplayer_authority() and health > 0 and amount > 0 and not is_broken():
		spend_durability(clampi(int(ceil(amount/maxf(durability_damage_step,1.0))),1,5))
		if _split_requested:
			cancel_attack()
			call_deferred("split_sword")
func same_family(target:ball) -> bool:
	return not sword_family.is_empty() and target.get_script() == get_script() and target.sword_family == sword_family
func nearest_foe() -> ball:
	var best:ball
	var distance:float = INF
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,target) or same_family(target) or not target.is_combat_lockable(): continue
		var d:float = global_position.distance_squared_to(ball.body_point(target,global_position))
		if d < distance:
			distance = d
			best = target
	return best
func touching_workbench() -> bool:
	return not bench_destroyed and is_broken() and dock_delay <= 0.0 and is_instance_valid(workbench) and workbench.touching(self)
func ensure_workbench() -> void:
	if bench_destroyed or sword_family.is_empty() or not is_broken(): return
	if not is_instance_valid(workbench):
		for node:Node in get_tree().get_nodes_in_group("MCSwordWorkbench"):
			if node.family == sword_family:
				workbench = node
				break
	if not is_instance_valid(workbench):
		workbench = BENCH.new()
		workbench.family = sword_family
		workbench.repair_duration = repair_duration
		workbench.heal_ratio = bench_heal_ratio
		workbench.set_multiplayer_authority(get_multiplayer_authority())
		preload("res://scripts/effects/我的世界/mc_explosion.gd").runtime_container(self).add_child(workbench)
		workbench.global_position = repair_anchor
	workbench.bind_piece(self)
func apply_part_geometry() -> void:
	if _geometry_kind == part_kind or not is_instance_valid(image): return
	_geometry_kind = part_kind
	image.texture = SWORD if part_kind == 0 else HILT if part_kind == 1 else BLADE
	for path:String in ["CollisionShape2D","hitbox/CollisionShape2D","hurtbox/CollisionShape2D"]:
		var node:CollisionShape2D = get_node(path)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(90,110) if part_kind == 0 else Vector2(58,58)
		node.set_deferred("shape",shape)
func set_migrated_health(value:int,maximum:int) -> void:
	Max_health = maximum
	default_properties["Max_health"] = maximum
	set_meta("death_return_restore",true)
	health = value
	remove_meta("death_return_restore")
## A copy is a whole fresh sword: copying a split hilt/blade uses the whole sword health.
func character_copy_template_stats(stats:Dictionary) -> Dictionary:
	if part_kind != 0 and full_max_health > 0: stats["Max_health"] = full_max_health
	return stats
func split_sword() -> void:
	if not is_multiplayer_authority() or not _split_requested or is_broken() or health <= 0 or is_queued_for_deletion(): return
	full_max_health = Max_health
	var prior_health:int = health
	var heading:Vector2 = direction.normalized() if direction.length_squared()>0.001 else Vector2.RIGHT
	repair_anchor = global_position
	bench_destroyed = false
	sword_family = str(get_path())+":"+str(Time.get_ticks_usec())
	part_kind = 1
	_split_requested = false
	_swing_pending = false
	swing_left = 0.0
	player_control_action_cancelled(0)
	dock_delay = 0.5
	set_migrated_health(maxi(1,int(ceil(prior_health*0.5))),maxi(1,int(ceil(full_max_health*0.5))))
	direction = heading.orthogonal()
	apply_part_geometry()
	ensure_workbench()
	var scene:PackedScene = load("res://scenes/characters/我的世界/木剑.tscn")
	var blade:Node2D = scene.instantiate()
	blade.part_kind = 2
	blade.durability = 0
	blade.Team = Team
	blade.full_max_health = full_max_health
	blade.Max_health = maxi(1,int(floor(full_max_health*0.5)))
	blade.Damage = int(default_properties.get("Damage",Damage))
	blade.Speed = float(default_properties.get("Speed",Speed))
	blade.sword_family = sword_family
	blade.repair_anchor = repair_anchor
	blade.repair_duration = repair_duration
	blade.bench_heal_ratio = bench_heal_ratio
	blade.dock_delay = 0.5
	blade.direction = -direction
	blade.position = get_parent().to_local(repair_anchor)
	blade.name = Game.return_random_name(blade)
	blade.set_multiplayer_authority(get_multiplayer_authority())
	# Fragments are independent bodies, but still one original roster entry.
	get_tree().current_scene.bind_battle_lifecycle(blade,self)
	get_parent().add_child(blade,true)
	blade.set_migrated_health(maxi(1,int(floor(prior_health*0.5))),blade.Max_health)
	blade.apply_part_geometry()
	blade.ensure_workbench()
	blade.add_to_group("BattleTransient")
	move_and_collide(direction*8.0)
	blade.move_and_collide(blade.direction*8.0)
	play_sword_transformation(repair_anchor)
	emit_sword_audio("entity.item.break",repair_anchor,-6.0)
	if multiplayer.has_multiplayer_peer():
		_new5_visual.rpc(network_visual_state())
		blade.call_deferred("send_fragment_state")
func send_fragment_state() -> void:
	if multiplayer.has_multiplayer_peer(): _new5_visual.rpc(network_visual_state())
func step_part(delta:float) -> void:
	dock_delay = maxf(0,dock_delay-delta)
	swing_cooldown = maxf(0,swing_cooldown-delta)
	_part_recovery_left = maxf(0,_part_recovery_left-delta)
	sword_charge = 0.0
	ensure_workbench()
	if not can_act():
		cancel_attack()
		return
	advance_attack(delta)
	if is_player_controlled() or dock_delay > 0.0 or _part_recovery_left > 0.0: return
	var target:ball = nearest_foe()
	if is_instance_valid(target) and global_position.distance_to(ball.body_point(target,global_position)) <= attack_trigger_reach()+U.radius(target): begin_swing()
func start_repair() -> bool:
	# Kept as a player-action query; only the bench can advance the two-piece timer.
	return touching_workbench() and workbench.is_materialized()
func cancel_repair() -> void:
	repairing = false
	repair_left = 0.0
func finish_repair() -> void:
	if part_kind != 1 or not is_instance_valid(workbench): return
	workbench.complete_repair()
func reform_with(other:ball) -> void:
	if part_kind != 1 or not is_instance_valid(other) or health <= 0 or other.health <= 0: return
	var combined:int = mini(full_max_health,int(health)+int(other.health))
	var point:Vector2 = ball.body_point(workbench,global_position)
	part_kind = 0
	durability = MAX_DURABILITY
	set_migrated_health(combined,full_max_health)
	global_position = point
	repairing = false
	repair_left = 0.0
	player_control_action_cancelled(0)
	swing_left = 0.0
	_swing_pending = false
	successful_repairs += 1
	sword_family = ""
	apply_part_geometry()
	other.queue_free() # consumed, not killed: no death effects or kill credit
	play_sword_transformation(global_position)
	emit_sword_audio("block.crafter.craft",point,-6.0)
	emit_sword_audio("entity.breeze.deflect",point,-4.0)
	workbench.queue_free()
	workbench = null
	if multiplayer.has_multiplayer_peer(): _new5_visual.rpc(network_visual_state())
func move(speed_value:float,delta:float) -> void:
	if not active(): return
	if is_broken() and touching_workbench() and workbench.is_materialized(): super.stand(delta)
	else: super.move(speed_value,delta)
func Attack() -> void:
	Attacking = false
	if is_broken(): begin_swing()
func Skill() -> void:
	Using_Skill = false
func player_control_action_ids() -> Array[StringName]:
	# This Skill() is a state-machine placeholder, not a second weapon action.
	return [&"Attack"]
func player_control_action_hold_repeat_allowed(action_index:int) -> bool:
	return is_broken() and action_index == 0
func player_control_action(action_index:int) -> void:
	if action_index != 0 or not is_player_controlled() or not is_multiplayer_authority(): return
	if is_broken():
		if can_act(): begin_swing()
	elif (can_act() or can_keep_charging_through_knockback()) and not _swing_pending:
		_manual_release_pending = false
		_manual_charging = true

func player_control_action_released(action_index:int) -> void:
	if action_index != 0 or not _manual_charging: return
	_manual_charging = false
	if can_act() and not is_broken():
		if not begin_swing(): sword_charge = 0.0
	elif can_keep_charging_through_knockback() and sword_charge+0.00001 >= minimum_charge_time/maxf(charge_duration,0.1):
		# Releasing while being pushed preserves this charge and swings once
		# control returns; it never attacks through the displacement lock.
		_manual_release_pending = true
	else:
		player_control_action_cancelled(0)

func player_control_action_cancelled(_action_index:int) -> void:
	_manual_charging = false
	_manual_release_pending = false
	sword_charge = 0.0

func charge_pose() -> Transform2D:
	ensure_attack_shape()
	var charge:float = clampf(sword_charge,0,1)
	var shake:float = sin(_view_clock*85.0)*0.025 if charge >= 0.999 else 0.0
	var angle:float = (-1.0 if presentation_left() else 1.0)*(-0.9*charge+shake)
	var parent:Node2D = image.get_parent()
	var jitter:Vector2 = Vector2(sin(_view_clock*97.0),cos(_view_clock*89.0))*0.45 if charge >= 0.999 else Vector2.ZERO
	var offset:Vector2 = parent.to_local(parent.to_global(Vector2.ZERO)+Vector2.UP*6.0*charge+jitter)
	return parent.global_transform*Transform2D(angle,image.scale,0.0,_rest_image_position+offset)
func visual_mob() -> void:
	if not is_instance_valid(image): return
	apply_part_geometry()
	image.texture = SWORD if part_kind == 0 else HILT if part_kind == 1 else BLADE
	update_idle_facing()
	set_character_visual_flip_h(presentation_left() if part_kind != 2 else false)
	ensure_attack_shape()
	image.position = _rest_image_position
	if swing_visual_left > 0.0:
		var phase:float = clampf(1.0-swing_visual_left/attack_duration(),0,1)
		var parent:Node2D = image.get_parent()
		image.position = parent.to_local(weapon_transform(phase).origin)
		image.rotation = weapon_rotation(phase)
	elif part_kind == 2:
		image.rotation = blade_motion_direction().angle()+PI*0.25
	elif part_kind == 0:
		var pose:Transform2D = charge_pose()
		image.position = image.get_parent().to_local(pose.origin)
		image.rotation = (-1.0 if presentation_left() else 1.0)*(-0.9*clampf(sword_charge,0,1)+(sin(_view_clock*85.0)*0.025 if sword_charge>=0.999 else 0.0))
	else:
		image.rotation = 0.0
	if not _status_removed:
		side_status_remove_permanent("left","mc_frontier")
		_status_removed = true
func visual_state() -> Dictionary:
	return {"idle_left":_idle_left,"swing_left_facing":_swing_left_facing,"blade_heading":blade_motion_direction(),"bench_destroyed":bench_destroyed,"bench_age":workbench.age if is_instance_valid(workbench) else 0.0,"part":part_kind,"family":sword_family,"full_max":full_max_health,"dock_delay":dock_delay,"time":clock,"durability":durability,"charge":sword_charge,"attack_charge":_swing_charge,"manual_charge":_manual_charging,"repairing":repairing,"repair":repair_left,"anchor":repair_anchor,"swing":swing_visual_left,"heading":swing_heading}
func accept_visual(data:Dictionary) -> void:
	var old_family:String = sword_family
	var was_destroyed:bool = bench_destroyed
	super.accept_visual(data)
	_idle_left = bool(data.get("idle_left",_idle_left))
	_swing_left_facing = bool(data.get("swing_left_facing",_swing_left_facing))
	_blade_heading = data.get("blade_heading",_blade_heading)
	part_kind = clampi(int(data.get("part",part_kind)),0,2)
	sword_family = str(data.get("family",sword_family))
	bench_destroyed = bool(data.get("bench_destroyed",false)) or (was_destroyed and old_family == sword_family)
	full_max_health = int(data.get("full_max",full_max_health))
	dock_delay = float(data.get("dock_delay",dock_delay))
	durability = clampi(int(data.get("durability",MAX_DURABILITY)),0,MAX_DURABILITY)
	sword_charge = clampf(float(data.get("charge",0)),0,1)
	_swing_charge = clampf(float(data.get("attack_charge",0)),0,1)
	_manual_charging = bool(data.get("manual_charge",false))
	repairing = bool(data.get("repairing",false))
	repair_left = float(data.get("repair",0))
	repair_anchor = data.get("anchor",global_position)
	swing_visual_left = float(data.get("swing",0))
	swing_heading = data.get("heading",Vector2.RIGHT)
	apply_part_geometry()
	if is_broken() and bench_destroyed:
		if is_instance_valid(workbench): workbench.shatter_local()
	elif is_broken():
		ensure_workbench()
		workbench.age = clampf(float(data.get("bench_age",0.0)),0.0,workbench.materialize_duration)
		workbench.update_opacity()
	elif is_instance_valid(workbench):
		workbench.queue_free()
		workbench = null
func client_visual_step(delta:float) -> void:
	if not is_combat_runtime_active(): return
	swing_visual_left = maxf(0.0,swing_visual_left-delta)
	if repairing: repair_left = maxf(0,repair_left-delta)
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_WOODEN_SWORD")

func lose_workbench() -> void:
	if multiplayer.has_multiplayer_peer(): _bench_lost.rpc(sword_family)
	_bench_lost(sword_family)
@rpc("authority","call_remote","reliable")
func _bench_lost(family:String) -> void:
	if sword_family != family: return
	bench_destroyed = true
	repairing = false
	repair_left = 0.0
	if is_instance_valid(workbench): workbench.shatter_local()
func Die() -> void:
	if is_broken() and is_instance_valid(workbench): workbench.break_bench()
	if _death_sound_done: return
	repairing = false
	ITEM_DEATH.spawn(self)
	super.Die()
