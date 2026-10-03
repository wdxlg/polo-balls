extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")
## Five independent combatants share a cohort, not a mortal master.
## Morphs conserve integer HP/capacity, including fair remainder allocation.
const BAT_TEXTURE = preload("res://Images/characters/我的世界/蝙蝠/fly_00.png")
const BAT_FRAMES = preload("res://Images/characters/我的世界/蝙蝠/bat_fly.tres")
const VAMPIRE_TEXTURE = preload("res://Images/characters/我的世界/蝙蝠/vampire_face.png")
const BAT_AUDIO = preload("res://scripts/characters/我的世界/bat/bat_audio.gd")
const GATHER_NAV = preload("res://scripts/characters/我的世界/bat/bat_gather_navigation.gd")
const TRANSFORM_FX = preload("res://scripts/characters/我的世界/bat/bat_transform_fx.gd")
const SCENE_PATH:String = "res://scenes/characters/我的世界/蝙蝠.tscn"
@export var initial_bat_health:int = 70
@export var initial_count:int = 5
@export var bat_damage:int = 5
@export var vampire_damage:int = 10
@export var vampire_health_per_damage:int = 30
@export_range(0.0,1.0) var feeding_damage_reduction:float = 0.75
@export var bat_speed:float = 90.0
@export var vampire_speed:float = 120.0
@export var bat_duration:float = 12.0
@export var vampire_duration:float = 7.0
@export var detection_range:float = 45.0
@export var bite_cooldown:float = 3.0
@export_range(0.1,2.0,0.1) var attach_duration:float = 2.0
@export var drain_interval:float = 0.5
@export_range(0.05,1.0,0.01) var shield_attack_interval:float = 0.25
@export var gather_speed:float = 220.0
@export var gather_arrival_radius:float = 5.0
@export var gather_min_duration:float = 0.45
var vampire:bool = false
var cohort:Dictionary = {}
var _cohort_collision_peers:Array[WeakRef] = []
var _retired:bool = false
var _redistributing:bool = false
var _cooldown:float = 0.4
# Keep normal and shield clocks separately: switching targets or losing a shield
# must never carry the fast cadence into attacks against bare health.
var _shield_bite_wait:float = 0.25
var _attached_ref:WeakRef
var _attach_offset:Vector2 = Vector2.ZERO
var _drain_wait:float = 0.0
# Independent of the damage cadence: successful drains must not renew the latch.
var _attach_left:float = 0.0
var _last_host_position:Vector2 = Vector2.ZERO
var _approaching:bool = false
var _animation_time:float = 0.0
var _animation_frame:int = -1
var _gather_path:Array[Vector2] = []
var _gather_repath:float = 0.0
var _gather_hits:Dictionary = {}
var _gather_saved_mask:int = -1

func get_preview_texture() -> Texture2D: return BAT_TEXTURE
func _ready() -> void:
	mc_audio_role = "bat"
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	motion_blur_enabled = false
	motion_blur_effect_strength = 0.0
	motion_stretch_enabled = false
	AfterImage_Speed = 0.0
	super._ready()
	add_to_group("MCBat")
	_apply_form(false)
	# Deferred until World has applied team, setup identity and spawn position.
	if cohort.is_empty(): call_deferred("initialize_swarm")

func initialize_swarm() -> void:
	if not cohort.is_empty() or _retired or health <= 0 or not is_multiplayer_authority(): return
	# Formation previews (and previews being freed) must not leave a real swarm behind.
	if is_queued_for_deletion() or has_meta("rotation_prestart_preview"): return
	var world:Node = get_tree().current_scene
	var victory_key:String = "team:"+Team if not Team.is_empty() else "solo_instance:"+str(get_instance_id())
	var presentation_key:String = "team:"+Team if not Team.is_empty() else "solo:"+str(get_instance_id())
	if world.has_method("_victory_side_key_for_character"):
		victory_key = world.call("_victory_side_key_for_character",self)
		presentation_key = world.call("return_ball_side_key",self)
	cohort = {"members":[weakref(self)],"left":bat_duration,"frame":-1,"key":victory_key,"presentation":presentation_key,"id":get_instance_id()}
	_mark_identity(self)
	for i:int in range(1,maxi(initial_count,1)):
		_spawn_member(initial_bat_health,initial_bat_health,i,maxi(initial_count,1))

