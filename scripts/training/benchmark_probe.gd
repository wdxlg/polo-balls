extends "res://scripts/training/benchmark_100.gd"
## Diagnostic-only isolation. Never referenced by the normal game.
var probe:String = "replication"
var touched:int = 0
func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe="):
			probe = arg.trim_prefix("--probe=")
	super._initialize()
var pooled_audio:AudioStream
func _run() -> void:
	if probe in ["audio_pool","combined"]:
		var player:AudioStreamPlayer = root.get_node("Audios/Sfx/KnifeThrow1")
		pooled_audio = load("res://classes/prewarmed_audio_stream.gd").new()
		pooled_audio.configure(player.stream,100)
		player.stream = pooled_audio
	node_added.connect(_probe_node)
	await super._run()
	if probe == "stages":
		for path:String in ["res://scripts/training/character_stage_probe.gd","res://scripts/training/knife_stage_probe.gd"]:
			load(path).profile_us.clear()
			load(path).profile_calls.clear()
	var api:MultiplayerAPI = world.get_multiplayer()
	print("PROBE ",probe," touched=",touched," has_peer=",api.has_multiplayer_peer()," peer_type=",api.multiplayer_peer.get_class() if api.multiplayer_peer else "null")
func _probe_node(node:Node) -> void:
	if probe in ["fresh","combined"]:
		if node.has_method("get_battle_units_fast"):
			node.ready.connect(_install_fresh.bind(node),CONNECT_ONE_SHOT)
		elif node.get_script() != null and node.get_script().resource_path == "res://scripts/training/character_fresh_probe.gd":
			node.scene_file_path = "res://scenes/characters/杀戮尖塔/小刀猎.tscn"
			touched += 1
	if probe == "native_rid" and node.get_script() != null and node.get_script().resource_path == "res://scripts/characters/杀戮尖塔/小刀猎.gd":
		node.set("knife",load("res://scenes/training/knife_native_rid_probe.tscn"))
		touched += 1
	if probe == "native" and node.get_script() != null and node.get_script().resource_path == "res://scripts/characters/杀戮尖塔/小刀猎.gd":
		node.set("knife",load("res://scenes/training/knife_native_probe.tscn"))
		touched += 1
	if probe == "gpu_hits" and node.get_script() != null and node.get_script().resource_path == "res://scripts/effects/hit_burst_effect.gd":
		var values:Dictionary = {}
		for key:String in ["_origin","_streaks","_elapsed","_end_time","_use_real_time","_start_ticks_usec"]:
			values[key] = node.get(key)
		node.set_script(load("res://scripts/training/hit_burst_gpu_probe.gd"))
		for key:String in values:
			node.set(key,values[key])
		touched += 1
	if probe == "stages":
		if node.has_method("get_battle_units_fast"):
			node.ready.connect(_install_stages.bind(node),CONNECT_ONE_SHOT)
		elif node.get_script() != null and node.get_script().resource_path == "res://scripts/training/character_stage_probe.gd":
			node.scene_file_path = "res://scenes/characters/杀戮尖塔/小刀猎.tscn"
			touched += 1
	if probe == "batch" and node.get_script() != null and node.get_script().resource_path == "res://scripts/characters/杀戮尖塔/小刀猎.gd":
		node.set("knife",load("res://scenes/training/knife_batch_probe.tscn"))
		touched += 1
	if probe == "replication" and node is MultiplayerSynchronizer:
		node.replication_config = null
		node.process_mode = Node.PROCESS_MODE_DISABLED
		touched += 1
	if node.has_method("_process_auto_after_image"):
		if probe == "trails":
			node.set("AfterImage_Speed",0.0)
			touched += 1
		elif probe == "no_attacks":
			node.set("Can_Attack",false)
			touched += 1

func _finish() -> void:
	if probe in ["fresh","combined"] and world.has_meta("_fresh_knife_supply"):
		var supply:RefCounted = world.get_meta("_fresh_knife_supply")
		print("FRESH_SUPPLY hits=",supply.hits," misses=",supply.misses," available=",supply.count())
	if probe in ["native_rid","combined"] and world.has_meta("_native_knife_snapshot_factory"):
		print("NATIVE_RID_SPAWNED ",world.get_meta("_native_knife_snapshot_factory").get_rid_spawned())
	if probe == "native" and world.has_meta("_native_knife_snapshot_factory"):
		print("NATIVE_SPAWNED ",world.get_meta("_native_knife_snapshot_factory").get_spawned())
	if pooled_audio != null:
		print("AUDIO_POOL hits=",pooled_audio.hits," misses=",pooled_audio.misses," size=",pooled_audio.pool.size())
	if probe == "stages":
		for path:String in ["res://scripts/training/character_stage_probe.gd","res://scripts/training/knife_stage_probe.gd"]:
			print("STAGE_PROFILE ",path," ",JSON.stringify({"us":load(path).profile_us,"calls":load(path).profile_calls}))
	super._finish()

func _install_stages(w:Node) -> void:
	var scene:PackedScene = load("res://scenes/training/character_stage_probe.tscn")
	w.Characters_Dic["小刀猎"] = scene
	w._character_scene_cache["res://scenes/characters/杀戮尖塔/小刀猎.tscn"] = scene

func _install_fresh(w:Node) -> void:
	var scene:PackedScene = load("res://scenes/training/character_fresh_probe.tscn")
	w.Characters_Dic["小刀猎"] = scene
	w._character_scene_cache["res://scenes/characters/杀戮尖塔/小刀猎.tscn"] = scene
	var supply:RefCounted = load("res://classes/fresh_scene_supply.gd").new()
	if probe == "combined":
		GDExtensionManager.load_extension("res://.performance_tools/native/knife_native.gdextension")
		supply.start(load("res://scenes/training/knife_native_rid_probe.tscn"),128)
	else:
		supply.start(load("res://scenes/shooter/knife.tscn"),128)
	w.set_meta("_fresh_knife_supply",supply)
	w.tree_exiting.connect(supply.close,CONNECT_ONE_SHOT)
