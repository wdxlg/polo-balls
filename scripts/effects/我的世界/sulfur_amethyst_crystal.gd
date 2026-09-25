extends Node3D
## One original amethyst-cluster cross model, shared by the attached crystal and
## its projectile. No cone, item-icon substitution, generated image or repaint.
const TEXTURE:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/amethyst_cluster.png")
var length:float = 1.6
var width:float = 0.82

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = TEXTURE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i:int in range(2):
		var quad := QuadMesh.new()
		quad.size = Vector2(width,length)
		var face := MeshInstance3D.new()
		face.name = "NativeClusterCross%d" % i
		face.mesh = quad
		face.material_override = material
		face.position.y = length*0.5 # Bottom is the buried root, not the midpoint.
		face.rotation.y = PI*0.25+float(i)*PI*0.5
		add_child(face)
