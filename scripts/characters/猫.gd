extends ball

@export_category("外观")
@export var normal_texture:Texture2D
@export var hiss_texture:Texture2D
@export var scratch_texture:Texture2D
@export_range(0.05,2.0,0.05) var hiss_visual_duration:float = 0.45
@export_range(0.05,2.0,0.05) var scratch_visual_duration:float = 0.28

@export_category("九条命")
@export_range(1,20,1) var total_lives:int = 9
@export_range(0.1,10.0,0.1) var revive_delay:float = 1.4

@export_category("抓挠")
@export_range(1.0,500.0,1.0) var scratch_range:float = 105.0
@export_range(0.0,500.0,1.0) var scratch_knockback_distance:float = 85.0
@export_range(0.0,2000.0,10.0) var scratch_knockback_speed:float = 720.0
@export var scratch_audio:String = ""

@export_category("哈气")
@export_range(1.0,800.0,1.0) var hiss_detect_range:float = 165.0
@export_range(0.1,30.0,0.1) var hiss_cooldown:float = 5.5
@export_range(0.0,500.0,1.0) var hiss_knockback_distance:float = 210.0
@export_range(0.0,2500.0,10.0) var hiss_knockback_speed:float = 800.0
@export_range(0.0,10.0,0.1) var hiss_empower_duration:float = 2.0
@export var hiss_audio:String = "蛇叫"

var remaining_lives:int = 9
var _reviving:bool = false
var _scratch_cooldown_left:float = 0.0
var _hiss_cooldown_left:float = 0.0
var _hiss_empower_left:float = 0.0
var _scratch_active:bool = false
var _visual_token:int = 0

var _saved_body_layer:int = 0
var _saved_body_mask:int = 0
var _saved_hitbox_layer:int = 0
var _saved_hitbox_mask:int = 0
var _saved_hurtbox_layer:int = 0
var _saved_hurtbox_mask:int = 0
var _saved_hitbox_monitoring:bool = true
var _saved_hitbox_monitorable:bool = true
var _saved_hurtbox_monitoring:bool = true
var _saved_hurtbox_monitorable:bool = true


func get_health_threshold_values() -> PackedFloat32Array:
	# 还有额外命时，0HP 不是真正死亡，而是进入复活流程。
	if remaining_lives > 1:
		return PackedFloat32Array([0.0])
	return PackedFloat32Array()


func _ready() -> void:
	# 猫不用基础碰撞自动普攻，抓挠由范围检测主动触发。
	# 场景默认已经是普通猫纹理；这里保底，避免资源被单独实例化时丢图。
	var sprite:Sprite2D = $Graphics/Image
	if normal_texture != null:
		sprite.texture = normal_texture
	Can_Attack = false
	Can_Skill = false
	remaining_lives = maxi(total_lives,1)
	super._ready()

	_saved_body_layer = collision_layer
	_saved_body_mask = collision_mask
	_saved_hitbox_layer = self_hitbox.collision_layer
	_saved_hitbox_mask = self_hitbox.collision_mask
	_saved_hurtbox_layer = self_hurtbox.collision_layer
	_saved_hurtbox_mask = self_hurtbox.collision_mask
	_saved_hitbox_monitoring = self_hitbox.monitoring
	_saved_hitbox_monitorable = self_hitbox.monitorable
	_saved_hurtbox_monitoring = self_hurtbox.monitoring
	_saved_hurtbox_monitorable = self_hurtbox.monitorable


func _show_action_texture(texture:Texture2D,duration:float) -> void:
	if texture == null or not (image is Sprite2D):
		return

	_visual_token += 1
	var token:int = _visual_token
	(image as Sprite2D).texture = texture
	_restore_normal_texture_after(maxf(duration,0.05),token)


func _restore_normal_texture_after(delay:float,token:int) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self) or token != _visual_token:
		return
	if image is Sprite2D and normal_texture != null:
		(image as Sprite2D).texture = normal_texture


func _set_normal_texture() -> void:
	_visual_token += 1
	if image is Sprite2D and normal_texture != null:
		(image as Sprite2D).texture = normal_texture


func _is_forced_map_death() -> bool:
	return bool(get_meta(&"__out_of_bounds_forced_death",false))