func _mark_identity(unit:ball) -> void:
	unit.set_meta("mc_bat_cohort",cohort.id)
	unit.set_meta("battle_continuation_victory_side_key",cohort.key)
	unit.set_meta("battle_continuation_presentation_side_key",cohort.presentation)
	unit.set_meta("victory_side_key",cohort.key)
	if has_meta("battle_setup_id"): unit.set_meta("battle_setup_id",get_meta("battle_setup_id"))

func living_members() -> Array:
	var result:Array = []
	for ref:WeakRef in cohort.get("members",[]):
		var unit:Variant = ref.get_ref()
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and not unit._retired and unit.health > 0:
			result.append(unit)
	return result

func _spawn_member(hp:int,capacity:int,index:int,count:int) -> ball:
	var unit:ball = (load(SCENE_PATH) as PackedScene).instantiate() as ball
	unit.manual_controllable_subentity=true # Split members keep independent movement and bite.
	unit.set("cohort",cohort)
	for key:String in ["initial_bat_health","initial_count","bat_damage","vampire_damage","vampire_health_per_damage","feeding_damage_reduction","bat_speed","vampire_speed","bat_duration","vampire_duration","detection_range","bite_cooldown","attach_duration","drain_interval","shield_attack_interval","gather_speed","gather_arrival_radius","gather_min_duration"]:
		unit.set(key,get(key))
	unit.Max_health = capacity
	unit.Team = Team
	unit.name = Game.return_random_name(unit)
	unit.set_multiplayer_authority(get_multiplayer_authority())
	_mark_identity(unit)
	var point:Vector2 = _spawn_point(index,count)
	unit.position = get_parent().to_local(point)
	get_parent().add_child(unit,true)
	unit.call("assign_vitals",hp,capacity)
	unit.direction = Vector2.RIGHT.rotated(TAU*float(index)/float(maxi(count,1)))
	unit.add_to_group("BattleTransient")
	# Symmetric body-only exceptions, including every newly split member.
	# Hitbox/hurtbox layers and collisions with other cohorts stay unchanged.
	for member:ball in living_members():
		preload("res://classes/body_collision_exclusions.gd").add_exception(unit,member)
		preload("res://classes/body_collision_exclusions.gd").add_exception(member,unit)
		unit._cohort_collision_peers.append(weakref(member))
		member._cohort_collision_peers.append(weakref(unit))
	cohort.members.append(weakref(unit))
	return unit

func _forget_cohort_collision_peer(peer:Node) -> void:
	for i:int in range(_cohort_collision_peers.size()-1,-1,-1):
		var other:Variant = _cohort_collision_peers[i].get_ref()
		if not is_instance_valid(other) or other == peer:
			_cohort_collision_peers.remove_at(i)

func _clear_cohort_collision_exceptions() -> void:
	# Remove both RIDs before a merge/death frees a body. Godot otherwise leaves
	# stale exception RIDs on survivors; do not depend on the mutable members list.
	for ref:WeakRef in _cohort_collision_peers:
		var peer:Variant = ref.get_ref()
		if is_instance_valid(peer):
			preload("res://classes/body_collision_exclusions.gd").remove_exception(self,peer)
			preload("res://classes/body_collision_exclusions.gd").remove_exception(peer,self)
			peer._forget_cohort_collision_peer(self)
	_cohort_collision_peers.clear()

