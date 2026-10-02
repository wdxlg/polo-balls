extends "res://tests/test_mc_frontier.gd"

var enchant:Script

func fighter(at:Vector2, side:String) -> Node2D:
	var b:Node2D = dummy(at,side)
	b.state_machine.set_physics_process(false)
	b.self_hitbox.monitoring = false
	b.Has_Collision_Damage = false
	b.Max_health = 10000
	b.default_properties.Max_health = 10000
	b.health = 10000
	b.max_block = 500
	b.default_properties.max_block = 500
	b.block = 0
	b.Damage_reduction = 0.0
	b.default_properties.Damage_reduction = 0.0
	return b

func damage_from(b:Node2D,amount:float) -> void:
	b.Damage = amount
	b.default_properties.Damage = amount

func hit(a:Node2D,b:Node2D) -> void:
	a._on_hitbox_on_hit(b.self_hurtbox)

func close(actual:float,wanted:float,tolerance:float = 1.1) -> bool:
	return absf(actual - wanted) <= tolerance

func knockbacks(b:Node2D) -> int:
	var count:int = 0
	for node:Node in b.get_children():
		if node.name.begins_with("KnockbackEffect_"): count += 1
	return count

func run() -> void:
	var center:Vector2 = await setup_world()
	enchant = load("res://scripts/effects/我的世界/mc_enchantments.gd")
	create_timer(80.0).timeout.connect(func(): finish(2))
	var attacker:Node2D = fighter(center + Vector2(-160.0,0.0),"Team0")
	var defender:Node2D = fighter(center + Vector2(160.0,0.0),"Team1")
	damage_from(attacker,100.0)
	attacker.Speed = 200.0
	attacker.default_properties.Speed = 200.0
	await physics_frame
	await process_frame

	# Breach must ignore five percent damage reduction AND send five percent
	# of the mitigated hit straight to HP, even when the shield has room.
	defender.Damage_reduction = 0.4
	defender.default_properties.Damage_reduction = 0.4
	defender.block = 500
	enchant.apply(attacker,"breach",1)
	var hp:float = float(defender.health)
	var shield:float = float(defender.block)
	hit(attacker,defender)
	check(close(hp - float(defender.health),3.25),"breach deals five percent post-armor damage through the shield")
	check(close(shield - float(defender.block),61.75),"breach bypasses five percent of armor without creating extra shield damage")
	check(not defender.has_meta("_mc_enchant_armor_penetration") and not defender.has_meta("_mc_enchant_shield_bypass"),"breach hit context is cleared")
	enchant.remove(attacker,"breach")
	defender.health = 10000
	defender.block = 500
	hp = float(defender.health)
	hit(attacker,defender)
	check(close(float(defender.health),hp,0.01),"without breach a shielded hit does not wound")

	# Density is calculated from the live speed attribute at the hit site.
	defender.block = 0
	defender.health = 10000
	defender.Damage_reduction = 0.0
	defender.default_properties.Damage_reduction = 0.0
	enchant.apply(attacker,"density",2)
	hp = float(defender.health)
	hit(attacker,defender)
	check(close(hp - float(defender.health),100.0+float(attacker.Speed)*0.10),"density adds ten percent of current Speed to outgoing damage at level two")
	enchant.remove(attacker,"density")

	defender.health = 10000
	defender.set_meta("mc_creature_family","arthropod")
	enchant.apply(attacker,"bane_of_arthropods",2)
	hp = float(defender.health)
	hit(attacker,defender)
	check(close(hp - float(defender.health),160.0),"bane grants thirty percent per level against marked arthropods")
	defender.remove_meta("mc_creature_family")
	defender.health = 10000
	hp = float(defender.health)
	hit(attacker,defender)
	check(close(hp - float(defender.health),100.0),"bane does not increase damage to unmarked targets")
	enchant.remove(attacker,"bane_of_arthropods")

	# Only the actual HP + shield lost to this hit is reflected once, even
	# if armor and equipment both supply Thorns.
	var armor:Node = Node.new()
	armor.name = "EnchantedArmor"
	defender.add_child(armor)
	enchant.apply(defender,"thorns",1)
	enchant.apply(armor,"thorns",2)
	defender.block = 50
	defender.health = 10000
	attacker.health = 10000
	var attacked_hp:float = float(attacker.health)
	hp = float(defender.health)
	shield = float(defender.block)
	hit(attacker,defender)
	var actual_loss:float = hp - float(defender.health) + shield - float(defender.block)
	check(close(actual_loss,100.0),"thorns baseline records real HP plus shield loss")
	check(close(attacked_hp - float(attacker.health),actual_loss * 0.10),"thorns reflects highest equipped level once after mitigation")
	var protected_target:Node2D = fighter(center + Vector2(0.0,260.0),"Team1")
	enchant.apply(protected_target,"protection",1)
	enchant.apply(protected_target,"projectile_protection",1)
	hp = float(protected_target.health)
	hit(attacker,protected_target)
	check(close(hp - float(protected_target.health),95.0),"regular protection lowers live melee damage five percent per level")

	# Buffs must be reversible and require a real water state, not a blue map.
	var component:Node = enchant.ensure(attacker)
	enchant.apply(attacker,"efficiency",2)
	enchant.apply(attacker,"aqua_affinity",2)
	enchant.apply(attacker,"depth_strider",3)
	component.call("_refresh_combat_buffs")
	var source:int = attacker.get_instance_id()
	var attack_name:String = "MC附魔攻速"
	var speed_name:String = "MC附魔水中移速"
	check(attacker.Buff_Dic.has(source) and attacker.Buff_Dic[source].has(attack_name),"efficiency applies a live attack cooldown buff")
	check(close(float(attacker.Buff_Dic[source][attack_name].amount),1.0/1.10,0.001),"dry cooldown buff is inverse of ten percent attack speed")
	check(not attacker.Buff_Dic[source].has(speed_name),"water movement bonus cannot activate on a dry map")
	attacker.set_meta("in_water",true)
	component.call("_refresh_combat_buffs")
	check(close(float(attacker.Buff_Dic[source][attack_name].amount),1.0/1.30,0.001),"submerged mining and efficiency combine attack speed")
	check(attacker.Buff_Dic[source].has(speed_name) and close(float(attacker.Buff_Dic[source][speed_name].amount),1.30,0.001),"depth strider adds ten percent per level while submerged")
	await physics_frame
	await process_frame
	check(close(float(attacker.Speed),260.0) and close(float(attacker.Attack_Cooling),1.0/1.30,0.02),"submerged bonuses change actual Speed and Attack_Cooling attributes")
	attacker.set_meta("in_water",false)
	component.call("_refresh_combat_buffs")
	check(close(float(attacker.Buff_Dic[source][attack_name].amount),1.0/1.10,0.001) and not attacker.Buff_Dic[source].has(speed_name),"leaving water removes only the water bonuses")
	await physics_frame
	await process_frame
	check(close(float(attacker.Speed),200.0) and close(float(attacker.Attack_Cooling),1.0/1.10,0.02),"leaving water restores live Speed and retains efficiency attack speed")
	enchant.remove(attacker,"efficiency")
	component.call("_refresh_combat_buffs")
	check(not attacker.Buff_Dic.has(source) or not attacker.Buff_Dic[source].has(attack_name),"unequipping the attack enchant clears its buff")
	await physics_frame
	await process_frame
	check(close(float(attacker.Attack_Cooling),1.0,0.02),"unequipping efficiency restores the actual attack cooldown")

	# Mode-specific effects are delivered exactly at the authoritative hit.
	var melee_target:Node2D = fighter(center + Vector2(300.0,140.0),"Team1")
	var ranged_target:Node2D = fighter(center + Vector2(300.0,-140.0),"Team1")
	var projectile:Node2D = fighter(center + Vector2(-300.0,-140.0),"Team0")
	projectile.Type = 1 # ball.Ball_Type.Shooter; avoid preloading ball before autoload setup
	projectile.Master = attacker
	damage_from(projectile,80.0)
	hp = float(protected_target.health)
	hit(projectile,protected_target)
	check(close(hp - float(protected_target.health),68.4),"projectile protection independently reduces ranged damage ten percent per level")
	enchant.apply(attacker,"fire_aspect",1)
	enchant.apply(attacker,"knockback",1)
	hit(attacker,melee_target)
	check(melee_target.has_node("MinecraftBlazeBurn") and knockbacks(melee_target) == 1,"melee flame and knockback apply once to melee hit")
	hit(projectile,ranged_target)
	check(not ranged_target.has_node("MinecraftBlazeBurn") and knockbacks(ranged_target) == 0,"melee-only effects do not follow a projectile")
	enchant.remove(attacker,"fire_aspect")
	enchant.remove(attacker,"knockback")
	enchant.apply(attacker,"flame",1)
	enchant.apply(attacker,"punch",1)
	var other_melee:Node2D = fighter(center + Vector2(-300.0,140.0),"Team1")
	hit(attacker,other_melee)
	check(not other_melee.has_node("MinecraftBlazeBurn") and knockbacks(other_melee) == 0,"ranged-only effects do not apply to melee")
	var other_ranged:Node2D = fighter(center + Vector2(140.0,-300.0),"Team1")
	hit(projectile,other_ranged)
	check(other_ranged.has_node("MinecraftBlazeBurn") and knockbacks(other_ranged) == 1,"projectiles inherit master flame and punch once")
	var shield_only:Node2D = fighter(center + Vector2(-280.0,-300.0),"Team1")
	enchant.apply(shield_only,"thorns",2)
	shield_only.block = 500
	attacker.health = 10000
	attacked_hp = float(attacker.health)
	hit(attacker,shield_only)
	check(shield_only.health == 10000 and close(attacked_hp - float(attacker.health),10.0),"a fully blocked hit still reflects ten percent of real shield loss")
	var fatal_target:Node2D = fighter(center + Vector2(280.0,300.0),"Team1")
	enchant.apply(fatal_target,"thorns",2)
	fatal_target.health = 30
	attacker.health = 10000
	attacked_hp = float(attacker.health)
	hit(attacker,fatal_target)
	check(fatal_target.health == 0 and close(attacked_hp - float(attacker.health),3.0),"a fatal hit reflects only the thirty HP actually lost")

	print("MC ENCHANT REBALANCE RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
