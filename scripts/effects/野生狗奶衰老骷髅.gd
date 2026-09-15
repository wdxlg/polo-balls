extends Node2D

# 野生狗奶衰老视觉：骷髅头跟随目标世界位置。
# V307：视觉进一步缩小，并继续放在人物之上、速度线/血条之下。
# 透明度与衰老百分比线性对应；显示透明度达到 95% 后开始颤抖；100% 时立即消失。

const SKULL_TEXTURE:Texture2D = preload("res://Images/characters/meme/野生狗奶/头(1).png")

var _target:ball = null
var _sprite:Sprite2D = null
var _world_size:float = 28.0
var _shake_start_opacity:float = 0.95
var _shake_max_offset:float = 5.0
var _shake_rotation_deg:float = 3.0
var _age_ratio:float = 0.0
var _phase:float = 0.0


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_phase = float(get_instance_id() % 997) * 0.031

	_sprite = Sprite2D.new()
	_sprite.name = "Skull"
	_sprite.texture = SKULL_TEXTURE
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)
	_apply_world_size()
	modulate = Color(1.0,1.0,1.0,0.0)
	visible = false


func setup(
	target:ball,
	world_size:float,
	shake_start_opacity:float,
	shake_max_offset:float,
	shake_rotation_deg:float
) -> void:
	_target = target
	_world_size = maxf(world_size,1.0)
	_shake_start_opacity = clampf(shake_start_opacity,0.0,0.99)
	_shake_max_offset = maxf(shake_max_offset,0.0)
	_shake_rotation_deg = maxf(shake_rotation_deg,0.0)
	_apply_world_size()
	_snap_to_target()


func set_age_percent(age_percent:float,death_percent:float) -> void:
	var safe_death:float = maxf(death_percent,0.001)
	_age_ratio = clampf(age_percent / safe_death,0.0,1.0)

	if _age_ratio >= 0.9999:
		visible = false
		modulate.a = 0.0
		queue_free()
		return

	visible = _age_ratio > 0.0001
	modulate.a = _age_ratio
	if _age_ratio < _shake_start_opacity:
		rotation = 0.0
	_snap_to_target()


func _process(_delta:float) -> void:
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	if _target.health <= 0:
		visible = false
		queue_free()
		return
	if not visible:
		return

	var base_position:Vector2 = _target.global_position
	if modulate.a >= _shake_start_opacity:
		var shake_t:float = clampf(
			(modulate.a - _shake_start_opacity) / maxf(1.0 - _shake_start_opacity,0.001),
			0.0,
			1.0
		)
		var now:float = float(Time.get_ticks_msec()) * 0.001
		var strength:float = lerpf(_shake_max_offset * 0.35,_shake_max_offset,shake_t)
		var shake_offset:Vector2 = Vector2(
			sin(now * 67.0 + _phase),
			sin(now * 79.0 + _phase * 1.73)
		) * strength
		global_position = base_position + shake_offset
		rotation = sin(now * 83.0 + _phase * 0.67) * deg_to_rad(_shake_rotation_deg) * maxf(shake_t,0.25)
	else:
		global_position = base_position
		rotation = 0.0


func _apply_world_size() -> void:
	if _sprite == null or not is_instance_valid(_sprite) or SKULL_TEXTURE == null:
		return
	var texture_size:Vector2 = SKULL_TEXTURE.get_size()
	var max_dimension:float = maxf(texture_size.x,texture_size.y)
	if max_dimension <= 0.0:
		return
	var uniform_scale:float = _world_size / max_dimension
	_sprite.scale = Vector2(uniform_scale,uniform_scale)


func _snap_to_target() -> void:
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position
