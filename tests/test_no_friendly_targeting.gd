extends "res://tests/test_sulfur_cube_balance.gd"
## Character-specific targeting and damage never pick or hurt teammates, whatever the
## global Have_Team_Damage switch says. The switch only decides generic hitbox contact
## (classes/hitbox.gd); a character's own enemy predicate, skill damage filter and
## projectile filter always exclude the same Team, like World's nearest-enemy rule.
const ALLOWED_SWITCH_READERS:Array[String] = [
	"res://classes/hitbox.gd", # generic body / bullet contact: the one place the switch applies
	"res://scripts/characters/传说之下/Sans.gd", # dodge: a teammate's generic hitbox can still hurt him
	"res://scripts/terrain/生成地形安全管理器.gd", # terrain passability, not targeting
]
# [scene, method, kind]; kind "enemy" = true for foe, false for mate; "friendly" = inverse.
const CHARACTERS:Array = [
	["res://scenes/characters/人物/保安.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/决斗者.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/影子.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/拳击手.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/矿工.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/鼓手.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/猎人.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/裁判.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/炸弹客.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/人物/炮兵.tscn","_can_hit_target","enemy"],
	["res://scenes/characters/人物/时光客.tscn","_can_rewind_damage","enemy"],
	["res://scenes/characters/人物/火车长.tscn","_is_valid_mining_target","enemy"],
	["res://scenes/characters/人物/小丑.tscn","_can_damage_ball","enemy"],
	["res://scenes/characters/人物/剑客.tscn","_is_friendly","friendly"],
	["res://scenes/characters/乐队/户山香澄.tscn","_is_enemy","enemy"],
	["res://scenes/characters/乐队/若叶睦.tscn","_is_valid_enemy","enemy"],
	["res://scenes/characters/meme/棍母.tscn","_is_non_existent_enemy","enemy"],
	["res://scenes/characters/我的世界/苦力怕.tscn","_is_enemy","enemy"],
	["res://scenes/characters/我的世界/重锤.tscn","_is_enemy","enemy"],
	["res://scenes/characters/我的世界/钻石剑.tscn","_is_enemy_target","enemy"],
	["res://scenes/characters/我的世界/铁匠村民.tscn","_is_enemy_target","enemy"],
	["res://scenes/characters/我的世界/女巫.tscn","_is_valid_potion_enemy","enemy"],
	["res://scenes/characters/我的世界/烈焰人.tscn","_is_enemy","enemy"],
	["res://scenes/characters/我的世界/末影人.tscn","mc_enemy","enemy"], # mc_mob_base
	["res://scenes/characters/游戏/战争女神.tscn","_is_war_enemy","enemy"],
	["res://scenes/characters/游戏/魔角猎人.tscn","_is_enemy","enemy"],
	["res://scenes/characters/AI/磐灯守卫.tscn","enemy_valid","enemy"], # ai_original_base
]
# [script, {member:value}, method, kind, pass_master]
const PROJECTILES:Array = [
	["res://scripts/effects/我的世界/骷髅箭.gd",{"_source_team":"Team0"},"_can_damage_target","enemy",false],
	["res://scripts/shooter/战争女神_火焰剑气.gd",{"team":"Team0"},"_can_damage_target","enemy",false],
	["res://scripts/shooter/时光客时钟.gd",{"Team":"Team0"},"_should_ignore_character","friendly",false],
	["res://scripts/shooter/猎人_霰弹.gd",{"Team":"Team0"},"_can_damage_target","enemy",true],
	["res://scripts/shooter/猎人_霰弹.gd",{"Team":"Team0"},"_should_pass_through","friendly",true],
	["res://scripts/shooter/魔角猎人_黑弹.gd",{"Team":"Team0"},"_can_damage_target","enemy",true],
	["res://scripts/shooter/魔角猎人_黑弹.gd",{"Team":"Team0"},"_should_pass_through","friendly",true],
	["res://scripts/shooter/炸弹客炸弹.gd",{"Team":"Team0"},"_can_damage_target","enemy",true],
	["res://scripts/effects/薇欧拉_火场.gd",{"Team":"Team0"},"_is_enemy","enemy",false],
	["res://scripts/effects/薇欧拉_火焰弹.gd",{},"_is_enemy","enemy",true],
	["res://scripts/effects/传说之下/Sans骨头攻击.gd",{"source_team":"Team0"},"_is_enemy","enemy",false],
	["res://scripts/effects/传说之下/Sans滚动骨头.gd",{"source_team":"Team0"},"_is_enemy","enemy",false],
	["res://scripts/effects/传说之下/Sans龙骨炮.gd",{"source_team":"Team0"},"_is_enemy","enemy",false],
]

func hold(u:Node) -> void:
	if "state_machine" in u and u.state_machine!=null:u.state_machine.set_physics_process(false)
	u.set_physics_process(false)
	u.set_process(false)
	if "Has_Collision_Damage" in u:u.Has_Collision_Damage=false

