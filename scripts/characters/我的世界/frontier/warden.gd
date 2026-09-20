extends "res://scripts/characters/我的世界/frontier/base.gd"
## Sound positions, not enemy references, drive decisions. Hits are always actual area/path contacts.
const SHRIEKER:Texture2D = preload("res://Images/characters/我的世界/frontier/shrieker_block.png")
const WARDEN:SpriteFrames = preload("res://Images/characters/我的世界/frontier/warden_frames.tres")
const NOISE = preload("res://scripts/characters/我的世界/frontier/battle_noise.gd")
const WAVE = preload("res://scripts/characters/我的世界/frontier/warden_wave.gd")
enum Form { DORMANT, EMERGING, AWAKE, BURROWING }
@export var listen_range:float = 360.0
@export var hearing_fx_threshold:float = 16.0
@export var alert_max:float = 100.0
@export var probe_count:int = 5
@export var probe_interval:float = 0.32
@export var probe_range:float = 300.0
@export var probe_speed:float = 320.0
@export var probe_end_speed:float = 100.0
@export var shrieker_speed:float = 54.0
@export var emerge_duration:float = 3.0
@export var sonic_windup:float = 1.15
@export var sonic_range:float = 360.0
@export var melee_range:float = 50.0
@export var sonic_noise_threshold:float = 38.0
@export var rage_noise_threshold:float = 82.0
@export var rage_speed_multiplier:float = 1.6
@export var sleep_delay:float = 8.0
var form:int = Form.DORMANT
var alert_level:float = 0.0
var signals_received:int = 0
var probe_left:float = 0.0
var _probe_wait:float = 0.0
var probes_remaining:int = 0
var ritual_epoch:int = 0
var _echo_tokens:Dictionary = {}
var _pending_echoes:Dictionary = {}
var rage_left:float = 0.0
var quiet_time:float = 0.0
var form_left:float = 0.0
var sonic_left:float = 0.0
var sonic_origin:Vector2 = Vector2.ZERO
var sonic_end:Vector2 = Vector2.ZERO
var sonic_recover:float = 0.0
var melee_left:float = 0.0
var melee_visual_left:float = 0.0
var _melee_heading:Vector2 = Vector2.RIGHT
var _sonic_heading:Vector2 = Vector2.RIGHT
var listen_heading:Vector2 = Vector2.RIGHT
var heard_position:Vector2 = Vector2.ZERO
var heard_strength:float = 0.0
var sounds:Dictionary = {}
var _turn_wait:float = 0.0
var _bounce_hold:float = 0.0
var _attack_cooldown:float = 0.0
var _sonic_cooldown:float = 0.0
var _dormant_max:int = 600
var _changing_form:bool = false
var summons:int = 0
var sonic_casts:int = 0
var probe_casts:int = 0
var _sonic_pending:bool = false
var _melee_pending:bool = false
var _collider_awake:bool = false
var _wave_serial:int = 0
var _last_wave_event:int = 0
var waves:Array = []
var voice_controller:Node
# 瞄准提示：攻击前摇期间在瞄准的声源位置画 MC 风格蓝圈（fx.gd 绘制）。aim_left 倒数到 0 或攻击取消即消失。
var aim_point:Vector2 = Vector2.ZERO
var aim_left:float = 0.0
var aim_total:float = 0.0
var aim_kind:String = ""
func _aim(kind:String,point:Vector2,duration:float) -> void:
	aim_kind = kind
	aim_point = point
	aim_total = maxf(duration,0.05)
	aim_left = aim_total
func _clear_aim() -> void:
	aim_left = 0.0
	aim_total = 0.0
	aim_kind = ""
func role_key() -> String: return "warden"
func get_preview_texture() -> Texture2D: return SHRIEKER
func _ready() -> void:
	super._ready()
	voice_controller=preload("res://scripts/characters/我的世界/frontier/warden_voice.gd").new()
	voice_controller.name="WardenVoice"
	voice_controller.actor=self
	voice_controller.set_multiplayer_authority(get_multiplayer_authority())
	add_child(voice_controller)
	_dormant_max = Max_health
	if form==Form.DORMANT:
		Speed=shrieker_speed
		default_properties["Speed"]=Speed
	add_to_group("MCWardenListener")
	if is_multiplayer_authority(): NOISE.ensure(self)
