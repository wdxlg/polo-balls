extends Node2D

var owner_ball:ball = null
var radius:float = 72.0
var duration:float = 8.0
var damage_interval:float = 0.5
var damage_amount:float = 10.0
var heal_interval:float = 1.0
var heal_amount:float = 14.0
var form2_follow_speed:float = 18.0

var _life_left:float = 0.0
var _damage_left:float = 0.0
var _heal_left:float = 0.0
var _visual_time:float = 0.0
var _heal_flash:float = 0.0
var _damage_flash:float = 0.0
var _visual_age:float = 0.0
var _visual_base_scale:Vector2 = Vector2.ONE
var _spawn_tween:Tween = null
var _circle_material:ShaderMaterial = null
var _world_anchor_position:Vector2 = Vector2.ZERO
var _world_anchor_ready:bool = false

@onready var effect_area:Area2D = $EffectArea
@onready var collision_shape:CollisionShape2D = $EffectArea/CollisionShape2D
@onready var magic_circle_visual:Sprite2D = $MagicCircleVisual


func set_world_anchor(world_position:Vector2) -> void:
	_world_anchor_position = world_position
	_world_anchor_ready = true
	_keep_world_transform()


func _keep_world_transform() -> void:
	if not _world_anchor_ready or not is_inside_tree():
		return
	global_position = _world_anchor_position
	global_rotation = 0.0
	global_scale = Vector2.ONE
	z_as_relative = false
	z_index = -1


func setup(
	new_owner:ball,
	new_radius:float,
	new_duration:float,
	new_damage_interval:float,
	new_damage_amount:float,
	new_heal_interval:float,
	new_heal_amount:float,
	new_form2_follow_speed:float = 18.0
) -> void:
	owner_ball = new_owner
	radius = maxf(new_radius,10.0)
	duration = maxf(new_duration,0.2)
	damage_interval = maxf(new_damage_interval,0.05)
	damage_amount = maxf(new_damage_amount,0.0)
	heal_interval = maxf(new_heal_interval,0.05)
	heal_amount = maxf(new_heal_amount,0.0)
	form2_follow_speed = maxf(new_form2_follow_speed,0.0)
	_life_left = duration
	_damage_left = damage_interval
	_heal_left = heal_interval
	_visual_age = 0.0
	_apply_circle_setup()
	_start_spawn_visual_animation()


func _ready() -> void:
	add_to_group("BattleTransient")
	z_as_relative = false
	z_index = -1
	if not _world_anchor_ready:
		_world_anchor_position = global_position
		_world_anchor_ready = true
	_keep_world_transform()
	effect_area.collision_layer = 0
	effect_area.collision_mask = 2
	effect_area.monitoring = true
	effect_area.monitorable = false
	effect_area.set_meta("threat_debug_damage",damage_amount)
	_apply_circle_setup()
	if magic_circle_visual != null:
		# V57：法阵使用 blend_add 发光时，不能只靠 CanvasItem alpha 淡出。
		# 为每个法阵实例复制独立材质，并用 Shader 参数同时衰减本体 RGB 与外发光。
		if magic_circle_visual.material is ShaderMaterial:
			_circle_material = (magic_circle_visual.material as ShaderMaterial).duplicate(true) as ShaderMaterial
			magic_circle_visual.material = _circle_material
			_circle_material.set_shader_parameter("visual_fade",0.0)
		magic_circle_visual.self_modulate = Color(1.0,1.0,1.0,1.0)
	queue_redraw()


func _apply_circle_setup() -> void:
	if collision_shape == null:
		return
	var shape := collision_shape.shape as CircleShape2D
	if shape != null:
		shape.radius = radius
	if effect_area != null:
		effect_area.set_meta("threat_debug_damage",damage_amount)
	if magic_circle_visual != null and magic_circle_visual.texture != null:
		var tex_size:Vector2 = magic_circle_visual.texture.get_size()
		var longest:float = maxf(tex_size.x,tex_size.y)
		if longest > 0.001:
			var visual_scale:float = (radius * 2.0) / longest
			_visual_base_scale = Vector2.ONE * visual_scale
			if _spawn_tween == null:
				magic_circle_visual.scale = _visual_base_scale


