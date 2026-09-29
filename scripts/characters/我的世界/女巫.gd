extends ball
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")

const NATIVE_MODEL_ANIMATION = preload("res://scripts/effects/我的世界/mc_native_batch2.gd")
var _native_mob_animation:Node

const POTION_SCRIPT = preload("res://scripts/effects/我的世界/女巫药水.gd")
const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")

const HURT_SFX = [
	preload("res://audio/characters/女巫/女巫受伤1.ogg"),
	preload("res://audio/characters/女巫/女巫受伤2.ogg"),
]
const DEATH_SFX = preload("res://audio/characters/女巫/女巫死亡.ogg")
const LAUGH_SFX = preload("res://audio/characters/女巫/女巫笑.ogg")
const WITCH_DRINK_SFX = [
	preload("res://audio/characters/女巫/女巫喝药1.ogg"),
	preload("res://audio/characters/女巫/女巫喝药2.ogg"),
]
const THROW_SFX = preload("res://audio/characters/女巫/药水扔出.ogg")
const DRINK_SFX = preload("res://audio/characters/女巫/药水饮用.ogg")

const DRINK_REPEAT_COUNT:int = 3
const DRINK_REPEAT_GAP_MIN_RATIO:float = 0.52
const DRINK_REPEAT_GAP_MAX_RATIO:float = 0.64
const HEALING_POTION_HEALTH_THRESHOLD:float = 300.0
const POTION_TARGET_MODE_NORMAL:int = 0
const POTION_TARGET_MODE_MIXED_INVERSION:int = 1
const POTION_TARGET_MODE_ALL_INVERTED:int = 2

@export_category("女巫 / 炼药")
@export_range(0.5,20.0,0.1) var brew_interval:float = 2.0
@export_range(0.1,3.0,0.05) var brewing_duration:float = 0.85
@export_range(0.0,1.0,0.01) var mistake_chance:float = 0.20
@export_range(0.0,120.0,1.0) var throw_start_offset_x:float = 38.0
@export_range(-120.0,60.0,1.0) var throw_start_offset_y:float = -16.0
@export_range(0.1,1.5,0.05) var brewed_hold_duration:float = 0.45
@export_range(0.2,1.8,0.05) var drink_animation_duration:float = 0.78
@export_range(0.0,1.0,0.01) var witch_drink_voice_chance:float = 0.45
@export_range(0.0,80.0,1.0) var drink_mouth_offset_x:float = 18.0
@export_range(-120.0,20.0,1.0) var drink_mouth_offset_y:float = -48.0
@export_range(2.0,24.0,0.5) var drink_bob_distance:float = 8.0

var _brew_left:float = 0.0
var _brewing_left:float = 0.0
var _brewing:bool = false
var _pending_effect:String = ""
var _brew_anchor:Node2D = null
var _brew_visual:Node2D = null
var _brew_sprite:Sprite2D = null
var _decision_pending:bool = false
var _decision_left:float = 0.0
var _pending_should_drink:bool = false
var _pending_target_inversion_mode:int = POTION_TARGET_MODE_NORMAL
var _action_busy:bool = false
var _brew_facing:float = 1.0

var _last_health_for_audio:float = -1.0
var _hurt_audio_cooldown:float = 0.0
var _death_audio_played:bool = false


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	side_status_ui_enabled = false

	# V109：女巫场景自身仍可能保存旧的 500 HP，而且 ball.default_properties / health
	# 都是 @onready，在子类 _ready() 前就已经按场景值初始化。只改 Max_health 会被
	# World 的默认属性恢复重新压回旧值，health 也会继续停在旧上限。
	# 因此这里同时改“上限、默认属性缓存、当前生命”，并禁止初始化时冒出 +100 回血跳字。
	Max_health = 600
	default_properties["Max_health"] = 600
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.suppress_floating_text = true
	health = Max_health
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.suppress_floating_text = false

	super._ready()
	_native_mob_animation = NATIVE_MODEL_ANIMATION.attach(self,"witch")
	_last_health_for_audio = float(health)
	_setup_brew_visual()
	_schedule_next_brew()


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	_update_brew_anchor_facing()
	_update_hurt_audio(delta)
	if not is_multiplayer_authority():
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	if not is_combat_runtime_active():
		return

	if _action_busy:
		return

	if _decision_pending:
		_update_ready_potion_visual()
		if not is_player_controlled():
			_decision_left -= delta
			if _decision_left <= 0.0: _execute_brew_decision()
		return

	if _brewing:
		_brewing_left -= delta
		_update_brew_visual_animation()
		if _brewing_left <= 0.0:
			_finish_brew()
		return

	_brew_left -= delta
	if not is_player_controlled() and _brew_left <= 0.0:
		_begin_brew()

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active() or _action_busy or _brewing: return
	if not _decision_pending:
		if _brew_left<=0.0: _begin_brew()
		return
	if _find_nearest_enemy_for_potion()==null: return
	var effect:String=_pending_effect
	_pending_effect=""
	_decision_pending=false
	_throw_potion(effect)
