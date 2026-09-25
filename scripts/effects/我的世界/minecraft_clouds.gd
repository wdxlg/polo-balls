extends Node2D
## Native fancy-cloud footprint extruded into a 12x12x4 slab. No gameplay state/RNG.
## One shared World2D material: main camera, overview and recording see the same clouds.
const CLOUD_TEXTURE:Texture2D = preload("res://Images/effects/我的世界/clouds/clouds.png")
const CLOUD_SHADER:Shader = preload("res://shaders/minecraft_clouds.gdshader")
const CELL_SIZE:float = 48.0
const THICKNESS:float = 16.0
const DRIFT_SPEED:float = 2.4 # Vanilla 0.03 block/tick * 20 ticks/sec * 4 px/block.
const PERIOD:float = CELL_SIZE*256.0
const OVERHEAD_Z:int = 3000
const BACKGROUND_Z:int = -5
var world:Node
var enabled:bool = true
var overhead:bool = true
var travel:float = 0.0
var cloud_material:ShaderMaterial
var regions:Array[Rect2] = []
var _parts:Array[Polygon2D] = []

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
	cloud_material.set_shader_parameter("height_shift",Vector2(-THICKNESS*0.5,-THICKNESS))
	refresh()

func refresh() -> void:
	if not is_instance_valid(world) or cloud_material == null: return
	enabled = bool(Game.Game_Settings.get("Minecraft_Clouds",true))
	overhead = world.map_background_style() == "blue"
	z_index = OVERHEAD_Z if overhead else BACKGROUND_Z
	visible = enabled
	if not enabled: return
	# Reuse the world's exact island-union complement. Grass/other tiled maps
	# keep clouds outside the opaque arena, behind walls, people and labels.
	regions.clear()
	if overhead:
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

func advance(delta:float) -> void:
	if not enabled or not is_inside_tree() or not is_finite(delta) or delta <= 0.0: return
	if Game.now_stop_state or get_tree().paused or Engine.time_scale <= 0.000001: return
	# Physics delta only, never shader wall time; pause/offline capture cannot jump.
	travel = fposmod(travel+delta*DRIFT_SPEED,PERIOD)
	cloud_material.set_shader_parameter("travel",travel)

func reset_drift() -> void:
	travel = 0.0
	if cloud_material != null: cloud_material.set_shader_parameter("travel",travel)
