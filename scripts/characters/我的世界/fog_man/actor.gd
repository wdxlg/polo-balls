extends "res://scripts/characters/我的世界/new5/base.gd"
## Original mod art, adapted combat design. Authority owns discovery/warps/damage.
const BODY = preload("res://Images/characters/我的世界/fog_man/body.tres")
const EYES = preload("res://Images/characters/我的世界/fog_man/eyes.tres")
const FIELD = preload("res://scripts/characters/我的世界/fog_man/field.gd")
const EYE_FX = preload("res://scripts/characters/我的世界/fog_man/eyes.gd")
const LIGHTNING = preload("res://scenes/effects/我的世界/雷电.tscn")
const MC_ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const FX = preload("res://scripts/characters/我的世界/fog_man/effects.gd")
## Independent legs: walk / rage-run frames follow real displacement against the OWN base speed
## (rage run = 2 cycles per walk cycle) and settle to idle when still, rage included. The attack
## clip keeps its original whole-body mod animation (its leg motion is baked into the swing).
const MC_LEGS = preload("res://scripts/effects/我的世界/mc_legs.gd")
const VOICES:Dictionary = {
	"spawn":preload("res://audio/characters/我的世界/fog_man/spawn.ogg"),
	"whisper":preload("res://audio/characters/我的世界/fog_man/whisper.ogg"),
	"vanish":preload("res://audio/characters/我的世界/fog_man/vanish.ogg"),
	"rage":preload("res://audio/characters/我的世界/fog_man/chase.ogg"),
	"hurt":preload("res://audio/characters/我的世界/fog_man/spotted.ogg"),
	"thunder":preload("res://audio/characters/我的世界/苦力怕/thunder1.ogg")
}
enum Phase { STALK, VANISHED, RAGE }
enum Rush { MIST, REVEAL, RECOVER, RETREAT, FACE_VANISH, FACE_SHOW }
var rush:int = Rush.MIST
var rush_left:float = 0.0
var retreat_direction:Vector2 = Vector2.ZERO
var charge_fx:Node2D
var rush_hits:int = 0
var attack_kind:int = 0
var dash_direction:Vector2 = Vector2.ZERO
var dash_remaining:float = 0.0
var dash_hit_ids:Dictionary = {}
var face_point:Vector2 = Vector2.ZERO
var face_fired:bool = false
var face_radius:float = 100.0
var face_casts:int = 0
var mist_casts:int = 0
@export var discovery_ratio:float = 0.6
@export var discovery_hold:float = 0.3
@export var discovery_health_cost:float = 0.08
@export var vanish_duration:float = 2.0
@export var behind_range:float = 90.0
@export var behind_hold:float = 0.6
@export var rage_duration:float = 4.0
@export var rage_speed_ratio:float = 1.8
@export var rage_cooldown:float = 5.0
@export var clear_radius:float = 180.0
@export var attack_interval:float = 0.45
@export var attack_reach:float = 48.0
var phase:int = Phase.STALK
var phase_started:float = 0.0
var rage_left:float = 0.0
var lightning_wait:bool = false
var lightning_visual:Node2D
var rage_origin:Vector2 = Vector2.ZERO
var exposure_left:float = 0.0
var rear_hold:float = 0.0
var rage_wait:float = 0.0
var vanish_left:float = 0.0
var grace_left:float = 0.8
var discovery_count:int = 0
var fog:Node2D
var eye_fx:Node2D
var effects:Node2D
var _nav_left:float = 0.0
var _target_ref:WeakRef
var _behind_target_id:int = 0
var _attack_left:float = 0.0
var _swing_left:float = 0.0
var _reappear_attempts:int = 0
var _saved_layer:int = 0
var _saved_mask:int = 0
var _clip:StringName = &"idle"
var _frame_index:int = 0
var gait:RefCounted
var _legs_delta:float = 0.0
var _event_id:int = 0
var _last_event:int = 0
var _transition:int = 0
var _last_state_time:float = -1.0
var _voices:Array[Dictionary] = []
var _ambient_wait:float = 5.0
var _announced:bool = false
func get_preview_texture() -> Texture2D: return BODY.get_frame_texture(&"idle",0)
func _ready() -> void:
	super._ready()
	add_to_group("MCFogMan")
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	fog = FIELD.ensure(self)
	charge_fx = preload("res://scripts/characters/我的世界/fog_man/charge_mist.gd").new()
	charge_fx.actor = self
	fog.add_child(charge_fx)
	eye_fx = EYE_FX.new()
	eye_fx.actor = self
	add_child(eye_fx)
	effects = FX.new()
	effects.actor = self
	add_child(effects)
	image.z_as_relative = false
	image.z_index = 3
	set_meta("ignore_combat_locking",true)