func controlled_skill_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active() or _action_busy or _brewing: return
	if not _decision_pending:
		if _brew_left<=0.0: _begin_brew()
		return
	var effect:String=_pending_effect
	_pending_effect=""
	_decision_pending=false
	_drink_potion(effect)


func _update_hurt_audio(delta:float) -> void:
	_hurt_audio_cooldown = maxf(_hurt_audio_cooldown - delta,0.0)
	var current_health:float = float(health)
	if _last_health_for_audio < 0.0:
		_last_health_for_audio = current_health
		return
	if current_health < _last_health_for_audio - 0.01 and current_health > 0.0 and _hurt_audio_cooldown <= 0.0:
		_play_world_sfx(HURT_SFX.pick_random(),0.5,randf_range(0.97,1.04))
		_hurt_audio_cooldown = 0.18
	_last_health_for_audio = current_health


func _begin_brew() -> void:
	if _brewing:
		return
	_pending_target_inversion_mode = _current_potion_target_inversion_mode()
	var available_effects:Array[String] = []
	for candidate_effect in POTION_EFFECTS.ALL:
		var effect_name:String = String(candidate_effect)
		var is_healing_effect:bool = POTION_EFFECTS.is_healing_family(effect_name)
		# 原规则：女巫高于 300 HP 时不炼治疗/恢复。
		# 只有“场上所有敌人都开启反转”时才解除这条门槛，因为这时治疗/恢复已经稳定是进攻药水。
		# 混合阵容按用户要求只修改治疗/恢复的投掷比例，不额外修改它们的出现门槛。
		if (
			is_healing_effect
			and _pending_target_inversion_mode != POTION_TARGET_MODE_ALL_INVERTED
			and float(health) >= HEALING_POTION_HEALTH_THRESHOLD
		):
			continue
		available_effects.append(effect_name)
	if available_effects.is_empty():
		_schedule_next_brew()
		return
	_pending_effect = available_effects.pick_random()
	_brew_facing = _current_visual_facing_sign()
	_update_brew_anchor_facing()
	_brewing = true
	_brewing_left = maxf(brewing_duration,0.1)
	_show_brew_visual(_pending_effect)


func _finish_brew() -> void:
	if not _brewing:
		return
	_brewing = false
	var effect:String = _pending_effect
	if effect.is_empty():
		_hide_brew_visual()
		_schedule_next_brew()
		return

	# 投掷概率随敌方“治疗/伤害反转”构成调整：
	# - 无反转：完全保持旧规则；
	# - 混合：只把治疗/恢复改成和中毒/瞬伤一样的高投掷倾向；
	# - 全反转：治疗/恢复保持高投掷，同时中毒/瞬伤反过来按旧治疗的低投掷倾向。
	var good:bool = _potion_counts_as_self_use(effect,_pending_target_inversion_mode)
	var reverse:bool = randf() < clampf(mistake_chance,0.0,1.0)
	_pending_should_drink = good
	if reverse:
		_pending_should_drink = not _pending_should_drink

	# 药水炼成后先完整停在女巫前方，让玩家看清成品，再决定喝掉或扔出。
	_decision_pending = true
	_decision_left = maxf(brewed_hold_duration,0.1)
	_place_brew_visual_in_front()
	if _brew_visual != null:
		_brew_visual.rotation = 0.0
		_brew_visual.scale = Vector2.ONE

	# 女巫笑声作为炼制完成的角色反馈；误判时必笑，正常时偶尔笑。
	if reverse or randf() < 0.35:
		_play_world_sfx(LAUGH_SFX,-0.5,randf_range(0.97,1.03))


