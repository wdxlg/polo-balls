class_name particles
extends GPUParticles2D

@export var master:Node
@export var destroy_self:bool = false

@export var follow_position:bool = true
@export var follow_rotation:bool = true
@export var follow_scale:bool = true
@export var follow_skew:bool = true

@onready var default_position:Vector2 = global_position
@onready var default_rotation:float = global_rotation
@export var position_offset:Vector2 = Vector2.ZERO
@export var rotation_offset:float = 0

@export var delay_emit:float = 0
@onready var delay_emit_time:float = 0
@onready var has_destroying:bool = false

@export var auto_free_one_shot:bool = true

var des_time:float = 0

func _ready() -> void:
	if one_shot and auto_free_one_shot:
		if not finished.is_connected(_on_one_shot_finished):
			finished.connect(_on_one_shot_finished)

func _on_one_shot_finished() -> void:
	if is_inside_tree():
		queue_free()

func follow() -> void:
	if follow_position and is_instance_valid(master):
		global_position = master.global_position + position_offset
	else:
		global_position = position_offset + default_position

	if follow_rotation and is_instance_valid(master):
		global_rotation = master.global_rotation + rotation_offset
	else:
		global_rotation = default_rotation + rotation_offset

	if is_instance_valid(master):
		if follow_scale:
			scale = master.scale
		if follow_skew:
			skew = master.skew

func delay(delta:float) -> void:
	delay_emit_time += delta

	if not has_destroying and delay_emit_time > delay_emit:
		if one_shot:
			restart()
		else:
			emitting = false
		has_destroying = true

func destroy(delta:float) -> void:
	des_time += delta
	if des_time > lifetime:
		queue_free()

func _process(delta:float) -> void:
	var has_master:bool = is_instance_valid(master)

	if not destroy_self:
		if has_master:
			follow()
		else:
			delay(delta)
			if has_destroying:
				destroy(delta)
	else:
		follow()
		delay(delta)
		if has_destroying:
			destroy(delta)
