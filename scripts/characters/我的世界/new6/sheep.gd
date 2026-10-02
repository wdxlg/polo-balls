extends "res://scripts/characters/我的世界/new5/base.gd"
# 后撤逐渐刹停 → 起冲瞬间瞄准 → 默认速度起步并加速冲撞。
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/new6/sheep_frames.tres")
const WOOL_BODY_ATLAS:Texture2D = preload("res://Images/characters/我的世界/new6/sheep_wool_body.png")
const WOOL_FIXED_ATLAS:Texture2D = preload("res://Images/characters/我的世界/new6/sheep_wool_fixed.png")
const FX = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")
const WOOL_PROJECTILE = preload("res://scripts/characters/我的世界/new6/wool_projectile.gd")
## Independent legs: body + both wool layers step on one gait phase driven by real displacement
## against the OWN base speed (a 520 px/s charge strides fast, a slow brake slowly) and settle on
## walk 2 / 6 (closest to idle) before the idle clip resumes. Standing states (graze / recover) never step.
const MC_LEGS = preload("res://scripts/effects/我的世界/mc_legs.gd")
enum RamState { ROAM, WINDUP, CHARGE, RECOVER, GRAZE, BRAKE_GRAZE }
@export var wool_max:int = 3
@export var wool_trigger_radius:float = 32.0
@export var wool_projectile_radius:float = 22.0
@export var wool_burst_radius:float = 58.0
@export var wool_heal_ratio:float = 0.08
@export var ram_trigger_range:float = 105.0
@export var ram_windup:float = 0.55
@export var ram_cooldown:float = 5.0
@export var charge_speed:float = 520.0
@export var charge_acceleration:float = 650.0
@export var wall_squash_duration:float = 0.5
@export var wall_stun_speed:float = 240.0
@export var wall_stun_duration:float = 1.0
@export var retreat_speed:float = 80.0
@export var charge_contact_speed_ratio:float = 0.65
@export var graze_delay:float = 3.0
@export var graze_cooldown:float = 8.0
@export var graze_heal_ratio:float = 0.025
@export var graze_bite_interval:float = 0.8
@export var graze_braking:float = 120.0
@export var sheared_speed_mult:float = 1.15
var facing:Vector2 = Vector2.RIGHT
var wool:int = 3
var ram_state:RamState = RamState.ROAM
var _phase_left:float = 0.0
var _ram_left:float = 0.0
var _charge_dir:Vector2 = Vector2.RIGHT
var _retreat_dir:Vector2 = Vector2.LEFT
var _aim_point:Vector2 = Vector2.ZERO
var _charge_target:WeakRef
var _charge_speed:float = 0.0
var _charge_distance:float = 0.0
var _charge_contacts:Dictionary = {}
var _charge_exceptions:Array[WeakRef] = []
var _retreat_current_speed:float = 0.0
var _visual_base_scale:Vector2 = Vector2.ONE
var _wall_squash_age:float = 999.0
var _wall_squash_axis:Vector2 = Vector2.RIGHT
var _wall_squash_strength:float = 0.0
var _since_hurt:float = 99.0
var _regrow:float = 0.0
var _heal_pool:float = 0.0
var _graze_elapsed:float = 0.0
var _graze_cooldown_left:float = 0.0
var _bite_flash_left:float = 0.0
var _bite_serial:int = 0
var _seen_bite_serial:int = 0
var _ambient_cd:float = 3.0
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
@export var footstep_base_interval:float = 0.55
var _footstep_cadence = FOOTSTEP.new()
var _breath_player:AudioStreamPlayer2D
var _footstep_player:AudioStreamPlayer2D
var _sound_position:Vector2
var _moving:bool = false
var gait:RefCounted
var _legs_delta:float = 0.0
var _visual_rest:Vector2
var _graze_velocity:Vector2 = Vector2.ZERO
var _observed_health:int = 0
const WOOL_PEAK:float = 1.35
var _wool_break_serial:int = 0
var _seen_wool_break_serial:int = 0
var _wool_phase:int = 0
var _wool_elapsed:float = 0.0
var _wool_cooldown:float = 0.0
var _caught_projectiles:Array = []
var _reflected_projectiles:Array = []
var _wall_stun_effect:WeakRef
var _remote_wall_stun_visual:bool = false
var _grass_foot_local_y:float = 0.0
var _grass_patch:Node2D
var _wool_visual:Sprite2D
var _wool_fixed_visual:Sprite2D
var _wool_body_frames:Array[Texture2D] = []
var _wool_fixed_frames:Array[Texture2D] = []

func _ready() -> void:
	super._ready()
	wool = wool_max
	_visual_rest = image.position
	_visual_base_scale = image.scale
	_observed_health = health
	add_to_group("MinecraftWoolSheep")
	_create_graze_grass()
	_wool_visual = Sprite2D.new()
	_wool_visual.name = "NativeWoolShell"
	_wool_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 原生模型按骨骼重烘焙：只有 body 在弹胀层，头/腿独立固定。
	image.add_child(_wool_visual)
	_wool_fixed_visual = Sprite2D.new()
	_wool_fixed_visual.name = "FixedNativeHeadAndLegs"
	_wool_fixed_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.add_child(_wool_fixed_visual)
	for row:int in range(2):
		for index:int in range(8):
			var body_frame:AtlasTexture = AtlasTexture.new()
			body_frame.atlas = WOOL_BODY_ATLAS
			body_frame.region = Rect2(index*128,row*128,128,128)
			body_frame.filter_clip = true
			_wool_body_frames.append(body_frame)
			var fixed_frame:AtlasTexture = AtlasTexture.new()
			fixed_frame.atlas = WOOL_FIXED_ATLAS
			fixed_frame.region = body_frame.region
			fixed_frame.filter_clip = true
			_wool_fixed_frames.append(fixed_frame)
	Damage_reduction = 0.0
	_sound_position = global_position
	_ambient_cd = rng.randf_range(2.0,4.0)

