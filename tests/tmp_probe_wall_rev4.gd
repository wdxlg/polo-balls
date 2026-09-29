extends "res://tests/test_drowned_trident_aim_stick.gd"
# 临时探针：复现“撞墙插墙”段落，逐步打印弹道与墙体检测结果。
var GEOM
func run() -> void:
	GEOM = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(120.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.6).timeout
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1); return
	arena = world.return_map_world_rect(world.map_group["Map50x50"])
	center = arena.get_center()
	var drowned:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn", center+Vector2(-200,-260))
	var target:Node2D = dummy(center+Vector2(200,-260))
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14,220)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(-40,-260)
	await physics_frame
	print("PROBE_SETUP drowned=",drowned.global_position," target=",target.global_position," wall=",wall.global_position," range=",drowned.trident_range)
	print("PROBE_THROW started=",drowned.throw_trident(target))
	drowned._advance_trident_throw(drowned.trident_throw_windup+0.01)
	var spear:Node = drowned._trident
	spear.set_physics_process(false)
	print("PROBE_RELEASE origin=",spear.global_position," axis=",spear.axis," aim=",spear.aim_point," flight_length=",spear.flight_length)
	var rid:Array[RID] = [drowned.get_rid()]
	for i in range(120):
		spear.advance(1.0/120.0)
		if i%6==0 or spear.flight_state!=1:
			var from:Vector2 = spear.global_position
			var to:Vector2 = from+spear.axis*6.7
			var hit:Dictionary = GEOM.wall_ray(spear,from,to,rid)
			print("  step=",i," state=",spear.flight_state," traveled=%.1f"%spear.traveled," pos=",from," wall_ray=",("-" if hit.is_empty() else str(hit.position)+" "+str((hit.collider as Node).name))," planted=",spear.planted," seek=",spear.ground_seek)
		if spear.flight_state!=1: break
	print("PROBE_END state=",spear.flight_state," planted=",spear.planted," wall_ref=",spear.wall_ref," contact=",spear.plant_contact_point()," traveled=%.1f"%spear.traveled)
	finish(0)