func _execute_brew_decision() -> void:
	if not _decision_pending:
		return
	_decision_pending = false
	var effect:String = _pending_effect
	_pending_effect = ""
	if effect.is_empty():
		_hide_brew_visual()
		_schedule_next_brew()
		return
	if _pending_should_drink:
		_drink_potion(effect)
	else:
		_throw_potion(effect)


func _drink_potion(effect:String) -> void:
	_action_busy = true
	_start_drink_audio_feedback()
	if _brew_visual == null or not is_instance_valid(_brew_visual):
		_finish_drink_effect(effect)
		return

	# V392：喝药只把手里的同一瓶药水抬到嘴边，然后做三次很小的上下点动。
	# 不再缩小药瓶，也不再把人物 Image 一起倾斜，避免看起来像整个人在喝。
	_brew_visual.visible = true
	_update_brew_anchor_facing()
	var hand_scale:Vector2 = _brew_visual.scale
	var mouth:Vector2 = Vector2(absf(drink_mouth_offset_x),drink_mouth_offset_y)
	var total_duration:float = maxf(drink_animation_duration,0.24)
	var approach_duration:float = total_duration * 0.28
	var bob_leg_duration:float = total_duration * 0.09
	var settle_duration:float = maxf(total_duration - approach_duration - bob_leg_duration * 6.0,0.04)
	var tween:Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_brew_visual,"position",mouth,approach_duration)
	tween.parallel().tween_property(_brew_visual,"rotation",0.22,approach_duration)
	tween.parallel().tween_property(_brew_visual,"scale",hand_scale,approach_duration)

	for i:int in range(DRINK_REPEAT_COUNT):
		var up:Vector2 = mouth + Vector2(0.0,-drink_bob_distance)
		var down:Vector2 = mouth + Vector2(0.0,drink_bob_distance * 0.35)
		tween.tween_property(_brew_visual,"position",up,bob_leg_duration)
		tween.tween_property(_brew_visual,"position",down,bob_leg_duration)

	tween.tween_property(_brew_visual,"position",mouth,settle_duration)
	tween.tween_callback(Callable(self,"_finish_drink_effect").bind(effect))


func _start_drink_audio_feedback() -> void:
	# 女巫自己的喝药声改为概率角色反馈；不再每次必播。
	if not WITCH_DRINK_SFX.is_empty() and randf() < clampf(witch_drink_voice_chance,0.0,1.0):
		_play_world_sfx(WITCH_DRINK_SFX.pick_random(),0.8,randf_range(0.98,1.03))
	# 液体饮用声固定三次。每次到下一次的间隔都 >= 上一段音频长度的一半，
	# 并只在 0.52~0.64 倍之间做小范围随机。
	_play_drink_sfx_repeat(0)


func _play_drink_sfx_repeat(index:int) -> void:
	if index < 0 or index >= DRINK_REPEAT_COUNT:
		return
	_play_world_sfx(DRINK_SFX,-0.8,randf_range(0.99,1.01))
	if index + 1 >= DRINK_REPEAT_COUNT or get_tree() == null:
		return
	var stream_length:float = DRINK_SFX.get_length() if DRINK_SFX != null else 0.0
	var safe_length:float = maxf(stream_length,0.18)
	var gap:float = safe_length * randf_range(DRINK_REPEAT_GAP_MIN_RATIO,DRINK_REPEAT_GAP_MAX_RATIO)
	var timer:SceneTreeTimer = get_tree().create_timer(gap,false)
	timer.timeout.connect(Callable(self,"_play_drink_sfx_repeat").bind(index + 1))


func _finish_drink_effect(effect:String) -> void:
	POTION_EFFECTS.apply_stacking_effect(self,effect,self)
	var color:Color = POTION_EFFECTS.color_for(effect)
	_flash_character(color)
	_hide_brew_visual()
	_action_busy = false
	_schedule_next_brew()