func _spawn_point(index:int,count:int) -> Vector2:
	for attempt:int in range(24):
		var angle:float = TAU*float(index)/float(maxi(count,1))+float(attempt)*0.61
		var point:Vector2 = global_position+Vector2.RIGHT.rotated(angle)*(25.0+float(attempt/8)*14.0)
		if mc_position_clear(point,9.0) and mc_line_clear(global_position,point): return point
	return global_position

func mc_enemy(target:Variant) -> bool:
	if is_instance_valid(target) and not cohort.is_empty() and target.get_meta("mc_bat_cohort",-1) == cohort.id: return false
	return super.mc_enemy(target)

func mc_play(event:String,volume:float = -4.0) -> AudioStreamPlayer2D:
	if mc_audio_role == "bat": return BAT_AUDIO.play(self,"entity.bat."+event,global_position,volume)
	return super.mc_play(event,volume)
func mc_ambient_event() -> String: return "ambient"
func on_actual_health_damage_received(amount:float,before:float) -> void:
	if not _redistributing: super.on_actual_health_damage_received(amount,before)

func tick_physics(state:State,delta:float) -> void:
	if _retired: return
	if health <= 0:
		detach()
		super.tick_physics(state,delta)
		return
	if not is_multiplayer_authority() or not is_combat_runtime_active() or Game.now_stop_state: return
	if bool(cohort.get("gathering",false)):
		_tick_gather(state,delta)
		return
	if is_damage_output_disabled():
		detach()
		super.tick_physics(state,delta)
		return
	if cohort.is_empty(): initialize_swarm()
	var members:Array = living_members()
	# Elect a new leader automatically when the original bat dies.
	if not members.is_empty() and members[0] == self and int(cohort.frame) != Engine.get_physics_frames():
		cohort.frame = Engine.get_physics_frames()
		cohort.left = maxf(float(cohort.left)-delta,0.0)
		# Automatic morphs wait for every member's current feeding to end.
		# The independent two-second latch deadline still ends each feeding normally.
		var feeding:bool = false
		for member:Node2D in members:
			if member.feeding_guard_active(): feeding = true
		if float(cohort.left) <= 0.0 and not feeding:
			if vampire: split_swarm()
			else: fuse_swarm()
	if bool(cohort.get("gathering",false)):
		_tick_gather(state,delta)
		return
	_cooldown = maxf(_cooldown-delta,0.0)
	_shield_bite_wait = maxf(_shield_bite_wait-delta,0.0)
	_approaching = false
	if dizziness or is_damage_output_disabled(): detach()
	var host:Variant = attached_target()
	if host != null:
		_attach_left = maxf(_attach_left-maxf(delta,0.0),0.0)
		# Expire before applying any drain on this tick, including oversized deltas.
		if _attach_left <= 0.000001 or not mc_enemy(host) or _target_has_shield(host) or host.global_position.distance_to(_last_host_position) > 100.0 or not mc_line_clear(global_position,host.global_position):
			detach()
		else:
			_drain_wait -= delta
			if _drain_wait <= 0.0:
				# Respect the target's real damage routing (dodge, immunity, etc.).
				if drain_target(host) <= 0 or not mc_enemy(host): detach()
				else: _reset_drain_waits()
			if is_instance_valid(host): _last_host_position = host.global_position
	elif _attached_ref != null:
		detach()
	if _attached_ref == null and not dizziness and not is_player_controlled():
		var target:ball = mc_nearest(delta)
		if target != null and _bite_ready(target):
			var point:Vector2 = target_surface(target)
			var distance:float = global_position.distance_to(point)
			if global_position.distance_to(ball.body_point(target,global_position)) <= detection_range and mc_line_clear(global_position,ball.body_point(target,global_position)):
				if distance <= (10.0 if vampire else 8.0): begin_bite(target)
				else:
					_approaching = true
					direction = global_position.direction_to(ball.body_point(target,global_position))
	super.tick_physics(state,delta)

