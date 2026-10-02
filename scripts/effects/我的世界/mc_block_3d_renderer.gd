extends "res://scripts/effects/我的世界/地图立体墙.gd"
## 单格 3D 方块障碍专用的透视 overlay（工作台/锻造台/仙人掌/杜鹃花丛）。
## 与地图立体墙同一相机、投影、受光材质；太阳、环境光与地影强度每帧照抄地图墙体
## （随昼夜转向，按地图主题换能量），没有墙的蓝色主题用地图墙默认光和同一个昼夜太阳方向。
## 和墙一样画在角色之下（z -4），方块的真实影子投到 2D 地面上。
const NAME:StringName = &"MCBlock3DRenderer"
const USERS_META:StringName = &"mc_block_3d_users"
## 与地图立体墙 configure_regions 的默认（草/石/下界）一致。
const DEFAULT_AMBIENT_COLOR:Color = Color(0.72,0.79,0.89)
const DEFAULT_AMBIENT_ENERGY:float = 1.35
const DEFAULT_SUN_ENERGY:float = 2.6
const SHADOW_ALPHA:float = 0.62
const GROUND_CHECK_SECONDS:float = 0.5

var _ground_key:String = "-"
var _ground_wait:float = 0.0


## 宿主（世界场景）下共用的一份；首次调用时创建。
static func shared_for(host:Node,cell:float) -> Node2D:
	if host == null: return null
	var existing:Node = host.get_node_or_null(NodePath(String(NAME)))
	if existing != null:
		if existing.is_queued_for_deletion() or not is_instance_valid(existing.get("viewport")): return null
		return existing as Node2D
	var renderer:Node2D = load("res://scripts/effects/我的世界/mc_block_3d_renderer.gd").new()
	renderer.name = NAME
	renderer.set_meta(USERS_META,0)
	host.add_child(renderer)
	renderer.configure_block_overlay(cell)
	return renderer


static func add_user(renderer:Node2D,change:int) -> void:
	if not is_instance_valid(renderer): return
	var users:int = maxi(int(renderer.get_meta(USERS_META,0))+change,0)
	renderer.set_meta(USERS_META,users)
	renderer.set_active(users > 0)


func configure_block_overlay(cell:float) -> void:
	var host:Node = get_parent()
	var light:Variant = host.get("map_wall_light_direction") if host != null else null
	configure_surface_overlay(Vector2.ONE*cell,light if light is Vector2 else Vector2(1.0,-1.0))
	# 墙是背景：地面(-5) < 墙/地影(-4) < 人物。方块障碍同层，晚于地图墙加入，画在墙之上。
	z_as_relative = false
	z_index = -4
	# surface overlay 默认关闭地影通道；方块要像墙一样把真实影子投到地面。
	shadow_picture.show()
	_refresh_ground(true)
	sync_map_lighting()
	set_active(false)


func set_active(active:bool) -> void:
	visible = active
	set_process(active)
	if not is_instance_valid(viewport): return
	var mode:int = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	viewport.render_target_update_mode = mode
	shadow_viewport.render_target_update_mode = mode
	if active:
		_refresh_ground(true)
		sync_map_lighting()


func _process(delta:float) -> void:
	sync_map_lighting()
	_ground_wait -= delta
	if _ground_wait <= 0.0:
		_ground_wait = GROUND_CHECK_SECONDS
		_refresh_ground(false)


## 太阳/环境光/地影强度与地图墙体完全一致。
func sync_map_lighting() -> void:
	if not is_instance_valid(sun_light) or not sun_light.is_inside_tree(): return
	var host:Node = get_parent()
	var ambient:Environment = (viewport.get_node("BlockAmbientLight") as WorldEnvironment).environment
	var wall:Variant = host.get("map_wall_volume") if host != null else null
	if wall is Node2D and is_instance_valid(wall) and (wall as Node2D).visible and bool(wall.get("tiled")) and is_instance_valid(wall.get("sun_light")) and (wall.sun_light as Node3D).is_inside_tree():
		var wall_sun:DirectionalLight3D = wall.sun_light
		sun_light.global_transform = wall_sun.global_transform
		sun_light.light_color = wall_sun.light_color
		sun_light.light_energy = wall_sun.light_energy
		sun_light.shadow_opacity = wall_sun.shadow_opacity
		var wall_ambient:Environment = (wall.viewport.get_node("BlockAmbientLight") as WorldEnvironment).environment
		ambient.ambient_light_color = wall_ambient.ambient_light_color
		ambient.ambient_light_energy = wall_ambient.ambient_light_energy
	else:
		var light:Variant = host.get("map_wall_light_direction") if host != null else null
		_update_light(light if light is Vector2 else Vector2(1.0,-1.0))
		var daylight:float = 1.0
		var cycle:Variant = host.get("day_night_cycle") if host != null else null
		if cycle is Node and is_instance_valid(cycle) and bool(cycle.get("enabled")): daylight = clampf(float(cycle.get("daylight")),0.0,1.0)
		sun_light.light_energy = DEFAULT_SUN_ENERGY
		sun_light.shadow_opacity = daylight
		ambient.ambient_light_color = DEFAULT_AMBIENT_COLOR
		ambient.ambient_light_energy = DEFAULT_AMBIENT_ENERGY
	shadow_sun.global_transform = sun_light.global_transform
	shadow_sun.light_color = sun_light.light_color
	shadow_sun.light_energy = sun_light.light_energy
	shadow_sun.shadow_opacity = sun_light.shadow_opacity
	shadow_picture.modulate.a = SHADOW_ALPHA*sun_light.shadow_opacity


## 地影只落在真实地图岛屿上（与地图墙的接影地面同一范围）；换图后自动更新。
func _refresh_ground(force:bool) -> void:
	if not is_instance_valid(ground_node): return
	var host:Node = get_parent()
	var rects:Array[Rect2] = []
	if host != null and host.has_method("current_map_island_rects"):
		rects = host.call("current_map_island_rects")
	var key:String = str(rects)
	if not force and key == _ground_key: return
	_ground_key = key
	if rects.is_empty():
		ground_node.mesh = null
		return
	var catcher := SurfaceTool.new()
	catcher.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect:Rect2 in rects:
		var x0:float = rect.position.x
		var x1:float = rect.end.x
		var y0:float = rect.position.y
		var y1:float = rect.end.y
		_face(catcher,[Vector3(x0,-0.08,y0),Vector3(x0,-0.08,y1),Vector3(x1,-0.08,y1),Vector3(x1,-0.08,y0)],[Vector2.ZERO,Vector2.DOWN,Vector2.ONE,Vector2.RIGHT])
	ground_node.mesh = catcher.commit()
