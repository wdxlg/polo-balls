extends "res://scripts/characters/我的世界/鞘翅重锤.gd"
## Shared elytra flight with successful-hit propulsion; no mace rebound or post-pass braking.
const SPEAR_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/elytra_spear/netherite_spear.png")
const SPEAR_HIT_SOUNDS = preload("res://scripts/characters/我的世界/木矛.gd").HIT_SFX
const SPEAR_ATTACK_SOUNDS = preload("res://scripts/characters/我的世界/木矛.gd").ATTACK_SFX

@export_category("鞘翅长矛 / 飞行穿刺")
# Wooden spear's threshold is 90 * 3.8; independent from flight propulsion.
@export var pierce_speed_threshold:float = 342.0
@export var pierce_damage_multiplier:float = 2.0
@export var poke_hit_speed_bonus:float = 60.0
@export var pierce_hit_speed_bonus:float = 150.0
@export var spear_tip_radius_local:float = 8.0
@export var poke_knockback_distance:float = 6.0
@export var poke_retreat_duration:float = 0.16

@export_category("鞘翅长矛 / 迎敌穿刺冲刺")
@export var pierce_dash_min_speed:float = 560.0
@export var pierce_dash_speed_gain:float = 220.0
@export var pierce_dash_duration:float = 0.45
@export var pierce_dash_exit_grace:float = 0.30
@export var pierce_dash_range:float = 240.0
@export var pierce_dash_alignment_degrees:float = 14.0
var _pierce_dashing:bool = false
var _pierce_dash_left:float = 0.0
var _pierce_dash_cooldown_left:float = 0.0
var _pierce_dash_heading:Vector2 = Vector2.ZERO
var _spear_contacts:Dictionary = {}
var _poke_retreat_left:float = 0.0
var _pierce_heading:Vector2 = Vector2.ZERO
var last_contact_mode:StringName = &""
var last_contact_damage:float = 0.0
var last_contact_speed:float = 0.0

func _ready() -> void:
	super._ready()
	Can_Skill = true
	default_properties["Can_Skill"] = true
	remove_from_group("MinecraftMace")
	add_to_group("MinecraftElytraSpear")
	self_hitbox.set_deferred("monitoring",false)
	(image as Sprite2D).offset = Vector2.ZERO
	velocity = _glide_velocity
	_face_flight_direction()

func allows_character_motion_effects() -> bool:
	# The global allowlist intentionally excludes most characters; opt in only here.
	return true

func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and _pierce_dashing and (health<=0 or dizziness or not Can_Attack or not Can_Skill or is_damage_output_disabled()): _finish_pierce_dash(false)
	super.tick_physics(state,delta)
	# Authority already samples in ball.tick_physics; remote copies need local visuals.
	if not is_multiplayer_authority():
		_process_auto_after_image(delta)

func _process_auto_after_image(delta:float) -> void:
	if health <= 0 or not is_combat_runtime_active():
		_reset_after_image_sampling()
		return
	super._process_auto_after_image(delta)

func _resolve_opening_swing_sfx() -> void:
	# Do not load/play mace attacks for this flight-only subclass.
	pass

func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:State = State.Move
	if health <= 0: next = State.Die
	elif not is_combat_runtime_active(): next = State.Stand
	return -1 if state == next else next

func Attack() -> void:
	# Contacts are resolved by the continuous swept spear tip, not a mace coroutine.
	Attacking = false

func _on_hitbox_on_hit(_hurt:hurtbox) -> void:
	# Never stack the inherited generic hitbox damage on top of the swept contact.
	pass

func _try_dive_smash() -> bool:
	return false

func _begin_flight(_level:int) -> void:
	# No hit-triggered upward launch or mace combo growth.
	pass

func _finish_landing() -> void:
	pass

func _choose_flight_tactic(target:ball,delta:float) -> Vector2:
	if not is_player_controlled() and not _pierce_dashing: try_pierce_dash(target)
	if _pierce_dashing: return _pierce_dash_heading
	if not _pierce_heading.is_zero_approx() and not _spear_contacts.is_empty():
		return _pierce_heading
	if _poke_retreat_left > 0.0:
		return _glide_velocity.normalized()
	return super._choose_flight_tactic(target,delta)