func get_next_state(state:State) -> int:
	if _is_forced_map_death():
		remaining_lives = 0
		_reviving = false
		return super(state)

	if _reviving:
		return -1

	# 除普通攻击外，毒/地图机关等直接把 health 写到 0 时也必须消耗一条命。
	if health <= 0 and remaining_lives > 1:
		remaining_lives -= 1
		_start_revive_cycle()
		return -1

	return super(state)


func tick_physics(state:State,delta:float) -> void:
	if _reviving:
		velocity = Vector2.ZERO
		return

	_scratch_cooldown_left = maxf(_scratch_cooldown_left - delta,0.0)
	_hiss_cooldown_left = maxf(_hiss_cooldown_left - delta,0.0)
	_hiss_empower_left = maxf(_hiss_empower_left - delta,0.0)

	if is_multiplayer_authority():
		if _hiss_cooldown_left <= 0.0 and _has_target_in_range(hiss_detect_range):
			_do_hiss()

		if _scratch_cooldown_left <= 0.0 and _has_target_in_range(scratch_range):
			_do_scratch()

	super.tick_physics(state,delta)


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	# 身体普通接触仍然可以触发 hitbox 检测，但只有真正抓挠时才造成伤害。
	if not _scratch_active:
		return

	super(hurt)

	var target:ball = _hurtbox_target_ball(hurt)
	if (
		_hiss_empower_left > 0.0
		and target != null
		and target.health > 0
	):
		var push_dir:Vector2 = target.global_position - global_position
		if push_dir.length_squared() <= 0.000001:
			push_dir = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
		target.apply_knockback(
			push_dir.normalized(),
			scratch_knockback_distance,
			scratch_knockback_speed,
			0.4,
			0.0,
			{"source":self,"stop_on_character":true}
		)


func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _reviving:
		return

	super(damage,ignore_block)

	if _is_forced_map_death():
		remaining_lives = 0
		return

	# 前 8 次致死都进入“尸体等待”，不会让状态机真正进入 Die。
	if health <= 0 and remaining_lives > 1:
		remaining_lives -= 1
		_start_revive_cycle()
	elif health <= 0:
		remaining_lives = 0


func _set_revive_collisions_enabled(enabled:bool) -> void:
	# Area2D 正在发送 area/body entered/exited 信号时不能立即切 monitoring/monitorable。
	# 统一 deferred 到安全时机，避免 “Function blocked during in/out signal” 报错。
	if enabled:
		set_deferred("collision_layer",_saved_body_layer)
		set_deferred("collision_mask",_saved_body_mask)
		self_hitbox.set_deferred("collision_layer",_saved_hitbox_layer)
		self_hitbox.set_deferred("collision_mask",_saved_hitbox_mask)
		self_hitbox.set_deferred("monitoring",_saved_hitbox_monitoring)
		self_hitbox.set_deferred("monitorable",_saved_hitbox_monitorable)
		self_hurtbox.set_deferred("collision_layer",_saved_hurtbox_layer)
		self_hurtbox.set_deferred("collision_mask",_saved_hurtbox_mask)
		self_hurtbox.set_deferred("monitoring",_saved_hurtbox_monitoring)
		self_hurtbox.set_deferred("monitorable",_saved_hurtbox_monitorable)
	else:
		set_deferred("collision_layer",0)
		set_deferred("collision_mask",0)
		self_hitbox.set_deferred("collision_layer",0)
		self_hitbox.set_deferred("collision_mask",0)
		self_hitbox.set_deferred("monitoring",false)
		self_hitbox.set_deferred("monitorable",false)
		self_hurtbox.set_deferred("collision_layer",0)
		self_hurtbox.set_deferred("collision_mask",0)
		self_hurtbox.set_deferred("monitoring",false)
		self_hurtbox.set_deferred("monitorable",false)


func _start_revive_cycle() -> void:
	if _reviving or _is_forced_map_death():
		return
	_reviving = true
	can_restore_health = false
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_set_revive_collisions_enabled(false)

	# 尸体必须留在原地：只隐藏血条，不再隐藏 Graphics。
	health_bar.visible = false

	if Dead_Audio != "":
		Audios.play_sfx(Dead_Audio,{},true)

	call_deferred("_revive_after_delay")


