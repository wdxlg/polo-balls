extends ball
## Sleeping cat: ordinary movement, passive sleep/wake clock, one active Z burst.
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const AUDIO = preload("res://scripts/characters/默认/ding_sleep/audio.gd")
const FX = preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
const WAVE = preload("res://scripts/characters/默认/ding_sleep/wave.gd")
const CLOSED:Texture2D = preload("res://Images/characters/默认/ding_sleep/猫闭眼.png")
const OPEN:Texture2D = preload("res://Images/characters/默认/ding_sleep/猫.png")
const Z_SCENE:String = "res://scenes/shooter/默认/丁某人_Z.tscn"
@export var sleep_duration:float = 60.0
@export var awake_duration:float = 2.0
@export var burst_interval:float = 4.0
@export var shot_interval:float = 0.2
@export var z_windup_time:float = 0.18
@export var z_stretch_time:float = 0.16
@export var z_recover_time:float = 0.28
@export var wave_windup_time:float = 0.28
@export var wave_shiver_time:float = 0.45
@export var wave_stretch_time:float = 0.16
@export var wave_recover_time:float = 0.32
const WAVE_FLAT:Vector2 = Vector2(1.55,0.42)
const WAVE_TALL:Vector2 = Vector2(0.52,1.72)
var wave_charging:bool = false
var pose_is_wave:bool = false
var _pose_pivot:Vector2 = Vector2.ZERO
var _pose_base:Transform2D = Transform2D.IDENTITY
var _pose_previous:Vector2 = Vector2.ONE
var _pose_current:Vector2 = Vector2.ONE
var _pose_tick:int = -1
const Z_FLAT:Vector2 = Vector2(1.28,0.62)
const Z_TALL:Vector2 = Vector2(0.66,1.38)
# Pose: 0 rest, 1 Z windup, 2 Z firing/hold, 3 recovery, 4 wave squash/shiver, 6 emitted wave.
var z_pose_phase:int = 0
var z_pose_age:float = 0.0
var z_recover_from:Vector2 = Vector2.ONE
@export var z_speed:float = 110.0
@export var z_turn_degrees:float = 35.0
@export var wave_max_radius:float = 320.0
@export var wave_duration:float = 0.8
var sleep_left:float = 60.0
var awake:bool = false
var awake_left:float = 0.0
var wave_age:float = 0.0
var wave_origin:Vector2 = Vector2.ZERO
var wake_serial:int = 0
var shots_fired:int = 0
var wakes_fired:int = 0
var _burst_wait:float = 4.0
var _shots_left:int = 0
var _shot_wait:float = 0.0
var _aim:Vector2 = Vector2.RIGHT
var _counter:Label
var _wave:Node2D
var _wave_serial:int = -1
var _sound_serial:int = 0
var _last_sound_serial:int = 0
var _voice_rng := RandomNumberGenerator.new()
var _ambient_wait:float = 2.0
var _ambient_ticket:Dictionary = {}
var _z_ticket:Dictionary = {}
var _tickets:Array[Dictionary] = []
var _dead:bool = false
var last_sound_role:String = ""
var _last_death_feedback:bool = false