func attack_damage(multiplier:float = 1.0) -> float:
	return super.attack_damage(multiplier)*0.8

func voice_role() -> String:
	return "sheep"

func play_sound(event:String,volume_db:float = -5.0) -> AudioStreamPlayer2D:
	if event.is_empty() or not is_multiplayer_authority(): return null
	if multiplayer.has_multiplayer_peer(): _receive_sheep_sound.rpc(event,global_position,volume_db)
	return _receive_sheep_sound(event,global_position,volume_db)

@rpc("authority","call_remote","reliable")
func _receive_sheep_sound(event:String,point:Vector2,volume_db:float) -> AudioStreamPlayer2D:
	var death:bool = event == "entity.sheep.death"
	if death:
		for voice:Node in get_tree().get_nodes_in_group("MCNativeSFX"):
			if voice.get_meta("sheep_sound_owner",0) == get_instance_id() and voice.get_meta("mc_sound_event","") in ["entity.sheep.ambient","entity.sheep.step"]:
				voice.stop()
				voice.queue_free()
	# 按羊独立调度，冲刺脚步允许重叠；不受其他羊的全局75ms限流影响。
	var player:AudioStreamPlayer2D = AUDIO.play(self,event,point,volume_db,death,death or event == "block.wool.place",true,true)
	if is_instance_valid(player):
		player.set_meta("sheep_sound_owner",get_instance_id())
		# 原版放置羊毛声偏轻：保留原采样，但提高9dB，并获得拥挤声部优先权。
		if event == "block.wool.place": player.volume_db = 6.0
	if event == "entity.sheep.ambient": _breath_player = player
	if event == "entity.sheep.step": _footstep_player = player
	return player

func _sound_duration(player:AudioStreamPlayer2D) -> float:
	return player.stream.get_length()/maxf(player.pitch_scale,0.01) if is_instance_valid(player) and player.stream != null else 0.0

func _step_sheep_sounds(delta:float) -> void:
	var moved_px:float = global_position.distance_to(_sound_position)
	var moved:bool = moved_px > 0.05
	_sound_position = global_position
	if not is_multiplayer_authority() or not active() or health <= 0: return
	_ambient_cd = maxf(_ambient_cd-delta,0.0)
	if _ambient_cd <= 0 and not (is_instance_valid(_breath_player) and _breath_player.playing):
		var breath:AudioStreamPlayer2D = play_sound("entity.sheep.ambient",-6.0)
		_ambient_cd = _sound_duration(breath)+rng.randf_range(2.0,5.0)
	var charging:bool = ram_state == RamState.CHARGE
	var walking:bool = moved and not is_transport_mounted() and not dizziness and ram_state not in [RamState.GRAZE,RamState.RECOVER]
	if not _footstep_cadence.tick(moved_px if walking else 0.0,delta,FOOTSTEP.base_speed(self),footstep_base_interval): return
	play_sound("entity.sheep.step",-8.0 if not charging else -5.0)

func apply_knockback(knockback_direction:Vector2,knockback_distance:float,knockback_speed:float = 700.0,wall_bounce_strength:float = 0.0,stun_duration:float = 0.0,options:Dictionary = {}) -> Node:
	# 后撤与冲锋只免疫位移型击退，不免疫伤害或独立的纯眩晕。
	if ram_state in [RamState.WINDUP,RamState.CHARGE] and knockback_distance > 0.0: return null
	return super.apply_knockback(knockback_direction,knockback_distance,knockback_speed,wall_bounce_strength,stun_duration,options)

func _clear_ram_knockback() -> void:
	# 清理进入蓄力前残留的击退，以及直接写 Repel 的旧攻击路径。
	for effect:Node in get_children():
		if effect.get_script() == KNOCKBACK_EFFECT_SCRIPT and float(effect.get("distance")) > 0.0:
			effect._finish(false)
	Repel = Vector2.ZERO

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if not is_multiplayer_authority() or health <= 0: return
	_since_hurt = 0.0
	_observed_health = health
	_heal_pool = 0.0
	_graze_elapsed = 0.0
	_bite_flash_left = 0.0
	if ram_state in [RamState.GRAZE,RamState.BRAKE_GRAZE]: _finish_grazing()
	_update_graze_grass()

