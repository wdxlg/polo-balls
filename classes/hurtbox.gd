class_name hurtbox
extends Area2D

@warning_ignore("unused_signal")
signal on_hurt(hit:hitbox)


func _ready() -> void:
	# V410：Hurtbox 只作为 Hitbox 的被检测目标。保留 monitorable，关闭主动 monitoring。
	# 伤害仍由 hitbox.area_entered -> try_hit_hurtbox() 触发，不改变任何命中结果。
	set_deferred(&"monitorable",true)
	set_deferred(&"monitoring",false)
	input_pickable = false
