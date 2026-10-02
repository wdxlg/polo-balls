extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/vindicator/frames.tres")
## Independent legs: phase follows real displacement against the OWN base speed (buffs / slows
## change the tempo), keeps stepping through charge / swing, and settles on walk 3 / 9 (= idle).
const MC_LEGS = preload("res://scripts/effects/我的世界/mc_legs.gd")
const ARM:Texture2D = preload("res://Images/characters/我的世界/vindicator/arm.png")
const FOREARM:Texture2D = preload("res://Images/characters/我的世界/vindicator/forearm.png")
const HAND_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/vindicator/hand.png")
const AXE:Texture2D = preload("res://Images/characters/我的世界/vindicator/iron_axe.png")
const PREVIEW:Texture2D = preload("res://Images/characters/我的世界/vindicator/preview.png")
const SOUNDS = preload("res://scripts/characters/我的世界/vindicator/sounds.gd")
const VOICE = preload("res://scripts/effects/我的世界/mc_creature_voice.gd")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const SHOULDER:Vector2 = Vector2(60.297922,98.722430)
const HAND:Vector2 = Vector2(56.357506,58.194286)
const WRIST:Vector2 = Vector2(56.357506,64.870144)
const AXE_GRIP:Vector2 = Vector2(5.5,11.5)
const AXE_BLADE:Vector2 = Vector2(9.0,4.0)
const AXE_SCALE:float = 5.0
const REST_ARM_ANGLE:float = -2.75
const READY_ARM_ANGLE:float = -1.65
const RUSH_READY_ARM_ANGLE:float = -1.00
const DRAW_CHARGE_RATIO:float = 0.065
const RAISED_ARM_ANGLE:float = -0.70
const AXE_HOLD_ANGLE:float = -READY_ARM_ANGLE-PI/4.0
enum Phase { IDLE, CHARGE, DASH, SWING, RECOVER }
@export var full_charge_seconds:float = 1.6
@export var maximum_damage_multiplier:float = 4.0
@export var swing_seconds:float = 0.14
@export var recovery_seconds:float = 0.32
@export var rush_speed_multiplier:float = 3.6
var phase:int = Phase.IDLE
var charge_elapsed:float = 0.0
var phase_elapsed:float = 0.0
var released_charge:float = 0.0
var released_rush:bool = false
var facing:Vector2 = Vector2.RIGHT
var attack_wait:float = 0.0
var rush_wait:float = 2.0
var _manual_held:bool = false
var _hits:Dictionary = {}
var _regions:Array[Dictionary] = []
var _arm:Node2D
var _arm_sprite:Sprite2D
var _wrist:Node2D
var _hand_sprite:Sprite2D
var _axe:Sprite2D
var _charge_bar:Line2D
var _charge_fill:Line2D
var voice:Node
var _walk_clock:float = 0.0
var gait:RefCounted
var _last_position:Vector2
var _previous_distance:float = INF
var _visual_serial:int = 0
var _received_serial:int = 0
var _sync_wait:float = 0.0

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = true
	super._ready()
	_last_position = global_position
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_arm = Node2D.new()
	_arm.name = "AxeArm"
	_arm.show_behind_parent = true
	image.add_child(_arm)
	_arm_sprite = Sprite2D.new()
	_arm_sprite.texture = FOREARM
	_arm_sprite.centered = false
	_arm_sprite.offset = -SHOULDER
	_arm.add_child(_arm_sprite)
	_wrist = Node2D.new()
	_wrist.name = "AxeWrist"
	_wrist.position = WRIST-SHOULDER
	_arm.add_child(_wrist)
	_hand_sprite = Sprite2D.new()
	_hand_sprite.texture = HAND_TEXTURE
	_hand_sprite.centered = false
	_hand_sprite.offset = -WRIST
	_wrist.add_child(_hand_sprite)
	_axe = Sprite2D.new()
	_axe.texture = AXE
	_axe.centered = false
	_axe.offset = -AXE_GRIP
	_axe.scale = Vector2.ONE*AXE_SCALE
	_axe.position = HAND-WRIST
	_axe.rotation = AXE_HOLD_ANGLE
	_wrist.add_child(_axe)
	_wrist.move_child(_axe,0)
	_charge_bar = Line2D.new()
	_charge_bar.width = 3.0
	_charge_bar.default_color = Color(0.1,0.1,0.1,0.85)
	_charge_bar.points = PackedVector2Array([Vector2(-22,0),Vector2(22,0)])
	image.add_child(_charge_bar)
	_charge_fill = Line2D.new()
	_charge_fill.width = 2.0
	_charge_bar.add_child(_charge_fill)
	voice = VOICE.new()
	voice.name = "NativeVoice"
	voice.unit = self
	voice.events = SOUNDS.EVENTS.duplicate()
	voice.events["swing"] = AUDIO.EVENTS["entity.player.attack.sweep"]
	add_child(voice)
	_update_pose()

