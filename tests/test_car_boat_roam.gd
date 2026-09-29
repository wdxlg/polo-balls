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
const FRAMES8 = preload("res://Images/characters/我的世界/new6/boat_frames8.tres")
func run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2.ZERO,"A")
	boat.Can_Skill = false
	boat.facing = Vector2.RIGHT
	await physics_frame
	var traveled:float = 0.0
	var previous:Vector2 = boat.global_position
	var min_speed:float = INF
	for tick:int in range(300):
		boat.step_mob(1.0/60)
		boat.move(boat.Speed,1.0/60)
		traveled += boat.global_position.distance_to(previous)
		previous = boat.global_position
		if tick>120: min_speed = minf(min_speed,absf(boat._forward_speed))
	check(traveled>400,"boat patrols actively without enemies")
	check(min_speed>40,"patrol keeps cruising momentum")
	boat._rowing = false
	boat.facing = Vector2.RIGHT
	boat.visual_mob()
	var tex_right:Texture2D = boat.image.texture
	check(tex_right==FRAMES8.get_frame_texture(&"d0_idle",0) and is_zero_approx(boat.graphics.rotation),"right heading uses baked direction 0 without rotation")
	boat.facing = Vector2.from_angle(PI)
	boat.visual_mob()
	check(boat.image.texture==FRAMES8.get_frame_texture(&"d4_idle",0) and boat.image.texture!=tex_right,"opposite heading uses baked direction 4")
	print("CAR_BOAT_ROAM_RESULT checks=",checks," failures=",failures)
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
