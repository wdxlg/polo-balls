extends ball

# ============================================================
# 军官
# - 实际生命值受到伤害 -> 怒气百分比上升
# - 越愤怒，人物和百分比文字越红
# - 达到阈值切换为生气图片
# - 100% 播放警报，核弹从天上落向目标并爆炸
# ============================================================

@export_category("军官 - 怒气")
@export var normal_texture:Texture2D
@export var angry_texture:Texture2D
@export_range(1.0, 5000.0, 1.0) var damage_for_100_percent:float = 600.0
@export_range(0.0, 100.0, 1.0) var angry_at_percent:float = 55.0
@export var rage_red_color:Color = Color(1.0, 0.16, 0.12, 1.0)
@export_range(0.0, 1.0, 0.01) var rage_color_mix_at_100:float = 0.82
@export_range(0.0, 10.0, 0.1) var rage_decay_delay_after_damage:float = 1.5
@export_range(0.0, 100.0, 0.1) var rage_decay_percent_per_second:float = 5.0

@export_category("军官 - 核弹")
@export var nuke_texture:Texture2D
@export_enum("当前位置", "最近敌人") var nuke_target_mode:int = 1
@export_range(0.2, 5.0, 0.05) var nuke_fall_duration:float = 1.45
@export_range(100.0, 2000.0, 10.0) var nuke_start_height:float = 650.0
@export_range(0.01, 1.0, 0.01) var nuke_sprite_scale:float = 0.10
@export_range(10.0, 1200.0, 5.0) var nuke_explosion_radius:float = 320.0
@export_range(0.0, 10.0, 0.05) var nuke_damage_multiplier:float = 1.0
@export var nuke_ignore_block:bool = true
@export_range(0.1, 2.0, 0.05) var nuke_explosion_visual_duration:float = 0.65
@export_range(0.0, 1000.0, 5.0) var nuke_camera_shake:float = 220.0

@onready var rage_label:Label = $RageLabel
@onready var warning_audio:AudioStreamPlayer2D = $NukeWarningAudio
@onready var explosion_audio_template:AudioStreamPlayer2D = $NukeExplosionAudio

var rage_percent:float = 0.0
var nuke_active:bool = false
var rage_decay_wait_left:float = 0.0

# 核弹已经脱离军官节点、挂到 World 后，不能再依赖“删除军官”顺带清理。
# 用 cycle id 取消已经排队但尚未发射/命中的旧回调，并保存当前落弹 Tween 和节点。
var _nuke_cycle_id:int = 0
var _nuke_fall_tween:Tween = null
var _owned_nuke_nodes:Array[Node] = []


func _ready() -> void:
	super._ready()
	_ensure_audio_streams()
	_update_rage_visual()


func _exit_tree() -> void:
	# 不只死亡：Reset、换场景、外部直接 queue_free 军官时也要取消其核弹。
	_cancel_active_nuke()


func tick_physics(state:State, delta:float) -> void:
	super.tick_physics(state, delta)

	if not is_multiplayer_authority():
		return

	_process_rage_decay(delta)


func _process_rage_decay(delta:float) -> void:
	if nuke_active:
		return

	if rage_percent <= 0.0:
		if rage_percent != 0.0:
			rage_percent = 0.0
			_update_rage_visual()
		return

	if state_machine and state_machine.current_state == State.Die:
		return

	if rage_decay_wait_left > 0.0:
		rage_decay_wait_left = maxf(
			rage_decay_wait_left - delta,
			0.0
		)
		return

	if rage_decay_percent_per_second <= 0.0:
		return

	var old_rage:float = rage_percent

	rage_percent = maxf(
		rage_percent
		- rage_decay_percent_per_second * delta,
		0.0
	)

	# 只有数值真正变化时才刷新外观。
	if absf(rage_percent - old_rage) > 0.001:
		_update_rage_visual()


func _ensure_audio_streams() -> void:
	# 用户修改过场景后如果 Inspector 里的 stream 被清空，
	# 仍然自动从上一版角色包路径恢复。
	if (
		warning_audio
		and warning_audio.stream == null
		and ResourceLoader.exists("res://audio/sfx/军官/核弹警报.wav")
	):
		warning_audio.stream = load(
			"res://audio/sfx/军官/核弹警报.wav"
		)

	if (
		explosion_audio_template
		and explosion_audio_template.stream == null
		and ResourceLoader.exists("res://audio/characters/军官/核弹爆炸.wav")
	):
		explosion_audio_template.stream = load(
			"res://audio/characters/军官/核弹爆炸.wav"
		)


