extends Node2D

const MISSILE_TEXTURE:Texture2D = preload("res://Images/characters/人物/炮兵/导弹.png")
const SMOKE_TEXTURE:Texture2D = preload("res://Images/characters/人物/炮兵/烟雾.png")

# 炮兵齐射的纯视觉节点。
# 逻辑伤害由炮兵本体（authority）结算；这个节点只负责：
# 绿色虚线作战区域、中心加号、红色落点、收缩角框、落弹、爆炸和烟雾视觉。
#
# v20：
# - 红圈出现到命中的总时长由“导弹发射.mp3”的真实长度驱动（由炮兵.gd传入分段时间）。
# - 导弹中心在地图外时完全隐藏；进入地图后才显示，尾迹也裁到地图矩形内。
# - 爆炸改为多层实心圆扩大并渐隐；越内层越灰、消失越快。
# - v21：烟雾改用用户提供的透明 PNG；每团随机从橙色到灰白色染色，并随机旋转/大小/漂移后向上消散。
# - v22：绿色大范围锁敌后使用淡入/收拢、慢速旋转，并在最后一枚导弹发射时反向淡出/放大。
# - v23：炮弹命中瞬间增加白色圆环描边冲击波，扩大并渐隐。

var barrage_radius:float = 55.0
var strike_radius:float = 21.0
var strike_points:PackedVector2Array = PackedVector2Array()
var strike_radii:PackedFloat32Array = PackedFloat32Array()
var strike_reveal_delays:PackedFloat32Array = PackedFloat32Array()
var warning_duration:float = 1.55
var warning_hold_duration:float = 0.12
var shell_fall_duration:float = 0.24
var explosion_visual_duration:float = 0.82
var impact_ring_duration:float = 0.58
var smoke_visual_duration:float = 1.75
var shell_start_height:float = 165.0
var map_rect:Rect2 = Rect2()

# 绿色大范围视觉：出现时从略大收拢到真实范围并淡入；
# 最后一枚导弹开始发射时反向放大淡出。
var command_area_intro_duration:float = 0.40
var command_area_outro_duration:float = 0.40
var command_area_intro_scale:float = 1.07
var command_area_rotation_speed_deg:float = 6.0

var _elapsed:float = 0.0
var _lifetime:float = 2.5
var _shell_sprites:Array[Sprite2D] = []
var _smoke_sprites:Array[Sprite2D] = []
var _smoke_meta:Array[Dictionary] = []

const SMOKE_PUFFS_PER_STRIKE:int = 9
const SMOKE_ORANGE:Color = Color(1.0,0.34,0.08,1.0)
const SMOKE_GRAY_WHITE:Color = Color(0.88,0.90,0.92,1.0)

const GREEN:Color = Color(0.18,1.0,0.36,1.0)
const GREEN_SOFT:Color = Color(0.18,1.0,0.36,0.18)
const RED:Color = Color(1.0,0.12,0.10,0.96)
const RED_SOFT:Color = Color(1.0,0.12,0.10,0.25)
const SHELL_HIGHLIGHT:Color = Color(1.0,0.86,0.48,0.92)


func _ready() -> void:
	# 地图外视觉遮罩在 World 的 z=90；炮兵视觉保持在其下方。
	z_index = 80
	add_to_group("BattleTransient")
	add_to_group("ArtilleryBarrageVisual")

	var max_reveal_delay:float = 0.0
	for value:float in strike_reveal_delays:
		max_reveal_delay = maxf(max_reveal_delay,value)
	_lifetime = (
		max_reveal_delay
		+ maxf(warning_duration,0.05)
		+ maxf(warning_hold_duration,0.0)
		+ maxf(shell_fall_duration,0.05)
		+ maxf(maxf(explosion_visual_duration,smoke_visual_duration),0.05)
		+ 0.16
	)
	_create_shell_sprites()
	_create_smoke_sprites()
	_update_shell_sprites()
	_update_smoke_sprites()
	queue_redraw()


func _process(delta:float) -> void:
	_elapsed += delta
	_update_shell_sprites()
	_update_smoke_sprites()
	queue_redraw()
	if _elapsed >= _lifetime:
		queue_free()


func _draw() -> void:
	_draw_command_area()
	for i:int in range(strike_points.size()):
		var local_point:Vector2 = strike_points[i] - global_position
		var reveal_delay:float = strike_reveal_delays[i] if i < strike_reveal_delays.size() else 0.0
		var actual_radius:float = strike_radii[i] if i < strike_radii.size() else strike_radius
		_draw_strike(local_point,reveal_delay,actual_radius,i)


