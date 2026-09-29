extends Node
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")
# 被羊毛弹开的弹丸：保留原生外观，以独立扫掠飞行解除旧主人/追踪逻辑。
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
var shot:Node2D
var holder:WeakRef
var flying:bool = false
var flight:Vector2 = Vector2.ZERO
var damage:float = 10.0
var damage_kind:StringName = &"ordinary"
var life:float = 4.0
var grace:float = 0.0
var replica:bool = false
var last_holder:WeakRef
var hold_offset:Vector2 = Vector2.ZERO

static func has_prop(node:Object,key:String) -> bool:
	for prop:Dictionary in node.get_property_list():
		if prop.name == key: return true
	return false
static func is_projectile(node:Node) -> bool:
	return PROJECTILE_API.supports(node,"wool")

static func motion(node:Node2D) -> Vector2:
	return PROJECTILE_API.velocity_of(node)

static func candidates(tree:SceneTree) -> Array[Node]:
	return PROJECTILE_API.candidates(tree)

static func entry_fraction(start:Vector2,finish:Vector2,center:Vector2,radius:float) -> float:
	var offset:Vector2 = start-center
	if offset.length_squared() <= radius*radius: return 0.0
	var step:Vector2 = finish-start
	var length_squared:float = step.length_squared()
	if length_squared < 0.000001: return INF
	var b:float = offset.dot(step)
	var discriminant:float = b*b-length_squared*(offset.length_squared()-radius*radius)
	if discriminant < 0.0: return INF
	var t:float = (-b-sqrt(discriminant))/length_squared
	return t if t >= 0.0 and t <= 1.0 else INF

static func sweep(node:Node2D,start:Vector2,finish:Vector2,ignore:Node = null) -> bool:
	if not is_projectile(node): return false
	var contacts:Array[Dictionary] = []
	for sheep:Node in node.get_tree().get_nodes_in_group("MinecraftWoolSheep"):
		if not is_instance_valid(sheep) or sheep == ignore or sheep.health <= 0: continue
		var t:float = entry_fraction(start,finish,sheep.global_position,sheep.wool_projectile_radius)
		if is_finite(t): contacts.append({"sheep":sheep,"t":t})
	contacts.sort_custom(func(a:Dictionary,b:Dictionary): return a.t < b.t)
	for contact:Dictionary in contacts:
		var sheep:Node = contact.sheep
		var point:Vector2 = start.lerp(finish,float(contact.t))
		if not U.line_clear(sheep,start,point): continue
		if not U.line_clear(sheep,point,sheep.global_position): continue
		# 扫掠仅防止穿透，先推进到真实接触点，不能在远处直接拦停弹丸。
		var previous:Vector2 = node.global_position
		node.global_position = point
		if sheep.catch_wool_projectile(node): return true
		node.global_position = previous
	return false

func setup(projectile:Node2D,sheep:Node) -> void:
	shot = projectile
	flight = motion(shot)
	damage = PROJECTILE_API.damage_of(shot)
	damage_kind = StringName(PROJECTILE_API.damage_kind_of(shot))
	shot.set_meta("mc_wool_flight",weakref(self))
	# 原脚本不再抢方向、重选主人或在被拒绝的命中后自行销毁。
	shot.set_deferred("process_mode",Node.PROCESS_MODE_DISABLED)
	if shot is ball:
		shot.collision_layer = 0
		shot.collision_mask = 0
		hold_by(sheep)
	else:
		hold_by(sheep)
func hold_by(sheep:Node) -> void:
	hold_offset = (shot.global_position-sheep.global_position).limit_length(sheep.wool_projectile_radius)
	holder = weakref(sheep)
	last_holder = holder
	flying = false
func launch() -> void:
	if not is_instance_valid(shot): queue_free(); return
	var sheep = holder.get_ref() if holder != null else null
	var dir:Vector2 = -flight.normalized()
	if is_instance_valid(sheep):
		shot.global_position = sheep.global_position+hold_offset
		dir = hold_offset.normalized()
	if dir.length_squared() < 0.01: dir = Vector2.RIGHT
	flight = dir*clampf(maxf(flight.length(),280.0),280.0,1000.0)
	flying = true
	holder = null
	grace = 0.16
	PROJECTILE_API.bind_owner(shot,null,"")
	if shot is ball: shot.Repel = Vector2.ZERO
	shot.global_rotation = (shot.Default_Rotation if shot is ball else 0.0)+dir.angle()
