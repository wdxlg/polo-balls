extends RefCounted
## Category-driven interaction protocol. Legacy field adaptation lives HERE, never in a role.
const CLASSIFY = preload("res://classes/combat_classification.gd")
const PROPS = preload("res://classes/property_index.gd")
const LEGACY = preload("res://classes/projectile_legacy_adapters.gd")
const DIRECTIONS = ["direction","_direction","_dir","travel_direction","axis","forward"]
const SPEEDS = ["Speed","speed","_speed","projectile_speed","travel_speed","move_speed"]
const VELOCITIES = ["flight_velocity","_velocity","velocity","linear_velocity"]
const OWNERS = ["Master","_src_ref","_source_ref","_caster","owner_ref","source_witch","builder_owner","owner_teacher","collector","owner_ball","unit"]
const TEAMS = ["Team","team","_team","_source_team","projectile_team","collector_team"]
static var registries:Dictionary = {}

static func has_prop(node:Object,key:String) -> bool:
	return is_instance_valid(node) and PROPS.has_property(node,key)

static func is_projectile(node:Node) -> bool:
	return CLASSIFY.is_projectile(node)

static func live(node:Node) -> bool:
	if not is_projectile(node) or not node is Node2D: return false
	if node.has_meta("allay_frozen_context") or bool(node.get_meta("allay_captured",false)): return false
	if node is ball and node.health != null and float(node.health) <= 0.0: return false
	for key:String in ["_dead","_finished","_exploded","exploded","_landed","_spent"]:
		if has_prop(node,key) and node.get(key) is bool and node.get(key): return false
	var c:Dictionary = LEGACY.config(node)
	if c.has("ended") and bool(node.get(c.ended)): return false
	if c.has("active") and not bool(node.get(c.active)): return false
	if c.has("state") and int(node.get(c.state)) != int(c.state_value): return false
	return true

static func supports(node:Node,capability:String) -> bool:
	if not live(node): return false
	if node.has_method("projectile_supports"): return bool(node.call("projectile_supports",capability))
	var overrides:Dictionary = node.get_meta("projectile_capabilities",{})
	if overrides.has(capability): return bool(overrides[capability])
	if capability in ["reflect","redirect"]:
		if node.has_method("set_projectile_velocity"): return true
		for key:String in DIRECTIONS+VELOCITIES:
			if has_prop(node,key): return true
		return false
	if capability == "capture": return node.get_script() != null
	return capability in ["block","predict","wool"]

static func _register(node:Node,tree_id:int) -> void:
	if not registries.has(tree_id) or not is_instance_valid(node) or not node is Node2D: return
	var info:Dictionary = CLASSIFY.declared(node)
	if is_projectile(node) or info.has("stage_field") or node is ball:
		registries[tree_id].nodes[node.get_instance_id()] = weakref(node)

static func _added(node:Node,tree_id:int) -> void:
	_register(node,tree_id)
	_register_id.call_deferred(node.get_instance_id(),tree_id)

static func _register_id(node_id:int,tree_id:int) -> void:
	if is_instance_id_valid(node_id): _register(instance_from_id(node_id) as Node,tree_id)

static func _removed(node:Node,tree_id:int) -> void:
	if registries.has(tree_id): registries[tree_id].nodes.erase(node.get_instance_id())

static func _seed(node:Node,tree_id:int) -> void:
	_register(node,tree_id)
	for child:Node in node.get_children(): _seed(child,tree_id)

static func ensure(tree:SceneTree) -> void:
	if tree == null: return
	var id:int = tree.get_instance_id()
	if registries.has(id): return
	candidates(tree)

