extends SceneTree
## 体型对比截图：咒术回战角色 vs 普通角色，并打印可见像素包围盒（世界坐标）。
var arena:Node2D
func _initialize() -> void: call_deferred("run")

func vis_rect(u:Node2D) -> Rect2:
	var img:Sprite2D = u.get_node_or_null("Graphics/Image") as Sprite2D
	if img == null or img.texture == null: return Rect2()
	var used:Rect2 = Rect2(img.texture.get_image().get_used_rect())
	var size:Vector2 = img.texture.get_size()
	var local:Rect2 = Rect2(used.position - (size * 0.5 if img.centered else Vector2.ZERO) + img.offset,used.size)
	var xf:Transform2D = img.get_global_transform()
	return Rect2(xf * local.position,Vector2.ZERO).expand(xf * local.end)

func area_ratio(u:Node2D) -> float:
	var img:Sprite2D = u.get_node_or_null("Graphics/Image") as Sprite2D
	if img == null or img.texture == null: return 0.0
	var im:Image = img.texture.get_image()
	var used:Rect2i = im.get_used_rect()
	var n:int = 0
	for y:int in range(used.position.y,used.end.y,2):
		for x:int in range(used.position.x,used.end.x,2):
			if im.get_pixel(x,y).a > 0.5: n += 1
	return float(n) / maxf(1.0,float(used.size.x * used.size.y) / 4.0)

func run() -> void:
	create_timer(40.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = true
	root.size = Vector2i(1000,300)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var bg:ColorRect = ColorRect.new()
	bg.size = Vector2(1000,300)
	bg.color = Color("35434b")
	bg.z_index = -10
	arena.add_child(bg)
	var names:Array = OS.get_cmdline_user_args()
	var i:int = 0
	for path:String in names:
		var u:Node2D = load(path).instantiate()
		u.position = Vector2(60 + i * 110,150)
		arena.add_child(u,true)
		i += 1
	await process_frame
	await process_frame
	for u:Node in arena.get_children():
		if u is Node2D and u.get_node_or_null("Graphics") != null:
			var r:Rect2 = vis_rect(u)
			print("JJK_SIZE ",u.name," w=",snappedf(r.size.x,0.1)," h=",snappedf(r.size.y,0.1)," fill=",snappedf(area_ratio(u),0.01))
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://jjk_shots"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("user://jjk_shots/size_compare.png"))
	quit(0)