# 只按“真正扣掉的生命”增加怒气。
# 被格挡、减伤掉的部分不会虚增百分比。
func take_damage(damage:float, ignore_block:bool = false) -> void:
	var old_health:float = float(health)

	super.take_damage(
		damage,
		ignore_block
	)

	if not is_multiplayer_authority():
		return

	var actual_health_damage:float = maxf(
		old_health - float(health),
		0.0
	)

	if actual_health_damage <= 0.0:
		return

	_add_rage_from_damage(
		actual_health_damage
	)


# V181：有些持续帧伤（Sans 骨头/龙骨炮/KR）为了保证严格每次 1 HP，
# 会直接修改 health，而不会调用 take_damage()。这类伤害已经在来源侧完成扣血，
# 所以这里只把“真实已损失生命”计入怒气，绝不能再次调用 take_damage()。
func notify_external_actual_health_damage(actual_damage:float, _source:Node = null) -> void:
	if not is_multiplayer_authority():
		return
	if actual_damage <= 0.0:
		return
	_add_rage_from_damage(actual_damage)


func _add_rage_from_damage(actual_damage:float) -> void:
	if nuke_active:
		return

	var percent_gain:float = (
		actual_damage
		/ maxf(damage_for_100_percent, 1.0)
		* 100.0
	)

	rage_percent = clampf(
		rage_percent + percent_gain,
		0.0,
		100.0
	)

	# 每次真正受伤后重新等待一段时间，再开始衰减。
	rage_decay_wait_left = rage_decay_delay_after_damage

	_update_rage_visual()

	if rage_percent >= 100.0:
		_trigger_nuke()


func _update_rage_visual() -> void:
	var t:float = clampf(
		rage_percent / 100.0,
		0.0,
		1.0
	)

	var current_color:Color = Color.WHITE.lerp(
		rage_red_color,
		t
	)

	if rage_label:
		rage_label.text = "%d%%" % int(round(rage_percent))
		rage_label.add_theme_color_override(
			"font_color",
			current_color
		)

	if image:
		# 你的 ball.gd / Set_RGB_Color shader 已经有专门的实例染色通道。
		# 直接走这个通道，比上一版只改 self_modulate 更可靠。
		image_color = current_color
		image_color_mix = clampf(
			t * rage_color_mix_at_100,
			0.0,
			1.0
		)
		set_image_color()

		# 保持 CanvasItem 本身为白色，避免 Shader 染色再乘一次 self_modulate。
		image.self_modulate = Color.WHITE

	if image is Sprite2D:
		var sprite:Sprite2D = image
		var wanted_texture:Texture2D = normal_texture

		if (
			rage_percent >= angry_at_percent
			and angry_texture != null
		):
			wanted_texture = angry_texture

		if wanted_texture != null and sprite.texture != wanted_texture:
			sprite.texture = wanted_texture
			_refit_character_visual_only()


func _refit_character_visual_only() -> void:
	var auto_fit := get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call("apply_visual_fit_only")



# 军官原先没有覆盖 Die()，而公共 ball.Die() 只播放死亡音效，
# 不会自动释放角色节点。因此军官死亡后会一直留在场上。
func Die() -> void:
	# 先取消核弹，再进入公共死亡流程。
	# 如果核弹已经从天上开始掉落，这里也会立即删掉，不允许军官死后继续留场。
	_cancel_active_nuke()

	super.Die()

	rage_decay_wait_left = 0.0

	# 和项目里其他会自行消失的角色保持一致：
	# 留一个很短的死亡展示时间，然后通过 Game.free_node 统一删除。
	await get_tree().create_timer(1.0).timeout

	if is_instance_valid(self):
		Game.free_node(self)


func _cancel_active_nuke() -> void:
	# 令所有已经绑定旧 cycle id 的延迟/落地回调失效。
	_nuke_cycle_id += 1
	nuke_active = false

	if warning_audio and warning_audio.playing:
		warning_audio.stop()

	if _nuke_fall_tween != null and _nuke_fall_tween.is_valid():
		_nuke_fall_tween.kill()
	_nuke_fall_tween = null

	for node:Node in _owned_nuke_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_owned_nuke_nodes.clear()


