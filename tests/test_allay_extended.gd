extends "res://tests/test_allay.gd"
var CAPTURE:Script
var EXT:Script
func reserve(allay:Node,point:Vector2) -> void:
	allay.cargo.clear()
	allay.notes=1
	allay._note_cloud.clear()
	allay._note_cloud.resize(1,point)
func run() -> void:
	CAPTURE=load("res://scripts/characters/我的世界/allay/capture.gd")
	EXT=load("res://scripts/characters/我的世界/allay/extended_capture.gd")
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.Game_Settings.Map_Background="blue"
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var allay:Node=spawn("res://scenes/characters/我的世界/悦灵.tscn",center,"Team0")
	var enemy:Node=spawn("res://scenes/ball.tscn",center+Vector2(400,0),"Team1")
	freeze(allay); freeze(enemy)
	allay.Can_Attack=false
	enemy.Can_Attack=false; enemy.Can_Skill=false
	# Every added ball script must be classified without cloning its special behavior.
	for path:String in EXT.BALL_PROJECTILES:
		var scene_path:String="res://scenes/shooter/"+path.get_file().get_basename()+".tscn"
		if path.ends_with("裁判牌.gd"): scene_path="res://scenes/shooter/裁判红牌.tscn"
		if path.ends_with("clown_projectile.gd"): scene_path="res://scenes/shooter/clown/clown_projectile.tscn"
		var shot:Node=load(scene_path).instantiate()
		shot.Damage=20
		shot.Speed=300.0
		shot.Master=enemy
		shot.Team="Team1"
		shot.position=center+Vector2(200,200)
		world.add_child(shot,true)
		shot.process_mode=Node.PROCESS_MODE_DISABLED
		var data:Dictionary=CAPTURE.describe(shot)
		check(not data.is_empty() and data.kind=="native","extended ball adapter: "+path.get_file())
		check(CAPTURE.hostile(allay,shot),"enemy ball ownership: "+path.get_file())
		shot.Team="Team0"
		check(not CAPTURE.hostile(allay,shot),"friendly ball protected: "+path.get_file())
		shot.queue_free()
	for path:String in EXT.CUSTOM:
		var c:Dictionary=EXT.CUSTOM[path]
		var shot:Node
		if c.has("owner_method"):
			shot=load("res://scenes/shooter/"+path.get_file().get_basename()+".tscn").instantiate()
			shot.Master_name=str(enemy.name)
			shot.Team="Team1"
			world.add_child(shot,true)
			shot.set_physics_process(false)
		else:
			shot=load(path).new()
			if c.has("owner"):
				shot.set(c.owner,weakref(enemy) if c.owner in ["owner_ref","_caster"] else enemy)
			if c.has("team"): shot.set(c.team,"Team1")
		if c.has("active"): shot.set(c.active,true)
		if c.has("authority"): shot.set(c.authority,true)
		if c.has("state"): shot.set(c.state,c.state_value)
		var data:Dictionary=CAPTURE.describe(shot)
		check(not data.is_empty() and data.kind=="native","extended custom adapter: "+path.get_file())
		check(CAPTURE.hostile(allay,shot),"enemy custom ownership: "+path.get_file())
		if c.has("team"):
			shot.set(c.team,"Team0")
			check(not CAPTURE.hostile(allay,shot),"friendly custom protected: "+path.get_file())
			shot.set(c.team,"Team1")
		elif c.has("owner"):
			var saved_owner:Variant=shot.get(c.owner)
			shot.set(c.owner,weakref(allay) if c.owner in ["owner_ref","_caster"] else allay)
			check(not CAPTURE.hostile(allay,shot),"owner custom protected: "+path.get_file())
			shot.set(c.owner,saved_owner)
		if c.has("ended"):
			shot.set(c.ended,true)
			check(CAPTURE.describe(shot).is_empty(),"spent attack excluded: "+path.get_file())
		elif c.has("active"):
			shot.set(c.active,false)
			check(CAPTURE.describe(shot).is_empty(),"nonflying attack excluded: "+path.get_file())
		elif c.has("state"):
			shot.set(c.state,3)
			check(CAPTURE.describe(shot).is_empty(),"stuck trident excluded")
		if shot.is_inside_tree(): shot.queue_free()
		else: shot.free()
	var ground:Node=load("res://scripts/shooter/蜘蛛地网.gd").new()
	ground.Type=ground.Ball_Type.Shooter_with_Health
	ground.set_meta("death_return_restore",true)
	ground.health=2
	check(CAPTURE.describe(ground).is_empty(),"ground web is not mistaken for flying attack")
	ground.free()
	# Real custom movement: absorb before the original callback can damage or explode.
	for title:String in ["军火商_子弹","猎人_霰弹","魔角猎人_黑弹"]:
		var shot:Node=load("res://scenes/shooter/"+title+".tscn").instantiate()
		shot.Master_name=str(enemy.name); shot.Team="Team1"
		shot.position=center+Vector2(60,120)
		shot.direction=Vector2.LEFT
		world.add_child(shot,true)
		reserve(allay,center+Vector2(35,120))
		shot._physics_process(0.06)
		check(shot.is_queued_for_deletion() and allay.notes==0 and allay.cargo.size()==1,"actual high-speed interception: "+title)
		if not shot.is_queued_for_deletion(): shot.queue_free()
	var potion:Node=load("res://scripts/effects/我的世界/女巫药水.gd").new()
	world.add_child(potion)
	potion.setup(center+Vector2(60,140),center+Vector2(-60,140),"poison",enemy)
	reserve(allay,potion.global_position)
	var health_before:float=allay.health
	var nodes_before:int=world.get_child_count()
	potion._physics_process(0.01)
	check(potion.is_queued_for_deletion() and allay.cargo.size()==1 and not potion._exploded,"potion absorbed without shattering")
	check(world.get_child_count()==nodes_before and allay.health==health_before,"potion absorption creates no area or damage")
	var reply:Node=CAPTURE.launch(allay,allay.cargo.back(),enemy,center+Vector2(0,150))
	check(reply!=null and reply.source_witch.Master==allay and reply.effect_type=="poison" and reply.get_script().resource_path=="res://scripts/effects/我的世界/女巫药水.gd","complex attack returns original potion with new ownership")
	if reply!=null: reply.queue_free()
	var fireball:Node=load("res://scenes/shooter/我的世界/恶魂火焰弹.tscn").instantiate()
	fireball.position=center+Vector2(65,180)
	world.add_child(fireball,true)
	fireball.flight_velocity=Vector2.LEFT*185.0
	reserve(allay,center+Vector2(40,180))
	fireball.step_mob(0.1)
	check(fireball.is_queued_for_deletion() and not fireball.exploded and allay.cargo.size()==1,"neutral ghast fireball absorbed before explosion")
	if not fireball.is_queued_for_deletion(): fireball.queue_free()
	# Moving note discovers non-ball objects even when they are stationary.
	var drowned:Node=spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(300,250),"Team1")
	freeze(drowned); drowned.Can_Attack=false; drowned.Can_Skill=false
	var spear:Node=drowned._trident
	spear.flight_state=1
	spear.global_position=center+Vector2(100,250)
	reserve(allay,spear.global_position)
	check(CAPTURE.sweep(spear,spear.global_position,spear.global_position) and spear.is_queued_for_deletion(),"actual trident capture")
	check(drowned._trident==null and drowned._tridents.is_empty() and not drowned.has_trident and drowned._refill_left>0.0,"trident capture retires owner reference and schedules refill")
	drowned.queue_free()
	var pancake:Node=spawn("res://scenes/shooter/不坏煎饼弹.tscn",center+Vector2(100,270),"Team1")
	pancake.Master=enemy
	reserve(allay,pancake.global_position)
	pancake.tick_physics(0,0.01)
	check(pancake.is_queued_for_deletion() and pancake._rot_elapsed==0.0 and allay.cargo.size()==1,"pancake captured before pre-movement overlap damage")
	if not pancake.is_queued_for_deletion(): pancake.queue_free()
	# Moving note discovers non-ball objects even when they are stationary.
	var pot2:Node=load("res://scripts/effects/我的世界/女巫药水.gd").new()
	world.add_child(pot2)
	pot2.setup(center+Vector2(200,200),center+Vector2(300,200),"poison",enemy)
	allay.cargo.clear(); allay.notes=0; allay._note_cloud.clear()
	var note:Node=allay.fire_note(enemy)
	check(CAPTURE.sweep_note(note,center+Vector2(160,200),center+Vector2(230,200)) and note._spent and pot2.is_queued_for_deletion(),"outgoing note intercepts registered custom potion")
	allay.notes=0
	await create_timer(3.0).timeout
	print("ALLAY_EXTENDED_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