# Ordinary knockback temporarily locks locomotion, but is not a true stun.
func can_act() -> bool:
	if form!=Form.DORMANT: return super.can_act()
	if not active() or not Can_Attack or is_damage_output_disabled(): return false
	if not dizziness: return true
	var locks:int=int(get_meta("generic_motion_lock_count",0))
	if locks<=0 or bool(get_meta("generic_motion_lock_baseline",false)): return false
	var motion_locks:int=0
	for child:Node in get_children():
		if child.get_script()==KNOCKBACK_EFFECT_SCRIPT and child._lock_acquired:
			if child._stage==1: return false
			motion_locks+=1
	return motion_locks==locks
func sonic_attack_busy() -> bool:
	if _sonic_pending or sonic_left>0.0 or sonic_recover>0.0: return true
	for wave:Variant in waves:
		if is_instance_valid(wave) and not wave.is_queued_for_deletion() and wave.kind=="sonic": return true
	return false
func sonic_can_continue() -> bool:
	# Once committed, control effects cannot cancel or stall the sonic charge/flight.
	return active() and form==Form.AWAKE and Can_Attack and not is_damage_output_disabled()
static func impact_event(actual:float) -> String:
	return "entity.player.attack.crit" if actual>50.0 else "entity.player.hurt"
static func impact_volume(actual:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual)
func damage_with_sound(target:ball,amount:float,point:Vector2,ignore_block:bool=false) -> bool:
	if not is_multiplayer_authority() or not U.enemy(self,target) or amount<=0 or is_damage_output_disabled(): return false
	var reference_health:float=target.get_impact_reference_health()
	var before:float=maxf(target.health,0.0)
	var hit_point:Vector2=target.global_position
	var accepted:bool=target.receive_positional_damage(amount,point,ignore_block,self)
	var remaining:float=maxf(target.health,0.0) if is_instance_valid(target) else 0.0
	var actual:float=maxf(before-remaining,0.0)
	if actual>0.0:
		var event:String=impact_event(actual)
		var volume:float=impact_volume(actual)
		if multiplayer.has_multiplayer_peer(): _warden_impact.rpc(event,hit_point,volume,actual,reference_health)
		_warden_impact(event,hit_point,volume,actual,reference_health)
	return accepted
@rpc("authority","call_remote","reliable")
func _warden_impact(event:String,point:Vector2,volume:float,actual:float=0.0,reference_health:float=200.0) -> void:
	# Actual high-damage hits use the common bounded focus/hitstop system.
	# HP-relative feedback already happens in the target setter; only supplement it,
	# without duplicating camera shake, particles, hit flash or damage reporting.
	if actual>50.0 and active() and not Game.now_stop_state and not get_tree().paused:
		var world:Node=get_tree().current_scene
		var feedback_health:float=minf(maxf(reference_health,1.0),200.0)
		if is_instance_valid(world):
			if world.has_method("request_damage_focus"): world.request_damage_focus(actual,feedback_health,point)
			if world.has_method("request_heavy_hitstop"): world.request_heavy_hitstop(actual,feedback_health,point)
	var player:AudioStreamPlayer2D=AUDIO.play(self,event,point,volume,false,true,true,true)
	if is_instance_valid(player): _cue_players.append(player)
func attack_damage(multiplier:float = 1.0) -> float:
	return super.attack_damage(multiplier*(0.5 if form==Form.AWAKE else 1.0)) if form==Form.AWAKE or (form==Form.DORMANT and probe_left>0.0) else 0.0
func sound_at(point:Vector2,power:float) -> float:
	return maxf(power,0.0)*maxf(0.0,1.0-global_position.distance_to(point)/maxf(listen_range,1.0))