func _enter_tree() -> void:
	# Configure before child synchronizer consumes spawn state (not in parent _ready).
	var sync:MultiplayerSynchronizer = get_node("MultiplayerSynchronizer")
	var config:SceneReplicationConfig = sync.replication_config.duplicate()
	# These transforms are derived from the synchronized pose; sending both applies it twice on spawn.
	for derived:NodePath in [NodePath("Graphics:scale"),NodePath("Graphics:position"),NodePath("Graphics/Image:global_position")]:
		if config.has_property(derived): config.remove_property(derived)
	for key:String in ["sleep_left","awake","awake_left","wave_age","wave_origin","wake_serial","direction","z_pose_phase","z_pose_age","z_recover_from","wave_charging","pose_is_wave"]:
		var path := NodePath(".:"+key)
		if not config.has_property(path): config.add_property(path)
		config.property_set_spawn(path,true)
		config.property_set_replication_mode(path,SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config

func _ready() -> void:
	Has_Collision_Damage = false
	motion_blur_enabled = false
	motion_stretch_enabled = false
	AfterImage_Speed = -1.0
	super._ready()
	self_hitbox.collision_layer = 0
	self_hitbox.collision_mask = 0
	self_hitbox.set_deferred("monitoring",false)
	# AutoFit has already sized the Sprite. Reuse its cached alpha bounds, not the collision rect.
	var rect:Rect2 = get_node("CharacterAutoFit")._texture_used_rect(CLOSED,image.centered,image.offset)["rect"]
	_pose_pivot = image.transform * Vector2(rect.get_center().x,rect.end.y)
	_pose_base = get_node("Graphics").transform
	_voice_rng.randomize()
	if is_multiplayer_authority(): sleep_left = maxf(sleep_duration,0.1)
	_burst_wait = maxf(burst_interval,0.1)
	_counter = Label.new()
	_counter.name = "SleepCountdown"
	_counter.position = Vector2(64,-142)
	_counter.add_theme_font_size_override("font_size",34)
	_counter.add_theme_color_override("font_color",Color("d4f5ff"))
	_counter.add_theme_color_override("font_outline_color",Color("15212b"))
	_counter.add_theme_constant_override("outline_size",5)
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_counter)
	add_to_group("DingSleep")
	_refresh_visual()

func has_collision_damage() -> bool: return false
func get_preview_texture() -> Texture2D: return CLOSED
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:int = State.Die if health<=0 else State.Stand if dizziness or not is_combat_runtime_active() or Speed<=0.0 else State.Move
	return -1 if next==state else next
func _can_act() -> bool:
	return is_multiplayer_authority() and not _dead and health>0 and is_combat_runtime_active() and not dizziness and Can_Attack and not is_damage_output_disabled()
func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta) # Ordinary movement/bounces; never steer body toward an enemy.
	step_sleep(delta)
func step_sleep(delta:float) -> void:
	if not is_multiplayer_authority() or _dead or health<=0 or not is_combat_runtime_active() or delta<=0.0: return
	_step_z_pose(delta)
	if wave_charging:
		if not _can_act() or not Can_Skill:
			wave_charging=false
			_finish_z_pose()
		elif z_pose_age+0.000001>=wave_windup_time+wave_shiver_time:
			_release_wave()
		_refresh_visual()
		return
	if awake:
		awake_left = maxf(awake_left-delta,0.0)
		wave_age += delta
		_sync_wave(true)
		if wave_age>=wave_duration and z_pose_phase==6: _finish_z_pose()
		if awake_left<=0.0:
			awake = false
			sleep_left = maxf(sleep_duration,0.1)
			_burst_wait = maxf(burst_interval,0.1)
			_ambient_wait = 1.0
	else:
		sleep_left = maxf(sleep_left-delta,0.0)
		if sleep_left<=0.0 and _can_act() and Can_Skill:
			_wake()
		else:
			_burst_wait = maxf(_burst_wait-delta,0.0)
			if not _can_act():
				_shots_left = 0
				_finish_z_pose()
			elif _shots_left>0:
				_shot_wait -= delta
				while _shots_left>0 and _shot_wait<=0.000001:
					_fire_z()
					_shot_wait += maxf(shot_interval,0.02)
			elif _burst_wait<=0.0 and not is_player_controlled():
				var target:ball = TOOLS.nearest_enemy(self)
				if is_instance_valid(target): begin_burst(global_position.direction_to(target.global_position))
		_ambient_wait -= delta
		if not awake and not wave_charging and _ambient_wait<=0.0 and not AUDIO.QUEUE.channel_busy(_ambient_ticket) and not AUDIO.QUEUE.channel_busy(_z_ticket):
			_emit_sound("sleep")
			_ambient_wait = 5.0
	_refresh_visual()
func begin_burst(heading:Vector2) -> bool:
	if not _can_act() or awake or wave_charging or sleep_left<=0.0 or _shots_left>0 or _burst_wait>0.0: return false
	_aim = heading.normalized() if not heading.is_zero_approx() else Vector2.RIGHT
	_burst_wait = maxf(burst_interval,0.1)
	_shots_left = 4
	_shot_wait = maxf(z_windup_time,0.01)
	z_recover_from = z_pose_scale()
	pose_is_wave = false
	z_pose_phase = 1
	z_pose_age = 0.0
	_apply_z_pose()
	return true
