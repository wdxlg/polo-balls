extends SceneTree
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func run() -> void:
	create_timer(20.0).timeout.connect(func(): finish(2))
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await process_frame
	await process_frame
	# 直接驱动轮放 HUD：用真实布局把 HUD 放到地图上方，然后放两个"当前"名字，
	# 左边标记为真正战死、右边标记为清场（灰）。
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	await process_frame
	var map_rect:Rect2 = world.return_map_visual_rect(world.map_group["Map10x10"])
	world.rotation_versus_root.visible = true
	world.rotation_versus_root.position = Vector2(map_rect.position.x,map_rect.position.y - 70.0)
	world.rotation_versus_root.size = Vector2(map_rect.size.x,58)
	var side_w:float = (map_rect.size.x - 28.0) * 0.5
	world.rotation_left_root.position = Vector2.ZERO
	world.rotation_left_root.size = Vector2(side_w,58)
	world.rotation_right_root.position = Vector2(side_w + 28.0,0)
	world.rotation_right_root.size = Vector2(side_w,58)
	for side in ["left","right"]:
		var label:Label = world._make_rotation_name_label(world._rotation_side_alignment(side))
		label.set_meta("raw_character_name","苦力怕" if side == "left" else "骷髅")
		label.text = label.get_meta("raw_character_name")
		label.add_theme_color_override("font_color",Color(0.35,1.0,0.42))
		label.position.y = 24.0
		world._rotation_side_root(side).add_child(label)
		world._rotation_current_labels[side] = label
	world._layout_rotation_label_widths()
	var left:Label = world._rotation_current_labels["left"]
	var right:Label = world._rotation_current_labels["right"]
	world._rotation_mark_current_dead("left",true)
	world._rotation_mark_current_dead("right",false)
	check(left.has_node("WastedOverlay"),"killed name gets a WASTED overlay")
	check(not right.has_node("WastedOverlay"),"round-cleared (grey) name gets no overlay")
	var overlay:Control = left.get_node("WastedOverlay")
	var text:Label = overlay.label()
	check(text.text == "WASTED","overlay text is WASTED")
	check(text.get_theme_color("font_color").r > 0.85 and text.get_theme_color("font_color").g < 0.2,"text is red")
	check(text.get_theme_color("font_outline_color") == Color.BLACK and text.get_theme_constant("outline_size") >= 2,"text has black outline")
	var font:Font = text.get_theme_font("font")
	check(font is FontVariation and (font as FontVariation).variation_embolden > 0.5,"text is bold")
	check(font is FontVariation and (font as FontVariation).spacing_glyph >= 0,"letter spacing is not squeezed (slightly looser than before)")
	# 红字必须压在名字文字中心上，而不是横带中心（横带贴边时两者不重合）。
	var name_font:Font = left.get_theme_font("font")
	var name_w:float = name_font.get_string_size(left.text,HORIZONTAL_ALIGNMENT_LEFT,-1,left.get_theme_font_size("font_size")).x
	var name_center_x:float = left.size.x - name_w * 0.5
	var wasted_center_x:float = overlay.position.x + text.position.x + text.size.x * 0.5
	check(absf(wasted_center_x - name_center_x) <= 1.5,"WASTED text is centered on the name text (%.1f vs %.1f)" % [wasted_center_x,name_center_x])
	world._rotation_mark_current_dead("left",true)
	check(left.get_children().filter(func(c): return c.name == "WastedOverlay").size() == 1,"overlay is not duplicated")
	await create_timer(0.4).timeout
	check(overlay.size.y >= left.size.y and overlay.size.x >= 64.0 and overlay.size.x <= left.size.x and overlay.scale.is_equal_approx(Vector2.ONE) and overlay.modulate.a > 0.99,"overlay band is fully shown after its intro tween")
	# 左侧名字右对齐（贴近 VS），横带应贴着名字所在的右端而不是整行居中。
	check(overlay.position.x + overlay.size.x >= left.size.x - 1.0,"band hugs the name text near the VS column")
	# 像素验证：把同样的名字+叠层复制到固定屏幕坐标的 CanvasLayer 上，避开相机变换。
	var layer := CanvasLayer.new()
	layer.layer = 127
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.1,0.45,0.75)
	bg.position = Vector2(20,400)
	bg.size = Vector2(200,40)
	layer.add_child(bg)
	var sample:Label = world._make_rotation_name_label(HORIZONTAL_ALIGNMENT_RIGHT)
	sample.text = "苦力怕"
	sample.add_theme_color_override("font_color",Color(1.0,0.28,0.28))
	sample.position = Vector2(40,414)
	sample.size = Vector2(160,12)
	layer.add_child(sample)
	world._rotation_attach_wasted_overlay(sample)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img:Image = root.get_texture().get_image()
	# canvas_items 拉伸：截图分辨率是 viewport 尺寸，CanvasLayer 坐标要按比例换算。
	var scale_factor:float = float(img.get_width()) / root.get_visible_rect().size.x
	var band:Control = sample.get_node("WastedOverlay")
	var label_rect:Rect2 = Rect2((sample.position + band.position) * scale_factor,band.size * scale_factor)
	# 采样横带：中心应比两端更黑
	var mid:Color = img.get_pixel(int(label_rect.get_center().x),int(label_rect.get_center().y))
	var edge:Color = img.get_pixel(int(label_rect.position.x + 2),int(label_rect.get_center().y))
	print("DBG mid=",mid," edge=",edge)
	var reds:int = 0
	var darks:int = 0
	for y in range(int(label_rect.position.y),int(label_rect.end.y)):
		for x in range(int(label_rect.position.x),int(label_rect.end.x)):
			var c:Color = img.get_pixel(x,y)
			if c.r > 0.6 and c.g < 0.25 and c.b < 0.25: reds += 1
			if c.v < 0.15: darks += 1
	print("DBG reds=",reds," darks=",darks)
	check(reds > 10,"red WASTED glyph pixels are rendered (%d)" % reds)
	check(darks > 40,"black band pixels are rendered (%d)" % darks)
	var crop_rect:Rect2i = Rect2i(bg.position * scale_factor,bg.size * scale_factor)
	var crop:Image = img.get_region(crop_rect)
	crop.resize(crop.get_width()*3,crop.get_height()*3,Image.INTERPOLATE_NEAREST)
	crop.save_png("res://tests/_wasted_preview.png")
	finish(0 if failures == 0 else 1)
func finish(code:int) -> void:
	print("WASTED checks=",checks," failures=",failures)
	quit(code)