func is_combat_lockable() -> bool:
	if phase == Phase.VANISHED or not is_combat_targetable(): return false
	return phase == Phase.RAGE or (is_instance_valid(fog) and fog.clear_at(global_position))
func is_combat_targetable() -> bool:
	return phase != Phase.VANISHED and super.is_combat_targetable()
func _refresh_locking() -> void:
	set_meta("ignore_combat_locking",not (phase==Phase.RAGE or (phase!=Phase.VANISHED and is_instance_valid(fog) and fog.clear_at(global_position))))
func move(speed:float,delta:float):
	if phase==Phase.VANISHED:
		velocity = Vector2.ZERO
		return
	if phase==Phase.RAGE and not lightning_wait:
		if rush==Rush.MIST:
			var before:Vector2 = global_position
			velocity = dash_direction*360.0
			move_with_body_slide(delta)
			dash_remaining -= before.distance_to(global_position)
			if before.distance_to(global_position)<0.1: dash_remaining = 0.0
			sweep_mist_damage(before,global_position)
			return
		if rush in [Rush.FACE_VANISH,Rush.FACE_SHOW]:
			velocity = Vector2.ZERO
			return
	var ratio:float = 0.65
	if phase==Phase.RAGE:
		ratio = 4.8 if rush==Rush.MIST else 2.8 if rush==Rush.RETREAT else 2.6
		if lightning_wait or (rush==Rush.RECOVER and not is_player_controlled()): ratio = 0.0
	super.move(speed*ratio,delta)
func stand(delta:float):
	if phase==Phase.VANISHED:
		velocity = Vector2.ZERO
		return
	super.stand(delta)
