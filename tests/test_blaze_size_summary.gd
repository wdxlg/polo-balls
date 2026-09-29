extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(90).timeout.connect(func(): finish(2))
	var unit:Node2D = actor("烈焰人",center+Vector2(34,0))
	var reference:Node2D = load("res://scenes/characters/我的世界/烈焰人.tscn").instantiate()
	reference.body_size_vs_creeper = 1.0
	world.add_child(reference,true)
	reference.global_position = center-Vector2(34,0)
	reference.state_machine.set_physics_process(false)
	reference.set_physics_process(false)
	reference.set_process(false)
	await process_frame
	await physics_frame
	await process_frame
	check(unit.body_size_vs_creeper==0.8,"default body size is 80 percent of the previous value")
	check(unit.image.scale.is_equal_approx(reference.image.scale*0.8),"native-animation attachment preserves the exact 20 percent visual reduction")
	check(unit.image.global_scale.abs().is_equal_approx(reference.image.global_scale.abs()*0.8),"rendered world scale is reduced without shrinking the whole actor")
	var body:RectangleShape2D = unit.collision_shape_2d.shape
	var hurt:RectangleShape2D = unit.get_node("hurtbox/CollisionShape2D").shape
	check(body.size.is_equal_approx(Vector2(78,155)*0.8),"body physics shape follows the 20 percent reduction")
	check(hurt.size.is_equal_approx(Vector2(74,150)*0.8),"hurt shape follows the 20 percent reduction")
	check(unit.get_node("BlazeRodA/CollisionShape2D").shape.size==Vector2(18,72),"external defensive rod dimensions are unchanged")
	check(unit.rod_orbit_x==27 and unit.rod_attack_orbit_x==72,"rod orbit and attack reach are not shrunk with the body")
	check(unit.fire_patch_radius==34 and unit.fireball_speed==330,"fireball speed and ground-fire radius remain unchanged")
	check(unit.Damage==28 and unit.Max_health==520,"size adjustment does not change damage or health")
	var locale:String = str(game.current_locale)
	game.current_locale = "zh_CN"
	var summary:String = world._armor_test_special_effect_summary(unit,unit.Type_Tags)
	check(summary.contains("灼烧") and summary.contains("持续掉血"),"actual armor-stand summary explains attack burning damage")
	check(summary.contains("地面或障碍物") and summary.contains("生成火焰") and summary.contains("周期伤害"),"summary explains impact ground fire and its damage")
	check(summary.contains("烈焰棒") and summary.contains("挡伤") and summary.contains("箭矢"),"summary explains rod shielding without claiming blanket invulnerability")
	check(summary.split("\n").size()==3 and summary.length()>120,"armor-stand text uses a complete three-paragraph explanation")
	var snapshot:Dictionary = world._armor_test_capture_snapshot(unit)
	check(snapshot.special==summary,"actual armor-stand UI snapshot consumes the new character-owned summary")
	unit.fireball_burn_duration = 4.7
	check(unit.get_armor_test_effect_summary().contains("4.7秒"),"summary duration follows current character parameters")
	unit.fireball_burn_duration = 3.2
	game.current_locale = "en"
	var english:String = world._armor_test_special_effect_summary(unit,unit.Type_Tags)
	check(english.contains("burning") and english.contains("ground fire") and english.contains("blocking arrows"),"English summary also includes all three requested mechanics")
	game.current_locale = locale
	# Actual rod collider and arrow interception, not just a descriptive claim.
	unit._update_rods(0.0)
	var rod:AnimatableBody2D = unit.get_node("BlazeRodA")
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters2D.create(rod.global_position+Vector2(0,-18),rod.global_position+Vector2(0,18),1,[unit.get_rid()])
	var contact:Dictionary = world.get_world_2d().direct_space_state.intersect_ray(query)
	check(contact.get("collider")==rod,"raycast hits the real orbiting rod collider")
	var shooter:Node2D = dummy(center+Vector2(0,-55))
	var arrow:Node2D = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(arrow)
	arrow.set_physics_process(false)
	arrow.global_position = rod.global_position+Vector2(0,-18)
	arrow.configure(shooter,shooter.Team,Vector2.DOWN,300.0,40.0,0.0,0.0,90.0,5.5)
	var hp:float = unit.health
	arrow._physics_process(0.12)
	check(arrow.is_queued_for_deletion() and unit.health==hp,"arrow hitting a rod is removed without damaging the Blaze body")
	# Real GPU rendering of old-size reference (left) and new body (right).
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480,320)
	viewport.world_2d = world.get_world_2d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera2D.new()
	viewport.add_child(camera)
	camera.position = center
	camera.zoom = Vector2.ONE*2.5
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = viewport.get_texture().get_image()
	check(image!=null and not image.is_empty(),"real GPU comparison viewport renders both native models")
	if image!=null: image.save_png("res://.git/blaze-size-summary/comparison.png")
	viewport.queue_free()
	print("BLAZE_SIZE_SUMMARY checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
