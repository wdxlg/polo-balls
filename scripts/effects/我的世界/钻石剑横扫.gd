extends Node2D

const FRAMES = [
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫0.png"),
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫1.png"),
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫2.png"),
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫3.png"),
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫4.png"),
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫5.png"),
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫6.png"),
	preload("res://Images/characters/我的世界/钻石剑/横扫之刃/横扫7.png"),
]

# 每一帧真正有非透明像素的包围盒（原图均为 1024x1024）。
# V132 横扫伤害直接使用这个可见区域对应的世界矩形，而不是角色身边的大圆。
const FRAME_BOUNDS = [
	Rect2(704.0,384.0,288.0,288.0),
	Rect2(256.0,352.0,736.0,320.0),
	Rect2(32.0,352.0,960.0,320.0),
	Rect2(32.0,352.0,960.0,320.0),
	Rect2(32.0,352.0,832.0,320.0),
	Rect2(32.0,352.0,736.0,320.0),
	Rect2(32.0,352.0,480.0,320.0),
	Rect2(32.0,448.0,224.0,224.0),
]

var _sprite:Sprite2D = null
var _origin:Vector2 = Vector2.ZERO
var _direction:Vector2 = Vector2.RIGHT
var _elapsed:float = 0.0
var _duration:float = 0.34
var _start_distance:float = 18.0
var _spread_distance:float = 54.0
var _start_scale:float = 0.048
var _end_scale:float = 0.078
var _configured:bool = false
var _damage_owner:Node = null


func _ready() -> void:
	top_level = true
	z_as_relative = false
	# 地图外视觉遮罩位于 z=90；横扫是攻击反馈，不应被地图边界裁掉。
	z_index = 98
	_sprite = Sprite2D.new()
	_sprite.name = "SweepSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	add_child(_sprite)
	set_process(false)


func configure(
	origin:Vector2,
	direction_value:Vector2,
	mirror:bool = false,
	duration_value:float = 0.34,
	start_distance_value:float = 18.0,
	spread_distance_value:float = 54.0,
	damage_owner:Node = null
) -> void:
	_origin = origin
	_direction = direction_value.normalized() if direction_value.length_squared() > 0.000001 else Vector2.RIGHT
	_duration = maxf(duration_value,0.08)
	_start_distance = maxf(start_distance_value,0.0)
	_spread_distance = maxf(spread_distance_value,0.0)
	_damage_owner = damage_owner
	_elapsed = 0.0
	_configured = true
	# 横扫素材的“正前方”是本地 UP；旋转 +90° 后让弧面的凸出方向对准目标。
	rotation = _direction.angle() + PI * 0.5
	global_position = _origin + _direction * _start_distance
	if _sprite != null:
		# mirror 仅保留在 API 里兼容旧调用；弧面正面始终朝敌人。
		_sprite.flip_h = false
		_sprite.flip_v = false
		_sprite.texture = FRAMES[0]
		_sprite.scale = Vector2.ONE * _start_scale
		_sprite.modulate = Color.WHITE
	set_process(true)


func _process(delta:float) -> void:
	if not _configured or _sprite == null:
		return
	_elapsed += maxf(delta,0.0)
	var progress:float = clampf(_elapsed / _duration,0.0,1.0)

	# 横扫不跟着角色：_origin 在生成那一刻就锁死，之后只沿攻击方向向前推进。
	# 同时明显放大并逐渐透明，形成“向前扩散出去”的效果。
	var move_eased:float = 1.0 - pow(1.0 - progress,2.15)
	var scale_eased:float = 1.0 - pow(1.0 - progress,1.65)
	var frame_index:int = clampi(int(floor(progress * float(FRAMES.size()))),0,FRAMES.size() - 1)
	_sprite.texture = FRAMES[frame_index]
	var current_scale:float = lerpf(_start_scale,_end_scale,scale_eased)
	_sprite.scale = Vector2.ONE * current_scale
	global_position = _origin + _direction * (_start_distance + _spread_distance * move_eased)

	var fade:float = 1.0
	if progress > 0.46:
		fade = 1.0 - smoothstep(0.46,1.0,progress)
	_sprite.modulate = Color(1.0,1.0,1.0,clampf(fade,0.0,1.0))

	_apply_visual_damage(frame_index,current_scale)
	if progress >= 1.0:
		queue_free()


func _apply_visual_damage(frame_index:int,current_scale:float) -> void:
	if _damage_owner == null or not is_instance_valid(_damage_owner):
		return
	if not _damage_owner.has_method("_deal_sweep_visual_damage"):
		return
	if frame_index < 0 or frame_index >= FRAME_BOUNDS.size():
		return

	var bounds:Rect2 = FRAME_BOUNDS[frame_index]
	var local_center_px:Vector2 = bounds.position + bounds.size * 0.5 - Vector2(512.0,512.0)
	var local_center:Vector2 = local_center_px * current_scale
	var world_center:Vector2 = global_transform * local_center
	var world_size:Vector2 = bounds.size * current_scale
	_damage_owner.call("_deal_sweep_visual_damage",world_center,world_size,global_rotation)
