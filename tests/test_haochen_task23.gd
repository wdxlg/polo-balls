extends "res://tests/test_sulfur_cube_balance.gd"
## Haochen copies: halved stats from the initial form, own UI shrinking with the body,
## and no copy (or anything it launched) ever selecting Haochen's side as a target.
## Part A walks the whole roster with team damage ON (the game default) and calls
## every custom enemy predicate a copy has on Haochen and a teammate: all must refuse,
## while the same predicate on the original (enemy team) accepts that teammate.
## Env HAOCHEN_T23_ONLY=a,b limits part A to scene paths containing those words.
var TOOLS:Script
var GUARD:Script
var COPY_SCALE:Script
var hero:Node2D
const PREDICATES:Array[String] = ["_is_enemy","_is_valid_enemy","_is_attackable_enemy","_is_enemy_character",
	"_is_non_existent_enemy","_can_use_as_straw_side_enemy","_is_hostile_character","_is_valid_hook_enemy",
	"_is_control_attack_enemy","_is_legal_enemy","mc_enemy","slime_enemy","wt_enemy","_is_valid_potion_enemy",
	"_is_enemy_target","_enemy","_is_enemy_combatant","_valid_enemy","_is_enemy_ball","_is_war_enemy",
	"enemy_valid","is_bolt_enemy","is_landing_enemy","_can_target","_is_valid_target"]

func hold(u:Node) -> void:
	if u.state_machine!=null:u.state_machine.set_physics_process(false)
	u.set_physics_process(false)
	u.Has_Collision_Damage=false;u.Can_Skill=false

func unit(scene:String,n:String,team:String,pos:Vector2) -> Node2D:
	var u:Node2D=load(scene).instantiate();u.name=n;u.Team=team;u.position=pos
	world.add_child(u,true)
	return u

func copy_of(donor:Node2D,pos:Vector2) -> Node2D:
	var snap:Dictionary=TOOLS.capture_character_template(donor)
	return TOOLS.spawn_character_copy(hero,snap,pos,0.5,{"owner":hero,"parent":world,"full_vitals":true,"monochrome":true,
		"body_scale":0.5,"friendly_guard":true,"metadata":{"haochen_copy":true},"prepare_instance":func(u:Node2D):u.scale*=0.5})

func collect(dir_path:String,out:Array[String]) -> void:
	var dir:=DirAccess.open(dir_path)
	if dir==null:return
	for sub:String in dir.get_directories():collect(dir_path.path_join(sub),out)
	for file:String in dir.get_files():
		if file.ends_with(".tscn") and not file=="皓宸.tscn":out.append(dir_path.path_join(file))

func one_arg(obj:Object,method:String) -> bool:
	for m:Dictionary in obj.get_method_list():
		if str(m.name)==method:return (m.args as Array).size()-(m.default_args as Array).size()==1
	return false

