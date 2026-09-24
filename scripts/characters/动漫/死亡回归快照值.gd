extends RefCounted
## Graph codec: preserve aliases/cycles, weak references, RNG state and typed containers.
var world:Node
var paths:Dictionary = {}
var objects:Array[Dictionary] = []
var unsupported:Dictionary = {}
var _sources:Array = []
var _source_buckets:Dictionary = {}
var _decoded:Dictionary = {}
var _resource_versions:Dictionary = {}
var _resource_watch:Dictionary = {}
var roots:Dictionary = {}
var _rng_decoded:Dictionary = {}
func encode(value:Variant) -> Variant:
	var kind:int = typeof(value)
	if kind != TYPE_OBJECT and kind != TYPE_ARRAY and kind != TYPE_DICTIONARY and kind != TYPE_CALLABLE:
		return {"$instance":paths[value]} if kind == TYPE_INT and paths.has(value) else value
	if typeof(value) == TYPE_OBJECT and not is_instance_valid(value): return null
	if value is Node:
		if not is_instance_valid(value): return null
		if paths.has(value.get_instance_id()): return {"$node":paths[value.get_instance_id()]}
		if not value.is_inside_tree(): return value # Detached resource/prewarm prototypes are not live battle entities.
		return {"$node":[0,world.get_path_to(value) if world.is_ancestor_of(value) else value.get_path()]}
	if value is WeakRef:
		return {"$weak":encode(value.get_ref())}
	if value is RandomNumberGenerator:
		return {"$rng":[value.seed,value.state,value.get_instance_id()]}
	if value is Array or value is Dictionary:
		# Bucket by structure, not recursively hashing values (cycles are allowed).
		var bucket_key:int = hash(value)
		var bucket:Array = _source_buckets.get(bucket_key,[])
		for i:int in bucket:
			if is_same(_sources[i],value): return {"$container":i}
		var index:int = objects.size()
		bucket.append(index)
		_source_buckets[bucket_key] = bucket
		_sources.append(value)
		var template:Variant = value.duplicate(false)
		template.clear()
		objects.append({"template":template,"items":[]})
		var items:Array = []
		if value is Array:
			for item:Variant in value: items.append(encode(item))
		else:
			for key:Variant in value: items.append([encode(key),encode(value[key])])
		objects[index].items = items
		return {"$container":index}
	if value is Callable:
		if value.is_valid() and value.get_object() is Node and not str(value.get_method()).contains("lambda"): return {"$call":[encode(value.get_object()),value.get_method(),encode(value.get_bound_arguments())]}
		unsupported["Callable/closure"] = true
		return null
	if value is Resource:
		if value is Shape2D or value is Material or value is Curve or value is Gradient:
			var id:int = value.get_instance_id()
			if not _resource_versions.has(id): _resource_versions[id] = value.duplicate(true)
			if not _resource_watch.has(id):
				_resource_watch[id] = true
				value.changed.connect(_invalidate_resource.bind(id))
			return _resource_versions[id]
		return value
	if value is Object:
		if is_instance_valid(value): unsupported[value.get_class()] = true
		return null
	if value is int and paths.has(value): return {"$instance":paths[value]}
	return value
func _invalidate_resource(id:int) -> void:
	_resource_versions.erase(id)

func begin_decode(pool:Array,root_map:Dictionary) -> void:
	objects.assign(pool)
	roots = root_map
	_decoded.clear()
	_rng_decoded.clear()
func _decode_container(index:int) -> Variant:
	if _decoded.has(index): return _decoded[index]
	var descriptor:Dictionary = objects[index]
	var container:Variant = descriptor.template.duplicate(false)
	_decoded[index] = container
	if container is Array:
		for item:Variant in descriptor.items: container.append(decode(item))
	else:
		for pair:Array in descriptor.items:
			var key:Variant = decode(pair[0])
			if key != null: container[key] = decode(pair[1])
	return container
func resolve(address:Array) -> Node:
	var root:Node = world if int(address[0]) == 0 else roots.get(int(address[0]))
	return root.get_node_or_null(address[1]) if is_instance_valid(root) else null
func decode(value:Variant) -> Variant:
	if not value is Dictionary:
		return value.duplicate(true) if value is Shape2D or value is Material or value is Curve or value is Gradient else value
	if value.has("$container"): return _decode_container(int(value["$container"]))
	if value.has("$node"): return resolve(value["$node"])
	if value.has("$instance"):
		var node:Node = resolve(value["$instance"])
		return node.get_instance_id() if node != null else 0
	if value.has("$weak"): return weakref(decode(value["$weak"]))
	if value.has("$rng"):
		var id:int = value["$rng"][2]
		if not _rng_decoded.has(id):
			var rng := RandomNumberGenerator.new()
			rng.seed = value["$rng"][0]
			rng.state = value["$rng"][1]
			_rng_decoded[id] = rng
		return _rng_decoded[id]
	if value.has("$call"):
		var data:Array = value["$call"]
		var target:Variant = decode(data[0])
		return Callable(target,data[1]).bindv(decode(data[2])) if is_instance_valid(target) else Callable()
	return value
