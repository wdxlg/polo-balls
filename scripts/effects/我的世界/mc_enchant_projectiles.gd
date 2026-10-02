extends Node
## Shared Multishot / Piercing runtime for EVERY projectile, independent of the shooter.
## A projectile is any node the combat classification marks as projectile; its owner is
## resolved through classes/projectile_interactions.gd and the Master chain.
##   Multishot n>0: each shot becomes n+1 shots spread evenly from -45 to +45 degrees.
##   Multishot n<0: each shot is kept with chance 1/(|n|+1), otherwise retired before it flies.
##   Piercing  n>0: after a character hit destroys the shot, a continuation is spawned past
##                  the target (it skips every pierced target) until n extra characters are hit.
##   Piercing  n<0: 10%/level that the shot shatters harmlessly on its first character hit.
## Clones are rebuilt from the shot's own scene/script plus a snapshot of its state taken
## right after the shooter configured it; references into its own subtree are not copied.
const CLASSIFY = preload("res://classes/combat_classification.gd")
const PROJECTILES = preload("res://classes/projectile_interactions.gd")
const EFFECTS = preload("res://scripts/effects/我的世界/mc_enchantment_effects.gd")
const ENCHANTS_PATH:String = "res://scripts/effects/我的世界/mc_enchantments.gd"
const NODE_NAME:String = "MCEnchantProjectiles"
const SKIP_PROPERTIES:Array[String] = ["script","name","owner","scene_file_path","unique_name_in_owner","health","block","multiplayer"]
const PIERCE_WINDOW_MS:int = 700

var _spawn_counts:Dictionary = {}
var _tracked:Dictionary = {} # projectile instance id -> pierce bookkeeping

static func ensure(tree:SceneTree) -> Node:
	if tree == null or tree.root == null: return null
	var existing:Node = tree.root.get_node_or_null(NODE_NAME)
	if existing != null: return existing
	var runtime:Node = load("res://scripts/effects/我的世界/mc_enchant_projectiles.gd").new()
	runtime.name = NODE_NAME
	tree.root.add_child.call_deferred(runtime)
	return runtime

static func find(tree:SceneTree) -> Node:
	return tree.root.get_node_or_null(NODE_NAME) if tree != null and tree.root != null else null

func _enter_tree() -> void:
	if not get_tree().node_added.is_connected(_on_node_added): get_tree().node_added.connect(_on_node_added)

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added): get_tree().node_added.disconnect(_on_node_added)

func _on_node_added(node:Node) -> void:
	if not (node is Node2D) or node.has_meta("mc_enchant_inspected") or not CLASSIFY.is_projectile(node): return
	# Shooters often set owner/velocity right after add_child; inspect once that call returns.
	_inspect.call_deferred(node.get_instance_id())

static func _enchants() -> Script:
	return load(ENCHANTS_PATH)

func _levels_for(node:Node) -> Dictionary:
	var source:Node = PROJECTILES.owner_of(node)
	if not is_instance_valid(source): source = node
	var caster:Node = _enchants()._caster_of(source)
	if not (caster is ball): return {}
	return {"caster":caster,"levels":_enchants()._combat_levels(caster,node)}

func _inspect(id:int) -> void:
	if not is_instance_id_valid(id): return
	var node:Node2D = instance_from_id(id) as Node2D
	if node == null or not node.is_inside_tree() or node.is_queued_for_deletion() or node.has_meta("mc_enchant_inspected"): return
	node.set_meta("mc_enchant_inspected",true)
	var found:Dictionary = _levels_for(node)
	if found.is_empty(): return
	var levels:Dictionary = found.levels
	var multishot:int = int(levels.get("multishot",0))
	var piercing:int = int(levels.get("piercing",0))
	if multishot == 0 and piercing == 0: return
	# Replicated shots are shaped once by their authority; clones replicate like any other shot.
	if not node.is_multiplayer_authority(): return
	var caster:ball = found.caster
	var count:int = int(_spawn_counts.get(caster.get_instance_id(),0))
	_spawn_counts[caster.get_instance_id()] = count+1
	if piercing < 0: node.set_meta("mc_fizzle_chance",clampf(-0.10*piercing,0.0,1.0))
	if multishot < 0:
		# Deterministic per shooter and shot index so every peer drops the same shots.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|%d|ms" % [caster.name,count])
		if rng.randf() >= EFFECTS.multishot_keep_chance(multishot):
			PROJECTILES.retire(node)
			return
	var recipe:Dictionary = snapshot(node)
	if piercing > 0: _track(node,recipe,piercing,[])
	if multishot <= 0: return
	var angles:Array[float] = EFFECTS.multishot_angles(multishot)
	var base_velocity:Vector2 = PROJECTILES.velocity_of(node)
	for index:int in range(1,angles.size()):
		var clone:Node2D = spawn_from(node,recipe)
		if clone == null: break
		_turn(clone,angles[index],base_velocity)
		if piercing > 0: _track(clone,recipe,piercing,[])
	_turn(node,angles[0],base_velocity)

