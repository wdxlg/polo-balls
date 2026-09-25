extends SceneTree
# Real World + actual potion/enchantment stands, not high-Z feedback substitutes.
var checks:int = 0
var failures:int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("WALL_TOOLTIP FAIL: "+label)
func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
func _delta(a:Color,b:Color) -> float:
	return absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
func _changed(a:Image,b:Image,rect:Rect2,logical_size:Vector2=Vector2.ZERO) -> int:
	var ratio:Vector2 = Vector2(a.get_size())/(root.get_visible_rect().size if logical_size==Vector2.ZERO else logical_size)
	var start:Vector2i = Vector2i(rect.position*ratio)
	var end:Vector2i = Vector2i(rect.end*ratio)
	var count:int = 0
	for y:int in range(maxi(0,start.y),mini(a.get_height(),end.y)):
		for x:int in range(maxi(0,start.x),mini(a.get_width(),end.x)):
			if _delta(a.get_pixel(x,y),b.get_pixel(x,y))>0.045: count += 1
	return count
func _pixel(img:Image,point:Vector2) -> Color:
	return img.get_pixelv(Vector2i(point*Vector2(img.get_size())/root.get_visible_rect().size))
func _rect(ui:MCPreviewTooltip) -> Rect2:
	return Rect2(ui._panel.position,ui._panel.size*ui._panel.scale)
func _screen_rect(world_rect:Rect2) -> Rect2:
	var canvas:Transform2D = root.get_canvas_transform()
	return Rect2(canvas*world_rect.position,canvas.basis_xform(world_rect.size))
func _ink(world:Node,screen_point:Vector2) -> Polygon2D:
	var ink := Polygon2D.new()
	ink.polygon = PackedVector2Array([Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)])
	ink.color = Color.CYAN
	world.add_child(ink)
	ink.global_position = root.get_canvas_transform().affine_inverse()*screen_point
	return ink