func unit(scene:String,n:String,team:String,pos:Vector2) -> Node2D:
	var u:Node2D=load(scene).instantiate();u.name=n;u.Team=team;u.position=pos
	world.add_child(u,true)
	return u

func judge(result:Variant,kind:String,is_foe:bool) -> bool:
	var ok:bool = result is bool and result
	if result is Object:ok = result != null
	return ok == (is_foe if kind=="enemy" else not is_foe)

func scan(dir:String,out:Array) -> void:
	for sub:String in DirAccess.get_directories_at(dir):
		if dir=="res://scripts" and sub=="training":continue
		scan(dir.path_join(sub),out)
	for f:String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):out.append(dir.path_join(f))

func run() -> void:
	game=root.get_node("Game")
	var saved:bool=game.Game_Settings.Have_Team_Damage
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	AudioServer.set_bus_mute(0,true)
	# Source guard: nobody else may let the switch decide whom a skill locks or hurts.
	var files:Array=[];scan("res://classes",files);scan("res://scripts",files)
	var offenders:Array=[]
	for path:String in files:
		if path in ALLOWED_SWITCH_READERS:continue
		for line:String in FileAccess.get_file_as_string(path).split("\n"):
			var code:String=line.split("#")[0]
			if code.contains("Have_Team_Damage"):offenders.append(path);break
	check(files.size()>300 and offenders.is_empty(),"only hitbox contact reads the team damage switch (%d scripts, offenders %s)" % [files.size(),str(offenders)])
	world=load("res://scenes/world.tscn").instantiate()
	world.default_map="Map30x30"
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var c:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var mate:Node2D=unit("res://scenes/ball.tscn","NFMate","Team0",c+Vector2(-60,80))
	var foe:Node2D=unit("res://scenes/ball.tscn","NFFoe","Team1",c+Vector2(60,80))
	var owner_ball:Node2D=unit("res://scenes/ball.tscn","NFOwner","Team0",c+Vector2(0,120))
	await process_frame
	for u:Node in [mate,foe,owner_ball]:
		hold(u);u.Can_Attack=false;u.Can_Skill=false;u.health=u.Max_health
		if "_damage_output_disabled_until_msec" in u:u._damage_output_disabled_until_msec=0
	var bad:Array=[]
	var tested:int=0
	for entry:Array in CHARACTERS:
		var who:Node2D=unit(entry[0],"NF"+entry[0].get_file().get_basename(),"Team0",c+Vector2(0,-60))
		await process_frame
		hold(who)
		if "_damage_output_disabled_until_msec" in who:who._damage_output_disabled_until_msec=0
		if not who.has_method(entry[1]):
			bad.append("%s missing %s" % [who.name,entry[1]])
		else:
			tested+=1
			for team_damage:bool in [true,false]:
				game.Game_Settings.Have_Team_Damage=team_damage
				if not judge(who.call(entry[1],mate),entry[2],false):bad.append("%s picks teammate (team damage %s)" % [who.name,team_damage])
				if not judge(who.call(entry[1],foe),entry[2],true):bad.append("%s rejects enemy (team damage %s)" % [who.name,team_damage])
		who.queue_free()
		await process_frame
	check(bad.is_empty() and tested==CHARACTERS.size(),"%d character predicates exclude teammates and accept enemies, team damage ON and OFF: %s" % [tested,str(bad)])
	# new5 shared helper
	var UTILS:Script=load("res://scripts/characters/我的世界/new5/utils.gd")
	game.Game_Settings.Have_Team_Damage=true
	check(not UTILS.enemy(owner_ball,mate) and UTILS.enemy(owner_ball,foe),"new5 utils.enemy excludes teammates with team damage ON")
	var pbad:Array=[]
	for entry:Array in PROJECTILES:
		var obj:Object=load(entry[0]).new()
		for key:String in entry[1]:
			if key in obj:obj.set(key,entry[1][key])
			else:pbad.append("%s has no %s" % [entry[0].get_file(),key])
		for team_damage:bool in [true,false]:
			game.Game_Settings.Have_Team_Damage=team_damage
			var args_mate:Array=[mate,owner_ball] if entry[4] else [mate]
			var args_foe:Array=[foe,owner_ball] if entry[4] else [foe]
			if not judge(obj.callv(entry[2],args_mate),entry[3],false):pbad.append("%s.%s teammate (td %s)" % [entry[0].get_file(),entry[2],team_damage])
			if not judge(obj.callv(entry[2],args_foe),entry[3],true):pbad.append("%s.%s enemy (td %s)" % [entry[0].get_file(),entry[2],team_damage])
		if obj is Node:obj.free()
	check(pbad.is_empty(),"%d projectile / field filters never hurt the shooter's team: %s" % [PROJECTILES.size(),str(pbad)])
	game.Game_Settings.Have_Team_Damage=saved
	print("NO_FRIENDLY_TARGETING checks=",checks," failures=",failures)
	world.queue_free();current_scene=null
	await process_frame
	quit(1 if failures>0 else 0)
