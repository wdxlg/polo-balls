extends "res://tests/benchmark_200.gd"
## 实验开关：--exp=noafterimage / minvisual / noblood / nostretch，用于定位大场面剩余开销
var exp_mode:String = ""
func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--exp="):
			exp_mode = arg.trim_prefix("--exp=")
	super._initialize()
func _before_spawn() -> void:
	var w:Node = world
	if exp_mode == "noblood":
		game.Game_Settings["Blood_Effects"] = false
	if exp_mode == "notext":
		get_tree_hook()
	if exp_mode == "minvisual":
		w.large_battle_visual_density_min = 0.15
		w.large_battle_visual_density_full_units = 41
	if exp_mode in ["noafterimage","nostretch"]:
		var RK = load("res://classes/runtime_knife_scene.gd")
		var ks:PackedScene = load("res://scenes/shooter/knife.tscn")
		var entry:Dictionary = RK.prepare(w,ks)
		var proto:Node = (entry.packed as PackedScene).instantiate()
		if exp_mode == "noafterimage":
			proto.AfterImage_Speed = -1.0
		else:
			proto.AfterImage_Mode = 0
		var packed:PackedScene = PackedScene.new()
		packed.pack(proto)
		proto.free()
		entry["packed"] = packed
		w.set_meta(RK.CACHE_KEY,entry)
		print("EXP applied ",exp_mode)
func get_tree_hook() -> void:
	node_added.connect(func(n:Node) -> void:
		if n is CharacterBody2D and n.get("health_bar") != null or (n is CharacterBody2D and n.has_method("is_large_battle_performance_mode")):
			n.ready.connect(func() -> void:
				var hb:Variant = n.get("health_bar")
				if hb != null:
					hb.suppress_floating_text = true
			,CONNECT_ONE_SHOT)
	)