func step_mob(delta:float) -> void:
	if not active(): return
	_graze_cooldown_left = maxf(_graze_cooldown_left-maxf(delta,0.0),0.0)
	if ram_state in [RamState.WINDUP,RamState.CHARGE]: _clear_ram_knockback()
	_step_sheep_sounds(delta)
	_wall_squash_age += delta
	_bite_flash_left = maxf(_bite_flash_left-delta,0.0)
	Damage_reduction = 0.0
	if health < _observed_health:
		_since_hurt = 0.0
		_heal_pool = 0.0
		_graze_elapsed = 0.0
		_bite_flash_left = 0.0
		if ram_state in [RamState.GRAZE,RamState.BRAKE_GRAZE]: _finish_grazing()
	_observed_health = health
	_since_hurt += delta
	_step_wool(delta)
	if ram_state not in [RamState.WINDUP,RamState.CHARGE]:
		_ram_left = maxf(_ram_left-delta,0.0)
	_phase_left -= delta
	_moving = velocity.length_squared() > 100.0
	if ram_state == RamState.ROAM and velocity.length_squared() > 100.0: facing = velocity.normalized()
	# 低血量休整优先于寻敌/蓄力，不受敌人距离影响；进入后只由满血或扣血结束。
	if _graze_cooldown_left <= 0.0 and ram_state not in [RamState.GRAZE,RamState.BRAKE_GRAZE] and ram_state != RamState.CHARGE and health < Max_health*0.75 and _since_hurt >= graze_delay:
		_begin_grazing()
	if ram_state == RamState.GRAZE:
		_graze(delta)
		return
	if ram_state == RamState.BRAKE_GRAZE: return
	if is_transport_mounted():
		_clear_charge_contacts()
		# 乘船禁止助跑位移，但保留船头方向的近身顶击。
		ram_state = RamState.ROAM
		facing = direction
		if can_act() and _ram_left <= 0.0:
			for node:Node in get_tree().get_nodes_in_group("Ball"):
				if not U.enemy(self,node): continue
				var victim:ball = node as ball
				var offset:Vector2 = ball.body_point(victim,global_position)-global_position
				if offset.dot(facing) < 0.0 or offset.length() > _body_radius(self)+_body_radius(victim)+10.0: continue
				if not U.line_clear(self,global_position,ball.body_point(victim,global_position)): continue
				if U.damage(self,victim,attack_damage(1.4),global_position):
					_ram_left = ram_cooldown
					pass # Final HP loss emits the shared 0dB-baseline MC feedback.
					break
		return
	var target:ball = null if is_player_controlled() else U.nearest(self)
	var distance:float = global_position.distance_to(ball.body_point(target,global_position)) if target != null else INF
	if not can_act():
		if ram_state in [RamState.WINDUP,RamState.CHARGE]: _finish_charge(false)
		return
	match ram_state:
		RamState.WINDUP:
			if _phase_left <= 0.0:
				_launch_charge()
		RamState.CHARGE:
			pass
		RamState.RECOVER:
			if _phase_left <= 0.0: ram_state = RamState.ROAM
		_:
			if not is_player_controlled() and distance <= ram_trigger_range and _ram_left <= 0.0 and U.line_clear(self,global_position,ball.body_point(target,global_position)):
				_begin_charge(ball.body_point(target,global_position),target)

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not can_act(): return
	if is_transport_mounted() or ram_state != RamState.ROAM or _ram_left > 0.0: return
	var point:Vector2 = player_control_aim_world_position(global_position)
	var best:float = INF
	var chosen:ball
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball) or not U.enemy(self,raw): continue
		var target:ball = raw as ball
		if global_position.distance_to(ball.body_point(target,global_position)) > ram_trigger_range or not U.line_clear(self,global_position,ball.body_point(target,global_position)): continue
		var tolerance:float = U.radius(target)+16.0
		var squared:float = point.distance_squared_to(ball.body_point(target,point))
		if squared <= tolerance*tolerance and squared < best:
			best = squared
			chosen = target
	if chosen != null: _begin_charge(ball.body_point(chosen,global_position),chosen)

func _begin_charge(point:Vector2,target:ball = null) -> void:
	_clear_ram_knockback()
	_clear_charge_contacts()
	_aim_point = point
	_charge_target = weakref(target) if is_instance_valid(target) else null
	_charge_dir = global_position.direction_to(point)
	if _charge_dir.length_squared() < 0.001: _charge_dir = facing
	_retreat_dir = -_charge_dir
	_retreat_current_speed = retreat_speed
	facing = _charge_dir
	ram_state = RamState.WINDUP
	_phase_left = ram_windup/preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self)
	_ram_left = ram_cooldown
	_charge_speed = 0.0

func _launch_charge() -> void:
	# 只在冲出这一刻读取敌人当前位置，之后绝不更新瞄准点/方向。
	var target = _charge_target.get_ref() if _charge_target != null else null
	if is_instance_valid(target) and target.health > 0: _aim_point = target.global_position
	_charge_target = null
	_charge_dir = global_position.direction_to(_aim_point)
	if _charge_dir.length_squared() < 0.001: _charge_dir = facing
	facing = _charge_dir
	ram_state = RamState.CHARGE
	_charge_speed = maxf(Speed,0.0)
	_charge_distance = 0.0

func impact_profile(impact_speed:float) -> Dictionary:
	var ratio:float = clampf(impact_speed/maxf(charge_speed,1.0),0.0,1.0)
	return {"damage":attack_damage(0.5+3.0*ratio),"distance":35.0+150.0*ratio,"speed":150.0+650.0*ratio,"wall_damage":attack_damage(0.5+1.8*ratio)}

