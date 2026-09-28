extends "res://tests/test_sheep_bites.gd"
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	sheep.health = 200
	sheep._observed_health = 200
	sheep._since_hurt = 99
	sheep.step_mob(0.01)
	check(sheep.ram_state == sheep.RamState.GRAZE,"first low-health graze available")
	sheep.receive_positional_damage(10,Vector2.ZERO,false,null)
	check(sheep.ram_state == sheep.RamState.ROAM and is_equal_approx(sheep._graze_cooldown_left,8.0),"damage interruption starts eight second cooldown")
	sheep._begin_grazing()
	check(sheep.ram_state == sheep.RamState.ROAM,"direct entry cannot bypass cooldown")
	sheep.step_mob(3.1)
	check(sheep.ram_state == sheep.RamState.ROAM,"three second hurt delay alone cannot restart graze")
	var left:float = sheep._graze_cooldown_left
	game.now_stop_state = true
	sheep.step_mob(10)
	check(is_equal_approx(sheep._graze_cooldown_left,left),"pause freezes cooldown")
	game.now_stop_state = false
	sheep.step_mob(4.89)
	check(sheep.ram_state == sheep.RamState.ROAM,"still blocked before eight seconds")
	sheep.step_mob(0.02)
	check(sheep.ram_state == sheep.RamState.GRAZE,"eligible after cooldown")
	sheep.health = sheep.Max_health-1
	sheep._observed_health = sheep.health
	sheep._graze(0.8)
	check(sheep.health == sheep.Max_health and sheep.ram_state == sheep.RamState.ROAM,"full heal finishes graze")
	check(is_equal_approx(sheep._graze_cooldown_left,8.0),"full heal starts cooldown")
	sheep.health = 200
	sheep._observed_health = 200
	sheep._since_hurt = 99
	sheep.step_mob(7.99)
	check(sheep.ram_state == sheep.RamState.ROAM,"health threshold cannot bypass cooldown")
	sheep.step_mob(0.02)
	check(sheep.ram_state == sheep.RamState.GRAZE,"next graze starts normally")
	sheep.health -= 1
	sheep.step_mob(0.01)
	check(sheep.ram_state == sheep.RamState.ROAM and sheep._graze_cooldown_left >= 7.99 and sheep._graze_cooldown_left <= 8.0,"health setter interruption retains cooldown after next tick")
	sheep._graze_cooldown_left = 0
	sheep.ram_state = sheep.RamState.BRAKE_GRAZE
	sheep.receive_positional_damage(1,Vector2.ZERO,false,null)
	check(sheep.ram_state == sheep.RamState.ROAM and is_equal_approx(sheep._graze_cooldown_left,8.0),"braking interruption starts cooldown")
	sheep._since_hurt = 99
	sheep.ram_state = sheep.RamState.CHARGE
	sheep.step_mob(9)
	check(sheep.ram_state == sheep.RamState.CHARGE,"cooldown expiry does not interrupt charge")
	sheep.health = 0
	sheep._graze_cooldown_left = 4
	sheep.step_mob(2)
	check(is_equal_approx(sheep._graze_cooldown_left,4.0),"dead sheep does not tick cooldown")
	print("SHEEP_GRAZE_COOLDOWN_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
