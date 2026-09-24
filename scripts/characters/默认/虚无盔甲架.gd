extends "res://scripts/characters/默认/盔甲架.gd"

# 虚无盔甲架：不透明度75%的普通盔甲架。
# 没有血条、完全不会掉血、投射物无法命中（直接穿过），但敌人仍会正常索敌并近战攻击它。
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")
var _void_projectile_bodies:Dictionary = {}
@export_range(0.0,1.0,0.01) var void_opacity:float = 0.75

func _ready() -> void:
	super._ready()
	modulate.a = void_opacity
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.visible = false
	add_to_group(PROJECTILE_CONTACT.INTANGIBLE_GROUP)
	tree_entered.connect(_void_begin_projectile_watch)
	_void_begin_projectile_watch()

func _void_begin_projectile_watch() -> void:
	# _ready is one-shot; a reused/reparented stand still needs a live watcher.
	if not get_tree().node_added.is_connected(_void_watch_projectile_body):
		get_tree().node_added.connect(_void_watch_projectile_body)
	if not tree_exiting.is_connected(_void_clear_projectile_bodies):
		tree_exiting.connect(_void_clear_projectile_bodies,CONNECT_ONE_SHOT)
	for node:Node in get_tree().root.find_children("*","PhysicsBody2D",true,false):
		_void_watch_projectile_body(node)

# ---------- 完全不会掉血 / 不会死亡 ----------
func take_damage(_damage:float,_ignore_block:bool = false) -> void:
	pass

func receive_positional_damage(_damage:float,_impact_position:Vector2,_ignore_block:bool = false,_source:Node = null) -> bool:
	return false

func receive_spatial_damage(_damage:float,_damage_space:Variant,_ignore_block:bool = false,_raw_health:bool = false) -> bool:
	return false

func receive_directional_damage(_damage:float,_source_position:Vector2,_incoming_direction:Vector2 = Vector2.ZERO,_ignore_block:bool = false) -> bool:
	return false

func on_actual_health_damage_received(_actual_health_damage:float,_health_before:float) -> void:
	# 兼容仍直接 target.health -= x 的旧入口：虚无盔甲架的生命值始终保持满值。
	if health < Max_health:
		health = Max_health

func get_next_state(state:State) -> int:
	if health <= 0:
		health = Max_health
	return super.get_next_state(state)

func Die() -> void:
	if health <= 0:
		health = Max_health
		return

# ---------- 投射物不命中，近战正常命中 ----------
func is_projectile_intangible() -> bool:
	return true

# Existing custom ray/distance projectiles already use this pass-through contract.
# This is passive immunity: no teleport, cooldown, charge consumption or feedback.
func try_full_projectile_dodge(_projectile:Node = null) -> bool:
	return true

func _void_projectile_hit(incoming_hit:hitbox) -> bool:
	if not is_instance_valid(incoming_hit): return false
	var node:Node = incoming_hit.get_parent()
	while is_instance_valid(node):
		if PROJECTILE_CONTACT.is_projectile(node): return true
		if node is ball: break
		node = node.get_parent()
	return PROJECTILE_CONTACT.is_projectile(incoming_hit.owner)

func can_receive_hit_contact(incoming_hit:hitbox,_contact_hurtbox:hurtbox) -> bool:
	return not _void_projectile_hit(incoming_hit)

func can_receive_hit_from(incoming_hit:hitbox) -> bool:
	return not _void_projectile_hit(incoming_hit)

func should_destroy_projectile_on_rejected_hit(_incoming_hit:hitbox) -> bool:
	return false

func on_incoming_hit_rejected(_incoming_hit:hitbox) -> void:
	# No contact occurred. The inherited rejection handler emits a block burst.
	pass

# PhysicsBody movement does not pass through hitbox.gd. Register both existing and
# newly spawned shots before their first movement, while keeping melee bodies solid.
func _void_watch_projectile_body(node:Node) -> void:
	if not node is PhysicsBody2D or node==self: return
	if node.is_node_ready():
		refresh_projectile_body_exception(node as PhysicsBody2D)
	else:
		var initialize:Callable = _void_projectile_ready.bind(node.get_instance_id())
		if not node.ready.is_connected(initialize): node.ready.connect(initialize,CONNECT_ONE_SHOT)
		# A pooled node re-enters without emitting ready again. Also retry after
		# this enter-tree stack, without caching an uninitialized projectile Type.
		_void_projectile_ready.call_deferred(node.get_instance_id())

func _void_projectile_ready(id:int) -> void:
	if not is_inside_tree() or not is_instance_id_valid(id): return
	var body:Object = instance_from_id(id)
	if body is PhysicsBody2D: refresh_projectile_body_exception(body as PhysicsBody2D)

func refresh_projectile_body_exception(body:PhysicsBody2D) -> void:
	if not is_instance_valid(body) or body==self or not body.is_inside_tree(): return
	var id:int = body.get_instance_id()
	if not PROJECTILE_CONTACT.is_projectile(body):
		_void_forget_projectile_body(id)
		return
	if _void_projectile_bodies.has(id): return
	body.add_collision_exception_with(self)
	add_collision_exception_with(body)
	_void_projectile_bodies[id] = weakref(body)
	var exiting:Callable = _void_forget_projectile_body.bind(id)
	if not body.tree_exiting.is_connected(exiting): body.tree_exiting.connect(exiting,CONNECT_ONE_SHOT)

func _void_forget_projectile_body(id:int) -> void:
	var reference:WeakRef = _void_projectile_bodies.get(id)
	if reference==null: return
	var body:PhysicsBody2D = reference.get_ref() as PhysicsBody2D
	if is_instance_valid(body):
		body.remove_collision_exception_with(self)
		remove_collision_exception_with(body)
	_void_projectile_bodies.erase(id)

func _void_clear_projectile_bodies() -> void:
	if get_tree().node_added.is_connected(_void_watch_projectile_body):
		get_tree().node_added.disconnect(_void_watch_projectile_body)
	for id:int in _void_projectile_bodies.keys(): _void_forget_projectile_body(id)
