extends Node2D

const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const BOMB_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/炸弹.png")

var owner_ref:WeakRef = null
var move_direction:Vector2 = Vector2.RIGHT
var scatter_speed:float = 155.0
var scatter_duration:float = 0.38
var fuse:float = 0.82
var explosion_radius:float = 46.0
var damage_multiplier:float = 3.1
var elapsed:float = 0.0
var _exploding:bool = false
var _explosion_t:float = 0.0
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


func _ready() -> void:
	z_as_relative = false
	z_index = 80
	add_to_group("BattleTransient")
	_build_visual()
	queue_redraw()


func _physics_process(delta:float) -> void:
	var source:ball = _owner()
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	if not source.is_combat_runtime_active():
		return
	if _exploding:
		_explosion_t += delta
		if _sprite != null:
			_sprite.visible = false
		queue_redraw()
		if _explosion_t >= 0.24:
			queue_free()
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
	_sprite.name = "BombImage"
	_sprite.texture = BOMB_TEXTURE
	var longest:float = maxf(BOMB_TEXTURE.get_width(),BOMB_TEXTURE.get_height())
	_sprite.scale = Vector2.ONE * (23.0 / maxf(longest,1.0))
	add_child(_sprite)


func _explode(source:ball) -> void:
	if _exploding:
		return
	_exploding = true
	_explosion_t = 0.0
	if source.is_multiplayer_authority():
		var damage:float = source.attack_damage(damage_multiplier)
		for target:ball in SUBMISSION_TOOLS.enemies_in_radius(source,global_position,explosion_radius):
			target.receive_positional_damage(damage,global_position,false,source)
	if source.has_method("play_uluru_explosion_sfx"):
		source.call("play_uluru_explosion_sfx",global_position,-5.0)
	queue_redraw()


func _draw() -> void:
	if not _exploding:
		return
	var t:float = clampf(_explosion_t / 0.24,0.0,1.0)
	var r:float = explosion_radius * smoothstep(0.0,1.0,t)
	draw_circle(Vector2.ZERO,r,Color(1.0,0.23,0.015,0.28 * (1.0-t)))
	draw_arc(Vector2.ZERO,r,0.0,TAU,28,Color(1.0,0.78,0.22,0.88 * (1.0-t)),3.2,true)


func _owner() -> ball:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null
