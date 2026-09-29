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
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(500,0),"B")
	var old_effect = sheep.apply_knockback(Vector2.UP,100,400)
	check(old_effect != null and sheep.dizziness,"ordinary sheep receives knockback")
	sheep._begin_charge(Vector2(500,0))
	check(not old_effect.is_active_effect() and not sheep.dizziness,"entering retreat clears previous knockback and its control lock")
	for phase:int in [sheep.RamState.WINDUP,sheep.RamState.CHARGE]:
		if phase==sheep.RamState.CHARGE: sheep._launch_charge()
		var result = sheep.apply_knockback(Vector2.UP,200,800,0.8,1.0,{"source":enemy})
		check(result==null and not sheep.dizziness,"retreat and charge reject knockback controllers "+str(phase))
		var hp:int = sheep.health
		sheep.receive_positional_damage(1,sheep.global_position,false,enemy)
		check(sheep.health<hp,"immunity does not block damage")
		sheep.Repel = Vector2(0,500)
		var start:Vector2 = sheep.global_position
		sheep.move(sheep.Speed,0.1)
		check(is_equal_approx(sheep.global_position.y,start.y) and sheep.Repel==Vector2.ZERO,"legacy repel cannot deflect movement")
		check(sheep.global_position.x<start.x if phase==sheep.RamState.WINDUP else sheep.global_position.x>start.x,"intended retreat or forward movement remains")
	sheep.step_mob(10)
	check(is_equal_approx(sheep._ram_left,5.0),"cooldown cannot expire during a long charge")
	sheep._finish_charge(false)
	check(is_equal_approx(sheep._ram_left,5.0),"full five second cooldown starts on finish")
	sheep.step_mob(4.9)
	check(sheep._ram_left>0 and sheep.ram_state==sheep.RamState.ROAM,"cooldown not ready at 4.9 seconds")
	sheep.step_mob(0.11)
	check(is_zero_approx(sheep._ram_left),"cooldown ready after five seconds")
	var normal = sheep.apply_knockback(Vector2.UP,100,400)
	check(normal!=null and sheep.dizziness,"knockback vulnerability restored outside ram")
	normal._finish(false)
	sheep._begin_charge(Vector2(500,0))
	sheep._launch_charge()
	sheep._finish_charge(true,false,520,Vector2.LEFT)
	check(sheep.dizziness and sheep._wall_stun_active(),"own wall crash still causes visible stun")
	print("SHEEP_RAM_IMMUNITY_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
