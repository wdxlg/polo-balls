extends Node3D
## A real six-sided, three-layer cube in a SubViewport, not seven flat sprites.
## The Mojang Java 26.2 18x18 outer and 16x16 inner UV crosses are sampled
## directly, with the original block textures on a separate central Box.

const OUTER:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/sulfur_cube_outer.png")
const INNER:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/sulfur_cube_inner.png")
const CRYSTAL = preload("res://scripts/effects/我的世界/sulfur_amethyst_crystal.gd")
const AMETHYST_CLUSTER:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/amethyst_cluster.png")
const TNT_TOP:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/tnt_top.png")
const TNT_BOTTOM:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/tnt_bottom.png")
const SHELL_SHADER:Shader = preload("res://shaders/sulfur_cube_shell.gdshader")
const BLOCK_TEXTURES:Array[Texture2D] = [
	null,
	preload("res://Images/characters/我的世界/sulfur_cube/source/blue_ice.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/magma.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/honeycomb_block.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/iron_block.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/tnt_side.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/source/amethyst_block.png"),
]
const OUTER_SIZE:float = 2.0
const INNER_SIZE:float = 2.0*16.0/18.0
const BLOCK_SIZE:float = 2.0*16.0/18.0 # Vanilla: full 16px block within the 18px outer model.
# Each cluster starts *inside* the amethyst block and pierces the jelly shell.
# The tips lean outwards and slightly towards the camera rather than standing
# upright on four flat cards in front of the creature.
const CRYSTAL_ROOTS:Array[Vector3] = [Vector3(-0.20,0.45,0.45),Vector3(0.45,-0.12,0.38),Vector3(0.20,-0.45,0.40),Vector3(-0.45,0.10,0.40)]
const CRYSTAL_TIPS:Array[Vector3] = [Vector3(-0.35,1.75,1.10),Vector3(1.85,0.12,1.20),Vector3(0.50,-1.60,1.35),Vector3(-1.65,-0.25,1.15)]
const FACE_NORMALS:Array[Vector3] = [Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT,Vector3.UP,Vector3.DOWN]
const FACE_ROTATIONS:Array[Vector3] = [Vector3.ZERO,Vector3(0,PI/2,0),Vector3(0,PI,0),Vector3(0,-PI/2,0),Vector3(-PI/2,0,0),Vector3(PI/2,0,0)]
# front, right, back, left, top, bottom from Mojang's two UV crosses.
const OUTER_UV:Array[Vector2i] = [Vector2i(18,18),Vector2i(36,18),Vector2i(54,18),Vector2i(0,18),Vector2i(18,0),Vector2i(36,0)]
const INNER_UV:Array[Vector2i] = [Vector2i(16,52),Vector2i(32,52),Vector2i(48,52),Vector2i(0,52),Vector2i(16,36),Vector2i(32,36)]

var outer_shell:Node3D
var inner_shell:Node3D
var crystal_layer:Node3D
var inner_block:Node3D
var block_mode:int = 0
var _swap_left:float = 0.0
var _magma_materials:Array[StandardMaterial3D] = []
var _block_initialized:bool = false
var _crystals_active:bool = true
var _crystal_grow_left:float = 0.0

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
	crystal_layer = Node3D.new()
	crystal_layer.name = "NativeAmethystCrystals"
	add_child(crystal_layer)
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
	for crystal:Node in crystal_layer.get_children():
		crystal_layer.remove_child(crystal)
		crystal.queue_free()
	inner_block.visible = block_mode > 0
	inner_shell.visible = block_mode == 0
	if block_mode == 0: return
	for face:int in range(6):
		var texture:Texture2D = BLOCK_TEXTURES[block_mode]
		if block_mode == 5 and face == 4: texture = TNT_TOP
		elif block_mode == 5 and face == 5: texture = TNT_BOTTOM
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color.WHITE if face in [0,4] else Color(0.86,0.86,0.86)
		if block_mode == 2:
			mat.uv1_scale = Vector3(1,1.0/3.0,1) # three original magma animation frames
			_magma_materials.append(mat)
		make_face(inner_block,BLOCK_SIZE,face,mat)
	if block_mode == 6: _make_crystals()
	crystal_layer.visible = block_mode == 6 and _crystals_active
	_swap_left = 0.24
	inner_block.scale = Vector3.ONE*0.3
	crystal_layer.scale = Vector3.ONE*0.3

func animate(time:float,delta:float,playing:bool,fuse_left:float) -> void:
	if outer_shell == null: return
	# Minecraft AbstractCubeMobRenderer stretches vertically and contracts X/Z
	# by the reciprocal factor. The outer shell and its contents deform TOGETHER.
	var squish:float = 0.105*sin(time*TAU*1.15) if playing else 0.0
	var vertical:float = 1.0+squish
	var body_scale := Vector3(1.0/vertical,vertical,1.0/vertical)
	outer_shell.scale = body_scale
	inner_shell.scale = body_scale
	crystal_layer.scale = body_scale
	if block_mode == 0: return
	if playing: _swap_left = maxf(_swap_left-delta,0.0)
	var appear:float = 1.0-_swap_left/0.24
	var insert_scale:float = lerpf(0.3,1.0,1.0-pow(1.0-appear,3.0))
	inner_block.scale = body_scale*insert_scale
	if playing: _crystal_grow_left = maxf(_crystal_grow_left-delta,0.0)
	var growth:float = 1.0-_crystal_grow_left/0.24
	crystal_layer.scale = body_scale*minf(insert_scale,lerpf(0.3,1.0,growth))
	if block_mode == 2:
		var frame:int = int(time*6.0)%3
		for material:StandardMaterial3D in _magma_materials:
			material.uv1_offset = Vector3(0,float(frame)/3.0,0)
	if block_mode == 5 and fuse_left > 0.0:
		inner_block.scale *= 1.0+0.035*absf(sin(time*TAU*2.5))
func set_crystals_active(active:bool) -> void:
	if active and not _crystals_active: _crystal_grow_left = 0.24
	_crystals_active = active
	if crystal_layer != null: crystal_layer.visible = block_mode == 6 and active

func crystals_ready() -> bool:
	return _crystals_active and _swap_left <= 0.0 and _crystal_grow_left <= 0.0

func _make_crystals() -> void:
	for i:int in range(CRYSTAL_TIPS.size()):
		var root:Vector3 = CRYSTAL_ROOTS[i]
		var tip:Vector3 = CRYSTAL_TIPS[i]
		var crystal:Node3D = CRYSTAL.new()
		crystal.name = "PiercingCrystal%d" % i
		crystal.length = root.distance_to(tip)
		crystal.position = root
		crystal.quaternion = Quaternion(Vector3.UP,(tip-root).normalized())
		crystal_layer.add_child(crystal)

func crystal_render_state(index:int) -> Dictionary:
	var crystal:Node3D = crystal_layer.get_child(index) as Node3D
	return {"transform":crystal.global_transform,"length":crystal.length,"width":crystal.width}

func crystal_tip_world(index:int) -> Vector3:
	if crystal_layer == null or index < 0 or index >= CRYSTAL_TIPS.size(): return global_position
	return crystal_layer.to_global(CRYSTAL_TIPS[index])
