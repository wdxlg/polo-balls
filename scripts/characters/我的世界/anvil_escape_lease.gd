extends Node
# A scoped BODY-only exception lets a compressed victim slide out from under its
# anvil. Areas remain hittable, and existing caller-owned exceptions are preserved.
var source_ref:WeakRef
var effect_ref:WeakRef
var owns_exception:bool = false
func setup(source:PhysicsBody2D,effect:Node) -> void:
	source_ref = weakref(source)
	effect_ref = weakref(effect)
	var victim:PhysicsBody2D = get_parent() as PhysicsBody2D
	if victim!=null and source not in victim.get_collision_exceptions():
		victim.add_collision_exception_with(source)
		owns_exception = true
func _physics_process(_delta:float) -> void:
	var source:Variant = source_ref.get_ref() if source_ref!=null else null
	var effect:Variant = effect_ref.get_ref() if effect_ref!=null else null
	if not is_instance_valid(source) or not is_instance_valid(effect) or not effect.is_active_effect() or effect.source!=source:
		queue_free()
func _exit_tree() -> void:
	var victim:PhysicsBody2D = get_parent() as PhysicsBody2D
	var source:Variant = source_ref.get_ref() if source_ref!=null else null
	if owns_exception and is_instance_valid(victim) and is_instance_valid(source):
		victim.remove_collision_exception_with(source)
	owns_exception = false
