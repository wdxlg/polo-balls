extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("REWORK_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func spawn(path:String,point:Vector2,team:String):
	var packed:PackedScene = load(path)
	if packed == null:
		push_error("Scene unavailable: "+path)
		quit(2)
		return null
	var actor = packed.instantiate()
	actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in actor.find_children("*","CollisionObject2D",true,false):
		(child as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(actor,true)
	return actor
func run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(80,0),"B")
	await physics_frame
	sheep.health = int(sheep.Max_health*0.75)
	sheep._observed_health = sheep.health
	sheep._since_hurt = 10
	sheep._ram_left = 10
	sheep.step_mob(0.1)
	check(sheep.ram_state != sheep.RamState.GRAZE,"exact 75 percent does not graze")
	sheep.health -= 1
	sheep._observed_health = sheep.health
	sheep._since_hurt = 1
	sheep.step_mob(0.1)
	check(sheep.ram_state == sheep.RamState.ROAM,"recent damage prevents grazing")
	sheep._since_hurt = 4
	sheep.velocity = Vector2(100,0)
	sheep.step_mob(0.1)
	check(sheep.ram_state == sheep.RamState.BRAKE_GRAZE,"low health starts braking even with nearby enemy")
	sheep.move(sheep.Speed,0.1)
	check(sheep.velocity.x > 0 and sheep.velocity.x < 100,"brakes gradually not instant stop")
	for i:int in range(10): sheep.move(sheep.Speed,0.1)
	check(sheep.ram_state == sheep.RamState.GRAZE,"braking finishes in graze")
	enemy.global_position = sheep.global_position+Vector2(24,0)
	sheep.wool = 3
	sheep.step_mob(0.01)
	check(sheep._wool_phase == 1 and sheep.wool == 2,"near enemy compresses wool and consumes charge")
	check(sheep.ram_state == sheep.RamState.GRAZE,"defence does not interrupt eating")
	sheep._step_wool(0.07)
	sheep.visual_mob()
	check(sheep._wool_visual.scale.x > 1,"wool expands without initial compression")
	var body_scale:Vector2 = sheep.image.scale
	sheep._step_wool(0.08)
	check(sheep._wool_phase == 1 and enemy.Repel.length() > 0,"expansion pushes enemy")
	sheep._step_wool(0.06)
	sheep.visual_mob()
	check(sheep._wool_visual.scale.x < 1.0 and sheep.image.scale == body_scale,"only wool expands not body")
	check(sheep.Damage_reduction == 0,"old passive damage reduction removed")
	enemy.global_position = Vector2(800,0)
	sheep.wool = 0
	sheep._regrow = 0
	var before:int = sheep.health
	sheep._graze(1.0)
	check(sheep.health > before and sheep.wool == 0,"small actual heal accumulates but does not immediately repair")
	sheep._graze(3.1)
	check(sheep.wool == 1,"8 percent actual health recovered repairs one wool")
	sheep.health = sheep.Max_health-1
	sheep._observed_health = sheep.health
	sheep.ram_state = sheep.RamState.GRAZE
	sheep._graze(1)
	check(sheep.health == sheep.Max_health and sheep.ram_state == sheep.RamState.ROAM,"full HP ends eating even with missing wool")
	sheep._ram_left = 10
	sheep.step_mob(0.1)
	check(sheep.ram_state == sheep.RamState.ROAM,"full health cannot farm wool by eating")
	sheep.ram_state = sheep.RamState.GRAZE
	sheep.receive_positional_damage(15,sheep.global_position,false,enemy)
	check(sheep.ram_state == sheep.RamState.ROAM and sheep._since_hurt == 0,"actual health damage immediately interrupts")
	# Nearness does not fire defensive wool during attack, but incoming shots do.
	sheep.wool = 3
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	sheep.ram_state = sheep.RamState.CHARGE
	enemy.global_position = sheep.global_position+Vector2(25,0)
	sheep._step_wool(0.01)
	check(sheep._wool_phase == 0 and sheep.wool == 3,"proximity cannot proc during attack")
	var shot = spawn("res://scenes/shooter/子弹.tscn",sheep.global_position+Vector2(20,0),"B")
	shot.direction = Vector2.LEFT
	shot.Speed = 600
	shot.Master = enemy
	shot.Master_name = str(enemy.name)
	shot.Damage = 20
	before = sheep.health
	check(not sheep.can_receive_hit_from(shot.self_hitbox),"actual projectile hit rejected into compression")
	check(not sheep.should_destroy_projectile_on_rejected_hit(shot.self_hitbox),"deflected shot preserved rather than destroyed")
	check(sheep._wool_phase == 1,"projectile can proc defence during attack")
	var controller = shot.get_meta("mc_wool_flight").get_ref()
	check(controller.flying,"shot reflected immediately without hold")
	sheep._step_wool(0.15)
	check(controller.flying and controller.flight.x > 0,"shot flies outward after expansion")
	check(shot.Team.is_empty() and shot.Master == null and shot.Master_name.is_empty(),"reflection clears old owner and team")
	check(sheep.health == before,"successful defence does not cost health")
	# Neutral flight can hurt former shooter's faction, not just the sheep's enemies.
	enemy.global_position = shot.global_position+Vector2(40,0)
	before = enemy.health
	controller._physics_process(0.1)
	check(enemy.health < before,"neutral reflected shot damages former owner")
	await process_frame
	var friendly = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(1400,0),"A")
	var shot2 = spawn("res://scenes/shooter/子弹.tscn",Vector2(1300,0),"B")
	shot2.direction = Vector2.RIGHT
	shot2.Damage = 20
	sheep.global_position = Vector2(1280,0)
	sheep.wool = 1
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	check(sheep.catch_wool_projectile(shot2),"last wool can reflect")
	var controller2 = shot2.get_meta("mc_wool_flight").get_ref()
	sheep._step_wool(0.15)
	before = friendly.health
	controller2._physics_process(0.4)
	check(friendly.health < before,"neutral shot also damages sheep faction")
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	var shot3 = spawn("res://scenes/shooter/子弹.tscn",Vector2(1260,0),"B")
	check(not sheep.catch_wool_projectile(shot3),"no wool means no free reflection")
	# Fast charge deceleration, no repeated long glide.
	sheep.global_position = Vector2(3000,0)
	sheep._begin_charge(Vector2(3100,0))
	sheep._launch_charge()
	for i:int in range(12): sheep.move(sheep.Speed,1.0/60.0)
	check(sheep._charge_speed > sheep.Speed,"speed rises above default in 0.2 seconds")
	for i:int in range(24):
		if sheep.ram_state == sheep.RamState.CHARGE: sheep.move(sheep.Speed,1.0/60.0)
	check(sheep.ram_state == sheep.RamState.CHARGE,"accelerated charge continues until range limit")
	for i:int in range(60):
		if sheep.ram_state == sheep.RamState.CHARGE: sheep.move(sheep.Speed,1.0/60.0)
	check(sheep.ram_state == sheep.RamState.CHARGE,"charge no longer has distance expiry")
	# Real base-projectile movement path must intercept before a high-speed crossing.
	sheep.global_position = Vector2(4000,0)
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	sheep.wool = 2
	var fast_shot = spawn("res://scenes/shooter/子弹.tscn",Vector2(3920,0),"B")
	fast_shot.direction = Vector2.RIGHT
	before = sheep.health
	fast_shot.move(9000,1.0/60.0)
	check(fast_shot.has_meta("mc_wool_flight") and sheep.health == before,"real fast projectile move swept interception")
	check(sheep.wool == 1,"swept interception consumes one layer")
	var held = fast_shot.get_meta("mc_wool_flight").get_ref()
	sheep._release_wool_projectiles()
	check(held.flying,"removal cleanup releases held projectile")
	var friend_shot = spawn("res://scenes/shooter/子弹.tscn",Vector2(4020,0),"Ball")
	friend_shot.Master = friendly
	check(not sheep.catch_wool_projectile(friend_shot),"friendly inherited master team not reflected")
	# No defensive trigger across a physical wall.
	var barrier:StaticBody2D = StaticBody2D.new()
	var shape:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(4,160)
	shape.shape = box
	barrier.add_child(shape)
	arena.add_child(barrier)
	barrier.global_position = Vector2(3970,0)
	await physics_frame
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	var blocked = spawn("res://scenes/shooter/子弹.tscn",Vector2(3930,0),"B")
	blocked.direction = Vector2.RIGHT
	check(not sheep.WOOL_PROJECTILE.sweep(blocked,blocked.global_position,Vector2(4050,0)),"wall blocks sheep projectile interception")
	check(sheep.wool == 1,"wall-separated threat spends no wool")
	print("SHEEP_WOOL_GRAZE_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