func _wants_tactical_firework(target:ball,aim:Vector2) -> bool:
	if _pierce_dashing:
		if not Can_Skill or not Can_Attack or is_damage_output_disabled(): return false
		# A rocket becoming ready mid-pass may propel this committed attack;
		# never let AI press the player's button or boost toward a passed enemy.
		return not is_player_controlled() and not dizziness and _rocket_cooldown<=0.0 and _rocket_remaining<=0.0 and _is_enemy(target) and (ball.body_point(target,global_position)-global_position).dot(_pierce_dash_heading)>0.0
	if not _pierce_heading.is_zero_approx() and not _spear_contacts.is_empty(): return false
	if _poke_retreat_left > 0.0: return false
	return super._wants_tactical_firework(target,aim)

func _step_glide(delta:float) -> void:
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active(): return
	_pierce_dash_cooldown_left = maxf(_pierce_dash_cooldown_left-delta,0.0)
	if _pierce_dashing and (dizziness or not Can_Attack or not Can_Skill or is_damage_output_disabled()): _finish_pierce_dash(false)
	_poke_retreat_left = maxf(_poke_retreat_left - delta,0.0)
	_clear_finished_contacts()
	var start:Vector2 = global_position
	var tip_start:Vector2 = spear_tip_world_position()
	# All gravity, drag, firework acceleration, steering and speed caps stay in parent.
	super._step_glide(delta)
	var finish:Vector2 = global_position
	var tip_finish:Vector2 = spear_tip_world_position()
	if not Can_Attack or dizziness or is_damage_output_disabled(): return
	_sweep_spear_contacts(start,finish,tip_start,tip_finish)
	if _pierce_dashing:
		_pierce_dash_left -= delta
		_clear_finished_contacts()
		if _pierce_dash_left<=0.0 and (_spear_contacts.is_empty() or _pierce_dash_left<=-maxf(pierce_dash_exit_grace,0.0)):
			_finish_pierce_dash(true)

func _flight_replication_properties() -> Array[StringName]:
	var properties:Array[StringName] = super._flight_replication_properties()
	properties.append_array([&"_pierce_dashing",&"_pierce_dash_left",&"_pierce_dash_cooldown_left",&"_pierce_dash_heading"])
	return properties

func _dash_ready() -> bool:
	return health>0 and Can_Attack and Can_Skill and not dizziness and not _airborne and not _returning_to_map and not _pierce_dashing and _pierce_dash_cooldown_left<=0.0 and _poke_retreat_left<=0.0 and _spear_contacts.is_empty() and _rocket_remaining<=0.0 and not is_damage_output_disabled() and is_combat_runtime_active()

func try_pierce_dash(target:ball = null,manual_direction:Vector2 = Vector2.ZERO) -> bool:
	if not is_multiplayer_authority() or not _dash_ready(): return false
	var manual:bool = not manual_direction.is_zero_approx()
	if manual!=is_player_controlled(): return false
	var aim:Vector2 = manual_direction.normalized()
	if not manual:
		if not _is_enemy(target): return false
		var offset:Vector2 = ball.body_point(target,global_position)-global_position
		if offset.length()<16.0 or offset.length()>maxf(pierce_dash_range,16.0): return false
		if _glide_velocity.is_zero_approx() or _glide_velocity.normalized().dot(offset.normalized())<cos(deg_to_rad(pierce_dash_alignment_degrees)): return false
		aim = offset.normalized()
	var incoming:float = _glide_velocity.length()
	var boosted:float = maxf(incoming,minf(maxf(incoming+pierce_dash_speed_gain,pierce_dash_min_speed),maximum_flight_speed))
	if boosted<pierce_speed_threshold: return false
	if not manual:
		_refresh_flight_arena(0.0)
		var exit_point:Vector2 = global_position+aim*boosted*maxf(pierce_dash_duration,0.01)
		if _patrol_rect.has_area() and not _patrol_rect.grow(maxf(arena_return_distance,16.0)*0.65).has_point(exit_point): return false
	_pierce_dashing = true
	_pierce_dash_heading = aim
	_pierce_dash_left = maxf(pierce_dash_duration,0.01)
	_pierce_dash_cooldown_left = maxf(Skill_Cooling,0.1)
	_poke_retreat_left = 0.0
	_glide_velocity = aim*boosted
	velocity = _glide_velocity+Repel
	# Ignite the real shared rocket integrator, not just its sprite/trail.
	# The separate dash never bypasses a rocket's own cooldown.
	if _rocket_cooldown<=0.0:
		_use_firework(aim)
	elif _rocket_display_left<=0.0:
		if multiplayer.has_multiplayer_peer(): _show_firework.rpc()
		else: _show_firework()
	_face_flight_direction()
	return true

