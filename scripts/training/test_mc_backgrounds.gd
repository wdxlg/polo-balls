extends "res://scripts/training/test_mc_new5.gd"

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(60).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	center=world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	var registry:Script=load("res://scripts/effects/我的世界/地图背景主题.gd")
	check(registry.OPTIONS.size()==6 and registry.OPTIONS[0]=="blue","six background options keep blue as compatibility default")
	check(not game._is_network_shared_setting("Map_Background"),"expanded background choice remains a local visual setting")
	var layer:TileMapLayer=world.map_group[world.now_choose_map]
	var physical:Rect2=world.return_map_world_rect(layer)
	var cell:Vector2=world.map_visual_cell_size(layer)
	check(is_instance_valid(world.control.map_background_option) and world.control.map_background_option.item_count==6,"settings dropdown exposes all six themes")
	var parameters:VBoxContainer=world.control.settings_category_boxes.parameters
	var background_row:Node=parameters.get_node_or_null("MapBackgroundRow")
	var framing_row:Node=parameters.get_node_or_null("CompositionRow")
	var framing_hint:Node=parameters.get_node_or_null("CompositionFeedback")
	check(background_row!=null and framing_row!=null and framing_row.get_index()==background_row.get_index()+1 and framing_hint!=null and framing_hint.get_index()==framing_row.get_index()+1,"framing controls follow the background selector immediately")
	check(world.control.map_background_option.item_selected.is_connected(Callable(world.control,"_on_map_background_selected")),"all theme choices are wired to the live setting")
	var blue_theme:Dictionary=registry.theme("blue")
	var texture_parallax_keys:Array[String]=["sand","stone","nether","end"]
	for key:String in registry.OPTIONS:
		game.set_runtime_game_setting("Map_Background",key,false)
		await process_frame
		await physics_frame
		var theme:Dictionary=registry.theme(key)
		var material:ShaderMaterial=world.map_outside_grid_material
		check(world.map_background_style()==key,"runtime selected style is normalized")
		check(material.get_shader_parameter("pattern_style")==int(theme.get("grid_style",0)),"parallax pattern is theme-specific")
		check((material.get_shader_parameter("normal_color") as Color).is_equal_approx(theme.get("grid_normal")),"overall parallax base color changes per theme")
		check((material.get_shader_parameter("dark_color") as Color).is_equal_approx(theme.get("grid_dark")),"overall parallax secondary color changes per theme")
		check((material.get_shader_parameter("accent_color") as Color).is_equal_approx(theme.get("grid_accent")),"overall parallax accent layer changes per theme")
		check(is_equal_approx(float(material.get_shader_parameter("cell_size_px")),float(theme.get("grid_cell"))),"overall parallax scale is customizable")
		check(is_equal_approx(float(material.get_shader_parameter("parallax_scale")),float(theme.get("grid_parallax"))),"overall parallax strength is customizable")
		check(material.get_shader_parameter("background_texture") == theme.get("grid_texture",null),"texture-copy parallax receives the configured block texture")
		check(world._waiter_door_background_color().is_equal_approx(material.get_shader_parameter("normal_color")),"door cutout follows current parallax background")
		check(world.control.map_background_option.selected==registry.OPTIONS.find(key),"dropdown follows every selected theme")
		check(world.control.map_background_option.get_item_text(registry.OPTIONS.find(key))==game.ui_t("MAP_BACKGROUND_"+key.to_upper()),"theme label resolves translation")
		if key=="blue":
			check(not world._is_grass_map_background() and not world.map_background_tiles.visible and world.return_map_visual_rect(layer)==physical,"blue keeps its original geometry and untiled background")
			continue
		if key=="grass":
			check(int(theme.get("grid_style"))==0 and theme.get("grid_normal")==blue_theme.get("grid_normal") and theme.get("grid_dark")==blue_theme.get("grid_dark") and theme.get("grid_accent")==blue_theme.get("grid_accent"),"grass parallax restores the old blue checker appearance")
			check(float(theme.get("grid_cell"))==float(blue_theme.get("grid_cell")) and float(theme.get("grid_parallax"))==float(blue_theme.get("grid_parallax")),"grass restores old checker scale and strength")
		else:
			check(registry.grid_texture(key)!=null and material.get_shader_parameter("background_texture")==registry.grid_texture(key),"non-grass themes parallax-copy a Minecraft block texture")
		check(world._is_grass_map_background() and world.map_background_tiles.visible,"Minecraft theme enables tiled map layer")
		check(world.return_map_visual_rect(layer).position.is_equal_approx(physical.position-cell) and world.return_map_visual_rect(layer).size.is_equal_approx(physical.size+cell*2),"theme retains one-cell wall without changing physical map")
		var tiles:Node2D=world.map_background_tiles
		check(tiles.parts.size()<=5,"each theme still uses bounded draw surfaces")
		check(tiles.parts[0].texture==theme.get("floor"),"map interior texture changes per theme")
		check(tiles.parts[0].modulate.is_equal_approx(theme.get("floor_modulate")),"map interior tint remains adjustable")
		var walls_ok:bool=true
		for i:int in range(1,tiles.parts.size()):
			walls_ok=walls_ok and tiles.parts[i].visible and tiles.parts[i].texture==theme.get("wall") and tiles.parts[i].modulate.is_equal_approx(theme.get("wall_modulate")) and (tiles.parts[i].scale*16).is_equal_approx(cell)
		check(walls_ok,"wall background texture and tint change per theme at exact cell scale")
	# The four new themes all copy target-dimension official block textures.
	for textured_key:String in texture_parallax_keys:
		check(registry.grid_texture(textured_key)!=null,"texture-copy theme has an official parallax texture")
	for pair:Array in [["sand","stone"],["sand","nether"],["sand","end"],["stone","nether"],["stone","end"],["nether","end"]]:
		check(registry.grid_texture(pair[0])!=registry.grid_texture(pair[1]),"each texture-copy theme uses a different parallax block")
	check(registry.theme("grass").get("floor").resource_path.ends_with("grass_block_top.png") and registry.theme("grass").get("wall").resource_path.ends_with("oak_log_top.png"),"existing grass keeps original Java textures")
	check(registry.theme("sand").get("floor").resource_path.ends_with("sand.png") and registry.theme("sand").get("wall").resource_path.ends_with("sandstone_top.png"),"sand delegates interior and wall to separate original textures")
	check(registry.theme("stone").get("floor").resource_path.ends_with("stone_bricks.png") and registry.theme("stone").get("wall").resource_path.ends_with("deepslate_bricks.png"),"stone delegates interior and wall independently")
	check(registry.theme("nether").get("floor").resource_path.ends_with("netherrack.png") and registry.theme("nether").get("wall").resource_path.ends_with("nether_bricks.png"),"nether delegates interior and wall independently")
	check(registry.theme("end").get("floor").resource_path.ends_with("end_stone.png") and registry.theme("end").get("wall").resource_path.ends_with("purpur_pillar_top.png"),"end delegates interior and wall independently")
	check(registry.grid_texture("sand").resource_path.ends_with("sandstone_top.png") and registry.grid_texture("stone").resource_path.ends_with("blackstone_top.png") and registry.grid_texture("nether").resource_path.ends_with("nether_bricks.png") and registry.grid_texture("end").resource_path.ends_with("purpur_block.png"),"parallax copies dimension-appropriate official block textures")
	var old_locale:String=game.current_locale
	var only_game:bool=game.Game_Settings.Only_In_Game_Translation
	game.Game_Settings.Only_In_Game_Translation=false
	game.current_locale="en"
	game._apply_translation_server_locale()
	world.control._sync_map_background_setting()
	var english:Array[String]=[]
	for i:int in range(world.control.map_background_option.item_count): english.append(world.control.map_background_option.get_item_text(i))
	check("Sand Blocks" in english and "Stone Bricks" in english and "Nether Wastes" in english and "End Stone" in english,"new settings have complete English labels")
	game.current_locale=old_locale
	game.Game_Settings.Only_In_Game_Translation=only_game
	game._apply_translation_server_locale()
	world.control._sync_map_background_setting()
	game.set_runtime_game_setting("Map_Background","blue",false)
	await process_frame
	check(world.return_map_visual_rect(layer)==physical and not world.map_background_tiles.visible and int(world.map_outside_grid_material.get_shader_parameter("pattern_style"))==0,"switching back restores blue parallax and original geometry")
	print("MC_BACKGROUNDS_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
