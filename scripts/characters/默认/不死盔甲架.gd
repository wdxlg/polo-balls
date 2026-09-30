extends "res://scripts/characters/默认/盔甲架.gd"

# 真正的无限血版本：和普通盔甲架一样承受伤害，只是生命永不下降，用现有 Health_bar 的 INF 显示。
# 被吸收的伤害记入 absorbed_health_loss，吸血、荆棘、命中反馈、伤害统计等按“实际掉血”结算的机制
# 与打普通盔甲架一致；只有 INF 级伤害或特定机制（出界等强制死亡）能真正击杀。
# Max_health/health 保持一个很小的有效值，避免用“超大整数”伪装无限血。
const IMMORTAL_HEALTH:int = 1
# V65：11 位数及以上伤害视为 INF 级破限伤害，可真正击杀无限血目标。
const INFINITE_DAMAGE_KILL_THRESHOLD:float = 10_000_000_000.0
# 视觉反馈（爆射线/镜头）使用的有界数值；吸收量、破限击杀和伤害跳字的原始值不受限制。
const IMMORTAL_VISUAL_DAMAGE_CAP:float = 100000.0
var _infinite_health_broken:bool = false
@export_range(10.0,2000.0,10.0) var immortal_impact_reference_health:float = 100.0


func get_impact_reference_health() -> float:
	return maxf(immortal_impact_reference_health,1.0)


# 无限生命的已确认命中使用吸收的伤害，不伪造真实掉血。
func get_received_hit_feedback_damage(raw_damage:float,_health_before:float) -> float:
	return 0.0 if is_nan(raw_damage) else clampf(raw_damage,0.0,IMMORTAL_VISUAL_DAMAGE_CAP)


# 对应普通盔甲架 health setter 里的反馈：受伤镜头 + 受伤音效。
# 爆射线与 MC 受击音效和普通目标一样由命中结算方按“掉血”生成（它们读取 absorbed_health_loss）。
func _emit_immortal_impact(damage:float) -> void:
	if is_nan(damage) or damage <= 0.0 or not is_node_ready() or not is_combat_runtime_active():
		return
	var visual_damage:float = minf(damage,IMMORTAL_VISUAL_DAMAGE_CAP)
	_notify_damage_camera_feedback(visual_damage)
	# 沿用普通盔甲架已有的受击音效概率和冷却。
	super.on_actual_health_damage_received(visual_damage,float(health))


# INF 级破限一击没有吸收量可供结算方读取，由这里补一次爆射线。
func _emit_immortal_burst(damage:float,origin:Vector2) -> void:
	if is_nan(damage) or damage <= 0.0 or not is_node_ready() or not is_combat_runtime_active():
		return
	var visual_damage:float = minf(damage,IMMORTAL_VISUAL_DAMAGE_CAP)
	var source_position:Vector2 = origin if origin.is_finite() else global_position - Vector2.RIGHT
	notify_hit_burst_feedback(source_position,visual_damage,visual_damage,0.0,
		_positional_damage_feedback_coverage(),int(Time.get_ticks_usec()) ^ int(get_instance_id()),
		(global_position - source_position).normalized())


# 普通伤害全部吸收：记入 absorbed_health_loss，调用方比较 before/after 时就能得到完整掉血。
func _record_absorbed_damage(damage:float) -> float:
	if is_nan(damage) or damage <= 0.0 or _is_infinite_damage(damage) or _infinite_health_broken:
		return 0.0
	absorbed_health_loss += damage
	return damage


func _is_infinite_damage(damage:float) -> bool:
	return is_inf(damage) or damage >= INFINITE_DAMAGE_KILL_THRESHOLD


func _break_infinite_health() -> void:
	if _infinite_health_broken:
		return
	_infinite_health_broken = true
	# 先退出 INF 血条显示，再静默把真实 1 HP 清到 0；真正的大伤害跳字已经单独生成。
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.suppress_floating_text = true
		if health_bar.has_method("set_invincible_display"):
			health_bar.call("set_invincible_display",false,false)
	health = 0
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.suppress_floating_text = false


func armor_stand_initial_max_health() -> int:
	return IMMORTAL_HEALTH


func _ready() -> void:
	super._ready()
	max_block = 0
	block = 0
	if default_properties != null:
		default_properties["Max_health"] = IMMORTAL_HEALTH
		default_properties["max_block"] = 0
	if health_bar != null and is_instance_valid(health_bar) and health_bar.has_method("set_invincible_display"):
		health_bar.call("set_invincible_display",true,false)


func can_receive_hit_contact(_incoming_hit:hitbox,_contact_hurtbox:hurtbox) -> bool:
	# 仍然算“命中”，这样碰撞、受击状态和攻击方逻辑正常；只是生命永远不会下降。
	return true