func _committed_glide_heading() -> Vector2:
	return _pierce_dash_heading if _pierce_dashing else Vector2.ZERO

func _on_map_return_started() -> void:
	super._on_map_return_started()
	if _pierce_dashing: _finish_pierce_dash(false)
	_pierce_heading = Vector2.ZERO
	_poke_retreat_left = 0.0

func _finish_pierce_dash(completed:bool) -> void:
	if not _pierce_dashing: return
	if not completed: _rocket_remaining = 0.0
	_pierce_dashing = false
	_pierce_dash_left = 0.0
	_pierce_dash_heading = Vector2.ZERO
	_on_pierce_dash_finished(completed)

func _on_pierce_dash_finished(_completed:bool) -> void:
	pass

func _update_flight(delta:float) -> void:
	if is_hard_controlled(): return
	if is_multiplayer_authority() and is_combat_runtime_active(): _pierce_dash_cooldown_left = maxf(_pierce_dash_cooldown_left-delta,0.0)
	super._update_flight(delta)

func player_control_action_ids() -> Array[StringName]:
	# Replace the inherited no-op Attack slot; do not duplicate a passive tip hit.
	return [&"controlled_pierce_dash_action",&"controlled_skill_action"]

func controlled_pierce_dash_action() -> void:
	if not is_player_controlled(): return
	try_pierce_dash(null,player_control_aim_direction(_glide_velocity.normalized()))

func controlled_skill_action() -> void:
	if not Can_Skill: return
	if _pierce_dashing:
		if not is_player_controlled() or not is_multiplayer_authority() or health<=0 or not is_combat_runtime_active() or is_damage_output_disabled() or dizziness or _rocket_cooldown>0.0 or _rocket_remaining>0.0: return
		# Mid-pass manual ignition follows the committed spear heading, not a
		# newly moved cursor that would turn a straight pierce into a side boost.
		_use_firework(_pierce_dash_heading)
		return
	super.controlled_skill_action()

func _face_flight_direction() -> void:
	super._face_flight_direction()
	# Native hand sprite points up-left. Graphics contributes heading + 90 degrees.
	image.rotation = PI * 0.25
	image.scale = _air_visual_base_scale
	if self_hurtbox != null:
		self_hurtbox.global_rotation = velocity.angle() if velocity.length_squared() > 0.001 else direction.angle()

func spear_tip_world_position() -> Vector2:
	var sprite:Sprite2D = image as Sprite2D
	# Native 32x32 texture: tip is at pixel (1,1), not at the transparent center.
	var tip:Vector2 = Vector2(1,1) - sprite.texture.get_size()*0.5 + sprite.offset
	return sprite.to_global(tip)

func spear_tip_world_radius() -> float:
	return spear_tip_radius_local * maxf(absf(global_scale.x),absf(global_scale.y))

func flight_damage_at_speed(speed_value:float,penetrating:bool) -> float:
	# Same 1x at 90 -> 2.4x at 420 slope as wooden spear, extended for flight >420.
	# Damage uses incoming sweep speed, before the reward for this contact.
	var speed_multiplier:float = speed_value/90.0 if speed_value < 90.0 else 1.0 + (speed_value - 90.0)*1.4/330.0
	return maxf(5.0,attack_damage(speed_multiplier * (pierce_damage_multiplier if penetrating else 1.0)))

func _clear_finished_contacts() -> void:
	var reach:float = global_position.distance_to(spear_tip_world_position()) + 8.0
	for id:Variant in _spear_contacts.keys():
		var target:ball = (_spear_contacts[id] as WeakRef).get_ref() as ball
		if not is_instance_valid(target) or not _is_enemy(target) or not _target_overlaps_damage_circle(target,global_position,reach):
			_spear_contacts.erase(id)
	if _spear_contacts.is_empty(): _pierce_heading = Vector2.ZERO