static func candidates(tree:SceneTree) -> Array[Node]:
	var result:Array[Node] = []
	if tree == null: return result
	var id:int = tree.get_instance_id()
	if not registries.has(id):
		for old:Variant in registries.keys():
			if not is_instance_valid(registries[old].tree.get_ref()): registries.erase(old)
		registries[id] = {"tree":weakref(tree),"nodes":{}}
		tree.node_added.connect(_added.bind(id))
		tree.node_removed.connect(_removed.bind(id))
		_seed(tree.root,id)
		var driver:Node = load("res://scripts/projectile_interaction_driver.gd").new()
		driver.name = "SharedProjectileInteractions"
		tree.root.add_child.call_deferred(driver)
	for key:Variant in registries[id].nodes.keys():
		var node:Node = registries[id].nodes[key].get_ref()
		if not is_instance_valid(node): registries[id].nodes.erase(key)
		elif node.is_inside_tree() and live(node): result.append(node)
	return result

static func velocity_of(node:Node) -> Vector2:
	if not is_instance_valid(node): return Vector2.ZERO
	if node.has_meta("mc_wool_flight"):
		var controller:Variant = node.get_meta("mc_wool_flight").get_ref()
		if is_instance_valid(controller): return controller.flight if controller.flying else Vector2.ZERO
	if node.has_method("get_projectile_velocity"): return node.call("get_projectile_velocity")
	for key:String in VELOCITIES:
		if has_prop(node,key) and node.get(key) is Vector2:
			var value:Vector2 = node.get(key)
			if value.length_squared() > 0.001: return value
	var heading:Vector2 = Vector2.ZERO
	for key:String in DIRECTIONS:
		if has_prop(node,key) and node.get(key) is Vector2:
			heading = node.get(key)
			if not heading.is_zero_approx(): break
	return heading.normalized()*speed_of(node)

static func speed_of(node:Node) -> float:
	if has_prop(node,"flight_velocity") and node.get("flight_velocity") is Vector2: return Vector2(node.get("flight_velocity")).length()
	if node.has_method("get_projectile_velocity"): return Vector2(node.call("get_projectile_velocity")).length()
	for key:String in SPEEDS:
		if has_prop(node,key) and (node.get(key) is float or node.get(key) is int): return absf(float(node.get(key)))
	for key:String in VELOCITIES:
		if has_prop(node,key) and node.get(key) is Vector2: return Vector2(node.get(key)).length()
	return 0.0

static func direction_of(node:Node) -> Vector2:
	var motion:Vector2 = velocity_of(node)
	if not motion.is_zero_approx(): return motion.normalized()
	for key:String in DIRECTIONS:
		if has_prop(node,key) and node.get(key) is Vector2 and not Vector2(node.get(key)).is_zero_approx(): return Vector2(node.get(key)).normalized()
	return node.get_meta("projectile_saved_direction",Vector2.RIGHT)

static func set_velocity(node:Node,motion:Vector2) -> bool:
	if not supports(node,"redirect"): return false
	var heading:Vector2 = motion.normalized() if not motion.is_zero_approx() else direction_of(node)
	node.set_meta("projectile_saved_direction",heading)
	if node.has_method("set_projectile_velocity"):
		node.call("set_projectile_velocity",motion)
		return true
	for key:String in DIRECTIONS:
		if has_prop(node,key) and node.get(key) is Vector2: node.set(key,heading)
	for key:String in SPEEDS:
		if has_prop(node,key): node.set(key,motion.length())
	for key:String in VELOCITIES:
		if has_prop(node,key) and node.get(key) is Vector2: node.set(key,motion)
	if has_prop(node,"max_speed"): node.set("max_speed",maxf(float(node.get("max_speed")),motion.length()))
	if node is Node2D: node.global_rotation = heading.angle()+(float(node.get("Default_Rotation")) if has_prop(node,"Default_Rotation") else 0.0)
	return true

static func set_direction(node:Node,heading:Vector2) -> void:
	heading = heading.normalized() if not heading.is_zero_approx() else Vector2.RIGHT
	node.set_meta("projectile_saved_direction",heading)
	set_velocity(node,heading*speed_of(node))

static func set_speed(node:Node,speed:float) -> void:
	set_velocity(node,direction_of(node)*maxf(speed,0.0))

