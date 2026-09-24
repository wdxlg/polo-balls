extends SceneTree
## Headless, reproducible matrix for EVERY character scene on disk (including
## inherited variants), plus ball-based summoned creatures. Checks runtime
## property changes, not merely the presence of status icons or formulas.
## Non-ball objects (walls, traps, independent beams) are listed separately.
var game:Node
var world:Node
var saved:Dictionary
var catalog:GDScript
var center:Vector2
var checks:int = 0
var failures:int = 0
var scene_count:int = 0
var fighter_count:int = 0
var skipped:Array[String] = []
var immune:Array[String] = []
var finishing:bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,path:String,label:String,detail:String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("POTION_CHARACTER_FAIL " + path + " " + label + " " + detail)

func gather(folder:String,paths:Array[String]) -> void:
	for name:String in DirAccess.get_directories_at(folder):
		if not name.begins_with("."):
			gather(folder.path_join(name),paths)
	for name:String in DirAccess.get_files_at(folder):
		if name.ends_with(".tscn"):
			paths.append(folder.path_join(name))

func quoted_value(line:String,key:String) -> String:
	var marker:String = " " + key + '="'
	var start:int = line.find(marker)
	if start < 0: return ""
	start += marker.length()
	var stop:int = line.find('"',start)
	return line.substr(start,stop-start) if stop >= 0 else ""

func direct_root_script_path(scene_path:String) -> String:
	var text:String = FileAccess.get_file_as_string(scene_path)
	var root_start:int = text.find("\n[node ")
	if root_start < 0: return ""
	var root_end:int = text.find("\n[node ",root_start+1)
	var root_lines:String = text.substr(root_start,root_end-root_start if root_end >= 0 else -1)
	var script_id:String = ""
	for line:String in root_lines.split("\n"):
		if line.begins_with('script = ExtResource("'):
			script_id = line.trim_prefix('script = ExtResource("').get_slice('"',0)
			break
	if script_id.is_empty(): return ""  # Scene inherits parent's script.
	for line:String in text.split("\n"):
		if line.begins_with("[ext_resource ") and quoted_value(line,"id") == script_id:
			return quoted_value(line,"path")
	return "missing mapping for " + script_id

func unquote_git_path(line:String) -> String:
	# Windows Godot decodes git's raw UTF-8 stdout as the local code page.
	# Ask Git for its ASCII C-style octal-escaped path and decode ourselves.
	if not line.begins_with('"') or not line.ends_with('"'):
		return line
	var escaped:String = line.substr(1,line.length()-2)
	var bytes:PackedByteArray = PackedByteArray()
	var i:int = 0
	while i < escaped.length():
		var c:int = escaped.unicode_at(i)
		if c == 92 and i+1 < escaped.length():
			var next:int = escaped.unicode_at(i+1)
			if next >= 48 and next <= 55 and i+3 < escaped.length():
				var value:int = (next-48)*64 + (escaped.unicode_at(i+2)-48)*8 + escaped.unicode_at(i+3)-48
				bytes.append(value)
				i += 4
				continue
			bytes.append(10 if next == 110 else 9 if next == 116 else 13 if next == 114 else next)
			i += 2
			continue
		bytes.append(c)
		i += 1
	return bytes.get_string_from_utf8()

func tracked_scene_paths() -> Dictionary:
	# Optional CI mode: include every Git-tracked role but not work-in-progress
	# untracked character prototypes from other concurrent branches.
	var output:Array = []
	var args:PackedStringArray = PackedStringArray([
		"-C",ProjectSettings.globalize_path("res://"),
		"-c","core.quotepath=true", "ls-files","--","scenes/characters","scenes/creatures"
	])
	var exit_code:int = OS.execute("git",args,output)
	check(exit_code == 0 and not output.is_empty(),"git","tracked scene inventory available")
	var tracked:Dictionary = {}
	if output.is_empty(): return tracked
	for raw:String in str(output[0]).replace("\r","").split("\n"):
		var line:String = unquote_git_path(raw)
		if line.ends_with(".tscn"):
			tracked["res://" + line.replace("\\","/")] = true
	check(tracked.size() >= 120,"git","expected at least 120 tracked character and creature scenes, got="+str(tracked.size()))
	return tracked

func refigure(actor:Node2D) -> void:
	world.set_ball_properties_to_dafault([actor])
	world.figure_buffs(0.001,[actor])

