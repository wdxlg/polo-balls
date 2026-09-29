extends Node2D

const WAR_GODDESS_BURN_SCRIPT:Script = preload("res://scripts/status/战争女神_灼烧.gd")
const WAR_GODDESS_BURN_NODE_NAME:StringName = &"WarGoddessBurnStatus"
const FIRE_FRAMES:SpriteFrames = preload("res://particles/mc_ground_fire.tres")
const SMALL_FLAME_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/火焰粒子/flame.png")
const FIRE_BURN_LOOP_SFX:AudioStream = preload("res://audio/characters/薇欧拉/火焰燃烧_[cut_94sec].mp3")

const APPEAR_TIME:float = 0.16
const END_START_RATIO:float = 0.72
const PARTICLE_STOP_RATIO:float = 0.73

var owner_ref:WeakRef = null
var Team:String = ""
var radius:float = 58.0
var duration:float = 5.0
var tick_interval:float = 0.55
var tick_damage:float = 8.0
var burn_duration:float = 3.0
var burn_tick_interval:float = 0.5
var burn_tick_damage:float = 5.0
var elapsed:float = 0.0
var tick_left:float = 0.0

var _main_fire:AnimatedSprite2D = null
var _fire_base_width:float = 170.0
var _fire_base_height:float = 270.0
var _particle_spawn_left:float = 0.0
var _particles:Array[Dictionary] = []
var _burn_loop_player:AudioStreamPlayer2D = null
var _rng:=RandomNumberGenerator.new()

func setup(owner_node:Node,position_value:Vector2,config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_node)
	Team = str(owner_node.get("Team")) if owner_node != null else ""
	global_position = position_value
	radius = maxf(float(config.get("radius",radius)),8.0)
	duration = maxf(float(config.get("duration",duration)),0.2)
	tick_interval = maxf(float(config.get("tick_interval",tick_interval)),0.05)
	tick_damage = maxf(float(config.get("tick_damage",tick_damage)),0.0)
	burn_duration = maxf(float(config.get("burn_duration",burn_duration)),0.1)
	burn_tick_interval = maxf(float(config.get("burn_tick_interval",burn_tick_interval)),0.05)
	burn_tick_damage = maxf(float(config.get("burn_tick_damage",burn_tick_damage)),0.0)
	_fire_base_width = maxf(radius * 2.95,90.0)
	_fire_base_height = maxf(radius * 4.65,150.0)
	tick_left = 0.05
	_start_burning_loop()

func _ready() -> void:
	z_as_relative = false
	# V413：地图外视觉遮罩在 world.gd 中使用绝对 z_index=90，地图黑色边线为 z_index=100。
	# 火焰根节点放在两者之间：主火焰子节点最终约 z=98，小火焰粒子约 z=99。
	# 这样火焰可越过地图外遮罩显示，但黑色地图边线仍压在火焰之上。
	z_index = 96
	add_to_group("BattleTransient")
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/薇欧拉_火场.gd:_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_build_fire_visual()

func _physics_process(delta:float) -> void:
	elapsed += delta
	if elapsed >= duration:
		_clear_particles()
		queue_free()
		return
	var owner_node:Node = _owner()
	if owner_node != null and owner_node.is_multiplayer_authority():
		tick_left -= delta
		while tick_left <= 0.0:
			tick_left += tick_interval
			_apply_fire_tick()
	_update_main_fire_visual()
	_update_small_flames(delta)

func _start_burning_loop() -> void:
	if FIRE_BURN_LOOP_SFX == null:
		return
	if _burn_loop_player != null and is_instance_valid(_burn_loop_player):
		if not _burn_loop_player.playing:
			_burn_loop_player.play()
		return
	_burn_loop_player = AudioStreamPlayer2D.new()
	_burn_loop_player.name = "ViolaFireFieldLoopSFX"
	var stream_value:AudioStream = FIRE_BURN_LOOP_SFX.duplicate() as AudioStream
	if stream_value is AudioStreamMP3:
		(stream_value as AudioStreamMP3).loop = true
	_burn_loop_player.stream = stream_value if stream_value != null else FIRE_BURN_LOOP_SFX
	var source:Node = _owner()
	var owner_gain:float = float(source.get("viola_audio_gain_db")) if source != null and source.get("viola_audio_gain_db") != null else 0.0
	_burn_loop_player.volume_db = clampf(owner_gain + 1.0,-20.0,10.0)
	_burn_loop_player.max_distance = 1650.0
	_burn_loop_player.attenuation = 0.82
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_burn_loop_player.bus = &"GameplayRecord"
	add_child(_burn_loop_player)
	_burn_loop_player.play()