func hear_noise(source:Node,point:Vector2,kind:String,power:float) -> bool:
	if not can_act() or not U.enemy(self,source) or not point.is_finite(): return false
	var perceived:float = sound_at(point,power)
	if perceived<=0.0: return false
	if perceived>=hearing_fx_threshold and form in [Form.DORMANT,Form.AWAKE]: emit_effect("heard_noise",point)
	if is_instance_valid(voice_controller): voice_controller.heard()
	quiet_time = 0.0
	var key:String = str(source.get_instance_id())+":"+kind
	# Copy the sound's world position. Never retain a target or track its later position silently.
	sounds[key] = {"point":point,"power":power,"age":0.0,"kind":kind}
	var axis:Vector2 = global_position.direction_to(point)
	if not axis.is_zero_approx(): listen_heading = axis
	if form==Form.DORMANT:
		# Hearing steers the probe, never the shrieker locomotion.
		if probe_left<=0.0:
			alert_level = minf(alert_max,alert_level+perceived*0.25)
			if alert_level>=alert_max: begin_probe()
	elif form==Form.AWAKE and perceived>=rage_noise_threshold:
		if rage_left<=0.0 and is_instance_valid(voice_controller): voice_controller.roar()
		rage_left = 2.8
	return true
func hear(source:ball,power:float = 24.0) -> bool:
	return hear_noise(source,source.global_position,"action",power) if is_instance_valid(source) else false
func _best_sound() -> Dictionary:
	var best:Dictionary = {}
	var volume:float = 0.0
	for record:Dictionary in sounds.values():
		var value:float = sound_at(record.point,float(record.power))*maxf(0.0,1.0-float(record.age)/2.0)
		if value>volume:
			volume = value
			best = {"point":record.point,"volume":value}
	return best
func begin_probe() -> bool:
	if not can_act() or form!=Form.DORMANT or probe_left>0.0 or alert_level<alert_max: return false
	probes_remaining = maxi(1,probe_count)
	probe_left = probes_remaining*probe_interval
	_probe_wait = 0.0
	alert_level = 0.0
	var first:Dictionary = _best_sound()
	_aim("probe",first.point if not first.is_empty() else global_position+listen_heading*probe_range*0.5,probe_interval)
	cue("shrieker",-3.0)
	return true
func emit_probe() -> bool:
	if not can_act() or form!=Form.DORMANT or probe_left<=0.0 or probes_remaining<=0: return false
	# Re-aim from the current muzzle to a recorded sound position, not a live target.
	var sound:Dictionary = _best_sound()
	if not sound.is_empty():
		var axis:Vector2 = global_position.direction_to(sound.point)
		if not axis.is_zero_approx(): listen_heading = axis
	_launch_wave("probe",global_position,listen_heading)
	probe_casts += 1
	probes_remaining -= 1
	# 下一发探测波瞄准的位置：仍有余弹时继续提示，最后一发后收起。
	if probes_remaining>0: _aim("probe",sound.point if not sound.is_empty() else global_position+listen_heading*probe_range*0.5,probe_interval)
	else: _clear_aim()
	cue("probe_fire",-3.0)
	if probes_remaining<=0: probe_left=0.0
	return true
func probe_contact(epoch:int,token:String,point:Vector2) -> void:
	if not can_act() or form!=Form.DORMANT or epoch!=ritual_epoch or signals_received>=5: return
	if _pending_echoes.has(token) or _echo_tokens.has(token) or _pending_echoes.size()>=64: return
	_pending_echoes[token] = true
	_launch_wave("return",point,Vector2.ZERO,token)
func receive_echo(epoch:int,token:String) -> bool:
	if not can_act() or form!=Form.DORMANT or epoch!=ritual_epoch or _echo_tokens.has(token) or not _pending_echoes.has(token): return false
	_pending_echoes.erase(token)
	_echo_tokens[token] = true
	signals_received = mini(5,signals_received+1)
	if signals_received==5: begin_emergence()
	return true
func _launch_wave(kind:String,point:Vector2,axis:Vector2,token:String = "") -> void:
	_wave_serial += 1
	if multiplayer.has_multiplayer_peer(): _wave_event.rpc(_wave_serial,kind,point,axis,ritual_epoch,token)
	_wave_event(_wave_serial,kind,point,axis,ritual_epoch,token)
@rpc("authority","call_remote","reliable")
func _wave_event(serial:int,kind:String,point:Vector2,axis:Vector2,epoch:int,token:String) -> void:
	if serial<=_last_wave_event or health<=0: return
	_last_wave_event = serial
	for i:int in range(waves.size()-1,-1,-1):
		if not is_instance_valid(waves[i]) or waves[i].is_queued_for_deletion(): waves.remove_at(i)
	if waves.size()>=48: return
	var wave:Node2D = WAVE.new()
	preload("res://scripts/effects/我的世界/mc_explosion.gd").runtime_container(self).add_child(wave)
	wave.setup(self,kind,point,axis,serial,epoch,token)
	waves.append(wave)
