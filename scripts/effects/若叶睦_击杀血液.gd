extends Node2D

# 实体血滴使用连续碰撞；击杀血雾按用户要求恢复旧版烟雾贴图。
const PROFILE_PUNCH:int = 0
const PROFILE_GUITAR:int = 1
const PROFILE_GENERIC:int = 2
const BLOOD_LIQUID_DROP_SCRIPT = preload("res://scripts/effects/blood_liquid_drop.gd")
const BLOOD_SURFACE_DECAL_SCRIPT = preload("res://scripts/effects/blood_surface_decal.gd")
const BLOOD_MIST_TEXTURE:Texture2D = preload("res://Images/characters/人物/炮兵/烟雾.png")
const MAX_FLYING_BLOOD_DROPS:int = 160
const MAX_BLOOD_DECALS:int = 120
const BLOOD_DECAL_LIFETIME:float = 16.0
const BLOOD_RENDER_Z:int = -2
const BLOOD_BURST_SFX = [
	preload("res://audio/sfx/combat/血液1.mp3"),
	preload("res://audio/sfx/combat/血液2.mp3"),
]
const BLOOD_DROP_SFX = [
	preload("res://audio/sfx/combat/血滴1.mp3"),
	preload("res://audio/sfx/combat/血滴2.mp3"),
	preload("res://audio/sfx/combat/血滴3.mp3"),
	preload("res://audio/sfx/combat/血滴4.mp3"),
]

var _rng := RandomNumberGenerator.new()
var _active_projectiles:Array[Dictionary] = []
var _wall_stamps:Array[Dictionary] = []
var _ground_stamps:Array[Vector2] = []
var _service_mode:bool = false
var _shed_count:int = 0
var _surface_jobs:Dictionary = {}
var _surface_cache:Dictionary = {}
var _surface_expected:Dictionary = {}
var _decal_order:Array[WeakRef] = []
var _ray_query := PhysicsRayQueryParameters2D.new()
static var _skip_frame:int = -1
static var _skip_rids:Array[RID] = []
static var _last_sound_msec:int = -1000
static var _last_burst_sound_msec:int = -1000

func _ready() -> void:
	set_physics_process(false)
	add_to_group("BattleTransient")

func configure(origin:Vector2,base_direction:Vector2,profile:int,seed_value:int,projectile_count:int,spread_degrees:float,force_value:float,context:Dictionary = {}) -> void:
	_rng.seed = seed_value if seed_value != 0 else Game.battle_rng_seed_or("pixel_blood",int(Time.get_ticks_usec()))
	var kind:String = str(context.get("kind","crush" if profile == PROFILE_PUNCH else ("slash" if profile == PROFILE_GUITAR else "generic")))
	if kind == "burn":
		queue_free()
		return
	var axis:Vector2 = context.get("direction",base_direction)
	axis = axis.normalized() if axis.is_finite() and axis.length_squared() > 0.001 else Vector2.RIGHT
	var speed:float = clampf(force_value * 0.70,90.0,250.0)
	var cone:float = maxf(spread_degrees,22.0)
	var gravity:float = 180.0
	var drag:float = 2.0
	var life:float = 0.38
	var count:int = clampi(projectile_count + 5,8,20)
	match kind:
		"pierce":
			speed = clampf(float(context.get("speed",force_value)) * 0.70,190.0,850.0)
			cone = lerpf(8.0,3.0,clampf(speed / 850.0,0.0,1.0))
			gravity = 35.0
			drag = 0.35
			life = 0.58
			count = 16
		"slash":
			cone = 48.0
			speed *= 1.15
			life = 0.34
		"crush":
			cone = 65.0
			speed *= 0.70
			gravity = 240.0
			life = 0.30
		"blast":
			cone = 175.0
			speed *= 1.45
			count = 22
	speed *= clampf(float(context.get("speed_scale",1.0)),0.5,1.6)
	life *= clampf(float(context.get("life_scale",1.0)),0.30,1.5)
	cone = minf(cone * clampf(float(context.get("cone_scale",1.0)),0.5,2.0),175.0)
	count = clampi(int(context.get("count",count)),4,24)
	set_meta("blood_profile",kind)
	var intensity:float = clampf(sqrt(maxf(float(context.get("damage",50.0)),1.0) / maxf(float(context.get("reference_health",50.0)),1.0)),0.5,1.5)
	count = clampi(count + int(round((intensity - 1.0) * 4.0)),6,24)
	count = mini(count,maxi(MAX_FLYING_BLOOD_DROPS - get_tree().get_nodes_in_group("CombatBloodDrop").size(),0))
	_play_random_blood_sound(origin,BLOOD_BURST_SFX,-3.0,_rng.randf_range(0.96,1.04),1500.0,true)
	_spawn_kill_mist(origin,axis,cone,intensity,seed_value ^ 0x4B10)
	for i:int in range(count):
		var fine:bool = i % 3 == 2
		var angle:float = deg_to_rad((_rng.randf() + _rng.randf() - 1.0) * cone * (1.0 if fine else 0.40))
		var direction_value:Vector2 = axis.rotated(angle)
		var velocity_value:Vector2 = direction_value * speed * (_rng.randf_range(0.65,1.15) if fine else _rng.randf_range(0.86,1.02))
		# 不挪动出生点到矛尖/墙后；细飞沫同样参加碰撞。
		_spawn_projectile(origin,velocity_value,gravity,drag,life * _rng.randf_range(0.75,1.15),
			_rng.randf_range(1.3,2.4) if fine else _rng.randf_range(4.8,6.4),
			_rng.randf_range(0.30,0.48) if fine else _rng.randf_range(0.75,1.0),
			_rng.randf_range(0.018,0.055) if fine else 0.0,kind == "pierce")
	set_physics_process(not _active_projectiles.is_empty())
	if _active_projectiles.is_empty(): queue_free()

