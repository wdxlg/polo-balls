extends "res://tests/test_mc_frontier.gd"
## Signed (inverse) enchantments through the shared ball damage hooks, the projectile
## runtime (Multishot / Piercing), stacking, the live tooltip, Mending and Impaling.

var enchant:Script

func fighter(at:Vector2,side:String) -> Node2D:
	var b:Node2D = dummy(at,side)
	b.state_machine.set_physics_process(false)
	b.self_hitbox.monitoring = false
	b.Has_Collision_Damage = false
	b.Max_health = 10000
	b.default_properties.Max_health = 10000
	b.health = 10000
	b.block = 0
	b.max_block = 0
	b.Damage_reduction = 0.0
	b.default_properties.Damage_reduction = 0.0
	return b

func close(actual:float,wanted:float,tolerance:float = 1.1) -> bool:
	return absf(actual-wanted) <= tolerance

func lost(target:Node2D,amount:float,source:Node,kind:StringName = &"") -> float:
	var before:float = float(target.health)
	if kind.is_empty(): target.receive_positional_damage(amount,target.global_position,false,source)
	else: target.receive_classified_positional_damage(amount,target.global_position,kind,false,source)
	return before-float(target.health)

func arrow(owner:Node2D,at:Vector2,heading:Vector2) -> Node2D:
	var shot:Node2D = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(shot,true)
	shot.global_position = at
	shot.configure(owner,str(owner.Team),heading,400.0,8.0,3.0,0.0,90.0,5.0)
	return shot

func arrows_of(owner:Node2D) -> Array[Node2D]:
	var result:Array[Node2D] = []
	for node:Node in get_nodes_in_group("MinecraftSkeletonArrow"):
		if node is Node2D and not node.is_queued_for_deletion() and node.get("_source_ref") != null and node._source_ref.get_ref() == owner: result.append(node)
	return result

