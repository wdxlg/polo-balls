extends SceneTree
var arena:Node2D
func _initialize() -> void: call_deferred("run")
func spawn(path:String,point:Vector2,team:String):
	var actor = load(path).instantiate()
	actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(actor,true)
	return actor
func run() -> void:
	root.size = Vector2i(960,640)
	root.get_node("Game").now_stop_state = false
	RenderingServer.set_default_clear_color(Color("263449"))
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var camera:Camera2D = Camera2D.new()
	camera.zoom = Vector2(4,4)
	arena.add_child(camera)
	var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(-55,-25),"A")
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(-50,-25),"A")
	var mace = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(-65,-25),"B")
	boat.facing = Vector2.RIGHT
	boat.visual_mob()
	boat.board_unit(sheep)
	boat.board_unit(mace)
	sheep.visual_mob()
	sheep.apply_transport_pose()
	mace.apply_transport_pose()
	var other = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(60,-25),"A")
	var rider = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(60,-20),"B")
	var rider2 = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(60,-30),"A")
	rider2.wool = 0
	other.facing = Vector2(-0.7,0.7).normalized()
	other.visual_mob()
	other.board_unit(rider)
	other.board_unit(rider2)
	rider.visual_mob()
	rider2.visual_mob()
	rider.apply_transport_pose()
	rider2.apply_transport_pose()
	var ram = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(-55,42),"A")
	ram._begin_charge(Vector2(30,42))
	ram._wool_phase = 1
	ram._wool_elapsed = 0.13
	ram.visual_mob()
	var graze = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(60,42),"A")
	graze.ram_state = graze.RamState.GRAZE
	graze._wool_phase = 2
	graze._wool_elapsed = 0.07
	graze.visual_mob()
	for i:int in range(6): await process_frame
	await RenderingServer.frame_post_draw
	print("VISUAL_SAVED ",root.get_texture().get_image().save_png("res://tests/sheep_boat_visual.png"))
	quit()
