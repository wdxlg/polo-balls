extends StaticBody2D

signal landed(cell:Vector2i)

# 时光的围棋子是实体地形：只占角色物理层 2，避免额外拦截只撞墙体层 1 的投射物。
# 角色基类 collision_mask=3，因此落地后的棋子会正常挡住角色。
var cell:Vector2i = Vector2i.ZERO
var color_slot:int = 0
var stone_radius:float = 6.0
var fall_height:float = 105.0
var fall_duration:float = 0.30

var _fall_offset_y:float = 0.0
var _removed:bool = false
var _landed:bool = false
var _fall_tween:Tween = null
var _terrain_shape:CollisionShape2D = null


func configure(cell_value:Vector2i, color_value:int, radius_value:float, fall_height_value:float, fall_duration_value:float) -> void:
	cell = cell_value
	color_slot = clampi(color_value,0,1)
	stone_radius = maxf(radius_value,2.0)
	fall_height = maxf(fall_height_value,0.0)
	fall_duration = maxf(fall_duration_value,0.05)
	set_meta("wall_hit_use_raw_contact",true)
	set_meta("wall_hit_visual_width",stone_radius)
	if is_inside_tree():
		_build_collision_shape()


func _ready() -> void:
	add_to_group("AI_Hazard")
	# 与项目原有“棋子”实体规则一致：服务器/authority 负责真实阻挡，远端只保留视觉。
	collision_layer = 2 if (not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()) else 0
	collision_mask = 0
	z_as_relative = false
	z_index = 36
	set_meta("wall_hit_use_raw_contact",true)
	set_meta("wall_hit_visual_width",stone_radius)
	_build_collision_shape()
	_fall_offset_y = -fall_height
	queue_redraw()
	_start_fall()


func _build_collision_shape() -> void:
	if _terrain_shape == null or not is_instance_valid(_terrain_shape):
		_terrain_shape = CollisionShape2D.new()
		_terrain_shape.name = "StoneCollision"
		add_child(_terrain_shape)
	var circle := CircleShape2D.new()
	circle.radius = stone_radius
	_terrain_shape.shape = circle
	# 棋子从空中落下时不阻挡；真正落地后再打开实体碰撞。
	_terrain_shape.disabled = not _landed or _removed


func _draw() -> void:
	var center := Vector2(0.0,_fall_offset_y)
	if not _removed:
		var shadow_alpha:float = 0.12 if not _landed else 0.20
		draw_circle(Vector2(2.1,2.4),stone_radius * 1.08,Color(0.0,0.0,0.0,shadow_alpha))
	if color_slot == 0:
		draw_circle(center,stone_radius,Color(0.025,0.028,0.032,1.0))
		draw_arc(center,stone_radius * 0.92,0.0,TAU,28,Color(0.16,0.17,0.18,0.55),0.55,true)
	else:
		draw_circle(center,stone_radius + 0.75,Color(0.06,0.065,0.075,0.96))
		draw_circle(center,stone_radius,Color(0.96,0.96,0.94,1.0))
		draw_arc(center,stone_radius * 0.86,0.0,TAU,28,Color(1.0,1.0,1.0,0.75),0.48,true)


func _start_fall() -> void:
	if _removed:
		return
	_landed = false
	if _terrain_shape != null and is_instance_valid(_terrain_shape):
		_terrain_shape.set_deferred("disabled",true)
	if _fall_tween != null and _fall_tween.is_valid():
		_fall_tween.kill()
	_fall_tween = create_tween()
	_fall_tween.tween_method(_set_fall_progress,0.0,1.0,fall_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fall_tween.tween_callback(_finish_land)


func _set_fall_progress(value:float) -> void:
	if _removed:
		return
	_fall_offset_y = lerpf(-fall_height,0.0,clampf(value,0.0,1.0))
	queue_redraw()


func _finish_land() -> void:
	if _removed:
		return
	_landed = true
	_fall_offset_y = 0.0
	if _terrain_shape != null and is_instance_valid(_terrain_shape):
		var gameplay_authority:bool = not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()
		_terrain_shape.set_deferred("disabled",not gameplay_authority)
	queue_redraw()
	var bounce := create_tween()
	bounce.tween_property(self,"scale",Vector2(1.14,0.86),0.045)
	bounce.tween_property(self,"scale",Vector2.ONE,0.075).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	landed.emit(cell)


func play_capture() -> void:
	if _removed:
		return
	_removed = true
	if _terrain_shape != null and is_instance_valid(_terrain_shape):
		_terrain_shape.set_deferred("disabled",true)
	if _fall_tween != null and _fall_tween.is_valid():
		_fall_tween.kill()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self,"position:y",position.y - 16.0,0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self,"scale",Vector2.ONE * 0.38,0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self,"modulate:a",0.0,0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func is_landed_stone() -> bool:
	return _landed and not _removed


# 给高级 AI/调试层一个可复用的实体障碍描述；没有额外接触伤害。
func get_ai_hazard_info(receiver:ball) -> Dictionary:
	if not _landed or _removed:
		return {}
	if receiver == null or not is_instance_valid(receiver):
		return {}
	return {
		"shape":"circle",
		"position":global_position,
		"velocity":Vector2.ZERO,
		"radius":stone_radius,
		"kind":"go_stone",
		"blocking":true,
		"damage":0.0,
		"source":self,
	}
