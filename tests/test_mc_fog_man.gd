extends "res://tests/test_mc_frontier.gd"
func advance(unit:Node2D,delta:float) -> void:
	unit.clock += delta
	unit.step_mob(delta)
	unit.visual_mob()
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(90).timeout.connect(func(): finish(2))
	check(world.return_all_character_names().has("雾中人"),"new character is indexed in the actual roster")
	var man:Node2D = actor("雾中人",center)
	var enemy:Node2D = dummy(center+Vector2(160,0))
	enemy.velocity = Vector2.RIGHT*10.0
	var fog:Node2D = man.fog
	await physics_frame
	fog.refresh_viewers()
	check(man.Max_health==600 and man.Damage==45,"character has intended base health and damage")
	check(get_nodes_in_group("MCFogField").size()==1,"one scene-wide fog manager")
	check(man.BODY.get_frame_count(&"walk")==12 and man.BODY.get_frame_count(&"rage")==12,"native textured 2D animation frames imported")
	check(man.EYES.get_frame_count(&"idle")==8 and man.eye_fx.z_index>fog.z_index,"separate glow eyes render above fog")
	check(not man.is_combat_lockable() and man.is_combat_targetable(),"hidden body is not lockable but can still take area damage")
	var seeker:Node2D = actor("末影人",center+Vector2(250,200),"Team1")
	check(seeker.mc_nearest()==null,"MC mob target selection also rejects hidden fog man")
	seeker._mc_target_ref = weakref(man)
	seeker._mc_target_wait = 10.0
	check(seeker.mc_nearest()==null,"previously cached lock is dropped while fog hides the target")
	seeker.Nearest_Enemy = man
	seeker.Target_Enemy = man
	check(seeker.return_reusable_combat_target()==null,"standard explicit and nearest target contracts reject hidden body")
	seeker.free()
	var hp:int = man.health
	man.receive_positional_damage(10,man.global_position,false,enemy)
	check(man.health<hp,"non-locking hidden state is not invincibility")
	man.health = 600
	check(fog.in_view_shape(Vector2(30,0),Vector2.ZERO,Vector2.LEFT),"near circle is omnidirectional")
	check(fog.in_view_shape(Vector2(170,70),Vector2.ZERO,Vector2.RIGHT),"triangle expands toward movement direction")
	check(not fog.in_view_shape(Vector2(-100,0),Vector2.ZERO,Vector2.RIGHT),"behind a viewer is not in forward sight")
	check(not fog.in_view_shape(Vector2(100,100),Vector2.ZERO,Vector2.RIGHT),"outside triangle sides stays foggy")
	enemy.velocity = Vector2.DOWN*10.0
	fog.refresh_viewers()
	check(fog.heading_for(enemy)==Vector2.DOWN,"view follows actual movement direction")
	enemy.velocity = Vector2.ZERO
	fog.refresh_viewers()
	check(fog.heading_for(enemy)==Vector2.DOWN,"stationary viewer retains last direction")
	enemy.velocity = Vector2.RIGHT*10.0
	fog.refresh_viewers()
	man.global_position = enemy.global_position+Vector2(140,0)
	check(fog.body_exposure(man,man.global_position)>=0.6,"most body visible inside forward triangle")
	var barrier:StaticBody2D = wall(enemy.global_position+Vector2(70,0),Vector2(12,160))
	await physics_frame
	check(fog.body_exposure(man,man.global_position)==0.0,"wall blocks discovery, not just its drawing")
	barrier.free()
	await physics_frame
	man.grace_left = 0.0
	advance(man,0.16)
	check(man.phase==man.Phase.STALK and man.health==600,"one short glimpse does not immediately penalize")
	advance(man,0.16)
	check(man.phase==man.Phase.VANISHED and man.health==552,"sustained body exposure costs exactly eight percent max health")
	check(man.discovery_count==1 and not man.disappear(),"same discovery cannot charge twice")
	check(man.collision_layer==0 and not man.is_combat_targetable(),"vanished body has no collision or damage target")
	man.eye_fx._process(0.01)
	check(man.eye_fx.trails.is_empty() and man.body_alpha()==0,"eyes and trails disappear with the body")
	var saved:float = man.vanish_left
	game.now_stop_state = true
	man.tick_physics(0,5.0)
	check(man.vanish_left==saved,"pause freezes disappearance countdown")
	game.now_stop_state = false
	man.vanish_left = 0.0
	check(man.try_reappear(),"finds a valid hidden reappearance location")
	check(man.phase==man.Phase.STALK and fog.body_exposure(man,man.global_position)==0,"reappearance prefers an unobserved point")
	check(man.global_position.distance_to(enemy.global_position)>=125.0 and man.collision_layer!=0,"reappearance does not spawn on enemy and restores collision")
	man.global_position = enemy.global_position-Vector2(75,0)
	man._target_ref = weakref(enemy)
	man.rear_hold = man.behind_hold
	man.rage_wait = 0.0
	check(man.begin_rage(),"staying behind a target triggers thunder rage")
	check(man.lightning_wait and not fog.clear_at(man.global_position),"warning precedes actual lightning clearing")
	man.lightning_visual._process(0.69)
	check(man.is_combat_lockable() and fog.clear_at(man.global_position),"rage clears local fog and enables locking")
	check(man.rage_left==4.0,"rage and clearing duration initialized")
	enemy.global_position = man.global_position+Vector2(25,0)
	man.start_rush_attack(enemy,0)
	man.global_position = enemy.global_position-Vector2(30,0)
	hp = enemy.health
	man.sweep_mist_damage(man.global_position,man.global_position+Vector2(60,0))
	check(enemy.health==hp-45 and not man.visible,"mist dash through the enemy deals forty-five base damage while hidden")
	man.sweep_mist_damage(man.global_position,man.global_position+Vector2(60,0))
	check(enemy.health==hp-45,"one dash cannot damage the same enemy twice")
	var discoveries:int = man.discovery_count
	advance(man,0.4)
	check(man.phase==man.Phase.RAGE and man.discovery_count==discoveries,"visible rage cannot cause discovery disappearance loop")
	advance(man,4.1)
	check(man.phase==man.Phase.STALK and man.rage_wait>0.0 and not man.is_combat_lockable(),"rage ends and restores hidden phase with cooldown")
	var second:Node2D = actor("雾中人",center+Vector2(-200,0))
	check(second.fog==fog and get_nodes_in_group("MCFogField").size()==1,"multiple fog men share one nonstacking field")
	second.set_multiplayer_authority(2)
	second.accept_visual(man.network_visual_state())
	check(second.phase==man.phase and not second.disappear(),"remote state sync does not grant damage authority")
	man.phase = man.Phase.RAGE
	man.rage_origin = man.global_position
	man.rage_left = 2.0
	man.set_phase(man.Phase.RAGE)
	second.accept_visual(man.network_visual_state())
	check(second.phase==second.Phase.RAGE and second.is_combat_lockable(),"remote rage carries lockability and cleared area")
	man.set_phase(man.Phase.STALK)
	man.health = 40
	check(man.disappear() and man.health==0,"discovery self-damage can kill")
	check(not man.try_reappear(),"a lethal discovery cannot resurrect the character")
	second.health = 0
	fog.fog_alpha = 0.45
	fog._process(1.0)
	check(fog.is_queued_for_deletion(),"last owner's death fades and removes shared fog")
	print("FOG MAN CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
