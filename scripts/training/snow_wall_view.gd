extends Node2D
## Minecraft snow appearance only: real wall-top cuboids + native precipitation sheets.
## No collider, damage, cold meter, AI threat, RPC or gameplay RNG in this view.
const WALL_RENDERER = preload("res://scripts/effects/我的世界/地图立体墙.gd")
const NATIVE_SNOW:Texture2D = preload("res://Images/effects/我的世界/雪环境/snow.png")
const NATIVE_WEATHER:Texture2D = preload("res://Images/effects/我的世界/雪环境/snowfall.png")
# Vanilla snow_height2.json: [0,0,0] -> [16,2,16]; side UVs [0,14,16,16].
const WEATHER_FADE_SECONDS:float = 0.9
const LAYER_HEIGHT:float = 2.0/16.0
const SIDE_UV:Vector2 = Vector2(14.0/16.0,1.0)
const WEATHER_LAYERS:Array[Vector3] = [Vector3(0.9,28,0.34),Vector3(1.4,43,0.50),Vector3(2.0,66,0.62)]
var field:Node2D
var visual_walls:Array[Rect2] = []
# A bounded, constant-cost world quad covers every supported pan/zoom and each
# shared World2D viewport independently; never derive precipitation from the map.
var weather_bounds:Rect2 = Rect2(-1000000,-1000000,2000000,2000000)
var weather_enabled:bool = false
var weather_time:float = 0.0
var weather_fade:float = 0.0
var weather_phases:Array[Vector2] = [Vector2.ZERO,Vector2(21,91),Vector2(47,183)]
var renderer:Node2D
var mesh_node:MeshInstance3D
var wall_piece_count:int = 0
var snow_base_height:float = 0.0
var snow_thickness:float = 0.0
var _overlay_renderer:Node2D
var _floor_shadow:MeshInstance3D
var _ground_shadow:MeshInstance3D
var _dirty:bool = true
var _last_renderer:Node2D

func _ready() -> void:
	name = "EnvironmentSnowView"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Weather is above the battlefield, below CanvasLayer UI. Wall meshes themselves
	# stay in the existing background pass (-4), not in this foreground CanvasItem.
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX-1 # Above overhead clouds; below day/night tint and CanvasLayer UI.
	RenderingServer.frame_pre_draw.connect(_before_draw)

func request_update() -> void:
	_dirty = true
	queue_redraw()

func set_weather(enabled:bool) -> void:
	if weather_enabled==enabled: return
	weather_enabled = enabled
	# Toggle only the target; preserve opacity and flake positions on reversal.
	queue_redraw()

func reset_weather(seed_value:int) -> void:
	weather_time = 0.0
	weather_fade = 0.0
	var rng:=RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x534e4f57
	for i:int in range(weather_phases.size()): weather_phases[i] = Vector2(rng.randf_range(0,64),rng.randf_range(0,256))
	request_update()

func advance_weather(delta:float) -> void:
	if (not weather_enabled and weather_fade<=0.0) or not is_finite(delta) or delta<=0.0: return
	# Controller supplies combat delta on every peer, including guests. No wall-clock
	# TIME shader: pause/zero speed/replay cannot silently advance precipitation.
	weather_time += delta
	weather_fade = move_toward(weather_fade,1.0 if weather_enabled else 0.0,delta/WEATHER_FADE_SECONDS)
	queue_redraw()

func _draw() -> void:
	if weather_fade<=0.0 or not weather_bounds.has_area(): return
	# Tile the untouched vanilla 64x256 weather texture, not hand-drawn snow dots.
	# Three world-space sheets cover the entire visible sky, including separate
	# recording/overview cameras. Geometry stays three quads, not particles per pixel.
	for i:int in range(WEATHER_LAYERS.size()):
		var layer:Vector3 = WEATHER_LAYERS[i]
		var motion:=Vector2(6.0+float(i)*3.0,layer.y)*weather_time
		var origin:Vector2 = (weather_bounds.position-motion)/layer.x+weather_phases[i]
		origin = Vector2(fposmod(origin.x,64.0),fposmod(origin.y,256.0))
		draw_texture_rect_region(NATIVE_WEATHER,weather_bounds,Rect2(origin,weather_bounds.size/layer.x),Color(1,1,1,layer.z*weather_fade),false,false)

