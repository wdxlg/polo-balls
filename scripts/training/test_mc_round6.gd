extends "res://scripts/training/test_mc_new5.gd"
var audio:Script
func heard(event:String) -> bool:
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if not node.is_queued_for_deletion() and node.get_meta("mc_sound_event","")==event: return true
	return false
func clear_audio() -> void:
	for node:Node in get_nodes_in_group("MCNativeSFX"): node.queue_free()
	await process_frame
	audio._last.clear()
func clear_fx() -> void:
	for group:String in ["MCDeathPose","MCDeathSmoke","MCItemFragments"]:
		for node:Node in get_nodes_in_group(group): node.queue_free()
	await process_frame
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(110).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	audio=load("res://scripts/characters/我的世界/new5/audio.gd")
	var guardian:Node2D=spawn("守卫者",Vector2(-130,-140))
	var victim:Node2D=spawn("",Vector2(40,-140),"Team1")
	victim.Max_health=10000
	victim.health=10000
	guardian.step_mob(0.01)
	check(guardian.locked==victim,"initial valid lock")
	var newcomer:Node2D=spawn("",Vector2(-35,-140),"Team1")
	newcomer.Max_health=10000
	newcomer.health=10000
	var hp:float=victim.health
	guardian.step_mob(0.4)
	check(guardian.locked==victim,"closer enemy cannot steal charge")
	check(victim.health==hp,"slow charge does not fire at old 0.38 second interval")
	guardian.step_mob(guardian.laser_tick)
	check(guardian.locked==victim and is_equal_approx(hp-victim.health,90),"charged hit deals 90 to original victim")
	var widths:Array[float]=[]
	for progress:float in [0.0,0.5,0.88,0.99]:
		guardian._tick_left=guardian.laser_tick*(1-progress)
		widths.append(guardian.charge_width())
	check(widths[0]<widths[1] and widths[1]<widths[2] and widths[3]<widths[0],"gradual widening then rapid narrowing before hit")
	victim.global_position=guardian.global_position+Vector2(100,50)
	guardian.step_mob(0.01)
	check(guardian.locked!=victim,"sector exit interrupts locked charge")
	guardian.break_lock()
	var ghast:Node2D=spawn("恶魂",Vector2(-160,100))
	var projectile:Node2D=ghast.fire_at(center+Vector2(150,100))
	projectile.state_machine.set_physics_process(false)
	check(is_equal_approx(projectile.Damage,ghast.attack_damage()*2.0),"fireball damage doubled")
	projectile.queue_free()
	var rod:Node2D=spawn("钓鱼竿",Vector2(150,100))
	victim.global_position=rod.global_position+Vector2(35,0)
	hp=victim.health
	rod.step_mob(0.01)
	check(is_equal_approx(hp-victim.health,rod.attack_damage()*2.5),"sword damage multiplied 2.5")
	newcomer.global_position=center+Vector2(0,340)
	var piston:Node2D=spawn("粘性活塞",Vector2(-80,0))
	piston.direction=Vector2.RIGHT
	piston.stick_duration=20
	victim.global_position=piston.global_position+Vector2(31,0)
	for child:Node in victim.get_children():
		if child.has_method("replace_with_hit"): child.call("_finish",false)
	await process_frame
	var original_layer:int=victim.collision_layer
	var original_mask:int=victim.collision_mask
	await clear_audio()
	for tick:int in range(30): piston.step_mob(0.016)
	check(victim.has_meta("mc_sticky_hold"),"adhesion started")
	check(heard("block.slime_block.place"),"adhesion uses random slime block placement sound")
	piston.phase=0
	piston.extension=piston.REST_EXTENSION
	piston._hit_ids.clear()
	for tick:int in range(24):
		victim.global_position=piston.sticky_anchor(victim)
		piston.step_mob(0.016)
	check(heard("block.slime_block.step"),"successful hit on held enemy adds slime footstep sound")
	var hold:Node=instance_from_id(int(victim.get_meta("mc_sticky_hold",0)))
	hold.set_physics_process(false)
	check(victim.collision_layer==0 and victim.collision_mask==0,"held body's layer and mask are zero")
	check(victim.get_node("hurtbox").monitorable,"hurtbox retained while solid collision is disabled")
	var wall:StaticBody2D=obstacle(Vector2(-30,0),true)
	await physics_frame
	for degrees:float in [0,45,90,135,180,225,270,315,359,1]:
		piston.facing=Vector2.RIGHT.rotated(deg_to_rad(degrees))
		victim.collision_layer=original_layer
		victim.collision_mask=original_mask
		hold._physics_process(0.01)
		check(victim.global_position.distance_to(piston.sticky_anchor(victim))<0.01,"held target exactly follows every direction")
		check(victim.collision_layer==0 and victim.collision_mask==0,"turn does not restore collision prematurely")
	piston.facing=Vector2.RIGHT
	hold._physics_process(0.01)
	hold.queue_free()
	await process_frame
	check(victim.collision_layer==original_layer and victim.collision_mask==original_mask,"release restores original body collision")
	check(not victim.has_meta("submission_allow_map_escape"),"release restores map safety participation")
	check(not victim.has_meta("mc_sticky_hold") and not victim.dizziness,"release clears only its own hold lock")
	wall.queue_free()
	await process_frame
	await clear_audio()
	guardian._ambient_left=0
	guardian._secondary_wait=100
	guardian.tick_ambient(0.01)
	check(heard("entity.guardian.flop"),"guardian primary idle is flop")
	var primary_left:float=guardian._ambient_left
	guardian._secondary_wait=0
	guardian.tick_ambient(0.01)
	check(heard("entity.guardian.ambient_land"),"guardian occasional low call")
	check(absf(guardian._ambient_left-(primary_left-0.01))<0.001,"low call does not reset flop cooldown")
	check(guardian._secondary_wait>guardian._ambient_left,"low call is less frequent")
	guardian.stop_ambient()
	await clear_audio()
	ghast._ambient_left=0
	ghast.tick_ambient(0.01)
	check(heard("entity.ghast.ambient"),"ghast original crying idle event")
	check(ghast._ambient_left>=ghast._ambient_player.stream.get_length()+ghast.ambient_gap_min,"full crying sound plus random gap")
	ghast.stop_ambient()
	var slime:Node2D=spawn("史莱姆",Vector2(0,200))
	await clear_audio()
	slime._ambient_left=0
	slime.tick_ambient(20)
	check(get_nodes_in_group("MCNativeSFX").is_empty(),"slime has no idle breathing sound")
	for actor:Node2D in [slime,guardian,ghast]:
		await clear_audio()
		actor.hurt_voice_chance=0
		actor.receive_positional_damage(1,actor.global_position+Vector2(10,0))
		check(not heard(actor.voice_event("hurt")),"zero probability emits no hurt sound")
		actor.hurt_voice_chance=1
		actor.receive_positional_damage(1,actor.global_position+Vector2(10,0))
		check(heard(actor.voice_event("hurt")),"actual health loss emits species hurt sound")
	for role:String in ["史莱姆","恶魂","守卫者"]:
		await clear_fx()
		await clear_audio()
		var actor:Node2D=spawn(role,Vector2.ZERO)
		actor.health=0
		var event:String=actor.voice_event("death")
		game.now_stop_state=true
		actor.Die()
		check(heard(event),"death voice still plays at end of round")
		check(get_nodes_in_group("MCDeathPose").size()==1,"new creature death pose copied")
		check(get_nodes_in_group("MCDeathSmoke").size()==1,"new creature white death smoke scheduled")
		check(get_nodes_in_group("MCDeathPose")[0].get_parent().name=="MCLocalEffects","death copy avoids multiplayer spawn root")
		if role=="恶魂":
			check(get_nodes_in_group("MCDeathPose")[0].z_index>100 and get_nodes_in_group("MCDeathSmoke")[0].z_index>100,"ghast death remains visible outside map")
		actor.Die()
		check(get_nodes_in_group("MCDeathPose").size()==1,"death visual only once")
		actor.queue_free()
		await process_frame
		check(get_nodes_in_group("MCDeathPose").size()==1,"corpse visual outlives actor")
		game.now_stop_state=false
	for role:String in ["木矛","重锤","钻石剑","钓鱼竿","粘性活塞"]:
		await clear_fx()
		var actor:Node2D=spawn(role,Vector2.ZERO)
		actor.health=0
		actor.Die()
		check(get_nodes_in_group("MCItemFragments").size()==1,role+" enters shared fragmentation")
		var fragments:Node2D=get_nodes_in_group("MCItemFragments")[0]
		fragments.set_process(false)
		check(fragments.pieces.size()>=4,role+" real texture split into pieces")
		for piece:Dictionary in fragments.pieces:
			check(piece.sprite.texture is AtlasTexture and not piece.sprite is CollisionObject2D,"real texture region, no physical collision")
			check(piece.velocity.y<0 and piece.sprite.modulate.a==1,"initial upward launch, opaque debris")
		actor.queue_free()
		await process_frame
		check(is_instance_valid(fragments),"debris persists after item removal")
		for tick:int in range(600):
			if fragments.is_queued_for_deletion(): break
			fragments.advance(1.0/60)
		check(fragments.is_queued_for_deletion(),"pieces fall out of map and clean themselves")
		check(fragments.age<20,"normal map exit, not fallback timeout")
	await clear_fx()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<13: await process_frame
	print("ROUND6_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
