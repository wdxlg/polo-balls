extends RefCounted
# Spread is separate from enemy damage and does not depend on friendly-fire settings.
# Every peer may display the source effect, but charge() only changes its owned items.
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
const ITEM_RADIUS:float = 3.0
static func can_receive(source:Node,spear:Node) -> bool:
	return is_instance_valid(source) and source.health>0 and source.is_combat_runtime_active() and is_instance_valid(spear) and not spear.charged and spear.eligible() and GEOMETRY.same_team(source,spear.unit)
static func in_radius(source:Node,point:Vector2,radius:float) -> int:
	var changed:int = 0
	for spear:Node in source.get_tree().get_nodes_in_group("MCUnenchantedTrident"):
		if not can_receive(source,spear): continue
		if spear.enchantment_position().distance_to(point)<=radius+ITEM_RADIUS:
			if spear.charge(): changed += 1
	return changed
static func along_arc(source:Node,a:Vector2,b:Vector2,old_a:Vector2,old_b:Vector2,previous:Dictionary) -> int:
	var changed:int = 0
	for spear:Node in source.get_tree().get_nodes_in_group("MCUnenchantedTrident"):
		if not can_receive(source,spear): continue
		var id:int = spear.get_instance_id()
		var point:Vector2 = spear.enchantment_position()
		var old:Vector2 = previous.get(id,point)
		previous[id] = point
		var touched:bool = GEOMETRY.touching(a,b,point,old,source.network_width+ITEM_RADIUS)
		if not touched: touched = Geometry2D.is_point_in_polygon(point,PackedVector2Array([old_a,old_b,b,a]))
		if touched and spear.charge(): changed += 1
	return changed