func _draw_command_area() -> void:
	# 炮击中心理论上始终在地图内；若切图过程中旧视觉落到新地图外，则直接不绘制。
	if not _is_world_point_inside_map(global_position):
		return

	var intro_duration:float = maxf(command_area_intro_duration,0.05)
	var outro_duration:float = maxf(command_area_outro_duration,0.05)
	var overscale:float = maxf(command_area_intro_scale,1.0)

	# 最后一枚“导弹发射”的时刻就是最后一个红圈 reveal 的时刻。
	var last_launch_time:float = 0.0
	for delay:float in strike_reveal_delays:
		last_launch_time = maxf(last_launch_time,delay)

	var alpha_factor:float = 1.0
	var area_scale:float = 1.0
	if _elapsed < intro_duration:
		# EASE_OUT/CUBIC：开始变化快，越接近实际范围越慢。
		var t_in:float = clampf(_elapsed / intro_duration,0.0,1.0)
		var ease_out:float = 1.0 - pow(1.0 - t_in,3.0)
		alpha_factor = ease_out
		area_scale = lerpf(overscale,1.0,ease_out)

	if _elapsed >= last_launch_time:
		# 与出现相反：最后一枚导弹发射时开始，先慢后快地微微放大并淡出。
		var t_out:float = clampf((_elapsed - last_launch_time) / outro_duration,0.0,1.0)
		var ease_in:float = pow(t_out,3.0)
		alpha_factor *= 1.0 - ease_in
		area_scale = lerpf(1.0,overscale,ease_in)
		if t_out >= 1.0:
			return

	var displayed_radius:float = maxf(barrage_radius * area_scale,1.0)
	var rotation_phase:float = deg_to_rad(command_area_rotation_speed_deg) * _elapsed
	var strong_green:Color = Color(GREEN.r,GREEN.g,GREEN.b,GREEN.a * alpha_factor)
	var soft_green:Color = Color(GREEN_SOFT.r,GREEN_SOFT.g,GREEN_SOFT.b,GREEN_SOFT.a * alpha_factor)

	# 内侧柔和圆环和外侧虚线一起跟随半径动画；虚线缓慢旋转。
	draw_arc(Vector2.ZERO,maxf(displayed_radius - 3.0,1.0),0.0,TAU,96,soft_green,2.0,true)
	_draw_dashed_circle(Vector2.ZERO,displayed_radius,strong_green,3.0,42,0.56,rotation_phase)

	var plus_half:float = clampf(barrage_radius * 0.075,10.0,22.0) * area_scale
	var plus_width:float = 3.5
	draw_line(Vector2(-plus_half,0.0),Vector2(plus_half,0.0),strong_green,plus_width,true)
	draw_line(Vector2(0.0,-plus_half),Vector2(0.0,plus_half),strong_green,plus_width,true)


func _draw_strike(point:Vector2,reveal_delay:float,actual_radius:float,_strike_index:int) -> void:
	var world_point:Vector2 = global_position + point
	if not _is_world_point_inside_map(world_point):
		return

	var warn_time:float = maxf(warning_duration,0.05)
	var hold_time:float = maxf(warning_hold_duration,0.0)
	var fall_time:float = maxf(shell_fall_duration,0.05)
	var local_time:float = _elapsed - reveal_delay
	if local_time < 0.0:
		return
	var radius:float = maxf(actual_radius,1.0)

	var warning_progress:float = clampf(local_time / warn_time,0.0,1.0)
	var eased:float = 1.0 - pow(1.0 - warning_progress,3.0)
	var shell_start:float = warn_time + hold_time
	var impact_time:float = shell_start + fall_time

	if local_time < impact_time:
		var fixed_red:Color = RED
		var soft_red:Color = RED_SOFT

		# 最终真实爆炸半径：从红圈出现的一刻就显示。
		draw_arc(point,radius,0.0,TAU,64,fixed_red,3.0,true)

		# 内部是完整实心圆，从中心不断放大。
		var inner_radius:float = lerpf(maxf(2.0,radius * 0.08),radius,eased)
		draw_circle(point,inner_radius,soft_red)

		# 外层方框从大到小，只画四角；最终贴到爆炸圆外接正方形。
		var square_half:float = lerpf(radius * 1.88,radius,eased)
		_draw_corner_square(point,square_half,radius * 0.34,fixed_red,3.2)

	# 最后一小段才显示真正导弹，发射音效则从红圈出现时已经开始播放。
	if local_time >= shell_start and local_time < impact_time:
		var shell_progress:float = clampf((local_time - shell_start) / fall_time,0.0,1.0)
		var fall_eased:float = shell_progress * shell_progress
		var shell_pos:Vector2 = point + Vector2(0.0,lerpf(-shell_start_height,0.0,fall_eased))
		var shell_world:Vector2 = global_position + shell_pos
		if _is_world_point_inside_map(shell_world):
			var trail_top:Vector2 = shell_pos + Vector2(0.0,-28.0 - 24.0 * shell_progress)
			var trail_top_world:Vector2 = global_position + trail_top
			var clipped_top_world:Vector2 = _clamp_world_point_to_map(trail_top_world)
			draw_line(clipped_top_world - global_position,shell_pos,SHELL_HIGHLIGHT,2.4,true)

	# 命中：白色冲击波描边 + 多层爆炸圆 + 上升烟雾。
	if local_time >= impact_time:
		var after_impact:float = local_time - impact_time
		_draw_impact_ring(point,radius,after_impact)
		_draw_explosion_layers(point,radius,after_impact)


