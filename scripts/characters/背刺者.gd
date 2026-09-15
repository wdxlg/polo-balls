extends ball

# 背刺者完全依靠飞刀输出；本体实体碰撞只负责正常物理阻挡/反弹。
const KNIFE_SCENE := preload("res://scenes/shooter/knife.tscn")

@export_category("背刺者 - 外观")
@export var friendly_texture:Texture2D
@export var knife_texture:Texture2D

@export_category("背刺条件")
# 与原版背刺鼠保持一致：不是窄锥形瞄准，而是“前半区 / 后半区”判断。
# tolerance 只用于防止恰好 90° 时浮点抖动。
@export_range(0.0,0.5,0.01) var facing_dot_tolerance:float = 0.02

@export_category("飞刀")
@export_range(10.0,1500.0,10.0) var projectile_speed:float = 360.0
@export_range(0.0,300.0,1.0) var projectile_spawn_offset:float = 30.0
@export var shoot_audio:String = "背刺者/飞刀掷出"
@export var knife_hit_audio:String = "背刺者/飞刀命中"
@export var enter_backstab_audio:String = "背刺者/进入背刺"
# 背刺窗口往往很短：进入合法背刺后很快出第一刀；
# 真正的慢攻速由 shot_cooldown 控制，而不是要求姿态连续保持几秒。
@export_range(0.02,0.5,0.01) var backstab_trigger_delay:float = 0.08
@export_range(0.1,10.0,0.05) var shot_cooldown:float = 2.35

@export_category("小幅避让")
# 只在真正的敌方角色靠得较近、并且大致挡在当前前方时尝试避让。
@export_range(0.0,400.0,1.0) var evade_trigger_distance:float = 118.0
@export_range(-1.0,1.0,0.05) var evade_front_dot_threshold:float = 0.12
# 每次只把原来的移动方向扭一点，不变成自由寻路。
@export_range(0.0,45.0,1.0) var evade_turn_degrees:float = 18.0
@export_range(0.1,5.0,0.05) var evade_cooldown_min:float = 0.75
@export_range(0.1,5.0,0.05) var evade_cooldown_max:float = 1.20

var _evade_cooldown_left:float = 0.0
var _shot_cooldown_left:float = 0.0
var _backstab_visual_active:bool = false


func _ready() -> void:
	# 与背刺鼠相同：队友也可以成为攻击目标，并且无视全局友伤开关。
	Can_Target_Teammates = true
	Prefer_Teammates = false
	Ignore_Team_Damage_Setting = true
	# ball.gd 只有在 continue_attack_time 达到 continue_attack_cooling 后才会调用 continue_attack。
	# 这里必须使用很短的触发延迟，否则背刺姿态在自动碰撞中通常维持不到几秒。
	continue_attack_cooling = backstab_trigger_delay
	super._ready()
	_set_character_texture(friendly_texture)


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority():
		_shot_cooldown_left = maxf(_shot_cooldown_left - delta,0.0)
		_process_small_evade(delta)

	# 继续使用 ball.gd 原本的移动、撞墙反弹、Buff、状态机规则。
	super.tick_physics(state,delta)

	if not is_multiplayer_authority():
		return

	# V130：直接控制期间不能再由“是否形成背刺角”自动开/关攻击。
	# 玩家左键决定何时出刀，鼠标决定方向；背刺角只保留给 AI。
	if has_player_control_aim():
		_update_backstab_visual(Attacking)
		return

	var target = return_reusable_combat_target()
	var can_backstab:bool = _has_backstab_angle(target)
	_update_backstab_visual(can_backstab)

	if can_backstab and not Attacking:
		Attacking = true
	elif not can_backstab and Attacking:
		Attacking = false


func _update_backstab_visual(active:bool) -> void:
	if _backstab_visual_active == active:
		return
	_backstab_visual_active = active
	_set_character_texture(knife_texture if active else friendly_texture)

	# 只保留“进入背刺”音效。恢复普通状态时仅切换图片，不再播放任何声音。
	if active and enter_backstab_audio != "":
		Audios.play_sfx.rpc(enter_backstab_audio,{},false,true)


func _set_character_texture(texture:Texture2D) -> void:
	if image is Sprite2D and texture != null:
		(image as Sprite2D).texture = texture


# 本体无碰撞伤害现在由 ball.Has_Collision_Damage=false 统一控制。
# 不再覆写 _on_hitbox_on_hit，避免每个无碰撞伤害角色各写一套特殊逻辑。


