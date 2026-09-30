extends SceneTree
# Infinite-health targets behave like a normal armor stand for everything that settles on actual
# health damage (bat lifesteal, hit feedback, combat stats); only INF-class damage or a specific
# mechanic can kill them.
const BAT_SCENE:String = "res://scenes/characters/我的世界/蝙蝠.tscn"
const IMMORTAL_SCENE:String = "res://scenes/characters/默认/不死盔甲架.tscn"
const STAND_SCENE:String = "res://scenes/characters/默认/盔甲架.tscn"
var world:Node
var game:Node
var saved:Dictionary
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("BAT_INF_OK ",label)
	else:
		failures += 1
		print("BAT_INF_FAIL ",label)
func spawn(path:String,point:Vector2,team:String) -> Node2D:
	var unit:Node2D = load(path).instantiate() as Node2D
	unit.Team = team
	unit.position = point
	world.add_child(unit,true)
	return unit
func frames(n:int) -> void:
	for i in n: await process_frame
func quiet(unit:Node) -> void:
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	if unit.state_machine != null: unit.state_machine.set_physics_process(false)
	if "hurt_sound_chance" in unit: unit.hurt_sound_chance = 0.0
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():print("BAT_INF_TIMEOUT");quit(2))
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
	world.control.hide();world.control.team.hide()
	var c:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()

	# A. A bat drains an immortal armor stand exactly like a normal armor stand.
	var immortal:Node2D=spawn(IMMORTAL_SCENE,c,"Team1")
	var stand:Node2D=spawn(STAND_SCENE,c+Vector2(0,60),"Team1")
	var bat:Node2D=spawn(BAT_SCENE,c+Vector2(-6,0),"Team0")
	await frames(4)
	for u in [immortal,stand]: quiet(u)
	for m in bat.living_members(): m.state_machine.set_physics_process(false)
	var leader:Node2D=bat
	var bite:float=leader.attack_damage()
	check(bite>0.0 and leader.mc_enemy(immortal),"bat treats the immortal stand as an enemy (bite %s)"%bite)
	var max0:int=leader.Max_health;var hp0:int=int(leader.health)
	var got:int=leader.drain_target(immortal)
	check(got==int(round(bite)),"drain on the immortal stand yields the full bite (%d/%s)"%[got,bite])
	check(leader.Max_health==max0+got and int(leader.health)==mini(leader.Max_health,hp0+got),"bat grows and heals from the immortal stand (%d->%d, %d->%d)"%[max0,leader.Max_health,hp0,int(leader.health)])
	check(int(immortal.health)==1 and immortal.state_machine.current_state!=immortal.State.Die,"immortal stand keeps its 1 HP and stays alive")
	leader.global_position=stand.global_position+Vector2(-6,0)
	var got_stand:int=leader.drain_target(stand)
	check(got_stand==got,"same bite on a normal armor stand drains the same amount (%d vs %d)"%[got_stand,got])
	# Latch: begin_bite succeeds and the host stays attached through repeated drains.
	leader.global_position=leader.target_surface(immortal)
	leader._cooldown=0.0;leader._shield_bite_wait=0.0
	leader.begin_bite(immortal)
	check(leader.attached_target()==immortal,"bat latches onto the immortal stand")
	var max1:int=leader.Max_health
	var ok_repeat:bool=true
	for i in 6:
		if leader.drain_target(immortal)<=0: ok_repeat=false
	check(ok_repeat and leader.Max_health==max1+6*got,"repeated drains keep feeding (%d->%d)"%[max1,leader.Max_health])
	leader.detach()

	# B. Ordinary damage never kills it, however large; the absorbed part is recorded.
	var abs0:float=immortal.absorbed_health_loss
	var r0:float=immortal.health_loss_reading()
	immortal.receive_positional_damage(1234567.0,immortal.global_position,false,null)
	immortal.take_damage(50.0)
	immortal.health-=80
	await frames(3)
	check(int(immortal.health)==1 and is_instance_valid(immortal) and immortal.state_machine.current_state!=immortal.State.Die,"huge / direct / legacy damage cannot kill it")
	check(is_equal_approx(immortal.absorbed_health_loss-abs0,1234567.0+50.0+80.0),"all three paths record the absorbed damage (%s)"%(immortal.absorbed_health_loss-abs0))
	check(is_equal_approx(r0-immortal.health_loss_reading(),1234567.0+50.0+80.0),"health_loss_reading drops by the damage taken")

	# C. Hitbox hits: same feedback nodes as on a normal armor stand (no doubled hit burst).
	var attacker:Node2D=spawn(STAND_SCENE,c+Vector2(-30,30),"Team0")
	await frames(2)
	quiet(attacker);attacker.Damage=12;attacker._damage_output_disabled_until_msec=0
	check(attacker.attack_damage()>0.0,"test attacker deals damage (%s)"%attacker.attack_damage())
	var counts:Array=[]
	for target in [stand,immortal]:
		target.global_position=attacker.global_position+Vector2(14,0)
		await frames(2)
		var before_children:int=world.get_child_count()
		var before_reading:float=target.health_loss_reading()
		attacker.Damage=12;attacker._damage_output_disabled_until_msec=0
		attacker._on_hitbox_on_hit(target.self_hurtbox)
		counts.append([world.get_child_count()-before_children,before_reading-target.health_loss_reading()])
	check(counts[0][1]>0.0 and is_equal_approx(counts[0][1],counts[1][1]),"hitbox hit deals the same damage to both (%s)"%str(counts))
	check(counts[0][0]==counts[1][0],"hitbox hit spawns the same feedback nodes on both (%s)"%str(counts))
	var pos_counts:Array=[]
	for target in [stand,immortal]:
		var before_children2:int=world.get_child_count()
		target.receive_positional_damage(12.0,attacker.global_position,false,attacker)
		pos_counts.append(world.get_child_count()-before_children2)
	check(pos_counts[0]==pos_counts[1] and pos_counts[0]>0,"positional hit spawns the same feedback nodes on both (%s)"%str(pos_counts))

	# D. INF-class damage still kills it.
	immortal.receive_positional_damage(INF,immortal.global_position,false,null)
	await frames(3)
	check(not is_instance_valid(immortal) or int(immortal.health)<=0,"INF damage kills the immortal stand")

	print("BAT_INF_RESULT checks=%d failures=%d"%[checks,failures])
	game.Game_Settings=saved
	world.queue_free();current_scene=null
	await process_frame
	quit(0 if failures==0 else 1)