func controlled_attack_action() -> void:
	if not is_player_controlled() or not mc_live() or dizziness or _retired or not has_player_control_aim() or bool(cohort.get("gathering",false)): return
	var point:Vector2=player_control_aim_world_position()
	var chosen:ball=null
	var nearest:float=INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw) or not raw.is_combat_lockable(): continue
		var distance:float=ball.body_point(raw,point).distance_to(point)
		if distance<=U.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	if chosen!=null: begin_bite(chosen)


func target_surface(target:ball) -> Vector2:
	var collision:CollisionShape2D = target.collision_shape_2d
	if collision == null or collision.shape == null: return ball.body_point(target,global_position)
	var local:Vector2 = collision.to_local(global_position)
	if collision.shape is RectangleShape2D:
		var half:Vector2 = (collision.shape as RectangleShape2D).size*0.5
		return collision.to_global(local.clamp(-half,half))
	if collision.shape is CircleShape2D:
		return collision.to_global(local.limit_length((collision.shape as CircleShape2D).radius))
	return ball.body_point(target,global_position)

func attached_target() -> Variant:
	var target:Variant = _attached_ref.get_ref() if _attached_ref != null else null
	return target if is_instance_valid(target) and not target.is_queued_for_deletion() else null

func _target_has_shield(target:Variant) -> bool:
	return is_instance_valid(target) and target is ball and not target.is_queued_for_deletion() and target.health > 0 and target.block > 0

func _shield_interval() -> float:
	return maxf(shield_attack_interval,0.05)

func _bite_ready(target:Variant) -> bool:
	return _cooldown <= 0.0 or (_target_has_shield(target) and _shield_bite_wait <= 0.0)

func _reset_drain_waits() -> void:
	_drain_wait = maxf(drain_interval,0.1)

func begin_bite(target:Variant) -> void:
	# Repeated bite requests cannot replace the host or restart an active latch.
	if _attached_ref != null or bool(cohort.get("gathering",false)): return
	if not mc_live() or dizziness or not mc_enemy(target) or not _bite_ready(target): return
	if global_position.distance_to(target_surface(target)) > (10.0 if vampire else 8.0): return
	if global_position.distance_to(ball.body_point(target,global_position)) > detection_range: return
	if not mc_line_clear(global_position,ball.body_point(target,global_position)): return
	# Failed shield bites do not latch or grant feeding protection/growth.
	_cooldown = maxf(bite_cooldown,0.0)
	_shield_bite_wait = _shield_interval()
	if drain_target(target) <= 0 or not mc_enemy(target): return
	_attached_ref = weakref(target)
	_attach_left = clampf(attach_duration,0.1,2.0)
	_attach_offset = target.to_local(target_surface(target))
	Repel = Vector2.ZERO
	_reset_drain_waits()
	_last_host_position = target.global_position
	preload("res://classes/body_collision_exclusions.gd").add_exception(self,target)
	# Cancel an earlier unlocked push as soon as a real latch succeeds.
	# Controllers preserve any genuine unconditional stun through the same hook.
	for child:Node in get_children():
		if child.has_method("respect_target_displacement_immunity"):
			child.call("respect_target_displacement_immunity")

func drain_target(target:Variant) -> int:
	if not mc_live() or dizziness or not mc_enemy(target): return 0
	# Measure with health_loss_reading(): damage absorbed by infinite-health targets
	# (and the timed no-death floor) is real damage dealt, so it feeds the bat too.
	var before:int = int(target.health)
	var before_reading:float = target.health_loss_reading()
	var target_ref:WeakRef = weakref(target)
	target.receive_positional_damage(attack_damage(),global_position,false,self)
	var alive_target:Variant = target_ref.get_ref()
	var loss:float = before_reading - float(alive_target.health_loss_reading()) if is_instance_valid(alive_target) else float(before)
	var actual:int = maxi(int(round(loss)),0)
	if actual <= 0 or health <= 0 or _retired: return 0
	# Both forms grow by actual HP damage; vampire retains its 2x healing.
	Max_health += actual
	default_properties["Max_health"] = Max_health
	health = mini(Max_health,int(health)+actual*(2 if vampire else 1))
	BAT_AUDIO.play(self,"entity.generic.eat",global_position,feeding_volume_db(actual))
	return actual