func step_mob(delta:float) -> void:
	if not is_instance_valid(fog): fog = FIELD.ensure(self)
	_refresh_locking()
	if not can_act():
		direction = Vector2.ZERO
		return
	if not _announced:
		_announced = true
		emit_event("spawn",global_position)
	grace_left = maxf(grace_left-delta,0.0)
	rage_wait = maxf(rage_wait-delta,0.0)
	_attack_left = maxf(_attack_left-delta,0.0)
	_swing_left = maxf(_swing_left-delta,0.0)
	if phase==Phase.VANISHED:
		vanish_left -= delta
		if vanish_left<=0.0: try_reappear()
		return
	if fog.viewers.is_empty(): fog.refresh_viewers()
	if phase==Phase.RAGE:
		if lightning_wait:
			direction = Vector2.ZERO
			return
		rage_left = maxf(rage_left-delta,0.0)
		if rage_left<=0.0:
			set_phase(Phase.STALK)
			grace_left = 0.6
			rage_wait = rage_cooldown
			return
		if is_player_controlled():
			manual_rush_step(delta)
			return
		var target:ball = valid_target()
		if not is_instance_valid(target): target = U.nearest(self)
		if is_instance_valid(target):
			_target_ref = weakref(target)
			rush_step(target,delta)
		else:
			direction = Vector2.ZERO
			set_rush(Rush.RETREAT,0.2)
		return
	if grace_left<=0.0 and fog.body_exposure(self,global_position)>=discovery_ratio:
		exposure_left += delta
		if exposure_left>=discovery_hold:
			disappear()
			return
	else: exposure_left = 0.0
	if is_player_controlled():
		var aimed:ball = manual_fog_target()
		if is_instance_valid(aimed) and rage_wait<=0.0 and behind(aimed):
			if _behind_target_id!=aimed.get_instance_id():
				_behind_target_id = aimed.get_instance_id()
				rear_hold = 0.0
			_target_ref = weakref(aimed)
			rear_hold += delta
		else:
			rear_hold = 0.0
		_tick_whisper(delta)
		return
	var target:ball = valid_target()
	if not is_instance_valid(target):
		target = U.nearest(self)
		_target_ref = weakref(target) if target!=null else null
	if not is_instance_valid(target):
		direction = Vector2.ZERO
		rear_hold = 0.0
		return
	if _behind_target_id!=target.get_instance_id():
		_behind_target_id = target.get_instance_id()
		rear_hold = 0.0
	if rage_wait<=0.0 and behind(target):
		rear_hold += delta
		if rear_hold>=behind_hold and begin_rage(): return
	else: rear_hold = 0.0
	_nav_left -= delta
	if _nav_left<=0.0:
		_nav_left = 0.12
		choose_stalk_direction(target)
	_tick_whisper(delta)

func _tick_whisper(delta:float) -> void:
	_ambient_wait -= delta
	if _ambient_wait<=0.0:
		_ambient_wait = rng.randf_range(8.0,14.0)
		var last:float = float(fog.get_meta("last_whisper",-100.0))
		if fog.elapsed-last>=6.0:
			fog.set_meta("last_whisper",fog.elapsed)
			emit_event("whisper",global_position)
func manual_fog_target() -> ball:
	if not has_player_control_aim(): return null
	var best:ball = null
	var best_distance:float = INF
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,candidate) or not candidate.is_combat_lockable(): continue
		var radius:float = maxf(42.0,U.radius(candidate)+20.0)
		var distance:float = ball.body_point(candidate,player_control_aim_position).distance_squared_to(player_control_aim_position)
		if distance<=radius*radius and distance<best_distance:
			best = candidate as ball
			best_distance = distance
	return best

func controlled_attack_action() -> void:
	if not is_player_controlled() or not can_act(): return
	var target:ball = manual_fog_target()
	if not is_instance_valid(target): return
	if phase==Phase.STALK:
		_target_ref = weakref(target)
		begin_rage() # 仍需绕后持续 behind_hold 秒且狂暴冷却结束。
	elif phase==Phase.RAGE and not lightning_wait and rush==Rush.RECOVER and rush_left<=0.0:
		start_rush_attack(target,0)

func controlled_skill_action() -> void:
	if not is_player_controlled() or not can_act() or phase!=Phase.RAGE or lightning_wait: return
	if rush!=Rush.RECOVER or rush_left>0.0: return
	var target:ball = manual_fog_target()
	if is_instance_valid(target): start_rush_attack(target,1)

func manual_rush_step(delta:float) -> void:
	# 保留当前招式的位移、命中和收招，但不由 AI 接续下一招或擅自退开。
	if rush==Rush.RECOVER:
		rush_left = maxf(rush_left-delta,0.0)
		return
	var target:ball = valid_target()
	rush_left -= delta
	match rush:
		Rush.MIST:
			if dash_remaining<=0.0 or rush_left<=0.0:
				set_rush(Rush.RECOVER,maxf(attack_interval,0.1))
		Rush.FACE_VANISH:
			if rush_left<=0.0 and (not is_instance_valid(target) or not manifest_face(target)):
				set_rush(Rush.RECOVER,maxf(attack_interval,0.1))
		Rush.FACE_SHOW:
			if rush_left<=0.0:
				set_rush(Rush.RECOVER,maxf(attack_interval,0.1))
		_:
			set_rush(Rush.RECOVER,0.0)