func begin_emergence() -> bool:
	if not can_act() or form!=Form.DORMANT or signals_received<5: return false
	form = Form.EMERGING
	form_left = emerge_duration
	_cancel_attacks(true)
	velocity = Vector2.ZERO
	cue("summon_shriek",-3.0)
	cue("emerge",-2.0)
	emit_effect("emerge",global_position)
	emit_effect("summon_screen",global_position)
	return true
func _form_stats(awake:bool) -> void:
	if health<=0: return
	_changing_form = true
	var ratio:float = clampf(float(health)/maxf(float(Max_health),1.0),0.0,1.0)
	Max_health = _dormant_max*2 if awake else _dormant_max
	default_properties["Max_health"] = Max_health
	Speed = 66.0 if awake else shrieker_speed
	default_properties["Speed"] = Speed
	var had_restore:bool = has_meta("death_return_restore")
	var old_restore:Variant = get_meta("death_return_restore") if had_restore else false
	set_meta("death_return_restore",true)
	health = maxi(1,int(round(ratio*Max_health)))
	if had_restore: set_meta("death_return_restore",old_restore)
	else: remove_meta("death_return_restore")
	_changing_form = false
func finish_emergence() -> bool:
	if not can_act() or form!=Form.EMERGING or form_left>0.0 or signals_received<5: return false
	form = Form.AWAKE
	_form_stats(true)
	update_form_collider(true)
	quiet_time = 0.0
	_attack_cooldown = 0.4
	_sonic_cooldown = 1.5
	summons += 1
	return true
func begin_burrow() -> void:
	if form!=Form.AWAKE or not can_act(): return
	form = Form.BURROWING
	form_left = 1.8
	_cancel_attacks(true)
	cue("warden_dig",-3.0)
	emit_effect("warden_burrow_debris",global_position)
func _finish_burrow() -> void:
	if form!=Form.BURROWING or health<=0: return
	form = Form.DORMANT
	alert_level = 0.0
	signals_received = 0
	ritual_epoch += 1
	_echo_tokens.clear()
	sounds.clear()
	heard_strength = 0.0
	rage_left = 0.0
	quiet_time = 0.0
	_form_stats(false)
	update_form_collider(false)
func _cancel_attacks(clear_waves:bool = false) -> void:
	_sonic_pending = false
	_melee_pending = false
	melee_left = 0.0
	sonic_left = 0.0
	sonic_recover = 0.0
	melee_visual_left = 0.0
	probe_left = 0.0
	probes_remaining = 0
	_clear_aim()
	if clear_waves:
		_pending_echoes.clear()
		for wave:Variant in waves:
			if is_instance_valid(wave): wave.queue_free()
		waves.clear()
