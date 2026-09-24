extends "res://scripts/characters/我的世界/鞘翅长矛.gd"
## The spear owns the glide, rocket, swept tip and hit-speed reward. An accepted
## tip hit is the mace's opening blow: impact at the tip, leap, then keep the
## original elytra-mace landing/rebound chain and its unbounded damage growth.
const COMBO_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/elytra_spear/elytra_mace_spear.png")
const HIT_AUDIO:Script = preload("res://scripts/characters/我的世界/new5/audio.gd")
const HIT_GAIN:Script = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
# User-supplied picture: mace head at upper right, handle at lower left.
# The actual striking tip is on the head, never on the opposite end of the shaft.
const COMBO_TIP_PIXEL:Vector2 = Vector2(121,5)

func _ready() -> void:
	super._ready()
	add_to_group("MinecraftElytraMaceSpear")
	add_to_group("MinecraftMace")

func get_preview_texture() -> Texture2D:
	return COMBO_TEXTURE

func spear_tip_world_position() -> Vector2:
	var sprite:Sprite2D = image as Sprite2D
	return sprite.to_global(COMBO_TIP_PIXEL-sprite.texture.get_size()*0.5+sprite.offset)

func set_character_visual_flip_h(_flipped:bool) -> void:
	# Graphics rotates the entire sprite to its actual flight heading. The base
	# character shader would independently mirror Image on rightward motion,
	# putting the visible mace head opposite the swept contact point.
	super.set_character_visual_flip_h(false)

func _face_flight_direction() -> void:
	super._face_flight_direction()
	if not is_instance_valid(image): return
	var spin:float = deg_to_rad(base_spin_speed_degrees+_flight_height*spin_speed_per_height)*_flight_elapsed if _airborne else 0.0
	image.rotation = -PI*0.25+spin

func _sweep_spear_contacts(start:Vector2,finish:Vector2,tip_start:Vector2,tip_finish:Vector2) -> void:
	# Same swept-tip collision as Elytra Spear. Once a hit starts the mace leap,
	# stop this sweep: the ordinary poke-retreat must not cancel the new rebound.
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
			if (target.global_position-body).dot(heading) < -radius: continue
			if not _target_combat_shapes_overlap_circle(target,tip,radius): continue
			_spear_contacts[target.get_instance_id()] = weakref(target)
			if not _apply_spear_contact(target,tip,heading,speed_value,penetrating): continue
			if _airborne:
				global_position = body
				_rebound_origin = body
				_face_flight_direction()
				return

func _apply_spear_contact(target:ball,point:Vector2,heading:Vector2,speed_value:float,penetrating:bool) -> bool:
	var before:float = maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0
	var sound_point:Vector2 = target.global_position if is_instance_valid(target) else point
	# Parent settles the spear hit, one-contact speed bonus and poke knockback.
	if not super._apply_spear_contact(target,point,heading,speed_value,penetrating): return false
	if is_instance_valid(target): _emit_mc_hit(maxf(before-maxf(float(target.health),0.0),0.0),sound_point)
	var radius:float = maxf(base_landing_radius,0.0)
	_damage_spear_mace_area(target,point,radius,heading)
	_show_impact_to_peers(point,radius,maxf(base_flight_height,speed_value*0.2),true)
	# Preserve the low-speed spear's retreat direction before the mace's leap.
	if not penetrating and is_instance_valid(target) and target.health > 0:
		_glide_velocity = -heading*_glide_velocity.length()
		velocity = _glide_velocity+Repel
		_poke_retreat_left = poke_retreat_duration
	_begin_flight(1)
	return true

func _damage_spear_mace_area(primary:ball,point:Vector2,radius:float,heading:Vector2) -> void:
	# The direct victim already took the spear blow; the opening mace ring hits
	# every other real overlapping enemy, without charging that victim twice.
	var targets:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		var other:ball = node as ball
		if other != primary and _is_enemy(other) and _target_overlaps_damage_circle(other,point,radius):
			targets.append(other)
	for other:ball in targets:
		if not is_instance_valid(other): continue
		var before:float = maxf(float(other.health),0.0)
		var sound_point:Vector2 = other.global_position
		set_meta("blood_damage_kind","mace")
		set_meta("blood_attack_velocity",(sound_point-point).normalized()*landing_knockback_speed)
		if not other.receive_positional_damage(attack_damage(base_landing_damage_multiplier),point,false,self): continue
		if is_instance_valid(other):
			_emit_mc_hit(maxf(before-maxf(float(other.health),0.0),0.0),sound_point)
			_knockback_spear_mace_target(other,point,heading,base_landing_knockback_distance,landing_knockback_speed)
	_knockback_spear_mace_target(primary,point,heading,base_landing_knockback_distance,landing_knockback_speed)

