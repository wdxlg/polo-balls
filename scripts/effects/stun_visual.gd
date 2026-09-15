extends Node2D
class_name StunVisual

# ========================================================
# 可复用眩晕视觉节点
# - 作为目标角色的子节点创建，但 top_level=true，避免继承角色旋转/缩放。
# - 每帧跟随目标的 global_position + follow_offset。
# - AnimatedSprite2D 在场景资源里自动循环 3 帧。
# - 目标失效时自动删除。
# ========================================================

var target:Node2D = null
var follow_offset:Vector2 = Vector2(0.0,-55.0)
var visual_scale:float = 0.055
var draw_z_index:int = 1000

@onready var animated_sprite:AnimatedSprite2D = $AnimatedSprite2D


func setup(
	p_target:Node2D,
	p_offset:Vector2 = Vector2(0.0,-55.0),
	p_scale:float = 0.055,
	p_z_index:int = 1000
) -> void:
	target = p_target
	follow_offset = p_offset
	visual_scale = maxf(p_scale,0.001)
	draw_z_index = p_z_index

	if is_inside_tree():
		_apply_settings()
		_follow_target()


func _ready() -> void:
	_apply_settings()
	_follow_target()

	if animated_sprite:
		animated_sprite.play(&"stun")


func _process(_delta:float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	visible = target.is_visible_in_tree()
	_follow_target()


func _apply_settings() -> void:
	# 不继承人物自身旋转和缩放，并确保它绘制在普通人物图层之上。
	top_level = true
	z_as_relative = false
	z_index = draw_z_index
	scale = Vector2.ONE * visual_scale
	rotation = 0.0


func _follow_target() -> void:
	if target == null or not is_instance_valid(target):
		return

	global_position = target.global_position + follow_offset
	global_rotation = 0.0
