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
func wall_at(point:Vector2) -> StaticBody2D:
	var wall:StaticBody2D = StaticBody2D.new()
	var cs:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(5,200)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = point
	return wall
func effect_for(actor):
	for child in actor.get_children():
		if child.has_method("replace_with_hit") and child.is_active_effect(): return child
	return null
func run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var U = load("res://scripts/characters/我的世界/new5/utils.gd")
	var stand = spawn("res://scenes/characters/默认/虚无盔甲架.tscn",Vector2.ZERO,"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(300,0),"B")
	await physics_frame
	check(is_equal_approx(stand.modulate.a,0.75),"void armor stand opacity is 75 percent")
	check(stand.health_bar == null or not stand.health_bar.visible,"void armor stand has no visible health bar")
	check(stand.is_combat_targetable() and U.enemy(enemy,stand),"void stand remains a valid combat target")
	check(U.nearest(enemy) == stand,"enemy AI locks onto void stand")
	var hp:int = stand.health
	stand.take_damage(500,true)
	stand.receive_positional_damage(500,stand.global_position,false,enemy)
	stand.receive_spatial_damage(500,{"point":stand.global_position,"source":enemy},true,true)
	check(stand.health == hp and stand.health > 0,"void stand never loses health from any damage entry")
	stand.health = 0
	await physics_frame
	check(stand.health > 0 and stand.state_machine.current_state != stand.State.Die,"direct zero-health write reverts and never dies")
	var melee_hit = enemy.get_node("hitbox")
	check(stand.can_receive_hit_contact(melee_hit,stand.get_node("hurtbox")),"melee hits still register on void stand")
	var bullet = spawn("res://scenes/shooter/子弹.tscn",Vector2(0,-250),"B")
	bullet.Master = enemy
	check(not stand.can_receive_hit_contact(bullet.get_node("hitbox"),stand.get_node("hurtbox")),"projectile hit hook rejects void stand")
	bullet.direction = Vector2.DOWN
	var passed:bool = false
	var alive_after_pass:bool = false
	for tick:int in range(120):
		if not is_instance_valid(bullet): break
		bullet.move(bullet.Speed,1.0/60)
		await physics_frame
		if is_instance_valid(bullet) and bullet.global_position.y > 150:
			passed = true
			alive_after_pass = bullet.health > 0 and bullet.state_machine.current_state != bullet.State.Die
			break
	check(passed,"bullet physically passes through void stand")
	check(alive_after_pass,"bullet not consumed by void stand")
	check(stand.health == hp,"void stand unharmed after projectile pass")
	print("VOID_STAND_RESULT checks=",checks," failures=",failures)
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
