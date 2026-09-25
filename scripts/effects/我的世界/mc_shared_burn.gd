extends RefCounted
## Single Minecraft burn entry for Blaze fireball, Blaze ground fire and Sulfur Cube.
## The existing status owns the visual, refresh, fire immunity and tick settlement.
const STATUS:Script = preload("res://scripts/status/mc_shared_burn_status.gd")
const NODE_NAME:StringName = &"MinecraftBlazeBurn"

static func apply(source:ball,target:ball,duration:float,tick_multiplier:float,tick_interval:float = 0.55) -> bool:
	if not is_instance_valid(source): return false
	return apply_amount(source,target,duration,source.attack_damage(maxf(tick_multiplier,0.0)),tick_interval)

static func apply_amount(source:ball,target:ball,duration:float,tick_damage:float,tick_interval:float = 0.55) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target) or source.health <= 0 or target.health <= 0:
		return false
	if not source.is_multiplayer_authority() or not target.can_receive_fire_status(): return false
	var existing:Node = target.get_node_or_null(NodePath(String(NODE_NAME)))
	if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.has_method("refresh"):
		existing.call("refresh",source,duration,maxf(tick_damage,0.0))
		return true
	var status:Node2D = STATUS.new() as Node2D
	status.name = NODE_NAME
	target.add_child(status,true)
	status.call("setup",target,source,duration,tick_interval,maxf(tick_damage,0.0))
	return true
