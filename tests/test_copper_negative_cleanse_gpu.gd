extends "res://tests/test_copper_negative_cleanse.gd"
var folder:String
var caption:Label

func grab(label:String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"real GPU image "+label)
	image.save_png(folder.path_join(label+".png"))
	return image

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("GPU renderer required"); quit(2); return
	EFFECTS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	COLD = load("res://scripts/characters/我的世界/snow_golem/cold.gd")
	BURN = load("res://scripts/effects/我的世界/mc_shared_burn.gd")
	CLEANSE = load("res://classes/status_cleansing.gd")
	game = root.get_node("Game"); saved = game.Game_Settings.duplicate(true); saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Map_Background = "grass"
	game.Game_Settings.Minecraft_Clouds = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(1080,720); root.content_scale_size = root.size; Engine.max_fps = 60
	create_timer(90,true,false,true).timeout.connect(func():finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"; world.refresh_map_presentation()
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"GPU production assets loaded")
	world.set_process(false); world.set_physics_process(false); world.control.hide(); world.versus_label.hide()
	for layer:CanvasLayer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera:=Camera2D.new(); world.add_child(camera); camera.make_current()
	camera.global_position = center; camera.zoom = Vector2.ONE*2.8; camera.force_update_scroll()
	var ui:=CanvasLayer.new(); ui.layer = 60; world.add_child(ui)
	caption = Label.new(); caption.position = Vector2(24,18)
	caption.add_theme_font_size_override("font_size",25)
	caption.add_theme_color_override("font_outline_color",Color.BLACK); caption.add_theme_constant_override("outline_size",5)
	ui.add_child(caption)
	folder = OS.get_environment("COPPER_CLEANSE_EVIDENCE_DIR")
	if folder.is_empty(): folder = "user://copper_cleanse_gpu"
	DirAccess.make_dir_recursive_absolute(folder)
	var unit:Node2D = copper(center+Vector2(-55,0)); unit.set_physics_process(false)
	var snow:Node2D = spawn("res://scenes/characters/我的世界/雪傀儡.tscn",center+Vector2(65,0),"Team0")
	snow.set_process(false); snow.set_physics_process(false); snow._field.set_physics_process(false)
	var source:Node2D = dummy(center+Vector2(400,0)); source.set_physics_process(false)
	check(snow.Max_health==425 and snow.health==425,"actual snow golem spawns with 425/425 HP")
	check(BURN.apply_amount(source,unit,20.0,3.0),"native burning attached")
	EFFECTS.apply_effect(unit,"weakness",2,30.0,source)
	EFFECTS.apply_effect(unit,"strength",3,30.0,source)
	EFFECTS.apply_effect(unit,"resistance",2,30.0,source)
	var good:Node = EFFECTS.current(unit,"strength")
	var cold:Node = COLD.ensure(unit); cold.add_cold(100,4.0,source)
	freeze_statuses(unit)
	caption.text = "净化前：灼烧 / 冻结 / 虚弱     雪傀儡 425 HP\n正面力量与抗性必须保留"
	var before:Image = await grab("00_before")
	var bolt:Node = natural(unit); bolt._process(unit.lightning_warning*0.5)
	caption.text = "自然落雷预警：负面效果仍在，不提前净化"
	await grab("01_warning")
	check(unit.has_node("MCSnowCold") and EFFECTS.current(unit,"weakness")!=null,"GPU warning preserves debuffs")
	bolt._process(unit.lightning_warning)
	caption.text = "自然落雷：清除所有负面效果，保留正面增益"
	await grab("02_impact")
	if is_instance_valid(bolt) and not bolt.is_queued_for_deletion(): bolt._process(0.5)
	caption.text = "净化后：灼烧 / 冻结 / 虚弱已清除\n力量 / 抗性保留；攻击引雷不净化     雪傀儡 425 HP"
	var after:Image = await grab("03_after")
	check(not unit.has_node("MCSnowCold") and not unit.has_node("MinecraftBlazeBurn") and EFFECTS.current(unit,"weakness")==null and not unit.dizziness,"GPU ice/fire/control removed on actual impact")
	check(EFFECTS.current(unit,"strength")==good and EFFECTS.current(unit,"resistance")!=null,"positive effects persist in the real scene")
	check(before.get_data()!=after.get_data(),"before/after images visibly differ")
	print("COPPER_CLEANSE_GPU_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
