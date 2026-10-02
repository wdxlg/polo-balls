extends CanvasLayer
## 动态模糊：主视口和录制抓帧视口各挂一份。规则见 MCP_CONTEXT。
const SHADER = preload("res://scripts/effects/motion_blur.gdshader")
const LAYER:int = 1
const MAX_OBJECTS:int = 64
const SHUTTER:float = 0.5
const SPEED_THRESHOLD:float = 300.0
const RAMP:float = 1.25
const TELEPORT_PER_TICK:float = 80.0
const MAX_BLUR_FRACTION:float = 0.1
const DEFAULT_RADIUS:float = 4.0
const RADIUS_MARGIN:float = 1.25

static var _scan_frame:int = -1
static var _scan:Array[Dictionary] = []

var target:Viewport
var _rect:ColorRect
var _material:ShaderMaterial
var _prev_positions:Dictionary = {}
var _prev_transform:Transform2D
var _prev_physics:int = -1
var _has_prev:bool = false
var _radius_cache:Dictionary = {}
var _radius_frame:Dictionary = {}

static func attach(parent:Node,viewport:Viewport) -> Node:
	var node:CanvasLayer = load("res://scripts/effects/motion_blur.gd").new()
	node.name = "MotionBlur"
	node.target = viewport
	parent.add_child(node)
	return node

static func enabled() -> bool:
	return bool(Game.Game_Settings.get("Motion_Blur",true))

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "MotionBlurRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderingServer.frame_pre_draw.connect(update_now)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(update_now):
		RenderingServer.frame_pre_draw.disconnect(update_now)

func view_transform() -> Transform2D:
	return target.global_canvas_transform*target.canvas_transform

func update_now() -> void:
	if not is_inside_tree() or not is_instance_valid(target): return
	var world:Node = get_tree().current_scene
	if not enabled() or not (world is Node2D):
		_rect.visible = false
		_has_prev = false
		_prev_positions.clear()
		return
	var physics:int = Engine.get_physics_frames()
	var xf:Transform2D = view_transform()
	if _has_prev and physics == _prev_physics and xf == _prev_transform: return
	var ticks:int = maxi(physics-_prev_physics,1) if _has_prev else 1
	var view:Vector2 = target.get_visible_rect().size
	var zoom:float = maxf(xf.get_scale().abs().x,0.0001)
	var threshold_px:float = SPEED_THRESHOLD*float(ticks)/float(Engine.physics_ticks_per_second)*zoom
	var max_blur:float = maxf(view.x,view.y)*MAX_BLUR_FRACTION
	var to_previous:Transform2D = _prev_transform*xf.affine_inverse() if _has_prev else Transform2D.IDENTITY
	if _has_prev:
		var center_motion:float = (view*0.5-to_previous*(view*0.5)).length()
		if center_motion > TELEPORT_PER_TICK*float(ticks)*zoom: to_previous = Transform2D.IDENTITY
	var candidates:Array[Dictionary] = []
	var positions:Dictionary = {}
	for entry:Dictionary in _scan_world(world):
		var item:CanvasItem = entry.item
		var id:int = entry.id
		var position:Vector2 = _world_center(item)
		positions[id] = position
		if not _has_prev or not _prev_positions.has(id): continue
		var previous:Vector2 = _prev_positions[id]
		if position.distance_to(previous) > TELEPORT_PER_TICK*float(ticks): continue
		var now_screen:Vector2 = xf*position
		var motion:Vector2 = now_screen-_prev_transform*previous
		var blur:Vector2 = motion*SHUTTER*_weight(motion.length(),threshold_px)
		var camera_motion:Vector2 = now_screen-to_previous*now_screen
		var camera_blur:Vector2 = camera_motion*SHUTTER*_weight(camera_motion.length(),threshold_px)
		var difference:float = (blur-camera_blur).length()
		if difference < 0.5: continue
		candidates.append({"center":now_screen,"blur":blur,"radius":_radius(item)*zoom,"priority":difference})
	_prev_positions = positions
	_prev_transform = xf
	_prev_physics = physics
	_has_prev = true
	candidates.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return float(a.priority) > float(b.priority))
	var count:int = mini(candidates.size(),MAX_OBJECTS)
	var objects := PackedVector4Array()
	var radii := PackedFloat32Array()
	objects.resize(MAX_OBJECTS)
	radii.resize(MAX_OBJECTS)
	for i:int in range(count):
		var c:Dictionary = candidates[i]
		objects[i] = Vector4(c.center.x,c.center.y,c.blur.x,c.blur.y)
		radii[i] = float(c.radius)
	var camera_active:bool = false
	for corner:Vector2 in [Vector2.ZERO,Vector2(view.x,0),Vector2(0,view.y),view,view*0.5]:
		if (corner-to_previous*corner).length() >= threshold_px: camera_active = true
	_rect.visible = count > 0 or camera_active
	if not _rect.visible: return
	_material.set_shader_parameter("view_size",view)
	_material.set_shader_parameter("object_count",count)
	_material.set_shader_parameter("objects",objects)
	_material.set_shader_parameter("radii",radii)
	_material.set_shader_parameter("cam_x",to_previous.x)
	_material.set_shader_parameter("cam_y",to_previous.y)
	_material.set_shader_parameter("cam_o",to_previous.origin)
	_material.set_shader_parameter("cam_threshold",threshold_px)
	_material.set_shader_parameter("shutter",SHUTTER)
	_material.set_shader_parameter("ramp",RAMP)
	_material.set_shader_parameter("max_blur",max_blur)

