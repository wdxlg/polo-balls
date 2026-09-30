extends SceneTree
## 咒术回战实战招式逐帧胶片（需要 GPU）：真实角色释放招式（含角色身上的持续特效、飞行弹、召唤物），
## 连续多帧截图到 user://jjk_shots/strip/<label>_<i>.png，用来检查特效是否在动、是否精致。看完即删。
## godot --path . --audio-driver Dummy --resolution 1280x720 --script res://tests/test_jjk_moves_strip.gd
## 环境变量 JJK_STRIP=label1,label2 只跑指定条目。
const DIR:String = "res://scenes/characters/动漫/"
const C:Vector2 = Vector2(640,360)
var arena:Node2D
var gojo:Node2D
var sukuna:Node2D

func _initialize() -> void: call_deferred("run")

func shot(label:String) -> void:
	await process_frame
	var img:Image = root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("user://jjk_shots/strip/%s.png" % label))

func _setup() -> void:
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	arena = Node2D.new()
	arena.name = "JJKMovesStrip"
	root.add_child(arena)
	current_scene = arena
	var tile:int = 64
	for y:int in range(0,720,tile):
		for x:int in range(0,1280,tile):
			var r:ColorRect = ColorRect.new()
			r.position = Vector2(x,y)
			r.size = Vector2(tile,tile)
			r.color = Color("3d4b45") if ((x / tile) + (y / tile)) % 2 == 0 else Color("46554e")
			r.z_index = -10
			arena.add_child(r)
	gojo = load(DIR + "五条悟.tscn").instantiate()
	gojo.Team = "A"
	gojo.position = C + Vector2(-190,0)
	gojo.set("_ai_think",10.0)
	arena.add_child(gojo,true)
	sukuna = load(DIR + "宿傩.tscn").instantiate()
	sukuna.Team = "B"
	sukuna.position = C + Vector2(190,0)
	sukuna.set("_ai_think",10.0)
	arena.add_child(sukuna,true)
	for i:int in 3:
		_hold()
		await process_frame

func _hold() -> void:
	for u:Node in get_nodes_in_group("JJKUnit"):
		u.set("_ai_think",10.0)
		if u.get("cursed_energy_max") != null: u.set("cursed_energy",float(u.get("cursed_energy_max")))
		if u is RigidBody2D: (u as RigidBody2D).linear_velocity = Vector2.ZERO
		elif u.get("velocity") != null: u.set("velocity",Vector2.ZERO)

func _act(label:String,t:float,done:Dictionary) -> void:
	var g:Object = gojo
	var s:Object = sukuna
	var L:Vector2 = Vector2.LEFT
	var R:Vector2 = Vector2.RIGHT
	match label:
		"blue": if not done.get(0,false): done[0] = g.call("cast_blue",C + Vector2(-60,0))
		"red":
			if not done.get(0,false):
				done[0] = g.call("begin_red_charge")
				done["t0"] = t
			if done.get(0,false) and t - float(done["t0"]) >= 0.8 and not done.has(1): done[1] = g.call("release_red",R,0.8)
		"purple":
			if not done.get(0,false):
				done[0] = g.call("begin_purple_charge")
				done["t0"] = t
			if done.get(0,false) and t - float(done["t0"]) >= 2.5 and not done.has(1): done[1] = g.call("release_purple",R,2.5)
		"teleport": if t >= 0.1 and not done.get(0,false): done[0] = g.call("teleport_to",C + Vector2(-60,-80))
		"dismantle": if not done.get(0,false): done[0] = s.call("cast_dismantle",L)
		"cleave":
			if not done.get(0,false):
				gojo.global_position = s.global_position + Vector2(-110,0)
				done[0] = s.call("cast_cleave",gojo.global_position)
		"web": if not done.get(0,false): done[0] = s.call("cast_web",gojo.global_position)
		"fuga": if not done.get(0,false): done[0] = s.call("cast_fuga",L)
		"world": if not done.get(0,false): done[0] = s.call("begin_world_slash",L,true)
		"maho": if not done.get(0,false): done[0] = s.call("summon_mahoraga")
		"agito": if not done.get(0,false): done[0] = s.call("summon_agito")

func run() -> void:
	create_timer(300.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://jjk_shots/strip"))
	# [标签, 开始截图时刻, 间隔, 张数]
	var specs:Array = [
		["idle",0.3,0.07,8],["blue",0.05,0.07,12],["red",0.1,0.1,14],["purple",0.3,0.25,14],["teleport",0.08,0.04,8],
		["dismantle",0.02,0.04,8],["cleave",0.02,0.05,8],["web",0.03,0.07,8],["fuga",0.05,0.08,14],["world",0.12,0.14,16],
		["maho",0.6,0.08,10],["agito",0.6,0.08,10],
	]
	var only:String = OS.get_environment("JJK_STRIP")
	for spec:Array in specs:
		var label:String = spec[0]
		if not only.is_empty() and not (label in only.split(",")): continue
		await _setup()
		var done:Dictionary = {}
		var t:float = 0.0
		var i:int = 0
		var next:float = float(spec[1])
		while i < int(spec[3]):
			_hold()
			_act(label,t,done)
			await process_frame
			t += 1.0 / 60.0
			if t >= next:
				await shot("%s_%02d" % [label,i])
				i += 1
				next += float(spec[2])
		print("JJK_STRIP ",label," frames=",i," acts=",done)
	quit(0)
