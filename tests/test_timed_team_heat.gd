extends "res://tests/test_rotation_timed_flow.gd"
# Timed mode team presentation and team verdict:
# - Top duel HUD shows only the number (no "受到伤害" label).
# - Head numbers and HUD numbers turn red by damage taken: each team's colour is its rank
#   among all teams' total damage taken, white (least) -> red (most); equal totals share a colour.
# - Timed top HUD pairs by TEAM: shown whenever there are exactly 2 teams. A team with more
#   than one member is shown as the team (wool + "X色队伍"), value = team total damage taken.
# - Verdict is by team total (least wins, whole team survives); head number stays personal.
const RED:=Color(1.0,0.2,0.2)
func label_color(id:int) -> Color:
	var label:Label=world._timed_damage_labels.get(id,null)
	return label.get_theme_color("font_color") if label!=null else Color.BLACK
func prepare() -> void:
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_time_left=10
func fresh() -> void:
	world.reset();await process_frame;await process_frame
	prepare()
func hud_side(key:String) -> Dictionary:
	for side:Dictionary in world.duel_top_hud.sides:
		if str(side.get("team_key",""))==key:return side
	return {}
func refresh_hud() -> void:
	world.refresh_versus_text();world.duel_top_hud._update_clock(0);world.duel_top_hud._refresh_pair();world.duel_top_hud._refresh_values();world.duel_top_hud._process(0)
func run() -> void:
	create_timer(60,true,false,true).timeout.connect(func():print("TIMED_TEAM_TIMEOUT");quit(2))
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

	# A. 2 teams, 2 v 1: colours, team HUD, team verdict.
	var a1:Node=timed_actor(1,"Team0");var a2:Node=timed_actor(2,"Team0");var b1:Node=timed_actor(3,"Team1")
	world._timed_damage_by_setup={1:0.0,2:0.0,3:0.0}
	world._update_all_timed_damage_labels()
	check(label_color(1).is_equal_approx(Color.WHITE) and label_color(3).is_equal_approx(Color.WHITE),"equal totals (all 0): every head number is white")
	a1.health-=30
	check(world._timed_damage_labels[1].text=="30" and world._timed_damage_labels[2].text=="0","head number stays PERSONAL damage taken (30 / 0)")
	check(label_color(1).is_equal_approx(RED) and label_color(2).is_equal_approx(RED),"the team that took more (30 vs 0) is red for every member, even the untouched one")
	check(label_color(3).is_equal_approx(Color.WHITE),"the team that took less is white")
	refresh_hud()
	var team_side:Dictionary=hud_side("team:Team0");var solo_side:Dictionary=hud_side("team:Team1")
	check(world.duel_top_hud.sides.size()==2 and not team_side.is_empty() and not solo_side.is_empty(),"2 teams (2v1) still show the top duel HUD")
	if not team_side.is_empty() and not solo_side.is_empty():
		var name:String=world.duel_top_hud.side_name_text(team_side)
		check(bool(team_side.is_team) and ("队伍" in name or "Team" in name),"a multi-member team is shown as the team, not a character: "+name)
		check(not bool(solo_side.get("is_team",false)),"a one-member team is shown as its character")
		check(world.duel_top_hud.side_value_text(team_side)=="30" and world.duel_top_hud.side_value_text(solo_side)=="0","HUD value is only the number (team total), no label text")
		check(world.duel_top_hud.side_value_color(team_side).is_equal_approx(RED) and world.duel_top_hud.side_value_color(solo_side).is_equal_approx(Color.WHITE),"HUD numbers use the same white->red ranking colour")
	a2.health-=15
	b1.health-=50
	refresh_hud()
	team_side=hud_side("team:Team0");solo_side=hud_side("team:Team1")
	check(not team_side.is_empty() and is_equal_approx(float(team_side.damage),45.0),"team value is the sum of all members' damage taken (30+15)")
	check(label_color(3).is_equal_approx(RED) and label_color(1).is_equal_approx(Color.WHITE),"colours flip when the other team's total overtakes (50 > 45)")
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_finished and world._timed_winner_setup in [1,2],"team with the least TOTAL damage taken wins (45 < 50)")
	check(a1.health>0 and a2.health>0 and b1.health==0,"the whole winning team survives; the losing team is eliminated")

	# B. 3 teams: rank gradient, ties share colour, HUD hidden, team overtime.
	await fresh()
	a1=timed_actor(1,"Team0");a2=timed_actor(2,"Team1");b1=timed_actor(3,"Team2")
	world._timed_damage_by_setup={1:10.0,2:20.0,3:30.0}
	world._update_all_timed_damage_labels()
	check(label_color(1).is_equal_approx(Color.WHITE) and label_color(2).is_equal_approx(Color.WHITE.lerp(RED,0.5)) and label_color(3).is_equal_approx(RED),"3 teams: white / half-red / red by rank")
	world._timed_damage_by_setup={1:10.0,2:10.0,3:30.0}
	world._update_all_timed_damage_labels()
	check(label_color(1).is_equal_approx(Color.WHITE) and label_color(2).is_equal_approx(Color.WHITE) and label_color(3).is_equal_approx(RED),"tied teams share the same colour")
	refresh_hud()
	check(world.duel_top_hud.sides.size()!=2,"more than 2 teams: no duel panels (clock only)")
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_overtime and not world._timed_finished,"lowest team tie enters overtime")
	a2.health-=1
	check(world._timed_finished and world._timed_winner_setup==1 and a2.health==0 and b1.health==0 and a1.health>0,"first loss breaking the team tie settles immediately")

	# C. 2v2 through the real roster (_battle_setup): dead member's damage still counts for the team.
	await fresh()
	for row:Array in [[1,"Team0"],[2,"Team0"],[3,"Team1"],[4,"Team1"]]:
		world._battle_setup.append({"id":row[0],"team":row[1],"char":"ball","x":0.0,"y":0.0})
	a1=timed_actor(1,"Team0");a2=timed_actor(2,"Team0");b1=timed_actor(3,"Team1");var b2:Node=timed_actor(4,"Team1")
	world._timed_damage_by_setup={1:0.0,2:0.0,3:0.0,4:0.0}
	b2.health=0;b2.queue_free();await process_frame;await process_frame
	var dead_loss:float=float(world._timed_damage_by_setup[4])
	var totals:Dictionary=world.timed_team_scores()
	check(dead_loss>0.0 and is_equal_approx(float(totals.get("team:Team1",0.0)),dead_loss),"a listed member who died keeps contributing to the team total ("+str(dead_loss)+")")
	refresh_hud()
	check(world.duel_top_hud.sides.size()==2 and bool(hud_side("team:Team1").get("is_team",false)),"a team keeps its team panel after a member dies")
	world._timed_damage_by_setup[1]=dead_loss*0.5;world._timed_damage_by_setup[2]=dead_loss*0.5
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_overtime and not world._timed_finished,"2v2 equal team totals -> overtime")
	b1.health-=1
	check(world._timed_finished and world._timed_winner_setup in [1,2] and a1.health>0 and a2.health>0 and b1.health==0,"team overtime settled by the first loss; both winners survive")

	print("TIMED_TEAM_RESULT checks=%d failures=%d"%[checks,failures])
	game.Game_Settings=saved;game.now_stop_state=false
	if is_instance_valid(world):world.queue_free()
	current_scene=null
	await process_frame;await process_frame
	quit(0 if failures==0 else 1)
