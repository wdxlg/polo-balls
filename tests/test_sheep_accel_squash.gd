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
	create_timer(30).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(-1000,0),"A")
	sheep._begin_charge(Vector2(-800,0))
	check(sheep._retreat_current_speed == 80,"retreat starts at previous retreat speed")
	var previous:float = sheep._retreat_current_speed
	var decreasing:bool = true
	for i:int in range(11):
		sheep.move(sheep.Speed,0.05)
		if sheep._retreat_current_speed > previous: decreasing = false
		previous = sheep._retreat_current_speed
	check(decreasing and sheep._retreat_current_speed < 0.01,"retreat decelerates to standstill")
	check(absf(sheep.global_position.x+1022.0) < 0.1,"retreat distance follows braking curve")
	sheep._launch_charge()
	check(sheep._charge_speed == sheep.Speed,"charge launches at default movement speed")
	var initial:float = sheep._charge_speed
	var locked:Vector2 = sheep._charge_dir
	sheep.move(sheep.Speed,0.2)
	check(absf(sheep._charge_speed-initial-130.0)<0.1,"charge accelerates at configured rate")
	var intermediate:float = sheep._charge_speed
	sheep.move(sheep.Speed,0.2)
	check(sheep._charge_speed > intermediate and sheep._charge_dir == locked,"charge speeds up without homing")
	for i:int in range(15):
		if sheep.ram_state == sheep.RamState.CHARGE: sheep.move(sheep.Speed,0.1)
	check(sheep.ram_state == sheep.RamState.CHARGE,"miss continues until a real obstacle")
	sheep.global_position = Vector2(3000,0)
	wall_at(Vector2(3090,0))
	await physics_frame
	sheep._begin_charge(Vector2(3200,0))
	sheep._launch_charge()
	for i:int in range(60):
		if sheep.ram_state != sheep.RamState.CHARGE: break
		sheep.move(sheep.Speed,1.0/60.0)
	check(sheep.ram_state == sheep.RamState.RECOVER and sheep.dizziness,"accelerated real wall crash retains stun")
	check(sheep._wall_squash_age == 0,"wall contact starts squash animation")
	var sounds:int = 0
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","") == "entity.sheep.wall_impact": sounds += 1
	check(sounds == 1,"one native collision sound per actual wall hit")
	var radius:float = sheep.get_node("CollisionShape2D").shape.radius
	sheep._wall_squash_age = 0.065
	sheep.visual_mob()
	check(sheep.image.scale.x < sheep._visual_base_scale.x and sheep.image.scale.y > sheep._visual_base_scale.y,"horizontal crash flattens horizontally and bulges vertically")
	check(sheep.get_node("CollisionShape2D").shape.radius == radius,"visual squash never changes physical collider")
	sheep._wall_squash_age = 0.065+(sheep.wall_squash_duration-0.065)/3.0
	sheep.visual_mob()
	check(sheep.image.scale.x > sheep._visual_base_scale.x,"recovery overshoots elastically")
	sheep._wall_squash_age = sheep.wall_squash_duration+0.01
	sheep.visual_mob()
	check(sheep.image.scale.is_equal_approx(sheep._visual_base_scale),"recovery restores exact original size")
	sheep._wall_squash_age = 0.065
	sheep._wall_squash_axis = Vector2.DOWN
	sheep.visual_mob()
	check(sheep.image.scale.y < sheep._visual_base_scale.y and sheep.image.scale.x > sheep._visual_base_scale.x,"vertical wall impact uses matching squash axis")
	check(sheep.visual_state().has("wall_squash_age"),"deformation included in visual sync")
	print("SHEEP_ACCEL_SQUASH_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
