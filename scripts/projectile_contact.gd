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
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return false
	# This hybrid becomes ordinary solid terrain after landing, not a permanent shot.
	if node.is_in_group("CouPenguinRock") and not bool(node.get("flying")): return false
	if node.is_in_group("Shooter") or node.is_in_group("AllayExtendedProjectile"): return true
	# Use the existing character projectile classifier only after _ready has set Type.
	if node.is_node_ready() and node.has_method("_is_projectile_motion_object") and bool(node.call("_is_projectile_motion_object")):
		return true
	var script:Script = node.get_script() as Script
	while script != null:
		if script.resource_path.begins_with("res://scripts/shooter/") or script.resource_path=="res://scripts/training/speedster_training_projectile.gd":
			return true
		script = script.get_base_script()
	# Neutral ghast fireballs intentionally use Creature, not Shooter.
	for info:Dictionary in node.get_property_list():
		if info.name=="flight_velocity": return true
	return false

static func refresh_body_exceptions(body:PhysicsBody2D) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree(): return
	for target:Node in body.get_tree().get_nodes_in_group(INTANGIBLE_GROUP):
		if target.has_method("refresh_projectile_body_exception"):
			target.call("refresh_projectile_body_exception",body)