func _sweep_spear_contacts(start:Vector2,finish:Vector2,tip_start:Vector2,tip_finish:Vector2) -> void:
	var speed_value:float = _glide_velocity.length()
	if speed_value < 0.01: return
	var penetrating:bool = speed_value >= pierce_speed_threshold
	var heading:Vector2 = _glide_velocity.normalized()
	var radius:float = spear_tip_world_radius()
	var steps:int = maxi(1,int(ceil(tip_start.distance_to(tip_finish)/maxf(radius,0.5))))
	var candidates:Array[Node] = get_tree().get_nodes_in_group("Ball")
	for i:int in range(steps+1):
		var fraction:float = float(i)/float(steps)
		var tip:Vector2 = tip_start.lerp(tip_finish,fraction)
		var body:Vector2 = start.lerp(finish,fraction)
		for node:Node in candidates:
			var target:ball = node as ball
			if not _is_enemy(target) or _spear_contacts.has(target.get_instance_id()): continue
			# Only the forward tip attacks; the wings and rear shaft cannot sweep damage.
			if (ball.body_point(target,body)-body).dot(heading) < -radius: continue
			if not _target_combat_shapes_overlap_circle(target,tip,radius): continue
			_spear_contacts[target.get_instance_id()] = weakref(target)
			if not _apply_spear_contact(target,tip,heading,speed_value,penetrating): continue
			if not penetrating and target.health > 0:
				# Turn away while retaining the successful-hit speed reward.
				global_position = body
				_glide_velocity = -heading * _glide_velocity.length()
				velocity = _glide_velocity + Repel
				_poke_retreat_left = poke_retreat_duration
				_face_flight_direction()
				return

func _apply_spear_contact(target:ball,point:Vector2,heading:Vector2,speed_value:float,penetrating:bool) -> bool:
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active(): return false
	if not Can_Attack or dizziness or is_damage_output_disabled() or not _is_enemy(target): return false
	var damage:float = flight_damage_at_speed(speed_value,penetrating)
	set_meta("blood_damage_kind","pierce")
	set_meta("blood_attack_velocity",heading * speed_value)
	if not target.receive_positional_damage(damage,point,false,self): return false
	last_contact_mode = &"pierce" if penetrating else &"poke"
	last_contact_damage = damage
	last_contact_speed = speed_value
	_apply_hit_speed_bonus(penetrating)
	if penetrating:
		# Hold the incoming line until the whole spear clears, including after acceleration.
		_pierce_heading = heading
	if not penetrating and target.health > 0:
		target.apply_knockback(heading,poke_knockback_distance,120.0,0.0,0.0,{"source":self})
	if multiplayer.has_multiplayer_peer(): _spear_contact_audio.rpc(point)
	else: _spear_contact_audio(point)
	return true

func _apply_hit_speed_bonus(penetrating:bool) -> void:
	# Only called after accepted damage; contact deduplication lives in the tip sweep.
	var speed_value:float = _glide_velocity.length()
	if speed_value <= 0.001: return
	var bonus:float = maxf(pierce_hit_speed_bonus if penetrating else poke_hit_speed_bonus,0.0)
	# At/above the cap a hit must never brake the character.
	var boosted:float = maxf(speed_value,minf(speed_value + bonus,maximum_flight_speed))
	_glide_velocity = _glide_velocity.normalized() * boosted
	velocity = _glide_velocity + Repel

@rpc("authority","call_local","reliable")
func _spear_contact_audio(point:Vector2) -> void:
	_play_world_sfx(SPEAR_ATTACK_SOUNDS.pick_random(),point,-4.0)
	_play_world_sfx(SPEAR_HIT_SOUNDS.pick_random(),point,-1.0)

func get_preview_texture() -> Texture2D:
	return SPEAR_TEXTURE

func get_ai_attack_threats(_receiver:ball) -> Array:
	if health <= 0 or not Can_Attack or dizziness or is_damage_output_disabled(): return []
	var speed_value:float = _glide_velocity.length()
	return [{"shape":"circle","position":spear_tip_world_position(),"radius":spear_tip_world_radius(),
		"damage":flight_damage_at_speed(speed_value,speed_value>=pierce_speed_threshold),
		"danger_in":0.0,"danger_duration":0.1,"kind":"elytra_spear_tip","source":self}]

func get_debug_attack_regions() -> Array:
	return get_ai_attack_threats(null)

func get_debug_detection_regions() -> Array[Dictionary]:
	if not _dash_ready() or is_player_controlled() or _glide_velocity.is_zero_approx(): return []
	var heading:float = _glide_velocity.angle()
	var half:float = deg_to_rad(pierce_dash_alignment_degrees)
	var points:=PackedVector2Array()
	for i:int in range(17): points.append(global_position+Vector2.from_angle(heading-half+half*2.0*float(i)/16.0)*maxf(pierce_dash_range,16.0))
	for i:int in range(16,-1,-1): points.append(global_position+Vector2.from_angle(heading-half+half*2.0*float(i)/16.0)*16.0)
	return [{"shape":"polygon","position":global_position,"points":points,"kind":"elytra_dash_alignment","source":self}]