func _spawn_kill_mist(origin:Vector2,_axis:Vector2,_cone:float,_intensity:float,seed_value:int) -> void:
	if BLOOD_MIST_TEXTURE == null or get_tree() == null or get_tree().current_scene == null:
		return
	# 恢复旧烟雾贴图和原来的颜色、大小、上飘与约0.9秒淡出。
	var mist_rng := RandomNumberGenerator.new()
	mist_rng.seed = seed_value
	var count:int = mini(mist_rng.randi_range(2,4),48 - get_tree().get_nodes_in_group("CombatBloodMist").size())
	for i:int in range(count):
		var puff:=Sprite2D.new()
		puff.texture = BLOOD_MIST_TEXTURE
		# V187：血雾跟随 World 使用 relative z=-2，绝不能盖住人物/投射物。
		puff.z_as_relative = true
		puff.z_index = BLOOD_RENDER_Z
		puff.self_modulate = Color(0.62 + mist_rng.randf_range(-0.05,0.08),0.015,0.02,mist_rng.randf_range(0.14,0.24))
		var size:float = mist_rng.randf_range(0.13,0.24)
		puff.scale = Vector2.ONE * size
		puff.rotation = mist_rng.randf_range(-PI,PI)
		var spawn_position:Vector2 = origin + Vector2(mist_rng.randf_range(-12.0,12.0),mist_rng.randf_range(-8.0,8.0))
		puff.add_to_group("BattleTransient")
		get_tree().current_scene.add_child(puff)
		puff.global_position = spawn_position
		puff.add_to_group("CombatBloodMist")
		var drift:=Vector2(mist_rng.randf_range(-20.0,20.0),-mist_rng.randf_range(30.0,48.0))
		var tw:=puff.create_tween().set_parallel(true)
		tw.tween_property(puff,"global_position",puff.global_position+drift,mist_rng.randf_range(0.75,1.05)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(puff,"scale",puff.scale*mist_rng.randf_range(1.10,1.22),0.9)
		tw.tween_property(puff,"rotation",puff.rotation+mist_rng.randf_range(-0.20,0.20),0.9)
		tw.tween_property(puff,"self_modulate:a",0.0,0.9)
		tw.finished.connect(puff.queue_free,CONNECT_ONE_SHOT)

func _spawn_projectile(origin:Vector2,velocity_value:Vector2,gravity:float,drag:float,life:float,size_value:float,splat:float,delay:float,pierce:bool,can_shed:bool = true) -> void:
	var world:Node = get_tree().current_scene
	if world == null: return
	var visual:Node2D = BLOOD_LIQUID_DROP_SCRIPT.new()
	world.add_child(visual)
	visual.global_transform = Transform2D(0.0,origin) # 不继承 World 的缩放，避免一滴血被放大成巨斑。
	visual.z_as_relative = true
	visual.z_index = BLOOD_RENDER_Z
	visual.add_to_group("BattleTransient")
	visual.add_to_group("CombatBloodDrop")
	visual.visible = false
	visual.call("configure",size_value * (1.7 if pierce else 1.0),size_value,Color("a7192c"),_rng.randi())
	_active_projectiles.append({"node":visual,"velocity":velocity_value,"gravity":gravity,"drag":drag,
		"life":life,"delay":delay,"age":0.0,"radius":float(visual.call("collision_radius")),"splat_scale":splat,
		"shed_at":_rng.randf_range(0.11,0.23) if can_shed and size_value >= 4.0 and _rng.randf() < 0.38 else -1.0,
		"detached":not can_shed})

func _physics_process(delta:float) -> void:
	if _service_mode:
		_drain_surface_requests()
		return
	_tick_projectiles(maxf(delta,0.0))
	if _active_projectiles.is_empty(): queue_free()

func _tick_projectiles(delta:float) -> void:
	for index:int in range(_active_projectiles.size() - 1,-1,-1):
		var info:Dictionary = _active_projectiles[index]
		var raw:Variant = info.get("node")
		if not is_instance_valid(raw):
			_active_projectiles.remove_at(index)
			continue
		var visual:Node2D = raw
		if info.has("landing_left"):
			info["landing_left"] = float(info["landing_left"]) - delta
			if float(info["landing_left"]) <= 0.0:
				visual.call("landing_resolved")
				_active_projectiles.remove_at(index)
			continue
		if info.has("contact_left"):
			info["contact_left"] = float(info["contact_left"]) - delta
			if float(info["contact_left"]) <= 0.0:
				visual.queue_free()
				_active_projectiles.remove_at(index)
			continue
		info["delay"] = float(info["delay"]) - delta
		if float(info["delay"]) > 0.0: continue
		var age:float = float(info["age"]) + delta
		info["age"] = age
		var v:Vector2 = info["velocity"]
		var previous:Vector2 = visual.global_position
		var next:Vector2 = previous + v * delta + Vector2.DOWN * float(info["gravity"]) * delta * delta * 0.5
		var axis:Vector2 = v.normalized()
		var radius:float = float(info["radius"])
		var hit:Dictionary = _sweep_blood(previous,next,radius)
		if not hit.is_empty():
			var normal:Vector2 = hit.get("normal",-axis)
			if normal.length_squared() < 0.01: normal = -axis
			var point:Vector2 = hit.get("position",previous)
			info["contact_left"] = _spawn_wall_decal(point,normal,hit.get("collider"),axis,float(info["splat_scale"]),hit.get("rid",RID()))
			visual.call("contact",point,normal)
			continue
		visual.visible = true
		visual.call("advance",next,axis)
		info["velocity"] = v * exp(-float(info["drag"]) * delta) + Vector2.DOWN * float(info["gravity"]) * delta
		var shed_at:float = float(info.get("shed_at",-1.0))
		if shed_at >= 0.0 and age >= shed_at and age < float(info["life"]):
			info["shed_at"] = -1.0
			if _shed_count < 3 and get_tree().get_nodes_in_group("CombatBloodDrop").size() < MAX_FLYING_BLOOD_DROPS:
				_shed_count += 1
				_spawn_projectile(next - axis * 2.0,v * 0.25 + Vector2.DOWN * _rng.randf_range(65.0,105.0),340.0,1.4,_rng.randf_range(0.18,0.29),_rng.randf_range(1.5,2.3),0.30,0.0,false,false)
				visual.call("release_droplet")
		if age >= float(info["life"]):
			var landing:Dictionary = visual.call("landing_snapshot")
			info["landing_left"] = 0.72
			visual.call("start_landing")
			_spawn_ground_decal(next,axis,float(info["splat_scale"]),landing)

func _sweep_blood(from_position:Vector2,to_position:Vector2,radius:float) -> Dictionary:
	var axis:Vector2 = (to_position - from_position).normalized()
	var side:Vector2 = axis.orthogonal() * radius
	var best:Dictionary = {}
	var distance:float = INF
	# 从中心开始查前沿，禁止把 ray 起点直接移进薄墙；左右边也必须截断。
	for offset:Vector2 in [Vector2.ZERO,side,-side]:
		var hit:Dictionary = _wall_raycast(from_position + offset,to_position + offset + axis * radius)
		if not hit.is_empty():
			var d:float = from_position.distance_squared_to(hit.get("position",from_position))
			if d < distance:
				distance = d
				best = hit
	return best

func _wall_raycast(from_position:Vector2,to_position:Vector2) -> Dictionary:
	if from_position.distance_squared_to(to_position) <= 0.000001:
		return {}
	var world:World2D = get_world_2d()
	if world == null:
		return {}
	var state:PhysicsDirectSpaceState2D = world.direct_space_state
	var frame:int = Engine.get_physics_frames()
	if frame != _skip_frame:
		_skip_frame = frame
		_skip_rids.clear()
	# 查询所有实体层，排除人物和投射物，兼容非 Terrain 层的生成障碍物。
	for _attempt:int in range(12):
		var query:PhysicsRayQueryParameters2D = _ray_query
		query.from = from_position
		query.to = to_position
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.collision_mask = 0xFFFFFFFF
		query.hit_from_inside = true
		query.exclude = _skip_rids
		var hit:Dictionary = state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider:Object = hit.get("collider")
		if _is_wall_like_object(collider):
			return hit
		var rid:RID = hit.get("rid",RID())
		if not rid.is_valid():
			return {}
		_skip_rids.append(rid)
	return {}


func _is_wall_like_object(collider:Object) -> bool:
	if collider == null:
		return false
	if collider.has_meta("wall_hit_surface"):
		return bool(collider.get_meta("wall_hit_surface"))
	if collider is ball:
		return false
	if collider is TileMapLayer or collider is StaticBody2D or collider is AnimatableBody2D:
		return true
	if collider.has_meta("wall_hit_surface"):
		return bool(collider.get_meta("wall_hit_surface"))
	return false


# 同一 World 共用一个表面服务；请求按碰撞体、位置、朝向合并，避免每一滴都建血池。
func _surface_service_node() -> Node:
	var existing:Node = get_tree().get_first_node_in_group("BloodSurfaceService")
	if is_instance_valid(existing):
		if not existing.is_queued_for_deletion(): return existing
		existing.remove_from_group("BloodSurfaceService")
	var service:Node = get_script().new()
	service._service_mode = true
	service.name = "BloodSurfaceService"
	get_tree().current_scene.add_child(service)
	service.add_to_group("BloodSurfaceService")
	return service

func _spawn_wall_decal(position_value:Vector2,surface_normal:Vector2,collider:Object,incoming_direction:Vector2,scale_value:float,body_rid:RID = RID()) -> float:
	if not is_instance_valid(collider) or not collider is Node2D: return 0.07
	return float(_surface_service_node().call("_queue_wall",position_value,surface_normal,collider,incoming_direction,scale_value,body_rid))

func _queue_wall(point:Vector2,normal:Vector2,collider:Node2D,incoming:Vector2,amount:float,body_rid:RID) -> float:
	var key:String = "w:%d:%d:%d:%d" % [collider.get_instance_id(),int(floorf(point.x / 18.0)),int(floorf(point.y / 18.0)),posmod(int(round(normal.angle() * 8.0 / TAU)),8)]
	if _surface_jobs.has(key):
		_surface_jobs[key]["amount"] = minf(float(_surface_jobs[key]["amount"]) + amount,4.0)
		return minf(0.08 + _surface_jobs.size() * 0.018,0.65)
	if _surface_jobs.size() >= 64: return 0.10
	var rid:RID = body_rid
	if not rid.is_valid() and collider is CollisionObject2D: rid = (collider as CollisionObject2D).get_rid()
	# RID 在碰撞当帧读取为几何快照；地图单元下一帧被删除也不会访问过期 RID。
	var polygons:Array[PackedVector2Array] = []
	if not _surface_cache.has(key): polygons = _body_polygons(rid,collider.global_transform.affine_inverse(),collider)
	_surface_jobs[key] = {"key":key,"wall":true,"collider":weakref(collider),"point":collider.to_local(point),
		"normal":collider.global_transform.basis_xform_inv(normal),"incoming":incoming,"amount":amount,"polygons":polygons}
	set_physics_process(true)
	return minf(0.08 + _surface_jobs.size() * 0.018,0.65)

func _spawn_ground_decal(position_value:Vector2,incoming_direction:Vector2,scale_value:float,landing:Dictionary = {}) -> void:
	_surface_service_node().call("_queue_floor",position_value,incoming_direction,scale_value,landing)

func _queue_floor(point:Vector2,incoming:Vector2,amount:float,landing:Dictionary = {}) -> void:
	var key:String = "g:%d:%d" % [int(floorf(point.x / 18.0)),int(floorf(point.y / 18.0))]
	if _surface_jobs.has(key):
		var job:Dictionary = _surface_jobs[key]
		job["amount"] = minf(float(job["amount"]) + amount,4.0)
		if not landing.is_empty():
			if job["landings"].size() < 3: job["landings"].append(landing)
			job["sources"].append(landing["source"])
		return
	if _surface_jobs.size() >= 32: return
	_surface_jobs[key] = {"key":key,"wall":false,"point":point,"incoming":incoming,"amount":amount,
		"landings":[landing] if not landing.is_empty() else [],"sources":[landing["source"]] if not landing.is_empty() else []}
	set_physics_process(true)

func _release_landing_sources(job:Dictionary) -> void:
	for reference:WeakRef in job.get("sources",[]):
		var source:Variant = reference.get_ref()
		if is_instance_valid(source): source.call("landing_resolved")

func _drain_surface_requests() -> void:
	var start:int = Time.get_ticks_usec()
	var processed:int = 0
	while not _surface_jobs.is_empty() and processed < 4:
		var key:Variant = _surface_jobs.keys()[0]
		var job:Dictionary = _surface_jobs[key]
		_surface_jobs.erase(key)
		_apply_surface_job(job)
		processed += 1
		if Time.get_ticks_usec() - start >= 2200: break
	if _surface_cache.size() > 192:
		for key:Variant in _surface_cache.keys():
			var alive:bool = false
			for reference:WeakRef in _surface_cache[key]:
				if is_instance_valid(reference.get_ref()): alive = true
			if not alive:
				_surface_cache.erase(key)
				_surface_expected.erase(key)
	set_physics_process(not _surface_jobs.is_empty())

func _apply_surface_job(job:Dictionary) -> void:
	var key:String = job["key"]
	var nodes:Array[WeakRef] = []
	if _surface_cache.has(key):
		for reference:WeakRef in _surface_cache[key]:
			var node:Variant = reference.get_ref()
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.call("add_volume",float(job["amount"]) * 0.25,job.get("landings",[]))
				_schedule_fade(node,false)
				nodes.append(reference)
		if nodes.size() >= int(_surface_expected.get(key,1)):
			_release_landing_sources(job)
			return
		# 预算可能只清走墙血/前堆中的一层；下一次命中补齐两层，不能永久只剩一层。
		for reference:WeakRef in nodes:
			var node:Variant = reference.get_ref()
			if is_instance_valid(node):
				job["amount"] = maxf(float(job["amount"]),float(node.get("_volume")))
				node.remove_from_group("CombatBloodDecal")
				node.queue_free()
		nodes.clear()
	var amount:float = float(job["amount"])
	var unit:float = clampf(0.55 + amount * 0.06,0.60,0.82) if bool(job["wall"]) else clampf(0.70 + amount * 0.15,0.75,1.25)
	if bool(job["wall"]):
		var object:Variant = (job["collider"] as WeakRef).get_ref()
		if not is_instance_valid(object): return
		var collider:Node2D = object
		var point:Vector2 = collider.to_global(job["point"])
		var normal:Vector2 = collider.global_transform.basis_xform(job["normal"]).normalized()
		var tangent := Vector2(normal.y,-normal.x)
		var transform := Transform2D(tangent,-normal,point - normal * 0.15)
		var masks:Array[PackedVector2Array] = []
		var local:Transform2D = transform.affine_inverse() * collider.global_transform
		for polygon:PackedVector2Array in job["polygons"]:
			masks.append(local * polygon)
		if masks.is_empty():
			masks = _build_wall_surface_masks(transform.origin,normal,tangent,collider,18.0,22.0)
		# 墙面投影与墙前堆积是两层，任何一层失败都不能让另一层消失。
		if not masks.is_empty() and collider.is_visible_in_tree():
			var holder:Node2D = BLOOD_SURFACE_DECAL_SCRIPT.new()
			var surface_z:int = 1
			for child:Node in collider.get_children():
				if child is CanvasItem and not child.is_in_group("CombatBloodDecal") and child.z_as_relative:
					surface_z = maxi(surface_z,child.z_index + 1)
			collider.add_child(holder)
			holder.name = "KillBloodWallProjection"
			holder.z_index = clampi(surface_z,0,100)
			holder.global_transform = transform
			holder.call("configure",masks,_rng.randi(),unit,(job["incoming"] as Vector2).dot(tangent),Vector2(Vector2.DOWN.dot(tangent),Vector2.DOWN.dot(-normal)))
			holder.add_to_group("BattleTransient")
			_schedule_fade(holder)
			nodes.append(weakref(holder))
		var pile:Node2D = _make_floor_patch(Transform2D(tangent,normal,point + normal * 0.2),unit * 0.75,true)
		if is_instance_valid(pile): nodes.append(weakref(pile))
		_play_random_blood_sound(point,BLOOD_DROP_SFX,-14.5,1.0,950.0)
	else:
		var point:Vector2 = job["point"]
		var holder:Node2D = _make_floor_patch(Transform2D(0.0,point.floor()),unit,false,job.get("landings",[]))
		if is_instance_valid(holder): nodes.append(weakref(holder))
		_play_random_blood_sound(point,BLOOD_DROP_SFX,-15.0,1.0,950.0)
	if not nodes.is_empty():
		_surface_cache[key] = nodes
		_surface_expected[key] = nodes.size()
	_release_landing_sources(job)

func _make_floor_patch(transform:Transform2D,unit:float,heap:bool,landings:Array = []) -> Node2D:
	var world:Node = get_tree().current_scene
	if world == null: return null
	var holder:Node2D = BLOOD_SURFACE_DECAL_SCRIPT.new()
	world.add_child(holder)
	holder.name = "KillBloodFrontPile" if heap else "KillBloodPixelGround"
	holder.global_transform = transform
	holder.z_index = BLOOD_RENDER_Z
	holder.add_to_group("BattleTransient")
	var bounds:PackedVector2Array = PackedVector2Array([Vector2(-28,0 if heap else -28),Vector2(28,0 if heap else -28),Vector2(28,28),Vector2(-28,28)])
	var masks:Array[PackedVector2Array] = [bounds]
	var blocked:Array[PackedVector2Array] = _floor_obstacle_polygons(transform)
	holder.call("configure_ground",_rng.randi(),unit,Callable(),masks,heap,blocked,landings)
	if holder.get("_cells").is_empty():
		holder.queue_free()
		return null
	_schedule_fade(holder)
	return holder

func _floor_obstacle_polygons(transform:Transform2D) -> Array[PackedVector2Array]:
	var polygons:Array[PackedVector2Array] = []
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(66,66)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = rectangle
	query.transform = Transform2D(0.0,transform.origin)
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	var seen:Dictionary = {}
	var excluded:Array[RID] = []
	for pass_index:int in range(4):
		query.exclude = excluded
		var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,64)
		for hit:Dictionary in hits:
			var rid:RID = hit["rid"]
			if seen.has(rid): continue
			seen[rid] = true
			excluded.append(rid)
			if _is_wall_like_object(hit.get("collider")):
				polygons.append_array(_body_polygons(rid,transform.affine_inverse(),hit.get("collider")))
		if hits.size() < 64: break
	return polygons

