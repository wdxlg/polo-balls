extends SceneTree
# 真实 World 路径：六主题、地图切换、服务员门洞、光向、碰撞不变。
const THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MAP_WALL_3D FAIL: "+label)
	else: print("PASS: ",label)

func _safety_snapshot(frame:Node) -> Array[String]:
	var shapes:Array[String] = []
	for item:Node in frame.find_children("*","StaticBody2D",true,false):
		var collider:CollisionShape2D = item.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collider == null or not collider.shape is RectangleShape2D: continue
		shapes.append("%s|%s|%d" % [item.global_position,(collider.shape as RectangleShape2D).size,(item as StaticBody2D).collision_layer])
	shapes.sort()
	return shapes

func _edge_covers_gap(edges:Array[Dictionary],side:int,line:float,low:float,high:float) -> bool:
	for edge:Dictionary in edges:
		if int(edge.side)!=side or absf(float(edge.line)-line)>0.01: continue
		if minf(float(edge.b),high)-maxf(float(edge.a),low)>0.1: return true
	return false

func _run() -> void:
	create_timer(50.0).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	var settings:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	await physics_frame
	var physical:Rect2 = world.return_map_world_rect(world.map_group["Map10x10"])
	var collision:Array[String] = _safety_snapshot(world._map_safety_frame)
	var ray:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(physical.get_center(),Vector2(physical.end.x+24.0,physical.get_center().y),1)
	var first_hit:Dictionary = world.get_world_2d().direct_space_state.intersect_ray(ray)
	var first_edges:Array[Dictionary] = world.map_wall_volume.wall_edges.duplicate(true)
	check(first_edges.size() == 4,"rectangle builds four continuous wall sections")
	check(physical.has_area() and not first_hit.is_empty(),"physical map and original wall collision exist")
	check(world.map_wall_light_direction.x>0.0 and world.map_wall_light_direction.y<0.0,"default source lies at top-right")
	check(world.map_wall_volume.face_offset.x<0.0 and world.map_wall_volume.face_offset.y>0.0,"wall side relief projects bottom-left")
	check(world.map_wall_volume.z_index>world.map_outside_mask_root.z_index and world.map_wall_volume.z_index<world.map_border_segment_root.z_index,"wall lies above map clipping but below existing border and doors")
	check(world.map_wall_volume.find_children("*","CollisionObject2D",true,false).is_empty(),"volume is visual-only, without extra physics bodies")
	for style:String in THEMES.OPTIONS:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		await process_frame
		await physics_frame
		var volume:Node2D = world.map_wall_volume
		var cell:Vector2 = world.map_visual_cell_size(world.map_group["Map10x10"])
		var displacement:Vector2 = -world.map_wall_light_direction.normalized()*minf(cell.x,cell.y)*world.map_wall_height_cells
		var cast:Vector2 = -world.map_wall_light_direction.normalized()*minf(cell.x,cell.y)*world.map_wall_shadow_cells
		var shader:ShaderMaterial = world.map_inside_shadow.surface.material
		check(volume.visible and volume.wall_edges.size()==first_edges.size() and volume.face_offset.is_equal_approx(displacement),"%s: 3D wall follows original perimeter at configured height" % style)
		check(bool(shader.get_shader_parameter("directional_enabled")) and (shader.get_shader_parameter("shadow_vector") as Vector2).is_equal_approx(cast) and shader.get_shader_parameter("segment_count")==volume.wall_edges.size(),"%s: floor shadows use same cut wall segments, casting bottom-left" % style)
		var hit:Dictionary = world.get_world_2d().direct_space_state.intersect_ray(ray)
		check(world.return_map_world_rect(world.map_group["Map10x10"]) == physical and _safety_snapshot(world._map_safety_frame)==collision and not hit.is_empty() and hit.position.is_equal_approx(first_hit.position),"%s: wall collision and playable footprint do not change" % style)
		var theme:Dictionary = THEMES.theme(style)
		check(volume.tiled == bool(theme.get("tiled",false)) and volume.wall_texture == theme.get("wall",null) and world.map_background_tiles.visible == volume.tiled,"%s: blue or original block top texture remains selected" % style)
	# 切换大小和传送门地图仍只沿各自真实地面边绘制，不沿外接矩形伪造墙。
	for map_key:String in ["Map50x50","Map_Portal","Map10x10"]:
		world.now_choose_map = map_key
		world.refresh_map_presentation()
		var edges:Array[Dictionary] = world.map_wall_volume.wall_edges
		check(not edges.is_empty() and world.map_inside_shadow.surface.material.get_shader_parameter("segment_count")==edges.size(),"%s: map switch refreshes both wall and shadow edges" % map_key)
		check(world.map_wall_volume.get_child_count()==0,"%s: single CanvasItem is used instead of per-cell child nodes" % map_key)
	game.set_runtime_game_setting("Map_Background","grass",false)
	world.refresh_map_presentation()
	var owner := Node2D.new()
	world.add_child(owner)
	owner.global_position = physical.position+Vector2(physical.size.x*0.5,18.0)
	var id:int = world.open_waiter_door(owner,38.0)
	check(id>0,"waiter opens a real perimeter door")
	if id>0:
		var info:Dictionary = world._waiter_doors[id]
		var side:int = int(info.side)
		var along:float = info.center.y if side<2 else info.center.x
		var line:float = [physical.position.x,physical.end.x,physical.position.y,physical.end.y][side]
		check(not _edge_covers_gap(world.map_wall_volume.wall_edges,side,line,along-float(info.width)*0.5,along+float(info.width)*0.5),"real door leaves a gap in the 3D wall, including its end face")
		check(world.map_inside_shadow.surface.material.get_shader_parameter("segment_count")==world.map_wall_volume.wall_edges.size(),"door also removes its cast-shadow source")
		var cell:Vector2 = world.map_visual_cell_size(world.map_group["Map10x10"])
		var probe:Vector2 = [Vector2(physical.position.x-cell.x*0.5,along),Vector2(physical.end.x+cell.x*0.5,along),Vector2(along,physical.position.y-cell.y*0.5),Vector2(along,physical.end.y+cell.y*0.5)][side]
		for style:String in ["grass","sand","stone","nether","end"]:
			game.set_runtime_game_setting("Map_Background",style,false)
			world.refresh_map_presentation()
			var wood_over_door:bool = false
			for wall_rect:Rect2 in world.map_background_tiles.visible_wall_rects():
				if wall_rect.has_point(probe): wood_over_door = true
			check(not wood_over_door,"%s: painted wall top is carved from open door" % style)
		game.set_runtime_game_setting("Map_Background","grass",false)
		world.refresh_map_presentation()
		world.close_waiter_door(id,0.05)
	await create_timer(0.15).timeout
	check(world.return_map_world_rect(world.map_group["Map10x10"])==physical,"closing door preserves original physical bounds")
	game.Game_Settings = settings
	game.now_stop_state = saved_stop
	world.queue_free()
	await process_frame
	print("MAP_WALL_3D checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
