extends RefCounted
## Temporary, owner-keyed BODY pair exclusions. Hurt/attack Areas and masks are untouched.
## Each caller releases its own lease; existing external exceptions are preserved.
const META:StringName = &"body_pair_exclusions"

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

static func are_excluded(a:PhysicsBody2D,b:PhysicsBody2D) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b) or not a.has_meta(META): return false
	var pairs:Dictionary = a.get_meta(META)
	return pairs.has(b.get_instance_id())

static func _acquire_one(body:PhysicsBody2D,other:PhysicsBody2D,holder:Node) -> void:
	var pairs:Dictionary = body.get_meta(META) if body.has_meta(META) else {}
	var id:int = other.get_instance_id()
	if not pairs.has(id):
		var added:bool = not body.get_collision_exceptions().has(other)
		pairs[id] = {"holders":{},"added":added}
		if added: body.add_collision_exception_with(other)
	pairs[id].holders[holder.get_instance_id()] = true
	body.set_meta(META,pairs)

static func _release_one(body:PhysicsBody2D,other:PhysicsBody2D,holder:Node) -> void:
	if not is_instance_valid(body) or not is_instance_valid(other) or not body.has_meta(META): return
	var pairs:Dictionary = body.get_meta(META)
	var id:int = other.get_instance_id()
	if not pairs.has(id): return
	pairs[id].holders.erase(holder.get_instance_id())
	if pairs[id].holders.is_empty():
		if pairs[id].added: body.remove_collision_exception_with(other)
		pairs.erase(id)
	if pairs.is_empty(): body.remove_meta(META)
