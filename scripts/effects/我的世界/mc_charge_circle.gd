extends Node2D
## Reusable world-space Minecraft telegraph. The owner supplies authoritative
## charge progress; this visual NEVER advances a timer or triggers damage itself.
const PIXELS = preload("res://scripts/effects/我的世界/pixel_arc.gd")
var radius:float = 80.0
var progress:float = 0.0
var ring_color:Color = Color(1.0,0.22,0.12,0.9)
var fill_color:Color = Color(1.0,0.12,0.06,0.16)

func _ready() -> void:
	set_as_top_level(true) # Parent scale/rotation must not alter the damage radius.
	z_as_relative = false
	z_index = 1
	add_to_group("MCChargeCircle")

func set_charge(point:Vector2,world_radius:float,fraction:float) -> void:
	global_transform = Transform2D(0.0,point)
	radius = maxf(world_radius,0.0)
	progress = clampf(fraction,0.0,1.0)
	queue_redraw()

func fill_radius() -> float:
	return radius*progress

func _draw() -> void:
	PIXELS.draw_disk(self,Vector2.ZERO,fill_radius(),fill_color)
	PIXELS.draw_ring(self,Vector2.ZERO,radius,ring_color)