func _graze(delta:float) -> void:
	if not active() or ram_state != RamState.GRAZE: return
	if health >= Max_health:
		_finish_grazing()
		return
	_graze_elapsed += maxf(delta,0.0)
	var interval:float = maxf(graze_bite_interval,0.2)
	while _graze_elapsed+0.000001 >= interval and ram_state == RamState.GRAZE:
		_graze_elapsed = maxf(_graze_elapsed-interval,0.0)
		# 一口一个回血结算；口间绝不回血。保留小数余量以维持原平均恢复速度。
		_heal_pool += Max_health*graze_heal_ratio*interval
		var whole:int = int(_heal_pool)
		_heal_pool -= whole
		var before:int = health
		health = mini(health+whole,Max_health)
		_regrow += maxf(health-before,0)
		_observed_health = health
		var threshold:float = maxf(Max_health*wool_heal_ratio,1.0)
		while _regrow >= threshold:
			_regrow -= threshold
			wool = mini(wool+1,wool_max)
		_bite_serial += 1
		_receive_graze_bite(_bite_serial)
		if multiplayer.has_multiplayer_peer(): _receive_graze_bite.rpc(_bite_serial)
		if health >= Max_health:
			_finish_grazing()

@rpc("authority","call_remote","reliable")
func _receive_graze_bite(serial:int) -> void:
	if serial <= _seen_bite_serial or health <= 0: return
	_seen_bite_serial = serial
	_bite_flash_left = 0.22
	_update_graze_grass()
	var ground:Vector2 = _graze_ground_position()
	if is_instance_valid(_grass_patch) and _grass_patch.visible:
		var fx:Node2D = preload("res://scripts/characters/我的世界/new6/grass_bite_fx.gd").new()
		fx.configure_from_grass(_grass_patch.get_node("VanillaGrass0"),ground)
		get_tree().current_scene.add_child(fx)
		fx.global_position = ground
	AUDIO.play(self,"block.grass.break",ground,-11.0,false,false,true,true)
	AUDIO.play(self,"entity.generic.eat",ground,-4.0,false,false,true,true)

func _body_radius(actor:ball) -> float:
	var shape:CollisionShape2D = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or shape.shape == null: return 10.0
	var size:Vector2 = shape.shape.get_rect().size*shape.global_scale.abs()
	return maxf(size.x,size.y)*0.5

func _clear_charge_contacts() -> void:
	for ref:WeakRef in _charge_exceptions:
		var body = ref.get_ref()
		if is_instance_valid(body): remove_collision_exception_with(body)
	_charge_exceptions.clear()
	_charge_contacts.clear()

func _refresh_charge_contacts() -> void:
	# 只屏蔽当前重叠；离开扫掠半径后恢复碰撞，允许同一趟追上再次撞击。
	for id in _charge_contacts.keys():
		var victim = _charge_contacts[id].get_ref()
		if is_instance_valid(victim) and global_position.distance_to(ball.body_point(victim,global_position)) <= _body_radius(self)+_body_radius(victim)+5.0:
			continue
		_charge_contacts.erase(id)
		for ref:WeakRef in _charge_exceptions.duplicate():
			var body = ref.get_ref()
			if not is_instance_valid(body) or body == victim:
				if is_instance_valid(body): remove_collision_exception_with(body)
				_charge_exceptions.erase(ref)

func _charge_obstacle(node:Node) -> bool:
	# 可破坏墙也是障碍，不能因为继承 ball 就当作普通单位穿过去。
	return not node is ball or U.wall_node(node)

func _charge_touch(victim:ball,point:Vector2) -> bool:
	if not is_instance_valid(victim) or victim == self or _charge_obstacle(victim): return false
	var id:int = victim.get_instance_id()
	if _charge_contacts.has(id): return false
	_charge_contacts[id] = weakref(victim)
	add_collision_exception_with(victim)
	_charge_exceptions.append(weakref(victim))
	var impact:Dictionary = impact_profile(_charge_speed)
	if U.enemy(self,victim) and can_act() and U.damage(self,victim,impact.damage,point):
		victim.apply_knockback(_charge_dir,impact.distance,impact.speed,0.65,0,{"source":self,"max_wall_bounces":1,"collision_damage":impact.wall_damage,"collision_damage_wall_only":true,"redirect_blend_time":0.0})
		pass # Final HP loss emits the shared 0dB-baseline MC feedback.
	# 撞单位消耗动量但不结束冲锋；持续接触只处理一次，分离后再次碰撞可再次受击。
	_charge_speed = maxf(_charge_speed*charge_contact_speed_ratio,minf(_charge_speed,30.0))
	velocity = _charge_dir*_charge_speed
	return true

func _hit_charge_path(from:Vector2,to:Vector2) -> bool:
	var contacts:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or node == self or not node.is_combat_targetable() or _charge_obstacle(node): continue
		var victim:ball = node as ball
		if _charge_contacts.has(victim.get_instance_id()): continue
		if (ball.body_point(victim,from)-from).dot(_charge_dir) < -_body_radius(victim): continue
		if U.segment_distance(ball.body_point_seg(victim,from,to),from,to) > _body_radius(self)+_body_radius(victim)+3.0: continue
		if not U.line_clear(self,from,ball.body_point(victim,from)): continue
		contacts.append(victim)
	contacts.sort_custom(func(a:ball,b:ball): return (ball.body_point(a,from)-from).dot(_charge_dir) < (ball.body_point(b,from)-from).dot(_charge_dir))
	for victim:ball in contacts: _charge_touch(victim,to)
	return not contacts.is_empty()