func step_mob(delta:float) -> void:
	if not is_combat_runtime_active() or Game.now_stop_state or get_tree().paused: return
	if not can_act() and sonic_can_continue():
		sonic_recover=maxf(0.0,sonic_recover-delta)
		# Keep only committed sonic attacks alive; stun still prevents new attacks and normal movement.
		_melee_pending=false
		melee_left=0.0
		melee_visual_left=0.0
		if _sonic_pending:
			sonic_origin=global_position
			sonic_end=sonic_origin+_sonic_heading*sonic_range
			sonic_left=maxf(0.0,sonic_left-delta)
			aim_left=maxf(0.0,aim_left-delta)
			if sonic_left<=0.0: release_sonic()
		return
	if not can_act():
		_cancel_attacks(true)
		sounds.clear()
		heard_strength = 0.0
		rage_left = 0.0
		return
	quiet_time += delta
	rage_left = maxf(0.0,rage_left-delta)
	_turn_wait = maxf(0.0,_turn_wait-delta)
	_bounce_hold = maxf(0.0,_bounce_hold-delta)
	_attack_cooldown = maxf(0.0,_attack_cooldown-delta)
	_sonic_cooldown = maxf(0.0,_sonic_cooldown-delta)
	sonic_recover = maxf(0.0,sonic_recover-delta)
	melee_visual_left = maxf(0.0,melee_visual_left-delta)
	aim_left = maxf(0.0,aim_left-delta)
	for key:Variant in sounds.keys():
		sounds[key].age += delta
		if float(sounds[key].age)>=2.0: sounds.erase(key)
	var sound:Dictionary = _best_sound()
	heard_strength = float(sound.get("volume",0.0))
	if not sound.is_empty():
		heard_position = sound.point
		if form==Form.AWAKE and _turn_wait<=0.0 and _bounce_hold<=0.0 and not is_player_controlled():
			var axis:Vector2 = global_position.direction_to(heard_position)
			if not axis.is_zero_approx(): direction = axis
			_turn_wait = 0.15
	if form in [Form.EMERGING,Form.BURROWING]:
		form_left = maxf(0.0,form_left-delta)
		if form_left<=0.0:
			if form==Form.EMERGING: finish_emergence()
			else: _finish_burrow()
		return
	if form==Form.DORMANT:
		if probe_left>0.0:
			_probe_wait -= delta
			if _probe_wait<=0.0:
				emit_probe()
				_probe_wait += probe_interval
			probe_left = maxf(0.001,probes_remaining*probe_interval) if probes_remaining>0 else 0.0
		elif quiet_time>1.0: alert_level = maxf(0.0,alert_level-delta*12.0)
		return
	if sonic_left>0.0:
		sonic_origin = global_position
		sonic_end = sonic_origin+_sonic_heading*sonic_range
		sonic_left = maxf(0.0,sonic_left-delta)
		if sonic_left<=0.0: release_sonic()
		return
	if sonic_attack_busy():
		_melee_pending=false; melee_left=0.0; melee_visual_left=0.0
		return
	if melee_left>0.0:
		melee_left = maxf(0.0,melee_left-delta)
		if melee_left<=0.0: release_melee()
		return
	if quiet_time>=sleep_delay:
		begin_burrow()
		return
	if not sound.is_empty() and not is_player_controlled():
		if global_position.distance_to(sound.point)<=melee_range: begin_melee()
		elif heard_strength>=sonic_noise_threshold: begin_sonic()
func begin_melee() -> bool:
	if not can_act() or form!=Form.AWAKE or melee_left>0.0 or sonic_attack_busy() or _attack_cooldown>0.0: return false
	var sound:Dictionary = _best_sound()
	if sound.is_empty() or global_position.distance_to(sound.point)>melee_range: return false
	_melee_heading = global_position.direction_to(sound.point)
	if _melee_heading.is_zero_approx(): _melee_heading = listen_heading
	_melee_pending = true
	melee_left = 0.2
	melee_visual_left = 0.4
	_attack_cooldown = 1.65
	_aim("melee",sound.point,melee_left)
	return true
func release_melee() -> void:
	if sonic_attack_busy():
		_melee_pending=false; melee_left=0.0; melee_visual_left=0.0
		return
	if not can_act() or form!=Form.AWAKE or not _melee_pending: return
	_melee_pending = false
	_clear_aim()
	for target:ball in foes(global_position,melee_range+100.0):
		var offset:Vector2 = target.global_position-global_position
		if offset.length()>melee_range+U.radius(target) or (not offset.is_zero_approx() and offset.normalized().dot(_melee_heading)<0.45): continue
		if U.line_clear(self,global_position,target.global_position) and damage_with_sound(target,attack_damage(2.0),target.global_position):
			if target.health>0 and target.can_receive_negative_effects(): target.apply_knockback(_melee_heading,75.0,430.0,0.0,0.0,{"lock_control":false,"source":self,"stop_on_character":false,"collision_damage":0.0})
			emit_effect("hit",target.global_position)
	cue("warden_hit",-3.0)
func begin_sonic() -> bool:
	if not can_act() or form!=Form.AWAKE or _sonic_cooldown>0.0 or sonic_attack_busy() or melee_left>0.0 or _melee_pending: return false
	var sound:Dictionary = _best_sound()
	if sound.is_empty() or float(sound.volume)<sonic_noise_threshold or global_position.distance_to(sound.point)<=melee_range: return false
	_sonic_heading = global_position.direction_to(sound.point)
	if _sonic_heading.is_zero_approx(): return false
	sonic_origin = global_position
	sonic_end = sonic_origin+_sonic_heading*sonic_range
	_melee_pending=false; melee_left=0.0; melee_visual_left=0.0
	_sonic_pending = true
	sonic_left = sonic_windup
	_sonic_cooldown = 6.0
	_aim("sonic",sound.point,sonic_windup)
	cue("sonic_charge",0.0)
	emit_effect("sonic_charge_screen",global_position)
	return true