func near(actual:float,expected:float,margin:float = 0.001) -> bool:
	return absf(actual-expected) <= margin * maxf(1.0,absf(expected))

func audit_scene(path:String) -> void:
	var packed:PackedScene = load(path) as PackedScene
	check(packed != null,path,"scene loads")
	if packed == null: return
	var node:Node = packed.instantiate()
	check(node != null,path,"scene instantiates")
	if node == null: return
	var declared_script_path:String = direct_root_script_path(path)
	if not declared_script_path.is_empty():
		var actual_script:Script = node.get_script() as Script
		check(actual_script != null and actual_script.resource_path == declared_script_path and actual_script.can_instantiate(),path,"scene root's own script compiled", "declared="+declared_script_path+" actual="+(actual_script.resource_path if actual_script != null else "none"))
	# Do not reference the global `ball` class directly in a SceneTree test:
	# preloading it before Game's autoload exists causes a circular compile.
	if not node is CharacterBody2D or not node.has_method("get_minecraft_potion_effect_ratio"):
		skipped.append(path + " (non-ball)")
		node.free()
		return
	var actor:Node2D = node as Node2D
	# Ball_Type.Ball=0 / Ball_Type.Creature=3; Shooter variants (1,2)
	# deliberately do not enter World.figure_buffs().
	if int(actor.get("Type")) not in [0,3]:
		skipped.append(path + " (non-fighter Type=" + str(actor.get("Type")) + ")")
		actor.free()
		return
	fighter_count += 1
	actor.Team = "Team0"
	actor.position = center
	world.add_child(actor,true)
	if actor.state_machine != null:
		actor.state_machine.set_physics_process(false)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.Has_Collision_Damage = false
	if actor.health <= 0:
		skipped.append(path + " (dead immediately on scene entry)")
		actor.queue_free()
		return
	# Other per-character passive Buffs can already be present after _ready().
	refigure(actor)
	var base_damage:float = float(actor.Damage)
	var base_speed:float = float(actor.Speed)
	var base_attack_cooling:float = float(actor.Attack_Cooling)
	var base_reduction:float = float(actor.Damage_reduction)
	var base_max_health:float = float(actor.Max_health)
	var positive_ratio:float = maxf(actor.get_minecraft_potion_effect_ratio(true),0.0)
	var negative_ratio:float = maxf(actor.get_minecraft_potion_effect_ratio(false),0.0)
	if positive_ratio <= 0.000001 or negative_ratio <= 0.000001:
		immune.append(path + " positive=" + str(positive_ratio) + " negative=" + str(negative_ratio))
	# These statuses enter the live ball's real Buff reset/calculation path.
	# Test positive and negative phases separately: Damage is integer-typed and
	# each of the two multiplicative Buffs rounds at its own step.
	for kind:String in ["speed","haste","strength","resistance","health_boost","absorption","fire_resistance"]:
		var installed:bool = bool(catalog.call("apply_effect",actor,kind,2,10.0))
		check(installed == (positive_ratio > 0.000001),path,kind + " applies iff target permits")
	refigure(actor)
	var positive_damage:float = float(actor.Damage)
	var positive_speed:float = float(actor.Speed)
	var positive_attack_cooling:float = float(actor.Attack_Cooling)
	if positive_ratio > 0.000001:
		var expected_speed:float = base_speed * maxf(0.0,1.0 + 0.4 * positive_ratio)
		var expected_attack:float = base_attack_cooling/maxf(1.0 + 0.2*positive_ratio,0.0001)
		var expected_damage:float = base_damage * maxf(0.0,1.0 + 0.2 * positive_ratio)
		check(near(positive_speed,expected_speed,0.005),path,"Speed II changes movement attribute",str(base_speed)+" -> "+str(positive_speed)+" expected="+str(expected_speed))
		if base_attack_cooling > 0.0:
			check(near(positive_attack_cooling,expected_attack,0.005),path,"Haste II changes attack cooldown",str(base_attack_cooling)+" -> "+str(positive_attack_cooling)+" expected="+str(expected_attack))
		check(near(positive_damage,expected_damage,0.005) or absf(positive_damage-expected_damage) <= 1.0,path,"Strength II changes attack attribute",str(base_damage)+" -> "+str(positive_damage)+" expected="+str(expected_damage))
		check(near(actor.Damage_reduction,clampf(base_reduction+0.4*positive_ratio,0.0,1.0),0.005),path,"Resistance II changes incoming reduction (capped at full immunity)",str(base_reduction)+" -> "+str(actor.Damage_reduction))
		check(near(actor.Max_health,base_max_health+40.0*positive_ratio,0.005) or absf(actor.Max_health-base_max_health-40.0*positive_ratio) <= 1.0,path,"Health Boost II changes maximum health",str(base_max_health)+" -> "+str(actor.Max_health))
		var absorption:Node = actor.get_node_or_null("MinecraftStatus_absorption")
		check(absorption != null and near(float(absorption.get("absorption_remaining")),40.0*positive_ratio,0.001),path,"Absorption II grants temporary hit points")
		check(actor.is_fire_immune() and not actor.receive_fire_spatial_damage(5.0,{"shape":"all"},true,true),path,"Fire Resistance rejects real fire damage")
	for kind:String in ["slowness","mining_fatigue","weakness"]:
		var installed:bool = bool(catalog.call("apply_effect",actor,kind,2,10.0))
		check(installed == (negative_ratio > 0.000001),path,kind + " applies iff target permits")
	refigure(actor)
	if negative_ratio > 0.000001:
		var slow_factor:float = maxf(0.0,1.0 - 0.4 * negative_ratio)
		var rate_factor:float = maxf(0.0,1.0 - 0.2 * negative_ratio)
		var weakness_factor:float = maxf(0.0,1.0 - 0.2 * negative_ratio)
		check(near(actor.Speed,positive_speed * slow_factor,0.005),path,"Slowness II changes movement attribute",str(positive_speed)+" -> "+str(actor.Speed))
		if positive_attack_cooling > 0.0:
			check(near(actor.Attack_Cooling,positive_attack_cooling/maxf(rate_factor,0.0001),0.005),path,"Mining Fatigue II changes attack cooldown",str(positive_attack_cooling)+" -> "+str(actor.Attack_Cooling))
		check(near(actor.Damage,positive_damage*weakness_factor,0.005) or absf(actor.Damage-positive_damage*weakness_factor) <= 1.0,path,"Weakness II changes attack attribute",str(positive_damage)+" -> "+str(actor.Damage))
	actor.queue_free()

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(world) and is_instance_valid(world.get("_mc_prewarmer")):
		for resource_path:Variant in world._mc_prewarmer._paths.values():
			var load_status:int = ResourceLoader.load_threaded_get_status(str(resource_path))
			if load_status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(resource_path))
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(175.0,true,false,true).timeout.connect(func():
		push_error("POTION_CHARACTER_TIMEOUT before completing all scenes")
		finish(2)
	)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3,true,false,true).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	catalog = load("res://scripts/effects/我的世界/mc_status_effects.gd") as GDScript
	var paths:Array[String] = []
	gather("res://scenes/characters",paths)
	gather("res://scenes/creatures",paths)
	paths.sort()
	var tracked_only:bool = OS.get_cmdline_user_args().has("--tracked-only")
	var tracked:Dictionary = tracked_scene_paths() if tracked_only else {}
	var limit:int = 0
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--limit="):
			limit = int(argument.trim_prefix("--limit="))
	for path:String in paths:
		if tracked_only and not tracked.has(path): continue
		if limit > 0 and scene_count >= limit: break
		scene_count += 1
		audit_scene(path)
		await process_frame
		if scene_count % 20 == 0: print("POTION_CHARACTER_PROGRESS scenes=",scene_count," fighters=",fighter_count," failures=",failures)
	if limit <= 0:
		check(scene_count >= 120 and fighter_count >= 100,"inventory","at least 120 scenes and 100 combat units were actually audited")
	else:
		check(scene_count == limit,"inventory","limited run covered the requested number of scenes")
	for skipped_path:String in skipped: print("POTION_CHARACTER_SKIP ",skipped_path)
	for immune_path:String in immune: print("POTION_CHARACTER_IMMUNE ",immune_path)
	print("POTION_CHARACTER_RESULT checks=",checks," failures=",failures," scenes=",scene_count," fighters=",fighter_count," skipped=",skipped.size()," immune=",immune.size()," tracked_only=",tracked_only," limit=",limit)
	await finish(1 if failures > 0 else 0)