func _body_polygons(body_rid:RID,to_local_transform:Transform2D,collider:Object = null) -> Array[PackedVector2Array]:
	var result:Array[PackedVector2Array] = []
	if not body_rid.is_valid(): return result
	var body_transform:Transform2D = PhysicsServer2D.body_get_state(body_rid,PhysicsServer2D.BODY_STATE_TRANSFORM)
	for index:int in range(mini(PhysicsServer2D.body_get_shape_count(body_rid),32)):
		if is_instance_valid(collider) and collider is CollisionObject2D:
			var owner_id:int = (collider as CollisionObject2D).shape_find_owner(index)
			if (collider as CollisionObject2D).is_shape_owner_disabled(owner_id): continue
		var rid:RID = PhysicsServer2D.body_get_shape(body_rid,index)
		var kind:int = PhysicsServer2D.shape_get_type(rid)
		var data:Variant = PhysicsServer2D.shape_get_data(rid)
		var polygon := PackedVector2Array()
		match kind:
			PhysicsServer2D.SHAPE_RECTANGLE:
				var half:Vector2 = data
				polygon = PackedVector2Array([Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)])
			PhysicsServer2D.SHAPE_CIRCLE:
				for i:int in range(24): polygon.append(Vector2.from_angle(TAU * i / 24.0) * float(data))
			PhysicsServer2D.SHAPE_CAPSULE:
				var dimensions:Vector2 = data
				var radius:float = dimensions.y
				var shift:float = maxf(dimensions.x * 0.5 - radius,0.0)
				for i:int in range(24):
					var p:Vector2 = Vector2.from_angle(TAU * i / 24.0) * radius
					p.y += shift if p.y >= 0.0 else -shift
					polygon.append(p)
			PhysicsServer2D.SHAPE_CONVEX_POLYGON:
				if data is PackedVector2Array: polygon = data
		if polygon.size() >= 3:
			result.append(to_local_transform * body_transform * PhysicsServer2D.body_get_shape_transform(body_rid,index) * polygon)
	return result

