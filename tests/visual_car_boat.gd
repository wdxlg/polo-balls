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
	RenderingServer.set_default_clear_color(Color("263449"))
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var camera:Camera2D = Camera2D.new()
	camera.zoom = Vector2(2,2)
	camera.position = Vector2(60,0)
	arena.add_child(camera)
	spawn("res://scenes/characters/默认/盔甲架.tscn",Vector2(0,0),"A")
	spawn("res://scenes/characters/默认/虚无盔甲架.tscn",Vector2(120,0),"A")
	for i:int in range(8): await process_frame
	await RenderingServer.frame_post_draw
	print("VOID_VISUAL ",root.get_texture().get_image().save_png("res://tests/void_stand.png"))
	quit()
