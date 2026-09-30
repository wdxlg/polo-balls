extends "res://tests/test_sulfur_cube_balance.gd"
## Blaze has no friendly fire and never locks teammates, whatever the global
## Have_Team_Damage switch says (it only decides whether hits on teammates hurt).
## Checks the target predicate, nearest-enemy pick, fireball / fire-field damage
## filters, and a real burst with a teammate standing closer than the enemy.
var hits:Dictionary = {}

func hold(u:Node) -> void:
	if u.state_machine!=null:u.state_machine.set_physics_process(false)
	u.set_physics_process(false)
	u.Has_Collision_Damage=false

func unit(scene:String,n:String,team:String,pos:Vector2) -> Node2D:
	var u:Node2D=load(scene).instantiate();u.name=n;u.Team=team;u.position=pos
	world.add_child(u,true)
	return u

func run() -> void:
	game=root.get_node("Game")
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
	var c:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var blaze:Node2D=unit("res://scenes/characters/我的世界/烈焰人.tscn","BlazeT","Team0",c+Vector2(-50,0))
	var mate:Node2D=unit("res://scenes/ball.tscn","BlazeMate","Team0",c+Vector2(-10,0))
	var foe:Node2D=unit("res://scenes/ball.tscn","BlazeFoe","Team1",c+Vector2(60,0))
	var pet:Node2D=unit("res://scenes/ball.tscn","BlazePet","Ball",c+Vector2(-50,40))
	await process_frame
	for u:Node in [blaze,mate,foe,pet]:hold(u)
	for u:Node in [mate,foe,pet]:u.Can_Attack=false;u.Can_Skill=false;u.health=u.Max_health
	pet.Master=blaze
	game.combat_damage_resolved.connect(func(_src:Node,tgt:Node,amount:float,_b:float):
		if amount>0.0 and is_instance_valid(tgt):hits[str(tgt.name)]=float(hits.get(str(tgt.name),0.0))+amount)
	var FIREBALL:Script=load("res://scripts/effects/我的世界/烈焰弹.gd")
	var FIELD:Script=load("res://scripts/effects/我的世界/烈焰火场.gd")
	for team_damage:bool in [true,false]:
		game.Game_Settings.Have_Team_Damage=team_damage
		var tag:String="team damage "+("ON" if team_damage else "OFF")
		check(not blaze._is_enemy(mate) and not blaze._is_enemy(pet) and blaze._is_enemy(foe),"%s: blaze locks the enemy, never its teammate or own summon" % tag)
		check(blaze._nearest_enemy(9999.0)==foe,"%s: nearest enemy is the farther enemy, not the closer teammate" % tag)
		var fb:Node=FIREBALL.new();fb._source_team="Team0"
		var fd:Node=FIELD.new();fd._source_team="Team0"
		check(not fb._can_damage(mate) and fb._can_damage(foe),"%s: fireball explosion/burn skips teammates, hits enemies" % tag)
		check(not fd._can_damage(mate) and fd._can_damage(foe),"%s: fire field skips teammates, hits enemies" % tag)
		fb.free();fd.free()
	# Real bursts with team damage ON (the game default).
	game.Game_Settings.Have_Team_Damage=true
	if "_damage_output_disabled_until_msec" in blaze:blaze._damage_output_disabled_until_msec=0
	for i:int in range(5):await physics_frame
	hits.clear()
	var mate_hp:int=int(mate.health);var mate_max:int=int(mate.Max_health)
	for burst:int in range(3):
		blaze._burst_active=false
		blaze.Attack()
		var t:float=0.0
		while t<2.2:
			await physics_frame;t+=1.0/60.0
			mate.global_position=c+Vector2(-10,0);foe.global_position=c+Vector2(60,0)
	check(float(hits.get("BlazeFoe",0.0))>0.0,"real bursts hit the enemy (%.0f)" % float(hits.get("BlazeFoe",0.0)))
	check(float(hits.get("BlazeMate",0.0))==0.0 and int(mate.health)==mate_hp,"teammate standing closer takes no damage (%.0f, hp %d/%d -> %d)" % [float(hits.get("BlazeMate",0.0)),mate_hp,mate_max,int(mate.health)])
	check(float(hits.get("BlazePet",0.0))==0.0,"own summon takes no damage")
	game.Game_Settings.Have_Team_Damage=saved
	print("BLAZE_NO_TEAM_DAMAGE checks=",checks," failures=",failures," hits=",hits)
	world.queue_free();current_scene=null
	await process_frame
	quit(1 if failures>0 else 0)
