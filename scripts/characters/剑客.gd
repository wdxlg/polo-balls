extends ball
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")

const BLEED_STATUS_SCRIPT:Script = preload("res://scripts/status/剑客_流血.gd")
const BLEED_NODE_NAME:StringName = &"SwordsmanBleedStatus"
const VISUAL_NORMAL:Texture2D = preload("res://Images/characters/剑客/普通.png")
const VISUAL_SLASH:Texture2D = preload("res://Images/characters/剑客/挥剑.png")
const VISUAL_PARRY:Texture2D = preload("res://Images/characters/剑客/招架.png")
const VISUAL_THRUST:Texture2D = preload("res://Images/characters/剑客/突刺.png")
const AUDIO_PARRY_1:AudioStream = preload("res://audio/characters/剑客/格挡1.mp3")
const AUDIO_PARRY_2:AudioStream = preload("res://audio/characters/剑客/格挡2.mp3")
const AUDIO_PARRY_3:AudioStream = preload("res://audio/characters/剑客/格挡3.mp3")
const AUDIO_SWING:AudioStream = preload("res://audio/characters/剑客/剑挥舞.mp3")
const AUDIO_SLASH_HIT:AudioStream = preload("res://audio/characters/剑客/剑伤害.mp3")
const AUDIO_THRUST_DASH_1:AudioStream = preload("res://audio/characters/剑客/刺冲刺.mp3")
const AUDIO_THRUST_DASH_2:AudioStream = preload("res://audio/characters/剑客/刺冲刺2.mp3")
const AUDIO_THRUST_HIT:AudioStream = preload("res://audio/characters/剑客/剑客刺击中.mp3")

@export_category("剑客 - 招架")
@export_range(2.0,12.0,0.1) var parry_interval:float = 5.2
@export_range(0.3,3.0,0.05) var parry_window:float = 1.05
@export_range(0.05,1.0,0.05) var parry_counter_delay:float = 0.26
@export_range(20.0,180.0,1.0) var parry_counter_radius:float = 82.0 # 旧版本兼容，不再用于命中判定
@export_range(40.0,220.0,1.0) var parry_counter_length:float = 108.0
@export_range(20.0,120.0,1.0) var parry_counter_width:float = 58.0
@export_range(0.0,10.0,0.05) var parry_counter_damage_multiplier:float = 1.4583333
@export_range(0.18,0.8,0.01) var slash_visual_hold:float = 0.36
@export_range(0.0,0.30,0.01) var slash_damage_delay:float = 0.08
@export_range(1,5,1) var parry_bleed_stacks:int = 1

@export_category("剑客 - 矩形反击视觉")
# 直接把 PNG 拖到这里即可。这里不再 preload 固定文件，所以旧图片删除/改名不会让脚本失效。
@export var counter_rect_fx_texture:Texture2D
# 也可以只填一个 PNG 路径作为后备，例如：res://Images/characters/剑客/我的反击图.png
@export_file("*.png") var counter_rect_fx_texture_path:String = ""
@export_range(16.0,160.0,1.0) var counter_rect_fx_length:float = 52.0
# 保留旧字段兼容旧场景；新版图片显示不再强制压扁到这个高度。
@export_range(2.0,20.0,1.0) var counter_rect_fx_width:float = 3.0
@export var counter_rect_fx_auto_rotate_long_side:bool = false # 兼容旧场景；新版不再根据宽高自动旋转图片
# 武器 PNG 的原始朝向。当前项目的武器图是竖直、刀尖朝下（+Y），所以默认保持 true。
@export var counter_rect_fx_vertical_points_down:bool = true
@export_range(-180.0,180.0,1.0) var counter_rect_fx_texture_rotation_degrees:float = 0.0
@export_range(35.0,160.0,1.0) var counter_rect_fx_sweep_degrees:float = 82.0
@export_range(0.10,0.60,0.01) var counter_rect_fx_duration:float = 0.22
@export_range(1,8,1) var counter_rect_fx_afterimages:int = 3
@export_range(0.10,1.0,0.01) var counter_rect_fx_alpha:float = 0.82
@export var counter_rect_fx_preserve_texture_color:bool = true
@export var counter_rect_fx_color:Color = Color(0.72,0.90,1.0,1.0)
@export_range(0.55,1.0,0.01) var parry_visual_scale_multiplier:float = 0.78
@export var parry_visual_tint:Color = Color(0.62,0.82,1.0,1.0)

@export_category("剑客 - 闪避反击")
@export_range(1.0,10.0,0.1) var dodge_cooldown:float = 3.6
@export_range(10.0,140.0,1.0) var dodge_distance:float = 56.0
@export_range(0.10,0.6,0.01) var dodge_duration:float = 0.22
@export_range(0.0,0.8,0.01) var riposte_pause:float = 0.10
@export_range(10.0,100.0,1.0) var behind_distance:float = 34.0
@export_range(0.10,0.7,0.01) var thrust_duration:float = 0.20 # 旧版本兼容；现在突刺位移为瞬移
@export_range(0.0,10.0,0.05) var thrust_damage_multiplier:float = 1.5
# Damage（攻击力）就是追击挥剑的基础伤害。
@export_range(0.0,10.0,0.05) var follow_slash_damage_multiplier:float = 1.0
@export_range(18.0,120.0,1.0) var thrust_hitbox_width:float = 46.0
@export_range(20.0,160.0,1.0) var follow_slash_length:float = 92.0
@export_range(18.0,120.0,1.0) var follow_slash_width:float = 54.0
@export_range(0.18,0.8,0.01) var thrust_visual_hold:float = 0.38
@export_range(0.0,0.20,0.01) var thrust_face_windup:float = 0.07
@export_range(-180.0,180.0,1.0) var facing_rotation_offset_degrees:float = 0.0
@export_range(2,10,1) var thrust_afterimage_count:int = 6
@export_range(0.08,0.6,0.01) var thrust_afterimage_fade:float = 0.26
@export_range(0.10,0.8,0.01) var thrust_afterimage_alpha:float = 0.42
@export_range(1,5,1) var thrust_bleed_stacks:int = 2
@export_range(1,5,1) var slash_bleed_stacks:int = 1

