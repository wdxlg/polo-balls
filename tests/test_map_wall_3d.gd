extends SceneTree
# 六主题/真实方块网格/内凹边和门洞/蓝色平面/原 2D 碰撞回归。
const THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
const OAK:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/oak_log.png")
const SAND:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sandstone.png")
const PURPUR:Texture2D = preload("res://Images/effects/我的世界/草方块背景/purpur_pillar_side.png")
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MAP_WALL_TRUE_3D FAIL: "+label)
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

func _wall_covers(rects:Array[Rect2],point:Vector2) -> bool:
	for rect:Rect2 in rects:
		if rect.has_point(point): return true
	return false

func _expected_side(style:String) -> Texture2D:
	match style:
		"grass": return OAK
		"sand": return SAND
		"end": return PURPUR
		_: return THEMES.wall_texture(style)

func _run() -> void:
	create_timer(80.0).timeout.connect(func(): quit(2))
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
	check(physical.has_area() and not first_hit.is_empty(),"original map collision exists")
	check(world.map_wall_volume == null,"blue initial scene never allocates a 3D wall")
	check(world.map_inside_shadow.surface.material.get_shader_parameter("shadow_vector")==Vector2.ZERO,"blue keeps only the flat border/contact shade")
	check(world.map_background_tiles.visible==false,"blue uses original flat map floor")
	check(world.map_wall_light_direction.x>0.0 and world.map_wall_light_direction.y<0.0,"light defaults to top-right")
	for style:String in ["grass","sand","stone","nether","end"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		await process_frame
		await physics_frame
		var volume:Node2D = world.map_wall_volume
		var cell:Vector2 = world.map_visual_cell_size(world.map_group["Map10x10"])
		var cast:Vector2 = -world.map_wall_light_direction.normalized()*minf(cell.x,cell.y)*world.map_wall_shadow_cells
		var shader:ShaderMaterial = world.map_inside_shadow.surface.material
		check(is_instance_valid(volume) and volume.visible and volume.wall_rects.size()>0 and volume.block_count>=20,"%s: physical 3D block instances follow the actual wall footprint" % style)
		check(volume.viewport is SubViewport and volume.viewport.own_world_3d and volume.viewport.transparent_bg and volume.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"%s: independent transparent real 3D camera" % style)
		check(volume.sun_light is DirectionalLight3D and volume.sun_light.shadow_enabled and volume.mesh_node is MeshInstance3D,"%s: light casts shadows on true six-faced 3D mesh" % style)
		var mesh:ArrayMesh = volume.mesh_node.mesh as ArrayMesh
		check(mesh != null and mesh.get_surface_count()==3 and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==volume.block_count*6 and mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX].size()==volume.block_count*24,"%s: top, 4 sides and underside are genuine 3D triangles" % style)
		var cap:StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
		var side:StandardMaterial3D = mesh.surface_get_material(1) as StandardMaterial3D
		check(cap.albedo_texture==THEMES.wall_texture(style) and side.albedo_texture==_expected_side(style) and side.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL,"%s: Mojang block top and corresponding original side in lit 3D material" % style)
		var center:Vector2 = physical.get_center()
		var points:Array[Vector2] = [center,center+Vector2(cell.x*3.5,cell.y*2.5)]
		var aligned:bool = true
		for point:Vector2 in points:
			var projected:Vector2 = volume.picture.position+volume.camera.unproject_position(volume._ground_point(point,0))/_scale(volume)
			if projected.distance_to(point)>0.6: aligned=false
		check(aligned,"%s: 3D camera ground projection aligns with 2D map across distant cells" % style)
		check(bool(shader.get_shader_parameter("directional_enabled")) and shader.get_shader_parameter("shadow_vector")==cast and shader.get_shader_parameter("segment_count")==volume.wall_edges.size(),"%s: foreground shadow follows actual cut wall edges" % style)
		var hit:Dictionary = world.get_world_2d().direct_space_state.intersect_ray(ray)
		check(world.return_map_world_rect(world.map_group["Map10x10"])==physical and _safety_snapshot(world._map_safety_frame)==collision and not hit.is_empty() and hit.position.is_equal_approx(first_hit.position),"%s: new 3D meshes leave collision unchanged" % style)
		check(world.map_background_tiles.visible and volume.z_index>world.map_outside_mask_root.z_index and volume.z_index<world.map_border_segment_root.z_index,"%s: floor and foreground/door draw order preserved" % style)
		check(volume.find_children("*","CollisionObject2D",true,false).is_empty(),"%s: 3D mesh does not inject physics into combat" % style)
	for map_key:String in ["Map50x50","Map_Portal","Map10x10"]:
		world.now_choose_map = map_key
		world.refresh_map_presentation()
		var volume:Node2D = world.map_wall_volume
		check(volume.visible and not volume.wall_rects.is_empty() and volume.block_count>0 and volume.viewport.size.x<=4096 and volume.viewport.size.y<=4096,"%s: map switch rebuilds bounded viewport and real 3D blocks" % map_key)
		check(world.map_inside_shadow.surface.material.get_shader_parameter("segment_count")==volume.wall_edges.size(),"%s: shape edges and floor shadow stay in sync" % map_key)
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
		check(not _edge_covers_gap(world.map_wall_volume.wall_edges,side,line,along-float(info.width)*0.5,along+float(info.width)*0.5),"open door removes the exposed 3D edge")
		check(world.map_inside_shadow.surface.material.get_shader_parameter("segment_count")==world.map_wall_volume.wall_edges.size(),"door removes fake floor cast too")
		var cell:Vector2 = world.map_visual_cell_size(world.map_group["Map10x10"])
		var probe:Vector2 = [Vector2(physical.position.x-cell.x*0.5,along),Vector2(physical.end.x+cell.x*0.5,along),Vector2(along,physical.position.y-cell.y*0.5),Vector2(along,physical.end.y+cell.y*0.5)][side]
		for style:String in ["grass","sand","stone","nether","end"]:
			game.set_runtime_game_setting("Map_Background",style,false)
			world.refresh_map_presentation()
			check(not _wall_covers(world.map_wall_volume.wall_rects,probe),"%s: 3D block does not bridge the opening" % style)
			check(not _wall_covers(world.map_background_tiles.visible_wall_rects(),probe),"%s: underlying 2D wall top also stays carved" % style)
		game.set_runtime_game_setting("Map_Background","blue",false)
		world.refresh_map_presentation()
		check(not world.map_wall_volume.visible and world.map_wall_volume.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and world.map_wall_volume.block_count==0,"back to blue fully disables existing 3D world")
		check(world.map_inside_shadow.surface.material.get_shader_parameter("shadow_vector")==Vector2.ZERO,"blue remains flat after switching from 3D")
		game.set_runtime_game_setting("Map_Background","grass",false)
		world.refresh_map_presentation()
		world.close_waiter_door(id,0.05)
	await create_timer(0.15).timeout
	check(world.return_map_world_rect(world.map_group["Map10x10"])==physical,"closing door preserves physical map bounds")
	game.Game_Settings = settings
	game.now_stop_state = saved_stop
	world.queue_free()
	await process_frame
	print("MAP_WALL_TRUE_3D checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func _scale(volume:Node2D) -> float:
	return volume._render_scale