func _throw_potion(effect:String) -> void:
	var target:ball = _find_nearest_enemy_for_potion()
	if target == null:
		# 没有敌人可扔时不让药水卡死在手里，直接自己喝掉。
		_drink_potion(effect)
		return
	_play_world_sfx(THROW_SFX,0.8,randf_range(0.98,1.03))
	var projectile:Node2D = POTION_SCRIPT.new()
	get_tree().current_scene.add_child(projectile)

	# V392：投掷不是再生成一瓶“默认大小/默认角度”的药水。
	# 直接读取此刻手里 PotionImage 的世界 Transform，把同一视觉姿态交给飞行药水。
	var start:Vector2 = global_position
	var held_visual_transform:Variant = null
	if _brew_sprite != null and is_instance_valid(_brew_sprite) and _brew_sprite.visible:
		start = _brew_sprite.global_position
		held_visual_transform = _brew_sprite.global_transform
	elif _brew_visual != null and is_instance_valid(_brew_visual) and _brew_visual.visible:
		start = _brew_visual.global_position
	_hide_brew_visual()
	# 抛出时锁定敌人的这一刻位置；后续不追踪，保证是真正的抛物线。
	var target_point:Vector2 = ball.body_point(target,global_position)
	projectile.call("setup",start,target_point,effect,self,held_visual_transform)
	_schedule_next_brew()


func _find_nearest_enemy_for_potion() -> ball:
	if is_player_controlled():
		if not has_player_control_aim(): return null
		var point:Vector2=player_control_aim_world_position()
		var aimed:ball=null
		var closest:float=INF
		for raw:Node in get_tree().get_nodes_in_group("Ball"):
			if not (raw is ball) or not _is_valid_potion_enemy(raw as ball): continue
			var distance:float=ball.body_point(raw,point).distance_to(point)
			if distance<=U.radius(raw)+6.0 and distance<closest:
				aimed=raw as ball
				closest=distance
		return aimed
	if is_instance_valid(Nearest_Enemy) and Nearest_Enemy is ball:
		var nearest:ball = Nearest_Enemy as ball
		if _is_valid_potion_enemy(nearest):
			return nearest
	var best:ball = null
	var best_distance_sq:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_valid_potion_enemy(candidate):
			continue
		var d:float = global_position.distance_squared_to(ball.body_point(candidate,global_position))
		if d < best_distance_sq:
			best_distance_sq = d
			best = candidate
	return best


func _is_valid_potion_enemy(candidate:ball) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return false
	if candidate.health <= 0 or candidate.is_queued_for_deletion():
		return false
	if not candidate.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and candidate.Team == Team:
		return false
	return true


func _current_potion_target_inversion_mode() -> int:
	var has_inverted_enemy:bool = false
	var has_normal_enemy:bool = false
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_valid_potion_enemy(candidate):
			continue
		var inverted:bool = (
			candidate.has_method("is_minecraft_potion_healing_damage_inverted")
			and bool(candidate.call("is_minecraft_potion_healing_damage_inverted"))
		)
		if inverted:
			has_inverted_enemy = true
		else:
			has_normal_enemy = true
		if has_inverted_enemy and has_normal_enemy:
			return POTION_TARGET_MODE_MIXED_INVERSION
	if has_inverted_enemy:
		return POTION_TARGET_MODE_ALL_INVERTED
	return POTION_TARGET_MODE_NORMAL


func _potion_counts_as_self_use(effect:String,target_mode:int) -> bool:
	if target_mode == POTION_TARGET_MODE_NORMAL:
		return POTION_EFFECTS.is_good(effect)
	if POTION_EFFECTS.is_healing_family(effect):
		# 对反转敌人，治疗/恢复就是进攻药水，因此按原中毒/瞬伤的投掷倾向处理。
		return false
	if target_mode == POTION_TARGET_MODE_ALL_INVERTED and POTION_EFFECTS.is_damage_family(effect):
		# 所有敌人都反转时，中毒/瞬伤会帮助敌人，因此把投掷倾向降到原治疗药水水平。
		return true
	return POTION_EFFECTS.is_good(effect)


func _schedule_next_brew() -> void:
	# V417：女巫炼药攻速使用固定冷却，不再随机，也不再受 Attack_Cooling / 速度药水二次缩放。
	# 这样每次完成喝药或投掷后，下一轮炼药都严格等待同一个时间。
	_brew_left = maxf(brew_interval,0.1)


