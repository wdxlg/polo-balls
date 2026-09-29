extends "res://tests/test_mc_frontier.gd"
## Reproduce the offset on the actual painted floor, not just a physics circle.
const TILE = preload("res://classes/map_tile_geometry.gd")

func moss_center(moss:Node2D,point:Vector2) -> Vector2:
	var cell:Vector2i = moss.cell_at(point)
	return moss.point_for_cell(cell) if moss.has_method("point_for_cell") else Vector2(cell)*moss.CELL

func footprint_fits(moss:Node2D,point:Vector2) -> bool:
	var footprint:Array[Rect2] = [Rect2(point-Vector2.ONE*moss.CELL*0.5,Vector2.ONE*moss.CELL)]
	return TILE.subtract(footprint,world.current_map_island_rects()).is_empty()

func run() -> void:
	await setup_world()
	create_timer(75.0).timeout.connect(func(): finish(2))
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	for map_name:String in ["Map10x10","Map30x30","Map50x50","Map_Portal"]:
		world.now_choose_map = map_name
		world.refresh_map_presentation()
		var map_node:Node = world._current_map_node()
		var floor:Rect2 = world.return_map_world_rect(map_node)
		var cell_size:Vector2 = world.map_visual_cell_size(map_node)
		var moss:Node2D = actor("苔藓",floor.position+Vector2(24,24))
		moss.FOOTSTEPS.ensure(moss).set_physics_process(false)
		await physics_frame
		check(is_equal_approx(moss.CELL,cell_size.x) and is_equal_approx(moss.CELL,cell_size.y),map_name+": moss tile has the painted floor tile size")
		var first:Vector2 = floor.position+cell_size*0.5
		check(moss_center(moss,first).is_equal_approx(first),map_name+": first moss tile is centered over first floor cell")
		if map_name == "Map_Portal":
			var bottom_island:Vector2 = Vector2(136,2400)
			var gap:Vector2 = Vector2(136,2208)
			check(moss_center(moss,bottom_island).is_equal_approx(bottom_island) and footprint_fits(moss,bottom_island),"portal's separate island shares the floor grid")
			check(not footprint_fits(moss,gap) and (not moss.has_method("moss_floor_contains_tile") or not moss.moss_floor_contains_tile(gap)),"portal gap cannot receive moss even inside map bounding box")
			moss.free()
			continue
		var last:Vector2 = floor.end-cell_size*0.5
		check(moss_center(moss,last).is_equal_approx(last),map_name+": last moss tile is centered over last floor cell")
		var placed_first:bool = moss.plant(first)
		check(placed_first and moss.patches.size() == 1 and moss.patches[0].point == first and footprint_fits(moss,moss.patches[0].point),map_name+": first placed tile lies entirely inside the floor")
		moss.global_position = floor.end-Vector2(24,24)
		await physics_frame
		var placed_last:bool = moss.plant(last)
		check(placed_last and moss.patches.size() >= 2 and moss.patches.back().point == last and footprint_fits(moss,moss.patches.back().point),map_name+": last placed tile lies entirely inside the floor")
		moss.patches.clear()
		moss.global_position = floor.position+Vector2(24,24)
		await physics_frame
		moss.growth_left = 0.0
		var previewed:bool = moss.cultivate()
		var previews_inside:bool = previewed and moss._growth_pending.size() == moss.GROWTH_TILES
		for entry:Dictionary in moss._growth_pending:
			previews_inside = previews_inside and footprint_fits(moss,entry.point)
		check(previews_inside,map_name+": edge growth previews six complete floor tiles only")
		if map_name == "Map10x10":
			moss.cancel_cultivation()
			moss.patches.clear()
			moss.global_position = Vector2(40,40)
			await physics_frame
			check(moss.plant(Vector2(40,40)),"one 16px cell can be isolated for footsteps")
			var scheduler:Node = moss.FOOTSTEPS.ensure(moss)
			scheduler.set_physics_process(false)
			var walker:Node2D = dummy(Vector2(56,40))
			scheduler.states.clear()
			scheduler.sample(0.1)
			walker.global_position += Vector2(1,0)
			scheduler.sample(0.1)
			check(is_zero_approx(float(scheduler.states[walker.get_instance_id()].remaining)),"empty adjacent cell cannot trigger a moss footstep")
			walker.global_position = Vector2(40,40)
			var before_serial:int = moss._moss_sound_serial
			scheduler.sample(0.1)
			check(moss._moss_sound_serial > before_serial and float(scheduler.states[walker.get_instance_id()].remaining)>0.0,"walking onto moss triggers a footstep on the same grid")
			walker.free()
		moss.free()
	print("MOSS MAP ALIGNMENT: ",checks-failures,"/",checks)
	finish(0 if failures == 0 else 1)
