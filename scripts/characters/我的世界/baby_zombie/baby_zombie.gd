extends "res://scripts/characters/我的世界/zombie/zombie.gd"
## 原版（26.1 起）小僵尸核心 AI：无目标时随机漫步并停顿；看见敌人后追击；
## 原版攻击判定盒内挥臂近战，间隔 Attack_Cooling；受伤后锁定攻击者，并呼叫附近同队、当前没有目标的僵尸。
const BABY_FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/baby_zombie/baby_zombie.tres")
const PROJECTILE_OWNER = preload("res://classes/projectile_interactions.gd")
const BLOCK:float = 64.0 # 成年僵尸 128 px 碰撞高 ≈ 原版 1.95 格
const FOLLOW_RANGE:float = 35.0*BLOCK
const MELEE_REACH:float = (0.49*0.5+0.828)*BLOCK # 半身宽 + 原版攻击判定盒水平外扩 sqrt(2.04)-0.6
const SCAN_INTERVAL:float = 0.5 # 无目标时平均每 10 tick 找一次看得见的最近敌人
const UNSEEN_MEMORY:float = 3.0 # 连续 60 tick 看不见就放弃目标
const STROLL_INTERVAL:float = 6.0 # 漫步：每 tick 1/120 概率出发
const STROLL_RANGE:float = 10.0*BLOCK
const SWING_TIME:float = 0.3 # 生物挥臂 6 tick
const SWING_FRAMES:int = 5
const ATTACK_LEG_PHASES:int = 8
const GAIT_STRIDE:float = 15.0 # 腿长减半，同样摆角下每像素摆动翻倍（成年 30）
const KNOCKBACK_DISTANCE:float = 20.0
const KNOCKBACK_SPEED:float = 220.0
const VOICE_PITCH:Vector2 = Vector2(1.5,0.2)
var baby_target:WeakRef
var baby_unseen:float = 0.0
var baby_moving:bool = false
var baby_strolling:bool = false
var baby_stroll_to:Vector2
var baby_stroll_left:float = 0.0
var baby_swing_clock:float = -1.0
var baby_swing_serial:int = 0
var baby_swing_received:int = 0

func _ready() -> void:
	super._ready()
	voice.voice_pitch = VOICE_PITCH

func body_frames() -> SpriteFrames: return BABY_FRAMES
func bite_reach() -> float: return MELEE_REACH*COPY_SIZE.of(self)
func baby_follow_range() -> float: return FOLLOW_RANGE*COPY_SIZE.of(self)

func step_zombie(delta:float) -> void:
	_damage_regions.clear()
	_hold_distance = false
	baby_moving = false
	bite_cooldown = maxf(0.0,bite_cooldown-delta)
	if not can_act() or is_player_controlled(): return
	var target:ball = baby_current_target(delta)
	if target == null:
		baby_stroll(delta)
		return
	baby_strolling = false
	var offset:Vector2 = ball.body_point(target,global_position)-global_position
	if offset.length_squared() > 0.01: direction = offset.normalized()
	baby_moving = true # 原版近战目标在攻击距离内也继续贴近
	if bite_cooldown <= 0.0: begin_bite(target)

func baby_current_target(delta:float) -> ball:
	var target:Variant = baby_target.get_ref() if baby_target != null else null
	if target != null and not baby_can_keep(target): target = null
	if target != null:
		baby_unseen = 0.0 if baby_sees(target) else baby_unseen+delta
		if baby_unseen <= UNSEEN_MEMORY: return target
		target = null
	baby_target = null
	if _mc_rng.randf() >= delta/SCAN_INTERVAL: return null
	var best:float = INF
	var found:ball = null
	for raw:Variant in SubmissionCharacterTools.targeting_candidates(self):
		if not baby_can_keep(raw) or not baby_sees(raw): continue
		var distance:float = global_position.distance_squared_to(ball.body_point(raw,global_position))
		if distance < best:
			best = distance
			found = raw
	if found != null: baby_lock(found)
	return found

func baby_can_keep(target:Variant) -> bool:
	if not mc_enemy(target) or not target.is_combat_lockable(): return false
	return global_position.distance_to(ball.body_point(target,global_position)) <= baby_follow_range()
func baby_sees(target:ball) -> bool: return mc_line_clear(global_position,ball.body_point(target,global_position))
func baby_lock(target:ball) -> void:
	baby_target = weakref(target)
	baby_unseen = 0.0
	baby_strolling = false

func baby_stroll(delta:float) -> void:
	if baby_strolling:
		baby_stroll_left -= delta
		var offset:Vector2 = baby_stroll_to-global_position
		if offset.length() <= 6.0 or baby_stroll_left <= 0.0:
			baby_strolling = false
			return
		direction = offset.normalized()
		baby_moving = true
		return
	if _mc_rng.randf() >= delta/STROLL_INTERVAL: return
	var area:Rect2 = mc_arena_rect().grow(-24.0)
	var reach:float = STROLL_RANGE*COPY_SIZE.of(self)
	for attempt:int in range(10):
		var point:Vector2 = global_position+Vector2(_mc_rng.randf_range(-reach,reach),_mc_rng.randf_range(-reach,reach))
		point = point.clamp(area.position,area.end)
		if point.distance_to(global_position) < 24.0 or not mc_body_position_clear(point) or not mc_line_clear(global_position,point): continue
		baby_stroll_to = point
		baby_stroll_left = point.distance_to(global_position)/maxf(Speed,1.0)*1.5+0.5
		baby_strolling = true
		return

