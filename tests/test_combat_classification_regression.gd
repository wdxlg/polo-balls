extends "res://tests/test_mc_frontier.gd"
## Real damage before/after regression; no dependency on the new classifier.
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(80.0).timeout.connect(func():finish(2))
	var victim:Node2D = dummy(center)
	victim.block = 0
	victim.Damage_reduction = 0
	victim.fire_effect_ratio = 0.0
	var before:float = victim.health
	victim.receive_spatial_damage(40.0,{"point":center,"element":"fire"},false,false)
	check(victim.health == before,"explicit spatial fire must respect fire immunity")
	victim.fire_effect_ratio = 0.5
	before = victim.health
	victim.receive_spatial_damage(40.0,{"point":center,"element":"fire"},false,false)
	check(before-victim.health == 20.0,"explicit spatial fire uses multiplier exactly once")
	victim.cold_effect_ratio = 0.0
	before = victim.health
	victim.receive_spatial_damage(40.0,{"point":center,"element":"cold"},true,true)
	check(victim.health == before,"raw-health spatial cold cannot bypass cold immunity")
	var web:Node = load("res://scenes/shooter/蜘蛛地网.tscn").instantiate()
	var contact:GDScript = load("res://scripts/projectile_contact.gd")
	check(not contact.is_projectile(web),"stationary ground web is terrain, not flying projectile")
	web.free()
	var boat:Node2D = actor("木船",center+Vector2(100,0))
	boat.Max_health = 10000
	boat.health = 10000
	boat.block = 0
	boat.Damage_reduction = 0
	boat.fire_effect_ratio = 1.0
	victim.fire_effect_ratio = 0.0
	# An actual passenger is required; simply appending a node is not enough.
	boat._attach_passenger(victim,0)
	check(victim.is_transport_mounted(),"real boat rider attached")
	before = victim.health
	boat.receive_fire_positional_damage(60.0,center,false,null)
	check(victim.health == before,"boat sharing preserves each passenger's fire immunity")
	print("CLASSIFICATION_REGRESSION checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
