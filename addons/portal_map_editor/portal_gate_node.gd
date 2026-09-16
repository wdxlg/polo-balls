@tool
extends Marker2D
# 旧场景兼容占位。PortalMap 打开场景时迁移为原生瓦片层。
@export var link:Resource
@export var is_exit:bool = false
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	visible = false