@export_category("剑客 - 流血")
@export_range(1,10,1) var bleed_max_stacks:int = 5
@export_range(1.0,15.0,0.5) var bleed_duration:float = 6.0
@export_range(0.0,2.0,0.005) var bleed_action_damage_per_stack_multiplier:float = 0.0416667
@export_range(0.2,2.0,0.05) var bleed_move_tick_interval:float = 0.60
@export_range(0.0,2.0,0.0025) var bleed_move_damage_per_stack_multiplier:float = 0.0125

var _parry_active:bool = false
var _parry_counter_queue:Array[ball] = []
var _parry_counter_worker_running:bool = false
var _parry_cycle_left:float = 2.0
var _parry_time_left:float = 0.0
var _dodge_cooldown_left:float = 0.0
var _response_busy:bool = false
var _response_serial:int = 0
var _rejected_hit_reasons:Dictionary = {}
var _contact_passthrough_uses:int = 0
var _contact_passthrough_serial:int = 0
var _allow_damage_passthrough:bool = false
var _forced_facing_active:bool = false
var _forced_facing_image_rotation:float = 0.0
var _forced_facing_flip_h:bool = false
var _base_graphics_rotation:float = 0.0
var _base_image_rotation:float = 0.0


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	side_status_ui_enabled = false
	super._ready()
	image_color = Color.WHITE
	image_color_mix = 0.0
	set_image_color()
	var graphics:Node2D = get_node_or_null("Graphics") as Node2D
	if graphics != null:
		_base_graphics_rotation = graphics.rotation
	if image is Sprite2D:
		_base_image_rotation = (image as Sprite2D).rotation
	_set_swordsman_visual(VISUAL_NORMAL)
	_parry_cycle_left = randf_range(1.5,2.4)
	_update_defense_status_ui()


func get_preview_texture() -> Texture2D:
	# 放置预览不会执行 _ready()；显式告诉 world.gd 使用角色的正常立绘。
	return VISUAL_NORMAL


func _set_swordsman_visual(texture:Texture2D) -> void:
	if not image is Sprite2D or texture == null:
		return
	var sprite:Sprite2D = image as Sprite2D
	sprite.self_modulate = Color.WHITE
	if sprite.texture != texture:
		sprite.texture = texture
		sprite.offset = Vector2.ZERO
		sprite.visible = true
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		call_deferred("_refit_swordsman_visual_preserving_rotation")
	# AutoFit 会先根据当前贴图重算 scale；随后再叠加招架的缩小/变色，
	# 避免缩放被 AutoFit 立刻覆盖。
	call_deferred("_apply_swordsman_visual_style",texture)


func _refit_swordsman_visual_preserving_rotation() -> void:
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter == null or not fitter.has_method("apply_visual_fit_only"):
		return
	# 跟小丑瞄准一致：突刺只旋转 Image，并在左半区用 flip_h 折回正立角度。
	# AutoFit 会把 Image.rotation 算进可见包围盒，所以拟合前临时回到基础角度，
	# 拟合后再恢复当前突刺朝向，避免斜着时因为包围盒变大而突然缩小。
	var sprite:Sprite2D = image as Sprite2D if image is Sprite2D else null
	var restore_rotation:float = _base_image_rotation
	if sprite != null:
		restore_rotation = sprite.rotation
		if _forced_facing_active:
			sprite.rotation = _base_image_rotation
	fitter.call("apply_visual_fit_only")
	if sprite != null:
		sprite.rotation = _forced_facing_image_rotation if _forced_facing_active else restore_rotation


func _apply_swordsman_visual_style(expected_texture:Texture2D) -> void:
	if not image is Sprite2D or expected_texture == null:
		return
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture != expected_texture:
		return
	sprite.self_modulate = Color.WHITE
	if expected_texture == VISUAL_PARRY and _parry_active:
		sprite.scale *= clampf(parry_visual_scale_multiplier,0.55,1.0)
		sprite.self_modulate = parry_visual_tint


func get_next_state(state:State) -> int:
	# 纯反击角色，永远不会因为基础攻击/技能计时主动出招。
	Can_Attack = false
	Can_Skill = false
	return super.get_next_state(state)


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	# 突刺动作期间锁定“小丑式”正立朝向：右半区直接旋转，左半区折回角度 + flip_h，
	# 因此不会因为目标在左侧而把整个人物旋转到上下颠倒。
	if _forced_facing_active:
		_apply_forced_facing_now()
	if not is_multiplayer_authority() or state_machine == null or state_machine.current_state == State.Die:
		return

	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta,0.0)

	if _parry_active:
		_parry_time_left -= delta
		if _parry_time_left <= 0.0:
			_end_parry()
	else:
		_parry_cycle_left -= delta
		if _parry_cycle_left <= 0.0 and not _response_busy:
			_start_parry()


func Attack() -> void:
	Attacking = false


func Skill() -> void:
	Using_Skill = false


func _start_parry() -> void:
	_parry_active = true
	_parry_time_left = maxf(parry_window,0.1)
	_parry_cycle_left = maxf(parry_interval,0.2)
	_update_defense_status_ui()
	_set_swordsman_visual(VISUAL_PARRY)


func _end_parry() -> void:
	_parry_active = false
	_parry_time_left = 0.0
	_update_defense_status_ui()
	if not _response_busy:
		_set_swordsman_visual(VISUAL_NORMAL)


func _update_defense_status_ui() -> void:
	# 剑客不再用侧边文字说明“招架/闪避/反击”，状态只通过角色动作、
	# 音效以及招架时的缩小 + 变色来表达。保留 remove 仅用于清掉旧状态。
	side_status_remove_permanent("right","swordsman_defense")