func _run() -> void:
	create_timer(115.0,true,false,true).timeout.connect(func():quit(2))
	var folder:String = "user://map_wall_tooltips"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = false
	AudioServer.set_bus_mute(0,true)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.day_night_cycle.advancing = false
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	var area:Rect2 = world.return_map_world_rect(world._current_map_node())
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.position = area.get_center()
	camera.zoom = Vector2.ONE*2.3
	camera.force_update_scroll()
	var potion:Node2D = load("res://scenes/characters/默认/药水测试盔甲架.tscn").instantiate()
	var enchant:Node2D = load("res://scenes/characters/默认/附魔测试盔甲架.tscn").instantiate()
	for actor:Node2D in [potion,enchant]:
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.set("Team","A")
		actor.position = Vector2(area.end.x-22,area.get_center().y+(-48 if actor==potion else 48))
		world.add_child(actor,true)
	var chosen:Array[MCPreviewPotionEffect] = [potion.potion_pool[0],potion.potion_pool[1]]
	potion.set_displayed_potions(chosen)
	var selected:Array[MCPreviewEnchantment] = [enchant.enchantment_pool[0]]
	enchant.set_displayed_enchantments("附魔书",selected,"Enchanted Book")
	var frames:Array[MCPreviewTooltip] = [potion.get_node("Minecraft信息框"),enchant.get_node("Minecraft信息框")]
	for ui:MCPreviewTooltip in frames: ui.set_process(false)
	for style:String in ["blue","grass","sand","stone","nether","end","blue"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		for ui:MCPreviewTooltip in frames: ui._process(0.0)
		await _frame()
		var actual:Image = root.get_texture().get_image()
		var view_rect:Rect2 = root.get_visible_rect()
		var count:int = world.map_border_segment_root.get_child_count()
		check((count>0)==(style=="blue"),style+": only blue creates black map border segments")
		world.map_border_segment_root.hide()
		await _frame()
		var no_border:Image = root.get_texture().get_image()
		var border_delta:int = _changed(actual,no_border,_screen_rect(area.grow(24)))
		check(border_delta>30 if style=="blue" else border_delta==0,style+": GPU black frame present only for blue")
		world.map_border_segment_root.show()
		if style=="blue": continue
		var volume:Node2D = world.map_wall_volume
		for ui:MCPreviewTooltip in frames: ui.z_index = 110
		await _frame()
		var reference:Image = root.get_texture().get_image()
		for ui:MCPreviewTooltip in frames: ui.z_index = MCPreviewTooltip.TOOLTIP_Z
		var wall_z:int = volume.z_index
		volume.z_index = 90 # Negative control: the previous fix still hid low-Z frames.
		await _frame()
		var old_layer:Image = root.get_texture().get_image()
		volume.z_index = wall_z
		for i:int in range(frames.size()):
			var r:Rect2 = _rect(frames[i]).intersection(view_rect)
			var error:int = _changed(actual,reference,r)
			var old_error:int = _changed(old_layer,reference,r)
			print("WALL_TOOLTIP_PIXELS ",style," kind=",i," current=",error," wall90=",old_error)
			check(error<=3 and old_error>15,"%s: real %s frame fully visible across wall, old layer demonstrably occludes it" % [style,"potion" if i==0 else "enchantment"])
			var inside:Rect2 = r.intersection(_screen_rect(area).grow(-2))
			check(inside.has_area(),style+": actual frame overlaps in-map foreground test area")
			if inside.has_area():
				var probe:Vector2 = inside.get_center()
				var ink:Polygon2D = _ink(world,probe)
				await _frame()
				var color:Color = _pixel(root.get_texture().get_image(),probe)
				check(color.g>color.r*2.5 and color.b>color.r*2.5,style+": ordinary world foreground still covers frame")
				ink.queue_free()
			var east:float = _screen_rect(area).end.x
			var outside:Rect2 = r.intersection(Rect2(Vector2(east+4,0),view_rect.size))
			check(outside.has_area(),style+": actual frame extends beyond map edge")
			if outside.has_area():
				var probe:Vector2 = outside.get_center()
				var ink:Polygon2D = _ink(world,probe)
				await _frame()
				check(_delta(_pixel(root.get_texture().get_image(),probe),_pixel(actual,probe))<0.045,style+": mask still clips outside units but retains frame and wall background")
				ink.queue_free()
		await _frame()
		if style=="grass":
			actual.save_png(folder+"/current.png")
			reference.save_png(folder+"/reference.png")
			old_layer.save_png(folder+"/wall90.png")
		volume.picture.hide()
		await _frame()
		var top:Rect2 = Rect2(area.position-Vector2(0,16),Vector2(area.size.x,16))
		check(_changed(actual,root.get_texture().get_image(),_screen_rect(top))>50,style+": wall outside map survives by being captured in background snapshot")
		volume.picture.show()
		check(volume.z_index<MCPreviewTooltip.TOOLTIP_Z and world.map_clip_backbuffer.z_index+world.z_index>volume.z_index,style+": walls precede frames and map snapshot, not foreground")
	await _check_captures(world,frames,area)
	for map_name:String in ["Map_Portal","Map50x50","Map10x10"]:
		world.now_choose_map = map_name
		for style:String in ["grass","blue"]:
			game.set_runtime_game_setting("Map_Background",style,false)
			world.refresh_map_presentation()
			check((world.map_border_segment_root.get_child_count()>0)==(style=="blue"),map_name+" "+style+": border policy survives map/theme transitions")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("WALL_TOOLTIP checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func _check_captures(world:Node,frames:Array[MCPreviewTooltip],area:Rect2) -> void:
	root.get_node("Game").set_runtime_game_setting("Map_Background","grass",false)
	world.refresh_map_presentation()
	var old_mask:int = root.canvas_cull_mask
	root.canvas_cull_mask &= ~((1<<17)|(1<<18))
	var views:Array[SubViewport] = []
	for i:int in range(2):
		var view := SubViewport.new()
		view.size = Vector2i(540,960)
		view.world_2d = root.world_2d
		view.canvas_cull_mask = 1|(1<<(17+i))
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var canvas:Transform2D = root.get_canvas_transform()
		var factor:float = 0.5 if i==0 else 0.6
		view.canvas_transform = Transform2D(canvas.x*factor,canvas.y*factor,canvas.origin*factor)
		views.append(view)
	var mirror:Node = load("res://scripts/ui/battle_record_effect_tooltips.gd").new()
	world.add_child(mirror)
	mirror.begin(views[0],views[1])
	mirror.sync()
	await _frame()
	var actual:Array[Image] = [views[0].get_texture().get_image(),views[1].get_texture().get_image()]
	for ui:MCPreviewTooltip in frames:
		for locale:String in ["zh","en"]: mirror.copies[ui.get_instance_id()][locale].z_index = 110
	await _frame()
	var reference:Array[Image] = [views[0].get_texture().get_image(),views[1].get_texture().get_image()]
	for ui:MCPreviewTooltip in frames:
		for locale:String in ["zh","en"]: mirror.copies[ui.get_instance_id()][locale].z_index = MCPreviewTooltip.TOOLTIP_Z
	world.map_wall_volume.z_index = 90
	await _frame()
	for i:int in range(2):
		var view:SubViewport = views[i]
		var locale:String = "zh" if i==0 else "en"
		var east:float = (view.canvas_transform*area.end).x
		var legacy:Image = view.get_texture().get_image()
		for source:MCPreviewTooltip in frames:
			var ui:MCPreviewTooltip = mirror.copies[source.get_instance_id()][locale]
			var r:Rect2 = _rect(ui).intersection(Rect2(Vector2(east+1,0),Vector2(view.size)))
			var error:int = _changed(actual[i],reference[i],r,Vector2(view.size))
			var old_error:int = _changed(legacy,reference[i],r,Vector2(view.size))
			print("WALL_TOOLTIP_CAPTURE ",locale," kind=",ui._kind," current=",error," wall90=",old_error)
			check(r.has_area() and error<=3 and old_error>10,"%s %s: shared-world recording mirror remains readable over outside wall" % [locale,ui._kind])
	world.map_wall_volume.z_index = -4
	mirror.finish()
	mirror.queue_free()
	for view:SubViewport in views:
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		view.queue_free()
	root.canvas_cull_mask = old_mask
	await process_frame
