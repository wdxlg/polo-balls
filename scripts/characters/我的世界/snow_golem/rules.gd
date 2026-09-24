extends RefCounted
## Snow never harms its own family, including unteamed parent/offspring.
static func enemy(source:ball,target:Variant) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target) or not target is ball: return false
	if source == target or target.is_queued_for_deletion() or not target.is_combat_targetable(): return false
	var family:String = str(source.get_meta("mc_snow_family",""))
	if not family.is_empty() and family == str(target.get_meta("mc_snow_family","")): return false
	if not source.Team.is_empty() and source.Team == target.Team: return false
	return true