func _finish_charge(wall:bool,_hit:bool = false,wall_impact_speed:float = -1.0,wall_normal:Vector2 = Vector2.ZERO) -> void:
	var impact_speed:float = _charge_speed if wall_impact_speed < 0 else wall_impact_speed
	_clear_charge_contacts()
	ram_state = RamState.RECOVER
	_ram_left = ram_cooldown
	_phase_left = 0.65
	_charge_speed = 0.0
	velocity = Vector2.ZERO
	if wall and impact_speed > 1.0:
		_wall_squash_age = 0.0
		_wall_squash_axis = -wall_normal if wall_normal.length_squared() > 0.001 else _charge_dir
		_wall_squash_strength = clampf(impact_speed/maxf(charge_speed,1.0),0.3,1.0)
		play_sound("entity.sheep.wall_impact",lerpf(-6.0,0.0,_wall_squash_strength))
	# 撞墙法线上的实际速度足够高才眩晕；低速/擦边撞击不会触发。
	if wall and impact_speed >= wall_stun_speed:
		_phase_left = maxf(_phase_left,wall_stun_duration)
		# 独立的纯眩晕立即进入视觉阶段。复用已有击退控制器会把眩晕排到击退之后，
		# 导致角色已撞停却没有头顶动画；不能只设置 dizziness。
		var stun:Node = apply_knockback(Vector2.ZERO,0.0,0.0,0.0,wall_stun_duration,{"replace_existing":false})
		_wall_stun_effect = weakref(stun) if is_instance_valid(stun) else null
		receive_positional_damage(Max_health*0.025,global_position,false,self)

func move(speed_value:float,delta:float) -> void:
	if ram_state in [RamState.WINDUP,RamState.CHARGE]: _clear_ram_knockback()
	if apply_transport_pose(): return
	if not active(): return
	if ram_state == RamState.BRAKE_GRAZE:
		_graze_velocity = _graze_velocity.move_toward(Vector2.ZERO,graze_braking*delta)
		velocity = _graze_velocity+Repel
		move_and_collide(velocity*delta)
		if _graze_velocity.length() <= 2.0:
			ram_state = RamState.GRAZE
		return
	if ram_state == RamState.WINDUP and not dizziness:
		# 面朝敌人真实后撤，墙后无空间时原地蓄力，不穿墙。
		var next_retreat:float = move_toward(_retreat_current_speed,0.0,retreat_speed/maxf(ram_windup,0.01)*delta)
		var retreat_deceleration:float = retreat_speed/maxf(ram_windup,0.01)
		var braking_time:float = minf(delta,_retreat_current_speed/maxf(retreat_deceleration,0.01))
		var retreat_travel:float = _retreat_current_speed*braking_time-0.5*retreat_deceleration*braking_time*braking_time
		velocity = _retreat_dir*next_retreat+Repel
		move_and_collide(_retreat_dir*retreat_travel+Repel*delta)
		_retreat_current_speed = next_retreat
		return
	if ram_state == RamState.CHARGE and not dizziness:
		_refresh_charge_contacts()
		var old_speed:float = _charge_speed
		var cap:float = maxf(charge_speed,maxf(Speed,0.0))
		var accel:float = maxf(charge_acceleration,0.0)
		var next_speed:float = minf(old_speed+accel*delta,cap)
		var accelerating_time:float = minf(delta,maxf(cap-old_speed,0.0)/accel) if accel > 0.0 else 0.0
		var travel:float = old_speed*accelerating_time+0.5*accel*accelerating_time*accelerating_time+next_speed*(delta-accelerating_time)
		velocity = _charge_dir*old_speed
		var start:Vector2 = global_position
		var collision:KinematicCollision2D = move_and_collide(_charge_dir*travel)
		var moved:float = start.distance_to(global_position)
		_charge_distance += moved
		# 撞到障碍前实际走了多少，决定接触瞬间剩余速度。
		_charge_speed = minf(sqrt(maxf(old_speed*old_speed+2.0*accel*moved,0.0)),cap)
		if collision == null: _charge_speed = next_speed
		velocity = _charge_dir*_charge_speed
		var obstacle_speed:float = _charge_speed
		_hit_charge_path(start,global_position)
		if collision != null:
			var collider:Node = collision.get_collider() as Node
			if _charge_obstacle(collider):
				_finish_charge(true,false,absf((_charge_dir*obstacle_speed).dot(collision.get_normal())),collision.get_normal())
			elif collider is ball:
				_charge_touch(collider,global_position)
		# 没有距离/时间到期收招：只有撞上实体障碍才结束这趟冲锋。
		return
	if ram_state in [RamState.WINDUP,RamState.RECOVER,RamState.GRAZE]:
		super.stand(delta)
		return
	super.move(speed_value*(sheared_speed_mult if wool <= 0 else 1.0),delta)

func _attacking() -> bool:
	return ram_state in [RamState.WINDUP,RamState.CHARGE, RamState.RECOVER]