func _knockback_spear_mace_target(target:ball,point:Vector2,heading:Vector2,distance:float,speed_value:float) -> void:
	if not is_instance_valid(target) or target.health <= 0 or distance <= 0.0: return
	var away:Vector2 = (target.global_position-point).normalized()
	if away.is_zero_approx(): away = heading
	target.apply_knockback(away,distance,speed_value,0.0,0.0,{"source":self,"stop_on_character":true})

func _begin_flight(level:int) -> void:
	# Reuse the mace's chain state/height timing and the elytra-mace's *physical*
	# loft. Elytra Spear deliberately overrides this with a no-op, so the combo
	# must explicitly restore this entry point without changing that parent role.
	var incoming:Vector2 = _glide_velocity
	var target:ball = _flight_target()
	if is_instance_valid(target) and absf(target.velocity.x)>25.0:
		_rebound_side = signf(target.velocity.x)
	elif absf(incoming.x)>70.0:
		_rebound_side = signf(incoming.x)
	else:
		_rebound_side = -_rebound_side
	var starting_new_chain:bool = not _airborne
	if starting_new_chain and graphics != null:
		_visual_base_position = graphics.position
		_visual_base_rotation = graphics.rotation
	_chain_level = clampi(level,1,maxi(max_chain_level,1))
	if starting_new_chain or _chain_damage_multiplier <= 0.0:
		_chain_damage_multiplier = maxf(base_landing_damage_multiplier,0.0)
	_airborne = true
	Attacking = true
	_flight_elapsed = 0.0
	_flight_height = base_flight_height+flight_height_gain*float(_chain_level-1)
	var half:float = maxf(base_flight_duration*0.5,0.10)
	var extra:float = maxf(_flight_height-base_flight_height,0.0)
	_rise_duration = half
	_fall_duration = half+minf(extra*maxf(landing_duration_gain_per_height,0.0),maxf(maximum_landing_duration_bonus,0.0))
	_flight_duration = _rise_duration+_fall_duration
	if _landing_recover_tween != null and _landing_recover_tween.is_valid(): _landing_recover_tween.kill()
	_landing_recover_tween = null
	_flight_start_rotation = graphics.rotation if graphics != null else _visual_base_rotation
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_flight_mode = FlightMode.REBOUND
	_mode_elapsed = 0.0
	_launch_y = global_position.y
	_rebound_origin = global_position
	_rebound_diving = false
	_rocket_remaining = 0.0
	var lift:float = sqrt(2.0*maxf(smash_gravity,1.0)*maxf(_flight_height,1.0))
	var lateral:float = incoming.x*0.8+_rebound_side*clampf(lift*0.38,100.0,210.0)
	_glide_velocity = Vector2(clampf(lateral,-maximum_flight_speed*0.65,maximum_flight_speed*0.65),-lift*0.90)
	velocity = _glide_velocity
	_face_flight_direction()

func _finish_landing() -> void:
	# Same radius, independent post-hit multiplier and retrigger test as Mace.
	# The Elytra Mace's inherited _update_flight() invokes this on true descent
	# overlap; each successful landing launches a taller/faster next leap.
	var radius:float = base_landing_radius+landing_radius_gain*float(_chain_level-1)
	var multiplier:float = maxf(_chain_damage_multiplier,base_landing_damage_multiplier)
	var knock_distance:float = base_landing_knockback_distance+landing_knockback_gain*float(_chain_level-1)
	var center:Vector2 = _ground_impact_center()
	var hit_result:Dictionary = _damage_area(center,radius,attack_damage(multiplier),knock_distance,
		landing_knockback_speed+float(_chain_level-1)*16.0,radius)
	_show_impact_to_peers(center,radius,_flight_height,int(hit_result.get("hits",0))>0)
	if int(hit_result.get("retrigger_hits",0))>0 and health>0 and is_combat_runtime_active() and not is_damage_output_disabled():
		_chain_damage_multiplier = maxf(multiplier*maxf(landing_damage_jump_multiplier,1.0),0.0)
		_begin_flight(mini(_chain_level+1,maxi(max_chain_level,1)))
	else:
		_airborne = false
		Attacking = false
		_chain_level = 1
		_chain_damage_multiplier = 0.0
		_recover_from_landing_pose()
	_sync_air_visual_followers()