static func feeding_volume_db(actual_damage:int) -> float:
	# Louder than the old -11 dB bite; actual HP loss, not nominal/overkill damage.
	# +1 dB per doubling, capped at the native SFX ceiling to limit loud swarms.
	return clampf(-3.0+log(float(maxi(actual_damage,1)))/log(2.0),-3.0,2.0)

func _notify_damage_camera_feedback(actual_damage:float,blocked:bool = false,focus_damage:float = -1.0,focus_origin:Vector2 = Vector2.INF) -> void:
	# Redistribution is a state transfer, not a hit (150 -> 30 is not 120 damage).
	if _redistributing: return
	super._notify_damage_camera_feedback(actual_damage,blocked,focus_damage,focus_origin)

func detach() -> void:
	var target:Variant = attached_target()
	if target != null: preload("res://classes/body_collision_exclusions.gd").remove_exception(self,target)
	if _attached_ref != null:
		_cooldown = maxf(_cooldown,bite_cooldown)
		_shield_bite_wait = _shield_interval()
		direction = Vector2.RIGHT.rotated(_mc_rng.randf_range(0.0,TAU))
	_attached_ref = null
	_attach_left = 0.0
	_drain_wait = 0.0

func is_knockback_displacement_immune() -> bool:
	return feeding_guard_active()

func apply_knockback(knockback_direction:Vector2,knockback_distance:float,knockback_speed:float = 700.0,wall_bounce_strength:float = 0.0,stun_duration:float = 0.0,options:Dictionary = {}) -> Node:
	if not feeding_guard_active():
		return super.apply_knockback(knockback_direction,knockback_distance,knockback_speed,wall_bounce_strength,stun_duration,options)
	# Do not create the generic displacement/controller lock during feeding.
	# Real unconditional stun still applies; collision-only stun cannot trigger
	# when the immune bat never travels into a wall/body.
	if stun_duration <= 0.0 or bool(options.get("stun_only_on_collision",false)): return null
	var stun:Node = super.apply_knockback(Vector2.ZERO,0.0,0.0,0.0,stun_duration,options)
	if is_instance_valid(stun): detach()
	return stun

func stand(delta:float) -> void:
	# Hurt/stand must follow the host too, not consume legacy Repel or crowd push.
	if feeding_guard_active():
		Repel = Vector2.ZERO
		move(Speed,delta)
		return
	super.stand(delta)

func move(speed:float,delta:float) -> void:
	if bool(cohort.get("gathering",false)):
		_move_gather(delta)
		return
	var target:Variant = attached_target()
	if target != null:
		var point:Vector2 = target.to_global(_attach_offset)
		if not mc_line_clear(global_position,point) or not mc_position_clear(point,7.0 if vampire else 4.0):
			detach()
		else:
			# Follow the body using physics, never teleport through terrain.
			move_and_collide(point-global_position)
			Repel = Vector2.ZERO
			velocity = Vector2.ZERO
			return
	super.move(speed*(1.8 if _approaching else 1.0),delta)

func _complete_fusion() -> void:
	if vampire or not mc_live() or cohort.is_empty(): return
	var members:Array = living_members()
	if members.is_empty() or members[0] != self: return
	detach()
	var total_hp:int = 0
	var total_max:int = 0
	for unit:ball in members:
		total_hp += int(unit.health)
		total_max += unit.Max_health
	var merge_point:Vector2 = cohort.get("gather_point",global_position)
	for unit:ball in members: unit.call("_end_gather_member")
	cohort.gathering = false
	global_position = merge_point
	# Keep the leader alive throughout the transaction so victory cannot fire between forms.
	assign_vitals(total_hp,total_max)
	for unit:ball in members:
		if unit != self: unit.call("retire_for_merge")
	cohort.members = [weakref(self)]
	cohort.left = maxf(vampire_duration,0.1)
	_apply_form(true)
	play_transform_effect(true)