func release_sonic() -> void:
	if not sonic_can_continue() or not _sonic_pending: return
	sonic_left=0.0
	_sonic_pending = false
	_clear_aim()
	sonic_origin = global_position
	sonic_end = sonic_origin+_sonic_heading*sonic_range
	_launch_wave("sonic",sonic_origin,_sonic_heading)
	sonic_recover = 0.5
	sonic_casts += 1
	cue("sonic_boom",2.0)
	emit_effect("sonic_screen",global_position)
func move(speed_value:float,delta:float) -> void:
	if not active(): return
	if form==Form.DORMANT:
		super.move(speed_value,delta)
		return
	if form!=Form.AWAKE:
		super.stand(delta)
		return
	var factor:float = rage_speed_multiplier if rage_left>0.0 else 1.0
	if sonic_left>0.0: factor = 0.22
	elif melee_left>0.0: factor = 0.35
	# Never stop merely because there is no sound; use shared player input, motion and wall bounce logic.
	super.move(speed_value*factor,delta)
func when_collide(speed_value:float,collision:KinematicCollision2D) -> void:
	super.when_collide(speed_value,collision)
	_bounce_hold = 0.35
func Attack() -> void:
	Attacking = false
	begin_melee()
func Skill() -> void:
	Using_Skill = false
	begin_sonic()
func player_control_action(action_index:int) -> void:
	if action_index==0: begin_melee()
	elif action_index==1: begin_sonic()
func visual_mob() -> void:
	if not is_instance_valid(image): return
	update_form_collider(form in [Form.AWAKE,Form.BURROWING])
	if form==Form.DORMANT: image.texture = SHRIEKER
	else:
		var clip:StringName = &"idle"
		var progress:float = -1.0
		if form==Form.EMERGING: clip=&"emerge"; progress=1.0-form_left/emerge_duration
		elif form==Form.BURROWING: clip=&"dig"; progress=1.0-form_left/1.8
		elif sonic_left>0.0: clip=&"sonic"; progress=(1.0-sonic_left/sonic_windup)*0.72
		elif sonic_recover>0.0: clip=&"sonic"; progress=0.72+0.28*(1.0-sonic_recover/0.5)
		elif melee_visual_left>0.0: clip=&"attack"; progress=1.0-melee_visual_left/0.4
		elif velocity.length_squared()>4.0: clip=&"walk"
		var count:int = WARDEN.get_frame_count(clip)
		var index:int = clampi(roundi(clampf(progress,0,1)*float(count-1)),0,count-1) if progress>=0 else int(_view_clock*WARDEN.get_animation_speed(clip))%count
		image.texture = WARDEN.get_frame_texture(clip,index)
	image.rotation = listen_heading.angle() if form==Form.DORMANT else 0.0
	face_horizontal(direction,true)
	# Keep bars and echo icons, but never show overhead status text in any form.
	if not _status_text.is_empty():
		_status_text=""
		side_status_remove_permanent("left","mc_frontier")
func visual_state() -> Dictionary:
	return {"time":clock,"form":form,"alert":alert_level,"signals":signals_received,"probe":probe_left,"probe_count":probes_remaining,"rage":rage_left,"epoch":ritual_epoch,"strength":heard_strength,"listen":listen_heading,"form_left":form_left,"sonic":sonic_left,"sonic_a":sonic_origin,"sonic_b":sonic_end,"recover":sonic_recover,"melee":melee_visual_left,"direction":direction,"aim":aim_point,"aim_left":aim_left,"aim_total":aim_total,"aim_kind":aim_kind}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	form = clampi(int(data.get("form",0)),0,3)
	alert_level = clampf(float(data.get("alert",0)),0,alert_max)
	signals_received = clampi(int(data.get("signals",0)),0,5)
	probe_left = maxf(0.0,float(data.get("probe",0)))
	probes_remaining = maxi(0,int(data.get("probe_count",0)))
	rage_left = maxf(0.0,float(data.get("rage",0)))
	ritual_epoch = int(data.get("epoch",0))
	heard_strength = maxf(0.0,float(data.get("strength",0)))
	listen_heading = data.get("listen",Vector2.RIGHT)
	form_left = float(data.get("form_left",0))
	sonic_left = float(data.get("sonic",0))
	sonic_origin = data.get("sonic_a",global_position)
	sonic_end = data.get("sonic_b",global_position)
	sonic_recover = float(data.get("recover",0))
	melee_visual_left = float(data.get("melee",0))
	direction = data.get("direction",direction)
	aim_point = data.get("aim",aim_point)
	aim_left = maxf(0.0,float(data.get("aim_left",0)))
	aim_total = maxf(0.0,float(data.get("aim_total",0)))
	aim_kind = str(data.get("aim_kind",""))
