extends Node2D

# 乌鲁鲁（原项目内部名“堵桥”）燃烧弹落地区域。
# 区域逻辑保留原有伤害/自伤/灼烧；默认半径收至58，与当前薇欧拉火场默认半径一致；视觉继续使用圆内随机粒子分布，
# 仅把药水粒子替换为薇欧拉的小火焰，并用加法混合 + 过亮色增强发光感。
const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const WAR_GODDESS_BURN_SCRIPT:Script = preload("res://scripts/status/战争女神_灼烧.gd")
const WAR_GODDESS_BURN_NODE_NAME:StringName = &"WarGoddessBurnStatus"
const SMALL_FLAME_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/火焰粒子/flame.png")

var owner_ref:WeakRef = null
var radius:float = 58.0
var duration:float = 5.2
var tick_interval:float = 0.75
var direct_damage_multiplier:float = 2.4
var self_damage_multiplier:float = 0.5
var burn_duration:float = 4.0
var burn_tick_interval:float = 0.5
var burn_tick_damage_multiplier:float = 0.7
var particle_interval:float = 0.0107

var _elapsed:float = 0.0
var _tick_left:float = 0.05
var _particle_left:float = 0.0
var _particles:Array[Dictionary] = []
var _glow_material:CanvasItemMaterial = null
var _rng:=RandomNumberGenerator.new()
var _ending:bool = false


func setup(owner_ball:ball,position_value:Vector2,config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_ball)
	global_position = position_value
	radius = maxf(float(config.get("radius",radius)),12.0)
	duration = maxf(float(config.get("duration",duration)),0.2)
	tick_interval = maxf(float(config.get("tick_interval",tick_interval)),0.08)
	direct_damage_multiplier = maxf(float(config.get("direct_damage_multiplier",direct_damage_multiplier)),0.0)
	self_damage_multiplier = clampf(float(config.get("self_damage_multiplier",self_damage_multiplier)),0.0,1.0)
	burn_duration = maxf(float(config.get("burn_duration",burn_duration)),0.1)
	burn_tick_interval = maxf(float(config.get("burn_tick_interval",burn_tick_interval)),0.05)
	burn_tick_damage_multiplier = maxf(float(config.get("burn_tick_damage_multiplier",burn_tick_damage_multiplier)),0.0)
	particle_interval = maxf(float(config.get("particle_interval",particle_interval)),0.006)
	_tick_left = 0.05
	_particle_left = 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 96
	add_to_group("BattleTransient")
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/堵桥火圈.gd:_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_glow_material = CanvasItemMaterial.new()
	_glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func _physics_process(delta:float) -> void:
	var source:ball = _owner()

	# V106：火区寿命结束时只“关掉发射器和伤害”，不清空当前火苗。
	# 已经存在的小火焰继续按各自 lifetime 上飘、缩放、alpha 淡出，最后一个消失后再释放区域节点。
	if _ending:
		_update_small_flames(delta)
		if _particles.is_empty():
			queue_free()
		return

	if source == null or not is_instance_valid(source):
		_begin_natural_fade_out()
		_update_small_flames(delta)
		if _particles.is_empty():
			queue_free()
		return
	if not source.is_combat_runtime_active():
		return

	_elapsed += delta
	_tick_left -= delta
	_particle_left -= delta
	if _elapsed >= duration:
		_begin_natural_fade_out()
		_update_small_flames(delta)
		if _particles.is_empty():
			queue_free()
		return

	if source.is_multiplayer_authority():
		while _tick_left <= 0.0:
			_tick_left += tick_interval
			_apply_tick(source)

	# 与女巫药水区域相同：sqrt(rand) 让粒子在整个圆形面积内均匀分布。
	var spawn_guard:int = 0
	while _particle_left <= 0.0 and spawn_guard < 10:
		_particle_left += particle_interval
		_spawn_small_flame()
		spawn_guard += 1
	_update_small_flames(delta)


func _begin_natural_fade_out() -> void:
	if _ending:
		return
	_ending = true
	# 不再生成新粒子，也不再触发伤害 tick；已有粒子由 _update_small_flames 自然淡出。
	_particle_left = INF
	_tick_left = INF


