extends ball

const WAR_GODDESS_IMMUNITY_SHADER:Shader = preload("res://shaders/战争女神_火焰免疫.gdshader")
const WAR_GODDESS_CIRCLE_SCENE:PackedScene = preload("res://scenes/effects/战争女神_法阵.tscn")
const WAR_GODDESS_PROJECTILE_SCENE:PackedScene = preload("res://scenes/shooter/战争女神_火焰剑气.tscn")
const WAR_GODDESS_TRANSFORM_EFFECT_SCENE:PackedScene = preload("res://scenes/effects/战争女神_变身火焰.tscn")
const WAR_GODDESS_FORM1_TEXTURE:Texture2D = preload("res://Images/characters/游戏/战争女神/形态1.png")
const WAR_GODDESS_FORM2_TEXTURE:Texture2D = preload("res://Images/characters/游戏/战争女神/形态2.png")
const WAR_GODDESS_SWORD_TEXTURE:Texture2D = preload("res://Images/characters/游戏/战争女神/剑.png")
const SFX_WAR_MAGIC_CIRCLE:AudioStream = preload("res://audio/characters/游戏/战争女神/火焰法阵.wav")
const SFX_WAR_FIRE_SWING:AudioStream = preload("res://audio/characters/游戏/战争女神/火焰挥舞.wav")
const SFX_WAR_SWORD_HIT:AudioStream = preload("res://audio/characters/游戏/战争女神/砍人.mp3")
const SFX_WAR_SWORD_SWING:AudioStream = preload("res://audio/characters/游戏/战争女神/挥舞.mp3")
const SFX_WAR_IMMUNITY:AudioStream = preload("res://audio/characters/游戏/战争女神/火焰爆裂.wav")
const SFX_WAR_TRANSFORM:AudioStream = preload("res://audio/characters/游戏/战争女神/变身.wav")
const SFX_BURN_TICK:AudioStream = preload("res://audio/status/debuff/烫伤.wav")
const WAR_IMMUNITY_STACK_SLOTS:int = 4
const WAR_IMMUNITY_REFRESH_PROGRESS:float = 0.30
const WAR_IMMUNITY_FLASH_SECONDS:float = 0.16

@export_category("战争女神 - 普攻")
@export_range(30.0,220.0,1.0) var melee_range:float = 52.0
@export_range(12.0,120.0,1.0) var melee_width:float = 28.0
@export_range(0.0,30.0,0.05) var melee_damage_multiplier:float = 19.3333333
@export_range(0.2,2.0,0.01) var attack_interval:float = 0.78
@export_range(0.02,0.50,0.01) var attack_windup:float = 0.13
@export_range(0.02,0.50,0.01) var attack_active_time:float = 0.10
@export_range(0.02,0.70,0.01) var attack_recovery:float = 0.18

@export_category("战争女神 - 被动免疫")
@export_range(0.0,1.0,0.01) var damage_immunity_chance:float = 0.20
@export_range(0.15,1.5,0.01) var immunity_fx_duration:float = 0.95
@export_range(0.08,0.55,0.01) var immunity_fx_radius:float = 0.50

@export_category("战争女神 - 法阵")
@export_range(40.0,320.0,1.0) var circle_radius:float = 72.0
@export_range(1.0,30.0,0.1) var circle_duration:float = 8.0
@export_range(0.1,2.0,0.05) var circle_damage_interval:float = 0.50
@export_range(0.0,30.0,0.05) var circle_damage_multiplier:float = 3.3333333
@export_range(0.2,3.0,0.05) var circle_heal_interval:float = 1.0
@export_range(1.0,100.0,1.0) var circle_heal_amount:float = 14.0
@export_range(20.0,500.0,1.0) var actual_heal_to_form2:float = 100.0
@export_range(1.0,30.0,0.1) var magic_circle_cooldown:float = 9.5
@export_range(0.0,10.0,0.1) var first_circle_delay:float = 2.0

@export_category("战争女神 - 形态2")
@export_range(1.0,2.0,0.01) var form2_speed_multiplier:float = 1.15
@export_range(0.0,100.0,1.0) var form2_circle_follow_speed:float = 18.0
@export_range(1.0,2.0,0.01) var form2_melee_range_multiplier:float = 1.15
@export_range(100.0,700.0,5.0) var form2_target_range:float = 330.0
@export_range(0.0,30.0,0.05) var projectile_damage_multiplier:float = 8.6666667
@export_range(100.0,1200.0,10.0) var projectile_speed:float = 560.0
@export_range(100.0,1000.0,10.0) var projectile_max_distance:float = 520.0
@export_range(0.2,10.0,0.1) var projectile_burn_duration:float = 3.0
@export_range(0.1,2.0,0.05) var projectile_burn_tick_interval:float = 0.5
@export_range(0.0,10.0,0.05) var projectile_burn_tick_damage_multiplier:float = 1.0

@export_category("战争女神 - 音效")
@export_range(-36.0,12.0,0.5) var sword_swing_sfx_volume_db:float = -1.0
@export_range(-36.0,12.0,0.5) var sword_hit_sfx_volume_db:float = 0.0
@export_range(-36.0,12.0,0.5) var magic_circle_sfx_volume_db:float = -2.0
@export_range(-36.0,12.0,0.5) var fire_swing_sfx_volume_db:float = -2.0
@export_range(-36.0,12.0,0.5) var burn_tick_sfx_volume_db:float = 1.0
@export_range(-36.0,12.0,0.5) var immunity_sfx_volume_db:float = -1.0
@export_range(-36.0,12.0,0.5) var transform_sfx_volume_db:float = -2.0
@export_range(120.0,2400.0,20.0) var war_sfx_max_distance:float = 900.0
@export_range(0.05,2.0,0.05) var war_sfx_attenuation:float = 0.75

@onready var war_attack_detect_area:Area2D = $AttackDetectArea
@onready var war_attack_detect_shape:CollisionShape2D = $AttackDetectArea/CollisionShape2D
@onready var war_melee_pivot:Node2D = $MeleePivot
@onready var war_melee_area:Area2D = $MeleePivot/MeleeArea
@onready var war_melee_shape:CollisionShape2D = $MeleePivot/MeleeArea/CollisionShape2D

