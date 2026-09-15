extends SceneTree
var game:Node
var saved:Dictionary
var world:Node
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.versus_label.hide()
	world.interaction_label.hide()
	world._center_watermark_root.hide()
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map10x10"])
	world.camera_2d.global_position = rect.get_center()
	world.camera_2d.position_smoothing_enabled = false
	world.camera_2d.zoom = Vector2.ONE*3.8
	world.camera_2d.force_update_scroll()
	for i:int in range(8):
		var side:float = -1.0 if i<4 else 1.0
		var actor:Node2D = load("res://scenes/characters/月计/殷红迷雾.tscn").instantiate()
		actor.Team = "Team0"
		actor.position = rect.get_center()+Vector2(side*20,-60+(i%4)*40)
		actor.scale = Vector2.ONE*0.5
		world.add_child(actor,true)
		actor.graphics.hide()
		actor.health_bar.hide()
		var dir:Vector2 = Vector2.RIGHT*side
		var area:Area2D = actor._create_local_rect_attack_volume(dir,Vector2(220,64),1.0,30.0)
		actor._spawn_blade_light_on_area(i%4,area,Vector2(220,64),i>=4)
		var effect:Node2D = world.get_child(world.get_child_count()-1)
		effect._elapsed = 0.10
		effect._update_material(0.14)
		var outline:=Line2D.new()
		outline.z_as_relative = false
		outline.z_index = 150
		outline.default_color = Color(0.1,1.0,0.9,0.8)
		outline.width = 0.5
		outline.closed = true
		var h:Vector2 = Vector2(110,32)*0.5
		var p:Vector2 = area.global_position
		outline.points = PackedVector2Array([p-h,p+Vector2(h.x,-h.y),p+h,p+Vector2(-h.x,h.y)])
		world.add_child(outline)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://scripts/training/mist_alignment_gpu.png")
	game.Game_Settings = saved
	print("MIST_ALIGNMENT_GPU_OK")
	quit()