# 所有标准 Hitbox（近战、投射物、身体碰撞）都会在真正结算前进入这里。
func can_receive_hit_contact(incoming_hit:hitbox,_contact_hurtbox:hurtbox) -> bool:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return true
	var attacker:ball = _resolve_counter_target_from_hitbox(incoming_hit)
	var source_position:Vector2 = incoming_hit.global_position
	var reason:String = _try_defend(attacker,source_position)
	if not reason.is_empty():
		_rejected_hit_reasons[incoming_hit.get_instance_id()] = reason
		return false

	# hitbox.gd 接受命中后会同步调用一次 take_damage()；只给这一次放行，
	# 防止 take_damage() 的最后兼容防线再次把同一击当成新攻击。
	_grant_contact_passthrough_once()
	return true


func can_receive_hit_from(incoming_hit:hitbox) -> bool:
	return can_receive_hit_contact(incoming_hit,null)


func on_incoming_hit_rejected(incoming_hit:hitbox) -> void:
	var reason:String = ""
	if incoming_hit != null and is_instance_valid(incoming_hit):
		var hit_id:int = incoming_hit.get_instance_id()
		reason = str(_rejected_hit_reasons.get(hit_id,""))
		_rejected_hit_reasons.erase(hit_id)

	if reason == "parry":
		# 每次真正挡下一击时随机一个格挡音；不是进入招架姿态就播放。
		_play_random_parry_audio()
		# 招架：沿用公共格挡爆裂，并让真正的投射物停下/销毁。
		super.on_incoming_hit_rejected(incoming_hit)
	elif reason == "dodge":
		# 闪避：不播放格挡火花，也不销毁子弹；它只是从原位置躲开。
		pass
	else:
		super.on_incoming_hit_rejected(incoming_hit)


func receive_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block:bool = false,
	source:Node = null
) -> bool:
	if damage <= 0.0:
		return false
	var attacker:ball = _resolve_counter_target(source)
	var reason:String = _try_defend(attacker,impact_position)
	if not reason.is_empty():
		_play_special_defense_feedback(reason,impact_position,damage,source)
		return false
	_allow_damage_passthrough = true
	var accepted:bool = super.receive_positional_damage(damage,impact_position,ignore_block,source)
	_allow_damage_passthrough = false
	return accepted


func receive_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block:bool = false,
	raw_health:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	var source:Node = null
	var impact_position:Vector2 = global_position
	if damage_space is Vector2:
		impact_position = damage_space as Vector2
	elif damage_space is Dictionary:
		var context:Dictionary = damage_space as Dictionary
		if context.get("source",null) is Node:
			source = context.get("source",null) as Node
		if context.get("point",null) is Vector2:
			impact_position = context.get("point",global_position) as Vector2
		elif context.get("center",null) is Vector2:
			impact_position = context.get("center",global_position) as Vector2
		elif context.get("origin",null) is Vector2:
			impact_position = context.get("origin",global_position) as Vector2

	var attacker:ball = _resolve_counter_target(source)
	var reason:String = _try_defend(attacker,impact_position)
	if not reason.is_empty():
		_play_special_defense_feedback(reason,impact_position,damage,source)
		return false
	_allow_damage_passthrough = true
	var accepted:bool = super.receive_spatial_damage(damage,damage_space,ignore_block,raw_health)
	_allow_damage_passthrough = false
	return accepted


func take_damage(damage:float,ignore_block:bool = false) -> void:
	if damage <= 0.0:
		return
	if _allow_damage_passthrough:
		super.take_damage(damage,ignore_block)
		return
	if _contact_passthrough_uses > 0:
		_contact_passthrough_uses -= 1
		super.take_damage(damage,ignore_block)
		return

	# 兼容极少数仍直接调用 take_damage() 的旧攻击。没有来源信息时用最近敌人作为反击目标。
	var attacker:ball = _nearest_valid_enemy()
	var reason:String = _try_defend(attacker,attacker.global_position if attacker != null else global_position)
	if not reason.is_empty():
		_play_special_defense_feedback(reason,global_position,damage,null)
		return
	super.take_damage(damage,ignore_block)


func _grant_contact_passthrough_once() -> void:
	_contact_passthrough_uses += 1
	_contact_passthrough_serial += 1
	var serial:int = _contact_passthrough_serial
	call_deferred("_expire_contact_passthrough",serial)


func _expire_contact_passthrough(serial:int) -> void:
	if serial == _contact_passthrough_serial:
		_contact_passthrough_uses = 0


func _try_defend(attacker:ball,source_position:Vector2) -> String:
	# super.receive_spatial_damage() 会再转调 receive_positional_damage()；
	# 已经放行的同一笔伤害不能在这层被二次当成新攻击。
	if _allow_damage_passthrough:
		return ""
	if state_machine == null or state_machine.current_state == State.Die or health <= 0:
		return ""
	if _parry_active and not incoming_damage_bypasses_guard():
		_trigger_parry_counter(attacker)
		return "parry"
	if _dodge_cooldown_left <= 0.0 and not _response_busy:
		_dodge_cooldown_left = maxf(dodge_cooldown,0.1)
		_start_dodge_response(attacker,source_position)
		return "dodge"
	return ""


func _trigger_parry_counter(attacker:ball) -> void:
	# 每一次在招架窗口里真正挡下的攻击都排入反击队列，不再“一次招架只能反击一次”。
	# 队列串行播放，避免短时间多段攻击把人物贴图/音效/判定互相覆盖。
	_parry_counter_queue.append(attacker)
	if not _parry_counter_worker_running:
		_parry_counter_worker_running = true
		_response_busy = true
		call_deferred("_run_parry_counter_queue")


func _run_parry_counter_queue() -> void:
	while not _parry_counter_queue.is_empty():
		if state_machine == null or state_machine.current_state == State.Die or health <= 0:
			break
		var preferred_target:ball = _parry_counter_queue.pop_front()
		await get_tree().create_timer(maxf(parry_counter_delay,0.05),false,true).timeout
		if state_machine == null or state_machine.current_state == State.Die or health <= 0:
			break
		await _execute_parry_counter(preferred_target)

	_parry_counter_queue.clear()
	_parry_counter_worker_running = false
	_response_busy = false
	if is_instance_valid(self) and health > 0:
		_set_swordsman_visual(VISUAL_PARRY if _parry_active else VISUAL_NORMAL)