func _process(_delta:float) -> void:
	_sync_geometry()

func _before_draw() -> void:
	# Also follows camera/theme/visibility changes while the game is paused.
	_sync_geometry()
	var active:bool = is_visible_in_tree()
	for node:MeshInstance3D in [mesh_node,_floor_shadow,_ground_shadow]:
		if is_instance_valid(node): node.visible = active
	if is_instance_valid(_overlay_renderer):
		var world:Node = field.get_parent()
		var light:Vector2 = world.map_wall_light_direction if world.has_method("_current_map_node") else Vector2(1,-1)
		_overlay_renderer._update_light(light)

func _shared_renderer() -> Node2D:
	if not is_instance_valid(field): return null
	var world:Node = field.get_parent()
	if world.has_method("_is_grass_map_background") and world._is_grass_map_background():
		var candidate:Node2D = world.map_wall_volume
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and is_instance_valid(candidate.viewport): return candidate
	return null

func _sync_geometry() -> void:
	if not is_instance_valid(field) or not is_inside_tree(): return
	var shared:Node2D = _shared_renderer()
	if shared!=_last_renderer:
		_last_renderer = shared
		_dirty = true
	if is_instance_valid(renderer) and not is_equal_approx(snow_base_height,float(renderer.block_height)):
		_dirty = true
	if not _dirty: return
	_dirty = false
	var pieces:Array[Dictionary] = []
	var seen:Dictionary = {}
	for cell:Vector2i in field.environment_patches:
		var record:Dictionary = field.environment_patches[cell]
		if not bool(record.decorative): continue
		var alpha:float = field.snow_alpha(record)
		if alpha<=0.0: continue
		var offset:Vector2 = field._development_environment_offsets.get(cell,Vector2.ZERO)
		for piece:Dictionary in projected_pieces(cell,record):
			var rect:Rect2 = Rect2(piece.rect.position+offset,piece.rect.size)
			if seen.has(rect):
				var previous:int = int(seen[rect])
				pieces[previous].alpha = maxf(float(pieces[previous].alpha),alpha)
				continue
			seen[rect] = pieces.size()
			pieces.append({"rect":rect,"corner":piece.corner+offset,"tile_size":piece.tile_size,"alpha":alpha})
	wall_piece_count = pieces.size()
	var reusable:bool = is_instance_valid(mesh_node) and ((is_instance_valid(shared) and renderer==shared) or (not is_instance_valid(shared) and renderer==_overlay_renderer and is_instance_valid(_overlay_renderer)))
	if not reusable or pieces.is_empty(): _clear_meshes()
	if pieces.is_empty():
		_clear_overlay()
		renderer = null
		return
	if is_instance_valid(shared):
		_clear_overlay()
		renderer = shared
	else:
		# Blue retains its flat black boundary. Only the snow has 3D thickness;
		# reuse the normal renderer instead of introducing a second camera algorithm.
		if not is_instance_valid(_overlay_renderer):
			_overlay_renderer = WALL_RENDERER.new()
			_overlay_renderer.name = "BlueSnowSurfaceRenderer"
			add_child(_overlay_renderer)
			var world:Node = field.get_parent()
			var light:Vector2 = world.map_wall_light_direction if world.has_method("_current_map_node") else Vector2(1,-1)
			_overlay_renderer.configure_surface_overlay(pieces[0].tile_size,light)
			_overlay_renderer.z_index = int(world.map_border_segment_root.z_index)+1 if world.has_method("_current_map_node") and is_instance_valid(world.map_border_segment_root) else 1
		renderer = _overlay_renderer
	snow_base_height = float(renderer.block_height)
	snow_thickness = 0.0
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece:Dictionary in pieces:
		# A perceptual opacity ease avoids a bright lit surface staying clipped
		# white through most of a short fade; full-opacity lighting stays unchanged.
		var alpha:float = float(piece.alpha)
		surface.set_color(Color(1,1,1,alpha*alpha))
		var tile_size:Vector2 = piece.tile_size
		var thickness:float = minf(tile_size.x,tile_size.y)*LAYER_HEIGHT
		snow_thickness = maxf(snow_thickness,thickness)
		renderer.append_world_cuboid(surface,surface,surface,piece.rect,piece.corner,tile_size,snow_base_height,thickness,SIDE_UV)
	var mesh:ArrayMesh = surface.commit()
	var material:StandardMaterial3D = mesh_node.mesh.surface_get_material(0) if reusable else renderer._new_material(NATIVE_SNOW)
	material.emission_enabled = false
	material.vertex_color_use_as_albedo = true
	# Lit surfaces fade continuously, just like the 2D snow. Back-face culling
	# prevents rear cube faces from adding opacity back into a half-faded tile.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var shadow_material:StandardMaterial3D = _ground_shadow.material_override if reusable and is_instance_valid(_ground_shadow) else material.duplicate()
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	mesh.surface_set_material(0,material)
	if reusable:
		mesh_node.mesh = mesh
		if is_instance_valid(_floor_shadow):
			_floor_shadow.mesh = mesh
			_floor_shadow.material_override = shadow_material
		if is_instance_valid(_ground_shadow):
			_ground_shadow.mesh = mesh
			_ground_shadow.material_override = shadow_material
		return
	mesh_node = MeshInstance3D.new()
	mesh_node.name = "NativeSnowHeight2OnWallTops"
	mesh_node.mesh = mesh
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.layers = renderer.mesh_node.layers
	renderer.viewport.add_child(mesh_node)
	# Same actual mesh casts onto summit's floor pass and the old maps' catcher.
	# Older/two-pass renderers have no floor-only pass. Keep this decoration usable
	# without taking ownership of a concurrent renderer-channel refactor.
	var floor_layer:int = int(renderer.get_script().get_script_constant_map().get("FLOOR_LAYER",0))
	if floor_layer!=0:
		_floor_shadow = MeshInstance3D.new()
		_floor_shadow.name = "SnowLayerShadowForFloorPass"
		_floor_shadow.mesh = mesh
		_floor_shadow.material_override = shadow_material
		_floor_shadow.layers = floor_layer
		_floor_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mesh_node.add_child(_floor_shadow)
	_ground_shadow = MeshInstance3D.new()
	_ground_shadow.name = "SnowLayerShadowForGroundCatcher"
	_ground_shadow.mesh = mesh
	_ground_shadow.material_override = shadow_material
	_ground_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	renderer.shadow_viewport.add_child(_ground_shadow)