func _physics_process(delta:float) -> void:
	if not is_instance_valid(shot) or shot.is_queued_for_deletion(): queue_free(); return
	if get_tree().paused or Game.now_stop_state: return
	if replica:
		if flying: shot.global_position += flight*delta
		return
	if not is_multiplayer_authority(): return
	if not flying:
		var sheep = holder.get_ref() if holder != null else null
		if not is_instance_valid(sheep) or sheep.health <= 0: launch()
		else: shot.global_position = sheep.global_position+hold_offset
		return
	life -= delta
	var protect_holder:bool = grace > 0.0
	grace = maxf(grace-delta,0.0)
	if life <= 0: _retire(); return
	var start:Vector2 = shot.global_position
	var finish:Vector2 = start+flight*delta
	var wall:Dictionary = U.trace(shot,start,finish)
	if not wall.is_empty(): finish = wall.position
	var ignored:Node = last_holder.get_ref() if protect_holder and last_holder != null else null
	if sweep(shot,start,finish,ignored): return
	var nearest:ball
	var nearest_t:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or node == shot or is_projectile(node) or not node.is_combat_targetable(): continue
		if PROJECTILE_CONTACT.ignores(node): continue
		if protect_holder and last_holder != null and node == last_holder.get_ref(): continue
		var center:Vector2 = node.global_position
		var radius:float = 12.0
		var cs:CollisionShape2D = node.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs != null and cs.shape != null: radius = maxf((cs.shape.get_rect().size*cs.global_scale.abs()).x*0.5,4.0)
		var t:float = (center-start).dot(flight.normalized())
		if U.segment_distance(center,start,finish) <= radius+3.0 and t < nearest_t:
			nearest = node
			nearest_t = t
	if nearest != null:
		if nearest.has_method("catch_wool_projectile") and nearest.catch_wool_projectile(shot): return
		nearest.receive_classified_positional_damage(damage,start,damage_kind,false,shot)
		_retire()
		return
	shot.global_position = finish
	if not wall.is_empty(): _retire()
func _retire() -> void:
	if is_instance_valid(shot): shot.queue_free()
	queue_free()

func snapshot() -> Dictionary:
	if not is_instance_valid(shot) or shot.is_queued_for_deletion(): return {}
	return {"path":str(shot.get_path()),"position":shot.global_position,"flight":flight,"flying":flying,"life":life}
static func accept_snapshots(sheep:Node,states:Array) -> void:
	var retained:Dictionary = sheep.get_meta("mc_wool_remote_shots",{})
	var present:Dictionary = {}
	for data:Dictionary in states:
		var path:String = str(data.get("path",""))
		present[path] = true
		var projectile:Node2D = sheep.get_node_or_null(NodePath(path)) as Node2D
		if projectile == null: continue
		var controller
		if projectile.has_meta("mc_wool_flight"): controller = projectile.get_meta("mc_wool_flight").get_ref()
		if not is_instance_valid(controller):
			controller = load("res://scripts/characters/我的世界/new6/wool_projectile.gd").new()
			sheep.get_tree().current_scene.add_child(controller,true)
			controller.setup(projectile,sheep)
		controller.replica = true
		controller.flight = data.get("flight",Vector2.ZERO)
		if bool(data.get("flying",false)) and not controller.flying: controller.launch()
		controller.flying = bool(data.get("flying",false))
		controller.flight = data.get("flight",Vector2.ZERO)
		projectile.global_position = data.get("position",projectile.global_position)
		retained[path] = weakref(controller)
	for path in retained.keys():
		if present.has(path): continue
		var controller = retained[path].get_ref()
		if is_instance_valid(controller): controller._retire()
		retained.erase(path)
	sheep.set_meta("mc_wool_remote_shots",retained)