var form2_active:bool = false
var circle_actual_heal_accumulated:float = 0.0
var _war_base_speed:float = 0.0
var _war_attack_cooldown_left:float = 0.0
var _war_circle_cooldown_left:float = 0.0
var _war_action_busy:bool = false
var _war_melee_hit_ids:Dictionary = {}
var _war_effect_serial:int = 0
var _war_current_circle:Node2D = null

var _war_attack_visual_left:float = 0.0
var _war_attack_visual_total:float = 0.0
var _war_attack_visual_angle:float = 0.0
var _war_attack_visual_form2:bool = false

var _war_immunity_slots:Array[Dictionary] = []
var _war_immunity_serial:int = 0
var _war_immunity_flash_left:float = 0.0
var _war_audio_serial:int = 0
var _war_transform_effect_serial:int = 0
var _war_contact_passthrough_uses:int = 0
var _war_contact_passthrough_serial:int = 0
var _war_damage_passthrough:bool = false
var _war_rejected_immunity_hits:Dictionary = {}



func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	_war_base_speed = Speed
	_war_attack_cooldown_left = randf_range(0.15,0.45)
	_war_circle_cooldown_left = maxf(first_circle_delay,0.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# V45：正式接入用户提供的形态1像素图。先于 ball._ready() 写入，
	# 让 CharacterAutoFit、选择预览和真实战斗统一使用同一张素材。
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = WAR_GODDESS_FORM1_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = true
		sprite.self_modulate = Color.WHITE
		var immunity_material := ShaderMaterial.new()
		immunity_material.shader = WAR_GODDESS_IMMUNITY_SHADER
		sprite.material = immunity_material
		immunity_material.set_shader_parameter("immunity_radius",immunity_fx_radius)
		_initialize_war_immunity_slots()
		_refresh_war_immunity_content_rect()

	super._ready()
	# V53：自定义免疫 Shader 编译成功后，继续沿用 ball 的 sprite_flip_h 镜像协议。
	# 这里主动重推一次当前朝向，确保进入战斗的第一帧也与移动方向一致。
	set_character_visual_flip_h(is_character_visual_flipped_h())
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		call_deferred("_refit_war_goddess_visual")
	_setup_war_goddess_combat_shapes()
	queue_redraw()


func _refit_war_goddess_visual() -> void:
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		fitter.call("apply_visual_fit_only")
	# AutoFit 只处理尺寸；重新确认 Shader 水平镜像，避免换形态/重算尺寸后朝向丢失。
	set_character_visual_flip_h(is_character_visual_flipped_h())
	# V58：AutoFit 会按透明像素重新居中 Sprite.offset。每次拟合后重推实际可见像素包围盒，
	# 让免疫受击位置与半径始终按人物真正内容计算，而不是按整张 64x64 PNG 的透明留白计算。
	_refresh_war_immunity_content_rect()

func get_preview_texture() -> Texture2D:
	return WAR_GODDESS_FORM1_TEXTURE


func _setup_war_goddess_combat_shapes() -> void:
	war_attack_detect_area.collision_layer = 0
	war_attack_detect_area.collision_mask = 2
	war_attack_detect_area.monitoring = true
	war_attack_detect_area.monitorable = false
	war_attack_detect_area.set_meta("threat_debug_detection",true)

	war_melee_area.collision_layer = 0
	war_melee_area.collision_mask = 2
	war_melee_area.monitoring = false
	war_melee_area.monitorable = false
	war_melee_area.set_meta("threat_debug_damage",0.0)
	_refresh_war_goddess_ranges()


func _local_scale_safe() -> float:
	return maxf(absf(global_scale.x),0.001)


func _refresh_war_goddess_ranges() -> void:
	var local_scale:float = _local_scale_safe()
	var detect_shape := war_attack_detect_shape.shape as CircleShape2D
	if detect_shape != null:
		var wanted_detect:float = form2_target_range if form2_active else melee_range
		detect_shape.radius = wanted_detect / local_scale

	var rect := war_melee_shape.shape as RectangleShape2D
	if rect != null:
		var world_length:float = melee_range * (form2_melee_range_multiplier if form2_active else 1.0)
		rect.size = Vector2(world_length / local_scale,melee_width / local_scale)
		war_melee_area.position = Vector2(world_length * 0.5 / local_scale,0.0)


func _process(delta:float) -> void:
	# 远端没有 state_machine physics authority；攻击挥剑视觉在本地按 RPC 状态继续推进。
	if not is_multiplayer_authority():
		_update_war_goddess_visual_timers(delta)


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	_update_war_goddess_visual_timers(delta)
	if not is_multiplayer_authority():
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		war_melee_area.monitoring = false
		war_melee_area.set_meta("threat_debug_damage",0.0)
		return
	if not is_combat_runtime_active():
		return

	_war_attack_cooldown_left = maxf(_war_attack_cooldown_left - delta,0.0)
	_war_circle_cooldown_left = maxf(_war_circle_cooldown_left - delta,0.0)

	# V130：操控时不再由角色自己的定时器自动法阵/自动普攻。
	# 左键与右键分别走下面的 controlled_* 手动入口。
	if is_player_controlled():
		return

	if not _war_action_busy and _war_circle_cooldown_left <= 0.0:
		_war_circle_cooldown_left = maxf(magic_circle_cooldown,0.2)
		_war_action_busy = true
		_run_magic_circle_cast()
		return

	if not _war_action_busy and _war_attack_cooldown_left <= 0.0:
		var target:ball = _find_war_attack_target()
		if target != null:
			_war_attack_cooldown_left = maxf(attack_interval,0.05)
			_war_action_busy = true
			_run_war_attack(target)


func _update_war_goddess_visual_timers(delta:float) -> void:
	if _war_attack_visual_left > 0.0:
		_war_attack_visual_left = maxf(_war_attack_visual_left - delta,0.0)
		queue_redraw()
	_update_war_immunity_slots(delta)


func _find_war_attack_target() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for area:Area2D in war_attack_detect_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var candidate_node:Node = area.get_parent()
		if not candidate_node is ball:
			candidate_node = area.owner
		if not candidate_node is ball:
			continue
		var candidate:ball = candidate_node as ball
		if not _is_war_enemy(candidate):
			continue
		var d:float = global_position.distance_squared_to(candidate.global_position)
		if d < nearest_distance_sq:
			nearest_distance_sq = d
			nearest = candidate
	return nearest


func _is_war_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and target.Team == Team:
		return false
	return true


func controlled_attack_action() -> void:
	if not is_multiplayer_authority() or not is_player_controlled() or _war_action_busy:
		return
	if health <= 0 or is_damage_output_disabled() or _war_attack_cooldown_left > 0.0:
		return
	_war_attack_cooldown_left = maxf(attack_interval,0.05)
	_war_action_busy = true
	_run_war_attack(null)


func controlled_skill_action() -> void:
	if not is_multiplayer_authority() or not is_player_controlled() or _war_action_busy:
		return
	if health <= 0 or is_damage_output_disabled() or _war_circle_cooldown_left > 0.0:
		return
	_war_circle_cooldown_left = maxf(magic_circle_cooldown,0.2)
	_war_action_busy = true
	_run_magic_circle_cast()


func _run_war_attack(target:ball) -> void:
	Attacking = true
	var target_position:Vector2
	if is_player_controlled() and has_player_control_aim():
		target_position = player_control_aim_world_position(global_position + direction)
	elif target != null and is_instance_valid(target):
		target_position = combat_target_position(target)
	else:
		target_position = global_position + Vector2.RIGHT
	var aim:Vector2 = target_position - global_position
	if aim.length_squared() <= 0.000001:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	var angle:float = aim.angle()
	_start_war_attack_visual_local(angle,form2_active)
	if multiplayer.has_multiplayer_peer():
		_remote_war_attack_visual.rpc(angle,form2_active)

	if not (await wait_for_combat_time(maxf(attack_windup,0.01))):
		_finish_war_attack()
		return
	if not is_instance_valid(self) or health <= 0:
		return

	# 近战与远程在同一个命中时刻发生。形态2时近战仍保留，所以近距离目标可以叠加两份伤害。
	_activate_war_melee(angle)
	await get_tree().physics_frame
	if is_instance_valid(self):
		_damage_war_melee_overlaps()
		if form2_active:
			_spawn_war_projectile_everywhere(aim)

	if not (await wait_for_combat_time(maxf(attack_active_time,0.01))):
		_finish_war_attack()
		return
	_deactivate_war_melee()
	await wait_for_combat_time(maxf(attack_recovery,0.01))
	_finish_war_attack()


func _activate_war_melee(angle:float) -> void:
	war_melee_pivot.rotation = angle
	_war_melee_hit_ids.clear()
	war_melee_area.set_meta("threat_debug_damage",attack_damage(melee_damage_multiplier))
	war_melee_area.monitoring = true


func _deactivate_war_melee() -> void:
	war_melee_area.monitoring = false
	war_melee_area.set_meta("threat_debug_damage",0.0)
	_war_melee_hit_ids.clear()


func _damage_war_melee_overlaps() -> void:
	if not is_multiplayer_authority():
		return
	var outgoing:float = attack_damage(melee_damage_multiplier)
	if outgoing <= 0.0:
		return

	# V47：近战实际结算不再依赖“刚打开 Area2D 后下一帧是否已经刷新 overlap 列表”。
	# 直接按这一刀当前的世界空间矩形做 PhysicsShapeQuery，保证看到挥剑就能正常结算伤害。
	var world_length:float = melee_range * (form2_melee_range_multiplier if form2_active else 1.0)
	var world_width:float = melee_width
	var blade_shape := RectangleShape2D.new()
	blade_shape.size = Vector2(world_length,world_width)

	var forward:Vector2 = Vector2.RIGHT.rotated(war_melee_pivot.rotation)
	var center:Vector2 = global_position + forward * world_length * 0.5
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = blade_shape
	query.transform = Transform2D(war_melee_pivot.rotation,center)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	if self_hurtbox != null and is_instance_valid(self_hurtbox):
		query.exclude = [self_hurtbox.get_rid()]

	var results:Array = get_world_2d().direct_space_state.intersect_shape(query,64)
	for result in results:
		if not result is Dictionary:
			continue
		var collider:Variant = (result as Dictionary).get("collider",null)
		if not collider is hurtbox:
			continue
		var area:hurtbox = collider as hurtbox
		var target_node:Node = area.get_parent()
		if not target_node is ball:
			target_node = area.owner
		if not target_node is ball:
			continue
		var target:ball = target_node as ball
		if not _is_war_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		if _war_melee_hit_ids.has(target_id):
			continue
		_war_melee_hit_ids[target_id] = true
		var before_health:float = float(target.health)
		var before_block:float = float(target.block)
		var hit_point:Vector2 = target.global_position
		target.receive_positional_damage(outgoing,hit_point,false,self)
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		if health_loss > 0.0 or block_loss > 0.0:
			var hit_fx_seed:int = Game.battle_rng_seed_or("scripts/characters/游戏/战争女神.gd:hit_fx_seed",int(Time.get_ticks_usec()) ^ target_id ^ get_instance_id())
			target.notify_hit_burst_feedback(
				hit_point,
				outgoing,
				health_loss,
				block_loss,
				melee_width,
				hit_fx_seed,
				(target.global_position - global_position).normalized()
			)
			_play_war_sword_hit_networked(hit_point)


func _finish_war_attack() -> void:
	_deactivate_war_melee()
	Attacking = false
	_war_action_busy = false


func _start_war_attack_visual_local(angle:float,is_form2:bool) -> void:
	_war_attack_visual_angle = angle
	_war_attack_visual_form2 = is_form2
	_war_attack_visual_total = maxf(attack_windup + attack_active_time + attack_recovery,0.08)
	_war_attack_visual_left = _war_attack_visual_total
	# V55：形态2的挥剑只使用火焰挥舞音效。普通形态仍播放普通挥剑声。
	# 火焰挥舞声在真正生成火焰剑气的命中时刻播放，避免形态2双重挥舞音。
	if not is_form2:
		_play_war_one_shot_local(SFX_WAR_SWORD_SWING,global_position,sword_swing_sfx_volume_db,randf_range(0.98,1.02))
	queue_redraw()


@rpc("authority","call_remote","reliable")
func _remote_war_attack_visual(angle:float,is_form2:bool) -> void:
	_start_war_attack_visual_local(angle,is_form2)


func _run_magic_circle_cast() -> void:
	Using_Skill = true
	_spawn_war_circle_everywhere(global_position)
	await wait_for_combat_time(0.20)
	Using_Skill = false
	_war_action_busy = false


func _spawn_war_circle_everywhere(spawn_position:Vector2) -> void:
	_war_effect_serial += 1
	_spawn_war_circle_local(spawn_position,_war_effect_serial)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_war_circle.rpc(spawn_position,_war_effect_serial)


@rpc("authority","call_remote","reliable")
func _remote_spawn_war_circle(spawn_position:Vector2,serial:int) -> void:
	_spawn_war_circle_local(spawn_position,serial)


func _spawn_war_circle_local(spawn_position:Vector2,serial:int) -> void:
	_play_war_one_shot_local(SFX_WAR_MAGIC_CIRCLE,spawn_position,magic_circle_sfx_volume_db,1.0)
	if _war_current_circle != null and is_instance_valid(_war_current_circle):
		_war_current_circle.queue_free()
	var circle:Node2D = WAR_GODDESS_CIRCLE_SCENE.instantiate() as Node2D
	if circle == null:
		return
	circle.name = "WarGoddessMagicCircle_%d" % serial
	# V49：不再用 top_level。top_level 会改变 CanvasItem 绘制分组，
	# 这里改为普通子节点 + 世界变换锁定，让法阵稳定显示在人物下面。
	circle.top_level = false
	circle.z_as_relative = false
	circle.z_index = -1
	add_child(circle,true)
	circle.global_position = spawn_position
	circle.global_rotation = 0.0
	circle.global_scale = Vector2.ONE
	if circle.has_method("set_world_anchor"):
		circle.call("set_world_anchor",spawn_position)
	if circle.has_method("setup"):
		circle.call(
			"setup",
			self,
			circle_radius,
			circle_duration,
			circle_damage_interval,
			attack_damage(circle_damage_multiplier),
			circle_heal_interval,
			circle_heal_amount,
			form2_circle_follow_speed
		)
	_war_current_circle = circle


func on_war_goddess_circle_heal(actual_healed:int) -> void:
	# V48：形态2改为累计“实际回复生命”100点。
	# heal() 的返回值就是本次真正恢复的生命；满血溢出的部分返回 0，因此不会计入。
	if not is_multiplayer_authority() or form2_active:
		return
	if actual_healed <= 0:
		return
	circle_actual_heal_accumulated += float(actual_healed)
	if circle_actual_heal_accumulated >= maxf(actual_heal_to_form2,1.0):
		_enter_war_form2()


func _enter_war_form2() -> void:
	if form2_active:
		return
	form2_active = true
	_play_war_transform_fx_local()
	Speed = _war_base_speed * maxf(form2_speed_multiplier,1.0)
	_refresh_war_goddess_ranges()
	queue_redraw()
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = WAR_GODDESS_FORM2_TEXTURE
		sprite.self_modulate = Color.WHITE
		_refresh_war_immunity_content_rect()
		call_deferred("_refit_war_goddess_visual")
	if multiplayer.has_multiplayer_peer():
		_remote_enter_war_form2.rpc()


@rpc("authority","call_remote","reliable")
func _remote_enter_war_form2() -> void:
	if form2_active:
		return
	form2_active = true
	_play_war_transform_fx_local()
	Speed = _war_base_speed * maxf(form2_speed_multiplier,1.0)
	_refresh_war_goddess_ranges()
	queue_redraw()
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = WAR_GODDESS_FORM2_TEXTURE
		sprite.self_modulate = Color.WHITE
		_refresh_war_immunity_content_rect()
		call_deferred("_refit_war_goddess_visual")


func _play_war_transform_fx_local() -> void:
	if not is_inside_tree():
		return
	_play_war_one_shot_local(SFX_WAR_TRANSFORM,global_position,transform_sfx_volume_db,1.0)
	var effect:Node2D = WAR_GODDESS_TRANSFORM_EFFECT_SCENE.instantiate() as Node2D
	if effect == null:
		return
	_war_transform_effect_serial += 1
	effect.name = "WarGoddessTransformFlame_%d" % _war_transform_effect_serial
	# V68：变身火焰需要直接遮住人物并随人物一起上飘，因此不再使用 top_level 世界锚定。
	effect.top_level = false
	effect.z_as_relative = true
	effect.z_index = 8
	add_child(effect,true)
	effect.position = Vector2.ZERO
	effect.rotation = 0.0
	effect.scale = Vector2.ONE
	if effect.has_method("setup"):
		effect.call("setup",96.0,20)


func _spawn_war_projectile_everywhere(aim:Vector2) -> void:
	if aim.length_squared() <= 0.000001:
		return
	_war_effect_serial += 1
	var spawn_position:Vector2 = global_position + aim.normalized() * 34.0
	_spawn_war_projectile_local(spawn_position,aim.normalized(),_war_effect_serial)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_war_projectile.rpc(spawn_position,aim.normalized(),_war_effect_serial)


@rpc("authority","call_remote","reliable")
func _remote_spawn_war_projectile(spawn_position:Vector2,aim:Vector2,serial:int) -> void:
	_spawn_war_projectile_local(spawn_position,aim,serial)


func _spawn_war_projectile_local(spawn_position:Vector2,aim:Vector2,serial:int) -> void:
	_play_war_one_shot_local(SFX_WAR_FIRE_SWING,spawn_position,fire_swing_sfx_volume_db,randf_range(0.97,1.03))
	var projectile:Node2D = WAR_GODDESS_PROJECTILE_SCENE.instantiate() as Node2D
	if projectile == null:
		return
	projectile.name = "WarGoddessFlameSlash_%d" % serial
	projectile.top_level = true
	add_child(projectile,true)
	projectile.global_position = spawn_position
	projectile.global_rotation = aim.angle()
	if projectile.has_method("setup"):
		projectile.call(
			"setup",
			self,
			Team,
			aim,
			attack_damage(projectile_damage_multiplier),
			projectile_speed,
			projectile_max_distance,
			projectile_burn_duration,
			projectile_burn_tick_interval,
			attack_damage(projectile_burn_tick_damage_multiplier)
		)


# ============================================================
# 20% 伤害免疫 + 局部 Shader 火焰崩散
# ============================================================
func can_receive_hit_contact(incoming_hit:hitbox,_contact_hurtbox:hurtbox) -> bool:
	if incoming_hit == null or not is_instance_valid(incoming_hit) or not is_multiplayer_authority():
		return true
	var impact:Vector2 = incoming_hit.global_position
	if _try_war_immunity(impact):
		_war_rejected_immunity_hits[incoming_hit.get_instance_id()] = true
		return false
	_grant_war_contact_passthrough()
	return true


func can_receive_hit_from(incoming_hit:hitbox) -> bool:
	return can_receive_hit_contact(incoming_hit,null)


func on_incoming_hit_rejected(incoming_hit:hitbox) -> void:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return
	var hit_id:int = incoming_hit.get_instance_id()
	if not _war_rejected_immunity_hits.has(hit_id):
		super.on_incoming_hit_rejected(incoming_hit)
		return
	_war_rejected_immunity_hits.erase(hit_id)

	# 免疫不是格挡，不生成格挡爆裂；普通非穿透投射物仍然在身体处结束。
	var attacker:ball = incoming_hit.get_parent() as ball
	if attacker == null and incoming_hit.owner is ball:
		attacker = incoming_hit.owner as ball
	if attacker != null and is_instance_valid(attacker) and _is_ranged_hit_source(attacker):
		if should_destroy_projectile_on_rejected_hit(incoming_hit):
			attacker.on_projectile_blocked_by(self,incoming_hit.global_position)


func receive_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block_value:bool = false,
	source:Node = null
) -> bool:
	if damage <= 0.0:
		return false
	if is_multiplayer_authority() and _try_war_immunity(impact_position):
		return false
	_war_damage_passthrough = true
	var accepted:bool = super.receive_positional_damage(damage,impact_position,ignore_block_value,source)
	_war_damage_passthrough = false
	return accepted


