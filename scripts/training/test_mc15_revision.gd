extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var failures:int = 0
var checks:int = 0
var finishing:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0",master:Node = null) -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.Master = master
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	return unit
func freeze_move(unit:Node2D) -> void:
	unit.Speed = 0
	unit.default_properties["Speed"] = 0
func obstacle(point:Vector2,size:Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = point
	return body
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Map_Background = "blue" # 隔离用户本地已保存的草地选择；结束恢复，测试不写配置。
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(4,4)
	camera.make_current()
	var source:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(-150,0),"Team1")
	freeze_move(source)
	check(game.Game_Settings.get("Map_Background","blue") == "blue","old/default settings preserve blue appearance")
	check(not game._is_network_shared_setting("Map_Background"),"background is visual-only local setting, not shared gameplay state")
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	var layer:TileMapLayer = world.map_group[world.now_choose_map]
	var physical:Rect2 = world.return_map_world_rect(layer)
	var cell:Vector2 = world.map_visual_cell_size(layer)
	var view_size:Vector2 = world.get_viewport_rect().size
	var safety:Node = world._map_safety_frame
	var safety_id:int = safety.get_instance_id()
	print("MC15_GEOMETRY physical=",physical," cell=",cell)
	camera.global_position = physical.get_center()
	camera.zoom = Vector2.ONE*world._base_camera_zoom_value()
	await physics_frame
	var from:Vector2 = physical.get_center()
	var to:Vector2 = Vector2(physical.end.x+cell.x*3,from.y)
	var query := PhysicsRayQueryParameters2D.create(from,to,1)
	var before:Dictionary = world.get_world_2d().direct_space_state.intersect_ray(query)
	check(not before.is_empty(),"baseline physics ray hits original wall")
	check(world.return_map_visual_rect(layer) == physical and not world.map_background_tiles.visible,"blue has original border and no tiled layer")
	check(world.map_background_shadow.footprint == world.return_map_display_rect(layer),"blue shadow begins at exposed edge")
	check(world.map_background_shadow.spread == cell,"shadow extends exactly one cell")
	await capture("BLUE")
	game.set_runtime_game_setting("Map_Background","grass",false)
	await process_frame
	await physics_frame
	camera.zoom = Vector2.ONE*world._base_camera_zoom_value()
	var outer:Rect2 = world.return_map_visual_rect(layer)
	check(outer.position.is_equal_approx(physical.position-cell) and outer.size.is_equal_approx(physical.size+cell*2),"grass visual border extends exactly one map cell on each side")
	check(world.return_map_world_rect(layer) == physical and world._map_safety_frame.get_instance_id() == safety_id,"physical rect and safety collision body are unchanged")
	var after:Dictionary = world.get_world_2d().direct_space_state.intersect_ray(query)
	check(not after.is_empty() and after.position.is_equal_approx(before.position) and after.rid == before.rid,"actual wall collision is still at the same position and RID")
	var tiles:Node2D = world.map_background_tiles
	check(tiles.parts.size() == 5 and tiles.parts[0].texture.resource_path.ends_with("grass_block_top.png"),"five lightweight repeated sprites render original grass-top texture")
	var correct:bool = true
	for i:int in range(1,5):
		correct = correct and tiles.parts[i].texture.resource_path.ends_with("oak_log_top.png") and (tiles.parts[i].scale*16).is_equal_approx(cell)
	check(correct,"outside ring uses original log-top texture at identical single-cell scale")
	check(tiles.z_index == -5 and not tiles.z_as_relative,"background remains below blood and native stone overlays")
	var line:Line2D = world.map_border_segment_root.get_child(0)
	check(line.points[0].x+line.width*0.5 <= outer.position.x,"entire black stroke stays outside wooden ring")
	world.interaction_label.visible = true
	world.interaction_label.text = "[center]这是一段用于检查外圈顶部边距和长文字换行的互动文字[/center]"
	world.refresh_top_text_layout()
	check(world.interaction_label.position.y+world.interaction_label.size.y <= outer.position.y,"top text stays above expanded visual border")
	check(world._center_watermark_root.global_position.y>outer.end.y,"creator watermark stays below wood ring rather than overlapping it")
	check(world.map_background_shadow.footprint == outer.grow(world.map_border_width),"grass shadow starts beyond full external black stroke")
	check(not line.antialiased and line.begin_cap_mode == Line2D.LINE_CAP_BOX,"pixel-exact outer border with filled square corners")
	await capture("GRASS")
	var field:Node2D = load("res://scripts/effects/我的世界/蠹虫石砖场.gd").new()
	world.add_child(field)
	field.setup(world,layer)
	check(field._field_shadow.visible and field._field_shadow.footprint == physical,"stone overlay has its own exposed inner outline shadow")
	check(field._inner_shadow.z_index == -5 and field._inner_shadow.get_index() == 0,"gap shadow sits after background and before stone chunks")
	for y:int in range(3,7):
		for x:int in range(3,7):
			field._begin_break(Vector2i(x,y),"Team0",false,0,42,"")
	await create_timer(1.5).timeout
	check(field._inner_shadow.mask_image.get_pixel(3,3).r == 0 and field._inner_shadow.mask_image.get_pixel(2,3).r > 0.99,"real break path updates occupancy and keeps neighboring stone")
	check(not field._inner_shadow_update_pending,"multiple same-frame breaks batch mask upload")
	await capture("STONE")
	game.set_runtime_game_setting("Map_Background","blue",false)
	await process_frame
	check(not field._field_shadow.visible and world.map_background_shadow.visible,"blue stone uses common outer shadow without doubled opacity")
	check(field._inner_shadow.visible,"internal gap shadows also enabled on blue background")
	await capture("STONE_BLUE")
	# Capture identical blue hole without shadow to verify actual GPU pixels, not only node flags.
	await RenderingServer.frame_post_draw
	var shaded:Image = root.get_texture().get_image()
	field._inner_shadow.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var plain:Image = root.get_texture().get_image()
	var darkened:int = 0
	for yy:int in range(shaded.get_height()/3,shaded.get_height()*2/3):
		for xx:int in range(shaded.get_width()/3,shaded.get_width()*2/3):
			if plain.get_pixel(xx,yy).b-shaded.get_pixel(xx,yy).b > 0.025:
				darkened += 1
	check(darkened > 100,"GPU rendering visibly darkens blue floor inside broken-stone gap")
	print("MC15_DARKENED_PIXELS=",darkened)
	field._inner_shadow.show()
	for y:int in range(10):
		for x:int in range(10):
			field._tile_states[Vector2i(x,y)] = 2
	field._queue_coord_redraw(Vector2i.ZERO)
	await process_frame
	check(field._inner_shadow.mask_image.get_pixel(2,3).r == 0,"removing remaining stone removes its shadow source")
	field.queue_free()
	await process_frame
	game.set_runtime_game_setting("Map_Background","grass",false)
	await process_frame
	check(is_instance_valid(world.control.map_background_option) and world.control.map_background_option.item_count == 2 and world.control.map_background_option.selected == 1,"real settings dropdown contains both themes and synchronizes current selection")
	check(game.ui_t("MAP_BACKGROUND_GRASS") != "MAP_BACKGROUND_GRASS" and world.control.map_background_option.get_item_text(1) == game.ui_t("MAP_BACKGROUND_GRASS"),"dropdown resolves actual translated words rather than showing raw keys")
	var old_locale:String = game.current_locale
	var only_game:bool = game.Game_Settings.Only_In_Game_Translation
	game.Game_Settings.Only_In_Game_Translation = false
	game.current_locale = "en"
	game._apply_translation_server_locale()
	world.control._sync_map_background_setting()
	check(world.control.map_background_option.get_item_text(1) == "Grass Blocks" and world.control.map_background_label.text == "Background","English labels are translated and fit the same setting row")
	game.current_locale = old_locale
	game.Game_Settings.Only_In_Game_Translation = only_game
	game._apply_translation_server_locale()
	world.control._sync_map_background_setting()
	world.control.show()
	world.control.game_setting.show()
	world.control._show_settings_category("parameters")
	await create_timer(0.15).timeout
	await capture("SETTINGS")
	world.control.hide()
	game.set_runtime_game_setting("Map_Background","blue",false)
	await process_frame
	check(not tiles.visible and world.return_map_visual_rect(layer) == physical and world.control.map_background_option.selected == 0,"switching back restores original blue geometry and dropdown")
	# Large map uses same five draw surfaces, aligned cells and viewport fit.
	world.now_choose_map = "Map50x50"
	game.set_runtime_game_setting("Map_Background","grass",false)
	world.refresh_map_presentation()
	layer = world.map_group[world.now_choose_map]
	check(tiles.parts.size() == 5 and tiles.interior_rect == world.return_map_world_rect(layer),"larger map updates region without creating per-tile nodes")
	var fit:float = world._fit_zoom_for_map(layer)
	outer = world.return_map_visual_rect(layer)
	check(outer.size.x*fit <= view_size.x and outer.size.y*fit <= view_size.y,"camera fitting includes entire decorative outer ring in logical viewport coordinates")
	game.set_runtime_game_setting("Map_Background","blue",false)
	var fixture:Dictionary = await execution_fixture(99,center,source)
	var start:Vector2 = fixture.arrow.global_position
	var forward:Vector2 = fixture.arrow.get_flight_direction()
	var unit_scale:float = maxf(fixture.unit.global_transform.x.length(),fixture.unit.global_transform.y.length())
	fixture.control._begin_execution()
	await create_timer(0.21).timeout
	var pulled:float = (start-fixture.arrow.global_position).dot(forward)
	check(absf(pulled-84*unit_scale)<0.1,"actual execution pull distance is doubled from 42 to 84 root-local units")
	await create_timer(0.35).timeout
	check(is_instance_valid(fixture.arrow) and fixture.arrow._mode == 0,"longer pull still completes execution and launches arrow")
	check(is_equal_approx(float(world.get_meta("mc14_execution_amount",-1)),4.0),"execution requests exactly remaining 4 HP, without max HP or overkill")
	check(not is_instance_valid(fixture.unit) or fixture.unit.health <= 0,"remaining-health damage still kills target")
	print("MC15_CHECKS=%d/%d" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)
