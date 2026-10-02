extends SceneTree
var game:Node
var arena:Node2D
var errors:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	if ok: print("PASS: "+label)
	else:
		errors += 1
		push_error("FAIL: "+label)
func actor(path:String,label:String,point:Vector2,team:String) -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.name = label
	unit.Team = team
	unit.position = point
	arena.add_child(unit)
	unit.state_machine.set_physics_process(false)
	return unit
func capture(path:String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	check(not image.is_empty(),"real GPU viewport readback")
	var green:int = 0
	var gold:int = 0
	for y:int in range(0,image.get_height(),2):
		for x:int in range(0,image.get_width(),2):
			var c:Color = image.get_pixel(x,y)
			if c.g > c.r*1.12 and c.g > c.b*1.2 and c.g > 0.15: green += 1
			if c.r > 0.45 and c.g > 0.3 and c.b < c.g*0.6: gold += 1
	check(green > 150 and gold > 30,"original green skin and golden helmet render visibly")
	image.save_png(path)
	print("VISUAL_CAPTURE ",path," green=",green," gold=",gold)
func run() -> void:
	game = root.get_node("Game")
	game._settings_storage_path = "user://zombie_visual_settings.cfg"
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(960,600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var camera := Camera2D.new()
	camera.position = Vector2(225,135)
	camera.zoom = Vector2(5,5)
	arena.add_child(camera)
	RenderingServer.set_default_clear_color(Color("27303a"))
	var king:Node2D = actor("res://scenes/characters/我的世界/僵尸王.tscn","King",Vector2(170,160),"A")
	var zombie:Node2D = actor("res://scenes/characters/我的世界/僵尸.tscn","Zombie",Vector2(243,160),"A")
	var target:Node2D = actor("res://scenes/characters/我的世界/僵尸.tscn","Target",Vector2(267,160),"B")
	king.throw_cooldown = 0.0
	king.throw_slime(target.global_position)
	var shot:Node2D = get_nodes_in_group("MCZombieSlimeBall")[0]
	shot.set_physics_process(false)
	await create_timer(0.15).timeout
	var previous:Vector2 = shot._from
	for i:int in range(1,19):
		shot.global_position = shot.point_at(float(i)/40.0)
		shot._emit_slime_trail(previous,shot.global_position)
		previous = shot.global_position
		zombie.position.x += 0.015
		await process_frame
	check(not get_nodes_in_group("MCZombieSlimeParticle").is_empty(),"slime leaves native texture fragments")
	for fragment:Node in get_nodes_in_group("MCZombieSlimeParticle"):
		check(fragment.self_modulate.r == fragment.self_modulate.g and fragment.self_modulate.g == fragment.self_modulate.b,"slime fragments retain original green pixels without portal tint")
	check(zombie.begin_bite(target),"real scene triggers upper-and-lower jaw bite")
	var fx:Node2D = zombie._bite_fx
	fx.set_physics_process(false)
	fx._age = 0.08
	fx.queue_redraw()
	var args:PackedStringArray = OS.get_cmdline_user_args()
	var folder:String = args[0] if not args.is_empty() else "user://"
	await capture(folder.path_join("zombie_open.png"))
	fx._age = 0.14
	fx.queue_redraw()
	shot.global_position = shot.point_at(0.78)
	await capture(folder.path_join("zombie_closed.png"))
	check(fx.jaw_gap() == 0.0,"upper and lower pixel jaws close at the hit moment")
	arena.queue_free()
	await process_frame
	await wall_emergence(folder)
	print("ZOMBIE_VISUAL_RESULT failures=",errors)
	quit(1 if errors else 0)

func wall_pixels(path:String) -> int:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels:Image = root.get_texture().get_image()
	var green:int = 0
	for y:int in range(120,pixels.get_height(),2):
		for x:int in range(0,pixels.get_width(),2):
			var c:Color = pixels.get_pixel(x,y)
			if (c.g > c.r*1.12 and c.g > c.b*1.2 and c.g > 0.15) or (c.b > c.r*1.4 and c.b > c.g*1.4 and c.b > 0.08): green += 1
	pixels.save_png(path)
	print("WALL_CAPTURE ",path," body_pixels=",green)
	return green
func wall_emergence(folder:String) -> void:
	game.Game_Settings.Map_Background = "stone"
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Development_Mode = false
	var world:Node2D = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world._mc_prewarmer = null
	world.set_process(false)
	world.set_physics_process(false)
	world.control.hide()
	world.control.team.hide()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	await physics_frame
	await process_frame
	arena = world
	var rect:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	var king:Node2D = actor("res://scenes/characters/我的世界/僵尸王.tscn","WallKing",rect.get_center(),"A")
	king.hide()
	king._mc_rng.seed = 72
	king.summon_cooldown = 0.0
	check(king.summon_zombies()==2,"real World summons from outer walls")
	var entrants:Array = king.living_summons()
	var unit:Node2D = entrants[0]
	entrants[1].hide()
	unit.entry_left = 2.4
	unit.state_machine.set_physics_process(false)
	var camera := Camera2D.new()
	camera.position = unit.entry_face+unit.entry_normal*12.0
	camera.zoom = Vector2(5,5)
	world.add_child(camera)
	camera.make_current()
	await physics_frame
	check(unit._entry_clip != null and unit._entry_clip.active,"GPU scene uses injected world-space wall clip shader")
	var start:Vector2 = unit.global_position
	var hidden:int = await wall_pixels(folder.path_join("zombie_wall_hidden.png"))
	await create_timer(1.08).timeout
	var middle:int = await wall_pixels(folder.path_join("zombie_wall_emerging.png"))
	check((unit.global_position-start).dot(unit.entry_normal)>20.0,"shared physics Tween visibly moves the body out of the wall")
	await create_timer(1.35).timeout
	var full:int = await wall_pixels(folder.path_join("zombie_wall_out.png"))
	check(hidden < 10 and middle > hidden+20 and full > middle+20,"rendered body progressively reveals instead of appearing all at once")
	check(unit.entry_left == 0.0 and unit._entry_clip == null and unit.can_act(),"entry restores ordinary combat and the original material")
	check(unit.mc_body_position_clear(unit.global_position),"fully emerged body is not overlapping its wall")
	world.queue_free()
	await process_frame
