extends "res://tests/preview_mc_fog_clouds.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(30).timeout.connect(func(): finish(2))
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.enabled = false
	camera = Camera2D.new()
	world.add_child(camera)
	camera.position = center
	camera.zoom = Vector2.ONE*2.0
	camera.make_current()
	var man:Node2D = actor("雾中人",center)
	var enemy:Node2D = dummy(center+Vector2(120,0))
	enemy.state_machine.set_physics_process(false)
	fog = man.fog
	man.rage_origin = center
	man.rage_left = 4.0
	man.set_phase(man.Phase.RAGE)
	man.start_rush_attack(enemy,0)
	man.charge_fx.set_process(false)
	for i:int in range(6):
		man.position.x += 3.0
		man.charge_fx._process(0.04)
	var mist:Image = await capture()
	mist.save_png("res://tests/fog_rush_preview.png")
	check(not man.is_visible_in_tree() and not man.health_bar.is_visible_in_tree(),"GPU mist frame has no body or HUD")
	check(man.charge_fx.motes.size()>0,"GPU mist frame includes the moving cloud trail")
	man.charge_fx.hide()
	var plain:Image = await capture()
	var change:float = 0.0
	for x:int in range(-20,21,5):
		for y:int in range(-20,21,5): change = maxf(change,difference(mist,plain,man.global_position+Vector2(x,y)))
	print("RUSH MIST GPU CHANGE=",change)
	check(change>0.08,"replacement mist is actually rendered above terrain")
	man.charge_fx.show()
	man.start_rush_attack(enemy,1)
	while man.rush==man.Rush.FACE_VANISH: man.rush_step(enemy,0.06)
	man.charge_fx._process(0.0)
	var face:Image = await capture()
	face.save_png("res://tests/fog_face_preview.png")
	check(not man.is_visible_in_tree() and not man.health_bar.is_visible_in_tree(),"GPU face frame keeps body and HUD hidden")
	man.charge_fx.hide()
	var plain2:Image = await capture()
	plain2.save_png("res://tests/fog_face_plain.png")
	var face_change:float = 0.0
	for x:int in range(-44,45,8):
		for y:int in range(-56,25,8): face_change = maxf(face_change,difference(face,plain2,man.face_point+Vector2(x,y)))
	print("RUSH FACE GPU CHANGE=",face_change)
	check(face_change>0.08,"manifested face and burst fog are actually rendered")
	man.charge_fx.show()
	man.set_rush(man.Rush.RETREAT,0.45)
	man.clock += 1.0
	man.visual_mob()
	var retreat:Image = await capture()
	check(man.is_visible_in_tree() and man.image.is_visible_in_tree() and man.health_bar.is_visible_in_tree(),"body and HUD return for the visible retreat")
	retreat.save_png("res://tests/fog_rush_reveal.png")
	finish(0 if failures==0 else 1)