func run() -> void:
	var center:Vector2 = await setup_world()
	enchant = load("res://scripts/effects/我的世界/mc_enchantments.gd")
	create_timer(80.0).timeout.connect(func(): finish(2))
	var attacker:Node2D = fighter(center+Vector2(-200.0,0.0),"Team0")
	var target:Node2D = fighter(center+Vector2(200.0,0.0),"Team1")
	await physics_frame
	await process_frame

	# Stacking: opposite signs cancel, 0 removes; the live box shows "-N" in red.
	check(enchant.add(attacker,"sharpness",-2) == -2 and enchant.levels_of(attacker) == {"sharpness":-2},"a negative level can be granted")
	await process_frame
	var box:Node = attacker.get_node_or_null("Minecraft附魔状态框")
	check(box != null and box.visible,"runtime enchantments show a live tooltip")
	var rows:Array = enchant.preview_entries(attacker)
	check(rows.size() == 1 and rows[0].level_text_override == "-2" and rows[0].text_color == Color("ff5555"),"inverse level row reads -2 in red")
	check(enchant.add(attacker,"sharpness",2) == 0 and enchant.levels_of(attacker).is_empty(),"positive levels cancel negative ones and 0 removes the enchantment")

	# Generic positional entry: Sharpness +10%/level, inverse lowers it.
	enchant.add(attacker,"sharpness",5)
	check(close(lost(target,100.0,attacker),150.0),"Sharpness V adds 50% through receive_positional_damage")
	check(close(lost(target,100.0,attacker,&"fire"),100.0),"elemental ticks such as fire are not boosted by attack enchantments")
	enchant.add(attacker,"sharpness",-8)
	check(close(lost(target,100.0,attacker),70.0),"inverse Sharpness III lowers script damage")
	enchant.remove(attacker,"sharpness")

	# A shot that reports its shooter as source counts as ranged through its carrier.
	enchant.add(attacker,"power",3)
	var shot:Node2D = arrow(attacker,target.global_position+Vector2(-20.0,0.0),Vector2.RIGHT)
	await physics_frame
	var carrier:Node = enchant.hit_carrier(attacker,target,target.global_position)
	check(carrier == shot,"a live owned arrow at the impact point is the hit carrier")
	check(close(lost(target,100.0,attacker),130.0),"Power applies to an arrow that names its shooter as source")
	shot.queue_free()
	await process_frame
	check(close(lost(target,100.0,attacker),100.0),"without a shot nearby the same source is melee and Power is ignored")
	enchant.remove(attacker,"power")

	# Thorns and inverse Thorns through the generic entry.
	enchant.add(target,"thorns",2)
	attacker.health = 5000
	lost(target,100.0,attacker)
	check(close(5000.0-float(attacker.health),10.0),"Thorns reflects through receive_positional_damage")
	enchant.add(target,"thorns",-4)
	attacker.health = 5000
	lost(target,100.0,attacker)
	check(close(float(attacker.health)-5000.0,10.0),"inverse Thorns heals the attacker")
	enchant.remove(target,"thorns")

	# Unbreaking: 100% immunity, inverse 100% double damage.
	enchant.add(target,"unbreaking",100)
	check(close(lost(target,100.0,attacker),0.0),"Unbreaking C ignores every hit")
	enchant.add(target,"unbreaking",-200)
	check(close(lost(target,100.0,attacker),200.0),"inverse Unbreaking C doubles every hit")
	enchant.remove(target,"unbreaking")

	# Inverse Protection / Breach.
	enchant.add(target,"protection",-4)
	check(close(lost(target,100.0,attacker),120.0),"inverse Protection IV adds 20% damage taken")
	enchant.remove(target,"protection")
	enchant.add(attacker,"breach",-4)
	check(close(lost(target,100.0,attacker),80.0),"inverse Breach IV raises the target reduction by 20 points")
	enchant.remove(attacker,"breach")

	# Inverse Knockback pulls; inverse Fire Aspect burns the attacker.
	await create_timer(0.3).timeout # Contact procs are limited to one per carrier/target per 250 ms.
	enchant.add(attacker,"knockback",-3)
	enchant.add(attacker,"fire_aspect",-2)
	lost(target,10.0,attacker)
	var pull:Node = null
	for child:Node in target.get_children():
		if child.name.begins_with("KnockbackEffect_"): pull = child
	check(pull != null,"inverse Knockback still moves the target")
	check(attacker.has_node("MinecraftBlazeBurn") and not target.has_node("MinecraftBlazeBurn"),"inverse Fire Aspect sets the attacker on fire, not the target")
	check(pull != null and Vector2(pull.direction).x < -0.9,"inverse Knockback pulls toward the attacker")
	enchant.remove(attacker,"knockback")
	enchant.remove(attacker,"fire_aspect")

	# Inverse Efficiency slows the real attack cooldown through the shared buff.
	enchant.add(attacker,"efficiency",-10)
	attacker.get_node("MinecraftEnchantments").call("_refresh_combat_buffs")
	await physics_frame
	await process_frame
	check(close(float(attacker.Attack_Cooling),2.0,0.05),"inverse Efficiency X doubles the attack cooldown")
	enchant.remove(attacker,"efficiency")
	check(is_equal_approx(enchant.charge_speed(attacker),1.0),"no Quick Charge means unchanged charge speed")
	enchant.add(attacker,"quick_charge",3)
	check(close(enchant.charge_speed(attacker),1.3,0.001),"Quick Charge III charges 30% faster")
	enchant.remove(attacker,"quick_charge")

	# Mending heals 5% of the victim max health per level on a kill.
	var victim:Node2D = fighter(center+Vector2(0.0,220.0),"Team1")
	victim.Max_health = 400
	victim.health = 5
	enchant.add(attacker,"mending",2)
	attacker.health = 5000
	victim.receive_positional_damage(50.0,victim.global_position,false,attacker)
	for i:int in range(4): await physics_frame
	check(close(float(attacker.health),5040.0),"Mending II heals 10% of the victim max health on a kill")
	enchant.remove(attacker,"mending")

	# Impaling ignores character bodies; removing it restores collisions.
	enchant.add(attacker,"impaling",1)
	await process_frame
	check(attacker.get_collision_exceptions().has(target),"Impaling adds a body exclusion with other characters")
	enchant.remove(attacker,"impaling")
	check(not attacker.get_collision_exceptions().has(target),"removing Impaling releases the exclusion")

	# Multishot II: one arrow becomes three, evenly spread over -45..+45 degrees.
	enchant.add(attacker,"multishot",2)
	for i:int in range(3): await process_frame
	var source_shot:Node2D = arrow(attacker,center+Vector2(-200.0,-300.0),Vector2.RIGHT)
	for i:int in range(3): await process_frame
	var spread:Array[Node2D] = arrows_of(attacker)
	var angles:Array[float] = []
	for node:Node2D in spread: angles.append(snappedf(rad_to_deg(Vector2(node._direction).angle()),1.0))
	angles.sort()
	check(spread.size() == 3 and angles == [-45.0,0.0,45.0],"Multishot II turns one arrow into three at -45/0/+45 (got %s)" % [angles])
	for node:Node2D in spread: node.queue_free()
	await process_frame
	enchant.remove(attacker,"multishot")

	# Inverse Multishot drops shots with 1/(|n|+1); at -1000 virtually every shot is retired.
	enchant.add(attacker,"multishot",-1000)
	for i:int in range(8): arrow(attacker,center+Vector2(-200.0,-300.0+i*10.0),Vector2.RIGHT)
	for i:int in range(3): await process_frame
	check(arrows_of(attacker).size() <= 1,"inverse Multishot keeps almost no shots at -1000")
	for node:Node2D in arrows_of(attacker): node.queue_free()
	enchant.remove(attacker,"multishot")

	# Piercing: a destroyed shot continues past the pierced target and skips it afterwards.
	enchant.add(attacker,"piercing",1)
	for i:int in range(3): await process_frame
	var lane:Node2D = fighter(center+Vector2(0.0,-260.0),"Team1")
	var lane_hp:float = float(lane.health)
	var pierce_shot:Node2D = arrow(attacker,lane.global_position+Vector2(-220.0,0.0),Vector2.RIGHT)
	var continued:Node2D = null
	for i:int in range(90):
		await physics_frame
		for node:Node2D in arrows_of(attacker):
			if node != pierce_shot and node.global_position.x > lane.global_position.x+20.0: continued = node
		if continued != null: break
	check(float(lane.health) < lane_hp,"the arrow really hit the first target")
	check(continued != null and continued.has_meta("mc_projectile_clone"),"a stopped pierced shot continues on the far side of the target")
	check(continued != null and not enchant.allow_projectile_hit(continued,lane),"the continuation never hits the pierced target again")
	for node:Node2D in arrows_of(attacker): node.queue_free()
	enchant.remove(attacker,"piercing")

	# Inverse Piercing shatters the shot on its first character hit (100% at -10).
	enchant.add(attacker,"piercing",-10)
	for i:int in range(3): await process_frame
	var brittle:Node2D = arrow(attacker,center+Vector2(-200.0,300.0),Vector2.RIGHT)
	for i:int in range(3): await process_frame
	check(not enchant.allow_projectile_hit(brittle,target),"inverse Piercing X makes the first character hit fizzle")
	enchant.remove(attacker,"piercing")

	print("MC ENCHANT SIGNED HOOKS RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
