extends SceneTree
var failures:int = 0
var checks:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func run() -> void:
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "grass"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map_Portal"
	world.refresh_map_presentation()
	await process_frame
	var map:Node = world.map_group["Map_Portal"]
	var group:TileMapLayer = map.get_node("Portal_Characters")
	check(group.get_used_cells().size() == 6,"old two three-tile doors migrated into one group")
	check(group.get_cell_atlas_coords(Vector2i(2,8)).x == 0 and group.get_cell_atlas_coords(Vector2i(10,11)).x == 1,"entry/exit migration uses blue and red brushes")
	check(not group.visible and not group.collision_enabled,"editor tiles never render or add collision during gameplay")
	check(map.islands.size() == 3,"portal group layers are not counted as map islands")
	check(group.portal_doors(map).size() == 2,"adjacent same-color cells coalesce into one door")
	group.erase_cell(Vector2i(3,8))
	map.rebuild_gates()
	check(group.portal_doors(map).size() == 3,"erasing middle tile splits one door into two independently routable doors")
	group.set_cell(Vector2i(3,8),0,Vector2i.ZERO)
	group.set_cell(Vector2i(3,3),0,Vector2i.ZERO)
	check(group.portal_doors(map).size() == 2,"painting an interior cell does not create an off-wall portal")
	group.erase_cell(Vector2i(3,3))
	for x:int in range(2,5): group.erase_cell(Vector2i(x,8))
	map.rebuild_gates()
	var active:int = 0
	for gate:Dictionary in map.gates():
		if gate.group_id == group.get_instance_id(): active += 1
	check(active == 0,"only one red door after erasing blue stays inactive; no old numeric ranges return")
	for x:int in range(2,5): group.set_cell(Vector2i(x,8),0,Vector2i.ZERO)
	map.rebuild_gates()
	world.refresh_map_presentation()
	await process_frame
	var shadow:Node = world.map_background_shadow
	check(shadow.cutouts.size() == 1,"outside shadow subtracts the actual IslandA gate opening")
	check(int(shadow.surface.material.get_shader_parameter("cutout_count")) == 1,"shadow shader receives the nonrectangular wall cutout")
	check(shadow.z_index > world.map_outside_grid_root.z_index and not world.map_outside_grid_root.z_as_relative,"shadow composites above the parallax grid, not underneath it")
	var rect:Rect2 = map.island_rect("IslandA")
	var cuts:Array = shadow.cutouts
	check(cuts[0].has_point(Vector2(rect.position.x+56,rect.end.y+8)),"shadow cutout includes the portal cavity")
	check(not cuts[0].has_point(Vector2(rect.position.x+16,rect.end.y+8)),"remaining wall keeps its shadow footprint")
	check(cuts[0].end.y > shadow.footprint.end.y+shadow.spread.y,"cutout extends beyond shadow bounds, removing phantom outer-mouth edge")
	await create_timer(2.0).timeout
	if "--capture" in OS.get_cmdline_user_args():
		world.control.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var image:Image = root.get_texture().get_image()
		if image != null and not image.is_empty():
			image.save_png("res://tests/portal_tile_preview.png")
			print("CAPTURE saved tests/portal_tile_preview.png")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("PORTAL_TILES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
