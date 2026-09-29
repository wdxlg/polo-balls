extends SceneTree
# GPU regression: the same refracting rift must not cut an actor out of either
# full-resolution right-click recording viewport. Keep all three viewports real.
var game: Node
var world: Node
var recorder: Node
var rift: Node2D
var marker: Polygon2D
var area: Rect2

func _initialize() -> void:
	call_deferred("run")

func settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw

func sample(viewport: Viewport, label: String) -> Dictionary:
	if viewport is SubViewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await settle(0.18)
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return {"actor": 0, "total": 0}
	var projection: Viewport = viewport
	if viewport is SubViewport and viewport.name == "BattleRecordSRGB":
		projection = viewport.get_parent().get_node("BattleRecordCapture") as Viewport
	var transform: Transform2D = projection.get_stretch_transform() * projection.global_canvas_transform * projection.canvas_transform
	var rect: Rect2i = Rect2i(transform * area).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var matched: int = 0
	var total: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color: Color = image.get_pixel(x, y)
			if color.r > 0.55 and color.b > 0.42 and color.g < 0.5:
				matched += 1
			total += 1
	if OS.get_environment("RIFT_ACTOR_SAVE_IMAGES") == "1":
		var directory: String = "user://recordings/rift_actor_probe"
		DirAccess.make_dir_recursive_absolute(directory)
		image.save_png(directory.path_join(label + ".png"))
	return {"actor": matched, "total": total, "size": image.get_size()}

func intact(with_rift: Dictionary, without_rift: Dictionary) -> bool:
	return without_rift.total > 0 and without_rift.actor == without_rift.total and with_rift.actor >= without_rift.actor * 0.95

func run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): print("RIFT_ACTOR_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):
		world._mc_prewarmer.free()
	world.control.hide()
	root.size = Vector2i(540, 960)
	await settle(0.6)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.make_current()

	# Right-click simulation needs a real participant; keep it away from the
	# isolated colored actor silhouette so the comparison stays pixel-exact.
	var participant: Node2D = load("res://scenes/ball.tscn").instantiate()
	participant.Team = "Team0"
	participant.Can_Attack = false
	participant.Can_Skill = false
	participant.position = center + Vector2(220, 240)
	world.add_child(participant, true)
	participant.state_machine.set_physics_process(false)
	marker = Polygon2D.new()
	marker.name = "VisualActorProbe"
	marker.color = Color(1, 0.1, 0.85, 1)
	marker.polygon = PackedVector2Array([Vector2(-20, -25), Vector2(20, -25), Vector2(20, 25), Vector2(-20, 25)])
	marker.position = center + Vector2(-50, 0)
	world.add_child(marker)
	area = Rect2(marker.position - Vector2(20, 25), Vector2(40, 50))
	rift = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd").new()
	world.add_child(rift)
	rift.call("configure", null, 1783, PackedVector2Array([center + Vector2(-125, 0), center + Vector2(125, 0)]), [], center, 5.0)
	rift.set_process(false)
	rift.set("_age", 0.7)
	rift.call("_sync_visual")
	var warp_enabled: bool = rift._space_copy.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT and rift._space_warp.visible
	rift.visible = false
	var root_off: Dictionary = await sample(root, "normal_off")
	rift.visible = true
	var root_on: Dictionary = await sample(root, "normal_on")

	recorder = world.control._battle_record_controls.recorder
	recorder.preferences = recorder.PreferencesScript.new("user://rift_actor_probe.cfg")
	recorder.preferences.directory = "user://recordings/rift_actor_probe"
	if not recorder.start_simulated():
		print("START_ERROR ", recorder.get_last_error())
		quit(1)
		return
	var zh: Viewport = recorder._sim_viewport
	var en: Viewport = recorder._secondary._sim_viewport
	rift.visible = false
	var zh_off: Dictionary = await sample(zh, "zh_off")
	var en_off: Dictionary = await sample(en, "en_off")
	rift.visible = true
	var zh_on: Dictionary = await sample(zh, "zh_on")
	var en_on: Dictionary = await sample(en, "en_on")
	print("RIFT_ACTOR_COUNTS root_off=", root_off, " root_on=", root_on, " zh_off=", zh_off, " zh_on=", zh_on, " en_off=", en_off, " en_on=", en_on)
	var root_ok: bool = intact(root_on, root_off)
	var zh_ok: bool = intact(zh_on, zh_off) and zh_on["size"] == Vector2i(1080, 1920)
	var en_ok: bool = intact(en_on, en_off) and en_on["size"] == Vector2i(1080, 1920)
	print("RIFT_ACTOR_RESULT ", int(root_ok) + int(zh_ok) + int(en_ok) + int(warp_enabled), "/4")
	recorder.stop()
	var deadline: int = Time.get_ticks_usec() + 15000000
	while recorder.is_busy() and Time.get_ticks_usec() < deadline:
		await create_timer(0.05, true, false, true).timeout
	quit(0 if root_ok and zh_ok and en_ok and warp_enabled and not recorder.is_busy() else 1)
