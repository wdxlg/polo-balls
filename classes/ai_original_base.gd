extends ball
## Shared movement/telegraph plumbing only; each role owns its combat mechanics.
const FX = preload("res://scripts/effects/AI/原创战斗反馈.gd")
@export var engagement_range:float = 100.0
@export var preferred_distance:float = 60.0
@export var accent:Color = Color(1.0,0.7,0.3)
@export_multiline var character_traits:String = ""
var _think_left:float = 0.0
var _combat_clock:float = 0.0
var _action_generation:int = 0
func _ready() -> void:
	Has_Collision_Damage = false
	Health_Restore = 0
	super._ready()
	if not character_traits.is_empty():
		side_status_set_permanent("left","ai_role",character_traits.split("\n")[0],accent)
func enemy_valid(value:Variant,lockable:bool = false) -> bool:
	if value == null or not is_instance_valid(value) or not value is ball or value == self:
		return false
	var candidate:ball = value as ball
	if not candidate.is_combat_targetable():
		return false
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,candidate): # Haochen copies never pick his side
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.strip_edges().is_empty() and candidate.Team == Team:
		return false
	return not lockable or candidate.is_combat_lockable()
func nearest_opponent() -> ball:
	var best:ball = null
	var distance:float = INF
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not enemy_valid(candidate,true):
			continue
		var d:float = global_position.distance_squared_to((candidate as ball).global_position)
		if d < distance:
			distance = d
			best = candidate as ball
	return best
func enemies_near(point:Vector2,radius:float) -> Array[ball]:
	var result:Array[ball] = []
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if enemy_valid(candidate) and point.distance_to((candidate as ball).global_position) <= radius:
			result.append(candidate as ball)
	return result
func clear_line(point:Vector2) -> bool:
	if get_world_2d() == null:
		return false
	var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position,point,1,[get_rid()])
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()
func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health > 0 and is_combat_runtime_active():
		_combat_clock += delta
		_tick_trait(delta)
		_think_left -= delta
		if _think_left <= 0.0 and not is_player_controlled() and not dizziness:
			_think_left = 0.12
			var opponent:ball = nearest_opponent()
			if opponent != null:
				var offset:Vector2 = opponent.global_position - global_position
				if Attacking or Using_Skill:
					direction = Vector2.ZERO
				elif offset.length() > preferred_distance + 12.0:
					direction = offset.normalized()
				elif preferred_distance > 100.0 and offset.length() < preferred_distance * 0.5:
					direction = -offset.normalized()
				else:
					direction = Vector2.ZERO
	super.tick_physics(state,delta)
func _tick_trait(_delta:float) -> void:
	pass
func get_next_state(state:State) -> int:
	var next:int = super.get_next_state(state)
	if next == State.Skill and Attacking:
		return -1
	if next == State.Skill and not Using_Skill and not skill_available():
		# An unused ready skill must not starve normal attacks. Re-run the base
		# decision without auto-skill, restoring its ready cooldown afterwards.
		var saved_can_skill:bool = Can_Skill
		var saved_skill_time:float = float(state_machine.last_state_dis.get("Skill",0.0))
		Can_Skill = false
		next = super.get_next_state(state)
		Can_Skill = saved_can_skill
		state_machine.last_state_dis["Skill"] = saved_skill_time
	if next == State.Attack and Using_Skill:
		return -1
	if next == State.Attack and not Attacking:
		var opponent:ball = nearest_opponent()
		if opponent == null or global_position.distance_to(opponent.global_position) > engagement_range or not clear_line(opponent.global_position):
			return State.Move if state != State.Move else -1
	return next
func skill_available() -> bool:
	return true
func begin_action(skill:bool = false) -> int:
	_action_generation += 1
	if skill:
		Attacking = false
		Using_Skill = true
	else:
		Using_Skill = false
		Attacking = true
	return _action_generation
func action_valid(generation:int) -> bool:
	return generation == _action_generation and is_inside_tree() and health > 0 and state_machine.current_state != State.Die and not dizziness
func windup(seconds:float,generation:int) -> bool:
	var left:float = seconds
	while left > 0.0:
		await get_tree().physics_frame
		if not action_valid(generation):
			return false
		if is_combat_runtime_active():
			left -= get_physics_process_delta_time()
	return action_valid(generation) and not is_damage_output_disabled()
func finish_action(generation:int,skill:bool = false) -> void:
	if generation != _action_generation:
		return
	if skill:
		Using_Skill = false
	else:
		Attacking = false
func deal(target:Variant,multiplier:float = 1.0) -> bool:
	if not enemy_valid(target) or not is_multiplayer_authority() or is_damage_output_disabled() or not is_combat_runtime_active():
		return false
	var applied:bool = (target as ball).receive_positional_damage(attack_damage(multiplier),global_position,false,self)
	if applied and Hit_Audio != "":
		Audios.play_sfx.rpc(Hit_Audio,{},true)
	return applied
func effect(kind:int,start:Vector2,finish:Vector2,radius:float = 0.0,duration:float = 0.3) -> void:
	if multiplayer.has_multiplayer_peer():
		_ai_effect.rpc(kind,start,finish,radius,duration)
	else:
		_ai_effect(kind,start,finish,radius,duration)
@rpc("authority","call_local","reliable")
func _ai_effect(kind:int,start:Vector2,finish:Vector2,radius:float,duration:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var visual:Node2D = FX.new()
	world.add_child(visual)
	visual.configure(kind,start,finish,accent,radius,duration)
func Die() -> void:
	_action_generation += 1
	Attacking = false
	Using_Skill = false
	super.Die()
