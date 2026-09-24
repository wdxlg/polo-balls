extends Node2D
## Native Minecraft ice enclosure. Visual only: no collider, root transform or stun mutation.
const ICE:Texture2D = preload("res://Images/characters/我的世界/snow_golem/ice.png")
const CRACKS:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_0.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_1.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_2.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_3.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_4.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_5.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_6.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_7.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_8.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_9.png")]
const SHAKE_PARAMETER:StringName = &"snow_freeze_offset"
const MAX_SHAKE:float = 1.8
var cold:Node
var target:ball
var enclosed:bool = false
var progress:float = 0.0
var world_bounds:Rect2
var shake_world:Vector2 = Vector2.ZERO
var fragments:Array[Dictionary] = []
var breakout_count:int = 0
var _visual:Node2D
var _shader_id:int = -1
var _mode:int = 0 # 1 shader; 2 Sprite offset; 3 non-physics visual position
var _last_local:Vector2 = Vector2.ZERO
var _last_applied:Vector2 = Vector2.ZERO
var _fallback_applied:bool = false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	top_level = true
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("MCSnowIce")
	_rng.randomize()
	hide()
	set_process(false)

func begin(status:Node) -> void:
	cold = status
	target = status.target
	fragments.clear()
	enclosed = true
	progress = 0.0
	show()
	set_process(true)
	refresh()

func shake_strength(value:float) -> float:
	return lerpf(0.12,MAX_SHAKE,pow(clampf(value,0.0,1.0),1.65))

func sample_shake(value:float,total:float) -> Vector2:
	var p:float = clampf(value,0.0,1.0)
	var elapsed:float = p*maxf(total,0.05)
	# Continuous phase: 5 Hz at first, accelerating to 21 Hz near escape.
	var phase:float = TAU*(5.0*elapsed+8.0*elapsed*elapsed/maxf(total,0.05))
	var x:float = sin(phase)*0.76+sin(phase*1.73+0.6)*0.24
	var y:float = sin(phase*1.37+1.1)*0.7+sin(phase*2.11)*0.3
	return Vector2(x,y*0.42)*shake_strength(p)

func crack_stage() -> int:
	if not enclosed or progress < 0.35: return -1
	return clampi(int((progress-0.35)/0.65*10.0),0,9)

func _valid_target() -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_inside_tree() and target.health > 0

func _bind_visual() -> void:
	var next:Node2D = target.image if is_instance_valid(target.image) else null
	var shader:Shader = next.material.shader if is_instance_valid(next) and next.material is ShaderMaterial else null
	var shader_id:int = shader.get_instance_id() if shader != null else 0
	if _visual == next and _shader_id == shader_id: return
	_restore_visual()
	_visual = next
	_shader_id = shader_id
	_mode = 0
	# Shader.get_shader_uniform_list() lists material uniforms, not canvas-item
	# instance uniforms. Detect this opt-in channel in the shader source.
	if shader != null and "instance uniform vec2 snow_freeze_offset" in shader.code:
		_mode = 1
	if _mode == 0 and is_instance_valid(_visual):
		if _visual is Sprite2D or _visual is AnimatedSprite2D: _mode = 2
		elif _visual != target and _visual != target.graphics and not _visual is CollisionObject2D: _mode = 3

func _remove_fallback() -> void:
	if not _fallback_applied or not is_instance_valid(_visual): return
	var now:Vector2 = _visual.get("offset") if _mode == 2 else _visual.position
	# An animation can replace its own offset while frozen. Do not overwrite it.
	if now.is_equal_approx(_last_applied):
		if _mode == 2: _visual.set("offset",now-_last_local)
		elif _mode == 3: _visual.position = now-_last_local
	_fallback_applied = false
	_last_local = Vector2.ZERO

func _restore_visual() -> void:
	if is_instance_valid(_visual):
		if _mode == 1: _visual.set_instance_shader_parameter(SHAKE_PARAMETER,Vector2.ZERO)
		else: _remove_fallback()
	_last_local = Vector2.ZERO
	_fallback_applied = false

