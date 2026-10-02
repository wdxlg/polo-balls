extends Node2D
## Native footprint parallel to the battlefield: no tilt, foreshortening or shear.
## Solid cloud body with a straight lower edge. No gameplay state/RNG.
## One shared World2D material: main camera, overview and recording see the same clouds.
const CLOUD_TEXTURE:Texture2D = preload("res://Images/effects/我的世界/clouds/clouds.png")
const CLOUD_SHADER:Shader = preload("res://shaders/minecraft_clouds.gdshader")
const CELL_SIZE:float = 32.0
const THICKNESS:float = CELL_SIZE / 3.0 # 12:4 native width/thickness ratio, adapted to 2D.
const PLANE_DEPTH:float = 1.0 # Square footprint cells, aligned with the ground plane.
# Screen-motion ratio, not natural drift speed. Clouds must outrun both the
# 0.18-0.32 flat backgrounds and the below-arena summit scenery (<1.0).
const OVERHEAD_PARALLAX:float = 1.25
const BACKGROUND_PARALLAX:float = OVERHEAD_PARALLAX
const DRIFT_SPEED:float = CELL_SIZE*(0.03*20.0/12.0) # Native drift relative to one texture cell.
const PERIOD:float = CELL_SIZE*256.0
const OVERHEAD_Z:int = 3000
const BACKGROUND_Z:int = -5
const SUMMIT_Z:int = -7 # Above mountains(-8), below floor(-6) and character terrain.
var world:Node
var enabled:bool = true
var overhead:bool = true
var between_layers:bool = false
var travel:float = 0.0
var cloud_material:ShaderMaterial
var regions:Array[Rect2] = []
var _parts:Array[Polygon2D] = []

## 局部云块（例如角色召来的云）：与天空云同一原版贴图、着色器、格子尺寸和厚度，只画 mask 里的格子。
## region 是 clouds.png 的像素范围，取其中最大的四连通云块；四周留一圈空格给厚度和平铺。
static func cloud_piece(region:Rect2i,transpose:bool = false) -> Image:
	var source:Image = CLOUD_TEXTURE.get_image()
	if source == null: return null
	if source.is_compressed(): source.decompress()
	region = region.intersection(Rect2i(Vector2i.ZERO,source.get_size()))
	var seen:Dictionary = {}
	var best:Array[Vector2i] = []
	for y:int in range(region.position.y,region.end.y):
		for x:int in range(region.position.x,region.end.x):
			var start := Vector2i(x,y)
			if seen.has(start) or source.get_pixelv(start).a <= 0.5: continue
			var group:Array[Vector2i] = [start]
			seen[start] = true
			var index:int = 0
			while index < group.size():
				var cell:Vector2i = group[index]
				index += 1
				for step:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var next:Vector2i = cell+step
					if region.has_point(next) and not seen.has(next) and source.get_pixelv(next).a > 0.5:
						seen[next] = true
						group.append(next)
			if group.size() > best.size(): best = group
	if best.is_empty(): return null
	var low := Vector2i(1 << 30,1 << 30)
	var high := Vector2i(-1,-1)
	for cell:Vector2i in best:
		low = Vector2i(mini(low.x,cell.x),mini(low.y,cell.y))
		high = Vector2i(maxi(high.x,cell.x),maxi(high.y,cell.y))
	var size:Vector2i = high-low+Vector2i(3,3)
	var mask := Image.create(size.y if transpose else size.x,size.x if transpose else size.y,false,Image.FORMAT_RGBA8)
	for cell:Vector2i in best:
		var local:Vector2i = cell-low+Vector2i.ONE
		mask.set_pixelv(Vector2i(local.y,local.x) if transpose else local,Color.WHITE)
	return mask

