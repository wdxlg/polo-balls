extends "res://tests/test_ding_sleep.gd"
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	game=root.get_node("Game");game.now_stop_state=false;game.Game_Settings.Have_Team_Damage=false
	arena=Node2D.new();root.add_child(arena);current_scene=arena
	cat=load(CAT_PATH).instantiate();cat.Team="Team0";arena.add_child(cat);cat.state_machine.set_physics_process(false)
	check(cat.z_speed==110.0,"spawner default speed halved")
	check(cat.Speed==100.0 and cat.scale==Vector2(0.14,0.14),"cat movement speed and size unchanged")
	var z:Node2D=shot(Vector2(0,-100))
	check(z.Speed==110.0 and is_equal_approx(z.get_projectile_velocity().length(),110.0),"Z scene speed uses same 110 actual units per second")
	check(z.Projectile_Auto_Face_Motion,"Z opts into shared actual-motion facing")
	for i:int in range(8):
		z.global_position=Vector2(0,-100)
		z.direction=Vector2.from_angle(TAU*i/8.0)
		z.velocity=Vector2.ZERO
		var before:Vector2=z.global_position
		z.tick_physics(0,1.0/60.0)
		var motion:Vector2=z.global_position-before
		check(is_equal_approx(motion.length(),110.0/60.0),"actual movement is 110 units/sec direction %d" % i)
		check(absf(angle_difference(z._z_label.get_global_transform().get_rotation(),motion.angle()))<0.001,"Z glyph faces actual movement direction %d" % i)
	z.global_position=Vector2(0,-100);z.direction=Vector2.RIGHT;z.velocity=Vector2.ZERO
	var enemy:Node2D=target(Vector2(150,-30))
	z.tick_physics(0,0.1)
	check(z.direction.y>0.0 and absf(angle_difference(z.global_rotation,z.direction.angle()))<0.001,"homing curve turns Z glyph with trajectory")
	enemy.queue_free();await flush()
	z.set_projectile_velocity(Vector2.UP*110)
	z.tick_physics(0,1.0/60.0)
	check(absf(angle_difference(z._z_label.get_global_transform().get_rotation(),-PI/2.0))<0.001,"redirected projectile uses updated flight direction")
	var position_before:Vector2=z.global_position;var rotation_before:float=z.global_rotation
	game.now_stop_state=true;z.tick_physics(0,1.0)
	check(z.global_position==position_before and z.global_rotation==rotation_before,"pause freezes position and facing")
	game.now_stop_state=false
	game.set_language("en",false)
	check(game.t("丁某人睡觉")=="me","battle English name is exactly lowercase me")
	check(game.translate_game_text("丁某人睡觉")=="me","game text translation uses me")
	var catalog:Variant=load("res://global/translation_catalog.gd")
	check(catalog.TABLE.en["丁某人睡觉"]=="me","export-safe English mirror is me")
	game.set_language("zh",false)
	check(game.t("丁某人睡觉")=="丁某人睡觉","Chinese display name unchanged")
	z.queue_free();cat.queue_free();await create_timer(1.0).timeout
	arena.queue_free();await flush()
	print("DING_Z_FACING_ME_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