func _apply_shake(offset:Vector2) -> void:
	if not is_instance_valid(_visual): return
	var transform:Transform2D = _visual.global_transform
	if _mode == 3 and _visual.get_parent() is Node2D: transform = (_visual.get_parent() as Node2D).global_transform
	if absf(transform.determinant()) <= 0.000001: return
	var local:Vector2 = transform.affine_inverse().basis_xform(offset)
	if _mode == 1:
		if not local.is_equal_approx(_last_local): _visual.set_instance_shader_parameter(SHAKE_PARAMETER,local)
		_last_local = local
	elif _mode in [2,3]:
		var base:Vector2 = _visual.get("offset") if _mode == 2 else _visual.position
		_last_local = local
		_last_applied = base+local
		if _mode == 2: _visual.set("offset",_last_applied)
		else: _visual.position = _last_applied
		_fallback_applied = true

func _body_rect() -> Rect2:
	var radius:float = maxf(target.get_crowd_separation_radius_world(),6.0)
	var fallback := Rect2(target.global_position-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
	if not is_instance_valid(_visual): return fallback
	var rect:Rect2 = target._get_source_visual_rect()
	var texture:Texture2D = target._get_source_after_image_texture()
	var region := Vector4(0.0,0.0,1.0,1.0)
	if _visual is Sprite2D:
		var sprite := _visual as Sprite2D
		if sprite.region_enabled and texture != null:
			var ts:Vector2 = texture.get_size()
			region = Vector4(sprite.region_rect.position.x/ts.x,sprite.region_rect.position.y/ts.y,sprite.region_rect.size.x/ts.x,sprite.region_rect.size.y/ts.y)
		elif sprite.hframes > 1 or sprite.vframes > 1:
			region = Vector4(float(sprite.frame%sprite.hframes)/sprite.hframes,float(int(sprite.frame/sprite.hframes))/sprite.vframes,1.0/sprite.hframes,1.0/sprite.vframes)
	elif _visual is AnimatedSprite2D and texture != null:
		var animated := _visual as AnimatedSprite2D
		var size:Vector2 = texture.get_size()
		rect = Rect2(animated.offset-(size*0.5 if animated.centered else Vector2.ZERO),size)
	if texture != null and region.z > 0.0001 and region.w > 0.0001:
		# Reuse the existing alpha-bounds cache (also handles AtlasTexture frames).
		var used:Rect2 = target._get_after_image_visible_uv_rect(texture,region)
		var uv_min := Vector2((used.position.x-region.x)/region.z,(used.position.y-region.y)/region.w)
		var uv_size := Vector2(used.size.x/region.z,used.size.y/region.w)
		if target.is_character_visual_flipped_h(): uv_min.x = 1.0-uv_min.x-uv_size.x
		rect = Rect2(rect.position+uv_min*rect.size,rect.size*uv_size)
	var xform:Transform2D = _visual.global_transform
	var first:Vector2 = xform*rect.position
	var bounds := Rect2(first,Vector2.ZERO)
	for corner:Vector2 in [rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]: bounds = bounds.expand(xform*corner)
	if not bounds.size.is_finite() or bounds.size.x <= 0.01 or bounds.size.y <= 0.01: return fallback
	return bounds

func refresh() -> void:
	if not enclosed or not _valid_target() or not is_instance_valid(cold): return
	_bind_visual()
	_remove_fallback()
	var total:float = maxf(float(cold.freeze_total),0.05)
	progress = clampf(1.0-float(cold.frozen_left)/total,0.0,1.0)
	shake_world = sample_shake(progress,total)
	global_position = target.global_position
	world_bounds = _body_rect().grow(2.2)
	var size:Vector2 = Vector2(maxf(world_bounds.size.x,12.0),maxf(world_bounds.size.y,16.0))
	world_bounds = Rect2(world_bounds.get_center()-size*0.5,size)
	# Above the victim, but never repurpose its physical root or ordinary stun jitter.
	var visual_z:int = 0
	var item:CanvasItem = _visual
	while is_instance_valid(item):
		visual_z += item.z_index
		if not item.z_as_relative or not item.get_parent() is CanvasItem: break
		item = item.get_parent() as CanvasItem
	z_index = clampi(maxi(visual_z+1,1),-4096,4096)
	_apply_shake(shake_world)
	queue_redraw()

func finish(shatter:bool = true) -> void:
	var was_enclosed:bool = enclosed
	enclosed = false
	_restore_visual()
	shake_world = Vector2.ZERO
	if shatter and was_enclosed and _valid_target():
		breakout_count += 1
		var center:Vector2 = world_bounds.get_center()
		for index:int in range(10):
			var angle:float = TAU*float(index)/10.0
			var speed:float = _rng.randf_range(22.0,44.0)
			fragments.append({"point":center+Vector2(cos(angle)*world_bounds.size.x*0.45,sin(angle)*world_bounds.size.y*0.4),"velocity":Vector2(cos(angle)*speed,sin(angle)*speed-15.0),"age":0.0,"life":0.34,"size":_rng.randf_range(2.8,5.0),"angle":angle,"spin":_rng.randf_range(-5.0,5.0),"region":Rect2(Vector2(_rng.randi_range(0,12),_rng.randi_range(0,12)),Vector2(4,4))})
	else: fragments.clear()
	set_process(not fragments.is_empty())
	visible = not fragments.is_empty()
	queue_redraw()

func _process(delta:float) -> void:
	if not _valid_target():
		finish(false)
		return
	if not target.is_combat_runtime_active(): return
	if enclosed:
		if not is_instance_valid(cold) or cold.frozen_left <= 0.0: finish(true)
		else: refresh()
	for i:int in range(fragments.size()-1,-1,-1):
		var part:Dictionary = fragments[i]
		part.age = float(part.age)+delta
		if float(part.age) >= float(part.life): fragments.remove_at(i)
		else:
			part.velocity.y += 65.0*delta
			part.point += part.velocity*delta
			part.angle += float(part.spin)*delta
	if not enclosed and fragments.is_empty():
		hide()
		set_process(false)
	queue_redraw()

func _face(points:PackedVector2Array,texture:Texture2D,tint:Color) -> void:
	draw_polygon(points,PackedColorArray([tint,tint,tint,tint]),PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]),texture)

