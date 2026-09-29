extends "res://tests/test_mc_snow_golem.gd"
## Real GPU pixel comparisons with stock actors/projectiles, not a layer-only assertion.
var subjects:Array[Node2D] = []
var capture_dir:String
var pixel_half_span:Vector2i = Vector2i(40,40)
func label(text:String,point:Vector2,width:float = 220.0,size:int = 18) -> void:
	var node := Label.new()
	node.text = text
	node.position = point
	node.size.x = width
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color.WHITE)
	node.add_theme_color_override("font_shadow_color",Color.BLACK)
	node.add_theme_constant_override("shadow_offset_x",2)
	node.add_theme_constant_override("shadow_offset_y",2)
	root.get_node("SnowFixCaptions").add_child(node)
func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func show_subjects(value:bool) -> void:
	for unit:Node2D in subjects: unit.image.visible = value
func rgb_gap(a:Color,b:Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
func make_mask(empty:Image,actor_image:Image,snow_only:Image,center:Vector2i) -> Array[Vector2i]:
	var result:Array[Vector2i] = []
	# Stay strictly inside the full tile: edge protrusions cannot fake visibility.
	for y:int in range(maxi(0,center.y-pixel_half_span.y),mini(empty.get_height(),center.y+pixel_half_span.y)):
		for x:int in range(maxi(0,center.x-pixel_half_span.x),mini(empty.get_width(),center.x+pixel_half_span.x)):
			var point := Vector2i(x,y)
			var color:Color = actor_image.get_pixelv(point)
			if rgb_gap(color,empty.get_pixelv(point)) > 0.28 and rgb_gap(color,snow_only.get_pixelv(point)) > 0.12: result.append(point)
	return result
func retained(reference:Image,current:Image,mask:Array[Vector2i]) -> float:
	var count:int = 0
	for point:Vector2i in mask:
		if rgb_gap(reference.get_pixelv(point),current.get_pixelv(point)) <= 0.09: count += 1
	return float(count)/maxi(mask.size(),1)
func run() -> void:
	root.size = Vector2i(1000,800)
	root.content_scale_size = Vector2i(1000,800)
	game = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	# Blue-theme clouds intentionally cover actors at z=3000; isolate the floor
	# comparison from that unrelated overhead occluder instead of weakening masks.
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Map_Background = "grass" # Stock blue actor needs measurable contrast against the empty floor.
	var center:Vector2 = await setup_world()
	saved = original
	capture_dir = OS.get_environment("SNOW_GOLEM_EVIDENCE_DIR")
	if capture_dir.is_empty(): capture_dir = "user://snow_ground_gpu"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for ui:Node in world.find_children("*","CanvasLayer",true,false): ui.visible = false
	world.versus_label.hide()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center+Vector2(12,48)
	camera.zoom = Vector2(4,4)
	camera.make_current()
	camera.force_update_scroll()
	var captions := CanvasLayer.new()
	captions.name = "SnowFixCaptions"
	captions.layer = 115
	root.add_child(captions)
	label("雪径修复 / 原生 GPU 遮挡与朝向检查",Vector2(110,25),780,27)
	label("地面在下，人物与投射物在上；完整雪 → 无害小雪 → 消失",Vector2(100,70),800,18)
	var source:Node2D = spawn(GOLEM_PATH,center+Vector2(240,240))
	var field:Node2D = source._field
	field.set_physics_process(false)
	field.full_snow_lifetime = 1.0
	field.snow_fade_duration = 0.7
	var ball_unit:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(-96,0),"Team1")
	ball_unit.Can_Attack = false
	ball_unit.Can_Skill = false
	ball_unit.Has_Collision_Damage = false
	# Do not increase HP like dummy(): that intentionally triggers a transient
	# heal flash and makes a frame-to-frame pixel comparison nonstationary.
	var bullet:Node2D = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(-24,0))
	bullet.Master = source
	var snowball:Node2D = spawn("res://scenes/shooter/我的世界/雪球.tscn",center+Vector2(48,0))
	snowball.Master = source
	var golem:Node2D = spawn(GOLEM_PATH,center+Vector2(120,0))
	golem.direction = Vector2.DOWN # Front buttons provide an opaque, non-white mask inside a white snow tile.
	subjects.assign([ball_unit,bullet,snowball,golem])
	var names:Array[String] = ["普通角色","原有子弹","原版雪球","雪傀儡"]
	var screen_centers:Array[Vector2i] = []
	for i:int in range(subjects.size()):
		var unit:Node2D = subjects[i]
		unit.health_bar.hide()
		unit.motion_blur_enabled = false
		unit.AfterImage_Speed = 0.0
		unit.global_position = field.snow_point_at(field.snow_cell_at(unit.global_position))
		field.deposit(source,field.snow_cell_at(unit.global_position),false)
		label(names[i],Vector2(4+288*i,295),128,18)
	await process_frame
	# Screen coordinates are computed from the captured image AFTER layout settles.

	# Extra rows demonstrate movement/manual aim and native pumpkin/bare forms.
	var facing_units:Array[Node2D] = []
	for i:int in range(4):
		var path:String = GOLEM_PATH
		var unit:Node2D = spawn(path,center+Vector2(-96+72*i,96))
		unit.health_bar.hide()
		unit.direction = Vector2.LEFT if i in [0,2,3] else Vector2.RIGHT
		if i == 1: unit.has_pumpkin = false
		if i == 2:
			unit.set_player_control_peer(1)
			unit.set_player_control_direction(Vector2.RIGHT)
		if i == 3:
			unit._shot_left = 0.0
			unit.fire_at(unit.global_position+Vector2(100,0))
			for shot:Node in get_nodes_in_group("MCSnowball"):
				if shot.Master == unit: shot.queue_free()
		unit.move(0.0,0.016)
		unit.visual_mob()
		facing_units.append(unit)
	var direction_labels:Array[String] = ["向左移动 ←","无头：向右移动 →","雪傀儡：手控向右 →","向左走，向右发射 →"]
	for i:int in range(4): label(direction_labels[i],Vector2(-35+288*i,710),210,15)

	show_subjects(false)
	field.hide()
	var background:Image = await grab()
	show_subjects(true)
	var reference:Image = await grab()
	var image_scale:Vector2 = Vector2(reference.get_size())/root.get_visible_rect().size
	pixel_half_span = Vector2i(((field.grid_size*0.5-Vector2.ONE*2.0)*camera.zoom*image_scale).floor())
	screen_centers.clear()
	for unit:Node2D in subjects: screen_centers.append(Vector2i((unit.get_global_transform_with_canvas().origin*image_scale).round()))
	print("GROUND_GPU_COORDS image=",reference.get_size()," viewport=",root.get_visible_rect()," scale=",image_scale," centers=",screen_centers)
	reference.save_png(capture_dir.path_join("snow_golem_fixes_actor_reference.png"))
	show_subjects(false)
	field.show()
	var snow_only:Image = await grab()
	show_subjects(true)
	var full:Image = await grab()
	full.save_png(capture_dir.path_join("snow_golem_fixes_full.png"))
	var masks:Array = []
	for i:int in range(subjects.size()):
		var mask:Array[Vector2i] = make_mask(background,reference,snow_only,screen_centers[i])
		masks.append(mask)
		check(mask.size() >= 12,"GPU probe has actual actor/projectile pixels inside snow: "+names[i])
		var ratio:float = retained(reference,full,mask)
		print("SNOW_GPU_VISIBLE index=",i," full=",ratio," pixels=",mask.size())
		check(ratio > 0.80,"full snow leaves the real rendered subject visible: "+names[i])

	# A negative control intentionally reinstates ONLY the old faulty terrain z.
	var original_relative:bool = field.z_as_relative
	var original_z:int = field.z_index
	field.z_as_relative = false
	field.z_index = 1
	var old_layer:Image = await grab()
	old_layer.save_png(capture_dir.path_join("snow_golem_fixes_old_layer_control.png"))
	for i:int in range(3):
		var ratio:float = retained(reference,old_layer,masks[i])
		print("SNOW_GPU_OLD_LAYER index=",i," visible=",ratio)
		check(ratio < 0.35,"negative control reproduces occlusion with the old absolute snow layer: "+names[i])
	field.z_as_relative = original_relative
	field.z_index = original_z
	field.advance(1.01)
	check(field.patches.size() == 4 and field.patches.values()[0].level == 2 and field.snow_alpha(field.patches.values()[0])<1.0,"GPU full-to-fade frame keeps the actual one-block footprint")
	var half:Image = await grab()
	half.save_png(capture_dir.path_join("snow_golem_fixes_half.png"))
	for i:int in range(subjects.size()): check(retained(reference,half,masks[i]) > 0.80,"fading snow also stays below the subject: "+names[i])
	field.advance(0.71)
	check(field.patches.is_empty(),"GPU final frame has no expired snow left")
	var gone:Image = await grab()
	gone.save_png(capture_dir.path_join("snow_golem_fixes_gone.png"))
	for i:int in range(subjects.size()): check(retained(reference,gone,masks[i]) > 0.80,"melting never hides the subject: "+names[i])
	check(facing_units[0]._aim_pose==6 and facing_units[1]._aim_pose==2 and facing_units[2]._aim_pose==2 and facing_units[3]._aim_pose==0 and facing_units.all(func(u):return not u.is_character_visual_flipped_h()),"GPU walking/manual use diagonals, while the shot row retains its true target direction")
	print("SNOW_FIXES_GPU checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