func _draw_impact_ring(point:Vector2,radius:float,elapsed:float) -> void:
	# 炮弹接触地面的同一帧出现一个清晰的白色圆环。
	# 圆环从爆心快速扩张到爆炸范围之外，同时逐渐变细、变透明。
	var duration:float = maxf(impact_ring_duration,0.05)
	var t:float = clampf(elapsed / duration,0.0,1.0)
	if t >= 1.0:
		return

	# 先快后慢，让命中瞬间有明显冲击感。
	var eased:float = 1.0 - pow(1.0 - t,3.0)
	var ring_radius:float = lerpf(maxf(radius * 0.12,2.0),radius * 1.72,eased)
	var alpha:float = 0.96 * pow(1.0 - t,1.35)
	var width:float = lerpf(4.2,1.2,eased)
	draw_arc(point,ring_radius,0.0,TAU,72,Color(1.0,1.0,1.0,alpha),width,true)


func _draw_explosion_layers(point:Vector2,radius:float,elapsed:float) -> void:
	# 从外到内：越靠中心越接近纯灰，并且淡出时长越短。
	# 每层都是“实心圆扩大 + 渐隐”，而不是只画描边。
	var target_scales:PackedFloat32Array = PackedFloat32Array([1.34,1.08,0.82,0.58])
	var fade_durations:PackedFloat32Array = PackedFloat32Array([0.82,0.64,0.46,0.32])
	var colors:Array[Color] = [
		Color(0.92,0.40,0.12,0.34),
		Color(0.61,0.54,0.47,0.40),
		Color(0.48,0.48,0.48,0.46),
		Color(0.34,0.34,0.34,0.52),
	]

	for i:int in range(target_scales.size()):
		var duration:float = maxf(fade_durations[i],0.05)
		var t:float = clampf(elapsed / duration,0.0,1.0)
		if t >= 1.0:
			continue
		var expand:float = 1.0 - pow(1.0 - t,3.0)
		var layer_radius:float = lerpf(radius * 0.10,radius * target_scales[i],expand)
		var alpha:float = pow(1.0 - t,1.35)
		var base:Color = colors[i]
		draw_circle(point,layer_radius,Color(base.r,base.g,base.b,base.a * alpha))


func _create_smoke_sprites() -> void:
	_smoke_sprites.clear()
	_smoke_meta.clear()

	var texture_extent:float = maxf(maxf(SMOKE_TEXTURE.get_size().x,SMOKE_TEXTURE.get_size().y),1.0)
	for strike_index:int in range(strike_points.size()):
		for puff:int in range(SMOKE_PUFFS_PER_STRIKE):
			# 每一团烟固定一个独立随机种子，保证每帧更新时不会抖动。
			var rng:= RandomNumberGenerator.new()
			rng.seed = int((strike_index + 1) * 104729 + (puff + 1) * 13007)

			var sprite:= Sprite2D.new()
			sprite.texture = SMOKE_TEXTURE
			sprite.centered = true
			sprite.visible = false
			sprite.z_index = 5
			sprite.rotation = rng.randf_range(-PI,PI)
			add_child(sprite)

			# 每团烟在橙色 -> 灰白色之间独立随机。
			# self_modulate 只给这一张 Sprite2D 染色，不会影响其他炮击节点。
			var tint_mix:float = rng.randf_range(0.0,1.0)
			var tint:Color = SMOKE_ORANGE.lerp(SMOKE_GRAY_WHITE,tint_mix)
			var meta:Dictionary = {
				"strike_index": strike_index,
				"delay": rng.randf_range(0.02,0.22) + float(puff) * rng.randf_range(0.008,0.022),
				"duration": rng.randf_range(0.82,1.38),
				"offset_x": rng.randf_range(-0.46,0.46),
				"offset_y": rng.randf_range(-0.16,0.18),
				"drift_x": rng.randf_range(-1.55,1.55),
				"rise": rng.randf_range(1.25,3.25),
				"sway_phase": rng.randf_range(0.0,TAU),
				"sway_amount": rng.randf_range(0.08,0.32),
				"start_size": rng.randf_range(0.82,1.22),
				"end_size": rng.randf_range(2.05,3.25),
				"alpha": rng.randf_range(0.44,0.72),
				"rotation_speed": rng.randf_range(-0.42,0.42),
				"base_rotation": sprite.rotation,
				"tint": tint,
				"texture_extent": texture_extent,
			}
			_smoke_sprites.append(sprite)
			_smoke_meta.append(meta)


