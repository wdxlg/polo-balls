extends Node
## 入墙/出墙时按墙面裁切流浪商人的身体：只画墙面靠地板一侧的部分，已经钻进墙里的身体看不见。
## 做法：运行时把角色 Image 当前材质的 shader（ball.tscn 的 set_rgb_color.gdshader）源码注入一个世界空间半平面裁切
## （同名 instance uniform 保持不变：受击闪白、朝向翻转、软体形变都照旧），阶段期间给 Image
## 换上这份材质，结束后换回原材质。不用 clip_children：它的 canvas group 会改写 World
## 地图外遮罩（MapClipBackBuffer + screen_texture）读取的后备缓冲，墙外会冒出未裁切的身体。
## 纯视觉，每个端各自执行。
static var _clip_shaders:Dictionary = {} # base Shader -> clip Shader (null when not injectable)

var image:CanvasItem
var face:Vector2
var normal:Vector2 = Vector2.UP
var active:bool = false
var _original_material:Material
var _material:ShaderMaterial

static func base_shader_of(target:CanvasItem) -> Shader:
	if target == null or not is_instance_valid(target): return null
	var material:ShaderMaterial = target.material as ShaderMaterial
	return material.shader if material != null else null

## Base shader + clip (cached per base). Returns null if the base lacks the injection anchors.
static func clip_shader(base:Shader) -> Shader:
	if base == null: return null
	if _clip_shaders.has(base): return _clip_shaders[base]
	var code:String = base.code
	var anchors:Array[String] = ["varying vec4 sprite_modulate;","\tsprite_modulate = COLOR;","\tCOLOR = out_color;"]
	var ok:bool = not code.is_empty()
	for anchor:String in anchors: ok = ok and code.count(anchor) == 1
	if not ok:
		_clip_shaders[base] = null
		return null
	code = code.replace(anchors[0],anchors[0] + "\nvarying vec2 wall_clip_world;\nuniform vec2 wall_clip_point = vec2(0.0);\nuniform vec2 wall_clip_normal = vec2(0.0,-1.0);")
	code = code.replace(anchors[1],anchors[1] + "\n\twall_clip_world = (MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy;")
	code = code.replace(anchors[2],"\tif (dot(wall_clip_world - wall_clip_point,wall_clip_normal) < 0.0) { out_color.a = 0.0; }\n" + anchors[2])
	var shader := Shader.new()
	shader.code = code
	_clip_shaders[base] = shader
	return shader

func start(target:CanvasItem,face_point:Vector2,face_normal:Vector2) -> bool:
	if not is_instance_valid(target): return false
	if active and image != target: stop()
	if not active:
		var shader:Shader = clip_shader(base_shader_of(target))
		if shader == null: return false
		image = target
		_original_material = image.material
		if _material == null or _material.shader != shader:
			_material = ShaderMaterial.new()
			_material.shader = shader
		image.material = _material
	face = face_point
	normal = face_normal.normalized() if face_normal.length_squared() > 0.000001 else Vector2.UP
	_material.set_shader_parameter(&"wall_clip_point",face)
	_material.set_shader_parameter(&"wall_clip_normal",normal)
	active = true
	return true

func stop() -> void:
	if active and is_instance_valid(image) and image.material == _material: image.material = _original_material
	active = false

func _exit_tree() -> void:
	stop()

## Signed distance of a world point from the wall surface (> 0 = floor side, visible).
func side_of(point:Vector2) -> float:
	return (point - face).dot(normal)
