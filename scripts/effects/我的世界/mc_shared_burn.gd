extends RefCounted
## Single Minecraft burn entry for Blaze fireball, Blaze ground fire and Sulfur Cube.
## The existing status owns the visual, refresh, fire immunity and tick settlement.
const STATUS:Script = preload("res://scripts/status/mc_shared_burn_status.gd")
const NODE_NAME:StringName = &"MinecraftBlazeBurn"
const TICK_INTERVAL:float = 0.55

static func apply(source:ball,target:ball,duration:float,tick_multiplier:float,tick_interval:float = TICK_INTERVAL) -> bool:
	if not is_instance_valid(source): return false
	return apply_amount(source,target,duration,source.attack_damage(maxf(tick_multiplier,0.0)),tick_interval)

## soul=true：灵魂火造成的燃烧，显示原版灵魂火燃烧外观；不传即普通火（刷新时也回到普通火外观）。
static func apply_amount(source:ball,target:ball,duration:float,tick_damage:float,tick_interval:float = TICK_INTERVAL,soul:bool = false) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target) or source.health <= 0 or target.health <= 0:
		return false
	if not source.is_multiplayer_authority() or not target.can_receive_fire_status(): return false
	var existing:Node = target.get_node_or_null(NodePath(String(NODE_NAME)))
	if is_instance_valid(existing) and not existing.is_queued_for_deletion() and soul and not existing.has_method("set_soul"):
		# 旧式燃烧节点（如附魔火焰）没有灵魂火外观：换成共享燃烧状态。
		target.remove_child(existing)
		existing.queue_free()
		existing = null
	if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.has_method("refresh"):
		existing.call("refresh",source,duration,maxf(tick_damage,0.0))
		if existing.has_method("set_soul"): existing.call("set_soul",soul)
		return true
	var status:Node2D = STATUS.new() as Node2D
	status.name = NODE_NAME
	target.add_child(status,true)
	status.call("setup",target,source,duration,tick_interval,maxf(tick_damage,0.0))
	if soul and not status.is_queued_for_deletion(): status.call("set_soul",true)
	return true