func _begin_wool() -> bool:
	if not active() or wool <= 0 or _wool_phase != 0 or _wool_cooldown > 0.0: return false
	wool -= 1
	_wool_phase = 3 if wool == 0 else 1
	_wool_elapsed = 0.0
	_wool_cooldown = 0.9
	_wool_burst()
	return true

func catch_wool_projectile(shot:Node2D) -> bool:
	if not active() or not WOOL_PROJECTILE.is_projectile(shot): return false
	if global_position.distance_to(ball.body_point(shot,global_position)) > wool_projectile_radius+0.05: return false
	if shot is ball:
		var effective_team:String = shot.Team
		if (effective_team.is_empty() or effective_team == "Ball") and is_instance_valid(shot.Master): effective_team = shot.Master.Team
		if effective_team == Team and not effective_team.is_empty() and not shot.Ignore_Team_Damage_Setting: return false
	if shot.has_meta("mc_wool_flight"):
		var existing = shot.get_meta("mc_wool_flight").get_ref()
		if is_instance_valid(existing):
			if existing.holder != null and existing.holder.get_ref() == self: return true
			if existing.grace > 0 and existing.last_holder != null and existing.last_holder.get_ref() == self: return true
	if _wool_phase == 0 and not _begin_wool(): return false
	var controller
	if shot.has_meta("mc_wool_flight"): controller = shot.get_meta("mc_wool_flight").get_ref()
	if not is_instance_valid(controller):
		controller = WOOL_PROJECTILE.new()
		get_tree().current_scene.add_child(controller,true)
		controller.setup(shot,self)
	else:
		controller.hold_by(self)
	# 直接弹开，不再等待压缩蓄力。
	controller.launch()
	if not _reflected_projectiles.has(controller): _reflected_projectiles.append(controller)
	return true

func can_receive_hit_from(incoming) -> bool:
	if incoming == null: return true
	var shot:Node = incoming.get_parent()
	if not WOOL_PROJECTILE.is_projectile(shot) and incoming.owner is Node2D: shot = incoming.owner
	if shot is Node2D and catch_wool_projectile(shot): return false
	return true
func should_destroy_projectile_on_rejected_hit(incoming:hitbox) -> bool:
	return incoming == null or not WOOL_PROJECTILE.is_projectile(incoming.get_parent())

func _step_wool(delta:float) -> void:
	_wool_cooldown = maxf(_wool_cooldown-delta,0.0)
	if _wool_phase > 0:
		_wool_elapsed += delta
		if _wool_phase == 3 and _wool_elapsed >= 0.10:
			play_sound("block.wool.break",-3.0)
			_wool_break_serial += 1
			_receive_wool_break(_wool_break_serial)
			if multiplayer.has_multiplayer_peer(): _receive_wool_break.rpc(_wool_break_serial)
			_wool_phase = 0
			_wool_elapsed = 0.0
		elif _wool_phase != 3 and _wool_elapsed >= 0.45:
			_wool_phase = 0
			_wool_elapsed = 0.0
	if _wool_phase == 0 and (wool <= 0 or _wool_cooldown > 0): return
	for node:Node in WOOL_PROJECTILE.candidates(get_tree()):
		if node == self or not node is Node2D: continue
		if WOOL_PROJECTILE.is_projectile(node):
			var flight:Vector2 = WOOL_PROJECTILE.motion(node)
			var offset:Vector2 = global_position-ball.body_point(node,global_position)
			if flight.dot(offset) <= 0: continue
			if global_position.distance_to(ball.body_point(node,global_position)) > wool_projectile_radius: continue
			if U.line_clear(self,global_position,ball.body_point(node,global_position)): catch_wool_projectile(node)
		elif not _attacking() and U.enemy(self,node) and global_position.distance_to(ball.body_point(node,global_position)) <= wool_trigger_radius:
			if U.line_clear(self,global_position,ball.body_point(node,global_position)): _begin_wool()

@rpc("authority","call_remote","reliable")
func _receive_wool_break(serial:int) -> void:
	if serial <= _seen_wool_break_serial or health <= 0: return
	_seen_wool_break_serial = serial
	# 从原版羊毛当前帧采样碎块，保留放大时的位置；碎屑独立落地、停留。
	visual_mob()
	var previous_scale:Vector2 = _wool_visual.scale
	_wool_visual.scale = Vector2.ONE*WOOL_PEAK
	var ground:Vector2 = graphics.to_global(_visual_rest+Vector2(0,_grass_foot_local_y*image.scale.y))
	var fx:Node2D = preload("res://scripts/characters/我的世界/new6/wool_break_fx.gd").new()
	fx.configure_from_wool(_wool_visual,ground)
	_wool_visual.scale = previous_scale
	get_tree().current_scene.add_child(fx)
	fx.global_position = ground

func _wool_burst() -> void:
	for controller in _caught_projectiles:
		if is_instance_valid(controller): controller.launch()
	_caught_projectiles.clear()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,node) or WOOL_PROJECTILE.is_projectile(node): continue
		if global_position.distance_to(ball.body_point(node,global_position)) > wool_burst_radius or not U.line_clear(self,global_position,ball.body_point(node,global_position)): continue
		var dir:Vector2 = global_position.direction_to(ball.body_point(node,global_position))
		if dir.length_squared() < 0.01: dir = facing
		node.apply_knockback(dir,85.0,520.0,0.25,0.0,{"source":self})
	play_sound("block.wool.place",-3.0)

