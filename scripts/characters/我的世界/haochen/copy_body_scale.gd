extends RefCounted
## Body scale of a shrunken character copy (Haochen copies: 0.5); 1.0 for every
## other unit. The root scale already shrinks everything parented normally; overlays
## that ignore the parent scale (top_level bars and icons, status swirls, nodes that
## pin global_scale) multiply their sizes and head offsets by this factor so a copy's
## own UI and held body parts shrink with it. Projectiles, summons and skill areas
## keep their original size and must not use it.
## Duck-typed on purpose (no `ball` type) so any script can preload it without a cycle.

static func of(unit:Variant) -> float:
	if not is_instance_valid(unit) or not (unit is Object): return 1.0
	var profile:Variant = (unit as Object).get(&"character_copy_profile")
	if not (profile is Dictionary): return 1.0
	return clampf(float((profile as Dictionary).get("body_scale",1.0)),0.05,4.0)
