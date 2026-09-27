extends SceneTree
## 咒术回战特效图鉴（需要 GPU）：把 jjk_fx 的全部种类排成网格，在不同进度截图。
## godot --path . --audio-driver Dummy --rendering-method gl_compatibility --resolution 1280x960 --script res://tests/test_jjk_fx_gallery.gd
var arena:Node2D

func _initialize() -> void: call_deferred("run")

func shot(label:String) -> void:
	await process_frame
	var img:Image = root.get_texture().get_image()
	var path:String = ProjectSettings.globalize_path("res://.backups/jjk_20260928/fx_%s.png" % label)
	img.save_png(path)
	print("JJK_SHOT ", path)

func cell(i:int) -> Vector2:
	return Vector2(160 + (i % 4) * 320,150 + (i / 4) * 230)

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(1280,960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	arena.name = "JJKFxGallery"
	root.add_child(arena)
	current_scene = arena
	var bg:ColorRect = ColorRect.new()
	bg.size = Vector2(1280,960)
	bg.color = Color("35434b")
	bg.z_index = -10
	arena.add_child(bg)
	var specs:Array = [
		["ripple",{"radius":24.0},0.35],
		["red_burst",{"radius":80.0},0.35],
		["purple_beam",{"a":Vector2(-140,0),"b":Vector2(140,0),"width":60.0},0.9],
		["slash",{"a":Vector2(-90,40),"b":Vector2(90,-40),"color":Color(1,0.9,0.9),"width":3.0},0.3],
		["cleave",{"radius":34.0},0.35],
		["web",{"radius":100.0},0.6],
		["fuga_burst",{"radius":90.0},0.8],
		["world_slash",{"a":Vector2(-150,60),"b":Vector2(150,-60),"width":70.0},0.9],
		["black_flash",{"radius":60.0},0.45],
		["heal",{"radius":30.0},0.6],
		["thunder",{"radius":60.0},0.45],
		["teleport",{"a":Vector2(-110,0),"b":Vector2(110,0)},0.3],
		["wheel_turn",{"radius":22.0},0.6],
		["shockwave",{"radius":90.0,"color":Color(0.3,0.5,1.0)},0.5],
		["text",{"text":"领域展开 无量空处","size":34,"color":Color(0.75,0.9,1.0)},2.0],
		["text",{"text":"黑闪","size":26,"color":Color(1.0,0.2,0.25)},0.9],
	]
	var FX:GDScript = load("res://scripts/characters/动漫/咒术回战/jjk_fx.gd")
	var host:Node2D = Node2D.new()
	arena.add_child(host)
	for i:int in specs.size():
		var d:Dictionary = (specs[i][1] as Dictionary).duplicate()
		var c:Vector2 = cell(i)
		d["pos"] = c
		d["seed"] = 1000 + i
		if d.has("a"): d["a"] = c + d["a"]
		if d.has("b"): d["b"] = c + d["b"]
		FX.spawn(host,specs[i][0],d,specs[i][2])
		var lab:Label = Label.new()
		lab.text = specs[i][0]
		lab.position = c + Vector2(-150,-110)
		lab.z_index = 100
		arena.add_child(lab)
	var t:float = 0.0
	var marks:Array[float] = [0.06,0.15,0.3,0.5]
	var k:int = 0
	while k < marks.size():
		await process_frame
		t += 1.0 / 60.0
		if t >= marks[k]:
			await shot("%02d" % int(marks[k] * 100))
			k += 1
	quit(0)