func mc_enemy(target:Variant) -> bool:
	return super.mc_enemy(target) and target.get_world_2d()==get_world_2d()

func charge_ratio() -> float:
	return clampf(charge_elapsed/maxf(full_charge_seconds,0.05),0.0,1.0)
func damage_multiplier(ratio:float) -> float:
	return lerpf(1.0,maxf(maximum_damage_multiplier,1.0),clampf(ratio,0.0,1.0))
func can_act() -> bool:
	return mc_live() and not dizziness
func controlled_attack_action() -> void:
	if not is_player_controlled() or not can_act() or phase != Phase.IDLE or attack_wait>0.0: return
	_manual_held = true
	_begin_charge(false)
func controlled_skill_action() -> void:
	if not is_player_controlled() or not has_player_control_aim(): return
	_begin_charge(true)
func player_control_action_hold_repeat_allowed(index:int) -> bool: return index == 1
func player_control_action_released(index:int) -> void:
	if index != 0 or not is_multiplayer_authority() or not _manual_held: return
	_manual_held = false
	if phase == Phase.CHARGE and can_act(): _release_swing()
	elif phase == Phase.CHARGE: cancel_attack()
func player_control_action_cancelled(index:int) -> void:
	if index == 0 and _manual_held: cancel_attack()
func set_player_control_peer(peer_id:int) -> void:
	if peer_id != player_control_peer_id and is_multiplayer_authority(): cancel_attack()
	super.set_player_control_peer(peer_id)
func get_next_state(state:State) -> int:
	var attack_enabled:bool = Can_Attack
	var skill_enabled:bool = Can_Skill
	Can_Attack = false
	Can_Skill = false
	var next:int = super.get_next_state(state)
	Can_Attack = attack_enabled
	Can_Skill = skill_enabled
	return next

func _begin_charge(rush:bool) -> bool:
	if not can_act() or phase != Phase.IDLE or attack_wait>0.0 or (rush and rush_wait>0.0): return false
	if rush and not Can_Skill: return false
	if not rush and not Can_Attack: return false
	phase = Phase.DASH if rush else Phase.CHARGE
	charge_elapsed = 0.0
	phase_elapsed = 0.0
	released_charge = 0.0
	released_rush = false
	_previous_distance = INF
	_regions.clear()
	_aim_at_target()
	if rush: rush_wait = maxf(Skill_Cooling,0.1)
	_sync_visual(true)
	_update_pose()
	return true