static func split_count(hp:int,initial_hp:int) -> int:
	return 0 if hp <= 0 else maxi(1,int(float(hp)/float(maxi(initial_hp,1))))
static func share(total:int,count:int,index:int) -> int:
	return int(total/maxi(count,1))+(1 if index < total%maxi(count,1) else 0)

func split_swarm() -> void:
	if not vampire or not mc_live() or cohort.is_empty(): return
	detach()
	var total_hp:int = int(health)
	var total_max:int = Max_health
	var count:int = split_count(total_hp,initial_bat_health)
	if count <= 0: return
	cohort.members = [weakref(self)]
	# Spawn before shrinking the retained unit, preserving a live side at every point.
	for i:int in range(1,count):
		_spawn_member(share(total_hp,count,i),share(total_max,count,i),i,count)
	assign_vitals(share(total_hp,count,0),share(total_max,count,0))
	cohort.left = maxf(bat_duration,0.1)
	_apply_form(false)
	play_transform_effect(false)

func assign_vitals(hp:int,capacity:int) -> void:
	var was_suppressed:bool = health_bar.suppress_floating_text if health_bar != null else false
	var was_instant:bool = health_bar.force_instant_update_once if health_bar != null else false
	if health_bar != null:
		health_bar.suppress_floating_text = true
		health_bar._kill_bar_tween(health_bar.health_bar)
		health_bar.force_instant_update_once = true
	var was_redistributing:bool = _redistributing
	_redistributing = true
	Max_health = capacity
	default_properties["Max_health"] = capacity
	health = hp
	_redistributing = was_redistributing
	if health_bar != null:
		health_bar.suppress_floating_text = was_suppressed
		health_bar.force_instant_update_once = was_instant

func _apply_form(as_vampire:bool) -> void:
	mc_stop_ambient()
	vampire = as_vampire
	mc_audio_role = "evoker" if vampire else "bat"
	Damage = vampire_damage if vampire else bat_damage
	Speed = vampire_speed if vampire else bat_speed
	default_properties["Damage"] = Damage
	default_properties["Speed"] = Speed
	if image is Sprite2D:
		image.texture = VAMPIRE_TEXTURE if vampire else BAT_TEXTURE
		image.scale = Vector2.ONE*(0.6 if vampire else 0.55)
		image.offset = Vector2.ZERO
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_animation_frame = -1
	_animation_time = 0.0
	var size:Vector2 = Vector2(66,66) if vampire else Vector2(49,34)
	for shape_node:CollisionShape2D in [collision_shape_2d,self_hitbox.get_node("CollisionShape2D"),self_hurtbox.get_node("CollisionShape2D")]:
		var shape := RectangleShape2D.new()
		shape.size = size
		shape_node.set_deferred("shape",shape)
	_cooldown = 0.5
	_shield_bite_wait = _shield_interval()
	_mc_ambient_wait = 2.0
	refresh_character_ground_shadow()
	if health_bar != null:
		health_bar.position.y = -90.0 if vampire else -80.0
		health_bar.health_changed.emit(health,health,Max_health,false)

func retire_for_merge() -> void:
	if _retired: return
	_retired = true
	detach()
	_clear_cohort_collision_exceptions()
	mc_stop_ambient()
	hide()
	set_meta("ignore_combat_targeting",true)
	if is_in_group("Ball"): remove_from_group("Ball")
	queue_free()

func is_combat_targetable() -> bool:
	return not _retired and super.is_combat_targetable()
func Die() -> void:
	detach()
	super.Die()
func _exit_tree() -> void:
	detach()
	_clear_cohort_collision_exceptions()
	super._exit_tree()

# Native Minecraft Wiki animation frames with their original 20ms timing.
# Texture changes only: no whole-image stretch, oscillation or generated motion.
func _process(delta:float) -> void:
	advance_native_animation(delta)
