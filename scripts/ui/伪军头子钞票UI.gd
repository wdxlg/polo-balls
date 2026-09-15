extends Node2D

const MONEY_TEXTURE_PATH:String = "res://Images/characters/人物/收债人/收债人_一沓钱.png"

@export_category("伪军头子 - 钞票视觉")
@export var world_offset:Vector2 = Vector2(22.0,-13.0)
@export_range(8.0,48.0,1.0) var bill_longest_size:float = 20.0
@export_range(1.0,14.0,0.25) var bill_vertical_step:float = 7.5
@export_range(0.0,8.0,0.5) var feather_pixels:float = 2.5
@export_range(0.0,1.0,0.01) var empty_image_alpha:float = 0.16
@export_range(0.0,1.0,0.01) var full_image_alpha:float = 1.0

var money_value:float = 3.0
var max_bills:int = 3
var _money_texture:Texture2D = null

func _ready() -> void:
	top_level = true
	z_index = 65
	global_scale = Vector2.ONE
	_load_money_texture()
	queue_redraw()

func _process(_delta:float) -> void:
	var owner_node:Node2D = get_parent() as Node2D
	if owner_node == null or not is_instance_valid(owner_node):
		return
	global_position = owner_node.global_position + world_offset
	global_rotation = 0.0
	global_scale = Vector2.ONE

func set_money(value:float,max_value:int = 3) -> void:
	max_bills = maxi(max_value,1)
	money_value = clampf(value,0.0,float(max_bills))
	if _money_texture == null:
		_load_money_texture()
	queue_redraw()

func _load_money_texture() -> void:
	if _money_texture != null:
		return
	if not ResourceLoader.exists(MONEY_TEXTURE_PATH):
		return
	var resource:Resource = ResourceLoader.load(MONEY_TEXTURE_PATH)
	if resource is Texture2D:
		_money_texture = resource as Texture2D

func _bill_draw_size() -> Vector2:
	if _money_texture == null:
		return Vector2(20.0,12.0)
	var source_size:Vector2 = _money_texture.get_size()
	var longest:float = maxf(source_size.x,source_size.y)
	if longest <= 0.0:
		return Vector2(20.0,12.0)
	return source_size * (maxf(bill_longest_size,1.0) / longest)

func _draw() -> void:
	if _money_texture == null:
		# 收债人图片属于原项目既有资源；附件缺失时只是不显示，不造同义钞票图。
		return
	var draw_size:Vector2 = _bill_draw_size()
	for i:int in range(max_bills):
		# V95：三张钱保持竖排并适度重叠；默认步距让每张都能辨认，又不会回到首尾分离。
		var center := Vector2(0.0,float(i) * bill_vertical_step)
		var outer := Rect2(center - draw_size * 0.5,draw_size)
		# 即使该张还没攒到，也保留一张淡淡的真实收债人钞票轮廓。
		draw_texture_rect(_money_texture,outer,false,Color(1.0,1.0,1.0,empty_image_alpha))
		var progress:float = clampf(money_value - float(i),0.0,1.0)
		_draw_bill_fill(outer,progress)

func _draw_bill_fill(outer:Rect2,progress:float) -> void:
	if _money_texture == null or progress <= 0.0:
		return
	var texture_size:Vector2 = _money_texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	# 真实钞票图片从“下面 -> 上面”逐渐揭示；source_rect 与 dest_rect 同步裁切。
	var fill_height:float = outer.size.y * progress
	var fill_top:float = outer.end.y - fill_height
	var source_height:float = texture_size.y * progress
	var source_top:float = texture_size.y - source_height
	var source_rect := Rect2(Vector2(0.0,source_top),Vector2(texture_size.x,source_height))
	var dest_rect := Rect2(Vector2(outer.position.x,fill_top),Vector2(outer.size.x,fill_height))
	draw_texture_rect_region(_money_texture,dest_rect,source_rect,Color(1.0,1.0,1.0,full_image_alpha),false,true)

	if progress >= 1.0 or feather_pixels <= 0.0:
		return
	# 在当前揭示顶缘向上多画几条越来越透明的真实纹理切片，形成轻微羽化。
	var steps:int = 5
	var dest_band:float = feather_pixels / float(steps)
	var source_per_dest:float = texture_size.y / maxf(outer.size.y,0.001)
	for step:int in range(steps):
		var t:float = float(step + 1) / float(steps)
		var band_bottom:float = fill_top - dest_band * float(step)
		var band_top:float = band_bottom - dest_band
		if band_bottom <= outer.position.y:
			break
		band_top = maxf(band_top,outer.position.y)
		var actual_h:float = band_bottom - band_top
		if actual_h <= 0.0:
			continue
		var src_h:float = actual_h * source_per_dest
		var src_bottom:float = maxf(source_top - src_h * float(step),0.0)
		var src_top:float = maxf(src_bottom - src_h,0.0)
		var alpha:float = full_image_alpha * (1.0 - t) * 0.72
		if alpha <= 0.0:
			continue
		var feather_source := Rect2(Vector2(0.0,src_top),Vector2(texture_size.x,maxf(src_bottom - src_top,0.5)))
		var feather_dest := Rect2(Vector2(outer.position.x,band_top),Vector2(outer.size.x,actual_h))
		draw_texture_rect_region(_money_texture,feather_dest,feather_source,Color(1.0,1.0,1.0,alpha),false,true)