func _clear_meshes() -> void:
	# The floor proxy is a child of mesh_node, so it is freed with its source.
	for node:MeshInstance3D in [mesh_node,_ground_shadow]:
		if not is_instance_valid(node): continue
		node.hide()
		node.get_parent().remove_child(node)
		node.queue_free()
	mesh_node = null
	_floor_shadow = null
	_ground_shadow = null

func _clear_overlay() -> void:
	if is_instance_valid(_overlay_renderer):
		_overlay_renderer.hide()
		_overlay_renderer.get_parent().remove_child(_overlay_renderer)
		_overlay_renderer.queue_free()
	_overlay_renderer = null

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_before_draw): RenderingServer.frame_pre_draw.disconnect(_before_draw)
	_clear_meshes()
	_clear_overlay()

func projected_pieces(_cell:Vector2i,record:Dictionary) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	var tile:Rect2 = field.environment_tile(record)
	var size:Vector2 = tile.size
	for original:Rect2 in record.rects:
		var center:Vector2 = tile.get_center()
		if visual_walls.is_empty(): continue # No support: no floating decorative snow.
		# Background style is local. The same replicated record is placed on this
		# peer's real wall support; this never changes authoritative ground cells.
		var nearest:Rect2
		var best:float = INF
		var anchor:Vector2 = original.get_center()
		for wall:Rect2 in visual_walls:
			var distance:float = anchor.distance_squared_to(anchor.clamp(wall.position,wall.end))
			if distance<best:
				nearest = wall
				best = distance
		if best>pow(maxf(size.x,size.y)*2.0,2): continue
		if nearest.size.x>=nearest.size.y: center.y = nearest.get_center().y
		else: center.x = nearest.get_center().x
		var rectangle:Rect2 = Rect2(center-size*0.5,size).intersection(nearest)
		if rectangle.has_area(): result.append({"rect":rectangle,"corner":center-size*0.5,"tile_size":size})
	return result