func _trigger_nuke() -> void:
	if nuke_active:
		return

	# 已经死亡时不再新启动核弹。
	if health <= 0:
		return

	nuke_active = true
	rage_percent = 100.0
	_nuke_cycle_id += 1
	var cycle_id:int = _nuke_cycle_id
	_update_rage_visual()

	if warning_audio and warning_audio.stream:
		warning_audio.play()

	var target_position:Vector2 = _get_nuke_target_position()

	# 让警报先响一下，再真正落弹。SceneTreeTimer 本身不能取消，
	# 所以回调携带 cycle id；军官死亡/Reset 后旧回调只会直接 return。
	var delay_timer:SceneTreeTimer = get_tree().create_timer(0.38)
	delay_timer.timeout.connect(
		_launch_nuke.bind(target_position, cycle_id)
	)


func _get_nuke_target_position() -> Vector2:
	if (
		nuke_target_mode == 1
		and is_instance_valid(Nearest_Enemy)
		and Nearest_Enemy is Node2D
	):
		return combat_target_position(Nearest_Enemy)

	return global_position


func _launch_nuke(target_position:Vector2, cycle_id:int) -> void:
	if not is_inside_tree():
		return
	if cycle_id != _nuke_cycle_id or not nuke_active or health <= 0:
		return
	if state_machine and state_machine.current_state == State.Die:
		return

	var world:Node = get_tree().current_scene
	if world == null:
		_finish_nuke_cycle()
		return

	var bomb := Sprite2D.new()
	bomb.name = "OfficerNuke"
	bomb.texture = nuke_texture
	bomb.z_index = 1000
	bomb.rotation = PI
	bomb.scale = Vector2.ONE * nuke_sprite_scale
	bomb.global_position = (
		target_position
		+ Vector2(0.0, -nuke_start_height)
	)

	world.add_child(bomb)
	bomb.add_to_group("BattleTransient")
	bomb.add_to_group("OfficerNuke")
	bomb.set_meta("officer_nuke_owner", get_instance_id())
	# RL 只读取机制，不读取“军官”名字：核弹节点声明目标、半径、伤害和落地延迟。
	bomb.set_meta("ai_threat_target", target_position)
	bomb.set_meta("ai_threat_radius", nuke_explosion_radius)
	bomb.set_meta("ai_threat_damage", attack_damage(nuke_damage_multiplier))
	bomb.set_meta("ai_threat_delay", nuke_fall_duration)
	_owned_nuke_nodes.append(bomb)

	var fall_tween:Tween = world.create_tween()
	_nuke_fall_tween = fall_tween
	fall_tween.set_trans(Tween.TRANS_QUAD)
	fall_tween.set_ease(Tween.EASE_IN)

	fall_tween.tween_property(
		bomb,
		"global_position",
		target_position,
		nuke_fall_duration
	)

	fall_tween.finished.connect(
		_on_nuke_impact.bind(
			bomb,
			target_position,
			cycle_id
		)
	)


func _on_nuke_impact(
	bomb:Sprite2D,
	target_position:Vector2,
	cycle_id:int
) -> void:
	# 军官在核弹下落途中死亡、Reset 或开始了新的 cycle 时，旧核弹不得爆炸。
	if cycle_id != _nuke_cycle_id or not nuke_active or health <= 0:
		if is_instance_valid(bomb):
			bomb.queue_free()
		_owned_nuke_nodes.erase(bomb)
		_nuke_fall_tween = null
		return

	var world:Node = get_tree().current_scene

	if is_instance_valid(bomb):
		bomb.queue_free()
	_owned_nuke_nodes.erase(bomb)
	_nuke_fall_tween = null

	if world == null:
		_finish_nuke_cycle()
		return

	_play_explosion_sound_at(
		world,
		target_position
	)

	_spawn_explosion_visual(
		world,
		target_position
	)

	if is_multiplayer_authority():
		_apply_nuke_damage(
			target_position
		)

	# world.gd 里本来就有这个镜头震动量，
	# 用动态 set/get 避免这里依赖 World 静态类型。
	var old_shake = world.get("camera_shake_amount")
	if old_shake != null:
		world.set(
			"camera_shake_amount",
			float(old_shake) + nuke_camera_shake
		)

	_finish_nuke_cycle()