func _execute_parry_counter(preferred_target:ball) -> void:
	var target:ball = preferred_target
	if target == null or not is_instance_valid(target) or target.health <= 0 or _is_friendly(target):
		target = _nearest_valid_enemy()
	var attack_dir:Vector2 = _safe_attack_direction(target)
	_set_swordsman_visual(VISUAL_SLASH)
	_play_sword_audio(AUDIO_SWING)

	# 招架成功后的反击使用“武器图片本身”做碰撞。武器的 alpha 轮廓会跟随
	# 挥剑旋转，只有剑的非透明区域真正扫到敌人的 Hurtbox 才会造成伤害。
	var hit_count:int = await _perform_weapon_sweep(
		attack_dir,
		attack_damage(parry_counter_damage_multiplier),
		parry_bleed_stacks
	)
	if hit_count > 0:
		_play_sword_audio(AUDIO_SLASH_HIT)

	var remain:float = maxf(slash_visual_hold - maxf(counter_rect_fx_duration,0.10),0.08)
	await get_tree().create_timer(remain,false,true).timeout


func _start_dodge_response(attacker:ball,source_position:Vector2) -> void:
	_response_serial += 1
	var serial:int = _response_serial
	_response_busy = true
	call_deferred("_dodge_and_riposte",serial,attacker,source_position)


func _dodge_and_riposte(serial:int,attacker:ball,source_position:Vector2) -> void:
	if not _response_is_valid(serial):
		_response_busy = false
		return

	var incoming:Vector2 = global_position - source_position
	if incoming.length_squared() <= 0.000001 and attacker != null and is_instance_valid(attacker):
		incoming = global_position - attacker.global_position
	if incoming.length_squared() <= 0.000001:
		incoming = Vector2.RIGHT
	incoming = incoming.normalized()

	var side_a:Vector2 = incoming.rotated(PI * 0.5)
	var side_b:Vector2 = -side_a
	var dodge_dir:Vector2 = side_a if randf() < 0.5 else side_b
	var moved:float = await _move_in_steps(dodge_dir * maxf(dodge_distance,10.0),maxf(dodge_duration,0.1),serial)
	if not _response_is_valid(serial):
		_response_busy = false
		return
	if moved < minf(maxf(dodge_distance,10.0) * 0.25,14.0):
		_response_busy = false
		return

	await get_tree().create_timer(maxf(riposte_pause,0.0),false,true).timeout
	if not _response_is_valid(serial):
		_response_busy = false
		return

	if attacker == null or not is_instance_valid(attacker) or attacker.health <= 0 or _is_friendly(attacker):
		attacker = _nearest_valid_enemy()
	if attacker == null:
		_response_busy = false
		return

	# 目的点只由“剑客当前点 -> 敌人当前点”这条线决定，
	# 不读取敌人的朝向，因此不会因为敌人自己转身而跑到错误的一侧。
	var thrust_start:Vector2 = global_position
	var thrust_dir:Vector2 = attacker.global_position - thrust_start
	if thrust_dir.length_squared() <= 0.000001:
		thrust_dir = Vector2.RIGHT
	thrust_dir = thrust_dir.normalized()
	var thrust_destination:Vector2 = attacker.global_position + thrust_dir * maxf(behind_distance,10.0)

	# 记住动作前的 Image 旋转和镜像。突刺朝向完全复用“小丑瞄准”的做法：
	# 目标在左侧时把角度折回正立半平面，再用 flip_h 表示朝左，避免人物上下颠倒。
	var restore_image_rotation:float = (image as Sprite2D).rotation if image is Sprite2D else _base_image_rotation
	var restore_flip_h:bool = is_character_visual_flipped_h()
	_set_swordsman_visual(VISUAL_THRUST)
	_force_facing_direction(thrust_dir)
	_play_random_thrust_dash_audio()

	# 给真正的旋转至少留一个很短的可见窗口；位移仍然是随后同一帧瞬移。
	if thrust_face_windup > 0.0:
		await get_tree().create_timer(thrust_face_windup,false,true).timeout
	if not _response_is_valid(serial):
		_release_forced_facing(restore_flip_h,restore_image_rotation)
		_response_busy = false
		return

	# 瞬移本身不做逐帧位移；残影沿整条轨迹一次性铺开，再快速淡出。
	_spawn_thrust_afterimages(thrust_start,thrust_destination)
	global_position = thrust_destination
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO

	# 突刺判定就是从出发点到“敌人后方落点”的长条矩形。
	var thrust_hits:int = _deal_oriented_rect_counter(
		thrust_start,
		thrust_destination,
		thrust_hitbox_width,
		attack_damage(thrust_damage_multiplier),
		thrust_bleed_stacks
	)
	if thrust_hits > 0:
		_play_sword_audio(AUDIO_THRUST_HIT)

	# 突刺图片维持一会，不再瞬间切成挥剑。
	await get_tree().create_timer(maxf(thrust_visual_hold,0.18),false,true).timeout
	if not _response_is_valid(serial):
		_release_forced_facing(restore_flip_h,restore_image_rotation)
		_response_busy = false
		return

	# 落点后的追击挥剑也使用同一把武器的透明度轮廓碰撞。
	var follow_dir:Vector2 = _safe_attack_direction(attacker)
	_force_facing_direction(follow_dir)
	_set_swordsman_visual(VISUAL_SLASH)
	_play_sword_audio(AUDIO_SWING)
	var slash_hits:int = await _perform_weapon_sweep(
		follow_dir,
		attack_damage(follow_slash_damage_multiplier),
		slash_bleed_stacks
	)
	if slash_hits > 0:
		_play_sword_audio(AUDIO_SLASH_HIT)
	if not _response_is_valid(serial):
		_release_forced_facing(restore_flip_h,restore_image_rotation)
		_response_busy = false
		return

	await get_tree().create_timer(maxf(slash_visual_hold - maxf(counter_rect_fx_duration,0.10),0.08),false,true).timeout

	_release_forced_facing(restore_flip_h,restore_image_rotation)
	_response_busy = false
	_set_swordsman_visual(VISUAL_PARRY if _parry_active else VISUAL_NORMAL)