## Rotates a shot's travel (and its visual heading) by `angle` radians.
static func _turn(node:Node2D,angle:float,base_velocity:Vector2) -> void:
	if is_zero_approx(angle) or not is_instance_valid(node): return
	if not base_velocity.is_zero_approx() and PROJECTILES.set_velocity(node,base_velocity.rotated(angle)): return
	node.global_rotation += angle

## Snapshot of a configured projectile: script variables and stored properties, minus
## references into its own subtree (the clone builds its own children).
static func snapshot(node:Node) -> Dictionary:
	var props:Dictionary = {}
	for info:Dictionary in node.get_property_list():
		var usage:int = int(info.usage)
		if (usage & (PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_STORAGE)) == 0: continue
		var key:String = str(info.name)
		if key in SKIP_PROPERTIES: continue
		var value:Variant = node.get(key)
		if typeof(value) == TYPE_OBJECT:
			if not is_instance_valid(value): continue
			if value is Node and (value == node or node.is_ancestor_of(value)): continue
		elif value is Array or value is Dictionary:
			value = value.duplicate()
		props[key] = value
	var metas:Dictionary = {}
	for key:StringName in node.get_meta_list():
		if not String(key).begins_with("mc_enchant") and not String(key).begins_with("mc_pierce") and key != &"mc_fizzle_chance":
			metas[key] = node.get_meta(key)
	var groups:Array[StringName] = []
	for group:StringName in node.get_groups():
		if not String(group).begins_with("_"): groups.append(group)
	return {"props":props,"metas":metas,"groups":groups,"scene":node.scene_file_path,"script":node.get_script(),"transform":(node as Node2D).global_transform if node is Node2D else Transform2D.IDENTITY}

## Builds a sibling copy of `node` from its recipe. Returns null when the shot cannot be rebuilt.
static func spawn_from(node:Node,recipe:Dictionary) -> Node2D:
	var parent:Node = node.get_parent() if is_instance_valid(node) else null
	if parent == null or not parent.is_inside_tree(): return null
	return spawn_recipe(parent,recipe)

static func spawn_recipe(parent:Node,recipe:Dictionary) -> Node2D:
	var clone:Node = null
	var scene_path:String = str(recipe.get("scene",""))
	if not scene_path.is_empty():
		var packed:PackedScene = load(scene_path) as PackedScene
		if packed != null: clone = packed.instantiate()
	else:
		var script:Script = recipe.get("script") as Script
		if script == null or not script.can_instantiate() or _init_arity(script) > 0: return null
		clone = script.new()
	if not (clone is Node2D):
		if clone != null: clone.free()
		return null
	for key:String in recipe.props:
		if key in clone: clone.set(key,recipe.props[key])
	for key:StringName in recipe.metas: clone.set_meta(key,recipe.metas[key])
	for group:StringName in recipe.groups: clone.add_to_group(group,true)
	clone.set_meta("mc_enchant_inspected",true)
	clone.set_meta("mc_projectile_clone",true)
	parent.add_child(clone,true)
	(clone as Node2D).global_transform = recipe.transform
	return clone as Node2D

static func _init_arity(script:Script) -> int:
	for method:Dictionary in script.get_script_method_list():
		if str(method.name) == "_init":
			var required:int = (method.args as Array).size()-(method.default_args as Array).size()
			return maxi(required,0)
	return 0

func _track(node:Node2D,recipe:Dictionary,remaining:int,pierced:Array) -> void:
	if not is_instance_valid(node): return
	var id:int = node.get_instance_id()
	_tracked[id] = {"node":weakref(node),"parent":weakref(node.get_parent()),"recipe":recipe,"remaining":remaining,"pierced":pierced.duplicate(),
		"position":node.global_position,"velocity":PROJECTILES.velocity_of(node),"pending":false,"hit_ms":0,"target":null}
	if not pierced.is_empty(): node.set_meta("mc_pierce_ignore",pierced.duplicate())
	var exit_cb:Callable = _on_tracked_exit.bind(id)
	if not node.tree_exiting.is_connected(exit_cb): node.tree_exiting.connect(exit_cb)
	set_physics_process(true)