static func _weight(motion_px:float,threshold_px:float) -> float:
	return smoothstep(threshold_px,threshold_px*RAMP,motion_px)

static func _scan_world(world:Node) -> Array[Dictionary]:
	var frame:int = Engine.get_process_frames()
	if frame == _scan_frame: return _scan
	_scan_frame = frame
	_scan = []
	for child:Node in world.get_children():
		_add_candidate(child)
		if child is CanvasItem and not (child as CanvasItem).is_visible_in_tree(): continue
		for grandchild:Node in child.get_children():
			if not (child is Node2D) or (grandchild is CanvasItem and (grandchild as CanvasItem).top_level):
				_add_candidate(grandchild)
	return _scan

static func _add_candidate(node:Node) -> void:
	if not (node is Node2D or node is Control): return
	if node is Camera2D or node is AudioStreamPlayer2D or node is Marker2D or node is RemoteTransform2D or node is VisibleOnScreenNotifier2D: return
	var item:CanvasItem = node as CanvasItem
	if not item.is_visible_in_tree() or item.get_canvas_layer_node() != null: return
	_scan.append({"item":item,"id":item.get_instance_id()})

static func _world_center(item:CanvasItem) -> Vector2:
	if item is Control: return (item as Control).get_global_rect().get_center()
	return (item as Node2D).global_position

func _radius(item:CanvasItem) -> float:
	var id:int = item.get_instance_id()
	var frame:int = Engine.get_process_frames()
	if _radius_cache.has(id) and frame-int(_radius_frame.get(id,0)) < 30: return float(_radius_cache[id])
	var r:float = measure_radius(item)
	_radius_cache[id] = r
	_radius_frame[id] = frame
	if _radius_cache.size() > 4096:
		_radius_cache.clear()
		_radius_frame.clear()
	return r

static func measure_radius(item:CanvasItem) -> float:
	if item is Control:
		return (item as Control).get_global_rect().size.length()*0.5+1.0
	var node:Node2D = item as Node2D
	var best:float = 0.0
	var parts:Array[Node] = [node]
	parts.append_array(node.get_children())
	for part:Node in parts:
		var local:Rect2 = _local_rect(part)
		if local.size == Vector2.ZERO: continue
		var xf:Transform2D = (part as Node2D).transform if part != node else Transform2D.IDENTITY
		for corner:Vector2 in [local.position,local.position+Vector2(local.size.x,0),local.position+Vector2(0,local.size.y),local.end]:
			best = maxf(best,(xf*corner).length())
	var s:Vector2 = node.global_scale.abs()
	var r:float = best*maxf(s.x,s.y) if best > 0.0 else DEFAULT_RADIUS
	return r*RADIUS_MARGIN+1.0

static func _local_rect(part:Node) -> Rect2:
	if part is CollisionShape2D and (part as CollisionShape2D).shape != null:
		return (part as CollisionShape2D).shape.get_rect()
	if part is Sprite2D and (part as Sprite2D).texture != null:
		return (part as Sprite2D).get_rect()
	if part is AnimatedSprite2D:
		var sprite:AnimatedSprite2D = part
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation) and sprite.sprite_frames.get_frame_count(sprite.animation) > 0:
			var texture:Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
			if texture != null:
				var size:Vector2 = texture.get_size()
				return Rect2(-size*0.5 if sprite.centered else Vector2.ZERO,size)
	return Rect2()
