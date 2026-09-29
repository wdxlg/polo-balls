extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	var man:Node2D = actor("雾中人",center)
	var enemy:Node2D = dummy(center+Vector2(160,0))
	await physics_frame
	man.rage_origin = center
	man.rage_left = 4.0
	man.set_phase(man.Phase.RAGE)
	man.start_rush_attack(enemy,0)
	man.visual_mob()
	check(man.rush==man.Rush.MIST and not man.visible and not man.health_bar.is_visible_in_tree(),"mist rush hides the complete actor and HUD")
	check(man.is_combat_targetable() and man.is_combat_lockable(),"mist rush is not invulnerability or discovery disappearance")
	var hp:int = enemy.health
	man.charge_fx._process(0.04)
	check(man.charge_fx.motes.size()>0 and man.charge_fx.is_visible_in_tree(),"separate fog body stays visible while the actor root is hidden")
	man.rush_step(enemy,0.05)
	check(man.rush==man.Rush.MIST and man.direction.x>0,"mist dashes toward the target")
	var before:int = enemy.health
	man.global_position = enemy.global_position-Vector2(30,0)
	man.sweep_mist_damage(man.global_position,man.global_position+Vector2(60,0))
	check(enemy.health==before-45 and not man.visible,"mist passes through the enemy and deals damage without revealing")
	check(man.dash_hit_ids.has(enemy.get_instance_id()),"the dash records its hit for deduplication")
	man.sweep_mist_damage(man.global_position,man.global_position+Vector2(60,0))
	check(enemy.health==before-45,"one dash cannot damage the same enemy twice")
	man.dash_remaining = 0.0
	man.rush_step(enemy,0.05)
	check(man.rush==man.Rush.RETREAT and man.visible,"the dash ends into a visible retreat")
	man.rush_step(enemy,0.45)
	check(man.rush==man.Rush.MIST or man.rush==man.Rush.FACE_VANISH,"retreat randomly picks the next attack")
	man.start_rush_attack(enemy,1)
	var buddy:Node2D = dummy(enemy.global_position+Vector2(20,0))
	var buddy_hp:int = buddy.health
	check(man.rush==man.Rush.FACE_VANISH and not man.visible and man.charge_fx.motes.is_empty(),"face attack first fully disappears without a fog body")
	var guard:int = 0
	while man.rush==man.Rush.FACE_VANISH and guard<40:
		man.rush_step(enemy,0.05)
		guard += 1
	check(man.rush==man.Rush.FACE_SHOW and man.face_fired and not man.visible,"the face manifests beside the target while everything stays hidden")
	check(man.global_position.distance_to(enemy.global_position)<=80.0,"the face appears right next to the enemy")
	check(enemy.health<hp and buddy.health<buddy_hp,"the face burst damages the enemies around it")
	man.rush_step(enemy,0.3)
	check(man.rush==man.Rush.RETREAT and man.visible,"the face attack ends into a visible retreat")
	man.rush_step(enemy,0.45)
	var remote:Node2D = actor("雾中人",center+Vector2(-150,0))
	remote.set_multiplayer_authority(2)
	remote.accept_visual(man.network_visual_state())
	check(remote.rush==man.rush and remote.is_attack_hidden() and not remote.visible,"remote state carries the hidden attack stage")
	check(man.discovery_count==0 and man.health==600,"attack transformations never charge the discovery self-health cost")
	man.set_phase(man.Phase.STALK)
	check(man.visible and not man.is_attack_hidden(),"rage timeout restores the normal stalking appearance")
	finish(0 if failures==0 else 1)