func receive_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block_value:bool = false,
	raw_health:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	if not raw_health:
		return super.receive_spatial_damage(damage,damage_space,ignore_block_value,false)

	var impact:Vector2 = global_position
	if damage_space is Vector2:
		impact = damage_space as Vector2
	elif damage_space is Dictionary:
		var context:Dictionary = damage_space as Dictionary
		for key:String in ["point","center","origin"]:
			if context.get(key,null) is Vector2:
				impact = context.get(key,global_position) as Vector2
				break
	if is_multiplayer_authority() and _try_war_immunity(impact):
		return false
	_war_damage_passthrough = true
	var accepted:bool = super.receive_spatial_damage(damage,damage_space,ignore_block_value,true)
	_war_damage_passthrough = false
	return accepted


func take_damage(damage:float,ignore_block_value:bool = false) -> void:
	if damage <= 0.0:
		return
	if _war_damage_passthrough:
		super.take_damage(damage,ignore_block_value)
		return
	if _war_contact_passthrough_uses > 0:
		_war_contact_passthrough_uses -= 1
		super.take_damage(damage,ignore_block_value)
		return
	if is_multiplayer_authority() and _try_war_immunity(global_position):
		return
	super.take_damage(damage,ignore_block_value)


func _grant_war_contact_passthrough() -> void:
	_war_contact_passthrough_uses += 1
	_war_contact_passthrough_serial += 1
	var serial:int = _war_contact_passthrough_serial
	call_deferred("_expire_war_contact_passthrough",serial)


