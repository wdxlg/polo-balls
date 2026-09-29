extends "res://tests/test_allay_extended.gd"
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
	create_timer(90.0).timeout.connect(func(): finish(2))
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

	var native:Script=CAPTURE.NATIVE_RETURN
	# Regression: a target can disappear while the cube is winding up.
	for scenario:String in ["freed_raw","freed_weak","queued","dead","detached","wrong_type","missing","negative_index"]:
		var victim:Node=spawn("res://scenes/ball.tscn",center+Vector2(90,0),"Team1")
		var candidate:Variant=weakref(victim) if scenario=="freed_weak" else victim
		allay.cargo.assign([{"kind":"simple","scene":"res://scenes/shooter/子弹.tscn","damage":123.0,"speed":300.0,"scale":Vector2.ONE}])
		allay._cube_cloud.clear(); allay._cube_cloud.resize(1,center)
		allay._windup={"dir":Vector2.RIGHT,"target":candidate,"t":0.0,"idx":-1 if scenario=="negative_index" else 0}
		match scenario:
			"freed_raw","freed_weak": victim.free()
			"queued": victim.queue_free()
			"dead":
				victim.set_meta("death_return_restore",true)
				victim.health=0
			"detached": world.remove_child(victim)
			"wrong_type": allay._windup["target"]=allay._note_cloud
			"missing": allay._windup.erase("target")
		allay._wind_step(allay.windup_back+allay.windup_dash+0.01)
		check(allay._windup.is_empty(),"invalid target clears windup: "+scenario)
		check(allay.cargo.size()==1 and allay._cube_cloud.positions.size()==1,"invalid target does not consume stored shot: "+scenario)
		if is_instance_valid(victim):
			if victim.is_inside_tree(): victim.queue_free()
			else: victim.free()
	allay._wind_step(0.01)
	check(allay._windup.is_empty(),"empty windup is harmless")
	var freed:Variant=Node.new()
	freed.free()
	check(not native.safe_value(freed),"snapshot rejects freed object before type test")
	var ownerless:Node=load("res://scripts/effects/我的世界/女巫药水.gd").new()
	ownerless.source_witch=Node.new()
	ownerless.source_witch.free()
	check(EXT.source(ownerless,EXT.config(ownerless))==null,"adapter rejects freed projectile owner before type test")
	ownerless.free()
	allay._windup={"dir":Vector2.RIGHT,"target":weakref(enemy),"t":0.0,"idx":0}
	allay._wind_step(allay.windup_back+allay.windup_dash+0.01)
	check(allay.cargo.is_empty() and allay._windup.is_empty(),"valid subsequent target can still launch the preserved shot")
	allay.Damage=1
	for path:String in EXT.BALL_PROJECTILES:
		var scene:String="res://scenes/shooter/"+path.get_file().get_basename()+".tscn"
		if path.ends_with("裁判牌.gd"): scene="res://scenes/shooter/裁判红牌.tscn"
		if path.ends_with("clown_projectile.gd"): scene="res://scenes/shooter/clown/clown_projectile.tscn"
		var incoming:Node=spawn(scene,center+Vector2(80,120),"Team1")
		incoming.Master=enemy
		incoming.Damage=800
		incoming.Speed=735.0
		incoming.process_mode=Node.PROCESS_MODE_DISABLED
		reserve(allay,incoming.global_position)
		check(CAPTURE.sweep(incoming,incoming.global_position,incoming.global_position),"native ball capture: "+path.get_file())
		var data:Dictionary=allay.cargo.back()
		var returned:Node=CAPTURE.launch(allay,data,enemy,center+Vector2(100,120))
		check(returned!=null and returned.get_script().resource_path==path,"same projectile script: "+path.get_file())
		if returned!=null:
			check(returned.Damage==800 and is_equal_approx(returned.Speed,735.0),"unclamped damage and speed: "+path.get_file())
			check(returned.Master.Master==allay and returned.Team=="Team0","isolated new ownership: "+path.get_file())
			returned.queue_free()
	# Real ghast shot: 100 attack * 200% fireball, independent of later source/Allay stats.
	var ghast:Node=spawn("res://scenes/characters/我的世界/恶魂.tscn",center+Vector2(250,100),"Team1")
	freeze(ghast); ghast.Can_Attack=false; ghast.Can_Skill=false
	ghast.Damage=100
	ghast.fireball_damage_multiplier=2.0
	var fire:Node=ghast.fire_at(center+Vector2(400,100))
	fire.flight_velocity=Vector2.RIGHT*321.0
	fire.blast_radius=77.0
	fire.process_mode=Node.PROCESS_MODE_DISABLED
	reserve(allay,fire.global_position)
	check(CAPTURE.sweep(fire,fire.global_position,fire.global_position),"200 percent ghast fireball captured")
	var fire_data:Dictionary=allay.cargo.back()
	check(fire_data.native_properties.Damage==200 and fire_data.sound.event=="entity.ghast.shoot","snapshot stores resolved damage and ghast launch cue")
	ghast.Damage=999
	ghast.queue_free()
	await process_frame
	var fire_reply:Node=CAPTURE.launch(allay,fire_data,enemy,enemy.global_position)
	check(fire_reply!=null and fire_reply.Damage==200,"original caster gone: damage stays 200, not Allay scaling or double multiplier")
	var launch_audio:Node=fire_reply.get_meta("allay_launch_audio").get_ref()
	check(launch_audio!=null and launch_audio.playing and launch_audio.stream!=null,"original ghast launch audio actually playing")
	check(is_equal_approx(fire_reply.flight_velocity.length(),321.0) and fire_reply.blast_radius==77.0,"native ghast speed and blast radius preserved")
	enemy.Max_health=10000; enemy.health=10000
	var before:float=enemy.health
	fire_reply.explode()
	check(before-enemy.health==200,"returned ghast explosion actually deals 200")
	# Actual drowned context supplies native water/trident methods without spawning a second actor.
	var drowned:Node=spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(220,220),"Team1")
	freeze(drowned); drowned.Can_Attack=false; drowned.Can_Skill=false
	drowned.Damage=240
	var spear:Node=drowned._trident
	spear.flight_state=1; spear.charged=true
	reserve(allay,spear.global_position)
	check(CAPTURE.sweep(spear,spear.global_position,spear.global_position),"charged trident captured")
	var spear_data:Dictionary=allay.cargo.back()
	drowned.Damage=1
	var spear_reply:Node=CAPTURE.launch(allay,spear_data,enemy,center+Vector2(300,0))
	check(spear_reply!=null and spear_reply.charged and spear_reply.unit.trident_hit_damage()==120.0,"charged trident retains source attack snapshot and native unit APIs")
	check(not spear_reply.unit.is_in_group("Ball") and not spear_reply.unit.visible and not spear_reply.unit.Can_Attack,"frozen context is not an extra combat character")
	spear_reply.advance(0.01)
	spear_reply.retire()
	var water:Node=load("res://scripts/effects/我的世界/水泼弹.gd").new()
	world.add_child(water)
	water.global_position=center+Vector2(200,0)
	water.setup(drowned,water.global_position,123.0,0.6,4.0,"test_wet")
	reserve(allay,water.global_position)
	check(CAPTURE.sweep(water,water.global_position,water.global_position),"water capture")
	enemy.global_position=center+Vector2(120,-100)
	var water_reply:Node=CAPTURE.launch(allay,allay.cargo.back(),enemy,enemy.global_position-Vector2(24,0))
	before=enemy.health
	water_reply._physics_process(0.01)
	check(before-enemy.health==123.0,"native water damage and callback work with frozen source")
	drowned.queue_free()
	# Potion remains a potion, including effect type, impact audio and its original area.
	var potion:Node=load("res://scripts/effects/我的世界/女巫药水.gd").new()
	world.add_child(potion)
	potion.setup(center+Vector2(100,100),center+Vector2(300,100),"poison",enemy)
	potion.area_radius=87.0; potion.area_duration=6.0
	reserve(allay,potion.global_position)
	CAPTURE.sweep(potion,potion.global_position,potion.global_position)
	var potion_reply:Node=CAPTURE.launch(allay,allay.cargo.back(),enemy,center+Vector2(100,100))
	check(potion_reply.get_script().resource_path.ends_with("女巫药水.gd") and potion_reply.effect_type=="poison" and potion_reply.area_radius==87.0,"potion type and area configuration preserved")
	var children_before:int=world.get_child_count()
	potion_reply._explode(center+Vector2(300,300))
	check(world.get_child_count()>children_before and potion_reply._exploded,"returned potion uses original shatter and area creation")
	# Source context values, and nested projectile fields, are immutable snapshots.
	var blaze:Node=load("res://scenes/shooter/我的世界/烈焰弹.tscn").instantiate()
	world.add_child(blaze)
	enemy.Damage=200
	blaze.configure(enemy,"Team1",Vector2.LEFT,620.0,2.0,9.0,1.4,55.0,8.0,1.2,0.8)
	blaze.global_position=center+Vector2(100,100)
	reserve(allay,blaze.global_position)
	CAPTURE.sweep(blaze,blaze.global_position,blaze.global_position)
	var blaze_data:Dictionary=allay.cargo.back()
	enemy.Damage=1
	var blaze_reply:Node=CAPTURE.launch(allay,blaze_data,enemy,center+Vector2(100,100))
	check(blaze_reply._source_ball().attack_damage(blaze_reply._damage_multiplier)==400.0,"blaze direct damage uses captured source power")
	check(blaze_reply._burn_tick_damage_multiplier==1.4 and blaze_reply._fire_tick_damage_multiplier==1.2 and blaze_reply._fire_burn_tick_damage_multiplier==0.8,"burn and fire multipliers are not capped")
	blaze_reply.queue_free()
	# Native weapon owner callbacks must survive after the real owner is deleted.
	var clown:Node=spawn("res://scenes/characters/人物/小丑.tscn",center+Vector2(-120,120),"Team1")
	freeze(clown); clown.Can_Attack=false; clown.Can_Skill=false
	var hammer:Node=spawn("res://scenes/shooter/clown/clown_projectile.tscn",center+Vector2(50,100),"Team1")
	hammer.Master=clown; hammer.impact_damage=177.0; hammer.projectile_mode=1
	reserve(allay,hammer.global_position)
	CAPTURE.sweep(hammer,hammer.global_position,hammer.global_position)
	var hammer_data:Dictionary=allay.cargo.back()
	clown.queue_free()
	var hammer_reply:Node=CAPTURE.launch(allay,hammer_data,enemy,center)
	before=enemy.health
	hammer_reply._damage_target(enemy,hammer_reply.impact_damage,Vector2.RIGHT,false)
	check(before-enemy.health==177,"clown native hit callback still works without original owner")
	check(hammer_reply.projectile_mode==1 and hammer_data.sound.event=="狙击枪发射","clown weapon variant and firing cue preserved")
	hammer_reply.queue_free()
	for title:String in ["军火商_子弹","猎人_霰弹","魔角猎人_黑弹"]:
		var custom:Node=spawn("res://scenes/shooter/"+title+".tscn",center+Vector2(100,100),"Team1")
		custom.Master_name=str(enemy.name); custom.damage_amount=333.0
		reserve(allay,custom.global_position)
		CAPTURE.sweep(custom,custom.global_position,custom.global_position)
		var custom_reply:Node=CAPTURE.launch(allay,allay.cargo.back(),enemy,center)
		check(custom_reply.get_script()==custom.get_script() and custom_reply.damage_amount==333.0 and custom_reply._resolve_master().Master==allay,"native firearm configuration and source: "+title)
		before=enemy.health
		if title=="军火商_子弹": custom_reply._apply_direct_hit(enemy)
		else: custom_reply._apply_hit(enemy,custom_reply._resolve_master())
		check(before-enemy.health==333,"native firearm actual damage: "+title)
		custom_reply.queue_free()
	allay.notes=0; allay.cargo.clear(); allay._note_cloud.clear()
	await create_timer(0.2).timeout
	print("ALLAY_NATIVE_RETURN_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