func _move_in_steps(motion:Vector2,duration:float,serial:int) -> float:
	var start:Vector2 = global_position
	var steps:int = maxi(int(ceil(duration / 0.045)),3)
	var per_step:Vector2 = motion / float(steps)
	for _i:int in range(steps):
		if not _response_is_valid(serial):
			break
		var collision:KinematicCollision2D = move_and_collide(per_step)
		if collision != null:
			break
		await get_tree().physics_frame
	return start.distance_to(global_position)


func _move_toward_point_in_steps(destination:Vector2,duration:float,serial:int) -> void:
	var steps:int = maxi(int(ceil(duration / 0.045)),3)
	for i:int in range(steps):
		if not _response_is_valid(serial):
			return
		var remain_steps:int = maxi(steps - i,1)
		var motion:Vector2 = (destination - global_position) / float(remain_steps)
		if motion.length_squared() <= 0.000001:
			return
		var collision:KinematicCollision2D = move_and_collide(motion)
		if collision != null:
			return
		await get_tree().physics_frame


func _safe_attack_direction(target:ball) -> Vector2:
	var aim:Vector2 = Vector2.ZERO
	if target != null and is_instance_valid(target):
		aim = target.global_position - global_position
	if aim.length_squared() <= 0.000001:
		aim = direction
	if aim.length_squared() <= 0.000001:
		aim = Vector2.RIGHT
	return aim.normalized()


func _force_facing_direction(world_dir:Vector2) -> void:
	var safe_dir:Vector2 = world_dir
	if safe_dir.length_squared() <= 0.000001:
		safe_dir = Vector2.RIGHT
	safe_dir = safe_dir.normalized()

	# 与小丑 _apply_weapon_aim_visual() 相同的“正立半平面”规则：
	# 右侧目标：直接显示目标角度；左侧目标：角度 + PI 折回 -90°..90°，同时水平镜像。
	# 例如目标方向 160° -> 人物只显示 -20°，再 flip_h=true，而不会整个人倒过来。
	var facing_left:bool = safe_dir.x < 0.0
	var display_angle:float = safe_dir.angle()
	if facing_left:
		display_angle = wrapf(display_angle + PI,-PI,PI)

	_forced_facing_image_rotation = (
		_base_image_rotation
		+ display_angle
		+ deg_to_rad(facing_rotation_offset_degrees)
	)
	_forced_facing_flip_h = facing_left
	_forced_facing_active = true
	_apply_forced_facing_now()


func _apply_forced_facing_now() -> void:
	if not _forced_facing_active:
		return
	if image is Sprite2D:
		(image as Sprite2D).rotation = _forced_facing_image_rotation
	set_character_visual_flip_h(_forced_facing_flip_h)


func _release_forced_facing(restore_flip_h:bool,restore_rotation:float) -> void:
	_forced_facing_active = false
	if image is Sprite2D:
		(image as Sprite2D).rotation = restore_rotation
	set_character_visual_flip_h(restore_flip_h)


func _get_counter_rect_texture() -> Texture2D:
	# 1) 优先使用 Inspector 里直接拖入的 Texture2D。
	if counter_rect_fx_texture != null:
		return counter_rect_fx_texture

	# 2) 其次使用可选路径。这里使用运行时 load，不会因为旧文件被删除而让整个脚本 preload 失败。
	var p:String = counter_rect_fx_texture_path.strip_edges()
	if not p.is_empty() and ResourceLoader.exists(p):
		var res:Resource = load(p)
		if res is Texture2D:
			return res as Texture2D

	return null


func _weapon_pivot_rotation_for_world_angle(world_angle:float) -> float:
	# 当前武器 PNG 原始方向是“竖直向下”：纹理的 +Y 才是刀尖方向。
	# Godot 世界角度 0 指向 +X，因此需要把整把武器的旋转轴先减去 90°，
	# 才能让图片中的 +Y 对准传入的攻击方向。
	if counter_rect_fx_vertical_points_down:
		return world_angle - PI * 0.5
	return world_angle


func _make_counter_fx_pivot(parent:Node,texture:Texture2D,angle:float,alpha:float,node_name:String) -> Node2D:
	var pivot := Node2D.new()
	pivot.name = node_name
	pivot.z_as_relative = false
	pivot.z_index = 100
	parent.add_child(pivot)
	pivot.global_position = global_position
	pivot.global_rotation = _weapon_pivot_rotation_for_world_angle(angle)

	var sprite := Sprite2D.new()
	sprite.name = "Image"
	sprite.texture = texture
	sprite.centered = true
	sprite.visible = true
	sprite.z_as_relative = false
	sprite.z_index = 100
	pivot.add_child(sprite)

	# 武器资源是竖直、刀尖朝下，所以用纹理高度作为“武器长度”来统一缩放。
	# 若以后换成横向资源，把 counter_rect_fx_vertical_points_down 关闭即可。
	var tex_size:Vector2 = texture.get_size()
	var source_length:float = maxf(tex_size.y if counter_rect_fx_vertical_points_down else tex_size.x,1.0)
	var target_length:float = maxf(counter_rect_fx_length,1.0)
	var uniform_scale:float = target_length / source_length
	sprite.scale = Vector2.ONE * uniform_scale

	# 可选的素材自身微调角度。视觉与 CollisionPolygon2D 会读取同一个 rotation/scale/position。
	var local_correction:float = deg_to_rad(counter_rect_fx_texture_rotation_degrees)
	sprite.rotation = local_correction

	# Sprite2D centered=true 时，旋转轴默认在图片中心。这里把图片沿“刀尖方向”
	# 推开半个显示长度，使图片顶部（手柄端）落在剑客位置附近，挥剑围绕手柄转。
	var source_axis:Vector2 = Vector2.DOWN if counter_rect_fx_vertical_points_down else Vector2.RIGHT
	sprite.position = source_axis.rotated(local_correction) * (target_length * 0.5)

	var c:Color = Color.WHITE if counter_rect_fx_preserve_texture_color else counter_rect_fx_color
	c.a *= clampf(alpha,0.0,1.0)
	sprite.modulate = c

	return pivot