func _build_fire_visual() -> void:
	if FIRE_FRAMES == null or FIRE_FRAMES.get_frame_count(&"default") <= 0:
		return
	_main_fire = AnimatedSprite2D.new()
	_main_fire.name = "MainFireSequence"
	_main_fire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_main_fire.sprite_frames = FIRE_FRAMES
	_main_fire.animation = &"default"
	_main_fire.frame = _rng.randi_range(0,maxi(FIRE_FRAMES.get_frame_count(&"default") - 1,0))
	_main_fire.speed_scale = 1.0
	_main_fire.z_index = 2
	_main_fire.self_modulate = Color.WHITE
	add_child(_main_fire)
	_main_fire.play()
	_update_main_fire_visual()

func _update_main_fire_visual() -> void:
	if _main_fire == null or not is_instance_valid(_main_fire):
		return
	var life_t:float = clampf(elapsed / maxf(duration,0.001),0.0,1.0)
	var appear_t:float = clampf(elapsed / APPEAR_TIME,0.0,1.0)
	var appear_ease:float = 1.0 - pow(1.0 - appear_t,3.0)
	var pulse:float = 1.0 + sin(elapsed * 5.8) * 0.045 + sin(elapsed * 9.1 + 0.7) * 0.018
	var width_value:float = _fire_base_width * lerpf(0.72,1.0,appear_ease)
	var height_value:float = _fire_base_height * lerpf(0.16,1.0,appear_ease) * pulse
	var alpha_value:float = 1.0
	var end_t:float = clampf((life_t - END_START_RATIO) / maxf(1.0 - END_START_RATIO,0.001),0.0,1.0)
	var end_smooth:float = smoothstep(0.0,1.0,end_t)
	if end_smooth > 0.0:
		width_value *= lerpf(1.0,0.16,end_smooth)
		height_value *= lerpf(1.0,1.34,end_smooth)
		alpha_value = 1.0 - end_smooth
	var reference:Texture2D = FIRE_FRAMES.get_frame_texture(&"default",0)
	if reference == null:
		return
	var tex_size:Vector2 = reference.get_size()
	_main_fire.scale = Vector2(width_value / maxf(tex_size.x,1.0),height_value / maxf(tex_size.y,1.0))
	# V414：火焰箭爆炸点就是火场根节点 global_position。
	# 主火焰 PNG 的中心必须严格落在该爆炸点，不再把爆炸点当作火焰底部。
	# 因此高度呼吸/末段拉高都围绕火焰箭命中点展开。
	_main_fire.position = Vector2.ZERO
	_main_fire.modulate.a = clampf(alpha_value,0.0,1.0)

func _update_small_flames(delta:float) -> void:
	var life_t:float = clampf(elapsed / maxf(duration,0.001),0.0,1.0)
	if life_t < PARTICLE_STOP_RATIO and SMALL_FLAME_TEXTURE != null:
		_particle_spawn_left -= delta
		var spawn_guard:int = 0
		while _particle_spawn_left <= 0.0 and spawn_guard < 4:
			_particle_spawn_left += _rng.randf_range(0.055,0.095)
			_spawn_small_flame()
			spawn_guard += 1
	for i:int in range(_particles.size() - 1,-1,-1):
		var data:Dictionary = _particles[i]
		var node_value:Variant = data.get("node",null)
		if not is_instance_valid(node_value) or not (node_value is Sprite2D):
			_particles.remove_at(i)
			continue
		var sprite:Sprite2D = node_value as Sprite2D
		var age:float = float(data.get("age",0.0)) + delta
		var lifetime:float = maxf(float(data.get("lifetime",0.9)),0.1)
		data["age"] = age
		if age >= lifetime:
			sprite.queue_free()
			_particles.remove_at(i)
			continue
		var velocity:Vector2 = data.get("velocity",Vector2.ZERO)
		var sideways_accel:float = float(data.get("sideways_accel",0.0))
		velocity.x += sideways_accel * delta
		velocity.y -= 10.0 * delta
		data["velocity"] = velocity
		sprite.position += velocity * delta
		sprite.rotation += float(data.get("spin",0.0)) * delta
		var progress:float = clampf(age / lifetime,0.0,1.0)
		var fade_t:float = smoothstep(0.38,1.0,progress)
		var base_scale:float = float(data.get("base_scale",0.02))
		var scale_factor:float = lerpf(1.0,0.12,fade_t)
		sprite.scale = Vector2.ONE * base_scale * scale_factor
		sprite.modulate.a = 1.0 - fade_t

