extends SceneTree
## 咒术回战实机截图（需要 GPU）：
## godot --path . --audio-driver Dummy --rendering-method gl_compatibility --resolution 800x600 --script res://tests/test_jjk_gpu.gd
const DIR:String = "res://scenes/characters/动漫/"
var arena:Node2D

func _initialize() -> void: call_deferred("run")

func shot(label:String) -> void:
	await process_frame
	await process_frame
	var img:Image = root.get_texture().get_image()
	var path:String = ProjectSettings.globalize_path("user://jjk_shots/shot_%s.png" % label)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("JJK_SHOT ", path)

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(800,600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	arena.name = "JJKGpu"
	root.add_child(arena)
	current_scene = arena
	var bg:ColorRect = ColorRect.new()
	bg.size = Vector2(800,600)
	bg.color = Color("35434b")
	bg.z_index = -10
	arena.add_child(bg)
	var names:Array[String] = ["五条悟.tscn","宿傩.tscn","魔虚罗.tscn","嵌合暗兽.tscn"]
	var units:Array = []
	for i:int in names.size():
		var u:Node2D = load(DIR + names[i]).instantiate()
		u.Team = "A" if i == 0 else "B"
		u.position = Vector2(160 + i * 160,300)
		arena.add_child(u,true)
		units.append(u)
	await shot("lineup")
	# 让双方 AI 自由开打，按时间截几张。
	var t:float = 0.0
	var marks:Array[float] = [1.5,3.0,5.0,8.0]
	var k:int = 0
	while k < marks.size():
		await physics_frame
		t += 1.0 / 60.0
		if t >= marks[k]:
			await shot("t%d" % int(marks[k] * 10))
			k += 1
	quit(0)