func _draw() -> void:
	if enclosed:
		var rect := Rect2(world_bounds.position-global_position+shake_world*0.65,world_bounds.size)
		var depth:float = clampf(minf(rect.size.x,rect.size.y)*0.23,3.0,9.0)
		var d := Vector2(depth,-depth*0.6)
		var tl:Vector2 = rect.position
		var tr:Vector2 = rect.position+Vector2(rect.size.x,0)
		var br:Vector2 = rect.end
		var bl:Vector2 = rect.position+Vector2(0,rect.size.y)
		var top := PackedVector2Array([tl+d,tr+d,tr,tl])
		var side := PackedVector2Array([tr,tr+d,br+d,br])
		_face(top,ICE,Color(1.0,1.0,1.0,0.9))
		_face(side,ICE,Color(0.82,0.89,1.0,0.82))
		draw_texture_rect(ICE,rect,false,Color(1.0,1.0,1.0,0.64))
		var stage:int = crack_stage()
		if stage >= 0:
			draw_texture_rect(CRACKS[stage],rect,false,Color(1,1,1,0.66))
			_face(top,CRACKS[stage],Color(1,1,1,0.45))
			_face(side,CRACKS[stage],Color(1,1,1,0.5))
		draw_polyline(PackedVector2Array([tl,tl+d,tr+d,br+d,br,bl,tl,tr,br]),Color(0.66,0.82,1.0,0.6),0.65)
		draw_line(tr,tr+d,Color(0.77,0.9,1.0,0.6),0.65)
	for part:Dictionary in fragments:
		var opacity:float = 1.0-float(part.age)/float(part.life)
		var size:float = float(part.size)
		draw_set_transform(to_local(part.point),float(part.angle))
		draw_texture_rect_region(ICE,Rect2(Vector2(-size,-size)*0.5,Vector2.ONE*size),part.region,Color(1,1,1,opacity))
		draw_set_transform(Vector2.ZERO)

func _exit_tree() -> void:
	_restore_visual()
