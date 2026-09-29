extends Node
## Shared pre-motion interception. One per SceneTree, no per-role projectile lists.
const API = preload("res://classes/projectile_interactions.gd")
const CONTACT = preload("res://scripts/projectile_contact.gd")
const CAPTURE = preload("res://scripts/characters/我的世界/allay/capture.gd")

func _ready() -> void:
	process_physics_priority = -100

static func entry_fraction(start:Vector2,finish:Vector2,center:Vector2,radius:float) -> float:
	var delta:Vector2 = finish-start
	var relative:Vector2 = start-center
	if relative.length_squared() <= radius*radius: return 0.0
	var length_sq:float = delta.length_squared()
	if length_sq < 0.000001: return INF
	var b:float = relative.dot(delta)
	var disc:float = b*b-length_sq*(relative.length_squared()-radius*radius)
	if disc < 0.0: return INF
	var t:float = (-b-sqrt(disc))/length_sq
	return t if t>=0.0 and t<=1.0 else INF

func _physics_process(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	var targets:Array[ball] = []
	var has_interceptor:bool = get_tree().has_group("MinecraftAllay")
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or API.is_projectile(node) or not node.is_combat_targetable(): continue
		targets.append(node)
		if node.has_method("try_reflect_projectile") or node.has_method("try_block_projectile_hit"): has_interceptor = true
	if not has_interceptor: return
	for node:Node in API.candidates(get_tree()):
		if not node.is_multiplayer_authority() or not node is Node2D: continue
		if node.process_mode == Node.PROCESS_MODE_DISABLED or node.has_meta("_magnet_orbit_owner") or node.has_meta("mc_wool_flight"): continue
		if not node.can_process(): continue
		var shot:Node2D = node as Node2D
		var start:Vector2 = shot.global_position
		var finish:Vector2 = start+API.velocity_of(shot)*maxf(delta,0.0)
		if not start.is_equal_approx(finish):
			var query := PhysicsRayQueryParameters2D.create(start,finish,1)
			if shot is CollisionObject2D: query.exclude = [shot.get_rid()]
			var wall:Dictionary = shot.get_world_2d().direct_space_state.intersect_ray(query)
			if not wall.is_empty(): finish = wall.position
		var nearest:ball = null
		var nearest_t:float = INF
		for target:ball in targets:
			if not is_instance_valid(target) or not API.hostile(target,shot) or CONTACT.ignores(target): continue
			var target_radius:float = API.radius_of(target)
			var t:float = entry_fraction(start,finish,target.global_position,API.radius_of(shot)+target_radius)
			if t < nearest_t: nearest = target; nearest_t = t
		var stop:Vector2 = start.lerp(finish,nearest_t) if nearest != null else finish
		if get_tree().has_group("MinecraftAllay") and CAPTURE.sweep(shot,start,stop): continue
		if nearest == null: continue
		# Do not pre-roll ordinary dodge or damage: native contact owns those.
		if nearest.has_method("try_reflect_projectile") and nearest.call("try_reflect_projectile",shot): continue
		if nearest.has_method("try_block_projectile_hit") and nearest.call("try_block_projectile_hit",shot,stop,API.damage_of(shot)):
			API.retire(shot,nearest,stop)