func _aim_at_target() -> void:
	if has_player_control_aim(): facing = player_control_aim_direction(facing)
	elif not is_player_controlled():
		var enemy:ball = mc_nearest()
		if enemy != null: facing = global_position.direction_to(ball.body_point(enemy,global_position))
	if facing.length_squared()<0.001: facing = Vector2.RIGHT

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not is_combat_runtime_active() or delta<=0.0 or health<=0:
		_vindicator_gait().observe(self)
		return
	_vindicator_gait().tick(self,delta,dizziness != true)
	var moved:float = global_position.distance_to(_last_position)
	_last_position = global_position
	if moved<maxf(48.0,Speed*delta*5.0): _walk_clock += moved/maxf(Speed,1.0)
	if not is_multiplayer_authority():
		if phase in [Phase.CHARGE,Phase.DASH]:
			charge_elapsed = minf(charge_elapsed+delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self),maxf(full_charge_seconds,0.05))
		elif phase==Phase.SWING:
			phase_elapsed = minf(phase_elapsed+delta,maxf(swing_seconds,0.01))
		elif phase==Phase.RECOVER:
			phase_elapsed = minf(phase_elapsed+delta,maxf(recovery_seconds,0.01))
		_update_pose()
		return
	_regions.clear()
	attack_wait = maxf(attack_wait-delta,0.0)
	rush_wait = maxf(rush_wait-delta,0.0)
	if not can_act():
		if phase != Phase.IDLE: cancel_attack()
		return
	match phase:
		Phase.IDLE:
			var travel:Vector2 = player_control_direction if is_player_controlled() else direction
			if not travel.is_zero_approx(): facing = travel.normalized()
			if not is_player_controlled():
				var enemy:ball = mc_nearest(delta)
				if enemy != null:
					var distance:float = global_position.distance_to(ball.body_point(enemy,global_position))
					if distance<melee_reach()+24.0: _begin_charge(false)
					elif distance<420.0 and rush_wait<=0.0: _begin_charge(true)
		Phase.CHARGE:
			charge_elapsed = minf(charge_elapsed+delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self),maxf(full_charge_seconds,0.05))
			_aim_at_target()
			if charge_ratio()>=1.0: _release_swing()
			elif not is_player_controlled():
				var enemy:ball = mc_nearest(delta)
				if enemy != null:
					var distance:float = global_position.distance_to(ball.body_point(enemy,global_position))
					if distance<melee_reach()+10.0 and (charge_ratio()>=0.85 or (charge_ratio()>=0.5 and distance>_previous_distance+0.5)): _release_swing()
					_previous_distance = distance
		Phase.DASH:
			_advance_dash(delta)
		Phase.SWING:
			_advance_swing(delta)
		Phase.RECOVER:
			phase_elapsed += delta
			if phase_elapsed>=maxf(recovery_seconds,0.01):
				phase = Phase.IDLE
				phase_elapsed = 0.0
	_update_pose()
	_sync_wait -= delta
	_sync_visual(false)

func move(speed:float,delta:float) -> void:
	if phase == Phase.DASH: return
	super.move(speed,delta)
func stand(delta:float) -> void:
	if phase == Phase.DASH: return
	super.stand(delta)

func _advance_dash(delta:float) -> void:
	if not can_act() or phase != Phase.DASH: return
	charge_elapsed = minf(charge_elapsed+delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self),maxf(full_charge_seconds,0.05))
	phase_elapsed += delta
	_aim_at_target()
	_update_pose()
	var speed:float = maxf(Speed,0.0)*lerpf(1.4,maxf(rush_speed_multiplier,1.4),charge_ratio())
	var step:Vector2 = facing*speed*motion_scaled_delta(delta)
	velocity = step/maxf(delta,0.00001)
	var collision:KinematicCollision2D = move_with_body_collision(step,delta)
	var close:bool = false
	if has_player_control_aim(): close = global_position.distance_to(player_control_aim_world_position())<melee_reach()
	elif not is_player_controlled():
		var enemy:ball = mc_nearest()
		close = enemy != null and global_position.distance_to(ball.body_point(enemy,global_position))<melee_reach()+8.0
	if collision != null or close or charge_ratio()>=1.0:
		velocity = Vector2.ZERO
		_release_swing()

func _release_swing() -> void:
	if not can_act() or phase not in [Phase.CHARGE,Phase.DASH]: return
	released_charge = charge_ratio()
	released_rush = phase==Phase.DASH
	phase = Phase.SWING
	phase_elapsed = 0.0
	_manual_held = false
	_hits.clear()
	_regions.clear()
	attack_wait = maxf(Attack_Cooling,0.1)
	_update_pose()
	voice.request("swing",global_position,0.0)
	_sync_visual(true)