func valid_target() -> ball:
	var target:Variant = _target_ref.get_ref() if _target_ref!=null else null
	return target as ball if U.enemy(self,target) and target.is_combat_lockable() else null
func behind(target:ball) -> bool:
	var away:Vector2 = ball.body_point(target,global_position).direction_to(global_position)
	var distance:float = global_position.distance_to(ball.body_point(target,global_position))
	return distance>=20.0 and distance<=behind_range and away.dot(fog.heading_for(target)) < -0.65 and fog.line_visible(target.global_position,global_position,target)
func body_clear(point:Vector2) -> bool:
	var rect:Rect2 = fog.arena_rect().grow(-18.0)
	if not rect.has_point(point): return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape_2d.shape
	query.transform = collision_shape_2d.global_transform
	query.transform.origin += point-global_position
	query.collision_mask = 3
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
func choose_stalk_direction(target:ball) -> void:
	var goal:Vector2 = ball.body_point(target,global_position)-fog.heading_for(target)*70.0
	var best:Vector2 = Vector2.ZERO
	var best_cost:float = global_position.distance_to(goal)+fog.risk(self,global_position)*700.0+10.0
	for i:int in range(16):
		var heading:Vector2 = Vector2.RIGHT.rotated(TAU*float(i)/16.0)
		var point:Vector2 = global_position+heading*38.0
		if not body_clear(point) or not fog.line_visible(global_position,point,self): continue
		var cost:float = point.distance_to(goal)+fog.risk(self,point)*700.0+(1.0-heading.dot(direction))*3.0
		if cost<best_cost:
			best_cost = cost
			best = heading
	direction = best
func disappear() -> bool:
	if not can_act() or phase!=Phase.STALK: return false
	discovery_count += 1
	exposure_left = 0.0
	rear_hold = 0.0
	# Suppress the self-cost popup before the synchronous health setter emits HUD signals.
	if is_instance_valid(health_bar): health_bar.suppress_floating_text = true
	# Being discovered costs raw self health, not block/shield or outgoing damage.
	health = maxi(health-int(ceil(float(Max_health)*discovery_health_cost)),0)
	emit_event("vanish",global_position)
	if health<=0:
		Die()
		return true
	vanish_left = vanish_duration
	_reappear_attempts = 0
	set_phase(Phase.VANISHED)
	return true
func try_reappear() -> bool:
	if not is_multiplayer_authority() or phase!=Phase.VANISHED or health<=0: return false
	fog.refresh_viewers()
	var rect:Rect2 = fog.arena_rect().grow(-25.0)
	var best:Vector2 = Vector2.INF
	var best_risk:float = INF
	for i:int in range(48):
		var point := Vector2(rng.randf_range(rect.position.x,rect.end.x),rng.randf_range(rect.position.y,rect.end.y))
		if not body_clear(point) or fog.clear_at(point): continue
		var too_close:bool = false
		for entry:Dictionary in fog.enemy_viewers(self):
			if point.distance_to(entry.point)<125.0: too_close = true; break
		if too_close: continue
		var risk:float = fog.body_exposure(self,point)
		if risk<best_risk: best = point; best_risk = risk
		if risk==0.0: break
	_reappear_attempts += 1
	if best==Vector2.INF or (best_risk>0.0 and _reappear_attempts<6):
		vanish_left = 0.35
		return false
	global_position = best
	reset_physics_interpolation()
	grace_left = 0.65
	exposure_left = 0.0
	set_phase(Phase.STALK)
	emit_event("spawn",global_position)
	return true
