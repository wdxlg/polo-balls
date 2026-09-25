extends "res://scripts/training/test_mc_new5.gd"

const KNOCKBACK_PATH = "res://scripts/effects/knockback_effect.gd"

func death_bursts() -> Array[Node]:
	var result:Array[Node]=[]
	for fx:Node in get_nodes_in_group("MCSlimeJumpFX"):
		if is_instance_valid(fx) and not fx.is_queued_for_deletion() and fx.linger_after_death:
			result.append(fx)
	return result

func knockback_on(actor:Node) -> Node:
	for node:Node in actor.get_children():
		if node.get_script()!=null and node.get_script().resource_path==KNOCKBACK_PATH and not node.is_queued_for_deletion(): return node
	return null

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(65,true,false,true).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	for stage:int in range(3):
		var name:String=["史莱姆","史莱姆_中","史莱姆_小"][stage]
		var folder:String="characters" if stage==0 else "creatures"
		var slime:Node2D=spawn(name,Vector2.ZERO,"Team0",folder)
		var center_point:Vector2=slime.ground_point()
		var victim:Node2D=spawn("",Vector2.ZERO,"Team1")
		# Place the target inside the splash but OUTSIDE both solid body shapes;
		# pushing from an artificially deep spawn overlap can be blocked by physics.
		var victim_offset:float=u.radius(slime)+u.radius(victim)+3.0
		victim.global_position=center_point+Vector2(victim_offset,0)
		victim.health=10000
		victim.block=0
		victim.Damage_reduction=0
		check(victim_offset<slime.pulse_radius(true)+u.radius(victim),"unobstructed physical victim still lies inside landing radius, stage "+str(stage))
		var outside:Node2D=spawn("",Vector2(300,0),"Team1")
		outside.health=10000
		var friend:Node2D=spawn("",Vector2.ZERO,"Team0")
		friend.global_position=center_point+Vector2(0,slime.pulse_radius(true)+u.radius(friend)-2)
		friend.health=10000
		var family:Node2D=spawn(name,Vector2.ZERO,"Team1",folder)
		family.slime_family=slime.slime_family
		family.global_position=center_point+Vector2(0,-slime.pulse_radius(true)-u.radius(family)+2)
		family.state_machine.set_physics_process(false)
		await physics_frame
		var expected_landing:int=[40,27,17][stage]
		slime.emit_jump_fx(false)
		var takeoff_fx:Node=slime._jump_fx_nodes.back()
		check(takeoff_fx.particles.size()==[5,3,3][stage],"takeoff chips stay sparse, stage "+str(stage))
		slime.clear_jump_fx()
		slime.emit_jump_fx(true)
		var ordinary_fx:Node=slime._jump_fx_nodes.back()
		check(ordinary_fx.particles.size()==expected_landing and ordinary_fx.ring!=null,"ordinary landing has a full ring of chips, stage "+str(stage))
		var max_gap:float=0.0
		for index:int in range(expected_landing):
			var first_angle:float=(ordinary_fx.particles[index].plane as Vector2).angle()
			var next_angle:float=(ordinary_fx.particles[(index+1)%expected_landing].plane as Vector2).angle()
			max_gap=maxf(max_gap,fposmod(next_angle-first_angle,TAU))
		check(max_gap<TAU/float(expected_landing)*1.65,"denser landing chips do not leave a wide empty sector, stage "+str(stage))
		var outside_before:int=outside.health
		var friend_before:int=friend.health
		var family_before:int=family.health
		check(slime.pulse_contains(victim,true) or slime._pulse_contains_from(victim,true,center_point),"victim inside death/landing radius, stage "+str(stage))
		check(not slime._pulse_contains_from(outside,true,center_point),"outside victim excluded, stage "+str(stage))
		var power:float=slime.Damage
		if stage==0: slime.Damage*=2
		var expected_damage:float=slime.attack_damage(slime.landing_damage/maxf(float(slime.default_properties.get("Damage",slime.Damage)),0.01))
		check(expected_damage>0 and (stage!=0 or is_equal_approx(expected_damage,slime.landing_damage*2)),"fatal damage follows live Attack attribute, stage "+str(stage))
		var before:int=victim.health
		var bursts_before:int=death_bursts().size()
		# Actual lethal health setter: the impact must happen before Die/splitting/victory polling.
		slime.health=0
		check(slime._death_pulse_done and is_equal_approx(float(before-victim.health),expected_damage),"lethal hit immediately deals one landing-strength hit, stage "+str(stage))
		check(slime.Damage==power or stage==0,"unchanged attack attribute for other stages")
		check(outside.health==outside_before and friend.health==friend_before and family.health==family_before,"range, team and same-family immunity, stage "+str(stage))
		check(knockback_on(outside)==null and knockback_on(friend)==null and knockback_on(family)==null,"no push on excluded actors, stage "+str(stage))
		var knock:Node=knockback_on(victim)
		check(knock!=null and is_equal_approx(float(knock.get("distance")),slime.death_knockback_distance) and (knock.get("direction") as Vector2).x>0.8,"successful victim gets outward common knockback, stage "+str(stage))
		if knock!=null:
			# The fixture disables actors' AI/physics; manually consume the public
			# controller's actual Repel through CharacterBody2D collision movement.
			await physics_frame
			var before_x:float=victim.global_position.x
			victim.velocity=victim.Repel
			victim.move_and_slide()
			check(victim.global_position.x>before_x+0.05,"death knockback actually displaces the victim outwards, stage "+str(stage))
		var burst:Array[Node]=death_bursts()
		check(burst.size()==bursts_before+1,"one detached landing-style FX at lethal health, stage "+str(stage))
		var fx:Node=burst.back() if not burst.is_empty() else null
		if fx!=null:
			check(fx.landing and fx.owner_ref==null and fx.ring!=null and fx.ring.points.size()==72 and fx.particles.size()==expected_landing and fx.global_position.is_equal_approx(center_point),"death inherits dense landing chips at ground point, stage "+str(stage))
		var hp_after:int=victim.health
		slime.Die()
		slime.Die()
		check(victim.health==hp_after and death_bursts().size()==bursts_before+1,"Die and repeated Die do not re-hit or duplicate FX, stage "+str(stage))
		check(slime._jump_fx_nodes.is_empty(),"death clears ordinary owner-bound FX, stage "+str(stage))
		check(not is_instance_valid(ordinary_fx) or (not ordinary_fx.visible and ordinary_fx.is_queued_for_deletion()),"ordinary landing chips still clear on death, stage "+str(stage))
		if stage<2:
			var children:int=0
			for actor:Node in get_nodes_in_group("Ball"):
				if actor!=slime and actor.get_script()==slime.get_script() and actor.slime_family==slime.slime_family and actor.slime_stage==stage+1:
					children+=1
					check(actor.health>0,"new descendants are not hit by parent's own death blast")
			check(children==2,"normal two-way split survives burst, stage "+str(stage))
		if fx!=null:
			slime._jump_fx(center_point,true,stage,7,true)
			check(death_bursts().size()==bursts_before+1,"duplicate/late death RPC is ignored, stage "+str(stage))
		# ball's zero-health fallback awaits a physics tick; let it finish before
		# freeing the actor, or the fixture creates an unrelated freed-coroutine error.
		await process_frame
		await physics_frame
		if is_instance_valid(slime) and not slime.is_queued_for_deletion(): slime.free()
		if fx!=null: check(is_instance_valid(fx) and not fx.is_queued_for_deletion() and fx.visible,"FX survives freeing dead owner, stage "+str(stage))
		if stage==0 and knock!=null:
			await physics_frame
			check(is_instance_valid(knock) and knock.is_active_effect() and victim.Repel.x>0.0,"victim's real knockback persists after dead caster is freed")
		if stage==2 and fx!=null:
			var age_before:float=fx.age
			game.now_stop_state=true
			await create_timer(0.15,true,false,true).timeout
			check(is_instance_valid(fx) and fx.age>age_before+0.04,"last-death FX continues after battle stops")
			game.now_stop_state=false
		# Initial GPU/shader warm-up can consume wall time without rendered frames.
		# Wait for the FX's own real rendered process frames, not an arbitrary timer.
		for frame:int in range(120):
			if fx==null or not is_instance_valid(fx): break
			await process_frame
		if fx!=null: check(not is_instance_valid(fx),"detached death FX self-cleans after natural fade, stage "+str(stage))
		await clear_units()
	# Death while jumping strikes where the green ring lands, not at body height.
	var flyer:Node2D=spawn("史莱姆",Vector2.ZERO,"Team0")
	flyer.airborne=true
	flyer._jump_lift=38.0
	flyer.global_position=center+Vector2.UP*38.0
	var ground:Vector2=flyer.ground_point()
	var landed:Node2D=spawn("",Vector2.ZERO,"Team1")
	var airborne_only:Node2D=spawn("",Vector2.ZERO,"Team1")
	var max_reach:float=flyer.pulse_radius(true)+u.radius(landed)
	landed.global_position=ground+Vector2.DOWN*(max_reach-5.0)
	airborne_only.global_position=flyer.global_position+Vector2.UP*(max_reach-5.0)
	check(flyer._pulse_contains_from(landed,true,ground) and not flyer._pulse_contains_from(airborne_only,true,ground),"airborne ground splash contains only targets near the green landing ring")
	var has_death_threat:bool=false
	for region:Dictionary in flyer.get_debug_attack_regions():
		if region.kind=="slime_death" and (region.position as Vector2).is_equal_approx(ground) and is_equal_approx(float(region.radius),flyer.pulse_radius(true)):
			has_death_threat=true
	check(has_death_threat,"threat display declares the airborne death splash on the ground")
	var landed_hp:int=landed.health
	var air_hp:int=airborne_only.health
	flyer.health=0
	check(landed.health<landed_hp and airborne_only.health==air_hp,"airborne lethal health only hits enemies in the matching rendered blast")
	check(knockback_on(landed)!=null and knockback_on(airborne_only)==null,"airborne knockback shares the ground-centered damage footprint")
	flyer.Die()
	await process_frame
	await physics_frame
	if is_instance_valid(flyer) and not flyer.is_queued_for_deletion(): flyer.free()
	await clear_units()
	# The incoming death hit must still run the target's current defense formula.
	var armored_source:Node2D=spawn("史莱姆",Vector2.ZERO,"Team0")
	var armored:Node2D=spawn("",Vector2.ZERO,"Team1")
	armored.global_position=armored_source.ground_point()+Vector2(u.radius(armored_source)+u.radius(armored)+3,0)
	armored.Damage_reduction=0.5
	armored.block=0
	var armored_before:int=armored.health
	armored_source.health=0
	check(armored_before-armored.health==22,"victim's live 50% reduction halves large slime's 44 death damage")
	check(knockback_on(armored)!=null,"defended but damaged victim is still pushed")
	armored_source.Die()
	await process_frame
	await physics_frame
	if is_instance_valid(armored_source) and not armored_source.is_queued_for_deletion(): armored_source.free()
	await clear_units()
	# Replicas must never apply damage, knockback or spawn an FX from HP replication.
	var replica:Node2D=spawn("史莱姆_小",Vector2.ZERO,"Team0","creatures")
	replica.set_multiplayer_authority(2)
	var other:Node2D=spawn("",Vector2(18,0),"Team1")
	other.health=10000
	var other_before:int=other.health
	var count_before:int=death_bursts().size()
	replica.health=0
	replica.Die()
	check(other.health==other_before and knockback_on(other)==null and death_bursts().size()==count_before,"non-authority replica does not resolve death damage or FX")
	# Mimic delivery of the authority's visual-only RPC after replicated HP is 0.
	var replica_point:Vector2=replica.ground_point()
	replica._jump_fx(replica_point,true,2,771,true)
	replica._jump_fx(replica_point,true,2,771,true)
	check(death_bursts().size()==count_before+1 and other.health==other_before and knockback_on(other)==null,"remote death visual renders once without client-side damage")
	var replica_fx:Node=death_bursts().back()
	await process_frame
	await physics_frame
	if is_instance_valid(replica) and not replica.is_queued_for_deletion(): replica.free()
	check(is_instance_valid(replica_fx) and replica_fx.visible and not replica_fx.is_queued_for_deletion(),"remote visual survives replica removal")
	await clear_units()
	print("SLIME_DEATH_PULSE checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