func _advance_swing(delta:float) -> void:
	if not can_act() or phase != Phase.SWING: return
	var finish:float = minf(phase_elapsed+delta,maxf(swing_seconds,0.01))
	var sweep_step:float = minf(0.004,maxf(swing_seconds,0.01)/96.0)
	var steps:int = maxi(1,int(ceil((finish-phase_elapsed)/sweep_step)))
	var begin:float = phase_elapsed
	_update_pose()
	var previous:Vector2 = blade_center()
	for i:int in range(steps):
		phase_elapsed = lerpf(begin,finish,float(i+1)/float(steps))
		_update_pose()
		var next:Vector2 = blade_center()
		var radius:float = blade_radius()
		_regions.append({"shape":"segment","start":previous,"end":next,"radius":radius,"damage":attack_damage(damage_multiplier(released_charge)),"source":self,"kind":"vindicator_axe"})
		for contact:Dictionary in SWEEP.contacts(self,previous,next,radius,_hits,global_position):
			var target:ball = contact.target
			_hits[target.get_instance_id()] = true
			deal_axe_hit(target,contact.point)
			if not can_act():
				cancel_attack()
				return
		previous = next
	if finish>=maxf(swing_seconds,0.01):
		phase = Phase.RECOVER
		phase_elapsed = 0.0

func deal_axe_hit(target:ball,point:Vector2) -> bool:
	if not can_act() or phase != Phase.SWING or not mc_enemy(target): return false
	var space:Dictionary = {"shape":"point","point":point,"source":self,"carrier":"weapon_sweep","bypass_guard":released_charge>=0.5,"bypass_damage_reduction":released_charge>=0.75}
	return target.receive_classified_positional_damage(attack_damage(damage_multiplier(released_charge)),point,&"ordinary",released_charge>=0.5,self,space)

func cancel_attack() -> void:
	phase = Phase.IDLE
	phase_elapsed = 0.0
	charge_elapsed = 0.0
	released_charge = 0.0
	released_rush = false
	_manual_held = false
	_hits.clear()
	_regions.clear()
	velocity = Vector2.ZERO
	attack_wait = maxf(attack_wait,0.2)
	if is_instance_valid(_arm): _update_pose()
	_sync_visual(true)

func _charge_pose(ratio:float,rush:bool) -> Vector2:
	var draw:float = smoothstep(0.0,DRAW_CHARGE_RATIO,ratio)
	var ready:float = RUSH_READY_ARM_ANGLE if rush else READY_ARM_ANGLE
	return Vector2(lerpf(REST_ARM_ANGLE,lerpf(ready,RAISED_ARM_ANGLE,ratio),draw),AXE_HOLD_ANGLE)

func _swing_pose(aim:Vector2,progress:float) -> Vector2:
	var start:Vector2 = _charge_pose(clampf(released_charge,0.0,1.0),released_rush)
	var ready:Vector2 = Vector2(maxf(start.x,-1.05),AXE_HOLD_ANGLE)
	var draw_end:float = 0.18 if not start.is_equal_approx(ready) else 0.0
	if progress<draw_end:
		return start.lerp(ready,smoothstep(0.0,draw_end,progress))
	var blade:Vector2 = HAND-SHOULDER+(AXE_BLADE-AXE_GRIP).rotated(AXE_HOLD_ANGLE)*AXE_SCALE
	var turn:float = wrapf(aim.angle()-blade.angle()-ready.x,-PI,PI)
	var side:float = -1.0 if turn<0.0 else 1.0
	var finish:float = ready.x+side*maxf(absf(turn)+0.95,2.1)
	var cut:float = pow(clampf((progress-draw_end)/(0.82-draw_end),0.0,1.0),1.6)
	return Vector2(lerpf(ready.x,finish,cut),AXE_HOLD_ANGLE)

func _vindicator_gait() -> RefCounted:
	if gait == null:
		gait = MC_LEGS.create(float(FRAMES.get_frame_count(&"walk"))/maxf(FRAMES.get_animation_speed(&"walk"),0.001),[0.25,0.75])
		gait.observe(self)
	return gait