func _floor_cell_clear(point:Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_point(query,32):
		if _is_wall_like_object(hit.get("collider")): return false
	return true

func _surface_contains(point:Vector2,collider:Object) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	for result:Dictionary in get_world_2d().direct_space_state.intersect_point(query,16):
		if result.get("collider") == collider:
			return true
	return false


func _append_surface_mask(top:Array[Vector2],bottom:Array[Vector2],masks:Array[PackedVector2Array]) -> void:
	if top.size() < 2:
		return
	var polygon:PackedVector2Array = PackedVector2Array(top)
	for index:int in range(bottom.size() - 1,-1,-1):
		polygon.append(bottom[index])
	masks.append(polygon)


func _build_wall_surface_masks(origin:Vector2,normal:Vector2,tangent:Vector2,collider:Object,half_width:float,depth:float) -> Array[PackedVector2Array]:
	var masks:Array[PackedVector2Array] = []
	var top:Array[Vector2] = []
	var bottom:Array[Vector2] = []
	var state:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for index:int in range(15):
		var x:float = lerpf(-half_width,half_width,float(index) / 14.0)
		var sample:Vector2 = origin + tangent * x
		var ray := PhysicsRayQueryParameters2D.create(sample + normal * 6.0,sample - normal * depth,0xFFFFFFFF)
		ray.exclude = _skip_rids
		ray.collide_with_areas = false
		var hit:Dictionary = state.intersect_ray(ray)
		var valid:bool = not hit.is_empty() and hit.get("collider") == collider
		if valid:
			valid = (hit.get("normal",Vector2.ZERO) as Vector2).dot(normal) > 0.25
		var entry:float = 0.0
		if valid:
			entry = maxf(((hit["position"] as Vector2) - sample).dot(-normal) + 0.20,0.0)
			valid = entry < depth and _surface_contains(sample - normal * entry,collider)
		if not valid:
			_append_surface_mask(top,bottom,masks)
			top.clear()
			bottom.clear()
			continue
		var inside:float = entry
		var outside:float = depth
		if _surface_contains(sample - normal * depth,collider):
			inside = depth
		else:
			# 薄墙、石块边缘：二分实体厚度，血迹不能穿透另一侧或越过墙角。
			for step:int in range(6):
				var middle:float = (inside + outside) * 0.5
				if _surface_contains(sample - normal * middle,collider):
					inside = middle
				else:
					outside = middle
		top.append(Vector2(x,entry))
		bottom.append(Vector2(x,maxf(inside - 0.12,entry)))
	_append_surface_mask(top,bottom,masks)
	return masks


func _play_random_blood_sound(position_value:Vector2,streams:Array,volume_db:float,pitch:float,max_distance:float,kill_burst:bool = false) -> void:
	if streams.is_empty() or not is_inside_tree():
		return
	var now:int = Time.get_ticks_msec()
	var group:StringName = &"CombatBloodKillSFX" if kill_burst else &"CombatBloodDropSFX"
	# 击杀声独立于滴落声限流，不能被刚播放的轻微滴血声吞掉。
	if kill_burst:
		if now - _last_burst_sound_msec < 45: return
		_last_burst_sound_msec = now
	else:
		if now - _last_sound_msec < 35: return
		_last_sound_msec = now
	var voices:Array[Node] = get_tree().get_nodes_in_group(group)
	var limit:int = 4 if kill_burst else 8
	if voices.size() >= limit:
		if not kill_burst: return
		var oldest:Node = voices[0]
		oldest.call("stop")
		oldest.remove_from_group(group)
		oldest.remove_from_group("CombatBloodSFX")
		oldest.queue_free()
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var stream_value:Variant = streams[_rng.randi_range(0,streams.size() - 1)]
	if not stream_value is AudioStream:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "KillBloodSFX"
	player.stream = stream_value as AudioStream
	player.volume_db = clampf(volume_db,-30.0,6.0)
	player.pitch_scale = clampf(pitch,0.75,1.35)
	player.max_distance = maxf(max_distance,200.0)
	player.attenuation = 0.85
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value # 入树后定位，避免继承 World 变换造成声音错位。
	player.add_to_group("CombatBloodSFX")
	player.add_to_group(group)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _schedule_fade(holder:Node2D,register:bool = true) -> void:
	if not is_instance_valid(holder): return
	var now:int = Time.get_ticks_msec()
	if not register and now - int(holder.get_meta("blood_refresh_msec",0)) < 2000: return
	holder.set_meta("blood_refresh_msec",now)
	if holder.has_meta("blood_fade_tween"):
		var old:Variant = holder.get_meta("blood_fade_tween")
		if is_instance_valid(old): old.kill()
	holder.modulate.a = 1.0
	if register:
		holder.add_to_group("CombatBloodDecal")
		holder.set_meta("blood_decal_created_usec",Time.get_ticks_usec())
		_decal_order.append(weakref(holder))
		var count:int = get_tree().get_nodes_in_group("CombatBloodDecal").size()
		while count > MAX_BLOOD_DECALS and not _decal_order.is_empty():
			var candidate:Variant = _decal_order.pop_front().get_ref()
			if is_instance_valid(candidate) and candidate.is_in_group("CombatBloodDecal"):
				candidate.remove_from_group("CombatBloodDecal")
				candidate.queue_free()
				count -= 1
		if _decal_order.size() > 240:
			_decal_order = _decal_order.filter(func(reference:WeakRef) -> bool: return is_instance_valid(reference.get_ref()))
	var tween:Tween = holder.create_tween()
	holder.set_meta("blood_fade_tween",tween)
	tween.tween_interval(BLOOD_DECAL_LIFETIME * _rng.randf_range(0.70,1.0))
	tween.tween_property(holder,"modulate:a",0.0,1.3)
	tween.finished.connect(holder.queue_free,CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	for info:Dictionary in _active_projectiles:
		var raw:Variant = info.get("node")
		if is_instance_valid(raw): raw.queue_free()
	_active_projectiles.clear()
