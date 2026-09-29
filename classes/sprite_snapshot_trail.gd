extends Node2D
## Bounded visual-only trails for arbitrary plain sprites. Caller owns the clock
## and activation rules; snapshots reuse ball's safe sprite copier and shader.
const MATERIAL:ShaderMaterial = preload("res://shaders/after_image_material.tres")
const MAX_PER_SOURCE:int = 24
const MAX_GLOBAL:int = 256
static var live_count:int = 0
var samples:Array[Dictionary] = []
var total_emitted:int = 0

func capture(source:Sprite2D,pose:Transform2D,lifetime:float=0.16,alpha:float=0.42,tag:int=0) -> bool:
	if not is_instance_valid(source) or not source.is_visible_in_tree() or source.texture==null: return false
	if samples.size()>=MAX_PER_SOURCE or live_count>=MAX_GLOBAL: return false
	var copier:Node = get_parent()
	if not copier.has_method("_make_plain_sprite_snapshot"): return false
	var ghost:Sprite2D = copier._make_plain_sprite_snapshot(source)
	if ghost==null: return false
	ghost.name = "SpriteTrailSnapshot"
	ghost.material = MATERIAL
	ghost.top_level = true
	ghost.z_as_relative = false
	ghost.z_index = source.z_index-1
	ghost.set_instance_shader_parameter("progress",0.0)
	ghost.set_instance_shader_parameter("trail_direction",Vector2.RIGHT)
	ghost.set_instance_shader_parameter("source_flip_h",0.0)
	ghost.set_instance_shader_parameter("start_color",Color.WHITE)
	ghost.set_instance_shader_parameter("end_color",Color.WHITE)
	ghost.set_instance_shader_parameter("visual_params_a",Vector4(clampf(alpha,0.0,1.0),0.0,0.0,0.0))
	ghost.set_instance_shader_parameter("visual_params_b",Vector4.ZERO)
	ghost.set_instance_shader_parameter("style_mode",0)
	ghost.set_instance_shader_parameter("sample_count",1)
	ghost.set_instance_shader_parameter("fade_mode",1)
	add_child(ghost)
	ghost.global_transform = pose
	samples.append({"sprite":ghost,"age":0.0,"lifetime":maxf(lifetime,0.05),"tag":tag})
	live_count += 1
	total_emitted += 1
	return true

func advance(delta:float) -> void:
	if delta<=0.0: return
	for i:int in range(samples.size()-1,-1,-1):
		var sample:Dictionary = samples[i]
		sample.age += delta
		if sample.age>=sample.lifetime:
			_retire(sample)
			samples.remove_at(i)
		else:
			(sample.sprite as Sprite2D).set_instance_shader_parameter("progress",sample.age/sample.lifetime)

func _retire(sample:Dictionary) -> void:
	var ghost:Sprite2D = sample.sprite
	if is_instance_valid(ghost):
		ghost.hide()
		ghost.queue_free()
	live_count = maxi(live_count-1,0)

func clear() -> void:
	for sample:Dictionary in samples: _retire(sample)
	samples.clear()

func _exit_tree() -> void:
	clear()