func execution_fixture(max_hp:int,point:Vector2,source:Node2D) -> Dictionary:
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate()
	unit.set_script(load("res://scripts/training/test_mc14_damage_probe.gd"))
	unit.Team = "Team0"
	unit.Max_health = max_hp
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	unit.state_machine.set_physics_process(false)
	var shot:Node2D = arrow(source,unit.global_position,Vector2.RIGHT)
	shot.set_physics_process(false)
	shot._request_embed_in_enemy(unit)
	await process_frame
	await process_frame
	var control:Node = unit.get_node("MinecraftArrowWoundController")
	control.set_process(false)
	# 设定测试残血不应先制造普通大伤害镜头，避免混入被测的处决镜头。
	var stopped:bool = game.now_stop_state
	game.now_stop_state = true
	unit.health = 4
	game.now_stop_state = stopped
	return {"unit":unit,"arrow":shot,"control":control}
func arrow(source:Node2D,point:Vector2,dir:Vector2) -> Node2D:
	var result:Node2D = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(result,true)
	result.global_position = point
	result.configure(source,source.Team,dir,360.0,8.0,3.0,0.0,90.0,5.0)
	return result
func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	var size:Vector2i = image.get_size()
	if size.x>900: image.resize(900,int(size.y*900.0/size.x),Image.INTERPOLATE_NEAREST)
	print("MC15_"+label+"_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
func _stop_audio(node:Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.stop()
		if node.is_in_group("MCNativeSFX"): node.queue_free()
	for child:Node in node.get_children(): _stop_audio(child)
func finish(code:int) -> void:
	if finishing: return
	finishing = true
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	_stop_audio(root)
	await create_timer(0.12,true,false,true).timeout
	print("MC15_EXIT=",code)
	quit(code)
