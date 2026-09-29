extends RefCounted
## Passive contact policy only: never change character targeting or trigger a dodge.
## A projectile must consult this before impact/retirement/reflection/hit bookkeeping.
const INTANGIBLE_GROUP:StringName = &"ProjectileIntangible"

static func ignores(target:Variant) -> bool:
	if not is_instance_valid(target) or not target is Node: return false
	var node:Node = target as Node
	while is_instance_valid(node):
		if node.has_method("is_projectile_intangible") and bool(node.call("is_projectile_intangible")):
			return true
		node = node.get_parent()
	return false

static func is_projectile(node:Node) -> bool:
	return preload("res://classes/combat_classification.gd").is_projectile(node)

static func refresh_body_exceptions(body:PhysicsBody2D) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree(): return
	for target:Node in body.get_tree().get_nodes_in_group(INTANGIBLE_GROUP):
		if target.has_method("refresh_projectile_body_exception"):
			target.call("refresh_projectile_body_exception",body)
