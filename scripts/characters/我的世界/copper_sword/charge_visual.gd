extends "res://scripts/effects/我的世界/trident_charge_visual.gd"
## Copper-sword pose adapter only. Glint shader, vanilla glint texture,
## rerouting electric arcs and their draw implementation are inherited unchanged.
var unit:Node2D
func _ready() -> void:
	set_as_top_level(true)
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = hash(str(unit.get_path())+":copper")
	overlay = Sprite2D.new()
	overlay.name = "NativeEnchantment"
	glint_material = ShaderMaterial.new()
	glint_material.shader = GLINT
	glint_material.set_shader_parameter("native_glint",NATIVE_GLINT)
	overlay.material = glint_material
	add_child(overlay)
	# The native blade diagonal, excluding the wooden grip. Same trident arc generator.
	_path = PackedVector2Array()
	for i:int in range(14): _path.append(Vector2(-2.0,2.0).lerp(Vector2(6.5,-6.5),float(i)/13.0))
	visible = false
func _process(delta:float) -> void:
	if not is_instance_valid(unit):
		queue_free()
		return
	advance(delta if unit.is_combat_runtime_active() else 0.0)
func advance(delta:float) -> void:
	visible = is_instance_valid(unit) and unit.health>0 and unit.charged_left>0.0 and unit.image.visible
	if not visible: return
	global_transform = unit.image.global_transform
	# The body mirrors in its shader. Mirror this separate alpha mask exactly once.
	if unit.is_character_visual_flipped_h():
		var pose:Transform2D = global_transform
		pose.x = -pose.x
		global_transform = pose
	z_index = unit.image.z_index+1
	overlay.texture = unit.image.texture
	overlay.offset = unit.image.offset
	overlay.scale = Vector2.ONE
	_world_scale = maxf(global_transform.x.length(),0.01)
	glint_material.set_shader_parameter("world_texel",_world_scale)
	glint_material.set_shader_parameter("glint_time",unit._view_clock)
	_reroute_left -= maxf(delta,0.0)
	if _reroute_left<=0.0:
		_reroute_left = _rng.randf_range(0.045,0.095)
		_rebuild_arcs()
	queue_redraw()
