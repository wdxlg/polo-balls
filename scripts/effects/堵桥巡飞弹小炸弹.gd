extends Node2D

const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const BOMB_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/炸弹.png")
# V108：仍使用项目现有的3套MC爆炸动画帧，但声音改由乌鲁鲁自己的“小炸弹爆炸.mp3”播放。
# 视觉由堵桥.gd 的 spawn_uluru_explosion_visual() 生成，避免叠加魔角猎人的TNT音效。

var owner_ref:WeakRef = null
var move_direction:Vector2 = Vector2.RIGHT
var scatter_speed:float = 150.0
var scatter_duration:float = 0.34
var fuse:float = 1.0
var explosion_radius:float = 46.0
var damage_multiplier:float = 3.2
var mc_explosion_variant:int = 1
var elapsed:float = 0.0
var _finished:bool = false
var _sprite:Sprite2D = null


func setup(owner_ball:ball,position_value:Vector2,direction_value:Vector2,config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_ball)
	global_position = position_value
	move_direction = direction_value.normalized() if direction_value.length_squared() > 0.000001 else Vector2.RIGHT
	scatter_speed = maxf(float(config.get("bomb_scatter_speed",scatter_speed)),10.0)
	scatter_duration = maxf(float(config.get("bomb_scatter_duration",scatter_duration)),0.05)
	fuse = maxf(float(config.get("bomb_fuse",fuse)),0.15)
	explosion_radius = maxf(float(config.get("bomb_radius",explosion_radius)),8.0)
	damage_multiplier = maxf(float(config.get("bomb_damage_multiplier",damage_multiplier)),0.0)
	mc_explosion_variant = clampi(int(config.get("mc_explosion_variant",randi_range(1,3))),1,3)


func _ready() -> void:
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
	if elapsed <= scatter_duration:
		var ratio:float = 1.0 - elapsed / maxf(scatter_duration,0.001)
		global_position += move_direction * scatter_speed * maxf(ratio,0.15) * delta
		rotation += delta * 8.0
	if elapsed >= scatter_duration + fuse:
		_explode(source)


func _build_visual() -> void:
	if BOMB_TEXTURE == null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "乌鲁鲁子炸弹图像"
	_sprite.texture = BOMB_TEXTURE
	var longest:float = maxf(BOMB_TEXTURE.get_width(),BOMB_TEXTURE.get_height())
	# V105：子炸弹是散射子弹体，不应接近角色头像大小；22px -> 12px。
	_sprite.scale = Vector2.ONE * (12.0 / maxf(longest,1.0))
	add_child(_sprite)


func _explode(source:ball) -> void:
	if _finished:
		return
	_finished = true
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.visible = false
	if source.is_multiplayer_authority():
		var damage:float = source.attack_damage(damage_multiplier)
		for target:ball in SUBMISSION_TOOLS.enemies_in_radius(source,global_position,explosion_radius):
			target.receive_positional_damage(damage,global_position,false,source)

	# 不再画程序化圆圈。每个客户端都已有同一枚子炸弹实例，因此本地生成同一variant的MC爆炸帧。
	# V108改用乌鲁鲁专属“小炸弹爆炸”声音，不再让魔角猎人的TNT声音叠加。
	if source.has_method("spawn_uluru_explosion_visual"):
		source.call(
			"spawn_uluru_explosion_visual",
			global_position,
			maxf(explosion_radius * 2.0,48.0),
			clampi(mc_explosion_variant,1,3)
		)
	if source.is_multiplayer_authority() and source.has_method("play_uluru_small_bomb_explosion_sfx"):
		source.call("play_uluru_small_bomb_explosion_sfx",global_position)
	queue_free()


func _owner() -> ball:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null
