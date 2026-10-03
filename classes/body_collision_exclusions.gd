extends RefCounted
## All body exceptions share a lifetime registry; never enumerate native exception Nodes.
## Godot can retain a freed RID in that list, and converting it to a Node raises an engine error.
const META:StringName = &"body_pair_exclusions"
const NATIVE_META:StringName = &"body_native_exclusions"
const EXTERNAL_META:StringName = &"body_external_exclusions"

static func add_exception(a:PhysicsBody2D,b:PhysicsBody2D) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b: return
	var external:Dictionary = a.get_meta(EXTERNAL_META,{})
	external[b.get_instance_id()] = true
	a.set_meta(EXTERNAL_META,external)
	_ensure_native(a,b)

static func remove_exception(a:PhysicsBody2D,b:PhysicsBody2D) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b): return
	_erase(a,EXTERNAL_META,b.get_instance_id())
	_prune_native(a,b)

static func has_exception(a:PhysicsBody2D,b:PhysicsBody2D) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b): return false
	return a.get_meta(NATIVE_META,{}).has(b.get_instance_id())

static func are_excluded(a:PhysicsBody2D,b:PhysicsBody2D) -> bool:
	return has_exception(a,b) or has_exception(b,a)

static func acquire(a:PhysicsBody2D,b:PhysicsBody2D,holder:Node) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b or not is_instance_valid(holder): return
	_acquire_one(a,b,holder)
	_acquire_one(b,a,holder)
	var cleanup:Callable = release.bind(a,b,holder)
	for node:Node in [a,b,holder]:
		if not node.tree_exiting.is_connected(cleanup): node.tree_exiting.connect(cleanup)

static func release(a:PhysicsBody2D,b:PhysicsBody2D,holder:Node) -> void:
	if not is_instance_valid(holder): return
	_release_one(a,b,holder)
	_release_one(b,a,holder)
	var cleanup:Callable = release.bind(a,b,holder)
	for node:Variant in [a,b,holder]:
		if is_instance_valid(node) and node.tree_exiting.is_connected(cleanup): node.tree_exiting.disconnect(cleanup)

static func _acquire_one(body:PhysicsBody2D,other:PhysicsBody2D,holder:Node) -> void:
	var pairs:Dictionary = body.get_meta(META,{})
	var id:int = other.get_instance_id()
	if not pairs.has(id): pairs[id] = {}
	pairs[id][holder.get_instance_id()] = true
	body.set_meta(META,pairs)
	_ensure_native(body,other)

static func _release_one(body:PhysicsBody2D,other:PhysicsBody2D,holder:Node) -> void:
	if not is_instance_valid(body) or not is_instance_valid(other): return
	var pairs:Dictionary = body.get_meta(META,{})
	var id:int = other.get_instance_id()
	if not pairs.has(id): return
	pairs[id].erase(holder.get_instance_id())
	if pairs[id].is_empty(): _erase(body,META,id)
	_prune_native(body,other)

static func _ensure_native(body:PhysicsBody2D,other:PhysicsBody2D) -> void:
	var entries:Dictionary = body.get_meta(NATIVE_META,{})
	var id:int = other.get_instance_id()
	if entries.has(id): return
	var body_ref:WeakRef = weakref(body)
	var other_ref:WeakRef = weakref(other)
	var cleanup:Callable = func(): _native_tree_exit(body_ref,other_ref,id)
	entries[id] = {"rid":other.get_rid(),"other":weakref(other),"cleanup":cleanup}
	body.set_meta(NATIVE_META,entries)
	body.add_collision_exception_with(other)
	body.tree_exiting.connect(cleanup)
	other.tree_exiting.connect(cleanup)

static func _prune_native(body:PhysicsBody2D,other:PhysicsBody2D) -> void:
	var id:int = other.get_instance_id()
	if body.get_meta(META,{}).has(id) or body.get_meta(EXTERNAL_META,{}).has(id): return
	_forget_native(weakref(body),weakref(other),id)

static func _native_tree_exit(body_ref:WeakRef,other_ref:WeakRef,id:int) -> void:
	var body:PhysicsBody2D = body_ref.get_ref() as PhysicsBody2D
	var other:PhysicsBody2D = other_ref.get_ref() as PhysicsBody2D
	var retain:bool = is_instance_valid(body) and is_instance_valid(other) and not body.is_queued_for_deletion() and not other.is_queued_for_deletion() and body.get_meta(EXTERNAL_META,{}).has(id)
	_forget_native(body_ref,other_ref,id,retain)
	# Reparenting is not destruction. Restore a live caller-owned exception after
	# re-entry, unless its caller explicitly removed it while the tree was changing.
	if retain: _restore_after_reparent.call_deferred(body_ref,other_ref,id)

static func _restore_after_reparent(body_ref:WeakRef,other_ref:WeakRef,id:int) -> void:
	var body:PhysicsBody2D = body_ref.get_ref() as PhysicsBody2D
	if not is_instance_valid(body) or not body.get_meta(EXTERNAL_META,{}).has(id): return
	var other:PhysicsBody2D = other_ref.get_ref() as PhysicsBody2D
	if is_instance_valid(other) and body.is_inside_tree() and other.is_inside_tree():
		_ensure_native(body,other)
	else:
		_erase(body,EXTERNAL_META,id)

static func _forget_native(body_ref:WeakRef,other_ref:WeakRef,id:int,retain_external:bool=false) -> void:
	var body:PhysicsBody2D = body_ref.get_ref() as PhysicsBody2D
	if not is_instance_valid(body): return
	var entries:Dictionary = body.get_meta(NATIVE_META,{})
	if not entries.has(id): return
	var entry:Dictionary = entries[id]
	# The exception RID need not resolve to a live object to remove it.
	PhysicsServer2D.body_remove_collision_exception(body.get_rid(),entry.rid)
	var other:PhysicsBody2D = other_ref.get_ref() as PhysicsBody2D
	for node:PhysicsBody2D in [body,other]:
		if is_instance_valid(node) and node.tree_exiting.is_connected(entry.cleanup): node.tree_exiting.disconnect(entry.cleanup)
	for key:StringName in [NATIVE_META,META]: _erase(body,key,id)
	if not retain_external: _erase(body,EXTERNAL_META,id)

static func _erase(body:PhysicsBody2D,key:StringName,id:int) -> void:
	if not body.has_meta(key): return
	var entries:Dictionary = body.get_meta(key)
	entries.erase(id)
	if entries.is_empty(): body.remove_meta(key)