func _counter_fx_sprite_from_pivot(pivot:Node2D) -> Sprite2D:
	var n:Node = pivot.get_node_or_null("Image")
	return n as Sprite2D if n is Sprite2D else null


func _play_counter_rect_sweep(world_dir:Vector2) -> void:
	if not is_inside_tree():
		return
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var texture:Texture2D = _get_counter_rect_texture()
	if texture == null:
		push_warning("剑客反击特效没有图片：请在 Inspector 的 Counter Rect Fx Texture 拖入 PNG，或填写 Counter Rect Fx Texture Path。")
		return

	var safe_dir:Vector2 = world_dir
	if safe_dir.length_squared() <= 0.000001:
		safe_dir = Vector2.RIGHT
	var center_angle:float = safe_dir.angle()
	var sweep:float = deg_to_rad(clampf(counter_rect_fx_sweep_degrees,35.0,160.0))
	var start_angle:float = center_angle - sweep * 0.55
	var end_angle:float = center_angle + sweep * 0.45
	var base_alpha:float = clampf(counter_rect_fx_alpha,0.1,1.0)

	var sweep_pivot:Node2D = _make_counter_fx_pivot(parent,texture,start_angle,base_alpha,"SwordsmanCounterImageSweep")
	var sweep_sprite:Sprite2D = _counter_fx_sprite_from_pivot(sweep_pivot)
	if sweep_sprite == null:
		sweep_pivot.queue_free()
		return

	var tween := get_tree().create_tween().bind_node(sweep_pivot).set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sweep_pivot,"global_rotation",_weapon_pivot_rotation_for_world_angle(end_angle),maxf(counter_rect_fx_duration,0.10))
	var fade_color:Color = sweep_sprite.modulate
	fade_color.a = 0.0
	tween.tween_property(sweep_sprite,"modulate",fade_color,maxf(counter_rect_fx_duration,0.10))
	tween.chain().tween_callback(sweep_pivot.queue_free)

	# 图片残影同样保持原图比例。
	var ghost_count:int = clampi(counter_rect_fx_afterimages,1,8)
	for i:int in range(ghost_count):
		var t:float = float(i) / float(maxi(ghost_count - 1,1))
		var ghost_alpha:float = base_alpha * 0.42 * (1.0 - t * 0.45)
		var ghost_pivot:Node2D = _make_counter_fx_pivot(parent,texture,lerp_angle(start_angle,end_angle,t),ghost_alpha,"SwordsmanCounterImageAfterimage")
		var ghost_sprite:Sprite2D = _counter_fx_sprite_from_pivot(ghost_pivot)
		if ghost_sprite == null:
			ghost_pivot.queue_free()
			continue
		var ghost_fade:Color = ghost_sprite.modulate
		ghost_fade.a = 0.0
		var ghost_tween := get_tree().create_tween().bind_node(ghost_pivot)
		ghost_tween.tween_property(ghost_sprite,"modulate",ghost_fade,maxf(counter_rect_fx_duration * 0.85,0.08))
		ghost_tween.tween_callback(ghost_pivot.queue_free)


func _build_weapon_collision(area:Area2D,sprite:Sprite2D,texture:Texture2D) -> bool:
	if area == null or sprite == null or texture == null:
		return false
	var source_image:Image = texture.get_image()
	if source_image == null or source_image.is_empty():
		return false

	# 从武器 PNG 的 alpha 通道直接提取轮廓，透明部分没有碰撞。
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(source_image,0.10)
	var image_rect := Rect2i(Vector2i.ZERO,source_image.get_size())
	var polygons:Array[PackedVector2Array] = bitmap.opaque_to_polygons(image_rect,1.5)
	if polygons.is_empty():
		return false

	var tex_size:Vector2 = texture.get_size()
	var image_center:Vector2 = tex_size * 0.5
	var added:int = 0
	for source_polygon:PackedVector2Array in polygons:
		if source_polygon.size() < 3:
			continue
		var local_polygon := PackedVector2Array()
		for point:Vector2 in source_polygon:
			local_polygon.append(point - image_center)
		var collision := CollisionPolygon2D.new()
		collision.polygon = local_polygon
		collision.position = sprite.position
		collision.rotation = sprite.rotation
		collision.scale = sprite.scale
		area.add_child(collision)
		added += 1
	return added > 0


func _damage_targets_overlapping_weapon(area:Area2D,damage:float,bleed_stacks:int,already_hit:Dictionary) -> int:
	if area == null or not is_instance_valid(area) or damage <= 0.0:
		return 0
	var new_hits:int = 0
	for collider:Area2D in area.get_overlapping_areas():
		if not collider is hurtbox:
			continue
		var hurt:hurtbox = collider as hurtbox
		var parent_node:Node = hurt.get_parent()
		if not parent_node is ball:
			continue
		var target:ball = parent_node as ball
		if target == self or not target.is_combat_targetable() or _is_friendly(target):
			continue
		var target_id:int = target.get_instance_id()
		if already_hit.has(target_id):
			continue
		already_hit[target_id] = true

		var accepted:bool = target.receive_spatial_damage(
			damage,
			{
				"shape":"weapon_polygon",
				"point":target.global_position,
				"source":self
			},
			false,
			false
		)
		if accepted:
			_force_target_hit_flash(target)
			_apply_bleed(target,bleed_stacks)
			new_hits += 1
	return new_hits


