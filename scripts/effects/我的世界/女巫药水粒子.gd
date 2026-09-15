extends Sprite2D

# 用户提供的 8 帧粒子，严格按素材文件名中的时间顺序播放：
# 21:48:34, 35, 36, 37, 37(1), 38, 39, 40。
const FRAMES = [
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_01.webp"),
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_02.webp"),
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_03.webp"),
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_04.webp"),
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_05.webp"),
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_06.webp"),
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_07.webp"),
	preload("res://Images/characters/我的世界/女巫/药水粒子/药水粒子_08.webp"),
]

var velocity:Vector2 = Vector2(0.0,-28.0)
var frame_time:float = 0.065
var lifetime:float = 0.52
var _elapsed:float = 0.0
var _base_alpha:float = 0.92


func setup(
	world_position:Vector2,
	tint:Color,
	new_velocity:Vector2 = Vector2(0.0,-28.0),
	visual_scale:float = 0.032,
	new_frame_time:float = 0.065,
	absolute_z:int = 80
) -> void:
	global_position = world_position
	velocity = new_velocity
	frame_time = maxf(new_frame_time,0.02)
	lifetime = frame_time * float(FRAMES.size())
	_base_alpha = clampf(tint.a,0.0,1.0)
	var c:Color = tint
	c.a = _base_alpha
	self_modulate = c
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = FRAMES[0]
	scale = Vector2.ONE * maxf(visual_scale,0.005)
	rotation = randf_range(-0.14,0.14)
	z_as_relative = false
	z_index = absolute_z


func _process(delta:float) -> void:
	_elapsed += delta
	global_position += velocity * delta
	velocity.x = move_toward(velocity.x,0.0,10.0 * delta)

	var frame_index:int = clampi(int(_elapsed / frame_time),0,FRAMES.size() - 1)
	texture = FRAMES[frame_index]

	var life_ratio:float = clampf(_elapsed / maxf(lifetime,0.001),0.0,1.0)
	var alpha_ratio:float = 1.0
	if life_ratio > 0.62:
		alpha_ratio = 1.0 - smoothstep(0.62,1.0,life_ratio)
	var c:Color = self_modulate
	c.a = _base_alpha * alpha_ratio
	self_modulate = c

	if _elapsed >= lifetime:
		queue_free()