func _spawn_small_flame() -> void:
	if SMALL_FLAME_TEXTURE == null:
		return
	var sprite:=Sprite2D.new()
	sprite.texture = SMALL_FLAME_TEXTURE
	sprite.z_index = 3
	var side_sign:float = -1.0 if _rng.randf() < 0.5 else 1.0
	# V414：小火焰也从主火焰“中间”附近冒出，而不是从爆炸点上方很高的位置开始。
	var start_x:float = _rng.randf_range(-_fire_base_width * 0.14,_fire_base_width * 0.14)
	var start_y:float = _rng.randf_range(-_fire_base_height * 0.08,_fire_base_height * 0.08)
	sprite.position = Vector2(start_x,start_y)
	var target_height:float = _rng.randf_range(18.0,27.0)
	var base_scale:float = target_height / maxf(float(SMALL_FLAME_TEXTURE.get_height()),1.0)
	base_scale *= _rng.randf_range(0.88,1.12)
	sprite.scale = Vector2.ONE * base_scale
	sprite.modulate = Color(1.0,1.0,1.0,_rng.randf_range(0.82,1.0))
	add_child(sprite)
	_particles.append({
		"node":sprite,
		"age":0.0,
		"lifetime":_rng.randf_range(0.72,1.18),
		"base_scale":base_scale,
		"velocity":Vector2(side_sign * _rng.randf_range(28.0,58.0),-_rng.randf_range(58.0,96.0)),
		"sideways_accel":side_sign * _rng.randf_range(5.0,18.0),
		"spin":_rng.randf_range(-0.55,0.55),
	})

func _clear_particles() -> void:
	for data:Dictionary in _particles:
		var node_value:Variant = data.get("node",null)
		if is_instance_valid(node_value) and node_value is Node:
			(node_value as Node).queue_free()
	_particles.clear()

func _apply_fire_tick() -> void:
	if tick_damage <= 0.0:
		return
	var source:Node = _owner()
	if source == null:
		return
	var radius_sq:float = radius * radius
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_enemy(target):
			continue
		if global_position.distance_squared_to(target.global_position) > radius_sq:
			continue
		var applied:bool = target.receive_fire_spatial_damage(
			tick_damage,
			{"point":target.global_position,"source":source},
			false,
			false
		)
		if applied:
			_apply_war_goddess_burn(target,source)
			_play_burn_damage_sfx(source,target.global_position)

func _apply_war_goddess_burn(target:ball,source_node:Node) -> void:
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		return
	if not source_node is ball:
		return
	var source:ball = source_node as ball
	var existing:Node = target.get_node_or_null(NodePath(String(WAR_GODDESS_BURN_NODE_NAME)))
	if existing != null and existing.has_method("refresh"):
		existing.call("refresh",source,burn_duration,burn_tick_damage)
		return
	var status:Node2D = WAR_GODDESS_BURN_SCRIPT.new() as Node2D
	if status == null:
		return
	status.name = WAR_GODDESS_BURN_NODE_NAME
	status.top_level = true
	target.add_child(status,true)
	status.global_position = target.global_position
	status.call("setup",target,source,burn_duration,burn_tick_interval,burn_tick_damage)

func _play_burn_damage_sfx(source:Node,position_value:Vector2) -> void:
	if source != null and source.has_method("play_war_burn_tick_sfx"):
		source.call("play_war_burn_tick_sfx",position_value)

func _is_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	var source:Node = _owner()
	if source != null and target == source:
		return false
	if not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and target.Team == Team:
		return false
	return true

func _owner() -> Node:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is Node and is_instance_valid(raw):
		return raw as Node
	return null