func _play_explosion_sound_at(
	world:Node,
	target_position:Vector2
) -> void:
	if (
		explosion_audio_template == null
		or explosion_audio_template.stream == null
	):
		return

	var audio := AudioStreamPlayer2D.new()
	audio.name = "OfficerNukeExplosionAudio"
	audio.stream = explosion_audio_template.stream
	audio.volume_db = explosion_audio_template.volume_db
	audio.pitch_scale = explosion_audio_template.pitch_scale
	audio.global_position = target_position

	world.add_child(audio)
	audio.add_to_group("BattleTransient")
	audio.add_to_group("OfficerNuke")
	audio.set_meta("officer_nuke_owner", get_instance_id())

	audio.finished.connect(
		audio.queue_free
	)

	audio.play()


func _spawn_explosion_visual(
	world:Node,
	target_position:Vector2
) -> void:
	var holder := Node2D.new()
	holder.name = "OfficerNukeExplosion"
	holder.global_position = target_position
	holder.z_index = 999
	world.add_child(holder)
	holder.add_to_group("BattleTransient")
	holder.add_to_group("OfficerNuke")
	holder.set_meta("officer_nuke_owner", get_instance_id())

	var core := _create_circle(
		70.0,
		Color(1.0, 0.95, 0.62, 0.96)
	)
	var ring := _create_circle(
		70.0,
		Color(1.0, 0.22, 0.05, 0.78)
	)

	holder.add_child(ring)
	holder.add_child(core)

	core.scale = Vector2.ONE * 0.10
	ring.scale = Vector2.ONE * 0.15

	var final_scale:float = maxf(
		nuke_explosion_radius / 70.0,
		1.0
	)

	var tween:Tween = world.create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		core,
		"scale",
		Vector2.ONE * final_scale,
		nuke_explosion_visual_duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		ring,
		"scale",
		Vector2.ONE * final_scale * 1.15,
		nuke_explosion_visual_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		core,
		"modulate:a",
		0.0,
		nuke_explosion_visual_duration
	)

	tween.tween_property(
		ring,
		"modulate:a",
		0.0,
		nuke_explosion_visual_duration
	)

	tween.finished.connect(
		holder.queue_free
	)


func _create_circle(
	radius:float,
	color:Color
) -> Polygon2D:
	var polygon := Polygon2D.new()
	var points := PackedVector2Array()

	const POINT_COUNT:int = 48

	for i in range(POINT_COUNT):
		var angle:float = (
			TAU
			* float(i)
			/ float(POINT_COUNT)
		)
		points.append(
			Vector2(
				cos(angle),
				sin(angle)
			) * radius
		)

	polygon.polygon = points
	polygon.color = color
	return polygon


func _apply_nuke_damage(
	target_position:Vector2
) -> void:
	var targets:Array[Node] = (
		get_tree().get_nodes_in_group("Ball")
	)

	for node:Node in targets:
		if not node is ball:
			continue

		var target:ball = node

		# 军官自己不会被自己叫来的核弹炸死。
		if target == self:
			continue

		if not target.is_combat_targetable():
			continue

		var distance_to_blast:float = (
			target.global_position.distance_to(
				target_position
			)
		)

		if distance_to_blast > nuke_explosion_radius:
			continue

		# 沿用项目原来的队伤设置。
		if (
			not Game.Game_Settings.Have_Team_Damage
			and Team != ""
			and target.Team != ""
			and target.Team == Team
		):
			continue

		target.receive_spatial_damage(
			attack_damage(nuke_damage_multiplier),
			{
				"shape": "circle",
				"center": target_position,
				"radius": maxf(nuke_explosion_radius,1.0),
				"source": self,
			},
			nuke_ignore_block
		)


func _finish_nuke_cycle() -> void:
	nuke_active = false
	_nuke_fall_tween = null
	for index in range(_owned_nuke_nodes.size() - 1, -1, -1):
		var node:Node = _owned_nuke_nodes[index]
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			_owned_nuke_nodes.remove_at(index)
	rage_percent = 0.0
	rage_decay_wait_left = 0.0
	_update_rage_visual()


# ============================================================
# RL 通用策略接口：怒气越高，继续攻击的反制风险越高。
# ============================================================
func get_ai_strategy_info(_receiver:ball) -> Dictionary:
	return {
		"counter_risk": 1.0 if nuke_active else clampf(rage_percent/100.0,0.0,1.0),
		"defense_risk": 0.0,
		"reflect_risk": 0.0,
	}