func _update_smoke_sprites() -> void:
	var count:int = mini(_smoke_sprites.size(),_smoke_meta.size())
	for i:int in range(count):
		var sprite:Sprite2D = _smoke_sprites[i]
		if not is_instance_valid(sprite):
			continue

		var meta:Dictionary = _smoke_meta[i]
		var strike_index:int = int(meta.get("strike_index",0))
		if strike_index < 0 or strike_index >= strike_points.size():
			sprite.visible = false
			continue

		var reveal_delay:float = strike_reveal_delays[strike_index] if strike_index < strike_reveal_delays.size() else 0.0
		var warn_time:float = maxf(warning_duration,0.05)
		var hold_time:float = maxf(warning_hold_duration,0.0)
		var fall_time:float = maxf(shell_fall_duration,0.05)
		var impact_time:float = reveal_delay + warn_time + hold_time + fall_time
		var smoke_time:float = _elapsed - impact_time - float(meta.get("delay",0.0))
		var duration:float = maxf(float(meta.get("duration",1.0)),0.05)
		if smoke_time < 0.0 or smoke_time >= duration:
			sprite.visible = false
			continue

		var t:float = clampf(smoke_time / duration,0.0,1.0)
		var rise_t:float = 1.0 - pow(1.0 - t,2.0)
		var actual_radius:float = strike_radii[strike_index] if strike_index < strike_radii.size() else strike_radius
		actual_radius = maxf(actual_radius,1.0)
		var local_impact:Vector2 = strike_points[strike_index] - global_position

		var side:float = actual_radius * (
			float(meta.get("offset_x",0.0))
			+ float(meta.get("drift_x",0.0)) * t
			+ sin(float(meta.get("sway_phase",0.0)) + t * 4.0) * float(meta.get("sway_amount",0.0))
		)
		var vertical:float = actual_radius * float(meta.get("offset_y",0.0)) - actual_radius * float(meta.get("rise",2.0)) * rise_t
		sprite.position = local_impact + Vector2(side,vertical)

		# 地图外中心不显示；贴边部分仍由 World 的地图外遮罩继续裁掉。
		if not _is_world_point_inside_map(sprite.global_position):
			sprite.visible = false
			continue

		var size_factor:float = lerpf(float(meta.get("start_size",1.0)),float(meta.get("end_size",2.5)),rise_t)
		var target_size:float = actual_radius * size_factor
		var texture_extent:float = maxf(float(meta.get("texture_extent",630.0)),1.0)
		var uniform_scale:float = target_size / texture_extent
		sprite.scale = Vector2(uniform_scale,uniform_scale)
		sprite.rotation = float(meta.get("base_rotation",0.0)) + float(meta.get("rotation_speed",0.0)) * smoke_time

		# 快速淡入后逐渐消失；颜色本身随机处于橙色与灰白之间，
		# 随生命周期再轻微向灰白过渡，让爆心附近偏暖、飘高后偏灰。
		var fade_in:float = clampf(t / 0.14,0.0,1.0)
		var fade_out:float = pow(1.0 - t,1.45)
		var alpha:float = float(meta.get("alpha",0.58)) * fade_in * fade_out
		var base_tint:Color = meta.get("tint",SMOKE_GRAY_WHITE)
		var current_tint:Color = base_tint.lerp(SMOKE_GRAY_WHITE,t * 0.34)
		sprite.self_modulate = Color(current_tint.r,current_tint.g,current_tint.b,alpha)
		sprite.visible = true


