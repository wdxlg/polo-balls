extends "res://tests/test_rotation_timed_flow.gd"
# Timed mode: primary fighters never die during the fight. A lethal HP write stops at 1 HP while every
# hit keeps its full feedback / damage-taken score as if the fighter still had HP; the verdict at
# time-up still eliminates the losers. The world clock only moves down when the duel side panels show.
func score(id:int) -> float:
	return float(world._timed_damage_by_setup.get(id,0.0))
func prepare() -> void:
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_finished=false;world._timed_overtime=false;world._timed_time_left=10
func fresh() -> void:
	world.reset();await process_frame;await process_frame
	prepare()
func refresh_hud() -> void:
	world.refresh_versus_text();world.duel_top_hud._update_clock(0);world.duel_top_hud._refresh_pair();world.duel_top_hud._refresh_values();world.duel_top_hud._process(0)
func run() -> void:
	create_timer(60,true,false,true).timeout.connect(func():print("TIMED_NO_DEATH_TIMEOUT");quit(2))
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
	prepare()

	# A. Lethal writes during the fight stop at 1 HP; the full hit is still counted and fed back.
	var a:Node=timed_actor(1,"Team0");var b:Node=timed_actor(2,"Team1")
	world._timed_damage_by_setup={1:0.0,2:0.0}
	var start_hp:int=int(a.health)
	a.health-=start_hp+500
	await process_frame;await process_frame
	check(is_instance_valid(a) and a.health==1 and a.state_machine.current_state!=a.State.Die,"lethal hit during the timed fight leaves the fighter alive at 1 HP")
	check(is_equal_approx(score(1),float(start_hp+500)),"the whole lethal hit counts as damage taken (%s)"%score(1))
	check(is_equal_approx(float(a.timed_absorbed_health_loss),501.0),"the part below the floor is recorded as absorbed (%s)"%a.timed_absorbed_health_loss)
	a._last_combat_damage_health_before=-1.0
	a.health-=40
	check(a.health==1 and is_equal_approx(score(1),float(start_hp+540)),"hits at 1 HP keep counting their full damage")
	check(is_equal_approx(float(a._last_combat_damage_health_before),1.0),"hits at 1 HP still run the real-damage feedback path (character hooks / camera)")
	var before_score:float=score(1)
	a.take_damage(50.0,true)
	check(a.health==1 and score(1)>before_score,"take_damage at 1 HP: no death, damage still scored")
	before_score=score(1)
	var dealt:bool=a.receive_positional_damage(30.0,a.global_position+Vector2(20,0),true)
	check(dealt and a.health==1 and score(1)>before_score,"positional damage at 1 HP still reports a real hit (hit burst / hurt audio / report)")
	b.health-=10
	check(b.health==int(b.Max_health)-10,"non-lethal damage is unchanged")

	# B. Outside the running fight, and forced map deaths, keep the original death rules.
	world._timed_running=false
	var c:Node=timed_actor(3,"Team2")
	c.health=0
	check(c.health==0,"before the fight starts / after it ends, HP can still reach 0")
	world._timed_running=true
	var d:Node=timed_actor(4,"Team3")
	d.set_meta(&"__out_of_bounds_forced_death",true);d.health=0
	check(d.health==0,"forced out-of-bounds death is not blocked")
	game.Game_Settings.Training_Mode_Type="manual"
	var e:Node=timed_actor(5,"Team4")
	e.health=0
	check(e.health==0,"other modes are untouched")
	game.Game_Settings.Training_Mode_Type="timed"

	# C. Verdict at time-up still eliminates the loser.
	await fresh()
	a=timed_actor(1,"Team0");b=timed_actor(2,"Team1")
	world._timed_damage_by_setup={1:0.0,2:0.0}
	a.health-=int(a.health)+100
	check(a.health==1,"loser is still alive at 1 HP right before time-up")
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_finished and world._timed_winner_setup==2,"most damage taken loses")
	check(a.health==0 and b.health>0,"time-up verdict still kills the loser")

	# D. World clock only moves down when the two duel side panels are shown.
	await fresh()
	a=timed_actor(1,"Team0");b=timed_actor(2,"Team1");c=timed_actor(3,"Team2")
	world._timed_damage_by_setup={1:0.0,2:0.0,3:0.0}
	refresh_hud()
	var hud:Node=world.duel_top_hud
	hud._update_world_clock(10.0);hud._update_world_clock(10.0)
	check(hud.sides.size()!=2 and not hud._clock_down and is_zero_approx(hud.clock_shift),"timer-only HUD (3 teams): world clock stays in place (visible=%s shift=%s)"%[hud.visible,hud.clock_shift])
	await fresh()
	a=timed_actor(1,"Team0");b=timed_actor(2,"Team1")
	world._timed_damage_by_setup={1:0.0,2:0.0}
	refresh_hud()
	hud._update_world_clock(10.0);hud._update_world_clock(10.0)
	check(hud.sides.size()==2 and hud.visible and hud._clock_down,"duel side panels shown: world clock moves below them")

	print("TIMED_NO_DEATH_RESULT checks=%d failures=%d"%[checks,failures])
	game.Game_Settings=saved;game.now_stop_state=false
	if is_instance_valid(world):world.queue_free()
	current_scene=null
	await process_frame;await process_frame
	quit(0 if failures==0 else 1)
