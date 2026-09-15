extends Node2D

const SOURCE_TEXTURE_SIZE:float = 1024.0

@onready var _sprite:AnimatedSprite2D = $AnimatedSprite2D

var _rng:=RandomNumberGenerator.new()
var _velocity:Vector2 = Vector2(0.0,-34.0)
var _age:float = 0.0
var _lifetime:float = 0.72
var _base_scale:float = 0.009
var _start_color:Color = Color(0.22,0.22,0.23,0.90)
var _end_color:Color = Color(0.62,0.62,0.60,1.0)


func _ready() -> void:
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/我的世界/MC烟雾粒子.gd:_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())), 1))
	if _sprite != null and not _sprite.animation_finished.is_connected(_on_animation_finished):
		_sprite.animation_finished.connect(_on_animation_finished)
	_restart_visual()


func configure(
	world_position:Vector2,
	visual_diameter:float = 9.0,
	rise_speed:float = 34.0,
	horizontal_drift:float = 8.0,
	z_value:int = 95,
	_lifetime_hint:float = 0.72
) -> void:
	global_position = world_position
	z_as_relative = false
	z_index = z_value
	_base_scale = maxf(visual_diameter,1.0) / SOURCE_TEXTURE_SIZE
	_velocity = Vector2(
		_rng.randf_range(-absf(horizontal_drift),absf(horizontal_drift)),
		-absf(rise_speed) * _rng.randf_range(0.88,1.12)
	)
	var start_gray:float = _rng.randf_range(0.18,0.28)
	var end_gray:float = _rng.randf_range(0.56,0.68)
	# 烟雾不再渐隐：整个 7 -> 0 动画期间保持完全不透明，只改变灰度。
	_start_color = Color(start_gray,start_gray,start_gray + 0.01,1.0)
	_end_color = Color(end_gray,end_gray,end_gray * 0.97,1.0)
	_age = 0.0
	if is_node_ready():
		_restart_visual()


func _restart_visual() -> void:
	if _sprite == null:
		return
	_sprite.frame = 0
	_sprite.frame_progress = 0.0
	_sprite.scale = Vector2.ONE * _base_scale
	_sprite.self_modulate = _start_color
	_lifetime = _smoke_animation_duration()
	_sprite.play(&"smoke")


func _process(delta:float) -> void:
	var safe_delta:float = maxf(delta,0.0)
	_age += safe_delta
	position += _velocity * safe_delta
	if _sprite != null:
		var t:float = clampf(_age / maxf(_lifetime,0.001),0.0,1.0)
		# 贴图序列本身按 7 -> 0 越来越小；这里只保留轻微膨胀与灰度变化。
		# Alpha 始终为 1，不再做渐隐。
		_sprite.scale = Vector2.ONE * lerpf(_base_scale,_base_scale * 1.16,t)
		var shade:Color = _start_color.lerp(_end_color,t)
		shade.a = 1.0
		_sprite.self_modulate = shade


func _smoke_animation_duration() -> float:
	if _sprite == null or _sprite.sprite_frames == null:
		return 0.72
	var frames:SpriteFrames = _sprite.sprite_frames
	var animation_name:StringName = &"smoke"
	if not frames.has_animation(animation_name):
		return 0.72
	var fps:float = maxf(frames.get_animation_speed(animation_name),0.001)
	var duration:float = 0.0
	for frame_index:int in range(frames.get_frame_count(animation_name)):
		duration += frames.get_frame_duration(animation_name,frame_index) / fps
	return maxf(duration,0.05)


func _on_animation_finished() -> void:
	# smoke 是非循环动画。最后一帧完整显示结束后，下一步直接删除节点，
	# 不再额外留一段 alpha 淡出时间。
	if _sprite != null and _sprite.animation == &"smoke":
		queue_free()
