extends "res://tests/test_sulfur_cube_balance.gd"
## Task 10 (2026-09-28, user: "它的复制的东西还是会攻击友军。还有复制的ui也应该一起缩小").
## A real Haochen cast copies a real skeleton; then, with the global team-damage setting
## on AND off, every shared damage entry (hitbox contact, positional, spatial raw and
## classified, internal bleed) must refuse damage from the copy chain to Haochen's side
## (ally, ally's summon, Haochen) while the copy still hurts enemies and ordinary
## teammates keep the normal rules. The copy's own UI shrinks with its half-size body.
var HAOCHEN:PackedScene
var REQUEST:PackedScene

func hold(u:Node) -> void:
	u.state_machine.set_physics_process(false);u.set_physics_process(false)
	u.Has_Collision_Damage=false;u.Can_Attack=false;u.Can_Skill=false

func unit(scene:String,n:String,team:String,pos:Vector2) -> Node2D:
	var u:Node2D=load(scene).instantiate();u.name=n;u.Team=team;u.position=pos
	world.add_child(u,true)
	return u

func refill(list:Array) -> void:
	for u:Node in list:
		if is_instance_valid(u):u.Max_health=100000;u.health=100000;u.block=0

func run() -> void:
	game=root.get_node("Game")
	HAOCHEN=load("res://scenes/characters/我的世界/皓宸.tscn")
	var saved:bool=game.Game_Settings.Have_Team_Damage
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var BALL:String="res://scenes/ball.tscn"
	var hero:Node2D=unit("res://scenes/characters/我的世界/皓宸.tscn","T10Haochen","Team0",center)
	var donor:Node2D=unit("res://scenes/characters/我的世界/骷髅.tscn","T10Skeleton","Team1",center+Vector2(60,0))
	var ally:Node2D=unit(BALL,"T10Ally","Team0",center+Vector2(-60,40))
	var mate:Node2D=unit(BALL,"T10Mate","Team0",center+Vector2(-60,-40))
	var enemy:Node2D=unit(BALL,"T10Enemy","Team1",center+Vector2(0,70))
	await process_frame
	for u:Node in [hero,donor,ally,mate,enemy]:hold(u)
	check(hero.is_in_group(&"character_copy_friendly_guard"),"Haochen is a friendly-copy guard")
	# --- real cast ---------------------------------------------------------------
	for i:int in range(120):
		hero._scan_left=0.0;hero._step_energy(0.1)
		if hero.charge_phase==hero.Phase.COPYING:break
	var t:float=0.0
	while hero.completed_copies<1 and t<4.0:
		await physics_frame;t+=1.0/60.0
	var copy:Node2D=null
	for n:Node in world.get_children():
		if n!=donor and n.get_meta("haochen_copy",false):copy=n
	check(is_instance_valid(copy),"the real cast produced a copy of the skeleton")
	if not is_instance_valid(copy):
		print("HAOCHEN_TASK10 checks=",checks," failures=",failures);quit(1);return
	hold(copy)
	copy.global_position=center+Vector2(-30,0)
	check(bool(copy.character_copy_profile.get("friendly_guard",false)) and copy.is_in_group(&"character_copy_friendly_guard"),"the real copy request marks the copy as guarded through the replicated profile")
	# --- UI shrink ------------------------------------------------------------------
	var cbar:Control=copy.get_node("Health_Bar") as Control;var dbar:Control=donor.get_node("Health_Bar") as Control
	check(cbar.scale.is_equal_approx(dbar.scale),"copy health bar has no counter-scale (local %s vs %s)" % [cbar.scale,dbar.scale])
	check(cbar.get_global_transform().get_scale().abs().is_equal_approx(dbar.get_global_transform().get_scale().abs()*0.5),"copy health bar is drawn at half size with the body")
	var cst:Node2D=copy.get_node_or_null("Status_Image") as Node2D;var dst:Node2D=donor.get_node_or_null("Status_Image") as Node2D
	if cst!=null and dst!=null:check(cst.global_scale.abs().is_equal_approx(dst.global_scale.abs()*0.5),"copy status icon is drawn at half size")
	# Offspring: a legacy summon of the copy still on the default "Ball" team, and an
	# ally's own summon (also on "Ball", Master = ally).
	var spawnling:Node2D=unit(BALL,"T10CopySummon","Ball",center+Vector2(-20,20));spawnling.Master=copy
	var ally_pet:Node2D=unit(BALL,"T10AllyPet","Ball",center+Vector2(-80,60));ally_pet.Master=ally
	await process_frame
	hold(spawnling);hold(ally_pet)
	var everyone:Array=[hero,ally,mate,enemy,ally_pet,copy,spawnling]
	for team_damage:bool in [true,false]:
		game.Game_Settings.Have_Team_Damage=team_damage
		var tag:String=" (team damage %s)" % ("on" if team_damage else "off")
		for src:Node in [copy,spawnling,hero]:
			for victim:Node2D in [ally,ally_pet,hero]:
				if victim==src:continue
				refill(everyone)
				var ok:bool=victim.receive_positional_damage(25.0,victim.global_position,false,src)
				check(not ok and victim.health==100000,"positional: %s cannot hurt %s%s" % [src.name,victim.name,tag])
				refill(everyone)
				ok=victim._receive_spatial_damage_untyped(25.0,{"point":victim.global_position,"source":src},false,true)
				check(not ok and victim.health==100000,"raw spatial: %s cannot hurt %s%s" % [src.name,victim.name,tag])
				refill(everyone)
				ok=victim._receive_spatial_damage_untyped(25.0,{"point":victim.global_position,"source":src},false,false)
				check(not ok and victim.health==100000,"spatial: %s cannot hurt %s%s" % [src.name,victim.name,tag])
				refill(everyone)
				var bled:float=victim.receive_internal_status_damage(25.0,&"bleed",src)
				check(bled<=0.0 and victim.health==100000,"bleed: %s cannot hurt %s%s" % [src.name,victim.name,tag])
		# Contact: the copy's own body hitbox against the ally and the enemy.
		refill(everyone)
		copy.Has_Collision_Damage=true
		var hb:Node=copy.get_node("hitbox")
		hb._last_hit_msec_by_target.clear() # the previous round's enemy hit is inside the duplicate-hit guard
		var hit_ally:bool=hb.try_hit_hurtbox(ally.self_hurtbox)
		check(not hit_ally and ally.health==100000,"contact: the copy's hitbox cannot hurt the ally"+tag)
		var hit_enemy:bool=hb.try_hit_hurtbox(enemy.self_hurtbox)
		check(hit_enemy,"contact: the copy's hitbox still lands on the enemy"+tag)
		copy.Has_Collision_Damage=false
		# Controls: enemies still take copy-chain damage.
		refill(everyone)
		check(enemy.receive_positional_damage(25.0,enemy.global_position,false,copy) and enemy.health<100000,"the copy still damages enemies"+tag)
		refill(everyone)
		check(enemy.receive_positional_damage(25.0,enemy.global_position,false,spawnling) and enemy.health<100000,"the copy's summon still damages enemies"+tag)
		refill(everyone)
		check(donor.receive_internal_status_damage(25.0,&"bleed",copy)>0.0,"the copy's bleed still hurts the enemy it copied"+tag)
		# Ordinary teammates keep the normal rule (the guard is not a global switch).
		var U:Script=load("res://scripts/characters/我的世界/new5/utils.gd")
		check(not U.enemy(copy,ally) and not U.enemy(copy,ally,true) and not U.enemy(spawnling,ally_pet) and U.enemy(copy,enemy),"shared target helper: the copy chain never picks Haochen's side, still picks enemies"+tag)
		check(U.enemy(mate,ally)==team_damage,"shared target helper: ordinary teammates keep the team-damage rule"+tag)
		refill(everyone)
		check(ally.receive_positional_damage(25.0,ally.global_position,false,mate) and ally.health<100000,"an ordinary teammate's damage entry is untouched"+tag)
	game.Game_Settings.Have_Team_Damage=saved
	# Free-for-all: with no team, only Haochen and his own chain count as his side.
	hero.Team="";copy.Team="";copy.set_meta(&"forced_combat_team","")
	refill(everyone)
	check(not hero.receive_positional_damage(25.0,hero.global_position,false,copy),"no teams: the copy still never hurts Haochen")
	refill(everyone)
	check(ally.receive_positional_damage(25.0,ally.global_position,false,copy),"no teams: someone outside Haochen's chain is not his side")
	print("HAOCHEN_TASK10 checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