func _perform_weapon_sweep(world_dir:Vector2,damage:float,bleed_stacks:int) -> int:
	if not is_inside_tree() or damage <= 0.0:
		return 0
	var parent:Node = get_tree().current_scene
	var texture:Texture2D = _get_counter_rect_texture()
	if parent == null or texture == null:
		push_warning("剑客反击武器没有图片：请在 Counter Rect Fx Texture 指定武器 PNG。")
		return 0

	var safe_dir:Vector2 = world_dir.normalized() if world_dir.length_squared() > 0.000001 else Vector2.RIGHT
	var center_angle:float = safe_dir.angle()
	var sweep:float = deg_to_rad(clampf(counter_rect_fx_sweep_degrees,35.0,160.0))
	var start_angle:float = center_angle - sweep * 0.55
	var end_angle:float = center_angle + sweep * 0.45
	var base_alpha:float = clampf(counter_rect_fx_alpha,0.1,1.0)

	var pivot:Node2D = _make_counter_fx_pivot(parent,texture,start_angle,base_alpha,"SwordsmanWeaponSweep")
	var sprite:Sprite2D = _counter_fx_sprite_from_pivot(pivot)
	if sprite == null:
		pivot.queue_free()
		return 0

	var weapon_area := Area2D.new()
	weapon_area.name = "WeaponHitArea"
	weapon_area.collision_layer = 0
	weapon_area.collision_mask = 2
	weapon_area.monitoring = true
	weapon_area.monitorable = false
	pivot.add_child(weapon_area)
	if not _build_weapon_collision(weapon_area,sprite,texture):
		pivot.queue_free()
		push_warning("剑客武器 PNG 无法生成 alpha 碰撞轮廓。")
		return 0

	# 等一个物理帧让 Area2D 注册，然后逐帧旋转并检查重叠。
	await get_tree().physics_frame
	var already_hit:Dictionary = {}
	var hit_count:int = 0
	var duration:float = maxf(counter_rect_fx_duration,0.10)
	var elapsed:float = 0.0
	while elapsed < duration and is_instance_valid(pivot):
		var t:float = clampf(elapsed / duration,0.0,1.0)
		var eased:float = 1.0 - pow(1.0 - t,2.0)
		pivot.global_position = global_position
		pivot.global_rotation = _weapon_pivot_rotation_for_world_angle(lerp_angle(start_angle,end_angle,eased))
		hit_count += _damage_targets_overlapping_weapon(weapon_area,damage,bleed_stacks,already_hit)
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

	if is_instance_valid(pivot):
		pivot.global_position = global_position
		pivot.global_rotation = _weapon_pivot_rotation_for_world_angle(end_angle)
		hit_count += _damage_targets_overlapping_weapon(weapon_area,damage,bleed_stacks,already_hit)
		pivot.queue_free()
	return hit_count


func _spawn_thrust_afterimages(start:Vector2,end:Vector2) -> void:
	if not allows_character_motion_effects(): return
	if not image is Sprite2D or not is_inside_tree():
		return
	var sprite:Sprite2D = image as Sprite2D
	var parent:Node = get_tree().current_scene
	if parent == null:
		return

	var count:int = clampi(thrust_afterimage_count,2,10)
	for i:int in range(count):
		# 不把最后一个残影放在落点正中心，避免与本体完全重合。
		var t:float = float(i) / float(count)
		var ghost := sprite.duplicate() as Sprite2D
		if ghost == null:
			continue
		ghost.name = "SwordsmanThrustAfterimage"
		parent.add_child(ghost)
		var ghost_transform:Transform2D = sprite.global_transform
		ghost_transform.origin = start.lerp(end,t)
		ghost.global_transform = ghost_transform
		ghost.z_index = sprite.z_index - 1
		var alpha:float = clampf(thrust_afterimage_alpha,0.1,0.8) * (1.0 - t * 0.45)
		ghost.modulate = Color(1.0,1.0,1.0,alpha)
		var tween := get_tree().create_tween().bind_node(ghost)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ghost,"modulate",Color(1.0,1.0,1.0,0.0),maxf(thrust_afterimage_fade,0.08))
		tween.tween_callback(ghost.queue_free)