static func make_patch(mask:Image,tint:Color = Color.WHITE) -> Polygon2D:
	var patch := Polygon2D.new()
	var shader_material := ShaderMaterial.new()
	shader_material.shader = CLOUD_SHADER
	shader_material.set_shader_parameter("cloud_mask",ImageTexture.create_from_image(mask))
	shader_material.set_shader_parameter("cell_size",CELL_SIZE)
	shader_material.set_shader_parameter("height_shift",Vector2(0.0,THICKNESS))
	shader_material.set_shader_parameter("plane_depth",PLANE_DEPTH)
	shader_material.set_shader_parameter("parallax",1.0)
	shader_material.set_shader_parameter("cloud_tint",tint)
	patch.material = shader_material
	patch.color = Color.WHITE
	var size := Vector2(mask.get_size())*CELL_SIZE
	patch.polygon = PackedVector2Array([Vector2.ZERO,Vector2(size.x,0.0),size,Vector2(0.0,size.y)])
	return patch

## 把云块的格子中心放到 center（世界坐标）。
static func place_patch(patch:Polygon2D,center:Vector2) -> void:
	var top_left:Vector2 = center-patch.polygon[2]*0.5
	patch.global_position = top_left
	(patch.material as ShaderMaterial).set_shader_parameter("cell_origin",top_left)

func _init(owner_world:Node = null) -> void:
	world = owner_world

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	visibility_layer = 1
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	cloud_material.set_shader_parameter("cloud_mask",CLOUD_TEXTURE)
	cloud_material.set_shader_parameter("cell_size",CELL_SIZE)
	cloud_material.set_shader_parameter("height_shift",Vector2(0.0,THICKNESS))
	cloud_material.set_shader_parameter("plane_depth",PLANE_DEPTH)
	refresh()
	RenderingServer.frame_pre_draw.connect(_sync_battle_focus)

func refresh() -> void:
	if not is_instance_valid(world) or cloud_material == null: return
	enabled = bool(Game.Game_Settings.get("Minecraft_Clouds",true))
	var style:String = world.map_background_style()
	overhead = style == "blue"
	between_layers = style == "summit"
	z_index = OVERHEAD_Z if overhead else (SUMMIT_Z if between_layers else BACKGROUND_Z)
	cloud_material.set_shader_parameter("parallax",OVERHEAD_PARALLAX if overhead else BACKGROUND_PARALLAX)
	_sync_battle_focus()
	visible = enabled
	if not enabled: return
	# Reuse the world's exact island-union complement. Grass/other tiled maps
	# keep clouds outside the opaque arena, behind walls, people and labels.
	regions.clear()
	# Summit has real foreground alpha: clouds may continue beneath islands/columns.
	# The foreground 3D pass occludes them precisely, including perspective and doors.
	if overhead or between_layers:
		regions.append(Rect2(-1000000,-1000000,2000000,2000000))
	else:
		var map_node:Node = world._current_map_node()
		if map_node == null: visible = false; return
		var map_rect:Rect2 = world.return_map_visual_rect(map_node)
		regions.assign(world._map_outside_rects(world._current_visual_island_rects(map_rect)))
	while _parts.size() < regions.size():
		var part:=Polygon2D.new()
		part.name = "CloudRegion%d" % _parts.size()
		part.material = cloud_material
		part.color = Color.WHITE
		part.visibility_layer = 1
		add_child(part)
		_parts.append(part)
	for i:int in _parts.size():
		_parts[i].visible = i < regions.size()
		if i < regions.size():
			var rect:Rect2 = regions[i]
			_parts[i].polygon = PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func _sync_battle_focus() -> void:
	if cloud_material == null: return
	if between_layers and is_instance_valid(world) and is_instance_valid(world.map_wall_volume):
		world.map_wall_volume.apply_battle_focus(cloud_material)
	else:
		cloud_material.set_shader_parameter("focus_strength",0.0)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_battle_focus):
		RenderingServer.frame_pre_draw.disconnect(_sync_battle_focus)

func advance(delta:float) -> void:
	if not enabled or not is_inside_tree() or not is_finite(delta) or delta <= 0.0: return
	if Game.now_stop_state or get_tree().paused or Engine.time_scale <= 0.000001: return
	# Physics delta only, never shader wall time; pause/offline capture cannot jump.
	travel = fposmod(travel+delta*DRIFT_SPEED,PERIOD)
	cloud_material.set_shader_parameter("travel",travel)

func reset_drift() -> void:
	travel = 0.0
	if cloud_material != null: cloud_material.set_shader_parameter("travel",travel)