func _fire_z() -> void:
	if not _can_act() or awake:
		_shots_left=0
		_finish_z_pose()
		return
	if z_pose_phase==1:
		z_pose_phase=2
		z_pose_age=0.0
		_emit_sound("z") # First actual Z, once per whole burst (never during windup).
	var heading:Vector2 = _aim
	if is_player_controlled(): heading = player_control_aim_direction(_aim)
	else:
		var target:ball = TOOLS.nearest_enemy(self)
		if is_instance_valid(target): heading = global_position.direction_to(target.global_position)
	if heading.is_zero_approx(): heading=Vector2.RIGHT
	_shots_left -= 1
	shots_fired += 1
	var point:Vector2 = global_position+Vector2(0,-4)+heading*18.0
	var shot_name:String = "%s_Z_%d" % [name,shots_fired]
	_spawn_z(shot_name,point,heading,z_speed,z_turn_degrees)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _spawn_z.rpc(shot_name,point,heading,z_speed,z_turn_degrees)
	if _shots_left==0: _finish_z_pose()
@rpc("authority","call_remote","reliable")
func _spawn_z(shot_name:String,point:Vector2,heading:Vector2,speed:float,turn:float) -> void:
	var parent:Node = get_parent()
	if parent==null or parent.has_node(NodePath(shot_name)): return
	var shot:ball = (load(Z_SCENE) as PackedScene).instantiate()
	shot.name = shot_name
	shot.Master = self
	shot.Master_name = str(name)
	shot.Team = Team
	shot.Speed = speed
	shot.direction = heading
	shot.set("turn_degrees",turn)
	shot.position = (parent as Node2D).to_local(point) if parent is Node2D else point
	shot.set_multiplayer_authority(get_multiplayer_authority())
	parent.add_child(shot,true)
func _wake() -> void:
	if not _can_act() or not Can_Skill or awake or wave_charging: return
	z_recover_from=z_pose_scale() # A pending Z can flow into the stronger squash without snapping.
	pose_is_wave=true
	wave_charging=true
	z_pose_phase=4
	z_pose_age=0.0
	_shots_left=0
	_stop_ambient()
	_apply_z_pose()
	_refresh_visual()
func _release_wave() -> void:
	wave_charging=false
	z_pose_phase=6
	z_pose_age=0.0
	_apply_z_pose()
	awake = true
	awake_left = maxf(awake_duration,wave_duration)
	wave_age = 0.0
	wave_origin = global_position
	wake_serial += 1
	wakes_fired += 1
	_shots_left = 0
	_stop_ambient()
	_emit_sound("wake")
	_sync_wave(true)
func _sync_wave(deal_damage:bool) -> void:
	if _dead or not awake or wave_age>wave_duration:
		if is_instance_valid(_wave):
			if deal_damage and awake and wave_age>=wave_duration: _wave.set_age(wave_duration,is_multiplayer_authority())
			_wave.queue_free()
		_wave = null
		return
	if not is_instance_valid(_wave) or _wave_serial!=wake_serial:
		if is_instance_valid(_wave): _wave.queue_free()
		_wave = WAVE.new()
		_wave.name = "WakeWave"
		_wave.source = self
		_wave.max_radius = wave_max_radius
		_wave.duration = wave_duration
		add_child(_wave)
		_wave.global_position = wave_origin
		_wave_serial = wake_serial
	_wave.set_age(wave_age,deal_damage and is_multiplayer_authority())
func _pose_ease(age:float,duration:float) -> float:
	var t:float=clampf(age/maxf(duration,0.01),0.0,1.0)
	return t*t*t*(t*(t*6.0-15.0)+10.0) # C2: zero speed AND acceleration at both ends.