func _damage_area(center:Vector2,radius:float,damage_value:float,knock_distance:float,knock_speed:float,retrigger_radius:float = -1.0) -> Dictionary:
	# Reproduce Mace's full target/circle/retrigger contract, replacing its
	# old Witch-only sound with one native MC hit per actual health-damage event.
	if get_world_2d() == null or damage_value <= 0.0: return {"hits":0,"retrigger_hits":0}
	var targets:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		var target:ball = node as ball
		if _is_enemy(target) and _target_overlaps_damage_circle(target,center,radius): targets.append(target)
	var hits:int = 0
	var retriggers:int = 0
	for target:ball in targets:
		if not is_instance_valid(target): continue
		var in_retrigger_range:bool = retrigger_radius>0.0 and _target_overlaps_damage_circle(target,center,retrigger_radius)
		var before:float = maxf(float(target.health),0.0)
		var sound_point:Vector2 = target.global_position
		set_meta("blood_damage_kind","mace")
		set_meta("blood_attack_velocity",(sound_point-center).normalized()*knock_speed)
		var applied:bool = target.receive_positional_damage(damage_value,center,false,self)
		if applied:
			hits += 1
			if in_retrigger_range: retriggers += 1
			if is_instance_valid(target): _emit_mc_hit(maxf(before-maxf(float(target.health),0.0),0.0),sound_point)
		if is_instance_valid(target):
			_knockback_spear_mace_target(target,center,Vector2.RIGHT,knock_distance,knock_speed)
	return {"hits":hits,"retrigger_hits":retriggers}

func _show_impact_to_peers(point:Vector2,radius:float,height:float,hit_character:bool) -> void:
	if multiplayer.has_multiplayer_peer(): _show_combo_impact.rpc(point,radius,height,hit_character)
	_show_combo_impact(point,radius,height,hit_character)

@rpc("authority","call_remote","reliable")
func _show_combo_impact(point:Vector2,radius:float,height:float,hit_character:bool) -> void:
	_spawn_impact_visual(point,radius)
	_play_height_based_smash_sfx(point,height,hit_character)

func _emit_mc_hit(actual:float,point:Vector2) -> void:
	if actual <= 0.0: return
	if multiplayer.has_multiplayer_peer(): _play_spear_mace_hit.rpc(HIT_GAIN.damage_event(actual),point,actual)
	_play_spear_mace_hit(HIT_GAIN.damage_event(actual),point,actual)

@rpc("authority","call_remote","reliable")
func _play_spear_mace_hit(event:String,point:Vector2,actual:float) -> void:
	var player:AudioStreamPlayer2D = HIT_AUDIO.play(self,event,point,HIT_GAIN.damage_gain(actual),false,true,true,true)
	if is_instance_valid(player):
		player.set_meta("mc_actual_damage",actual)
		player.set_meta("mc_damage_source",get_instance_id())

func get_ai_attack_threats(receiver:ball) -> Array:
	if health<=0 or not Can_Attack or dizziness or is_damage_output_disabled(): return []
	if _airborne:
		# Spear sweep is paused in the mace leap. The real landing circle moves
		# with the body and grows with the current stack/damage multiplier.
		return [{"shape":"circle","position":_ground_impact_center(),
			"radius":base_landing_radius+landing_radius_gain*float(_chain_level-1),
			"damage":attack_damage(maxf(_chain_damage_multiplier,base_landing_damage_multiplier)),
			"danger_in":0.0 if _glide_velocity.y>35.0 else 0.1,"danger_duration":0.12,
			"kind":"elytra_spear_mace_landing","source":self}]
	var threats:Array = super.get_ai_attack_threats(receiver)
	if threats.is_empty(): return threats
	threats.append({"shape":"circle","position":spear_tip_world_position(),"radius":base_landing_radius,
		"damage":attack_damage(base_landing_damage_multiplier),"danger_in":0.0,
		"danger_duration":0.05,"kind":"elytra_spear_mace_on_tip_hit","source":self,
		"conditional_on_tip_hit":true})
	return threats

func get_debug_attack_regions() -> Array:
	return get_ai_attack_threats(null)

func get_debug_detection_regions() -> Array[Dictionary]:
	return []
