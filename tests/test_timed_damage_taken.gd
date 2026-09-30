extends "res://tests/test_rotation_timed_flow.gd"
# Timed mode shows and scores DAMAGE TAKEN.
# - Head number and the 1v1 top HUD show each setup's accumulated actual HP loss.
# - Every actual HP loss counts (enemy, summon, environment, self, sourceless writes),
#   read in ball.health's setter after character hooks; healing never changes it.
# - Least damage taken wins; a tie for the lowest enters overtime and settles on the
#   first HP loss that breaks it. Deleted or permanently dead setups cannot win.
func run() -> void:
	create_timer(60,true,false,true).timeout.connect(func():print("TIMED_TAKEN_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null
	await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	world.set_process(false);world.set_physics_process(false)
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_time_left=10

	# A. Display + accumulation through the real health setter.
	var blue:Node=timed_actor(1,"Team0")
	var red:Node=timed_actor(2,"Team1")
	world._timed_damage_by_setup={1:0.0,2:0.0}
	blue.health-=40 # sourceless / environment-style write
	check(is_equal_approx(world._timed_damage_by_setup[1],40.0) and world._timed_damage_by_setup[2]==0.0,"actual HP loss adds to the VICTIM's own score, not the attacker's")
	check(world._timed_damage_labels.has(1) and world._timed_damage_labels[1].text=="40","head number shows damage taken (40)")
	check(world._timed_damage_labels.has(2) and world._timed_damage_labels[2].text=="0","untouched fighter's head number stays 0")
	blue.health+=25
	check(is_equal_approx(world._timed_damage_by_setup[1],40.0),"healing neither reduces nor adds damage taken")
	var before_block:float=world._timed_damage_by_setup[2]
	red.health=red.health # no change: not a loss
	check(world._timed_damage_by_setup[2]==before_block,"a no-op health write adds nothing")
	var summon:Node=load("res://scenes/ball.tscn").instantiate();summon.Master=red;summon.Team="Team1";world.add_child(summon)
	summon.state_machine.set_physics_process(false);summon.Can_Attack=false;summon.Can_Skill=false
	var red_before:float=world._timed_damage_by_setup[2]
	summon.health-=30
	check(world._timed_damage_by_setup[2]==red_before,"a summon's own HP loss does not count toward its owner's score")
	summon.queue_free()
	world.refresh_versus_text();world.duel_top_hud._refresh_pair();world.duel_top_hud._refresh_values();world.duel_top_hud._update_clock(0);world.duel_top_hud._process(0)
	if world.duel_top_hud.sides.size()==2:
		var left:Dictionary=world.duel_top_hud.sides[0]
		var text:String=world.duel_top_hud.side_value_text(left)
		check(text=="40","1v1 top HUD shows only the same damage-taken number: "+text)
	else:
		check(false,"1v1 top HUD available for the timed duel")

	# B. Settlement: least damage taken wins.
	world._timed_damage_by_setup={1:120.0,2:30.0}
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_finished and world._timed_winner_setup==2,"least damage taken wins at time-up")
	check(blue.health==0 and red.health>0,"fighter with more damage taken is eliminated")
	var frozen:float=world._timed_damage_by_setup[2]
	red.health-=10
	check(world._timed_damage_by_setup[2]==frozen,"scores freeze after the verdict")

	# C. Tie for the lowest -> overtime; a HIGHER score is not killed early; first loss settles.
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_time_left=10
	blue=timed_actor(1,"Team0");red=timed_actor(2,"Team1")
	var third:Node=timed_actor(3,"Team2")
	world._timed_damage_by_setup={1:10.0,2:10.0,3:50.0}
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_overtime and not world._timed_finished and third.health>0,"lowest tie enters overtime; higher score survives meanwhile")
	blue.health-=1
	check(world._timed_finished and world._timed_winner_setup==2,"first real HP loss in overtime settles immediately for the other tied fighter")
	check(blue.health==0 and third.health==0 and red.health>0,"all other setups eliminated")

	# D. Deleted setups and permanently dead fighters cannot win by 'taking no damage'.
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_time_left=10
	blue=timed_actor(1,"Team0");red=timed_actor(2,"Team1")
	world._timed_damage_by_setup={1:80.0,2:60.0,77:0.0} # 77: placed then deleted, never fought
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_finished and world._timed_winner_setup==2,"a deleted setup with 0 damage taken is not a candidate")
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_time_left=10
	blue=timed_actor(1,"Team0");red=timed_actor(2,"Team1")
	third=timed_actor(3,"Team2")
	world._timed_damage_by_setup={1:80.0,2:90.0,3:0.0}
	third.health=0;third.queue_free();await process_frame;await process_frame
	check(world._timed_damage_by_setup[3]>0.0,"the lethal HP loss itself was counted as damage taken")
	world._timed_damage_by_setup[3]=0.0 # force the dead setup to hold the lowest score
	var dead_score:float=world._timed_damage_by_setup[3]
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_finished and world._timed_winner_setup==1,"a permanently dead fighter cannot win even with the lowest score (its score="+str(dead_score)+")")

	print("TIMED_TAKEN_RESULT checks=%d failures=%d"%[checks,failures])
	game.Game_Settings=saved;game.now_stop_state=false
	if is_instance_valid(world):world.queue_free()
	current_scene=null
	await process_frame;await process_frame
	quit(0 if failures==0 else 1)
