extends Node3D
## A real six-sided, three-layer cube in a SubViewport, not seven flat sprites.
## The Mojang Java 26.2 18x18 outer and 16x16 inner UV crosses are sampled
## directly, with the original block textures on a separate central Box.

const OUTER:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/sulfur_cube_outer.png")
const INNER:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/sulfur_cube_inner.png")
const OAK_TOP:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/oak_log_top.png")
const TNT_TOP:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/tnt_top.png")
const TNT_BOTTOM:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/tnt_bottom.png")
const SHELL_SHADER:Shader = preload("res://shaders/sulfur_cube_shell.gdshader")
const BLOCK_TEXTURES:Array[Texture2D] = [
	null,
	preload("res://Images/characters/我的世界/sulfur_cube/source/oak_log.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/blue_ice.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/magma.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/honeycomb_block.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/iron_block.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/tnt_side.png"),
]
const OUTER_SIZE:float = 2.0
const INNER_SIZE:float = 2.0*16.0/18.0
const BLOCK_SIZE:float = 2.0*16.0/18.0 # Vanilla: full 16px block within the 18px outer model.
const FACE_NORMALS:Array[Vector3] = [Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT,Vector3.UP,Vector3.DOWN]
const FACE_ROTATIONS:Array[Vector3] = [Vector3.ZERO,Vector3(0,PI/2,0),Vector3(0,PI,0),Vector3(0,-PI/2,0),Vector3(-PI/2,0,0),Vector3(PI/2,0,0)]
# front, right, back, left, top, bottom from Mojang's two UV crosses.
const OUTER_UV:Array[Vector2i] = [Vector2i(18,18),Vector2i(36,18),Vector2i(54,18),Vector2i(0,18),Vector2i(18,0),Vector2i(36,0)]
const INNER_UV:Array[Vector2i] = [Vector2i(16,52),Vector2i(32,52),Vector2i(48,52),Vector2i(0,52),Vector2i(16,36),Vector2i(32,36)]

var outer_shell:Node3D
var inner_shell:Node3D
var inner_block:Node3D
var block_mode:int = 0
var _swap_left:float = 0.0
var _magma_materials:Array[StandardMaterial3D] = []
var _block_initialized:bool = false

func _ready() -> void:
	outer_shell = Node3D.new()
	outer_shell.name = "NativeOuterShell"
	add_child(outer_shell)
	inner_shell = Node3D.new()
	inner_shell.name = "NativeInnerGel"
	add_child(inner_shell)
	inner_block = Node3D.new()
	inner_block.name = "InterchangeableBlock"
	add_child(inner_block)
	for face:int in range(6):
		# Match SulfurCubeRenderer: the translucent 18px outside is ALWAYS drawn;
		# its 16px inner jelly is rendered ONLY when no block is absorbed.
		make_face(outer_shell,OUTER_SIZE,face,_shell_material(OUTER,OUTER_UV[face],18))
		make_face(inner_shell,INNER_SIZE,face,_shell_material(INNER,INNER_UV[face],16))
	set_block(block_mode)

func _shell_material(texture:Texture2D,origin:Vector2i,texels:int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHELL_SHADER
	# Translucent inner gel must submit BEFORE the outer face: otherwise its
	# opaque white pixels erase the original eyes and mouth on an empty cube.
	material.render_priority = 1 if texture == OUTER else -1
	material.set_shader_parameter("native_atlas",texture)
	material.set_shader_parameter("atlas_origin",Vector2(origin)/128.0)
	material.set_shader_parameter("atlas_span",Vector2.ONE*float(texels)/128.0)
	return material

func make_face(parent:Node3D,side:float,face:int,material:Material) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*side
	var plane := MeshInstance3D.new()
	plane.name = "Face%d" % face
	plane.mesh = quad
	plane.material_override = material
	parent.add_child(plane)
	plane.position = FACE_NORMALS[face]*side*0.5
	plane.rotation = FACE_ROTATIONS[face]
	return plane

func set_block(mode:int) -> void:
	mode = clampi(mode,0,BLOCK_TEXTURES.size()-1)
	if _block_initialized and mode == block_mode: return
	block_mode = mode
	if inner_block == null: return
	_block_initialized = true
	for child:Node in inner_block.get_children():
		inner_block.remove_child(child)
		child.queue_free()
	_magma_materials.clear()
	inner_block.visible = block_mode > 0
	inner_shell.visible = block_mode == 0
	if block_mode == 0: return
	for face:int in range(6):
		var texture:Texture2D = BLOCK_TEXTURES[block_mode]
		if block_mode == 1 and face in [4,5]: texture = OAK_TOP
		elif block_mode == 6 and face == 4: texture = TNT_TOP
		elif block_mode == 6 and face == 5: texture = TNT_BOTTOM
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color.WHITE if face in [0,4] else Color(0.86,0.86,0.86)
		if block_mode == 3:
			mat.uv1_scale = Vector3(1,1.0/3.0,1) # three original magma animation frames
			_magma_materials.append(mat)
		make_face(inner_block,BLOCK_SIZE,face,mat)
	_swap_left = 0.24
	inner_block.scale = Vector3.ONE*0.3

func animate(time:float,delta:float,playing:bool,fuse_left:float) -> void:
	if outer_shell == null: return
	# Minecraft AbstractCubeMobRenderer stretches vertically and contracts X/Z
	# by the reciprocal factor. The outer shell and its contents deform TOGETHER.
	var squish:float = 0.105*sin(time*TAU*1.15) if playing else 0.0
	var vertical:float = 1.0+squish
	var body_scale := Vector3(1.0/vertical,vertical,1.0/vertical)
	outer_shell.scale = body_scale
	inner_shell.scale = body_scale
	if block_mode == 0: return
	if playing: _swap_left = maxf(_swap_left-delta,0.0)
	var appear:float = 1.0-_swap_left/0.24
	inner_block.scale = body_scale*lerpf(0.3,1.0,1.0-pow(1.0-appear,3.0))
	if block_mode == 3:
		var frame:int = int(time*6.0)%3
		for material:StandardMaterial3D in _magma_materials:
			material.uv1_offset = Vector3(0,float(frame)/3.0,0)
	if block_mode == 6 and fuse_left > 0.0:
		inner_block.scale *= 1.0+0.035*absf(sin(time*TAU*2.5))
