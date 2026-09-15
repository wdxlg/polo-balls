extends Label

var follow_target:Node2D = null
var world_offset:Vector2 = Vector2(7.0,-7.0)
var life_time:float = 1.1
var fade_ratio:float = 0.45
var _elapsed:float = 0.0


func setup(target:Node2D,text_value:String,text_color:Color,font_size:int,duration:float,offset_value:Vector2) -> void:
	follow_target = target
	text = Game.translate_game_text(text_value)
	world_offset = offset_value
	life_time = maxf(duration,0.15)
	add_theme_font_size_override("font_size",maxi(font_size,6))
	add_theme_color_override("font_color",text_color)
	add_theme_color_override("font_outline_color",Color.BLACK)
	add_theme_constant_override("outline_size",1)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = 1000
	size = Vector2(50.0,14.0)
	_update_follow_position()


func _process(delta:float) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		queue_free()
		return

	_elapsed += delta
	_update_follow_position()

	var fade_start:float = life_time * clampf(fade_ratio,0.0,0.95)
	if _elapsed >= fade_start:
		var fade_duration:float = maxf(life_time - fade_start,0.01)
		modulate.a = clampf(1.0 - (_elapsed - fade_start) / fade_duration,0.0,1.0)

	if _elapsed >= life_time:
		queue_free()


func _update_follow_position() -> void:
	# world_offset.x 现在表示“文字右边缘与角色中心的间距”。
	# 这样字体变小后不会因为 Label 自身宽度再额外把文字推得很远。
	var gap:float = maxf(world_offset.x,0.0)
	global_position = Vector2(
		follow_target.global_position.x - gap - size.x,
		follow_target.global_position.y + world_offset.y - size.y * 0.5
	)
