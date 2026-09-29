extends "res://tests/test_mc_frontier.gd"

func visual_extent(unit:Node2D) -> float:
	var sprite:Sprite2D = unit.image
	var bounds:Rect2i = sprite.texture.get_image().get_used_rect()
	var extent:Vector2 = Vector2(bounds.size)*sprite.global_scale.abs()
	return maxf(extent.x,extent.y)

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	var wood:Node2D = actor("木剑",center+Vector2(-150,0))
	wood.visual_mob()
	var reference:float = visual_extent(wood)
	check(is_equal_approx(reference,24.0),"reference wooden-sword visible size remains unchanged")
	check(wood.Max_health==750 and wood.health==750 and wood.Damage==42 and wood.durability==60,"wooden sword spawns with buffed health, damage and durability")
	check(wood.default_properties.Max_health==750 and wood.default_properties.Damage==42,"default property cache retains buffed stats")
	check(is_equal_approx(wood.charge_duration,2.0) and wood.Speed==130.0,"charge timing and movement speed remain unchanged")
	var diamond:Node2D = actor("钻石剑",center)
	var mace:Node2D = actor("重锤",center+Vector2(150,0))
	for unit:Node2D in [diamond,mace]:
		check(absf(visual_extent(unit)-reference)<0.001,str(unit.name)+" visible pixels match wooden sword after initialization")
		check(unit.scale.is_equal_approx(wood.scale),"size change does not enlarge root or physics bodies")
	check(diamond.Damage==34 and diamond.Max_health==500 and mace.Damage==32 and mace.Max_health==650,"other weapons keep their existing combat stats")
	check(diamond.collision_shape_2d.shape.size==Vector2(76,122) and mace.collision_shape_2d.shape.size==Vector2(82,112),"display resizing leaves body collisions unchanged")
	for role:String in ["钻石剑","重锤"]:
		var preview:Node2D = load("res://scenes/characters/我的世界/"+role+".tscn").instantiate()
		var sprite:Sprite2D = preview.get_node("Graphics/Image")
		var bounds:Vector2 = Vector2(sprite.texture.get_image().get_used_rect().size)*sprite.scale.abs()
		check(absf(maxf(bounds.x,bounds.y)-120.0)<0.001,role+" scene preview scale matches the reference")
		preview.free()
	check(diamond.receive_netherite_ingot(),"diamond sword still accepts an upgrade")
	diamond._upgrade_to_netherite()
	check(diamond.upgraded_to_netherite and absf(visual_extent(diamond)-reference)<0.001,"netherite upgrade keeps the enlarged visible size")
	check(mace._air_visual_base_scale.is_equal_approx(mace.image.scale),"mace flight captures its enlarged rest size")
	mace._begin_flight(1)
	mace._update_flight(mace._flight_duration*0.5)
	check(visual_extent(mace)>reference,"mace still grows naturally with airborne perspective")
	mace._finish_landing()
	check(absf(visual_extent(mace)-reference)<0.001,"landing restores enlarged rest size instead of old scale")
	var hp:int = wood.health
	wood.take_damage(30.0,true)
	check(wood.health==hp-30 and wood.durability<60,"buffed wooden sword still loses health and durability when hit")
	wood._split_requested = true
	wood.split_sword()
	await process_frame
	var bench:Node2D = wood.workbench
	bench.set_physics_process(false)
	var parts:Array = bench.living_pieces()
	var total_max:int = 0
	for piece:Node2D in parts:
		piece.state_machine.set_physics_process(false)
		piece.dock_delay = 0
		total_max += piece.Max_health
		check(piece.Damage==42 and piece.default_properties.Damage==42,"each fragment inherits buffed base damage")
		piece.global_position = bench.global_position+Vector2(-8 if piece==wood else 8,0)
	check(parts.size()==2 and total_max==750,"splitting preserves the buffed total health cap")
	bench.age = bench.materialize_duration
	bench.advance(wood.repair_duration+0.01)
	check(wood.part_kind==0 and wood.Max_health==750 and wood.Damage==42 and wood.durability==60,"crafting restores buffed sword and its full new durability")
	check(absf(visual_extent(wood)-reference)<0.001,"wooden-sword size stays unchanged through rebuilding")
	print("WEAPON SIZE AND BALANCE: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