func begin_rage() -> bool:
	if not can_act() or not Can_Skill or phase!=Phase.STALK or rage_wait>0.0: return false
	var target:ball = valid_target()
	if target==null or not behind(target) or rear_hold<behind_hold: return false
	rage_origin = global_position
	rage_left = rage_duration
	exposure_left = 0.0
	rear_hold = 0.0
	_attack_left = 0.15
	lightning_wait = true
	set_phase(Phase.RAGE)
	fog.refresh_left = 0.0
	emit_event("thunder_warning",global_position)
	return true
func deal_rush_damage(target:ball,point:Vector2) -> bool:
	if not can_act() or phase!=Phase.RAGE or lightning_wait or not U.enemy(self,target): return false
	var before:float = float(target.health)
	var victim:WeakRef = weakref(target)
	var accepted:bool = U.damage(self,target,attack_damage(),point)
	var after:Variant = victim.get_ref()
	var remaining:float = maxf(float(after.health),0.0) if is_instance_valid(after) else 0.0
	if accepted and before>remaining:
		rush_hits += 1
		pass # Actual HP feedback is now emitted by the victim.
	return accepted
func sweep_mist_damage(from:Vector2,to:Vector2) -> void:
	if not is_rush_mist() or not can_act() or from.distance_squared_to(to)<0.0001: return
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,candidate) or dash_hit_ids.has(candidate.get_instance_id()): continue
		if U.segment_distance(ball.body_point_seg(candidate,from,to),from,to)>16.0+U.radius(candidate): continue
		if not fog.line_visible(from,candidate.global_position,self): continue
		dash_hit_ids[candidate.get_instance_id()] = true
		deal_rush_damage(candidate,from)
func set_phase(next:int) -> void:
	phase = next
	if next!=Phase.RAGE: rush = Rush.MIST; rush_left = 0.0
	phase_started = clock
	apply_phase_flags()
	_transition += 1
	if multiplayer.has_multiplayer_peer(): _phase_snapshot.rpc(network_visual_state())
func apply_phase_flags() -> void:
	visible = phase!=Phase.VANISHED and not is_attack_hidden() and health>0
	if is_instance_valid(health_bar): health_bar.suppress_floating_text = phase==Phase.VANISHED or is_attack_hidden()
	if phase==Phase.RAGE and not lightning_wait and is_instance_valid(fog): fog.thunder_clear(self)
	if phase==Phase.VANISHED or is_attack_hidden():
		for popup:Node in get_tree().get_nodes_in_group("__damage_text_runtime"):
			var ref:Variant = popup.get_meta("combat_visual_owner",null)
			if ref is WeakRef and ref.get_ref()==self:
				if popup is CanvasItem: popup.hide()
				popup.queue_free()
	collision_layer = 0 if phase==Phase.VANISHED or is_attack_hidden() else _saved_layer
	collision_mask = 0 if phase==Phase.VANISHED else 1 if is_attack_hidden() else _saved_mask
	if phase==Phase.VANISHED:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		direction = Vector2.ZERO
		if is_instance_valid(eye_fx): eye_fx.trails.clear()
	_refresh_locking()
@rpc("authority","call_remote","reliable")
func _phase_snapshot(data:Dictionary) -> void: accept_visual(data)
func body_alpha() -> float:
	var time:float = clock if is_multiplayer_authority() else _view_clock
	if phase==Phase.VANISHED or is_attack_hidden(): return 0.0
	return clampf((time-phase_started)/0.35,0.0,1.0)
func _fog_gait() -> RefCounted:
	if gait == null:
		gait = MC_LEGS.create(float(BODY.get_frame_count(&"walk"))/maxf(BODY.get_animation_speed(&"walk"),0.001),[0.25,0.75])
		gait.observe(self)
	return gait