func _start_spawn_visual_animation() -> void:
	if magic_circle_visual == null or not is_inside_tree():
		return
	if _spawn_tween != null and _spawn_tween.is_valid():
		_spawn_tween.kill()
	magic_circle_visual.scale = _visual_base_scale * 0.56
	_spawn_tween = create_tween().bind_node(self)
	# V55：小尺寸出现 -> 快速放大略微过冲 -> 丝滑回弹到最终尺寸。
	_spawn_tween.tween_property(magic_circle_visual,"scale",_visual_base_scale * 1.10,0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_spawn_tween.tween_property(magic_circle_visual,"scale",_visual_base_scale,0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _form2_should_follow_owner() -> bool:
	if owner_ball == null or not is_instance_valid(owner_ball):
		return false
	var active:Variant = owner_ball.get("form2_active")
	return typeof(active) == TYPE_BOOL and bool(active)


func _process(delta:float) -> void:
	# V55：战争女神进入形态2后，当前法阵以很慢的速度朝她靠近，而不是瞬间绑定跟随。
	if _world_anchor_ready and _form2_should_follow_owner() and form2_follow_speed > 0.0:
		_world_anchor_position = _world_anchor_position.move_toward(owner_ball.global_position,form2_follow_speed * delta)
	_keep_world_transform()
	_visual_time += delta
	_visual_age += delta
	# 只旋转法阵图片，根节点负责真实伤害/回血区域的位置。
	if magic_circle_visual != null:
		magic_circle_visual.rotation += delta * 0.70
	_heal_flash = maxf(_heal_flash - delta * 3.6,0.0)
	_damage_flash = maxf(_damage_flash - delta * 5.2,0.0)
	if magic_circle_visual != null:
		var tint_g:float = clampf(1.0 - _damage_flash * 0.12 + _heal_flash * 0.05,0.78,1.0)
		var tint_b:float = clampf(1.0 - _damage_flash * 0.22 + _heal_flash * 0.08,0.68,1.0)
		# 出现时渐显；生命结束前渐隐。
		# V57：只把颜色 tint 留在 self_modulate，Alpha 固定为 1；
		# 真正的淡入淡出交给 Shader 的 visual_fade，让法阵本体和 additive glow 同步变暗。
		var fade_in:float = smoothstep(0.0,0.42,_visual_age)
		var fade_out:float = smoothstep(0.0,0.62,maxf(_life_left,0.0))
		var visual_alpha:float = minf(fade_in,fade_out)
		magic_circle_visual.self_modulate = Color(1.0,tint_g,tint_b,1.0)
		if _circle_material != null:
			_circle_material.set_shader_parameter("visual_fade",visual_alpha)


func _physics_process(delta:float) -> void:
	_keep_world_transform()
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()
		return
	if owner_ball == null or not is_instance_valid(owner_ball) or owner_ball.health <= 0:
		queue_free()
		return
	if not owner_ball.is_multiplayer_authority():
		return
	if not owner_ball.is_combat_runtime_active():
		return

	_damage_left -= delta
	while _damage_left <= 0.0:
		_damage_left += damage_interval
		_damage_enemies()

	_heal_left -= delta
	while _heal_left <= 0.0:
		_heal_left += heal_interval
		_heal_owner()


func _damage_enemies() -> void:
	if damage_amount <= 0.0:
		return
	var outgoing:float = owner_ball.effective_outgoing_damage(damage_amount)
	if outgoing <= 0.0:
		return
	var damaged_ids:Dictionary = {}
	for area:Area2D in effect_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var node:Node = area.get_parent()
		if not node is ball:
			node = area.owner
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == owner_ball or not _is_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		if damaged_ids.has(target_id):
			continue
		damaged_ids[target_id] = true
		var before_health:float = float(target.health)
		var before_block:float = float(target.block)
		target.receive_fire_positional_damage(outgoing,global_position,false,owner_ball)
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		if health_loss > 0.0:
			_damage_flash = 1.0
			var seed:int = Game.battle_rng_seed_or("scripts/effects/战争女神_法阵.gd:seed",int(Time.get_ticks_usec()) ^ target_id ^ get_instance_id())
			target.notify_hit_burst_feedback(global_position,outgoing,health_loss,block_loss,radius * 0.35,seed,(target.global_position-global_position).normalized())
			_play_hit_sfx(outgoing)


func _heal_owner() -> void:
	if owner_ball == null or not is_instance_valid(owner_ball) or heal_amount <= 0.0:
		return
	var owner_inside:bool = false
	for area:Area2D in effect_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var node:Node = area.get_parent()
		if not node is ball:
			node = area.owner
		if node == owner_ball:
			owner_inside = true
			break
	if not owner_inside:
		return
	var actual:int = owner_ball.heal(heal_amount)
	_heal_flash = 1.0
	if owner_ball.has_method("on_war_goddess_circle_heal"):
		owner_ball.call("on_war_goddess_circle_heal",actual)


func _is_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(owner_ball,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not owner_ball.Team.is_empty() and target.Team == owner_ball.Team:
		return false
	return true


func _play_hit_sfx(raw_damage:float) -> void:
	if owner_ball == null or owner_ball.Hit_Audio.is_empty():
		return
	var params:Dictionary = {"volume":clampf(raw_damage - 30.0,-18.0,0.0),"pitch":randf_range(0.96,1.04)}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(owner_ball.Hit_Audio,params,true)
	else:
		Audios.play_sfx(owner_ball.Hit_Audio,params,true)


func _draw() -> void:
	# V47：法阵视觉完全由用户提供的火焰法阵 PNG 显示。
	# 真实伤害/回血范围仍由 EffectArea/CollisionShape2D 决定。
	pass
