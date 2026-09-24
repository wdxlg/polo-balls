extends Node2D
const POINTS = preload("res://scripts/characters/我的世界/fog_man/eye_points.gd")
var actor:Node2D
var trails:Array[Dictionary] = []
var last_position:Vector2 = Vector2.INF
var emission_left:float = 0.0
func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 96
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
func _process(delta:float) -> void:
	if not is_instance_valid(actor): queue_free(); return
	if not actor.is_combat_runtime_active(): return
	if actor.health<=0 or actor.phase == actor.Phase.VANISHED:
		trails.clear()
		last_position = Vector2.INF
		queue_redraw()
		return
	for i:int in range(trails.size()-1,-1,-1):
		trails[i].age += delta
		if trails[i].age >= 0.28: trails.remove_at(i)
	emission_left -= delta
	if emission_left <= 0.0 and last_position != Vector2.INF and actor.global_position.distance_to(last_position)>0.25:
		emission_left = 0.025
		if trails.size() >= 12: trails.pop_front()
		trails.append({"transform":eye_transform(),"texture":actor.eye_texture(),"points":eye_points(),"age":0.0})
	last_position = actor.global_position
	queue_redraw()
func eye_transform() -> Transform2D:
	var result:Transform2D = actor.image.global_transform
	if actor._visual_facing_flipped_h: result = result.scaled_local(Vector2(-1,1))
	return result.translated_local(actor.image.offset)
func eye_points() -> Array[Vector2]:
	var result:Array[Vector2] = []
	var transform:Transform2D = eye_transform()
	for point:Vector2 in POINTS.POINTS[str(actor._clip)][actor._frame_index]: result.append(transform*point)
	return result
func draw_glow(points:Array[Vector2],alpha:float) -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for point:Vector2 in points:
		draw_circle(point,3.3,Color(0.4,0.72,1.0,0.055*alpha))
		draw_circle(point,2.1,Color(0.5,0.8,1.0,0.13*alpha))
		draw_circle(point,1.2,Color(0.7,0.9,1.0,0.32*alpha))
		draw_circle(point,0.65,Color(1,1,1,0.95*alpha))
func _draw() -> void:
	if not is_instance_valid(actor) or actor.health<=0 or actor.phase == actor.Phase.VANISHED: return
	var alpha:float = actor.body_alpha()
	for entry:Dictionary in trails:
		var fade:float = (1.0-entry.age/0.28)*0.42*alpha
		draw_set_transform_matrix(entry.transform)
		draw_texture(entry.texture,-entry.texture.get_size()*0.5,Color(0.55,0.8,1,fade))
		draw_glow(entry.points,fade)
	var tex:Texture2D = actor.eye_texture()
	if tex != null:
		draw_set_transform_matrix(eye_transform())
		draw_texture(tex,-tex.get_size()*0.5,Color(1,1,1,alpha))
	draw_glow(eye_points(),alpha)
	draw_set_transform_matrix(Transform2D.IDENTITY)