func visual_mob() -> void:
	visible = phase!=Phase.VANISHED and not is_attack_hidden() and health>0
	if not is_instance_valid(image): return
	var time:float = clock if is_multiplayer_authority() else _view_clock
	var legs:RefCounted = _fog_gait()
	var legs_step:float = _legs_delta
	_legs_delta = 0.0
	if health > 0 and is_combat_runtime_active() and phase != Phase.VANISHED and not is_attack_hidden():
		legs.tick(self,legs_step,dizziness != true)
	else:
		legs.observe(self)
		legs.reset_rest()
	_clip = &"attack" if _swing_left>0.0 else &"idle" if legs.at_rest else &"rage" if phase==Phase.RAGE else &"walk"
	_frame_index = int(time*BODY.get_animation_speed(_clip))%BODY.get_frame_count(_clip)
	if _clip == &"walk": _frame_index = legs.walk_index(BODY.get_frame_count(&"walk"))
	elif _clip == &"rage": _frame_index = legs.walk_index(BODY.get_frame_count(&"rage")*2)%BODY.get_frame_count(&"rage")
	image.texture = BODY.get_frame_texture(_clip,_frame_index)
	image.self_modulate = Color(0.9,0.92,0.95,body_alpha())
	image.visible = phase!=Phase.VANISHED and not is_attack_hidden() and health>0
	face_horizontal(player_control_direction if is_player_controlled() else direction,false)
func eye_texture() -> Texture2D: return EYES.get_frame_texture(_clip,_frame_index)
func visual_state() -> Dictionary:
	return {"time":clock,"transition":_transition,"phase":phase,"started":phase_started,"rage_left":rage_left,"lightning_wait":lightning_wait,"rage_origin":rage_origin,"vanish_left":vanish_left,"swing":_swing_left,"rush":rush,"rush_left":rush_left,"attack_kind":attack_kind,"dash_direction":dash_direction,"dash_remaining":dash_remaining,"face_point":face_point,"face_fired":face_fired,"retreat_direction":retreat_direction,"point":global_position}
func accept_visual(data:Dictionary) -> void:
	if int(data.get("transition",0))<_transition or float(data.get("time",0.0))<_last_state_time: return
	super.accept_visual(data)
	_last_state_time = _view_clock
	_transition = int(data.get("transition",0))
	phase = int(data.get("phase",Phase.STALK))
	phase_started = float(data.get("started",0.0))
	rage_left = float(data.get("rage_left",0.0))
	lightning_wait = bool(data.get("lightning_wait",false))
	rage_origin = data.get("rage_origin",global_position)
	vanish_left = float(data.get("vanish_left",0.0))
	_swing_left = float(data.get("swing",0.0))
	rush = int(data.get("rush",Rush.MIST))
	rush_left = float(data.get("rush_left",0.0))
	attack_kind = int(data.get("attack_kind",0))
	dash_direction = data.get("dash_direction",Vector2.ZERO)
	dash_remaining = float(data.get("dash_remaining",0.0))
	face_point = data.get("face_point",global_position)
	face_fired = bool(data.get("face_fired",false))
	retreat_direction = data.get("retreat_direction",Vector2.ZERO)
	if not is_multiplayer_authority(): global_position = data.get("point",global_position)
	apply_phase_flags()
func emit_event(kind:String,point:Vector2,amount:float = 0.0) -> void:
	if not is_multiplayer_authority(): return
	_event_id += 1
	if multiplayer.has_multiplayer_peer(): _fog_event.rpc(_event_id,kind,point,amount)
	_fog_event(_event_id,kind,point,amount)