func _finish_grazing() -> void:
	# 完成和中断共用退出入口；冷却从退出吃草开始，而不是被长时间吃草耗完。
	ram_state = RamState.ROAM
	_graze_cooldown_left = maxf(graze_cooldown,0.0)
	_heal_pool = 0.0
	_graze_elapsed = 0.0
	_bite_flash_left = 0.0
	_update_graze_grass()

func _begin_grazing() -> void:
	if not active() or _graze_cooldown_left > 0.0 or ram_state in [RamState.GRAZE,RamState.BRAKE_GRAZE]: return
	_clear_charge_contacts()
	_graze_elapsed = 0.0
	_bite_flash_left = 0.0
	_charge_target = null
	_charge_speed = 0.0
	_graze_velocity = velocity-Repel
	ram_state = RamState.BRAKE_GRAZE
	if is_transport_mounted() or _graze_velocity.length() < 2.0: ram_state = RamState.GRAZE

func _release_wool_projectiles() -> void:
	for controller in _caught_projectiles:
		if is_instance_valid(controller): controller.launch()
	_caught_projectiles.clear()
func Die() -> void:
	_clear_charge_contacts()
	_release_wool_projectiles()
	if is_instance_valid(_grass_patch): _grass_patch.hide()
	super.Die()
func _exit_tree() -> void:
	_clear_charge_contacts()
	_release_wool_projectiles()
	super._exit_tree()

func _create_graze_grass() -> void:
	# 根据原生静止帧的非透明脚底计算地面，不使用角色中心的固定偏移。
	var texture:Texture2D = FRAMES.get_frame_texture(&"sheared_idle",0)
	var pixels:Image = texture.get_image()
	var used:Rect2i = pixels.get_used_rect()
	_grass_foot_local_y = float(used.end.y)-texture.get_height()*0.5
	_grass_patch = Node2D.new()
	_grass_patch.name = "MinecraftGrazingGrass"
	add_child(_grass_patch)
	_grass_patch.top_level = true
	_grass_patch.z_as_relative = false
	_grass_patch.z_index = -1
	_grass_patch.visible = false
	var tuft:Sprite2D = Sprite2D.new()
	tuft.name = "VanillaGrass0"
	tuft.texture = preload("res://Images/characters/我的世界/new6/short_grass.png")
	tuft.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tuft.modulate = Color("80b84a")
	tuft.scale = Vector2(0.95,0.95)
	# 锚点在草根：咬下时缩短草叶不会使整株草离开地面。
	tuft.centered = false
	tuft.offset = Vector2(-8,-16)
	_grass_patch.add_child(tuft)

func _graze_ground_position() -> Vector2:
	var foot:Vector2 = graphics.to_global(_visual_rest+Vector2(0,_grass_foot_local_y*image.scale.y))
	return foot+Vector2(12.0 if facing.x >= 0 else -12.0,2.0)

func _update_graze_grass() -> void:
	if not is_instance_valid(_grass_patch): return
	_grass_patch.visible = health > 0 and ram_state == RamState.GRAZE and not is_transport_mounted()
	if _grass_patch.visible:
		_grass_patch.global_position = _graze_ground_position()
		_grass_patch.global_rotation = 0.0
		var tuft:Sprite2D = _grass_patch.get_node("VanillaGrass0")
		tuft.position = Vector2.ZERO
		# 咬下时草短暂压低，再恢复；始终只有这一株草。
		var bite:float = clampf(_bite_flash_left/0.22,0.0,1.0)
		tuft.scale = Vector2(0.95,0.95-0.38*bite)

func _apply_wall_squash() -> void:
	if _wall_squash_age >= wall_squash_duration: return
	var age:float = maxf(_wall_squash_age,0.0)
	var wave:float
	if age < 0.065:
		wave = smoothstep(0.0,0.065,age)
	else:
		var t:float = (age-0.065)/maxf(wall_squash_duration-0.065,0.01)
		wave = exp(-5.0*t)*cos(t*TAU*1.5)
	wave *= _wall_squash_strength
	var axis:Vector2 = graphics.global_transform.basis_xform_inv(_wall_squash_axis).normalized()
	var angle:float = axis.angle()
	var squash:Transform2D = Transform2D(angle,Vector2.ZERO)*Transform2D(0.0,Vector2(1.0-0.48*wave,1.0+0.22*wave),0.0,Vector2.ZERO)*Transform2D(-angle,Vector2.ZERO)
	var pose:Transform2D = image.transform
	image.transform = Transform2D(squash.basis_xform(pose.x),squash.basis_xform(pose.y),pose.origin)

func _process(delta:float) -> void:
	_legs_delta += maxf(delta,0.0)
	super._process(delta)

func _sheep_gait() -> RefCounted:
	if gait == null:
		gait = MC_LEGS.create(float(FRAMES.get_frame_count(&"sheared_walk"))/maxf(FRAMES.get_animation_speed(&"sheared_walk"),0.001),[0.25,0.75])
		gait.observe(self)
	return gait