func _revive_after_delay() -> void:
	await get_tree().create_timer(maxf(revive_delay,0.05)).timeout
	if not is_instance_valid(self) or _is_forced_map_death():
		return

	_set_revive_collisions_enabled(true)
	health_bar.visible = true

	can_restore_health = true
	health_bar.suppress_floating_text = true
	health = Max_health
	health_bar.suppress_floating_text = false
	direction = Vector2.from_angle(randf_range(0.0,TAU))
	_set_normal_texture()
	_reviving = false


func _has_target_in_range(radius:float) -> bool:
	return not _targets_in_range(radius).is_empty()


func _targets_in_range(radius:float) -> Array[ball]:
	var result:Array[ball] = []
	var radius_sq:float = radius * radius
	for node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == self or not target.is_combat_targetable():
			continue
		if Team != "" and target.Team != "" and Team == target.Team:
			continue
		if global_position.distance_squared_to(target.global_position) <= radius_sq:
			result.append(target)
	return result


func _do_scratch() -> void:
	var targets:Array[ball] = _targets_in_range(scratch_range)
	if targets.is_empty():
		return

	_show_action_texture(scratch_texture,scratch_visual_duration)
	_scratch_cooldown_left = maxf(Attack_Cooling,0.05)
	_scratch_active = true
	var hit_any:bool = false
	for target in targets:
		if self_hitbox.try_hit_hurtbox(target.self_hurtbox):
			hit_any = true
	_scratch_active = false

	if hit_any and scratch_audio != "":
		Audios.play_sfx.rpc(scratch_audio,{},true)


func _do_hiss() -> void:
	var targets:Array[ball] = _targets_in_range(hiss_detect_range)
	if targets.is_empty():
		return

	_show_action_texture(hiss_texture,hiss_visual_duration)
	_hiss_cooldown_left = maxf(hiss_cooldown,0.05)
	_hiss_empower_left = maxf(hiss_empower_duration,0.0)

	for target in targets:
		var push_dir:Vector2 = target.global_position - global_position
		if push_dir.length_squared() <= 0.000001:
			push_dir = Vector2.from_angle(randf_range(0.0,TAU))
		target.apply_knockback(
			push_dir.normalized(),
			hiss_knockback_distance,
			hiss_knockback_speed,
			0.55,
			0.0,
			{"source":self,"stop_on_character":true}
		)

	if hiss_audio != "":
		Audios.play_sfx.rpc(hiss_audio,{},true)


func Die() -> void:
	_set_revive_collisions_enabled(false)
	super()
	# 最后一条命也先保留尸体一小段时间，再真正删除。
	await get_tree().create_timer(1.4).timeout
	if is_instance_valid(self):
		Game.free_node(self)


# AI 通用威胁接口：抓挠是近身圆形伤害；哈气是控制场。
func get_ai_attack_threats(receiver:ball) -> Array:
	var result:Array = []
	if receiver == null or not is_instance_valid(receiver):
		return result
	if receiver == self or receiver.Type != Ball_Type.Ball or receiver.health <= 0:
		return result
	if Team != "" and receiver.Team != "" and Team == receiver.Team:
		return result
	var distance:float = global_position.distance_to(receiver.global_position)
	if distance <= scratch_range * 1.35 and _scratch_cooldown_left <= 0.22:
		result.append({
			"shape":"circle",
			"position":global_position,
			"radius":maxf(scratch_range,1.0),
			"danger_in":maxf(_scratch_cooldown_left,0.0),
			"danger_duration":maxf(scratch_visual_duration,0.05),
			"damage":attack_damage(),
			"kind":"cat_scratch",
			"source":self,
		})
	if distance <= hiss_detect_range * 1.35 and _hiss_cooldown_left <= 0.22:
		result.append({
			"shape":"circle",
			"position":global_position,
			"radius":maxf(hiss_detect_range,1.0),
			"danger_in":maxf(_hiss_cooldown_left,0.0),
			"danger_duration":maxf(hiss_visual_duration,0.05),
			"damage":0.0,
			"control":1.0,
			"kind":"cat_hiss",
			"source":self,
		})
	return result