func client_visual_step(delta:float) -> void:
	if not is_combat_runtime_active(): return
	form_left=maxf(0,form_left-delta); sonic_left=maxf(0,sonic_left-delta)
	probe_left=maxf(0,probe_left-delta); rage_left=maxf(0,rage_left-delta)
	sonic_recover=maxf(0,sonic_recover-delta); melee_visual_left=maxf(0,melee_visual_left-delta)
	aim_left=maxf(0,aim_left-delta)
func get_debug_attack_regions() -> Array:
	if not can_act(): return []
	if melee_left>0.0: return [{"shape":"circle","position":global_position+_melee_heading*(melee_range*0.5),"radius":melee_range*0.5,"damage":attack_damage(2.0),"kind":"warden_sound_melee"}]
	if sonic_left>0.0 or probe_left>0.0:
		var axis:Vector2 = _sonic_heading if sonic_left>0.0 else listen_heading
		var reach:float = sonic_range if sonic_left>0.0 else probe_range
		return [{"shape":"rect","position":global_position+axis*reach*0.5,"half_extents":Vector2(reach*0.5,11.0*WAVE.SONIC_SCALE if sonic_left>0.0 else 11.0),"rotation":axis.angle(),"damage":attack_damage(3.0 if sonic_left>0.0 else 0.35),"kind":"warden_sonic"}]
	return []
func get_armor_test_effect_summary() -> String:
	if english():
		return "Start as a shrieker listening for enemy movement, collisions and attacks; distant sounds are weaker. Full alert fires probes at recorded sound positions. Hits damage and push enemies; enough returning echoes awaken the Warden.\nAwakening raises maximum health while preserving its percentage. Follow the strongest sound location rather than tracking a target. Nearby noise triggers melee; distant loud noise triggers a slowed charge and a terrain- and shield-piercing sonic knockback attack. Stun does not cancel committed sonic charges. Very loud noise grants a running burst; prolonged silence causes burrowing and resets alert and echoes."
	return "开局为尖啸体，监听敌人的移动、碰撞和攻击，声音随距离衰减；警戒充满后向记录的声源连发探测波，命中伤害并击退，回响返回并积累足够后唤醒监守者。\n苏醒后提高生命上限并保留血量比例，依靠最响的声源位置行动，而非持续锁定敌人；近处挥击，远处响声触发蓄力声波，穿墙穿盾并强力击退，已开始的声波蓄力不会被眩晕打断。\n巨响会使其短暂加速奔跑；持续安静后潜地，重新开始警戒与回响积累。"

func Die() -> void:
	if _death_sound_done: return
	if is_instance_valid(frontier_fx):
		for child:Node in frontier_fx.get_children():
			if child.is_in_group("MCWardenGroundDebris"): child.queue_free()
	_cancel_attacks(true)
	if form==Form.AWAKE: DEATH_FX.death_pose(self,image,direction.x>=0)
	else: ITEM_DEATH.spawn(self)
	super.Die()
func update_form_collider(awake:bool) -> void:
	if awake==_collider_awake or not is_instance_valid(collision_shape_2d): return
	_collider_awake = awake
	var shape:RectangleShape2D = collision_shape_2d.shape as RectangleShape2D
	if shape!=null: shape.set_deferred("size",Vector2(126,170) if awake else Vector2(96,74))
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if amount>0 and form==Form.AWAKE and not _changing_form: cue("warden_hurt",-5.0)