func _setup_brew_visual() -> void:
	# V392：药水跟随 Graphics，而不是直接挂角色根节点。
	# Graphics 发生角色专属旋转/位移时，手中药水会自然继承；BrewFacingAnchor 只负责左右镜像。
	var visual_parent:Node2D = graphics if graphics != null and is_instance_valid(graphics) else self
	_brew_anchor = Node2D.new()
	_brew_anchor.name = "BrewFacingAnchor"
	_brew_anchor.position = Vector2.ZERO
	_brew_anchor.z_index = 120
	visual_parent.add_child(_brew_anchor)

	_brew_visual = Node2D.new()
	_brew_visual.name = "BrewVisual"
	_brew_visual.position = Vector2(absf(throw_start_offset_x),throw_start_offset_y)
	_brew_visual.z_index = 1
	_brew_visual.visible = false
	_brew_anchor.add_child(_brew_visual)

	_brew_sprite = Sprite2D.new()
	_brew_sprite.name = "PotionImage"
	_brew_sprite.centered = true
	_brew_sprite.scale = Vector2.ONE * 0.050
	_brew_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_brew_visual.add_child(_brew_sprite)

	_update_brew_anchor_facing()


func _show_brew_visual(effect:String) -> void:
	if _brew_visual == null:
		return
	_brew_visual.visible = true
	_place_brew_visual_in_front()
	_brew_visual.scale = Vector2.ONE * 0.92
	_brew_visual.rotation = -0.08
	if _brew_sprite != null:
		_brew_sprite.texture = POTION_EFFECTS.texture_for(effect)


func _current_visual_facing_sign() -> float:
	# ball.dir_left=true 表示原图默认朝左；公共 Shader flip 后方向相反。
	var default_sign:float = -1.0 if dir_left else 1.0
	var flipped:bool = is_character_visual_flipped_h()
	return -default_sign if flipped else default_sign


func _update_brew_anchor_facing() -> void:
	if _brew_anchor == null or not is_instance_valid(_brew_anchor):
		return
	_brew_facing = _current_visual_facing_sign()
	# 只镜像 X，不改 Graphics 自己的旋转；因此角色专属 Graphics.rotation 仍会完整继承。
	_brew_anchor.scale = Vector2(_brew_facing,1.0)


func _place_brew_visual_in_front() -> void:
	if _brew_visual == null:
		return
	_update_brew_anchor_facing()
	_brew_visual.position = Vector2(absf(throw_start_offset_x),throw_start_offset_y)


func _update_ready_potion_visual() -> void:
	if _brew_visual == null or not _brew_visual.visible:
		return
	# 成品阶段只做很轻微的上下浮动，不再像炼制过程一样剧烈晃动。
	var elapsed:float = maxf(brewed_hold_duration - _decision_left,0.0)
	var base:Vector2 = Vector2(absf(throw_start_offset_x),throw_start_offset_y)
	_brew_visual.position = base + Vector2(0.0,sin(elapsed * 7.0) * 2.0)
	_brew_visual.rotation = sin(elapsed * 5.0) * 0.025


func _update_brew_visual_animation() -> void:
	if _brew_visual == null or not _brew_visual.visible:
		return
	var elapsed:float = maxf(brewing_duration - _brewing_left,0.0)
	_brew_visual.rotation = sin(elapsed * 13.0) * 0.12
	var pulse:float = 0.92 + 0.06 * sin(elapsed * 9.0)
	_brew_visual.scale = Vector2.ONE * pulse


func _hide_brew_visual() -> void:
	if _brew_visual != null:
		_brew_visual.visible = false
		_brew_visual.scale = Vector2.ONE
		_brew_visual.rotation = 0.0


func _flash_character(color:Color) -> void:
	if image == null or not is_instance_valid(image) or not image is CanvasItem:
		return
	var canvas:CanvasItem = image as CanvasItem
	var before:Color = canvas.self_modulate
	var flash:Color = before.lerp(color,0.48)
	flash.a = before.a
	canvas.self_modulate = flash
	var tween:Tween = create_tween()
	tween.tween_property(canvas,"self_modulate",before,0.28)


func _play_world_sfx(stream:AudioStream,volume_db_value:float = 0.0,pitch:float = 1.0) -> void:
	if stream == null or get_tree() == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db_value
	player.pitch_scale = pitch
	world.add_child(player)
	player.global_position = global_position
	player.finished.connect(player.queue_free)
	player.play()


func Die() -> void:
	_hide_brew_visual()
	if not _death_audio_played:
		_death_audio_played = true
		_play_world_sfx(DEATH_SFX,2.0,randf_range(0.98,1.02))
	super.Die()
