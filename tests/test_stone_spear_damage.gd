extends "res://tests/test_stone_spear.gd"
func run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Have_Team_Damage=false
	AudioServer.set_bus_mute(0,true)
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	spear.Team="Team0"
	arena.add_child(spear)
	check(spear.SPEED_DAMAGE_FACTOR==0.25,"speed conversion coefficient halved")
	check(spear.Damage==20 and spear.Speed==170 and spear.movement_growth==10.0,"base attributes and movement growth halved again")
	check(spear.body_turn_degrees_per_second==3600.0,"0.05 second U-turn preserved")
	check(spear.formation_angle_response==8.0 and spear.formation_position_response==10.0,"copy smoothing preserved")
	for attack:int in [20,40]:
		spear.Damage=attack
		for speed_value:float in [-10.0,0.0,10.0,102.0,204.0,510.0,1020.0,10000.0]:
			var old_damage:float=spear.attack_damage(maxf(speed_value,0.0)/102.0)
			check(is_equal_approx(spear.damage_at_speed(speed_value),old_damage*0.25),"quarter original raw damage at speed=%s attack=%s" % [speed_value,attack])
	spear.Damage=20
	var target:Node2D=victim(Vector2(25,0))
	await physics_frame
	for form:int in [0,1,2]:
		reset_pose(form)
		if form==2: spear._stab_time=0.01
		for index:int in range(5):
			var hp:int=target.health
			spear._sweep_tip(index,Vector2.ZERO,Vector2(25.5,0),0.0,0.0,0.025,Vector2.ZERO)
			check(hp-target.health==50,"real 1020-speed hit is 50 not 100: formation=%d tip=%d" % [form,index])
			hp=target.health
			spear._sweep_tip(index,Vector2.ZERO,Vector2(25.5,0),0.0,0.0,0.025,Vector2.ZERO)
			check(target.health==hp,"damage reduction preserves tip deduplication")
		var threats:Array=spear.get_ai_attack_threats(null)
		check(threats.size()==5,"all five active tip threats remain available")
		for threat:Dictionary in threats:
			check(is_equal_approx(threat.damage,50.0),"AI threat matches reduced hit damage")
	reset_pose(2)
	spear._tip_speeds.fill(1020.0)
	check(spear.get_ai_attack_threats(null).is_empty(),"idle thrust remains harmless")
	spear._stab_time=spear.stab_out_time+0.1
	check(spear.get_ai_attack_threats(null).is_empty(),"return thrust remains harmless")
	print("STONE_DAMAGE_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