func run() -> void:
	game=root.get_node("Game")
	TOOLS=load("res://scripts/characters/投稿角色工具.gd")
	GUARD=load("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd")
	COPY_SCALE=load("res://scripts/characters/我的世界/haochen/copy_body_scale.gd")
	var saved:bool=game.Game_Settings.Have_Team_Damage
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Have_Team_Damage=true
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var c:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	hero=unit("res://scenes/characters/我的世界/皓宸.tscn","T23Haochen","Team0",c+Vector2(0,40))
	var ally:Node2D=unit("res://scenes/ball.tscn","T23Ally","Team0",c+Vector2(40,0))
	await process_frame
	hold(hero);hold(ally);ally.Can_Attack=false
	ally.Max_health=100000;ally.health=100000

	# --- B: stats come from the copy's initial form ----------------------------------
	var warden:Node2D=unit("res://scenes/characters/我的世界/监守者.tscn","T23Warden","Team1",c+Vector2(-50,0))
	await process_frame
	hold(warden)
	var dormant_max:int=warden.Max_health
	warden.signals_received=5;warden.form=warden.Form.EMERGING;warden.form_left=0.0
	check(warden.finish_emergence() and warden.Max_health==dormant_max*2,"original warden awakens with double health (%d)" % warden.Max_health)
	var wcopy:Node2D=copy_of(warden,c+Vector2(-50,-40))
	await process_frame
	check(wcopy.Max_health==ceili(dormant_max*0.5),"copy of an AWAKE warden starts dormant with half the dormant health (%d, want %d)" % [wcopy.Max_health,ceili(dormant_max*0.5)])
	check(is_equal_approx(wcopy.Speed,wcopy.shrieker_speed),"dormant warden copy keeps the dormant crawl speed, not the chase speed (%.1f)" % wcopy.Speed)
	wcopy.signals_received=5;wcopy.form=wcopy.Form.EMERGING;wcopy.form_left=0.0;wcopy.finish_emergence()
	check(wcopy.Max_health==ceili(dormant_max*0.5)*2 and wcopy.Max_health*2==warden.Max_health,"awakened warden copy has half the awakened original health (%d vs %d)" % [wcopy.Max_health,warden.Max_health])
	check(is_equal_approx(COPY_SCALE.of(wcopy),0.5) and is_equal_approx(COPY_SCALE.of(warden),1.0),"copy body scale 0.5 for the copy, 1.0 for the original")
	for n:Node in [warden,wcopy]:n.queue_free()
	var sword:Node2D=unit("res://scenes/characters/我的世界/钻石剑.tscn","T23Diamond","Team1",c+Vector2(-50,0))
	await process_frame
	hold(sword)
	var base_max:int=sword.Max_health;var base_dmg:float=float(sword.Damage)
	sword.has_netherite_ingot=true;sword._upgrade_to_netherite()
	check(sword.upgraded_to_netherite and sword.Max_health>base_max,"diamond sword upgraded (%d > %d)" % [sword.Max_health,base_max])
	var dsnap:Dictionary=TOOLS.capture_character_template(sword)
	check(int(dsnap.stats.Max_health)==base_max and is_equal_approx(float(dsnap.stats.Damage),base_dmg),"copy template of an upgraded sword uses the un-upgraded base (%s)" % str(dsnap.stats))
	sword.queue_free()
	var rabbit:Node2D=load("res://scenes/characters/动物/兔子.tscn").instantiate();rabbit.name="T23Bunny";rabbit.Team="Team1";rabbit.position=c+Vector2(-50,0)
	rabbit.is_baby=true
	world.add_child(rabbit,true)
	await process_frame
	hold(rabbit)
	var rsnap:Dictionary=TOOLS.capture_character_template(rabbit)
	check(rabbit.Max_health<rabbit._adult_max_health and int(rsnap.stats.Max_health)==rabbit._adult_max_health,"copy of a baby rabbit (a fresh adult) uses adult health (%d)" % int(rsnap.stats.Max_health))
	rabbit.queue_free()
	var wood:Node2D=unit("res://scenes/characters/我的世界/木剑.tscn","T23Wood","Team1",c+Vector2(-50,0))
	await process_frame
	hold(wood)
	var whole:int=wood.Max_health
	wood.full_max_health=whole;wood.part_kind=1;wood.Max_health=ceili(whole*0.5)
	check(int(TOOLS.capture_character_template(wood).stats.Max_health)==whole,"copy of a split hilt (a fresh whole sword) uses whole sword health")
	wood.queue_free()
	await process_frame

	# --- C: overlays that ignore the parent scale shrink with the copy -----------------
	var ws:Node2D=unit("res://scenes/characters/我的世界/凋灵骷髅.tscn","T23WS","Team1",c+Vector2(-50,0))
	await process_frame
	hold(ws)
	var wsc:Node2D=copy_of(ws,c+Vector2(-50,-40))
	await process_frame
	check(is_equal_approx(wsc.blade_length,ws.blade_length*0.5) and is_equal_approx(wsc.blade_radius,ws.blade_radius*0.5) and is_equal_approx(wsc.acquisition_range,ws.acquisition_range*0.5),"wither skeleton copy holds a half-size sword (%.2f vs %.2f)" % [wsc.blade_length,ws.blade_length])
	var STUN:Script=load("res://scripts/effects/stun_visual.gd")
	var sa:Node2D=STUN.new();sa.setup(ws);ws.add_child(sa)
	var sb:Node2D=STUN.new();sb.setup(wsc);wsc.add_child(sb)
	await process_frame
	check(is_equal_approx(sb.global_scale.x,sa.global_scale.x*0.5),"stun swirl over the copy is half size (%.3f vs %.3f)" % [sb.global_scale.x,sa.global_scale.x])
	for n:Node in [ws,wsc]:n.queue_free()
	var boss:Node2D=unit("res://scenes/characters/人物/伪军头子.tscn","T23Boss","Team1",c+Vector2(-50,0))
	await process_frame
	hold(boss)
	var bossc:Node2D=copy_of(boss,c+Vector2(-50,-40))
	for i:int in range(3):await process_frame
	var MONEY:Script=load("res://scripts/ui/伪军头子钞票UI.gd")
	var ua:Node2D=null;var ub:Node2D=null
	for n:Node in boss.get_children():if n.get_script()==MONEY:ua=n
	for n:Node in bossc.get_children():if n.get_script()==MONEY:ub=n
	if ua!=null and ub!=null:
		check(is_equal_approx(ub.global_scale.x,ua.global_scale.x*0.5),"money UI over the copy is half size (%.3f vs %.3f)" % [ub.global_scale.x,ua.global_scale.x])
	else:check(false,"money UI found on original and copy (%s %s)" % [ua,ub])
	for n:Node in [boss,bossc]:n.queue_free()
	await process_frame

	# --- A: no copy predicate selects Haochen's side ---------------------------------
	var only:String=OS.get_environment("HAOCHEN_T23_ONLY")
	var scenes:Array[String]=[];collect("res://scenes/characters",scenes);scenes.sort()
	var calls:int=0;var control_true:int=0;var bad:Array[String]=[]
	for path:String in scenes:
		if not only.is_empty():
			var keep:bool=false
			for w:String in only.split(",",false):keep=keep or path.contains(w)
			if not keep:continue
		var donor:Node=load(path).instantiate()
		if not (donor is CharacterBody2D) or not donor.has_method("receive_positional_damage"):donor.free();continue
		donor.name="T23Donor";donor.Team="Team1";donor.position=c+Vector2(-60,-30)
		world.add_child(donor,true)
		await process_frame
		if not is_instance_valid(donor):continue
		hold(donor)
		var cp:Node2D=copy_of(donor,c+Vector2(-20,-30))
		if cp==null:donor.queue_free();continue
		await process_frame
		if is_instance_valid(cp):
			hold(cp)
			for m:String in PREDICATES:
				if not cp.has_method(m) or not one_arg(cp,m):continue
				for victim:Node2D in [ally,hero]:
					calls+=1
					if bool(cp.call(m,victim)):bad.append("%s.%s(%s)" % [path.get_file(),m,victim.name])
				if is_instance_valid(donor) and bool(donor.call(m,ally)):control_true+=1
			if bool(TOOLS.is_enemy(cp,ally)) or bool(TOOLS.is_enemy(cp,hero)):bad.append("%s TOOLS.is_enemy" % path.get_file())
			calls+=2
		for n:Node in [donor,cp]:
			if is_instance_valid(n):n.queue_free()
		await process_frame
	check(bad.is_empty(),"no copy predicate accepts Haochen or his teammate (%d calls): %s" % [calls,str(bad.slice(0,12))])
	check(control_true>=10 or not only.is_empty(),"the same predicates on the enemy-team originals do accept that teammate (%d), so the guard is what refuses" % control_true)
	game.Game_Settings.Have_Team_Damage=saved
	print("HAOCHEN_TASK23 checks=",checks," failures=",failures," predicate_calls=",calls," control_true=",control_true)
	world.queue_free();current_scene=null
	await process_frame
	quit(1 if failures>0 else 0)