@rpc("authority","call_remote","reliable")
func _fog_event(id:int,kind:String,point:Vector2,amount:float) -> void:
	if id<=_last_event: return
	_last_event = id
	if kind=="thunder_warning":
		lightning_visual = MC_ABILITIES.lightning(charge_fx,point,id*7919,62.0,0.68,{
			"scene":LIGHTNING,"name":"FogManCreeperLightning","on_impact":_on_lightning_impact
		})
		return # Shared effect owns both warning thunder and impact explosion sounds.
	if kind in ["spawn","vanish"] and is_instance_valid(effects): effects.burst(kind,point)
	if not is_combat_runtime_active(): return
	var player:AudioStreamPlayer2D
	if kind=="hit":
		player = AUDIO.play(self,"entity.player.hurt",point,2.0-26.0/(1.0+maxf(amount,0.0)/50.0),false,true,true,true)
	elif VOICES.has(kind):
		var active:Array[Node] = get_tree().get_nodes_in_group("MCFogVoice")
		if active.size()>=12:
			if kind=="whisper": return
			active[0].stop()
			active[0].remove_from_group("MCFogVoice")
			active[0].queue_free()
		player = AudioStreamPlayer2D.new()
		player.stream = VOICES[kind]
		player.volume_db = -12.0 if kind=="whisper" else -7.0
		player.max_distance = 1800.0
		player.attenuation = 0.4
		if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
		get_tree().current_scene.add_child(player)
		player.global_position = point
		player.add_to_group("MCFogVoice")
		player.add_to_group("BattleTransient")
		player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
		player.play()
	if is_instance_valid(player): _voices.append({"player":weakref(player),"left":4.0 if kind=="rage" else 5.0,"kind":kind})
func _process(delta:float) -> void:
	_legs_delta += maxf(delta,0.0)
	super._process(delta)
	for i:int in range(_voices.size()-1,-1,-1):
		var player:Variant = _voices[i].player.get_ref()
		if not is_instance_valid(player): _voices.remove_at(i); continue
		player.stream_paused = not is_combat_runtime_active()
		if not player.stream_paused: _voices[i].left -= delta
		if _voices[i].left<=0.0 or (_voices[i].kind=="rage" and phase!=Phase.RAGE):
			player.stop()
			player.queue_free()
			_voices.remove_at(i)
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if health>0 and is_multiplayer_authority() and amount>0 and rng.randf()<0.35: emit_event("hurt",global_position)
func Die() -> void:
	if _death_sound_done: return
	emit_event("vanish",global_position)
	if is_instance_valid(eye_fx): eye_fx.trails.clear()
	remove_from_group("MCFogMan")
	super.Die()
func _exit_tree() -> void:
	if is_instance_valid(charge_fx): charge_fx.queue_free()
	for entry:Dictionary in _voices:
		var player:Variant = entry.player.get_ref()
		if is_instance_valid(player): player.stop(); player.queue_free()
	super._exit_tree()
func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_FOG_MAN")

func _self_foot_world_position() -> Vector2:
	return image.global_transform*(image.offset+Vector2(0,92)) if is_instance_valid(image) else global_position
func _on_lightning_impact(point:Vector2) -> void:
	if phase!=Phase.RAGE or health<=0: return
	lightning_wait = false
	rage_origin = point
	rage_left = rage_duration
	var target:ball = valid_target()
	if not is_instance_valid(target): target = U.nearest(self)
	if is_multiplayer_authority():
		if is_player_controlled(): set_rush(Rush.RECOVER,0.0)
		elif is_instance_valid(target): start_rush_attack(target)
	fog.thunder_clear(self)
	if is_multiplayer_authority():
		emit_event("rage",point)
		if multiplayer.has_multiplayer_peer(): _phase_snapshot.rpc(network_visual_state())

func is_attack_hidden() -> bool:
	return phase==Phase.RAGE and not lightning_wait and rush in [Rush.MIST,Rush.FACE_VANISH,Rush.FACE_SHOW]
func is_face_hidden() -> bool:
	return phase==Phase.RAGE and not lightning_wait and rush in [Rush.FACE_VANISH,Rush.FACE_SHOW]
func is_rush_mist() -> bool:
	return phase==Phase.RAGE and not lightning_wait and rush==Rush.MIST
