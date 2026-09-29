extends SceneTree
## 咒术回战特效逐帧胶片（需要 GPU）：每种特效单独播放，按特效自身时间在多个时刻截图，
## 输出到用户数据目录 user://jjk_shots/strip/，看完即删。
## godot --path . --audio-driver Dummy --resolution 1280x720 --script res://tests/test_jjk_fx_strip.gd
## 环境变量 JJK_STRIP=label1,label2 只跑指定条目。
var arena:Node2D
var host:Node2D
const C:Vector2 = Vector2(640,360)

func _initialize() -> void: call_deferred("run")

func shot(label:String) -> void:
	await process_frame
	var img:Image = root.get_texture().get_image()
	var path:String = ProjectSettings.globalize_path("user://jjk_shots/strip/%s.png" % label)
	img.save_png(path)

func _bg() -> void:
	var tile:int = 64
	for y:int in range(0,720,tile):
		for x:int in range(0,1280,tile):
			var r:ColorRect = ColorRect.new()
			r.position = Vector2(x,y)
			r.size = Vector2(tile,tile)
			r.color = Color("3d4b45") if ((x / tile) + (y / tile)) % 2 == 0 else Color("46554e")
			r.z_index = -10
			arena.add_child(r)
	# 角色尺寸参照（与实战同大小的头像）
	for f:Array in [["五条悟",Vector2(-120,60)],["宿傩",Vector2(120,60)]]:
		var s:Sprite2D = Sprite2D.new()
		var path:String = "res://Images/characters/动漫/咒术回战/%s_face.png" % f[0]
		if ResourceLoader.exists(path):
			s.texture = load(path)
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.scale = Vector2.ONE * 34.0 / maxf(s.texture.get_width(),1.0)
			s.position = C + f[1]
			s.z_index = 0
			arena.add_child(s)

func run() -> void:
	create_timer(240.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://jjk_shots/strip"))
	arena = Node2D.new()
	arena.name = "JJKFxStrip"
	root.add_child(arena)
	current_scene = arena
	_bg()
	host = Node2D.new()
	arena.add_child(host)
	var specs:Array = [
		["ripple","ripple",{"radius":24.0},0.45,[0.04,0.1,0.18,0.28,0.4]],
		["red","red_burst",{"radius":80.0},0.35,[0.03,0.08,0.16,0.28,0.45,0.65]],
		["purple","purple_beam",{"a":Vector2(-560,0),"b":Vector2(760,0),"width":60.0},0.6,[0.03,0.1,0.2,0.32,0.5,0.7,0.9]],
		["purple200","purple_beam",{"a":Vector2(-560,0),"b":Vector2(760,0),"width":120.0},0.9,[0.03,0.1,0.2,0.32,0.5,0.7,0.9]],
		["slash","slash",{"a":Vector2(-90,40),"b":Vector2(90,-40),"color":Color(1,0.9,0.9),"width":3.0},0.3,[0.02,0.05,0.1,0.18,0.28,0.38]],
		["cleave","cleave",{"radius":34.0},0.35,[0.03,0.08,0.15,0.25,0.4,0.6]],
		["web","web",{"radius":150.0},0.6,[0.04,0.12,0.25,0.45,0.7]],
		["fuga","fuga_burst",{"radius":130.0},0.8,[0.03,0.1,0.22,0.4,0.7,1.0,1.3]],
		["world","world_slash",{"a":Vector2(-800,300),"b":Vector2(800,-300),"width":70.0},0.9,[0.02,0.06,0.15,0.3,0.55,0.8,1.1]],
		["bf","black_flash",{"radius":70.0},0.45,[0.02,0.06,0.12,0.2,0.35,0.55]],
		["thunder","thunder",{"radius":60.0},0.45,[0.02,0.1,0.2,0.35,0.5,0.7]],
		["teleport","teleport",{"a":Vector2(-150,0),"b":Vector2(150,0)},0.3,[0.02,0.08,0.15,0.25,0.4]],
		["wheel","wheel_turn",{"radius":22.0},0.6,[0.05,0.2,0.35,0.5,0.7]],
		["shock","shockwave",{"radius":120.0,"color":Color(0.3,0.5,1.0)},0.5,[0.03,0.1,0.2,0.35,0.5]],
		["shockdark","shockwave",{"radius":200.0,"color":Color(0.1,0.02,0.15)},0.5,[0.03,0.1,0.2,0.35,0.5]],
		["heal","heal",{"radius":30.0},0.6,[0.05,0.15,0.3,0.45]],
	]
	var only:String = OS.get_environment("JJK_STRIP")
	var FX:GDScript = load("res://scripts/characters/动漫/咒术回战/jjk_fx.gd")
	for spec:Array in specs:
		if not only.is_empty() and not (spec[0] in only.split(",")): continue
		for ch:Node in host.get_children(): ch.queue_free()
		for ch2:Node in arena.get_children():
			if ch2.name.begins_with("JJK") or ch2 is CanvasLayer: ch2.queue_free()
		for i0:int in 50: await process_frame
		var d:Dictionary = (spec[2] as Dictionary).duplicate()
		d["pos"] = C
		d["seed"] = 4242
		if d.has("a"): d["a"] = C + d["a"]
		if d.has("b"): d["b"] = C + d["b"]
		var fx:Node2D = FX.spawn(host,spec[1],d,spec[3])
		var marks:Array = spec[4]
		var k:int = 0
		var guard:int = 0
		while k < marks.size() and guard < 600:
			guard += 1
			await process_frame
			if not is_instance_valid(fx): break
			if float(fx.get("t")) >= float(marks[k]):
				await shot("%s_%d" % [spec[0],k])
				k += 1
		print("JJK_STRIP ",spec[0]," frames=",k)
	quit(0)