func _update_pose() -> void:
	if not is_instance_valid(_arm) or health<=0: return
	var legs:RefCounted = _vindicator_gait()
	image.texture = FRAMES.get_frame_texture(&"idle",0) if legs.at_rest else FRAMES.get_frame_texture(&"walk",legs.walk_index(FRAMES.get_frame_count(&"walk")))
	var local_aim:Vector2 = image.to_local(image.global_position+facing).normalized()
	var mirrored:bool = local_aim.x>=0.0
	set_character_visual_flip_h(mirrored)
	var canonical_aim:Vector2 = Vector2(-absf(local_aim.x),local_aim.y)
	var held:Vector2 = Vector2(REST_ARM_ANGLE,AXE_HOLD_ANGLE)
	if phase in [Phase.CHARGE,Phase.DASH]:
		held = _charge_pose(charge_ratio(),phase==Phase.DASH)
	elif phase == Phase.SWING:
		held = _swing_pose(canonical_aim,phase_elapsed/maxf(swing_seconds,0.01))
	elif phase == Phase.RECOVER:
		var end:Vector2 = _swing_pose(canonical_aim,1.0)
		var settle:float = smoothstep(0.2,1.0,phase_elapsed/maxf(recovery_seconds,0.01))
		held = Vector2(lerp_angle(end.x,REST_ARM_ANGLE,settle),AXE_HOLD_ANGLE)
	var angle:float = held.x
	_wrist.rotation = 0.0
	var pose:Transform2D = Transform2D(angle,SHOULDER-Vector2(80,112))
	if mirrored:
		pose = Transform2D(Vector2(-1,0),Vector2(0,1),Vector2.ZERO)*pose
	pose.origin += image.offset
	_arm.transform = pose
	var reaching_front:bool = local_aim.y>=-0.15 and (phase==Phase.RECOVER or (phase==Phase.SWING and phase_elapsed>=maxf(swing_seconds,0.01)*0.12))
	_arm.show_behind_parent = not reaching_front
	_charge_bar.position = Vector2(0,-90)+image.offset
	_charge_bar.visible = phase in [Phase.CHARGE,Phase.DASH]
	_charge_fill.points = PackedVector2Array([Vector2(-22,0),Vector2(-22+44*charge_ratio(),0)])
	_charge_fill.default_color = Color(1,0.25,0.08) if charge_ratio()>=0.75 else Color(1,0.8,0.1) if charge_ratio()>=0.5 else Color(0.45,0.8,1)

func hand_center() -> Vector2:
	return _wrist.to_global(HAND-WRIST)
func blade_center() -> Vector2:
	return _axe.to_global(AXE_BLADE+_axe.offset)
func blade_radius() -> float:
	return maxf(_axe.global_scale.abs().x*4.5,0.3)
func melee_reach() -> float:
	return maxf(blade_center().distance_to(global_position),24.0)
func get_preview_texture() -> Texture2D: return PREVIEW
func get_armor_test_effect_summary() -> String: return Game.t("MC_ARMOR_INTRO_VINDICATOR")
func get_debug_attack_regions() -> Array[Dictionary]:
	return _regions if can_act() else []
func get_ai_attack_threats(_receiver:ball) -> Array: return get_debug_attack_regions()
func get_debug_detection_regions() -> Array[Dictionary]:
	if not can_act() or phase not in [Phase.CHARGE,Phase.DASH]: return []
	return [{"shape":"circle","center":blade_center(),"radius":blade_radius(),"damage":0.0,"source":self}]

func _sync_visual(force:bool) -> void:
	if not is_inside_tree() or not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer(): return
	if not force and _sync_wait>0.0: return
	_sync_wait = 0.05
	_visual_serial += 1
	_receive_visual.rpc(_visual_serial,phase,charge_elapsed,phase_elapsed,released_charge,facing,_walk_clock,released_rush)
@rpc("authority","call_remote","reliable")
func _receive_visual(serial:int,next_phase:int,charge:float,elapsed:float,released:float,aim:Vector2,walk:float,rush_release:bool=false) -> void:
	if serial<=_received_serial: return
	_received_serial = serial
	phase = next_phase
	charge_elapsed = charge
	phase_elapsed = elapsed
	released_charge = released
	released_rush = rush_release
	facing = aim
	_walk_clock = walk
	_update_pose()
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if amount>0 and health>0 and is_instance_valid(voice) and _mc_voice_rng.randf()<hurt_voice_chance: voice.request("hurt",global_position,-3.0)
func Die() -> void:
	cancel_attack()
	if is_instance_valid(voice): voice.request("death",global_position,0.0)
	if is_instance_valid(_arm): _arm.hide()
	if is_instance_valid(_charge_bar): _charge_bar.hide()
	super.Die()