func advance_native_animation(delta:float) -> void:
	if vampire or _retired or health <= 0 or not is_instance_valid(image): return
	if get_tree().paused or Game.now_stop_state or not is_combat_runtime_active(): return
	_animation_time = fmod(_animation_time+maxf(delta,0.0),0.5)
	var frame:int = mini(int(_animation_time*50.0),BAT_FRAMES.get_frame_count(&"fly")-1)
	if frame != _animation_frame:
		_animation_frame = frame
		image.texture = BAT_FRAMES.get_frame_texture(&"fly",frame)

func vampire_base_damage() -> int:
	return vampire_damage+int(float(maxi(int(health),0))/float(maxi(vampire_health_per_damage,1)))
func attack_damage(multiplier:float = 1.0) -> float:
	# Compute at the hit, not from a delayed timer or maximum HP.
	# Apply the same outgoing modifiers to the HP bonus as to the base attack.
	var bonus:float = float(vampire_base_damage()-vampire_damage) if vampire else 0.0
	return effective_outgoing_damage((float(Damage)+bonus)*maxf(multiplier,0.0))

func feeding_guard_active() -> bool:
	var host:Variant = attached_target()
	return not dizziness and mc_live() and host != null and mc_enemy(host) and not _target_has_shield(host)
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if feeding_guard_active(): damage *= 1.0-feeding_damage_reduction
	super.take_damage(damage,ignore_block)
func receive_spatial_damage(damage:float,damage_space:Variant,ignore_block:bool = false,raw_health:bool = false) -> bool:
	# Raw-health spatial attacks bypass take_damage; normal ones flow through it.
	if raw_health and feeding_guard_active(): damage *= 1.0-feeding_damage_reduction
	return super.receive_spatial_damage(damage,damage_space,ignore_block,raw_health)

func get_debug_detection_regions() -> Array:
	if health <= 0 or _retired: return []
	return [{"shape":"circle","position":global_position,"radius":detection_range,"kind":"bat_lifesteal_detection"}]

func fuse_swarm() -> void:
	if vampire or not mc_live() or cohort.is_empty() or bool(cohort.get("gathering",false)): return
	var members:Array = living_members()
	if members.is_empty() or members[0] != self: return
	var point:Vector2 = Vector2.ZERO
	for member:Node2D in members: point += member.global_position
	point /= float(members.size())
	if not mc_position_clear(point,8.0):
		point = global_position
		for member:Node2D in members:
			if mc_position_clear(member.global_position,8.0):
				point = member.global_position
				break
	if not mc_position_clear(point,8.0):
		cohort.left = 2.0
		return
	cohort.gathering = true
	cohort.gather_point = point
	cohort.gather_elapsed = 0.0
	cohort.gather_frame = -1
	var farthest:float = 0.0
	for member:Node2D in members:
		farthest = maxf(farthest,member.global_position.distance_to(point))
		member._begin_gather_member()
	cohort.gather_timeout = clampf(farthest/maxf(gather_speed,1.0)+4.0,4.0,12.0)

func _begin_gather_member() -> void:
	detach()
	_approaching = false
	_gather_hits.clear()
	_gather_path.clear()
	_gather_repath = 0.0
	if _gather_saved_mask < 0: _gather_saved_mask = collision_mask
	# Keep terrain solid, allow the five real bodies to overlap at their merge point.
	# Damage below is swept against real enemy bodies and filtered by mc_enemy().
	collision_mask = 1
func _end_gather_member() -> void:
	if _gather_saved_mask >= 0: collision_mask = _gather_saved_mask
	_gather_saved_mask = -1
	_gather_path.clear()
	_gather_hits.clear()
	velocity = Vector2.ZERO
	_cooldown = maxf(_cooldown,0.5)

