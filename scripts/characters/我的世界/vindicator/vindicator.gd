extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/vindicator/frames.tres")
const ARM:Texture2D = preload("res://Images/characters/我的世界/vindicator/arm.png")
const AXE:Texture2D = preload("res://Images/characters/我的世界/vindicator/iron_axe.png")
const PREVIEW:Texture2D = preload("res://Images/characters/我的世界/vindicator/preview.png")
const SOUNDS = preload("res://scripts/characters/我的世界/vindicator/sounds.gd")
const VOICE = preload("res://scripts/effects/我的世界/mc_creature_voice.gd")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const SHOULDER:Vector2 = Vector2(60.297922,98.722430)
const HAND:Vector2 = Vector2(56.357506,58.194286)
const AXE_GRIP:Vector2 = Vector2(5.5,11.5)
const AXE_BLADE:Vector2 = Vector2(9.0,4.0)
enum Phase { IDLE, CHARGE, DASH, SWING, RECOVER }
@export var full_charge_seconds:float = 1.6
@export var maximum_damage_multiplier:float = 4.0
@export var swing_seconds:float = 0.24
@export var recovery_seconds:float = 0.32
@export var rush_speed_multiplier:float = 3.6
var phase:int = Phase.IDLE
var charge_elapsed:float = 0.0
var phase_elapsed:float = 0.0
var released_charge:float = 0.0
var facing:Vector2 = Vector2.RIGHT
var attack_wait:float = 0.0
var rush_wait:float = 2.0
var _manual_held:bool = false
var _hits:Dictionary = {}
var _regions:Array[Dictionary] = []
var _arm:Node2D
var _arm_sprite:Sprite2D
var _axe:Sprite2D
var _charge_bar:Line2D
var _charge_fill:Line2D
var voice:Node
var _walk_clock:float = 0.0
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
	_arm_sprite.texture = ARM
	_arm_sprite.centered = false
	_arm_sprite.offset = -SHOULDER
	_arm.add_child(_arm_sprite)
	_axe = Sprite2D.new()
	_axe.texture = AXE
	_axe.centered = false
	_axe.offset = -AXE_GRIP
	_axe.scale = Vector2(3,3)
	_axe.position = HAND-SHOULDER
	_axe.rotation = -PI/4.0
	_arm.add_child(_axe)
	_arm.move_child(_axe,0)
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
	if not is_combat_runtime_active() or delta<=0.0: return
	if health<=0: return
	var moved:float = global_position.distance_to(_last_position)
	_last_position = global_position
	if moved<maxf(48.0,Speed*delta*5.0): _walk_clock += moved/maxf(Speed,1.0)
	if not is_multiplayer_authority():
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
			charge_elapsed = minf(charge_elapsed+delta,maxf(full_charge_seconds,0.05))
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
	charge_elapsed = minf(charge_elapsed+delta,maxf(full_charge_seconds,0.05))
	phase_elapsed += delta
	_aim_at_target()
	var speed:float = maxf(Speed,0.0)*lerpf(1.4,maxf(rush_speed_multiplier,1.4),charge_ratio())
	var step:Vector2 = facing*speed*motion_scaled_delta(delta)
	velocity = step/maxf(delta,0.00001)
	var collision:KinematicCollision2D = move_and_collide(step)
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
	var steps:int = maxi(1,int(ceil((finish-phase_elapsed)/0.008)))
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
	_manual_held = false
	_hits.clear()
	_regions.clear()
	velocity = Vector2.ZERO
	attack_wait = maxf(attack_wait,0.2)
	if is_instance_valid(_arm): _update_pose()
	_sync_visual(true)

func _update_pose() -> void:
	if not is_instance_valid(_arm) or health<=0: return
	var walking:bool = velocity.length_squared()>1.0
	image.texture = FRAMES.get_frame_texture(&"walk",int(_walk_clock*12.0)%12) if walking else FRAMES.get_frame_texture(&"idle",0)
	set_character_visual_flip_h(facing.x>=0.0)
	var shoulder:Vector2 = SHOULDER-Vector2(80,112)
	if is_character_visual_flipped_h(): shoulder.x = -shoulder.x
	var side:float = 1.0 if facing.x>=0.0 else -1.0
	var rest:float = (PI-0.15)*side
	var raised:float = 0.38*side
	var aimed:float = facing.angle()+PI/2.0
	if side<0.0 and aimed>0.0: aimed-=TAU
	var finish:float = aimed+0.65*side
	var angle:float = rest
	var axe_tilt:float = 0.0
	var start:float = lerpf(rest,raised,clampf(released_charge,0.0,1.0))
	if phase in [Phase.CHARGE,Phase.DASH]:
		angle = lerpf(rest,raised,charge_ratio())
	elif phase == Phase.SWING:
		angle = lerpf(start,finish,clampf(phase_elapsed/maxf(swing_seconds,0.01),0.0,1.0))
		axe_tilt = angle-start
	elif phase == Phase.RECOVER:
		var recovery:float = clampf(phase_elapsed/maxf(recovery_seconds,0.01),0.0,1.0)
		angle = lerpf(finish,rest,recovery)
		axe_tilt = (finish-start)*(1.0-recovery)
	_axe.rotation = -PI/4.0+(angle-axe_tilt)*side
	angle -= image.global_rotation
	var mirror:Vector2 = Vector2(-1,1) if is_character_visual_flipped_h() else Vector2.ONE
	_arm.transform = Transform2D(angle,mirror,0.0,shoulder+image.offset)
	_charge_bar.position = Vector2(0,-90)+image.offset
	_charge_bar.visible = phase in [Phase.CHARGE,Phase.DASH]
	_charge_fill.points = PackedVector2Array([Vector2(-22,0),Vector2(-22+44*charge_ratio(),0)])
	_charge_fill.default_color = Color(1,0.25,0.08) if charge_ratio()>=0.75 else Color(1,0.8,0.1) if charge_ratio()>=0.5 else Color(0.45,0.8,1)

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
	_receive_visual.rpc(_visual_serial,phase,charge_elapsed,phase_elapsed,released_charge,facing,_walk_clock)
@rpc("authority","call_remote","reliable")
func _receive_visual(serial:int,next_phase:int,charge:float,elapsed:float,released:float,aim:Vector2,walk:float) -> void:
	if serial<=_received_serial: return
	_received_serial = serial
	phase = next_phase
	charge_elapsed = charge
	phase_elapsed = elapsed
	released_charge = released
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
