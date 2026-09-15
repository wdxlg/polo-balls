extends Node2D

# 乌鲁鲁复合型燃烧弹落地后的持续区域。
# 视觉按“女巫药水区域”的思路在整个圆形范围内持续随机生成粒子，
# 但粒子直接复用薇欧拉的小火焰，并使用加法混合 + HDR 过亮色表现发光。
const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const WAR_GODDESS_BURN_SCRIPT:Script = preload("res://scripts/status/战争女神_灼烧.gd")
const WAR_GODDESS_BURN_NODE_NAME:StringName = &"WarGoddessBurnStatus"
const SMALL_FLAME_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/火焰粒子/flame.png")
const FIRE_BURN_LOOP_SFX:AudioStream = preload("res://audio/characters/薇欧拉/火焰燃烧_[cut_94sec].mp3")

var owner_ref:WeakRef = null
var radius:float = 82.0
var duration:float = 5.6
var tick_interval:float = 0.65
var damage_multiplier:float = 1.45
var burn_duration:float = 3.5
var burn_tick_interval:float = 0.5
var burn_tick_damage_multiplier:float = 0.55
var particle_interval:float = 0.038

var _elapsed:float = 0.0
var _tick_left:float = 0.05
var _particle_left:float = 0.0
var _particles:Array[Dictionary] = []
var _glow_material:CanvasItemMaterial = null
var _burn_loop_player:AudioStreamPlayer2D = null
var _rng:=RandomNumberGenerator.new()


func setup(owner_ball:ball,position_value:Vector2,config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_ball)
	global_position = position_value
	radius = maxf(float(config.get("radius",radius)),10.0)
	duration = maxf(float(config.get("duration",duration)),0.2)
	tick_interval = maxf(float(config.get("tick_interval",tick_interval)),0.08)
	damage_multiplier = maxf(float(config.get("damage_multiplier",damage_multiplier)),0.0)
	burn_duration = maxf(float(config.get("burn_duration",burn_duration)),0.1)
	burn_tick_interval = maxf(float(config.get("burn_tick_interval",burn_tick_interval)),0.05)
	burn_tick_damage_multiplier = maxf(float(config.get("burn_tick_damage_multiplier",burn_tick_damage_multiplier)),0.0)
	particle_interval = maxf(float(config.get("particle_interval",particle_interval)),0.012)
	_tick_left = 0.05
	_particle_left = 0.0


func _ready() -> void:
	z_as_relative = false
	# 不画圆环，只让小火焰本身标出危险区域。
	z_index = 96
	add_to_group("BattleTransient")
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/乌鲁鲁火焰区域.gd:_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_build_glow_material()
	_start_burning_loop()


func _physics_process(delta:float) -> void:
	var source:ball = _owner()
	if source == null or not is_instance_valid(source):
		_clear_particles()
		queue_free()
		return
	if not source.is_combat_runtime_active():
		return

	_elapsed += delta
	_tick_left -= delta
	_particle_left -= delta

	if source.is_multiplayer_authority():
		while _tick_left <= 0.0 and _elapsed <= duration + 0.001:
			_tick_left += tick_interval
			_apply_tick(source)

	# 与女巫药水区域相同：持续在圆内按面积均匀取点。
	var spawn_guard:int = 0
	while _particle_left <= 0.0 and _elapsed <= duration + 0.001 and spawn_guard < 6:
		_particle_left += particle_interval
		_spawn_small_flame()
		spawn_guard += 1

	_update_small_flames(delta)
	if _elapsed >= duration:
		_clear_particles()
		queue_free()


func _build_glow_material() -> void:
	_glow_material = CanvasItemMaterial.new()
	_glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func _spawn_small_flame() -> void:
	if SMALL_FLAME_TEXTURE == null:
		return
	var angle:float = _rng.randf_range(0.0,TAU)
	var dist:float = sqrt(_rng.randf()) * radius * 0.94
	var sprite:=Sprite2D.new()
	sprite.name = "UluruSmallFlame"
	sprite.texture = SMALL_FLAME_TEXTURE
	sprite.position = Vector2.from_angle(angle) * dist
	sprite.z_index = _rng.randi_range(0,3)
	if _glow_material != null:
		sprite.material = _glow_material
	var target_height:float = _rng.randf_range(18.0,31.0)
	var base_scale:float = target_height / maxf(float(SMALL_FLAME_TEXTURE.get_height()),1.0)
	base_scale *= _rng.randf_range(0.86,1.18)
	sprite.scale = Vector2.ONE * base_scale
	# 分量 > 1 可在 HDR 2D + Glow 环境中触发真实 bloom；没有 HDR 时加法混合仍保持明亮火焰感。
	sprite.self_modulate = Color(1.65,1.18,0.62,_rng.randf_range(0.76,1.0))
	add_child(sprite)
	_particles.append({
		"node":sprite,
		"age":0.0,
		"lifetime":_rng.randf_range(0.58,1.05),
		"base_scale":base_scale,
		"velocity":Vector2(_rng.randf_range(-7.0,7.0),-_rng.randf_range(11.0,24.0)),
		"spin":_rng.randf_range(-0.38,0.38),
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
		var lifetime:float = maxf(float(data.get("lifetime",0.8)),0.1)
		data["age"] = age
		if age >= lifetime:
			sprite.queue_free()
			_particles.remove_at(i)
			continue
		var velocity:Vector2 = data.get("velocity",Vector2.ZERO)
		velocity.y -= 4.0 * delta
		data["velocity"] = velocity
		sprite.position += velocity * delta
		sprite.rotation += float(data.get("spin",0.0)) * delta
		var progress:float = clampf(age / lifetime,0.0,1.0)
		var appear:float = smoothstep(0.0,0.13,progress)
		var fade:float = 1.0 - smoothstep(0.48,1.0,progress)
		var pulse:float = 1.0 + sin(age * 12.0 + float(data.get("phase",0.0))) * 0.10
		var base_scale:float = float(data.get("base_scale",0.03))
		sprite.scale = Vector2.ONE * base_scale * pulse * lerpf(0.72,1.0,appear)
		sprite.self_modulate.a = clampf(appear * fade,0.0,1.0)


func _apply_tick(source:ball) -> void:
	var damage:float = source.attack_damage(damage_multiplier)
	if damage <= 0.0:
		return
	for target:ball in SUBMISSION_TOOLS.enemies_in_radius(source,global_position,radius):
		var applied:bool = target.receive_fire_positional_damage(damage,target.global_position,false,source)
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


func _start_burning_loop() -> void:
	if FIRE_BURN_LOOP_SFX == null:
		return
	_burn_loop_player = AudioStreamPlayer2D.new()
	_burn_loop_player.name = "UluruFireAreaLoopSFX"
	var stream_value:AudioStream = FIRE_BURN_LOOP_SFX.duplicate() as AudioStream
	if stream_value is AudioStreamMP3:
		(stream_value as AudioStreamMP3).loop = true
	_burn_loop_player.stream = stream_value if stream_value != null else FIRE_BURN_LOOP_SFX
	_burn_loop_player.volume_db = -5.0
	_burn_loop_player.max_distance = 1450.0
	_burn_loop_player.attenuation = 0.82
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_burn_loop_player.bus = &"GameplayRecord"
	add_child(_burn_loop_player)
	_burn_loop_player.play()


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
