extends SceneTree
## 咒术回战领域视觉截图（需要 GPU）：无量空处 + 伏魔御厨子同时展开，含结界受损与翻转。
## godot --path . --audio-driver Dummy --rendering-method gl_compatibility --resolution 1280x960 --script res://tests/test_jjk_domain_gallery.gd
const DIR:String = "res://scenes/characters/动漫/"
var arena:Node2D

func _initialize() -> void: call_deferred("run")

func shot(label:String) -> void:
	await process_frame
	var img:Image = root.get_texture().get_image()
	var path:String = ProjectSettings.globalize_path("user://jjk_shots/dom_%s.png" % label)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("JJK_SHOT ", path)

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(1280,960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	arena.name = "JJKDomainGallery"
	root.add_child(arena)
	current_scene = arena
	var bg:ColorRect = ColorRect.new()
	bg.size = Vector2(1280,960)
	bg.color = Color("35434b")
	bg.z_index = -10
	arena.add_child(bg)
	var gojo:Node2D = load(DIR + "五条悟.tscn").instantiate()
	gojo.Team = "A"
	gojo.position = Vector2(340,520)
	arena.add_child(gojo,true)
	var sukuna:Node2D = load(DIR + "宿傩.tscn").instantiate()
	sukuna.Team = "B"
	sukuna.position = Vector2(950,520)
	arena.add_child(sukuna,true)
	await process_frame
	await process_frame
	var uv:Node = gojo.call("open_domain","uv",Vector2(340,520),280.0,10.0)
	var shrine:Node = sukuna.call("open_domain","shrine",Vector2(950,520),0.0,10.0)
	var t:float = 0.0
	var marks:Array[float] = [0.15,0.5,1.4,2.6]
	var k:int = 0
	while k < marks.size():
		await process_frame
		t += 1.0 / 60.0
		if t > 1.0 and is_instance_valid(uv): uv.set("barrier_hp",35.0)
		if t > 2.0 and is_instance_valid(uv) and float(uv.get("flip_left")) <= 0.0 and t < 2.1: uv.call("flip")
		if t >= marks[k]:
			await shot("%03d" % int(marks[k] * 100))
			k += 1
	print("JJK_DOMAIN_OK uv=",is_instance_valid(uv)," shrine=",is_instance_valid(shrine))
	quit(0)
