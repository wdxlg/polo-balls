extends Node2D
## One scene-owned field. Rendering and detection share the same radius/cone/LOS.
const MASK = preload("res://scripts/characters/我的世界/fog_man/mask.gd")
const SHADER = preload("res://shaders/mc_fog.gdshader")
const NEAR:float = 32.0
const REACH:float = 180.0
const HALF_WIDTH:float = 90.0
var viewers:Array[Dictionary] = []
var headings:Dictionary = {}
var bounds:Rect2 = Rect2(-1000,-1000,2000,2000)
var fog_alpha:float = 0.0
var elapsed:float = 0.0
var refresh_left:float = 0.0
var mask_view:SubViewport
var mask_node:Node2D
var veil:Polygon2D
var cloud_material:ShaderMaterial
var clouds:Dictionary = {}
var storms:Array[Dictionary] = []
var cloud_textures:Array[Texture2D] = []
var render_bounds:Rect2
const MEMORY_SIZE:int = 192
const CLOUD_STEP:float = 100.0
var reveal_memory:PackedFloat32Array = PackedFloat32Array()
var reveal_image:Image
var reveal_texture:ImageTexture
var mask_material:ShaderMaterial
static func ensure(actor:Node2D) -> Node2D:
	var world:Node = actor.get_tree().current_scene
	var found:Node = world.get_node_or_null("MCFogField")
	if is_instance_valid(found): return found
	var manager:Node2D = load("res://scripts/characters/我的世界/fog_man/field.gd").new()
	manager.name = "MCFogField"
	world.add_child(manager)
	return manager
func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = 90
	add_to_group("BattleTransient")
	add_to_group("MCFogField")
	mask_view = SubViewport.new()
	mask_view.size = Vector2i(768,768)
	mask_view.transparent_bg = true
	mask_view.disable_3d = true
	mask_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mask_view)
	mask_node = MASK.new()
	mask_view.add_child(mask_node)
	reveal_memory.resize(MEMORY_SIZE*MEMORY_SIZE)
	reveal_memory.fill(0.0)
	reveal_image = Image.create(MEMORY_SIZE,MEMORY_SIZE,false,Image.FORMAT_RGBA8)
	reveal_image.fill(Color(0,0,0,0))
	reveal_texture = ImageTexture.create_from_image(reveal_image)
	veil = Polygon2D.new()
	veil.visible = false # Compatibility handle only. No solid/background fog surface.
	mask_material = ShaderMaterial.new()
	mask_material.shader = SHADER
	mask_material.set_shader_parameter("reveal_mask",reveal_texture)
	mask_material.set_shader_parameter("mask_texel",Vector2.ONE/float(MEMORY_SIZE))
	veil.material = mask_material
	add_child(veil)
	cloud_material = mask_material.duplicate()
	cloud_material.set_shader_parameter("cloud_layer",true)
	for i:int in range(4):
		cloud_textures.append(load("res://Images/characters/我的世界/fog_man/cloud_%d.png" % i))
func owners() -> Array[Node]:
	var result:Array[Node] = []
	for actor:Node in get_tree().get_nodes_in_group("MCFogMan"):
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.health > 0: result.append(actor)
	return result