func _create_shell_sprites() -> void:
	_shell_sprites.clear()
	for i:int in range(strike_points.size()):
		var sprite:= Sprite2D.new()
		sprite.texture = MISSILE_TEXTURE
		sprite.centered = true
		# 新透明素材的弹头沿右上方向；旋转约 140° 后弹头朝屏幕下方（+Y）。
		sprite.rotation = deg_to_rad(140.0)
		sprite.visible = false
		sprite.z_index = 3

		var actual_radius:float = strike_radii[i] if i < strike_radii.size() else strike_radius
		var target_length:float = clampf(actual_radius * 2.15,24.0,38.0)
		var texture_length:float = maxf(maxf(MISSILE_TEXTURE.get_size().x,MISSILE_TEXTURE.get_size().y),1.0)
		var uniform_scale:float = target_length / texture_length
		sprite.scale = Vector2(uniform_scale,uniform_scale)

		add_child(sprite)
		_shell_sprites.append(sprite)


func _update_shell_sprites() -> void:
	var count:int = mini(_shell_sprites.size(),strike_points.size())
	for i:int in range(count):
		var sprite:Sprite2D = _shell_sprites[i]
		if not is_instance_valid(sprite):
			continue

		var reveal_delay:float = strike_reveal_delays[i] if i < strike_reveal_delays.size() else 0.0
		var local_time:float = _elapsed - reveal_delay
		var warn_time:float = maxf(warning_duration,0.05)
		var hold_time:float = maxf(warning_hold_duration,0.0)
		var fall_time:float = maxf(shell_fall_duration,0.05)
		var shell_start:float = warn_time + hold_time
		var impact_time:float = shell_start + fall_time

		if local_time >= shell_start and local_time < impact_time:
			var shell_progress:float = clampf((local_time - shell_start) / fall_time,0.0,1.0)
			var fall_eased:float = shell_progress * shell_progress
			var local_point:Vector2 = strike_points[i] - global_position
			sprite.position = local_point + Vector2(0.0,lerpf(-shell_start_height,0.0,fall_eased))
			# 关键：导弹中心还在地图黑线外时，Sprite2D 本体完全不显示。
			# 进入地图内之后才出现；地图外遮罩仍负责裁掉贴边时的少量外露像素。
			sprite.visible = _is_world_point_inside_map(sprite.global_position)
		else:
			sprite.visible = false


func _is_world_point_inside_map(world_point:Vector2) -> bool:
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return true
	return map_rect.has_point(world_point)


func _clamp_world_point_to_map(world_point:Vector2) -> Vector2:
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return world_point
	return Vector2(
		clampf(world_point.x,map_rect.position.x,map_rect.end.x),
		clampf(world_point.y,map_rect.position.y,map_rect.end.y)
	)


func _draw_dashed_circle(
	center:Vector2,
	radius:float,
	color:Color,
	width:float,
	dash_count:int,
	fill_ratio:float,
	phase_offset:float = 0.0
) -> void:
	var count:int = maxi(dash_count,8)
	var ratio:float = clampf(fill_ratio,0.1,0.9)
	for i:int in range(count):
		var begin:float = phase_offset + TAU * float(i) / float(count)
		var finish:float = begin + TAU / float(count) * ratio
		draw_arc(center,radius,begin,finish,5,color,width,true)


func _draw_corner_square(
	center:Vector2,
	half_extent:float,
	corner_length:float,
	color:Color,
	width:float
) -> void:
	var h:float = maxf(half_extent,2.0)
	var l:float = clampf(corner_length,4.0,h)
	var tl:Vector2 = center + Vector2(-h,-h)
	var tr:Vector2 = center + Vector2(h,-h)
	var bl:Vector2 = center + Vector2(-h,h)
	var br:Vector2 = center + Vector2(h,h)

	# 左上
	draw_line(tl,tl + Vector2(l,0.0),color,width,true)
	draw_line(tl,tl + Vector2(0.0,l),color,width,true)
	# 右上
	draw_line(tr,tr + Vector2(-l,0.0),color,width,true)
	draw_line(tr,tr + Vector2(0.0,l),color,width,true)
	# 左下
	draw_line(bl,bl + Vector2(l,0.0),color,width,true)
	draw_line(bl,bl + Vector2(0.0,-l),color,width,true)
	# 右下
	draw_line(br,br + Vector2(-l,0.0),color,width,true)
	draw_line(br,br + Vector2(0.0,-l),color,width,true)