func set_rush(next:int,duration:float) -> void:
	rush = next
	rush_left = duration
	if next in [Rush.MIST,Rush.FACE_VANISH,Rush.FACE_SHOW] and is_instance_valid(eye_fx): eye_fx.trails.clear()
	apply_phase_flags()
	if is_multiplayer_authority():
		_transition += 1
		if multiplayer.has_multiplayer_peer(): _phase_snapshot.rpc(network_visual_state())
func start_rush_attack(target:ball,kind:int = -1) -> void:
	if not is_multiplayer_authority() or not can_act() or phase!=Phase.RAGE or lightning_wait or not U.enemy(self,target): return
	attack_kind = rng.randi_range(0,1) if kind<0 else clampi(kind,0,1)
	_target_ref = weakref(target)
	dash_hit_ids.clear()
	face_fired = false
	if attack_kind==0:
		mist_casts += 1
		dash_direction = global_position.direction_to(ball.body_point(target,global_position))
		if dash_direction==Vector2.ZERO: dash_direction = Vector2.RIGHT
		dash_remaining = minf(global_position.distance_to(ball.body_point(target,global_position))+100.0,500.0)
		set_rush(Rush.MIST,1.6)
	else:
		face_casts += 1
		if is_instance_valid(charge_fx): charge_fx.motes.clear()
		set_rush(Rush.FACE_VANISH,0.38)
func rush_step(target:ball,delta:float) -> void:
	rush_left -= delta
	match rush:
		Rush.MIST:
			direction = dash_direction
			if dash_remaining<=0.0 or rush_left<=0.0:
				retreat_direction = choose_retreat(target)
				set_rush(Rush.RETREAT,0.45)
		Rush.FACE_VANISH:
			direction = Vector2.ZERO
			if rush_left<=0.0 and not manifest_face(target):
				retreat_direction = choose_retreat(target)
				set_rush(Rush.RETREAT,0.3)
		Rush.FACE_SHOW:
			direction = Vector2.ZERO
			if rush_left<=0.0:
				retreat_direction = choose_retreat(target)
				set_rush(Rush.RETREAT,0.45)
		Rush.RETREAT:
			direction = retreat_direction
			if direction==Vector2.ZERO or not body_clear(global_position+direction*20.0):
				retreat_direction = choose_retreat(target)
				direction = retreat_direction
			if rush_left<=0.0: start_rush_attack(target)
func manifest_face(target:ball) -> bool:
	if not can_act() or phase!=Phase.RAGE or rush!=Rush.FACE_VANISH or face_fired or not U.enemy(self,target): return false
	var away:Vector2 = ball.body_point(target,global_position).direction_to(global_position)
	if away==Vector2.ZERO: away = Vector2.LEFT
	var chosen:Vector2 = Vector2.INF
	for i:int in range(12):
		var point:Vector2 = ball.body_point(target,global_position)+away.rotated(TAU*i/12.0)*64.0
		if body_clear(point) and fog.line_visible(point,target.global_position,self) and fog.line_visible(global_position,point,self):
			chosen = point
			break
	if chosen==Vector2.INF: return false
	global_position = chosen
	reset_physics_interpolation()
	face_point = chosen
	face_fired = true
	set_rush(Rush.FACE_SHOW,0.28)
	# Snapshot candidates before damage callbacks can delete targets.
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,candidate): continue
		if ball.body_point(candidate,face_point).distance_to(face_point)>face_radius: continue
		if not fog.line_visible(face_point,candidate.global_position,self): continue
		deal_rush_damage(candidate,face_point)
	return true
func choose_retreat(target:ball) -> Vector2:
	var away:Vector2 = ball.body_point(target,global_position).direction_to(global_position)
	if away==Vector2.ZERO: away = Vector2.LEFT
	for angle:float in [0.0,0.55,-0.55,1.1,-1.1,1.57,-1.57]:
		var candidate:Vector2 = away.rotated(angle)
		if body_clear(global_position+candidate*40.0) and fog.line_visible(global_position,global_position+candidate*40.0,self): return candidate
	return Vector2.ZERO