func _physics_process(delta:float) -> void:
	if _tracked.is_empty():
		set_physics_process(false)
		return
	for id:int in _tracked.keys():
		if not _tracked.has(id): continue
		var entry:Dictionary = _tracked[id]
		var node:Node2D = entry.node.get_ref() as Node2D
		if not is_instance_valid(node):
			_tracked.erase(id)
			if entry.pending: _continue(entry)
			continue
		var motion:Vector2 = PROJECTILES.velocity_of(node)
		# Shots that move by transform expose no velocity field: use the frame displacement.
		var displaced:Vector2 = (node.global_position-Vector2(entry.position))/delta if delta > 0.0 else Vector2.ZERO
		if motion.is_zero_approx(): motion = displaced
		entry.position = node.global_position
		if entry.pending:
			# The hit stopped this shot (destroyed, embedded, spent or stalled): continue past the target.
			var speed:float = Vector2(entry.velocity).length()
			var stalled:bool = displaced.length() < speed*0.25
			if node.is_queued_for_deletion() or not PROJECTILES.live(node) or stalled:
				_tracked.erase(id)
				_disconnect_exit(node,id)
				_continue(entry)
			elif Time.get_ticks_msec()-int(entry.hit_ms) > PIERCE_WINDOW_MS:
				entry.pending = false # It kept flying through: nothing to continue.
		elif not motion.is_zero_approx():
			entry.velocity = motion

func _disconnect_exit(node:Node,id:int) -> void:
	var exit_cb:Callable = _on_tracked_exit.bind(id)
	if is_instance_valid(node) and node.tree_exiting.is_connected(exit_cb): node.tree_exiting.disconnect(exit_cb)

## Called by ball damage hooks after a projectile landed damage on a character.
func note_hit(source:Node,target:ball) -> void:
	var id:int = source.get_instance_id()
	if not _tracked.has(id): return
	var entry:Dictionary = _tracked[id]
	var target_id:int = target.get_instance_id()
	if not entry.pierced.has(target_id): entry.pierced.append(target_id)
	source.set_meta("mc_pierce_ignore",entry.pierced.duplicate())
	entry.pending = int(entry.remaining) > 0
	entry.hit_ms = Time.get_ticks_msec()
	entry.target = weakref(target)

func _on_tracked_exit(id:int) -> void:
	if not _tracked.has(id): return
	var entry:Dictionary = _tracked[id]
	if not entry.pending: return # Exits without a fresh hit (walls, lifetime, reparenting) end here.
	_tracked.erase(id)
	_continue.call_deferred(entry)

func _continue(entry:Dictionary) -> void:
	var parent:Node = entry.parent.get_ref() as Node
	var heading:Vector2 = Vector2(entry.velocity).normalized()
	if not is_instance_valid(parent) or not parent.is_inside_tree() or heading.is_zero_approx() or int(entry.remaining) <= 0: return
	var start:Vector2 = entry.position
	var target:Node2D = entry.target.get_ref() as Node2D if entry.target is WeakRef else null
	if is_instance_valid(target):
		# Emerge on the far side of the pierced body so the copy does not touch it again.
		var radius:float = float(target.call("_hit_burst_character_radius")) if target.has_method("_hit_burst_character_radius") else 40.0
		start = target.global_position+heading*(radius+18.0)
	var recipe:Dictionary = entry.recipe.duplicate()
	var original:Transform2D = entry.recipe.transform
	recipe.transform = Transform2D(heading.angle(),original.get_scale(),original.get_skew(),start)
	var clone:Node2D = spawn_recipe(parent,recipe)
	if clone == null: return
	clone.global_position = start
	PROJECTILES.set_velocity(clone,Vector2(entry.velocity))
	_track(clone,entry.recipe,int(entry.remaining)-1,entry.pierced)

## Hit gate used by every damage path: pierced targets are skipped, inverse Piercing may
## shatter the shot on its first character hit.
static func allow_hit(source:Node,target:Node) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target): return true
	if source.has_meta("mc_pierce_ignore") and (source.get_meta("mc_pierce_ignore") as Array).has(target.get_instance_id()): return false
	if source.has_meta("mc_fizzle_chance") and not source.has_meta("mc_fizzle_rolled"):
		source.set_meta("mc_fizzle_rolled",true)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|%d|fz" % [str(source.name),target.get_instance_id()])
		if rng.randf() < float(source.get_meta("mc_fizzle_chance")):
			source.set_meta("mc_enchant_fizzled",true)
			PROJECTILES.retire(source)
	return not source.has_meta("mc_enchant_fizzled")