static func source_of(node:Node) -> Node:
	if not is_instance_valid(node): return null
	if node.has_method("get_projectile_source"): return node.call("get_projectile_source")
	if has_prop(node,"launch_owner_id"):
		var source_id:int = int(node.get("launch_owner_id"))
		if source_id > 0 and is_instance_id_valid(source_id): return instance_from_id(source_id) as Node
	var c:Dictionary = LEGACY.config(node)
	var value:Variant = LEGACY.source(node,c) if not c.is_empty() else null
	if is_instance_valid(value): return value
	for key:String in OWNERS:
		if not has_prop(node,key): continue
		value = node.get(key)
		if typeof(value)==TYPE_OBJECT and not is_instance_valid(value): continue
		if value is WeakRef: value = value.get_ref()
		if is_instance_valid(value) and value is Node: return value
	for method:String in ["_source_ball","_resolve_master"]:
		if node.has_method(method):
			value = node.call(method)
			if is_instance_valid(value) and value is Node: return value
	return null

static func owner_of(node:Node) -> Node:
	var source:Node = source_of(node)
	if is_instance_valid(source) and source.has_meta("allay_frozen_context") and source is ball and is_instance_valid(source.Master): return source.Master
	return source

static func team_of(node:Node) -> String:
	if not is_instance_valid(node): return ""
	if node.has_meta("forced_combat_team"): return str(node.get_meta("forced_combat_team"))
	if node.has_method("get_projectile_team"): return str(node.call("get_projectile_team"))
	for key:String in TEAMS:
		if has_prop(node,key):
			var team:String = str(node.get(key)).strip_edges()
			if not team.is_empty() and team != "Ball": return team
	var source:Node = source_of(node)
	return str(source.Team) if source is ball else ""

static func hostile(receiver:ball,node:Node) -> bool:
	var source:Node = source_of(node)
	if node == receiver or source == receiver: return false
	if source is ball and (source.Master == receiver or receiver.Master == source): return false
	var team:String = team_of(node)
	return receiver.Team.is_empty() or team.is_empty() or team != receiver.Team

static func bind_owner(node:Node,source:ball,team:String,target:ball = null) -> void:
	if node.has_method("bind_projectile_owner"):
		node.call("bind_projectile_owner",source,team,target)
	else:
		for key:String in OWNERS:
			if not has_prop(node,key): continue
			var old:Variant = node.get(key)
			if typeof(old)==TYPE_OBJECT and not is_instance_valid(old): old = null
			node.set(key,weakref(source) if source != null and (old is WeakRef or key in ["_src_ref","_source_ref","_caster","owner_ref"]) else source)
		for key:String in TEAMS:
			if has_prop(node,key): node.set(key,team)
		if has_prop(node,"Master_name"):
			node.set("Master_name",str(source.get_tree().current_scene.get_path_to(source)) if is_instance_valid(source) and source.is_inside_tree() else "")
		if has_prop(node,"launch_owner_id"): node.set("launch_owner_id",source.get_instance_id() if is_instance_valid(source) else 0)
		if has_prop(node,"Target_Enemy"): node.set("Target_Enemy",target)
		for key:String in ["target_ref","_target_ref"]:
			if has_prop(node,key): node.set(key,weakref(target) if is_instance_valid(target) else null)
		if has_prop(node,"Ignore_Team_Damage_Setting"): node.set("Ignore_Team_Damage_Setting",true)
		if has_prop(node,"_force_no_friendly_fire"): node.set("_force_no_friendly_fire",true)
	node.set_meta("forced_combat_team",team)

static func damage_kind_of(node:Node) -> String:
	var kind:String = ""
	if node.has_method("get_projectile_damage_kind"): kind = str(node.call("get_projectile_damage_kind"))
	elif node.has_meta("projectile_damage_kind"): kind = str(node.get_meta("projectile_damage_kind"))
	elif node.get_script() != null: kind = str(LEGACY.PAYLOAD_KINDS.get(node.get_script().resource_path,"ordinary"))
	kind = CLASSIFY.canonical_damage_kind(kind)
	return kind if not kind.is_empty() else "ordinary"

