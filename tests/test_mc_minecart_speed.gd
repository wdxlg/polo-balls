extends "res://tests/test_mc_minecart.gd"
func enter(cart:Node2D,point:Vector2,goal:Vector2) -> void:
	cart.end_rush()
	cart.global_position=point
	cart.entry_needs_exit=false
	cart._boarding_lock=0.0
	cart.idle_left=999
	cart.set_player_control_peer(1)
	cart.set_player_control_aim_position(goal)
	check(board_fixture(cart,int(cart.rails.cell_at(point).id)),"board speed test route")
func run() -> void:
	var center:Vector2=await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var cart:Node2D=actor("矿车",center)
	var victim:Node2D=dummy(center+Vector2(200,200))
	await physics_frame
	await process_frame
	var net:Node2D=cart.rails
	var o:Vector2=net.cell_to_world(net.world_to_cell(center))
	var left:Vector2=o-Vector2(288,0)
	var right:Vector2=o+Vector2(288,0)
	cart.global_position=left
	build_grid(cart,PackedVector2Array([left,right]))
	enter(cart,left,right)
	cart.drive_speed=700
	cart.move(0,0.05)
	check(cart.drive_speed>700,"ordinary rail continues accelerating above old 620 cap")
	enter(cart,left,right)
	cart.drive_speed=2500
	cart.move(0,0.05)
	check(cart.drive_speed>2500,"no replacement cap at high speed")
	check(cart.global_position.x-left.x>124 and cart.global_position.x-left.x<128,"real movement matches high speed rather than silently truncating travel")
	var base:float=cart.attack_damage(1.0)
	cart.drive_speed=620
	var first:float=cart.rush_attack_damage()
	check(is_equal_approx(first,base*(0.35+4.7)),"at old maximum, speed bonus is doubled from 2.35 to 4.7")
	cart.drive_speed=1240
	var second:float=cart.rush_attack_damage()
	check(is_equal_approx(second,base*(0.35+4.7*4.0)),"damage keeps growing quadratically above old maximum")
	check(second>first*3.5,"doubling speed significantly raises damage")
	var view:Dictionary=cart.visual_state()
	cart.accept_visual(view)
	check(cart.drive_speed==1240,"remote visual snapshot preserves speed above 620")
	var bad:Dictionary=view.duplicate()
	bad.speed=INF
	cart.accept_visual(bad)
	check(cart.drive_speed==0,"non-finite remote speed is rejected without imposing a normal speed cap")
	enter(cart,left,right)
	cart.drive_speed=1240
	victim.global_position=left+Vector2(24,0)
	await physics_frame
	var hp:float=victim.health
	check(cart.hit_enemy(victim,cart.global_position),"higher-speed impact actually damages a target")
	check(hp-victim.health>first,"real HP damage exceeds old-reference-speed damage")
	check(not cart.hit_enemy(victim,cart.global_position),"per-victim one-second cooldown still prevents repeated overlap damage")
	victim.global_position=o+Vector2(200,200)
	# Swept body collision must remain safe well beyond the former maximum.
	enter(cart,left,right)
	cart.drive_speed=5000
	var barrier:StaticBody2D=wall(left+Vector2(96,0),Vector2(8,96))
	await physics_frame
	await process_frame
	cart.move(0,0.04)
	check(cart.global_position.x<barrier.global_position.x,"high-speed cart cannot pass through a thin terrain wall")
	check(cart.rush_phase==0,"wall collision ends high-speed travel normally")
	barrier.queue_free()
	await process_frame
	enter(cart,left,right)
	cart.drive_speed=1500
	cart.route_braking=true
	cart.move(0,0.01)
	check(cart.drive_speed<1500 and cart.drive_speed>1400,"manual braking still works above old maximum")
	game.now_stop_state=true
	var previous:float=cart.drive_speed
	cart.tick_physics(0,0.1)
	check(cart.drive_speed==previous,"pause freezes uncapped travel")
	game.now_stop_state=false
	var fx_source:String=cart.cart_fx.get_script().source_code
	check(not fx_source.contains("draw_texture_rect") and not fx_source.contains("POWERED_RAIL"),"five-icon speed bar renderer and its icon references are removed")
	check(cart.get_armor_test_effect_summary().contains("车速没有上限") or cart.get_armor_test_effect_summary().contains("without a speed cap"),"in-game mechanic summary reflects uncapped speed")
	print("RAIL SPEED CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