func _expire_war_contact_passthrough(serial:int) -> void:
	if serial == _war_contact_passthrough_serial:
		_war_contact_passthrough_uses = 0


func _try_war_immunity(impact_position:Vector2) -> bool:
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return false
	if randf() >= clampf(damage_immunity_chance,0.0,1.0):
		return false
	var hit_uv:Vector2 = _war_impact_uv(impact_position)
	var fx_seed:float = randf_range(0.0,999.0)
	_play_war_immunity_fx_local(hit_uv,fx_seed,impact_position)
	if multiplayer.has_multiplayer_peer():
		_remote_war_immunity_fx.rpc(hit_uv,fx_seed,impact_position)
	return true


func _war_texture_used_rect(texture:Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var texture_size:Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2()
	# V432 性能：可见像素范围只取决于纹理本身。此前每次免疫命中都 Texture2D.get_image()
	#（GPU->CPU 回读，单次 4~5 ms）；现在按纹理对象跨实例缓存一次。
	var cache_key:int = texture.get_instance_id()
	var cached:Variant = _war_texture_used_rect_cache.get(cache_key)
	if cached is Rect2:
		return cached
	var used_rect := Rect2(Vector2.ZERO,texture_size)
	var source_image:Image = texture.get_image()
	if source_image != null and not source_image.is_empty():
		var used:Rect2i = source_image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			used_rect = Rect2(Vector2(used.position),Vector2(used.size))
	_war_texture_used_rect_cache[cache_key] = used_rect
	return used_rect


static var _war_texture_used_rect_cache:Dictionary = {}


func _refresh_war_immunity_content_rect() -> void:
	if not image is Sprite2D:
		return
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture == null:
		return
	var texture_size:Vector2 = sprite.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var used_rect:Rect2 = _war_texture_used_rect(sprite.texture)
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		used_rect = Rect2(Vector2.ZERO,texture_size)
	var content_uv := Vector4(
		used_rect.position.x / texture_size.x,
		used_rect.position.y / texture_size.y,
		used_rect.size.x / texture_size.x,
		used_rect.size.y / texture_size.y
	)
	_set_war_immunity_material_parameter(&"immunity_content_rect",content_uv)
	_set_war_immunity_material_parameter(&"immunity_radius",immunity_fx_radius)
	# Shader-only 碎片需要飞出 Sprite 原本的 64x64 四边形，因此 V65 会扩大顶点绘制范围。
	# 围绕 Sprite 真正的图像中心扩张，避免 CharacterAutoFit 调整 offset 后人物整体被带偏。
	var quad_center:Vector2 = sprite.offset
	if not sprite.centered:
		quad_center += texture_size * 0.5
	_set_war_immunity_material_parameter(&"immunity_quad_center",quad_center)
	_set_war_immunity_material_parameter(&"immunity_canvas_expand",3.0)


func _war_impact_uv(impact_position:Vector2) -> Vector2:
	if not image is Sprite2D:
		return Vector2(0.5,0.5)
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture == null:
		return Vector2(0.5,0.5)

	var texture_size:Vector2 = sprite.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2(0.5,0.5)
	var used_rect:Rect2 = _war_texture_used_rect(sprite.texture)
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		used_rect = Rect2(Vector2.ZERO,texture_size)

	# V58：把世界受击点先映射到“实际非透明人物包围盒”的本地矩形。
	# CharacterAutoFit 本身也是按同一 used_rect 居中和拟合，因此左右/上下的受击半径现在使用同一真实像素尺度。
	var local_hit:Vector2 = sprite.to_local(impact_position)
	var visible_origin:Vector2 = sprite.offset + used_rect.position
	if sprite.centered:
		visible_origin -= texture_size * 0.5
	var visible_local_rect := Rect2(visible_origin,used_rect.size)
	var normalized := Vector2(
		(local_hit.x - visible_local_rect.position.x) / maxf(visible_local_rect.size.x,0.001),
		(local_hit.y - visible_local_rect.position.y) / maxf(visible_local_rect.size.y,0.001)
	)
	normalized.x = clampf(normalized.x,0.0,1.0)
	normalized.y = clampf(normalized.y,0.0,1.0)
	if is_character_visual_flipped_h():
		normalized.x = 1.0 - normalized.x

	var pixel_position:Vector2 = used_rect.position + normalized * used_rect.size
	var uv := Vector2(pixel_position.x / texture_size.x,pixel_position.y / texture_size.y)
	uv.x = clampf(uv.x,0.0,1.0)
	uv.y = clampf(uv.y,0.0,1.0)
	return uv


@rpc("authority","call_remote","reliable")
func _remote_war_immunity_fx(hit_uv:Vector2,fx_seed:float,impact_position:Vector2) -> void:
	_play_war_immunity_fx_local(hit_uv,fx_seed,impact_position)


func _initialize_war_immunity_slots() -> void:
	_war_immunity_slots.clear()
	_war_immunity_flash_left = 0.0
	_set_war_immunity_material_parameter(&"immunity_global_flash",0.0)
	for slot_index:int in range(WAR_IMMUNITY_STACK_SLOTS):
		_war_immunity_slots.append({
			"active": false,
			"progress": 1.0,
			"hit_uv": Vector2(0.5,0.5),
			"fx_seed": 0.0,
			"serial": 0,
		})
		_set_war_immunity_slot_shader(slot_index,Vector2(0.5,0.5),0.0,1.0)


func _war_immunity_uv_distance_px(a:Vector2,b:Vector2) -> float:
	if not image is Sprite2D:
		return INF
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture == null:
		return INF
	var texture_size:Vector2 = sprite.texture.get_size()
	return ((a - b) * texture_size).length()


func _war_immunity_same_spot_threshold_px() -> float:
	if not image is Sprite2D:
		return 8.0
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture == null:
		return 8.0
	var used_rect:Rect2 = _war_texture_used_rect(sprite.texture)
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		return 8.0
	return maxf(minf(used_rect.size.x,used_rect.size.y) * immunity_fx_radius * 0.52,6.0)


func _find_nearby_war_immunity_slot(hit_uv:Vector2) -> int:
	var threshold_px:float = _war_immunity_same_spot_threshold_px()
	var best_index:int = -1
	var best_distance:float = INF
	for slot_index:int in range(_war_immunity_slots.size()):
		var slot:Dictionary = _war_immunity_slots[slot_index]
		if not bool(slot.get("active",false)):
			continue
		var slot_uv:Vector2 = slot.get("hit_uv",Vector2(0.5,0.5))
		var distance_px:float = _war_immunity_uv_distance_px(slot_uv,hit_uv)
		if distance_px <= threshold_px and distance_px < best_distance:
			best_distance = distance_px
			best_index = slot_index
	return best_index


func _choose_war_immunity_slot() -> int:
	for slot_index:int in range(_war_immunity_slots.size()):
		var slot:Dictionary = _war_immunity_slots[slot_index]
		if not bool(slot.get("active",false)):
			return slot_index
	# 不同位置已经占满 4 个槽位时，替换最接近恢复完成的那一个。
	var best_index:int = 0
	var best_progress:float = -1.0
	for slot_index:int in range(_war_immunity_slots.size()):
		var slot:Dictionary = _war_immunity_slots[slot_index]
		var progress:float = float(slot.get("progress",1.0))
		if progress > best_progress:
			best_progress = progress
			best_index = slot_index
	return best_index


func _play_war_immunity_fx_local(hit_uv:Vector2,fx_seed:float,impact_position:Vector2) -> void:
	if image == null or not is_instance_valid(image):
		return
	if _war_immunity_slots.size() != WAR_IMMUNITY_STACK_SLOTS:
		_initialize_war_immunity_slots()

	# V65：同一个受击区域再次免疫时，不创建一个从 0 开始的新动画。
	# 直接复用当前槽位，并把进度拉回已经完全破碎但尚未恢复的阶段；不会先长回来再重新散开。
	var slot_index:int = _find_nearby_war_immunity_slot(hit_uv)
	_war_immunity_serial += 1
	if slot_index >= 0:
		var existing:Dictionary = _war_immunity_slots[slot_index]
		var old_uv:Vector2 = existing.get("hit_uv",hit_uv)
		var merged_uv:Vector2 = old_uv.lerp(hit_uv,0.28)
		var current_progress:float = minf(float(existing.get("progress",WAR_IMMUNITY_REFRESH_PROGRESS)),WAR_IMMUNITY_REFRESH_PROGRESS)
		var existing_seed:float = float(existing.get("fx_seed",fx_seed))
		existing["active"] = true
		existing["progress"] = current_progress
		existing["hit_uv"] = merged_uv
		existing["fx_seed"] = existing_seed
		existing["serial"] = _war_immunity_serial
		_war_immunity_slots[slot_index] = existing
		_set_war_immunity_slot_shader(slot_index,merged_uv,existing_seed,current_progress)
	else:
		slot_index = _choose_war_immunity_slot()
		_war_immunity_slots[slot_index] = {
			"active": true,
			"progress": 0.0,
			"hit_uv": hit_uv,
			"fx_seed": fx_seed,
			"serial": _war_immunity_serial,
		}
		_set_war_immunity_slot_shader(slot_index,hit_uv,fx_seed,0.0)

	# 全身橙色瞬闪与局部破碎进度解耦：每次免疫都会重新闪，但不会把同位置的缺口重置。
	_war_immunity_flash_left = WAR_IMMUNITY_FLASH_SECONDS
	_set_war_immunity_material_parameter(&"immunity_global_flash",1.0)
	_play_war_one_shot_local(SFX_WAR_IMMUNITY,impact_position,immunity_sfx_volume_db,randf_range(0.97,1.03))


func _update_war_immunity_slots(delta:float) -> void:
	if image == null or not is_instance_valid(image):
		return

	if _war_immunity_flash_left > 0.0:
		_war_immunity_flash_left = maxf(_war_immunity_flash_left - maxf(delta,0.0),0.0)
		var flash_ratio:float = clampf(_war_immunity_flash_left / maxf(WAR_IMMUNITY_FLASH_SECONDS,0.001),0.0,1.0)
		_set_war_immunity_material_parameter(&"immunity_global_flash",flash_ratio)
	else:
		_set_war_immunity_material_parameter(&"immunity_global_flash",0.0)

	var duration:float = maxf(immunity_fx_duration,0.05)
	var progress_step:float = maxf(delta,0.0) / duration
	for slot_index:int in range(_war_immunity_slots.size()):
		var slot:Dictionary = _war_immunity_slots[slot_index]
		if not bool(slot.get("active",false)):
			continue
		var progress:float = clampf(float(slot.get("progress",1.0)) + progress_step,0.0,1.0)
		slot["progress"] = progress
		if progress >= 1.0:
			slot["active"] = false
		_war_immunity_slots[slot_index] = slot
		_set_war_immunity_material_parameter(StringName("immunity_progress_%d" % slot_index),progress)


func _war_immunity_material() -> ShaderMaterial:
	if image == null or not is_instance_valid(image):
		return null
	var canvas_item:CanvasItem = image as CanvasItem
	if canvas_item == null:
		return null
	return canvas_item.material as ShaderMaterial


func _set_war_immunity_material_parameter(parameter_name:StringName,value:Variant) -> void:
	var immunity_material := _war_immunity_material()
	if immunity_material == null:
		return
	immunity_material.set_shader_parameter(parameter_name,value)


func _set_war_immunity_slot_shader(slot_index:int,hit_uv:Vector2,fx_seed:float,progress:float) -> void:
	_set_war_immunity_material_parameter(&"immunity_radius",immunity_fx_radius)
	_set_war_immunity_material_parameter(StringName("immunity_hit_uv_%d" % slot_index),hit_uv)
	_set_war_immunity_material_parameter(StringName("immunity_seed_%d" % slot_index),fx_seed)
	_set_war_immunity_material_parameter(StringName("immunity_progress_%d" % slot_index),clampf(progress,0.0,1.0))


# ================================
# 战争女神音效
# ================================
func _configure_war_audio(player:AudioStreamPlayer2D,volume_db_value:float) -> void:
	if player == null:
		return
	player.volume_db = volume_db_value
	player.max_distance = maxf(war_sfx_max_distance,50.0)
	player.attenuation = maxf(war_sfx_attenuation,0.05)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"


func _play_war_one_shot_local(
	stream_value:AudioStream,
	position_value:Vector2,
	volume_db_value:float,
	pitch_value:float = 1.0
) -> void:
	if stream_value == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer2D.new()
	_war_audio_serial += 1
	player.name = "WarGoddessOneShot_%d" % _war_audio_serial
	player.top_level = true
	player.stream = stream_value
	_configure_war_audio(player,volume_db_value)
	player.pitch_scale = maxf(pitch_value,0.05)
	add_child(player,true)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _play_war_sword_hit_networked(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_play_war_sword_hit_rpc.rpc(position_value)
	else:
		_play_war_sword_hit_rpc(position_value)


@rpc("authority","call_local","unreliable")
func _play_war_sword_hit_rpc(position_value:Vector2) -> void:
	_play_war_one_shot_local(SFX_WAR_SWORD_HIT,position_value,sword_hit_sfx_volume_db,randf_range(0.97,1.03))


func play_war_burn_tick_sfx(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_play_war_burn_tick_sfx_rpc.rpc(position_value)
	else:
		_play_war_burn_tick_sfx_rpc(position_value)


@rpc("authority","call_local","unreliable")
func _play_war_burn_tick_sfx_rpc(position_value:Vector2) -> void:
	_play_war_one_shot_local(SFX_BURN_TICK,position_value,burn_tick_sfx_volume_db,randf_range(0.97,1.04))


func _play_war_hit_sfx(raw_damage:float) -> void:
	if Hit_Audio.is_empty():
		return
	var params:Dictionary = {"volume":clampf(raw_damage - 40.0,-18.0,2.0),"pitch":randf_range(0.96,1.04)}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(Hit_Audio,params,true)
	else:
		Audios.play_sfx(Hit_Audio,params,true)


# ============================================================
# 程序化人物与攻击绘制
# ============================================================
func _draw() -> void:
	var local_scale:float = _local_scale_safe()
	# V51：形态2不再在人物身上绘制范围/光环。真实近战与远程索敌范围仍由碰撞形状负责。
	if _war_attack_visual_left <= 0.0 or WAR_GODDESS_SWORD_TEXTURE == null:
		return
	var progress:float = 1.0 - _war_attack_visual_left / maxf(_war_attack_visual_total,0.001)
	var sweep:float = lerpf(-0.80,0.80,smoothstep(0.0,1.0,progress))
	var angle:float = _war_attack_visual_angle + sweep
	var sword_length_world:float = melee_range * (form2_melee_range_multiplier if _war_attack_visual_form2 else 1.0)
	var origin:Vector2 = Vector2(8.0,0.0).rotated(_war_attack_visual_angle) / local_scale
	# 用户提供的 80x80 剑图，非透明内容从约 (35,45) 的剑柄延伸到右上刀尖。
	# 先把素材自身 -44° 的方向校正到 +X，再跟随真实挥剑方向旋转。
	var sword_scale:float = (sword_length_world / 61.5) / local_scale
	var texture_pivot:Vector2 = Vector2(35.0,45.0)
	var texture_direction_fix:float = deg_to_rad(44.0)
	for index:int in range(3):
		var trail_angle:float = angle - float(index + 1) * 0.10
		draw_set_transform(origin,trail_angle + texture_direction_fix,Vector2.ONE * sword_scale)
		draw_texture(WAR_GODDESS_SWORD_TEXTURE,-texture_pivot,Color(1.0,0.38,0.08,0.15 - float(index) * 0.035))
	# 当前刀本体最后绘制，固定 100% 不透明。
	draw_set_transform(origin,angle + texture_direction_fix,Vector2.ONE * sword_scale)
	draw_texture(WAR_GODDESS_SWORD_TEXTURE,-texture_pivot,Color.WHITE)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)


func _build_war_goddess_texture() -> Texture2D:
	var img := Image.create(192,192,false,Image.FORMAT_RGBA8)
	img.fill(Color(0.0,0.0,0.0,0.0))
	# 长发
	_preview_circle(img,96,50,31,Color(0.18,0.05,0.04,1.0))
	_preview_rect(img,66,45,126,119,Color(0.20,0.045,0.035,1.0))
	# 脸
	_preview_circle(img,96,49,20,Color(0.90,0.69,0.54,1.0))
	# 红黑铠甲
	_preview_rect(img,65,72,127,142,Color(0.16,0.055,0.06,1.0))
	_preview_rect(img,75,78,117,132,Color(0.42,0.07,0.055,1.0))
	_preview_rect(img,58,80,72,124,Color(0.30,0.06,0.055,1.0))
	_preview_rect(img,120,80,134,124,Color(0.30,0.06,0.055,1.0))
	# 腿与披风
	_preview_rect(img,76,138,92,174,Color(0.10,0.08,0.10,1.0))
	_preview_rect(img,100,138,116,174,Color(0.10,0.08,0.10,1.0))
	_preview_triangle(img,58,116,134,116,96,180,Color(0.34,0.045,0.035,0.92))
	# 金色饰边
	_preview_line(img,69,81,123,81,Color(0.93,0.62,0.16,1.0),3)
	_preview_line(img,96,82,96,128,Color(0.93,0.62,0.16,1.0),2)
	# 长剑，朝右上
	_preview_line(img,116,112,167,39,Color(0.88,0.92,0.98,1.0),5)
	_preview_line(img,116,112,167,39,Color(1.0,0.57,0.13,1.0),2)
	_preview_line(img,107,108,125,121,Color(0.95,0.68,0.20,1.0),4)
	return ImageTexture.create_from_image(img)


func _preview_rect(img:Image,x0:int,y0:int,x1:int,y1:int,color:Color) -> void:
	for y:int in range(maxi(y0,0),mini(y1,img.get_height())):
		for x:int in range(maxi(x0,0),mini(x1,img.get_width())):
			img.set_pixel(x,y,color)


func _preview_circle(img:Image,cx:int,cy:int,radius:int,color:Color) -> void:
	var r2:int = radius * radius
	for y:int in range(maxi(cy-radius,0),mini(cy+radius+1,img.get_height())):
		for x:int in range(maxi(cx-radius,0),mini(cx+radius+1,img.get_width())):
			var dx:int = x-cx
			var dy:int = y-cy
			if dx*dx + dy*dy <= r2:
				img.set_pixel(x,y,color)


func _preview_line(img:Image,x0:int,y0:int,x1:int,y1:int,color:Color,width:int) -> void:
	var steps:int = maxi(maxi(absi(x1-x0),absi(y1-y0)),1)
	for i:int in range(steps+1):
		var t:float = float(i)/float(steps)
		_preview_circle(img,roundi(lerpf(x0,x1,t)),roundi(lerpf(y0,y1,t)),maxi(width,1),color)


func _preview_triangle(img:Image,x1:int,y1:int,x2:int,y2:int,x3:int,y3:int,color:Color) -> void:
	var min_x:int = maxi(mini(x1,mini(x2,x3)),0)
	var max_x:int = mini(maxi(x1,maxi(x2,x3)),img.get_width()-1)
	var min_y:int = maxi(mini(y1,mini(y2,y3)),0)
	var max_y:int = mini(maxi(y1,maxi(y2,y3)),img.get_height()-1)
	var a:=Vector2(x1,y1)
	var b:=Vector2(x2,y2)
	var c:=Vector2(x3,y3)
	var denom:float = (b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
	if absf(denom) <= 0.0001:
		return
	for y:int in range(min_y,max_y+1):
		for x:int in range(min_x,max_x+1):
			var p:=Vector2(x,y)
			var w1:float = ((b.y-c.y)*(p.x-c.x)+(c.x-b.x)*(p.y-c.y))/denom
			var w2:float = ((c.y-a.y)*(p.x-c.x)+(a.x-c.x)*(p.y-c.y))/denom
			var w3:float = 1.0-w1-w2
			if w1 >= 0.0 and w2 >= 0.0 and w3 >= 0.0:
				img.set_pixel(x,y,color)