func can_receive_hit_from(_incoming_hit:hitbox) -> bool:
	return true


# INF 模式下 HealthBar 不会因为 health 变化自动生成伤害数字；
# 不死盔甲架又故意不扣真实生命，所以这里单独补“本次承受的伤害”跳字。
func _show_immortal_damage_text(damage:float) -> void:
	if is_nan(damage) or damage <= 0.0 or not is_multiplayer_authority():
		return
	_emit_immortal_impact(damage)
	if health_bar == null or not is_instance_valid(health_bar):
		return
	if not health_bar.has_method("_spawn_damage_text"):
		return
	# 真正 INF 不能先转 int；11 位数级别也直接把原始值交给 HealthBar，由它统一切换 INF 跳字。
	if _is_infinite_damage(damage):
		health_bar.call("_spawn_damage_text",damage,health_bar.health_bar)
		return
	var amount:int = maxi(int(round(damage)),1)
	health_bar.call("_spawn_damage_text",amount,health_bar.health_bar)


func receive_directional_damage(
	damage:float,
	source_position:Vector2,
	_incoming_direction:Vector2 = Vector2.ZERO,
	ignore_block:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	return receive_positional_damage(damage,source_position,ignore_block,null)


func receive_positional_damage(
	damage:float,
	_impact_position:Vector2,
	ignore_block:bool = false,
	_source:Node = null
) -> bool:
	if damage <= 0.0:
		return false
	var before_block:float = float(block)
	hit_white(ignore_block)
	_show_immortal_damage_text(damage)
	if _is_infinite_damage(damage):
		_emit_immortal_burst(damage,_positional_damage_feedback_origin(_impact_position,_source))
		_break_infinite_health()
		return true
	var absorbed:float = _record_absorbed_damage(damage)
	if absorbed > 0.0:
		# 与 ball.receive_positional_damage 相同的结算：MC 受击音效、爆射线、战斗伤害统计。
		var visual_before:float = float(health) + minf(absorbed,IMMORTAL_VISUAL_DAMAGE_CAP)
		_emit_positional_damage_feedback(minf(damage,IMMORTAL_VISUAL_DAMAGE_CAP),_impact_position,_source,visual_before,before_block,ignore_block)
		if _source != null and Game.has_method("report_combat_damage"):
			Game.report_combat_damage(_source,self,absorbed,float(health) + absorbed)
	return true


func receive_spatial_damage(
	damage:float,
	_damage_space:Variant,
	ignore_block:bool = false,
	_raw_health:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	var point:Vector2 = global_position
	var source:Node = null
	if _damage_space is Vector2:
		point = _damage_space
	elif _damage_space is Dictionary:
		if _damage_space.get("point") is Vector2:
			point = _damage_space["point"]
		if _damage_space.get("source") is Node:
			source = _damage_space["source"]
	return receive_positional_damage(damage,point,ignore_block,source)


func take_damage(damage:float,_ignore_block:bool = false) -> void:
	# 兼容仍然直接走 take_damage() 的伤害入口（含 Hitbox 命中）。普通伤害记为吸收；INF 级伤害可破限击杀。
	_show_immortal_damage_text(damage)
	if _is_infinite_damage(damage):
		_break_infinite_health()
		return
	_record_absorbed_damage(damage)


func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	# 兼容旧技能直接 target.health -= damage：读取 ball 在完整 setter 期间保留的请求扣血值。
	# 这样即使真实生命只有 1，也能识别 10,000,000,000+ 的破限伤害。
	if _infinite_health_broken:
		return
	var requested_damage:float = 0.0
	if has_method("current_health_damage_request_amount"):
		requested_damage = float(call("current_health_damage_request_amount"))
	if _is_infinite_damage(requested_damage):
		_show_immortal_damage_text(requested_damage)
		_break_infinite_health()
		return
	if actual_health_damage > 0.0:
		var shown:float = maxf(requested_damage,actual_health_damage)
		# 真实生命被写低时恢复它，整笔记为吸收；计时模式不死已在 setter 里记过吸收量，不重复记。
		if float(health) < health_before:
			_record_absorbed_damage(shown)
		health = maxi(int(ceil(health_before)),IMMORTAL_HEALTH)
		_show_immortal_damage_text(shown)


func get_next_state(state:State) -> int:
	if health <= 0 and not _infinite_health_broken:
		health = IMMORTAL_HEALTH
	return super.get_next_state(state)


func Die() -> void:
	# 普通伤害下仍然永生；只有 INF 级伤害破限后才允许进入父类死亡流程。
	if _infinite_health_broken:
		super.Die()
		return
	if health <= 0:
		health = IMMORTAL_HEALTH
	return