static func damage_of(node:Node) -> float:
	if node.has_method("get_projectile_damage"): return maxf(float(node.call("get_projectile_damage")),0.0)
	var c:Dictionary = LEGACY.config(node)
	if c.has("damage"): return maxf(float(node.get(c.damage)),0.0)
	if c.has("multiplier"):
		var source:Node = source_of(node)
		if source is ball: return source.attack_damage(float(node.get(c.multiplier)))
	if c.has("damage_value"): return float(c.damage_value)
	if has_prop(node,"_damage_multiplier"):
		var source:Node = source_of(node)
		if source is ball: return source.attack_damage(float(node.get("_damage_multiplier")))
	if node is ball: return node.attack_damage()
	for key:String in ["_direct_damage","_damage","damage_amount","Damage","impact_damage","enemy_damage","damage"]:
		if has_prop(node,key) and (node.get(key) is int or node.get(key) is float): return maxf(float(node.get(key)),0.0)
	return 0.0

static func radius_of(node:Node2D) -> float:
	if node.has_method("get_projectile_radius"): return maxf(float(node.call("get_projectile_radius")),1.0)
	var collider:CollisionShape2D = node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collider != null and collider.shape != null:
		return maxf((collider.shape.get_rect().size*collider.global_scale.abs()).x*0.5,1.0)
	return maxf(float(node.get_meta("manual_training_radius",LEGACY.config(node).get("radius",4.0))),1.0)

static func capture_descriptor(node:Node) -> Dictionary:
	if not supports(node,"capture"): return {}
	if node.is_inside_tree() and not node.is_multiplayer_authority(): return {}
	var c:Dictionary = LEGACY.config(node)
	if c.has("authority") and not bool(node.get(c.authority)): return {}
	return {"kind":"native","damage":damage_of(node),"speed":speed_of(node),"damage_kind":damage_kind_of(node)}

static func retire(node:Node,target:ball = null,point:Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return
	if node.has_method("on_projectile_blocked_by"):
		node.call("on_projectile_blocked_by",target,point)
		return
	# Retirement is NOT explosion/Die; rejection must not spawn a secondary attack.
	if node.has_method("retire"): node.call("retire")
	elif node.has_method("expire"): node.call("expire")
	else:
		node.set_physics_process(false)
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.queue_free()

static func reflect(node:Node2D,receiver:ball,push_out:float) -> bool:
	if not receiver.is_multiplayer_authority() or not node.is_multiplayer_authority() or not supports(node,"reflect"): return false
	var previous:Node = source_of(node)
	var heading:Vector2 = -direction_of(node)
	if heading.is_zero_approx(): heading = Vector2.RIGHT
	# Preserve native callbacks/attack context without retaining the old actor.
	# The isolated source is owned by receiver; it has no AI/body/attacks.
	var native:Script = load("res://scripts/characters/我的世界/allay/native_return.gd")
	var data:Dictionary = native.snapshot(node,{})
	var context:ball = native.context_for(receiver,data)
	if context == null: return false
	bind_owner(node,context,receiver.Team,previous as ball)
	if context != receiver:
		context.set_meta("allay_context_shot",weakref(node))
		if has_prop(context,"_tridents") and has_prop(node,"serial"):
			context.set("_trident",node)
			context.get("_tridents")[node.get("serial")] = node
	node.global_position = receiver.global_position+heading*maxf(push_out,4.0)
	set_velocity(node,heading*maxf(speed_of(node),1.0))
	if has_prop(node,"Repel"): node.set("Repel",Vector2.ZERO)
	node.set_meta("projectile_reflected_frame",Engine.get_physics_frames())
	return true

static func defense(node:Node2D,target:ball,point:Vector2) -> String:
	if not live(node) or not is_instance_valid(target) or not target.is_multiplayer_authority() or not node.is_multiplayer_authority(): return ""
	if preload("res://scripts/projectile_contact.gd").ignores(target): return "dodge"
	if target.has_method("try_full_projectile_dodge") and target.call("try_full_projectile_dodge",node): return "dodge"
	if target.has_method("try_reflect_projectile") and target.call("try_reflect_projectile",node): return "reflect"
	if target.has_method("try_block_projectile_hit") and target.call("try_block_projectile_hit",node,point,damage_of(node)):
		retire(node,target,point)
		return "block"
	return ""
