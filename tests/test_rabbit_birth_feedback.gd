extends SceneTree

const RABBIT:String = "res://scenes/characters/动物/兔子.tscn"
const HEARTS:String = "res://scenes/effects/兔子繁殖特效.tscn"
var checks:int = 0
var failures:int = 0
var health_losses:Array[Dictionary] = []
var game:Node

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok:
		print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func observe_added(node:Node) -> void:
	if node.scene_file_path != RABBIT:
		return
	var bar:Node = node.get_node("Health_Bar")
	bar.health_changed.connect(func(old_hp,new_hp,_maximum,_animated):
		if int(new_hp) < int(old_hp):
			health_losses.append({"old":old_hp,"new":new_hp,"position":node.global_position})
	)

func freeze(actor:Node) -> void:
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	actor.Can_Attack = false
	actor.Can_Skill = false

func spawn(w:Node2D,point:Vector2,baby:bool = false,growth:float = 5.2) -> Node2D:
	var actor:Node2D = load(RABBIT).instantiate()
	actor.spawn_initial_pair = false
	actor.is_baby = baby
	actor.baby_growth_time = growth
	actor.Team = "RabbitTest"
	actor.position = w.to_local(point)
	w.add_child(actor,true)
	freeze(actor)
	return actor

func particles(w:Node) -> int:
	return w._combat_impact_layer._particles.size() if is_instance_valid(w._combat_impact_layer) else 0

func clear_feedback(w:Node) -> void:
	health_losses.clear()
	w._damage_focus_pending_strength = -1.0
	w._damage_focus_started_usec = 0
	w._damage_focus_next_usec = 0
	w._damage_focus_weight = 0.0
	if is_instance_valid(w._combat_impact_layer):
		w._combat_impact_layer._particles.clear()
		w._combat_impact_layer._impacts.clear()

func assert_quiet(w:Node,label:String) -> void:
	check(health_losses.is_empty(),label+": no artificial damage health event "+str(health_losses))
	check(w._damage_focus_pending_strength < 0.0 and w._damage_focus_started_usec == 0,label+": no damage camera focus request")
	check(particles(w) == 0,label+": no critical particles")

func test_mode(development:bool) -> void:
	game.Game_Settings.Development_Mode = development
	game.Game_Settings.Development_Duration = 30.0
	game.Game_Settings.Development_Speed = 1.0
	var prefix:String = "development" if development else "battle"
	var w:Node2D = load("res://scenes/world.tscn").instantiate()
	w.tree_entered.connect(func(): current_scene = w,CONNECT_ONE_SHOT)
	root.add_child(w)
	if is_instance_valid(w._mc_prewarmer): w._mc_prewarmer.free()
	await process_frame
	await process_frame
	w.set_process(false)
	w.set_physics_process(false)
	w.control.team.hide()
	var center:Vector2 = w.return_map_world_rect(w._current_map_node()).get_center()
	if development: center = w._development.base_rect.get_center() + w._development._offset("right:0")
	var parent:Node2D = spawn(w,center+Vector2(-18,0))
	var partner:Node2D = spawn(w,center+Vector2(18,0))
	if development:
		for actor:Node in [parent,partner]: actor.set_meta("development_lane_key","right:0")
		w._development.update(0.2)
	check(w.is_combat_runtime_active(),prefix+": real World damage feedback is active")
	# Give the production camera one frame to frame the visible arena.
	w.set_process(true)
	await process_frame
	w.set_process(false)
	check(w._impact_is_on_screen(center),prefix+": breeding position is visible to feedback filters")
	freeze(parent)
	freeze(partner)
	clear_feedback(w)
	parent._spawn_initial_partner()
	var extra:Node2D = null
	for unit:Node in get_nodes_in_group("Ball"):
		if unit != parent and unit != partner and unit.scene_file_path == RABBIT:
			extra = unit
			freeze(unit)
	check(extra != null and extra.health == 145,prefix+": initial adult partner keeps full adult health")
	assert_quiet(w,prefix+" initial pair")
	clear_feedback(w)
	var before:Array = get_nodes_in_group("Ball")
	var midpoint:Vector2 = (parent.global_position+partner.global_position)*0.5
	parent._spawn_baby_with(partner)
	var baby:Node2D = null
	for unit:Node in get_nodes_in_group("Ball"):
		if unit not in before and unit.scene_file_path == RABBIT:
			baby = unit
			freeze(unit)
	check(baby != null and baby.is_baby and baby.health == 36 and baby.Max_health == 36,prefix+": newborn starts at 36/36")
	check(baby != null and baby._adult_max_health == 145,prefix+": adult maximum remains available for growth")
	check(baby != null and baby.scale.is_equal_approx(baby._adult_scale*baby.baby_scale_ratio),prefix+": baby scale is preserved")
	check(baby != null and baby.default_properties.Max_health == 36,prefix+": default health metadata matches newborn")
	assert_quiet(w,prefix+" breeding")
	var effect:Node2D = null
	for node:Node in w.get_children():
		if node.scene_file_path == HEARTS: effect = node
	check(effect != null and effect.global_position.distance_to(midpoint) < 0.01,prefix+": breeding hearts stay at the parents' midpoint")
	check(effect != null and effect.get_node("BreedSfx").playing,prefix+": original breeding sound still plays")
	check(effect != null and effect.get_child_count() == 7,prefix+": all six hearts still spawn")
	if baby != null:
		check(baby._hurt_shake_effect == null,prefix+": birth does not shake the baby")
		check(not baby.has_meta("death_return_restore"),prefix+": no restoration flag or temporary immunity left behind")
	# Use a fresh actor for genuine damage; never call visual feedback directly.
	clear_feedback(w)
	var hurt:Node2D = spawn(w,center)
	clear_feedback(w)
	hurt.take_damage(50)
	check(hurt.health == 95 and health_losses.size() == 1,prefix+": genuine 50 damage is still applied")
	check(particles(w) == 0,prefix+": exactly 50 damage still has no critical particles")
	clear_feedback(w)
	hurt.health = hurt.Max_health
	hurt.take_damage(60)
	check(hurt.health == 85 and health_losses.size() == 1,prefix+": genuine 60 damage is still applied")
	check(particles(w) > 0,prefix+": damage above 50 still emits critical particles")
	check(w._damage_focus_pending_strength >= 0.0,prefix+": genuine heavy hit still requests camera focus")
	if baby != null:
		clear_feedback(w)
		baby.take_damage(8)
		check(baby.health == 28 and health_losses.size() == 1,prefix+": newborn can take real damage immediately")
	# Growth must preserve health percentage without synthetic damage.
	clear_feedback(w)
	var growing:Node2D = spawn(w,center+Vector2(0,65),true,0.08)
	growing.take_damage(18)
	clear_feedback(w)
	await create_timer(0.16).timeout
	check(not growing.is_baby and growing.Max_health == 145 and growing.health == 73,prefix+": injured baby grows to rounded half adult health")
	check(growing.scale.is_equal_approx(growing._adult_scale),prefix+": growth restores adult size")
	assert_quiet(w,prefix+" growth")
	w.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	node_added.connect(observe_added)
	await test_mode(false)
	await test_mode(true)
	node_added.disconnect(observe_added)
	game.Game_Settings = saved
	print("RABBIT_BIRTH_FEEDBACK: %d checks / %d failures"%[checks,failures])
	quit(1 if failures > 0 else 0)