func _tick_gather(state:State,delta:float) -> void:
	var members:Array = living_members()
	if members.is_empty(): return
	if members[0] == self and int(cohort.get("gather_frame",-1)) != Engine.get_physics_frames():
		cohort.gather_frame = Engine.get_physics_frames()
		cohort.gather_elapsed = float(cohort.gather_elapsed)+delta
		if float(cohort.gather_elapsed) > float(cohort.gather_timeout):
			cancel_gather()
			return
	super.tick_physics(state,delta)
	if members[0] == self: try_complete_gather()

func try_complete_gather() -> bool:
	if not bool(cohort.get("gathering",false)) or vampire or not mc_live(): return false
	var members:Array = living_members()
	if members.is_empty() or members[0] != self: return false
	if float(cohort.gather_elapsed) < gather_min_duration: return false
	var point:Vector2 = cohort.gather_point
	for member:Node2D in members:
		if member.global_position.distance_to(point) > gather_arrival_radius: return false
	_complete_fusion()
	return true

func cancel_gather() -> void:
	for member:Node2D in living_members(): member._end_gather_member()
	cohort.gathering = false
	cohort.left = 2.0

func _move_gather(delta:float) -> void:
	var point:Vector2 = cohort.gather_point
	if global_position.distance_to(point) <= 0.5:
		velocity = Vector2.ZERO
		return
	_gather_repath -= delta
	if GATHER_NAV.clear(self,global_position,point):
		_gather_path.assign([point])
	elif _gather_path.is_empty() and _gather_repath <= 0.0:
		_gather_path = GATHER_NAV.route(self,global_position,point)
		_gather_repath = 0.5
	if _gather_path.is_empty(): return
	while _gather_path.size() > 1 and global_position.distance_to(_gather_path[0]) < 3.0:
		_gather_path.pop_front()
	var goal:Vector2 = _gather_path[0]
	var motion:Vector2 = (goal-global_position).limit_length(gather_speed*minf(delta,0.1))
	if motion.length_squared() <= 0.0001: return
	direction = motion.normalized()
	set_character_visual_flip_h(direction.x > 0.0 if dir_left else direction.x < 0.0)
	var steps:int = maxi(1,int(ceil(motion.length()/3.0)))
	for step:int in range(steps):
		var collision:KinematicCollision2D = move_and_collide(motion/float(steps))
		_gather_contact_damage()
		if collision != null:
			_gather_path.clear()
			break
	velocity = Vector2.ZERO

func _gather_contact_damage() -> void:
	if not mc_live() or not bool(cohort.get("gathering",false)): return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape_2d.shape
	query.transform = collision_shape_2d.global_transform
	query.collision_mask = 2
	query.exclude = [get_rid()]
	for record:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,64):
		var target:Variant = record.get("collider")
		if not mc_enemy(target): continue
		var id:int = target.get_instance_id()
		if _gather_hits.has(id): continue
		_gather_hits[id] = true
		# One hit per enemy per bat during this convergence; no free lifesteal/HP growth.
		target.receive_positional_damage(attack_damage(),global_position,false,self)

func play_transform_effect(to_vampire:bool) -> void:
	var effect:Node2D = TRANSFORM_FX.new()
	effect.position = global_position
	effect.visual_seed = int(get_instance_id()) ^ int(Engine.get_physics_frames())
	effect.set_meta("bat_to_vampire",to_vampire)
	effect.set_meta("bat_cohort_id",cohort.get("id",0))
	TRANSFORM_FX.runtime_container(self).add_child(effect)
	BAT_AUDIO.play(self,"entity.breeze.deflect",global_position,-4.0,false,true)

func get_debug_attack_regions() -> Array:
	if not bool(cohort.get("gathering",false)) or not mc_live(): return []
	var shape:RectangleShape2D = collision_shape_2d.shape as RectangleShape2D
	if shape == null: return []
	return [{"shape":"rect","position":collision_shape_2d.global_position,"half_extents":shape.size*collision_shape_2d.global_scale.abs()*0.5,"rotation":global_rotation,"damage":attack_damage(),"kind":"bat_gather_contact"}]