func _deal_oriented_rect_counter(
	start:Vector2,
	end:Vector2,
	width:float,
	damage:float,
	bleed_stacks:int
) -> int:
	var segment:Vector2 = end - start
	var length:float = segment.length()
	if length <= 0.001 or damage <= 0.0:
		return 0

	var shape := RectangleShape2D.new()
	shape.size = Vector2(length,maxf(width,1.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(segment.angle(),(start + end) * 0.5)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	# ball.tscn 的 Hurtbox 在 collision layer 2；Hitbox 自己是 layer 0。
	query.collision_mask = 2

	var results:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,64)
	var already_hit:Dictionary = {}
	var hit_count:int = 0
	for result:Dictionary in results:
		var collider:Variant = result.get("collider",null)
		if not collider is hurtbox:
			continue
		var hurt:hurtbox = collider as hurtbox
		var parent_node:Node = hurt.get_parent()
		if not parent_node is ball:
			continue
		var target:ball = parent_node as ball
		if target == self or not target.is_combat_targetable() or _is_friendly(target):
			continue
		var target_id:int = target.get_instance_id()
		if already_hit.has(target_id):
			continue
		already_hit[target_id] = true

		var accepted:bool = target.receive_spatial_damage(
			damage,
			{
				"shape":"rect",
				"position":(start + end) * 0.5,
				"half_extents":Vector2(length * 0.5,maxf(width,1.0) * 0.5),
				"rotation":segment.angle(),
				"point":target.global_position,
				"source":self
			},
			false,
			false
		)
		if accepted:
			# receive_spatial_damage() 通常会自己触发闪白；这里额外补一次纯视觉闪白，
			# 兼容某些角色覆写空间伤害入口后只扣血、但没有明显受击白闪的情况。
			_force_target_hit_flash(target)
			hit_count += 1
			_apply_bleed(target,bleed_stacks)
	return hit_count


func _deal_circle_counter(
	center:Vector2,
	radius:float,
	damage:float,
	bleed_stacks:int,
	preferred_target:ball = null
) -> int:
	var hit_count:int = 0
	var radius_safe:float = maxf(radius,1.0)
	var radius_sq:float = radius_safe * radius_safe
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == self or target.health <= 0 or _is_friendly(target):
			continue
		if not target.is_combat_targetable():
			continue
		if preferred_target != null and target != preferred_target:
			continue
		if target.global_position.distance_squared_to(center) > radius_sq:
			continue

		var accepted:bool = target.receive_spatial_damage(
			damage,
			{
				"shape":"circle",
				"center":center,
				"radius":radius_safe,
				"point":target.global_position,
				"source":self
			},
			false,
			false
		)
		if accepted:
			_force_target_hit_flash(target)
			hit_count += 1
			_apply_bleed(target,bleed_stacks)
	return hit_count


func _force_target_hit_flash(target:ball) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	# 使用 ball.gd 的公共纯视觉闪白，不强制切换 Hurt 状态，也不额外造成伤害。
	target.hit_white_visual_only()


func _apply_bleed(target:ball,added_stacks:int) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0 or target.Type != Ball_Type.Ball:
		return
	var existing:Node = target.get_node_or_null(NodePath(str(BLEED_NODE_NAME)))
	if existing != null and is_instance_valid(existing) and existing.has_method("add_stacks"):
		existing.call("add_stacks",added_stacks,self)
		return

	var status:Node = BLEED_STATUS_SCRIPT.new()
	status.name = BLEED_NODE_NAME
	target.add_child(status)
	status.call(
		"setup",
		target,
		self,
		added_stacks,
		bleed_max_stacks,
		bleed_duration,
		attack_damage(bleed_action_damage_per_stack_multiplier),
		bleed_move_tick_interval,
		attack_damage(bleed_move_damage_per_stack_multiplier)
	)


func _play_special_defense_feedback(reason:String,impact_position:Vector2,damage:float,source:Node) -> void:
	if reason == "parry":
		_play_random_parry_audio()
		notify_block_burst_feedback(impact_position,damage,24.0,Game.battle_rng_seed_or("scripts/characters/剑客.gd:parry_seed",int(Time.get_ticks_usec()) ^ get_instance_id()))
		# 自定义位置伤害若明确把投射物本体作为 source，也让它按公共格挡规则停下。
		if PROJECTILE_API.is_projectile(source):
			PROJECTILE_API.retire(source,self,impact_position)
	else:
		# 闪避反馈只保留位移本身，不再显示文字提示。
		pass


func _play_random_parry_audio() -> void:
	var choices:Array[AudioStream] = [AUDIO_PARRY_1,AUDIO_PARRY_2,AUDIO_PARRY_3]
	_play_sword_audio(choices[randi() % choices.size()])


func _play_random_thrust_dash_audio() -> void:
	var choices:Array[AudioStream] = [AUDIO_THRUST_DASH_1,AUDIO_THRUST_DASH_2]
	_play_sword_audio(choices[randi() % choices.size()])


func _play_sword_audio(stream:AudioStream,volume_db:float = 0.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 1000.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	# 音频自然播放结束时直接释放播放器。不要用计时器 Lambda 捕获 player，
	# 否则播放器若提前被释放，Godot 会报告 “Lambda capture ... was freed”。
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()


func _resolve_counter_target_from_hitbox(incoming_hit:hitbox) -> ball:
	if incoming_hit == null:
		return null
	var node:Node = incoming_hit.get_parent()
	if node is ball:
		return _normalize_counter_target(node as ball)
	if incoming_hit.owner is ball:
		return _normalize_counter_target(incoming_hit.owner as ball)
	return _nearest_valid_enemy()


func _resolve_counter_target(source:Node) -> ball:
	if source is hitbox:
		return _resolve_counter_target_from_hitbox(source as hitbox)
	if source is ball:
		return _normalize_counter_target(source as ball)
	if source != null and source.get_parent() is ball:
		return _normalize_counter_target(source.get_parent() as ball)
	return _nearest_valid_enemy()


func _normalize_counter_target(candidate:ball) -> ball:
	if candidate == null or not is_instance_valid(candidate):
		return null
	# 投射物、召唤物、墙等优先反击其真正主人；这样闪避一颗子弹后会追射手，
	# 闪过召唤物/墙的特殊伤害也不会跑去对一个静态 Creature 做突刺。
	if candidate.Type != Ball_Type.Ball and candidate.Master != null and is_instance_valid(candidate.Master):
		candidate = candidate.Master
	if candidate == self or candidate.health <= 0 or _is_friendly(candidate):
		return _nearest_valid_enemy()
	return candidate


func _nearest_valid_enemy() -> ball:
	var nearest:ball = null
	var best:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if candidate == self or candidate.Type != Ball_Type.Ball or candidate.health <= 0 or _is_friendly(candidate):
			continue
		var d:float = global_position.distance_squared_to(candidate.global_position)
		if d < best:
			best = d
			nearest = candidate
	return nearest


func _is_friendly(target:ball) -> bool:
	if target == null:
		return true
	if Team.is_empty() or target.Team.is_empty():
		return false
	if Team != target.Team:
		return false
	return true


func _response_is_valid(serial:int) -> bool:
	return (
		is_instance_valid(self)
		and serial == _response_serial
		and health > 0
		and state_machine != null
		and state_machine.current_state != State.Die
	)


func Die() -> void:
	_response_serial += 1
	_response_busy = false
	_parry_active = false
	_forced_facing_active = false
	_parry_counter_queue.clear()
	_parry_counter_worker_running = false
	var graphics:Node2D = get_node_or_null("Graphics") as Node2D
	if graphics != null:
		graphics.rotation = _base_graphics_rotation
	if image is Sprite2D:
		(image as Sprite2D).rotation = _base_image_rotation
	if image != null and is_instance_valid(image):
		image.set_instance_shader_parameter("power",0.0)
		if image is CanvasItem:
			(image as CanvasItem).self_modulate = Color.WHITE
	super()
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(self):
		Game.free_node(self)
