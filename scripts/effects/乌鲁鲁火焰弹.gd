extends Node2D

const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const FIRE_AREA_SCRIPT:Script = preload("res://scripts/effects/乌鲁鲁火焰区域.gd")
const FIRE_BOMB_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/火焰弹.png")
const FIRE_EXPLOSION_SFX:AudioStream = preload("res://audio/characters/薇欧拉/火焰爆炸_[cut_3sec].mp3")

var owner_ref:WeakRef = null
var start_position:Vector2 = Vector2.ZERO
var target_position:Vector2 = Vector2.ZERO
var duration:float = 0.62
var arc_height:float = 72.0
var impact_damage_multiplier:float = 2.2
var area_config:Dictionary = {}
var elapsed:float = 0.0
var _finished:bool = false
var _sprite:Sprite2D = null


func setup(owner_ball:ball,start_value:Vector2,target_value:Vector2,config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_ball)
	start_position = start_value
	target_position = target_value
	global_position = start_value
	duration = maxf(float(config.get("throw_duration",duration)),0.15)
	arc_height = maxf(float(config.get("arc_height",arc_height)),8.0)
	impact_damage_multiplier = maxf(float(config.get("impact_damage_multiplier",impact_damage_multiplier)),0.0)
	area_config = config.duplicate(true)


func _ready() -> void:
	add_to_group("AllayExtendedProjectile")
	z_as_relative = false
	z_index = 78
	add_to_group("BattleTransient")
	_build_visual()


func _physics_process(delta:float) -> void:
	if _finished:
		return
	var source:ball = _owner()
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	if not source.is_combat_runtime_active():
		return
	elapsed += delta
	var t:float = clampf(elapsed / maxf(duration,0.001),0.0,1.0)
	var base:Vector2 = start_position.lerp(target_position,t)
	var lift:float = -arc_height * 4.0 * t * (1.0 - t)
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,global_position,base+Vector2(0.0,lift)): return
	global_position = base + Vector2(0.0,lift)
	rotation += delta * 5.8
	if t >= 1.0:
		_land(source)


func _build_visual() -> void:
	if FIRE_BOMB_TEXTURE == null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "FireBombImage"
	_sprite.texture = FIRE_BOMB_TEXTURE
	var target_long_side:float = 30.0
	var tex_size:Vector2 = FIRE_BOMB_TEXTURE.get_size()
	var longest:float = maxf(tex_size.x,tex_size.y)
	_sprite.scale = Vector2.ONE * (target_long_side / maxf(longest,1.0))
	add_child(_sprite)


func _land(source:ball) -> void:
	if _finished:
		return
	_finished = true
	global_position = target_position
	if source.is_multiplayer_authority():
		var impact_radius:float = maxf(float(area_config.get("impact_radius",36.0)),8.0)
		var impact_damage:float = source.attack_damage(impact_damage_multiplier)
		for target:ball in SUBMISSION_TOOLS.enemies_in_radius(source,target_position,impact_radius):
			target.receive_fire_positional_damage(impact_damage,target_position,false,source,{"carrier":"projectile"})
	_spawn_area(source)
	_play_impact_sfx(source)
	queue_free()


func _spawn_area(source:ball) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var area:Node2D = FIRE_AREA_SCRIPT.new() as Node2D
	if area == null:
		return
	area.name = "乌鲁鲁火焰区域_%d" % Time.get_ticks_usec()
	world.add_child(area,true)
	area.call("setup",source,target_position,area_config)


func _play_impact_sfx(_source:ball) -> void:
	if FIRE_EXPLOSION_SFX == null or get_tree().current_scene == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "UluruFireBombImpactSFX"
	player.stream = FIRE_EXPLOSION_SFX
	player.global_position = target_position
	player.volume_db = -3.0
	player.pitch_scale = randf_range(0.96,1.04)
	player.max_distance = 1600.0
	player.attenuation = 0.78
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _owner() -> ball:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null