func _process(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	var living:Array[Node] = owners()
	if not living.is_empty() and not living[0].is_combat_runtime_active(): return
	elapsed += delta
	advance_storms(delta)
	fog_alpha = move_toward(fog_alpha,0.985 if not living.is_empty() else 0.0,delta*0.7)
	mask_material.set_shader_parameter("opacity",fog_alpha)
	mask_material.set_shader_parameter("fog_time",elapsed)
	cloud_material.set_shader_parameter("opacity",fog_alpha)
	cloud_material.set_shader_parameter("fog_time",elapsed)
	for key:Vector2i in clouds:
		var sprite:Sprite2D = clouds[key]
		var phase:float = float(key.x*13+key.y*7)
		sprite.position = Vector2(key)*CLOUD_STEP+Vector2(sin(elapsed*0.13+phase)*40.0,cos(elapsed*0.09+phase)*32.0)
		sprite.scale = Vector2(4.8,3.8)*(1.0+0.10*sin(elapsed*0.21+phase))
		sprite.rotation = sin(elapsed*0.06+phase)*0.18
		var offset:Vector2 = sprite.get_meta("avoid_offset",Vector2.ZERO)
		var target_offset:Vector2 = sprite.get_meta("avoid_target",Vector2.ZERO)
		var storm_offset:Vector2 = storm_push(Vector2(key)*CLOUD_STEP)
		if storm_offset.length()>target_offset.length(): target_offset = storm_offset
		var response:float = 0.85 if target_offset.length()>offset.length() else 2.5
		if not storms.is_empty(): response = 0.22 if storm_offset.length()>offset.length() else 0.65
		offset = offset.lerp(target_offset,1.0-exp(-delta/response))
		sprite.set_meta("avoid_offset",offset)
		sprite.position += offset
	if living.is_empty() and fog_alpha <= 0.0:
		queue_free()
		return
	refresh_left -= delta
	if refresh_left <= 0.0:
		refresh_left = 0.10
		refresh_viewers()
		rebuild_mask(living)
		update_mist_memory(0.10)
func refresh_viewers() -> void:
	viewers.clear()
	var alive:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or node.health <= 0 or node.Type != ball.Ball_Type.Ball or node.is_in_group("MCFogMan"): continue
		var id:int = node.get_instance_id()
		alive[id] = true
		var heading:Vector2 = node.velocity
		if heading.length_squared() <= 1.0:
			heading = node.player_control_direction if node.is_player_controlled() else Vector2.ZERO
		if heading.length_squared() > 0.01: headings[id] = heading.normalized()
		elif not headings.has(id):
			headings[id] = Vector2.RIGHT if node._visual_facing_flipped_h == node.dir_left else Vector2.LEFT
		viewers.append({"unit":weakref(node),"point":node.global_position,"heading":headings[id]})
	for id:Variant in headings.keys():
		if not alive.has(id): headings.erase(id)
func heading_for(unit:Node2D) -> Vector2:
	for entry:Dictionary in viewers:
		if entry.unit.get_ref() == unit: return entry.heading
	return Vector2.RIGHT if unit._visual_facing_flipped_h == unit.dir_left else Vector2.LEFT
static func in_view_shape(point:Vector2,origin:Vector2,heading:Vector2) -> bool:
	var rel:Vector2 = point-origin
	if rel.length_squared() <= NEAR*NEAR: return true
	var forward:float = rel.dot(heading)
	return forward >= 0.0 and forward <= REACH and absf(rel.cross(heading)) <= HALF_WIDTH*forward/REACH
func line_visible(origin:Vector2,point:Vector2,observer:Node2D = null) -> bool:
	if origin.distance_squared_to(point)<0.01: return true
	var excluded:Array[RID] = []
	if observer is CollisionObject2D: excluded.append(observer.get_rid())
	var ray := PhysicsRayQueryParameters2D.create(origin,point,1,excluded)
	ray.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()
func seen_by(entry:Dictionary,point:Vector2) -> bool:
	var unit:Variant = entry.unit.get_ref()
	return is_instance_valid(unit) and in_view_shape(point,entry.point,entry.heading) and line_visible(entry.point,point,unit)
func enemy_viewers(actor:ball) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	for entry:Dictionary in viewers:
		var unit:Variant = entry.unit.get_ref()
		if is_instance_valid(unit) and unit.health>0 and (Game.Game_Settings.Have_Team_Damage or actor.Team.is_empty() or unit.Team!=actor.Team): result.append(entry)
	return result
func body_exposure(actor:ball,point:Vector2) -> float:
	var best:float = 0.0
	var basis:Transform2D = actor.image.global_transform
	basis.origin += point-actor.global_position
	for entry:Dictionary in enemy_viewers(actor):
		var count:int = 0
		for x:float in [-11.0,0.0,11.0]:
			for y:float in [-35.0,10.0,60.0]:
				if seen_by(entry,basis*(Vector2(x,y)+actor.image.offset)): count += 1
		best = maxf(best,float(count)/9.0)
	return best
func risk(_actor:ball,point:Vector2) -> float:
	# Avoid every thin-fog hole, including allies' sight and another man's thunder.
	var result:float = 2.0 if clear_at(point) else 0.0
	for entry:Dictionary in viewers:
		if seen_by(entry,point): result += 1.0
	return result
func clear_at(point:Vector2) -> bool:
	for actor:Node in owners():
		if actor.phase == actor.Phase.RAGE and not actor.lightning_wait and point.distance_to(actor.rage_origin) <= storm_edge(actor.rage_origin,actor.clear_radius,(point-actor.rage_origin).angle()): return true
	return false
func arena_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world.has_method("return_map_world_rect"):
		var maps:Variant = world.get("map_group")
		var key:Variant = world.get("now_choose_map")
		if maps is Dictionary and maps.has(key):
			var rect:Rect2 = world.call("return_map_world_rect",maps[key])
			if rect.has_area(): return rect
	return Rect2(-1000,-1000,2000,2000)
func clipped_tip(origin:Vector2,tip:Vector2,unit:Node2D) -> Vector2:
	var exclude:Array[RID] = []
	if unit is CollisionObject2D: exclude.append(unit.get_rid())
	var ray := PhysicsRayQueryParameters2D.create(origin,tip,1,exclude)
	ray.hit_from_inside = true
	var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(ray)
	return hit.position if not hit.is_empty() else tip
func push_polygon(points:PackedVector2Array,alpha:float) -> void:
	var mapped := PackedVector2Array()
	for point:Vector2 in points: mapped.append((point-bounds.position)/bounds.size*Vector2(mask_view.size))
	mask_node.polygons.append(mapped)
	mask_node.colors.append(Color(1,1,1,alpha))
func rebuild_mask(living:Array[Node]) -> void:
	bounds = arena_rect().grow(260.0)
	# Mask coordinates are WORLD coordinates, not Polygon2D's texture-pixel UVs.
	# Rendering follows the camera beyond the arena; no map rectangle clips the mist.
	var inverse:Transform2D = get_canvas_transform().affine_inverse()
	var screen:Rect2 = get_viewport_rect()
	render_bounds = Rect2(inverse*screen.position,Vector2.ZERO)
	for corner:Vector2 in [Vector2(screen.end.x,screen.position.y),screen.end,Vector2(screen.position.x,screen.end.y)]:
		render_bounds = render_bounds.expand(inverse*corner)
	render_bounds = render_bounds.grow(380.0)
	veil.polygon = PackedVector2Array([render_bounds.position,Vector2(render_bounds.end.x,render_bounds.position.y),render_bounds.end,Vector2(render_bounds.position.x,render_bounds.end.y)])
	sync_clouds()
	veil.uv = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	for material:ShaderMaterial in [mask_material,cloud_material]:
		material.set_shader_parameter("mask_origin",bounds.position)
		material.set_shader_parameter("world_size",bounds.size)
	mask_node.polygons.clear()
	mask_node.colors.clear()
	for entry:Dictionary in viewers:
		var unit:Variant = entry.unit.get_ref()
		if not is_instance_valid(unit): continue
		var circle := PackedVector2Array()
		for i:int in range(32):
			circle.append(clipped_tip(entry.point,entry.point+Vector2.RIGHT.rotated(TAU*i/32.0)*NEAR,unit))
		push_polygon(circle,0.78)
		var cone := PackedVector2Array([entry.point])
		var perpendicular:Vector2 = entry.heading.orthogonal()
		for i:int in range(17):
			var tip:Vector2 = entry.point+entry.heading*REACH+perpendicular*lerpf(-HALF_WIDTH,HALF_WIDTH,float(i)/16.0)
			cone.append(clipped_tip(entry.point,tip,unit))
		push_polygon(cone,0.78)
	for actor:Node in living:
		if actor.phase == actor.Phase.RAGE and not actor.lightning_wait: thunder_clear(actor)
	mask_node.queue_redraw()

func sync_clouds() -> void:
	var active:Dictionary = {}
	var first:Vector2i = Vector2i((render_bounds.position/CLOUD_STEP).floor())
	var last:Vector2i = Vector2i((render_bounds.end/CLOUD_STEP).ceil())
	for y:int in range(first.y,last.y+1):
		for x:int in range(first.x,last.x+1):
			var key := Vector2i(x,y)
			active[key] = true
			if clouds.has(key): continue
			var sprite := Sprite2D.new()
			sprite.texture = cloud_textures[posmod(x*7+y*13,4)]
			sprite.material = cloud_material
			sprite.position = Vector2(key)*CLOUD_STEP
			sprite.scale = Vector2(4.8,3.8)
			sprite.flip_h = posmod(x+y,2)==0
			sprite.modulate = Color(0.86+0.035*posmod(x*3+y,4),0.90,0.94,1.0)
			add_child(sprite)
			clouds[key] = sprite
	for key:Vector2i in clouds.keys():
		if not active.has(key):
			clouds[key].queue_free()
			clouds.erase(key)

func update_mist_memory(delta:float) -> void:
	# Rasterize desired holes on CPU; retain spatial history, not an instant moving cutout.
	var target := PackedFloat32Array()
	target.resize(MEMORY_SIZE*MEMORY_SIZE)
	target.fill(0.0)
	var ratio:float = float(MEMORY_SIZE)/float(mask_view.size.x)
	for k:int in range(mask_node.polygons.size()):
		var polygon:PackedVector2Array = mask_node.polygons[k]
		for y:int in range(MEMORY_SIZE):
			var scan:float = (float(y)+0.5)/ratio
			var crossings:Array[float] = []
			for j:int in range(polygon.size()):
				var a:Vector2 = polygon[j]
				var b:Vector2 = polygon[(j+1)%polygon.size()]
				if (a.y<=scan and b.y>scan) or (b.y<=scan and a.y>scan):
					crossings.append((a.x+(scan-a.y)*(b.x-a.x)/(b.y-a.y))*ratio)
			crossings.sort()
			for j:int in range(0,crossings.size()-1,2):
				for x:int in range(clampi(int(ceil(crossings[j]-0.5)),0,MEMORY_SIZE),clampi(int(ceil(crossings[j+1]-0.5)),0,MEMORY_SIZE)):
					var index:int = y*MEMORY_SIZE+x
					target[index] = maxf(target[index],mask_node.colors[k].a)
	for i:int in range(reveal_memory.size()):
		var duration:float = 0.9 if target[i]>reveal_memory[i] else 2.8
		reveal_memory[i] = move_toward(reveal_memory[i],target[i],delta/duration)
		reveal_image.set_pixel(i%MEMORY_SIZE,i/MEMORY_SIZE,Color(1,1,1,reveal_memory[i]))
	reveal_texture.update(reveal_image)
	# Move cloud centers toward the nearest edge of the desired clearing, easing back later.
	for key:Vector2i in clouds:
		var sprite:Sprite2D = clouds[key]
		var anchor:Vector2 = Vector2(key)*CLOUD_STEP
		var mapped:Vector2 = (anchor-bounds.position)/bounds.size*Vector2(mask_view.size)
		var push:Vector2 = Vector2.ZERO
		for polygon:PackedVector2Array in mask_node.polygons:
			if not Geometry2D.is_point_in_polygon(mapped,polygon): continue
			var nearest:Vector2 = mapped+Vector2(100000,0)
			for j:int in range(polygon.size()):
				var edge:Vector2 = Geometry2D.get_closest_point_to_segment(mapped,polygon[j],polygon[(j+1)%polygon.size()])
				if edge.distance_squared_to(mapped)<nearest.distance_squared_to(mapped): nearest = edge
			push += (nearest-mapped).normalized()*38.0
		sprite.set_meta("avoid_target",push.limit_length(50.0))
func mist_reveal_at(point:Vector2) -> float:
	var cell:Vector2i = Vector2i(((point-bounds.position)/bounds.size*MEMORY_SIZE).floor())
	if cell.x<0 or cell.y<0 or cell.x>=MEMORY_SIZE or cell.y>=MEMORY_SIZE: return 0.0
	return reveal_memory[cell.y*MEMORY_SIZE+cell.x]

static func storm_edge(origin:Vector2,radius:float,angle:float) -> float:
	var seed_value:float = origin.x*0.013+origin.y*0.007
	return radius*(1.0+0.10*sin(angle*5.0+seed_value)+0.07*sin(angle*9.0-seed_value)+0.04*sin(angle*13.0+seed_value*2.0))
func thunder_clear(actor:Node2D) -> void:
	for storm:Dictionary in storms:
		if storm.owner.get_ref()==actor and storm.started==actor.phase_started: return
	if storms.size()>=16: storms.pop_front()
	storms.append({"owner":weakref(actor),"started":actor.phase_started,"origin":actor.rage_origin,"radius":actor.clear_radius,"remaining":3.2,"current":actor.clear_radius,"fade":1.0})
	upload_storms() # No refresh interval / opacity interpolation: visible this rendered frame.
func advance_storms(delta:float) -> void:
	for i:int in range(storms.size()-1,-1,-1):
		var storm:Dictionary = storms[i]
		var actor:Variant = storm.owner.get_ref()
		var held:bool = is_instance_valid(actor) and actor.health>0 and actor.phase==actor.Phase.RAGE and actor.phase_started==storm.started
		if not held: storm.remaining = maxf(0.0,storm.remaining-delta)
		storm.current = storm.radius*(storm.remaining/3.2)
		# The last stretch dissolves the clearing instead of collapsing to a weird point.
		storm.fade = 1.0 if storm.remaining>0.8 else maxf(storm.remaining/0.8,0.0)
		if storm.remaining<=0.0: storms.remove_at(i)
	upload_storms()
func upload_storms() -> void:
	var data := PackedVector4Array()
	data.resize(16)
	for i:int in range(storms.size()):
		var storm:Dictionary = storms[i]
		data[i] = Vector4(storm.origin.x,storm.origin.y,storm.current,storm.fade)
	cloud_material.set_shader_parameter("storm_count",storms.size())
	cloud_material.set_shader_parameter("storms",data)
func storm_push(anchor:Vector2) -> Vector2:
	var result := Vector2.ZERO
	for storm:Dictionary in storms:
		var relative:Vector2 = anchor-storm.origin
		var edge:float = storm_edge(storm.origin,storm.current,relative.angle())+35.0
		if relative.length()<edge:
			var push:Vector2 = Vector2.RIGHT.rotated(relative.angle())*(edge-relative.length())*storm.fade
			if push.length()>result.length(): result = push
	return result
