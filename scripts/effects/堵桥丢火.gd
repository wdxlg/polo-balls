extends Node2D

const FIRE_RING_SCRIPT:Script = preload("res://scripts/effects/堵桥火圈.gd")
const FIRE_BOMB_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/火焰弹.png")

var owner_ref:WeakRef = null
var start_position:Vector2 = Vector2.ZERO
var target_position:Vector2 = Vector2.ZERO
var duration:float = 0.62
var arc_height:float = 72.0
var elapsed:float = 0.0
var ring_config:Dictionary = {}
var _finished:bool = false
var _sprite:Sprite2D = null


func setup(owner_ball:ball,start_value:Vector2,target_value:Vector2,config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_ball)
	start_position = start_value
	target_position = target_value
	global_position = start_value
	duration = maxf(float(config.get("throw_duration",duration)),0.15)
	arc_height = maxf(float(config.get("arc_height",arc_height)),8.0)
	ring_config = config.duplicate(true)


func _ready() -> void:
	z_as_relative = false
	z_index = 76
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
	global_position = base + Vector2(0.0,lift)
	rotation += delta * 5.8
	if t >= 1.0:
		_land(source)


func _build_visual() -> void:
	if FIRE_BOMB_TEXTURE == null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "乌鲁鲁火焰弹图像"
	_sprite.texture = FIRE_BOMB_TEXTURE
	var tex_size:Vector2 = FIRE_BOMB_TEXTURE.get_size()
	var longest:float = maxf(tex_size.x,tex_size.y)
	# V105：燃烧弹弹体缩小，避免飞行过程中像大头像；28px -> 14px。
	_sprite.scale = Vector2.ONE * (14.0 / maxf(longest,1.0))
	add_child(_sprite)


func _land(source:ball) -> void:
	if _finished:
		return
	_finished = true
	if source.is_multiplayer_authority() and source.has_method("play_uluru_fire_land_sfx"):
		source.call("play_uluru_fire_land_sfx",target_position)
	var ring:Node2D = FIRE_RING_SCRIPT.new() as Node2D
	if ring != null and is_inside_tree() and get_tree().current_scene != null:
		ring.name = "堵桥火圈_%d" % Time.get_ticks_usec()
		get_tree().current_scene.add_child(ring,true)
		ring.call("setup",source,target_position,ring_config)
	queue_free()


func _owner() -> ball:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null
