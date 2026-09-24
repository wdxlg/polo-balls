extends RefCounted
# A train is one attack. Different trains/spikes must wait for a wall to clear.
static func scope(context:Node) -> String:
	var world:Node=context.get_tree().current_scene
	return str(world.get("now_choose_map")) if is_instance_valid(world) else ""
static func available(context:Node,side:int,token:String="") -> bool:
	for effect:Node in context.get_tree().get_nodes_in_group("SansWallAttack"):
		if not is_instance_valid(effect) or effect.is_queued_for_deletion(): continue
		if str(effect.get_meta("sans_wall_map",""))!=scope(context): continue
		if int(effect.get_meta("sans_wall_side",-1))!=side: continue
		if token.is_empty() or str(effect.get_meta("sans_wall_token",""))!=token: return false
	return true
static func register(effect:Node,context:Node,side:int,token:String) -> void:
	effect.set_meta("sans_wall_map",scope(context))
	effect.set_meta("sans_wall_side",side)
	effect.set_meta("sans_wall_token",token)
	effect.add_to_group("SansWallAttack")
static func side_from_inward(inward:Vector2) -> int:
	if absf(inward.x)>absf(inward.y): return 3 if inward.x>0.0 else 1
	return 0 if inward.y>0.0 else 2