func z_pose_scale() -> Vector2:
	match z_pose_phase:
		1: return z_recover_from.lerp(Z_FLAT,_pose_ease(z_pose_age,z_windup_time))
		2: return Z_FLAT.lerp(Z_TALL,_pose_ease(z_pose_age,z_stretch_time))
		3: return z_recover_from.lerp(Vector2.ONE,_pose_ease(z_pose_age,wave_recover_time if pose_is_wave else z_recover_time))
		4:
			if z_pose_age<wave_windup_time: return z_recover_from.lerp(WAVE_FLAT,_pose_ease(z_pose_age,wave_windup_time))
			var t:float=clampf((z_pose_age-wave_windup_time)/maxf(wave_shiver_time,0.01),0.0,1.0)
			var envelope:float=pow(sin(PI*t),2.0)
			var tremble:float=sin(TAU*12.0*(z_pose_age-wave_windup_time))*envelope
			return WAVE_FLAT+Vector2(0.035,-0.012)*tremble
		6: return WAVE_FLAT.lerp(WAVE_TALL,_pose_ease(z_pose_age,wave_stretch_time))
	return Vector2.ONE
func _set_pose_transform(ratio:Vector2) -> void:
	# Local bottom-center stays exactly fixed, including during shiver and interpolation.
	var visual:Node2D=get_node_or_null("Graphics")
	if visual!=null: visual.transform=_pose_base*Transform2D(0.0,ratio,0.0,_pose_pivot-_pose_pivot*ratio)
func _apply_z_pose() -> void:
	var ratio:Vector2=z_pose_scale()
	if Engine.is_in_physics_frame():
		var tick:int=Engine.get_physics_frames()
		if tick!=_pose_tick:
			_pose_previous=_pose_current
			_pose_tick=tick
		_pose_current=ratio
	else:
		_pose_previous=ratio
		_pose_current=ratio
		_pose_tick=-1
	_set_pose_transform(ratio)
func _render_z_pose(delta:float) -> void:
	if _dead or health<=0 or not is_combat_runtime_active() or get_tree().paused: return
	if is_multiplayer_authority():
		var fraction:float=Engine.get_physics_interpolation_fraction() if _pose_tick>=0 and Engine.get_physics_frames()-_pose_tick<=1 else 1.0
		_set_pose_transform(_pose_previous.lerp(_pose_current,fraction))
	else:
		# Visual-only packet smoothing. Never advances attacks, clocks, damage or sound.
		var goal:Vector2=z_pose_scale()
		_pose_current=_pose_current.lerp(goal,1.0-exp(-45.0*maxf(delta,0.0)))
		if _pose_current.distance_to(goal)<0.00001: _pose_current=goal
		_set_pose_transform(_pose_current)
func _step_z_pose(delta:float) -> void:
	if z_pose_phase!=0: z_pose_age+=delta
	if z_pose_phase==3 and z_pose_age>=(wave_recover_time if pose_is_wave else z_recover_time): _reset_z_pose()
	else: _apply_z_pose()
func _finish_z_pose() -> void:
	if z_pose_phase not in [1,2,4,6]: return
	z_recover_from=z_pose_scale()
	z_pose_phase=3
	z_pose_age=0.0
	_apply_z_pose()
func _reset_z_pose() -> void:
	z_pose_phase=0
	z_pose_age=0.0
	pose_is_wave=false
	wave_charging=false
	z_recover_from=Vector2.ONE
	_apply_z_pose()
func _refresh_visual() -> void:
	if not is_instance_valid(image) or not is_instance_valid(_counter): return
	image.texture = OPEN if awake else CLOSED
	_counter.text = str(ceili(maxf(sleep_left,0.0)))
	_counter.visible = not awake and not wave_charging and not _dead and health>0
func _process(_delta:float) -> void:
	_render_z_pose(_delta)
	_refresh_visual()
	if not is_multiplayer_authority(): _sync_wave(false)
	var paused:bool = Game.now_stop_state or get_tree().paused or not is_combat_runtime_active()
	for ticket:Dictionary in _tickets.duplicate():
		var ref:WeakRef = ticket.get("player") as WeakRef
		var player:AudioStreamPlayer2D = ref.get_ref() as AudioStreamPlayer2D if ref!=null else null
		if is_instance_valid(player): player.stream_paused=paused
		elif ticket.get("state","")!="queued": _tickets.erase(ticket)
	if awake or wave_charging: _stop_ambient()
