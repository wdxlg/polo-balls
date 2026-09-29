extends RefCounted
## One-shot negative-status removal. Identity/polarity is explicit, never guessed
## from a node name, icon, directory, caster or damage type. No immunity is granted.
const CLASSIFICATION = preload("res://classes/combat_classification.gd")

static func polarity(effect:Node) -> int:
	if effect.has_method("get_status_effect_polarity"):
		return int(effect.call("get_status_effect_polarity"))
	var profile:Dictionary = CLASSIFICATION.declared(effect)
	if str(profile.get("entity_kind",""))!="status": return 0
	match str(profile.get("status_polarity","neutral")):
		"negative": return -1
		"positive": return 1
	return 0

static func _collect(node:Node,target:Node,result:Array[Node]) -> void:
	for child:Node in node.get_children():
		# Never clear another actor (summon/rider) merely because it is parented here.
		if child.has_method("cleanse_negative_effects"): continue
		result.append(child)
		_collect(child,target,result)

static func clear_local(target:Node) -> int:
	var candidates:Array[Node] = []
	_collect(target,target,candidates)
	for ref:WeakRef in target._status_effect_registrations.values():
		var effect:Node = ref.get_ref() as Node
		if is_instance_valid(effect) and not candidates.has(effect): candidates.append(effect)
	# Newer tint/control owners release first; each cleanup owns its own leases.
	candidates.reverse()
	var removed:int = 0
	for effect:Node in candidates:
		if not is_instance_valid(effect) or effect==target or effect.has_method("cleanse_negative_effects"): continue
		if "target" in effect and effect.get("target")!=target: continue
		if polarity(effect)>=0: continue
		var profile:Dictionary = CLASSIFICATION.declared(effect)
		var cleanup:String = str(profile.get("status_cleanup","detach"))
		if effect.has_method("cleanse_status_effect"): cleanup = "cleanse_status_effect"
		effect.set_process(false)
		effect.set_physics_process(false)
		if cleanup!="detach" and effect.has_method(cleanup): effect.call(cleanup)
		if not is_instance_valid(effect):
			removed += 1
			continue
		# Stop DOT/control now, vacate stable names for legitimate later reapplication,
		# and run _exit_tree cleanup immediately, not one additional physics tick later.
		if effect.get_parent()!=null: effect.get_parent().remove_child(effect)
		if not effect.is_queued_for_deletion(): effect.queue_free()
		removed += 1
	for key:Variant in target._status_effect_registrations.keys():
		var ref:WeakRef = target._status_effect_registrations[key]
		var effect:Node = ref.get_ref() as Node
		if not is_instance_valid(effect) or effect.is_queued_for_deletion(): target._status_effect_registrations.erase(key)
	# Legacy Buffs share one polarity method, including explicit signs for future
	# effects. Direct erasure deliberately avoids poison/parasite expiration damage.
	for source_id:Variant in target.Buff_Dic.keys():
		var buffs:Dictionary = target.Buff_Dic[source_id]
		for key:Variant in buffs.keys():
			var buff:Buff = buffs[key] as Buff
			if buff!=null and buff.is_negative_for(target):
				buffs.erase(key)
				removed += 1
		if buffs.is_empty(): target.Buff_Dic.erase(source_id)
	# Pulls are renewable contact leases, not permanent immunity. A still-active
	# external hazard can apply a NEW effect after this instantaneous cleanse.
	if target.has_meta("shared_motion_pull_leases"):
		var leases:Dictionary = target.get_meta("shared_motion_pull_leases")
		for key:Variant in leases.keys():
			var ref:WeakRef = leases[key].get("caster") as WeakRef
			if ref==null or ref.get_ref()!=target: leases.erase(key)
		if leases.is_empty(): target.remove_meta("shared_motion_pull_leases")
	var world:Node = target.get_tree().current_scene if target.is_inside_tree() else null
	if is_instance_valid(world) and world.has_method("refresh_runtime_buffs") and target.is_multiplayer_authority():
		world.call("refresh_runtime_buffs",target)
	var tooltip:Node = target.get_node_or_null("Minecraft药水状态框")
	if tooltip!=null and tooltip.has_method("refresh_display"): tooltip.call("refresh_display")
	return removed
