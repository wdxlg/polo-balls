extends "res://tests/test_sulfur_cube_balance.gd"
## Full-roster friendly-fire sweep: for every character scene, a real Haochen
## copy (TOOLS.spawn_character_copy) fights a dummy next to its stationary
## master for 3 s. Any health loss on Haochen whose resolved source chain is
## Haochen (copy, its projectiles/summons/AOE) is friendly fire. Runs with the
## game's default Have_Team_Damage=true and with false.
var HAOCHEN:PackedScene
var TOOLS:Script
var hero:Node2D
var hits:Dictionary = {}
var trace:bool = false
var current_path:String = ""

func collect(dir_path:String,out:Array[String]) -> void:
	var dir:=DirAccess.open(dir_path)
	if dir==null:return
	for sub:String in dir.get_directories():collect(dir_path.path_join(sub),out)
	for file:String in dir.get_files():
		if not file.ends_with(".tscn"):continue
		var path:String=dir_path.path_join(file)
		if path.ends_with("我的世界/皓宸.tscn"):continue
		var head:String=FileAccess.get_file_as_string(path).substr(0,1200)
		if head.contains("res://scenes/ball.tscn"):out.append(path)

func on_damage(source:Node,target:Node,amount:float,_before:float) -> void:
	if target==hero and amount>0.0:
		var key:String=str(source.name) if is_instance_valid(source) else "?"
		if trace and not hits.has(key):push_error("SWEEP_TRACE scene=%s source=%s" % [current_path,key])
		hits[key]=float(hits.get(key,0.0))+amount

func run() -> void:
	game=root.get_node("Game")
	HAOCHEN=load("res://scenes/characters/我的世界/皓宸.tscn")
	TOOLS=load("res://scripts/characters/投稿角色工具.gd")
	var only:String=OS.get_environment("HAOCHEN_SWEEP_ONLY")
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
	game.combat_damage_resolved.connect(on_damage)
	var scenes:Array[String]=[]
	collect("res://scenes/characters",scenes)
	scenes.sort()
	if not only.is_empty():
		var wanted:PackedStringArray=only.split(",",false)
		scenes=scenes.filter(func(p):
			for w:String in wanted:
				if p.ends_with("/"+w+".tscn"):return true
			return false)
	trace=OS.get_environment("HAOCHEN_SWEEP_TRACE")=="1"
	var modes:Array=[true,false]
	if OS.get_environment("HAOCHEN_SWEEP_MODE")=="on":modes=[true]
	print("SWEEP_SCENES ",scenes.size())
	var offenders:Array[String]=[]
	var spawned_ok:int=0
	var size_bad:Array[String]=[]
	for team_damage:bool in modes:
		game.Game_Settings.Have_Team_Damage=team_damage
		for path:String in scenes:
			current_path=path
			var before:Dictionary={}
			for c:Node in world.get_children():before[c.get_instance_id()]=true
			hits.clear()
			hero=HAOCHEN.instantiate();hero.name="SweepHaochen";hero.Team="Team0";hero.position=center
			world.add_child(hero,true)
			var dummy:Node2D=load("res://scenes/ball.tscn").instantiate();dummy.name="SweepDummy";dummy.Team="Team1";dummy.position=center+Vector2(70,0)
			world.add_child(dummy,true)
			await process_frame
			for u:Node in [hero,dummy]:
				u.state_machine.set_physics_process(false);u.set_physics_process(false)
				u.Has_Collision_Damage=false;u.Can_Attack=false;u.Can_Skill=false
			dummy.Max_health=1000000;dummy.health=1000000
			var donor:Node=load(path).instantiate()
			var snap:Dictionary={}
			if donor.get("Max_health")!=null and donor.has_method("_refresh_character_copy_visuals"):
				var stats:Dictionary={}
				for key:String in TOOLS.COPY_STAT_KEYS:stats[key]=donor.get(key)
				snap={"scene":path,"label":path.get_file().get_basename(),"stats":stats,"health":1,"block":0,"energy":0}
			donor.free()
			var copy:Node=null
			if not snap.is_empty():
				copy=TOOLS.spawn_character_copy(hero,snap,center+Vector2(28,0),0.5,{"owner":hero,"parent":world,"full_vitals":true,"monochrome":true,"metadata":{"haochen_copy":true},
					"body_scale":0.5,"prepare_instance":func(u:Node2D):u.scale*=0.5})
				# Task 9: the copy is half size, its health bar keeps the normal size.
				if is_instance_valid(copy):
					var probe:Node2D=load(path).instantiate()
					var want:Vector2=probe.scale*0.5
					# Readable = the bar's on-screen size is not halved with the body (some
					# characters trim their own bar in _ready, e.g. MC mobs 0.9x).
					var bar_normal:float=absf((probe.get_node("Health_Bar") as Control).scale.x*probe.scale.x) if probe.get_node_or_null("Health_Bar") is Control else 0.0
					probe.free()
					var bar:Control=copy.get_node_or_null("Health_Bar") as Control
					var bar_now:float=absf(bar.get_global_transform().get_scale().x) if bar!=null else 0.0
					if not copy.scale.is_equal_approx(want) or (bar!=null and bar_now<0.85*bar_normal):
						var line:String="SWEEP_SIZE scene=%s scale=%s want=%s bar=%.4f normal=%.4f" % [path,copy.scale,want,bar_now,bar_normal]
						print(line);size_bad.append(line)
			var spawned:bool=copy!=null
			var lost:int=0
			for f:int in range(180):
				if not is_instance_valid(hero):lost=-1;break
				hero.health=hero.Max_health # refill, then measure this frame's drop
				await physics_frame
				if is_instance_valid(hero) and int(hero.health)<int(hero.Max_health):lost+=int(hero.Max_health)-int(hero.health)
				if is_instance_valid(dummy):dummy.health=1000000
			var total:float=0.0
			for k:String in hits:total+=float(hits[k])
			if total>0.0 or lost>0:
				var line:String="SWEEP_HIT team_damage=%s scene=%s copy=%s resolved=%s lost=%d" % [str(team_damage),path,str(copy.name) if is_instance_valid(copy) else "<gone>",str(hits),lost]
				print(line);offenders.append(line)
			if not spawned:
				print("SWEEP_NOCOPY team_damage=",team_damage," scene=",path)
			else:spawned_ok+=1
			for c:Node in world.get_children():
				if not before.has(c.get_instance_id()) and not c.is_queued_for_deletion():c.queue_free()
			for n:Node in get_nodes_in_group("BattleTransient"):
				if is_instance_valid(n) and not n.is_queued_for_deletion():n.queue_free()
			for i:int in range(3):await process_frame
	print("SWEEP_DONE spawned=",spawned_ok," offenders=",offenders.size())
	print("SWEEP_SIZE_DONE bad=",size_bad.size())
	check(size_bad.is_empty(),"every copy is exactly half size with a readable health bar")
	for l:String in offenders:print("SWEEP_SUMMARY ",l)
	check(spawned_ok==scenes.size()*modes.size(),"every roster character produced a real Haochen copy in every team-damage mode")
	check(offenders.is_empty(),"no copy (nor its projectiles, summons, AOE or offspring) ever damaged Haochen")
	print("HAOCHEN_FRIENDLY_SWEEP checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