func _emit_sound(role:String) -> void:
	_sound_serial += 1
	var index:int = _voice_rng.randi_range(0,AUDIO.EVENTS[role].size()-1)
	if multiplayer.has_multiplayer_peer(): _sound.rpc(_sound_serial,role,index,global_position)
	else: _sound(_sound_serial,role,index,global_position)
@rpc("authority","call_local","reliable")
func _sound(serial:int,role:String,index:int,point:Vector2) -> void:
	if serial<=_last_sound_serial: return
	_last_sound_serial=serial
	last_sound_role=role
	if role=="z": _stop_ambient()
	var ticket:Dictionary=AUDIO.play(self,role,index,point)
	if not ticket.is_empty(): _tickets.append(ticket)
	if role=="sleep": _ambient_ticket=ticket
	if role=="z": _z_ticket=ticket
func _stop_ambient() -> void:
	if _ambient_ticket.is_empty(): return
	_ambient_ticket["cancel_requested"]=true
	var ref:WeakRef=_ambient_ticket.get("player") as WeakRef
	var player:Node=ref.get_ref() if ref!=null else null
	if is_instance_valid(player): player.stop(); player.queue_free()
	_ambient_ticket={}
func on_actual_health_damage_received(actual:float,before:float) -> void:
	super.on_actual_health_damage_received(actual,before)
	if is_multiplayer_authority() and actual>0 and health>0 and _voice_rng.randf()<0.45: _emit_sound("hurt")
func player_control_action_ids() -> Array[StringName]: return [&"controlled_burst"]
func player_control_action_hold_repeat_allowed(_index:int) -> bool: return false
func controlled_burst() -> void:
	if is_player_controlled(): begin_burst(player_control_aim_direction(direction))
func get_ai_attack_threats(receiver:ball) -> Array[Dictionary]:
	return _wave.threats(receiver) if is_instance_valid(_wave) else []
func get_debug_attack_regions() -> Array: return get_ai_attack_threats(null)
func get_debug_detection_regions() -> Array[Dictionary]: return []
func get_armor_test_effect_summary() -> String:
	if TranslationServer.get_locale().begins_with("en"):
		return "Normally sleeps while moving. Every 4 seconds begins a short windup, then fires four gently homing Z shots, 0.2 seconds apart: 1 base damage and 0.1 seconds stun each.\nThe small top-right counter counts down 60 seconds. At zero, charges briefly before waking for 2 seconds and releasing one expanding shockwave: raw-health damage equal to each enemy's current HP on contact. Then sleeps and resets to 60.\nC control: left click fires a ready Z burst; waking remains passive. Ordinary defense/absorption and special death rules use the shared damage system."
	return "正常移动时闭眼睡觉；每4秒短暂蓄力后连续射出4个轻微追踪Z，间隔0.2秒，每发基础1伤害、0.1秒眩晕。\n右上小数字60秒倒数，到0先蓄力，随后睁眼2秒并释放一次冲击波；波碰到敌人时造成其当前生命值的真伤，随后恢复闭眼与60秒数字。\nC手控：左键在冷却结束时发射Z连发，苏醒为被动。真伤沿用公共直接生命入口，特殊吸收、复活与免疫规则保留。"
func Die() -> void:
	if _dead: return
	_dead=true
	_reset_z_pose()
	_shots_left=0
	_stop_ambient()
	if is_instance_valid(_wave): _wave.queue_free()
	if is_multiplayer_authority():
		_emit_sound("death")
		if multiplayer.has_multiplayer_peer(): _death_visual.rpc()
		else: _death_visual()
	super.Die() # Keep the project's default death sound and lifecycle.
@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _last_death_feedback: return
	_last_death_feedback=true
	_reset_z_pose()
	FX.death_pose(self,image,direction.x>=0.0)
	image.hide()
	_counter.hide()
func _exit_tree() -> void: _stop_ambient()