func _spawn_small_flame() -> void:
	if SMALL_FLAME_TEXTURE == null:
		return
	var angle:float = _rng.randf_range(0.0,TAU)
	var dist:float = sqrt(_rng.randf()) * radius * 0.92
	var sprite:=Sprite2D.new()
	sprite.name = "乌鲁鲁区域小火焰"
	sprite.texture = SMALL_FLAME_TEXTURE
	sprite.position = Vector2.from_angle(angle) * dist
	sprite.z_index = _rng.randi_range(0,3)
	if _glow_material != null:
		sprite.material = _glow_material

	# 上一版 18~31px 过大；本版压到约 7~12px，密度则贴近女巫药水区域。
	var target_height:float = _rng.randf_range(7.0,12.0)
	var base_scale:float = target_height / maxf(float(SMALL_FLAME_TEXTURE.get_height()),1.0)
	base_scale *= _rng.randf_range(0.90,1.08)
	sprite.scale = Vector2.ONE * base_scale
	sprite.self_modulate = Color(1.55,1.12,0.58,_rng.randf_range(0.72,0.95))
	add_child(sprite)
	_particles.append({
		"node":sprite,
		"age":0.0,
		"lifetime":_rng.randf_range(0.48,0.82),
		"base_scale":base_scale,
		"velocity":Vector2(_rng.randf_range(-3.0,3.0),-_rng.randf_range(7.0,15.0)),
		"spin":_rng.randf_range(-0.22,0.22),
		"phase":_rng.randf_range(0.0,TAU),
	})


func _update_small_flames(delta:float) -> void:
	for i:int in range(_particles.size() - 1,-1,-1):
		var data:Dictionary = _particles[i]
		var node_value:Variant = data.get("node",null)
		if not is_instance_valid(node_value) or not (node_value is Sprite2D):
			_particles.remove_at(i)
			continue
		var sprite:Sprite2D = node_value as Sprite2D
		var age:float = float(data.get("age",0.0)) + delta
		var lifetime:float = maxf(float(data.get("lifetime",0.65)),0.1)
		data["age"] = age
		if age >= lifetime:
			sprite.queue_free()
			_particles.remove_at(i)
			continue
		var velocity:Vector2 = data.get("velocity",Vector2.ZERO)
		velocity.y -= 2.5 * delta
		data["velocity"] = velocity
		sprite.position += velocity * delta
		sprite.rotation += float(data.get("spin",0.0)) * delta
		var progress:float = clampf(age / lifetime,0.0,1.0)
		var appear:float = smoothstep(0.0,0.10,progress)
		var fade:float = 1.0 - smoothstep(0.44,1.0,progress)
		var pulse:float = 1.0 + sin(age * 13.0 + float(data.get("phase",0.0))) * 0.07
		var base_scale:float = float(data.get("base_scale",0.01))
		sprite.scale = Vector2.ONE * base_scale * pulse * lerpf(0.78,1.0,appear)
		sprite.self_modulate.a = clampf(appear * fade,0.0,1.0)


func _apply_tick(source:ball) -> void:
	var radius_sq:float = radius * radius
	var enemy_damage:float = source.attack_damage(direct_damage_multiplier)
	if enemy_damage <= 0.0:
		return

	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not is_instance_valid(target) or target.health <= 0:
			continue
		if global_position.distance_squared_to(target.global_position) > radius_sq:
			continue

		if target == source:
			var self_damage:float = enemy_damage * self_damage_multiplier
			if self_damage > 0.0:
				target.receive_fire_positional_damage(self_damage,target.global_position,false,null)
			continue

		if not SUBMISSION_TOOLS.is_enemy(source,target):
			continue
		var applied:bool = target.receive_fire_positional_damage(enemy_damage,target.global_position,false,source)
		if applied:
			_apply_burn(source,target)


func _apply_burn(source:ball,target:ball) -> void:
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		return
	var tick_damage:float = source.attack_damage(burn_tick_damage_multiplier)
	var existing:Node = target.get_node_or_null(NodePath(String(WAR_GODDESS_BURN_NODE_NAME)))
	if existing != null and existing.has_method("refresh"):
		existing.call("refresh",source,burn_duration,tick_damage)
		return
	var status:Node2D = WAR_GODDESS_BURN_SCRIPT.new() as Node2D
	if status == null:
		return
	status.name = WAR_GODDESS_BURN_NODE_NAME
	status.top_level = true
	target.add_child(status,true)
	status.global_position = target.global_position
	status.call("setup",target,source,burn_duration,burn_tick_interval,tick_damage)


func _clear_particles() -> void:
	for data:Dictionary in _particles:
		var node_value:Variant = data.get("node",null)
		if is_instance_valid(node_value) and node_value is Node:
			(node_value as Node).queue_free()
	_particles.clear()


func _owner() -> ball:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null