func _process_small_evade(delta:float) -> void:
	_evade_cooldown_left = maxf(_evade_cooldown_left - delta,0.0)
	if _evade_cooldown_left > 0.0:
		return
	if direction.length_squared() <= 0.000001:
		return

	# 用 World 原本维护的 Nearest_Enemy，只躲真正的敌人；
	# 不因为背刺者允许攻击队友，就连队友也一起躲。
	var enemy = Nearest_Enemy
	if enemy == null or not is_instance_valid(enemy) or not (enemy is ball):
		return
	if enemy.health <= 0:
		return

	var to_enemy:Vector2 = combat_target_position(enemy) - global_position
	var distance_sq:float = to_enemy.length_squared()
	if distance_sq <= 0.000001 or distance_sq > evade_trigger_distance * evade_trigger_distance:
		return

	var forward:Vector2 = direction.normalized()
	var enemy_dir:Vector2 = to_enemy.normalized()
	if forward.dot(enemy_dir) < evade_front_dot_threshold:
		return

	# 敌人在当前方向左边 -> 向右偏；在右边 -> 向左偏。
	# 正前方几乎完全重合时随机选一边，避免所有局面固定往同一侧绕。
	var side_value:float = forward.x * enemy_dir.y - forward.y * enemy_dir.x
	var turn_sign:float
	if absf(side_value) < 0.04:
		turn_sign = -1.0 if randf() < 0.5 else 1.0
	else:
		turn_sign = -1.0 if side_value > 0.0 else 1.0

	direction = forward.rotated(deg_to_rad(evade_turn_degrees) * turn_sign).normalized()
	_evade_cooldown_left = randf_range(
		minf(evade_cooldown_min,evade_cooldown_max),
		maxf(evade_cooldown_min,evade_cooldown_max)
	)


func _has_backstab_angle(target) -> bool:
	if target == null or not is_instance_valid(target) or not (target is ball):
		return false

	var to_target:Vector2 = combat_target_position(target) - global_position
	if to_target.length_squared() <= 0.000001:
		return false
	if direction.length_squared() <= 0.000001 or target.direction.length_squared() <= 0.000001:
		return false

	# 完全按项目原版“背刺鼠”的几何逻辑做宽半区判断：
	# 1) 目标位于背刺者当前朝向的前半区。
	# 2) 目标自己的朝向远离背刺者，也就是把背部留给背刺者。
	# 不再要求 32° / 46° 的极窄夹角，否则自动战斗里合法窗口太少。
	var dir_to_target:Vector2 = to_target.normalized()
	var attacker_forward_dot:float = direction.normalized().dot(dir_to_target)
	var target_forward_dot:float = target.direction.normalized().dot(dir_to_target)
	return (
		attacker_forward_dot > facing_dot_tolerance
		and target_forward_dot > facing_dot_tolerance
	)


func Attack() -> void:
	super()
	if not has_player_control_aim() or not is_multiplayer_authority():
		return
	if state_machine.current_state == State.Die or is_damage_output_disabled():
		Attacking = false
		return
	Attacking = true
	_update_backstab_visual(true)
	continue_attack()
	await get_tree().create_timer(maxf(backstab_trigger_delay + 0.04,0.10)).timeout
	if is_instance_valid(self) and state_machine != null and state_machine.current_state != State.Die:
		Attacking = false
		_update_backstab_visual(false)


func continue_attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return

	var target = return_reusable_combat_target()
	if not has_player_control_aim() and not _has_backstab_angle(target):
		Attacking = false
		return
	if _shot_cooldown_left > 0.0:
		return

	var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(target) - global_position)
	if dir.length_squared() <= 0.000001:
		return
	dir = dir.normalized()

	var knife:ball = KNIFE_SCENE.instantiate()
	knife.Master = self
	knife.Master_name = name
	knife.Team = Team
	knife.Target_Enemy = null if has_player_control_aim() else target
	knife.Damage = Damage
	knife.Speed = projectile_speed
	knife.Hit_Audio = knife_hit_audio
	knife.direction = dir
	knife.global_position = global_position + dir * projectile_spawn_offset
	knife.global_rotation = knife.Default_Rotation + dir.angle()
	knife.name = Game.return_random_name(knife)
	get_tree().current_scene.add_child(knife,true)
	_shot_cooldown_left = shot_cooldown

	if shoot_audio != "":
		Audios.play_sfx.rpc(shoot_audio,{},true,true)


func Die() -> void:
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
