extends "res://classes/ai_original_base.gd"
var _marks:Dictionary = {}
func _tick_trait(_delta:float) -> void:
	for id:int in _marks.keys():
		if not is_instance_id_valid(id) or float(_marks[id].expires) <= _combat_clock:
			_marks.erase(id)
	if _marks.is_empty():
		side_status_remove_permanent("left","ai_marks")
func Attack() -> void:
	super.Attack()
	if not is_multiplayer_authority() or not is_combat_runtime_active():
		return
	var target:ball = nearest_opponent()
	if target == null:
		return
	var point:Vector2 = target.global_position
	var generation:int = begin_action()
	effect(0,global_position,point,22.0,0.26)
	if await windup(0.26,generation):
		effect(2,global_position,point,2.0,0.3)
		if enemy_valid(target) and target.global_position.distance_to(point) <= 32.0 and global_position.distance_to(target.global_position) <= engagement_range and clear_line(target.global_position) and deal(target):
			var id:int = target.get_instance_id()
			var stacks:int = mini(int(_marks.get(id,{"stacks":0}).stacks) + 1,3)
			_marks[id] = {"stacks":stacks,"expires":_combat_clock+4.0}
			effect(3,target.global_position,target.global_position,18.0 + stacks*4.0,0.5)
			side_status_set_permanent("left","ai_marks","时印 %d/3" % stacks,accent)
	finish_action(generation)
func Skill() -> void:
	if not is_multiplayer_authority() or not is_combat_runtime_active() or is_damage_output_disabled():
		return
	var generation:int = begin_action(true)
	effect(0,global_position,global_position,170.0,0.45)
	if await windup(0.45,generation):
		var allies:Array[ball] = []
		for node:Node in get_tree().get_nodes_in_group("Ball"):
			if not node is ball:
				continue
			var ally:ball = node as ball
			if ally.health <= 0 or ally.Type != Ball_Type.Ball or ally.health >= ally.Max_health:
				continue
			if ally != self and (Team.is_empty() or ally.Team != Team):
				continue
			if global_position.distance_to(ally.global_position) <= 170.0 and clear_line(ally.global_position):
				allies.append(ally)
		allies.sort_custom(func(a:ball,b:ball): return float(a.health)/maxf(a.Max_health,1.0) < float(b.health)/maxf(b.Max_health,1.0))
		for i:int in range(mini(allies.size(),3)):
			allies[i].heal(40)
			effect(3,allies[i].global_position,allies[i].global_position,30.0,0.55)
		for id:int in _marks.keys():
			if not is_instance_id_valid(id):
				continue
			var target:Variant = instance_from_id(id)
			if enemy_valid(target) and float(_marks[id].expires) > _combat_clock and global_position.distance_to(target.global_position) <= 260.0 and clear_line(target.global_position):
				effect(1,target.global_position,target.global_position,32.0,0.35)
				deal(target,0.75 * int(_marks[id].stacks))
		_marks.clear()
		side_status_remove_permanent("left","ai_marks")
	finish_action(generation,true)

func skill_available() -> bool:
	if not _marks.is_empty():
		return true
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball:
			var ally:ball = node as ball
			if ally.health > 0 and ally.health < ally.Max_health and (ally == self or (not Team.is_empty() and ally.Team == Team)) and global_position.distance_to(ally.global_position) <= 170.0:
				return true
	return false