func visual_mob() -> void:
	# 每帧从原始尺寸重新叠加压缩，避免积累变形；不修改实体碰撞。
	image.transform = Transform2D(0.0,_visual_base_scale,0.0,_visual_rest)
	_update_graze_grass()
	var legs:RefCounted = _sheep_gait()
	var legs_step:float = _legs_delta
	_legs_delta = 0.0
	if health > 0 and is_combat_runtime_active():
		legs.tick(self,legs_step,dizziness != true and not is_transport_mounted() and ram_state not in [RamState.GRAZE,RamState.RECOVER])
	else: legs.observe(self)
	var moving:bool = not legs.at_rest
	# 弹胀材质只含躯干，没有任何头部像素，避免白色脸部被误判为羊毛。
	var frame_index:int = legs.walk_index(8) if moving else int(_view_clock*FRAMES.get_animation_speed(&"wool_idle"))%8+8
	if is_instance_valid(_wool_visual): _wool_visual.texture = _wool_body_frames[frame_index]
	if is_instance_valid(_wool_fixed_visual): _wool_fixed_visual.texture = _wool_fixed_frames[frame_index]
	if moving and image is Sprite2D: image.texture = FRAMES.get_frame_texture(&"sheared_walk",legs.walk_index(FRAMES.get_frame_count(&"sheared_walk")))
	else: frame(FRAMES,&"sheared_idle")
	face_horizontal(facing,true)
	image.position = _visual_rest
	if is_instance_valid(_wool_visual):
		_wool_visual.visible = wool > 0 or _wool_phase > 0
		_wool_visual.flip_h = is_character_visual_flipped_h()
		var factor:float = 1.0
		if _wool_phase > 0:
			# 瞬间膨胀，阻尼弹簧回缩；尾端归零避免收尾跳变。
			var t:float = clampf(_wool_elapsed/0.45,0.0,1.0)
			factor = WOOL_PEAK if _wool_phase == 3 else 1.0+(WOOL_PEAK-1.0)*exp(-4.0*t)*cos(TAU*1.5*t)*(1.0-t)
		_wool_visual.scale = Vector2.ONE*factor
	if is_instance_valid(_wool_fixed_visual):
		_wool_fixed_visual.visible = wool > 0 or _wool_phase > 0
		_wool_fixed_visual.flip_h = is_character_visual_flipped_h()
		_wool_fixed_visual.scale = Vector2.ONE
		_wool_fixed_visual.position = Vector2.ZERO
		_wool_fixed_visual.rotation = 0.0
	if ram_state == RamState.WINDUP:
		image.rotation = deg_to_rad(8.0)*(1.0 if facing.x >= 0 else -1.0)
	elif ram_state == RamState.GRAZE:
		var phase:float = clampf(_graze_elapsed/maxf(graze_bite_interval,0.2),0,1)
		var dip:float = maxf(smoothstep(0.45,1.0,phase),clampf(_bite_flash_left/0.22,0,1))
		image.rotation = 0.0 # 吃草只做低头位移，不循环旋转整只羊。
		image.position.y += 2.0+4.0*dip

	_apply_wall_squash()

func _wall_stun_active() -> bool:
	var effect = _wall_stun_effect.get_ref() if _wall_stun_effect != null else null
	return is_instance_valid(effect) and effect.is_active_effect()

func _set_remote_wall_stun_visual(enabled:bool) -> void:
	if enabled == _remote_wall_stun_visual: return
	_remote_wall_stun_visual = enabled
	if enabled: begin_stun_visual()
	else: end_stun_visual()

func visual_state() -> Dictionary:
	var shots:Array = []
	for controller in _reflected_projectiles.duplicate():
		if not is_instance_valid(controller) or controller.is_queued_for_deletion():
			_reflected_projectiles.erase(controller)
			continue
		var data:Dictionary = controller.snapshot()
		if not data.is_empty(): shots.append(data)
	return {"time":clock,"facing":facing,"wool":wool,"moving":_moving,"ram_state":int(ram_state),"wool_phase":_wool_phase,"wool_elapsed":_wool_elapsed,"wool_shots":shots,"wall_stunned":_wall_stun_active(),"graze_elapsed":_graze_elapsed,"wall_squash_age":_wall_squash_age,"wall_squash_axis":_wall_squash_axis,"wall_squash_strength":_wall_squash_strength}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	facing = data.get("facing",facing)
	wool = int(data.get("wool",wool))
	_moving = bool(data.get("moving",_moving))
	ram_state = int(data.get("ram_state",ram_state)) as RamState
	_wool_phase = int(data.get("wool_phase",0))
	_wool_elapsed = float(data.get("wool_elapsed",0.0))
	_graze_elapsed = float(data.get("graze_elapsed",0.0))
	_wall_squash_age = float(data.get("wall_squash_age",999.0))
	_wall_squash_axis = data.get("wall_squash_axis",Vector2.RIGHT)
	_wall_squash_strength = float(data.get("wall_squash_strength",0.0))
	WOOL_PROJECTILE.accept_snapshots(self,data.get("wool_shots",[]))
	if not is_multiplayer_authority(): _set_remote_wall_stun_visual(bool(data.get("wall_stunned",false)))

func client_visual_step(delta:float) -> void:
	_wall_squash_age += delta
	_bite_flash_left = maxf(_bite_flash_left-delta,0.0)
	if ram_state == RamState.GRAZE: _graze_elapsed = minf(_graze_elapsed+delta,graze_bite_interval)
	if _wool_phase > 0:
		_wool_elapsed += delta
		if _wool_phase == 3 and _wool_elapsed >= 0.10: _wool_phase = 0