func move(speed:float,delta:float):
	if not is_player_controlled() and not baby_moving:
		stand(delta)
		return
	super.move(speed,delta)

func begin_bite(target:Variant) -> bool:
	if not can_act() or bite_cooldown > 0.0: return false
	if not mc_enemy(target):
		if is_player_controlled(): baby_swing(Attack_Cooling) # 手控时对空挥臂
		return false
	var point:Vector2 = ball.body_point(target,global_position)
	if global_position.distance_to(point) > bite_reach() or not mc_line_clear(global_position,point): return false
	baby_swing(Attack_Cooling)
	_damage_regions.append({"shape":"circle","position":point,"radius":6.0,"damage":attack_damage(),"source":self,"kind":"baby_zombie_swing"})
	var heading:Vector2 = global_position.direction_to(point)
	if target.receive_classified_positional_damage(attack_damage(),point,&"ordinary",false,self,{"carrier":"body_contact"}) and is_instance_valid(target) and target.health > 0 and heading != Vector2.ZERO:
		target.apply_knockback(heading,KNOCKBACK_DISTANCE,KNOCKBACK_SPEED,0.0,0.0,{"source":self,"lock_control":false,"stop_on_character":true})
	return true

func baby_swing(cooldown:float) -> void:
	bite_cooldown = cooldown
	baby_swing_serial += 1
	_receive_swing(baby_swing_serial)
	if multiplayer.has_multiplayer_peer(): _receive_swing.rpc(baby_swing_serial)

@rpc("authority","call_remote","reliable")
func _receive_swing(serial:int) -> void:
	if serial <= baby_swing_received: return
	baby_swing_received = serial
	baby_swing_clock = 0.0

func record_combat_damage_source(source:Node,health_before:float) -> void:
	super.record_combat_damage_source(source,health_before)
	baby_hurt_by(source)
func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	var accepted:bool = super.receive_positional_damage(damage,impact_position,ignore_block,source)
	if accepted: baby_hurt_by(source)
	return accepted
func _on_hurtbox_on_hurt(hit:hitbox) -> void:
	super._on_hurtbox_on_hurt(hit)
	if is_instance_valid(hit): baby_hurt_by(hit.get_parent())

func baby_attacker_of(source:Variant) -> Variant:
	if not is_instance_valid(source): return null
	if mc_enemy(source): return source
	var shooter:Variant = PROJECTILE_OWNER.owner_of(source)
	if mc_enemy(shooter): return shooter
	var leader:Variant = source.get("Master")
	return leader if mc_enemy(leader) else null

func baby_hurt_by(source:Variant) -> void:
	if not is_multiplayer_authority() or health <= 0: return
	var attacker:Variant = baby_attacker_of(source)
	if attacker == null or not attacker.is_combat_lockable(): return
	baby_lock(attacker)
	if Team.is_empty(): return
	for raw:Variant in get_tree().get_nodes_in_group(&"MinecraftZombie"):
		if raw == self or not is_instance_valid(raw) or not raw.has_method("zombie_alert") or raw.Team != Team: continue
		if raw.global_position.distance_to(global_position) <= baby_follow_range(): raw.zombie_alert(attacker)

func zombie_alert(attacker:Variant) -> void:
	var current:Variant = baby_target.get_ref() if baby_target != null else null
	if is_multiplayer_authority() and health > 0 and not baby_can_keep(current) and mc_enemy(attacker) and attacker.is_combat_lockable(): baby_lock(attacker)

func get_ai_attack_threats() -> Array[Dictionary]:
	var target:Variant = baby_target.get_ref() if baby_target != null else null
	if not can_act() or not mc_enemy(target): return []
	return [{"shape":"circle","position":global_position,"radius":bite_reach(),"damage":attack_damage(),"source":self,"danger_delay":bite_cooldown,"danger_duration":0.05,"kind":"baby_zombie_swing"}]

func _process(delta:float) -> void:
	_update_wall_entry()
	var moved:float = global_position.distance_to(_previous)
	_previous = global_position
	if health <= 0 or not is_combat_runtime_active() or get_tree().paused: return
	_idle_clock += delta
	_walking = not dizziness and moved > 0.02 and moved < 50.0
	if _walking: _gait += moved/GAIT_STRIDE
	var frames:SpriteFrames = body_frames()
	if baby_swing_clock >= 0.0:
		baby_swing_clock += delta
		if baby_swing_clock >= SWING_TIME: baby_swing_clock = -1.0
	if baby_swing_clock >= 0.0:
		var phase:int = clampi(int(baby_swing_clock/SWING_TIME*SWING_FRAMES),0,SWING_FRAMES-1)
		if _walking: image.texture = frames.get_frame_texture(&"attack_walk",posmod(int(_gait*ATTACK_LEG_PHASES),ATTACK_LEG_PHASES)*SWING_FRAMES+phase)
		else: image.texture = frames.get_frame_texture(&"attack_idle",phase)
	else:
		var clip:StringName = &"walk" if _walking else &"idle"
		var index:int = int(_gait*frames.get_frame_count(clip)) if _walking else int(_idle_clock*frames.get_animation_speed(clip))
		image.texture = frames.get_frame_texture(clip,posmod(index,frames.get_frame_count(clip)))
	image.rotation = 0.0

func get_armor_test_effect_summary() -> String: return Game.t("MC_ARMOR_INTRO_BABY_ZOMBIE")
