extends "res://tests/test_elytra_return_dash.gd"
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.High_Damage_Feedback = false
	AudioServer.set_bus_mute(0,true)
	arena = FlightArena.new()
	root.add_child(arena)
	current_scene = arena
	var unit:Node2D = actor("卫道士",Vector2(-250,0))
	var enemy:Node2D = victim(Vector2.ZERO)
	unit.rush_wait = 0
	unit.attack_wait = 0
	unit.state_machine.set_physics_process(true)
	unit.set_physics_process(true)
	var states:Dictionary = {}
	var before:int = enemy.health
	var start:Vector2 = unit.global_position
	var most_charge:float = 0.0
	var raised_while_rushing:bool = false
	for frame:int in range(480):
		await physics_frame
		states[unit.phase] = true
		most_charge = maxf(most_charge,unit.charge_ratio())
		if unit.phase==unit.Phase.DASH and unit.charge_elapsed>=0.12:
			raised_while_rushing = raised_while_rushing or (unit.hand_center().y<unit._arm.global_position.y-4 and unit.velocity.length()>unit.Speed)
		if enemy.health<before: break
	check(unit.global_position.distance_to(start)>50,"autonomous real physics closes distance")
	check(states.has(unit.Phase.DASH),"AI independently starts the rush")
	check(raised_while_rushing,"autonomous moving rush actually raises the hand above shoulder, not just a charge timer")
	check(most_charge>0.1,"AI rush actually accumulates charge over physics frames")
	check(states.has(unit.Phase.SWING) and enemy.health<before,"AI reaches the target and its real axe sweep deals damage")
	print("VINDICATOR_LIVE_HIT loss=",before-enemy.health," charge=",unit.released_charge," states=",states.keys())
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	var after:int = enemy.health
	for frame:int in 12: await physics_frame
	check(enemy.health==after,"idle visible axe does not cause passive contact damage")
	for warm:int in 8: await process_frame
	print("VINDICATOR_LIVE_RESULT checks=",checks," failures=",failures," completed=true")
	await finish()
