extends SceneTree
## Focused real-scene regression: action order, no unattended bow AI, release/cancel.
var checks:int = 0
var failures:int = 0
var arena:Node2D
var previous:Node

func _initialize() -> void: call_deferred("run")

func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROLE_CONTROL_FAIL " + label)

func spawn(path:String,probe:String = "") -> Node2D:
	var actor:Node2D = (load(path) as PackedScene).instantiate() as Node2D
	if not probe.is_empty(): actor.set_script(load(probe))
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(actor,true)
	actor.set_physics_process(false)
	return actor

func verify_action(path:String,wanted:Array[StringName]) -> void:
	var actor:Node2D = (load(path) as PackedScene).instantiate() as Node2D
	check(actor.player_control_action_ids() == wanted,path + " maps only its real actions")
	actor.free()

func run() -> void:
	create_timer(45.0).timeout.connect(func():quit(2))
	previous = current_scene
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var one_attack:Array[StringName] = [&"controlled_attack_action"]
	verify_action("res://scenes/characters/我的世界/仙人掌.tscn",[&"Skill"])
	verify_action("res://scenes/characters/我的世界/木剑.tscn",[&"Attack"])
	verify_action("res://scenes/characters/我的世界/铜剑.tscn",one_attack)
	verify_action("res://scenes/characters/我的世界/铁砧.tscn",[&"controlled_skill_action"])
	verify_action("res://scenes/characters/我的世界/弓.tscn",one_attack)
	verify_action("res://scenes/characters/我的世界/天堂陨落长弓.tscn",one_attack)
	verify_action("res://scenes/characters/我的世界/恶魂.tscn",one_attack)
	verify_action("res://scenes/characters/我的世界/羊.tscn",one_attack)
	verify_action("res://scenes/characters/我的世界/守卫者.tscn",[&"controlled_attack_action",&"controlled_skill_action"])
	verify_action("res://scenes/characters/我的世界/钓鱼竿.tscn",[&"controlled_attack_action",&"controlled_skill_action"])
	verify_action("res://scenes/characters/我的世界/粘性活塞.tscn",one_attack)
	verify_action("res://scenes/characters/我的世界/唱片机.tscn",one_attack)
	verify_action("res://scenes/characters/我的世界/监守者.tscn",[&"Attack",&"Skill",&"begin_probe",&"begin_burrow"])
	verify_action("res://scenes/characters/meme/大狗叫.tscn",one_attack)
	verify_action("res://scenes/creatures/小狗叫.tscn",one_attack)
	verify_action("res://scenes/creatures/铁傀儡村民.tscn",[&"controlled_attack_action",&"controlled_skill_action"])
	verify_action("res://scenes/creatures/布鲁斯_狗.tscn",one_attack)
	verify_action("res://scenes/creatures/训犬师_狗.tscn",one_attack)
	verify_action("res://scenes/creatures/九头蛇_头.tscn",[])
	verify_action("res://scenes/creatures/我的世界/史莱姆_中.tscn",[])
	verify_action("res://scenes/creatures/我的世界/史莱姆_小.tscn",[])
	verify_action("res://scenes/creatures/伪军.tscn",one_attack)
	verify_action("res://scenes/creatures/唤魔恼鬼.tscn",one_attack)
	var cactus:Node2D = spawn("res://scenes/characters/我的世界/仙人掌.tscn","res://tests/manual_cactus_control_probe.gd")
	cactus.set_player_control_peer(1)
	cactus.player_control_action(0)
	cactus.player_control_action(1)
	check(cactus.manual_volleys == 1,"single cactus action fires from left, not right")
	var anvil:Node2D = spawn("res://scenes/characters/我的世界/铁砧.tscn","res://tests/manual_anvil_control_probe.gd")
	anvil.set_player_control_peer(1)
	anvil.player_control_action(0)
	anvil.player_control_action(1)
	check(anvil.manual_slams == 1,"single anvil slam fires from left, not right")
	var warden:Node2D = spawn("res://scenes/characters/我的世界/监守者.tscn","res://tests/manual_warden_control_probe.gd")
	warden.set_player_control_peer(1)
	for slot:int in range(4): warden.player_control_action(slot)
	check(warden.actions == [0,1,2,3],"Warden left/right/middle/number-one dispatch distinct existing actions")
	var piston:Node2D = spawn("res://scenes/characters/我的世界/粘性活塞.tscn")
	piston.set_player_control_peer(1)
	piston.player_control_action(0)
	check(piston._manual_extend_held,"piston starts extending only after left press")
	piston.player_control_action_released(0)
	check(not piston._manual_extend_held,"piston release stops active extension request")
	var music:Node2D = spawn("res://scenes/characters/我的世界/唱片机.tscn","res://tests/manual_note_block_control_probe.gd")
	music.set_player_control_peer(1)
	music.record_phase=2
	music.finish_ejection()
	check(music.record_phase==3 and music.started_tracks.is_empty(),"manual jukebox never auto-loads next disc")
	music.player_control_action(0)
	check(music.started_tracks.size()==1,"jukebox left-click loads next existing disc")
	music.record_phase=3
	music.set_player_control_peer(0)
	check(music.started_tracks.size()==2,"jukebox resumes original auto playback after exit")

	var bow:Node2D = spawn("res://scenes/characters/我的世界/弓.tscn","res://tests/manual_bow_control_probe.gd")
	bow.set_player_control_peer(1)
	bow.set_player_control_aim_position(bow.global_position + Vector2.RIGHT*120.0)
	bow.draw_time = 1.0
	bow.full_hold_time = 0.2
	bow._cool = 0.0
	bow.step_mob(1.5)
	check(bow.shots == 0 and bow.drawing == 0.0,"bow cannot acquire/fire merely because it is selected")
	bow.controlled_attack_action()
	bow.step_mob(0.4)
	check(bow._manual_fire_held and is_equal_approx(bow.drawing,0.4),"bow charges only while manual button is down")
	bow.player_control_action_released(0)
	check(not bow._manual_fire_held and bow.shots == 1 and is_equal_approx(bow.shot_ratio,0.4),"releasing bow fires one partial charge")
	bow._cool = 0.0
	bow.controlled_attack_action()
	bow.step_mob(0.1)
	bow.player_control_action_cancelled(0)
	check(not bow._manual_fire_held and bow.shots == 1 and bow.drawing == 0.0,"switching from bow cancels rather than firing")
	bow.controlled_attack_action()
	bow.set_player_control_peer(0)
	check(not bow._manual_fire_held,"bow cannot remain held after leaving control")

	var longbow:Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn","res://tests/manual_longbow_control_probe.gd")
	longbow.set_player_control_peer(1)
	longbow.set_player_control_aim_position(longbow.global_position + Vector2.UP*120.0)
	longbow.draw_time = 0.3
	longbow._cool = 0.0
	longbow.step_mob(0.4)
	check(longbow.shots == 0 and longbow.drawing == 0.0,"longbow does not auto fire under selected aim")
	longbow.controlled_attack_action()
	longbow.step_mob(0.4)
	check(longbow.shots == 1 and longbow._manual_fire_held,"longbow fires after a manual draw")
	longbow.player_control_action_released(0)
	longbow._cool = 0.0
	longbow.step_mob(0.5)
	check(longbow.shots == 1 and not longbow._manual_fire_held,"releasing longbow stops next shot")
	longbow.controlled_attack_action()
	longbow.player_control_action_cancelled(0)
	check(not longbow._manual_fire_held and longbow.drawing == 0.0,"longbow switch cancels charge")

	var soldier:Node2D = spawn("res://scenes/creatures/伪军.tscn")
	check(soldier.Type == 3 and soldier.manual_controllable_subentity and soldier.can_player_control() and root.get_node("Game")._can_control_candidate(soldier),"real independent soldier is C-selectable")
	var vex:Node2D = spawn("res://scenes/creatures/唤魔恼鬼.tscn")
	check(vex.Type == 3 and vex.manual_controllable_subentity and vex.can_player_control() and root.get_node("Game")._can_control_candidate(vex),"real Vex is C-selectable")
	for path:String in ["res://scenes/creatures/铁傀儡村民.tscn","res://scenes/creatures/布鲁斯_狗.tscn","res://scenes/creatures/训犬师_狗.tscn","res://scenes/creatures/九头蛇_头.tscn","res://scenes/creatures/我的世界/史莱姆_中.tscn","res://scenes/creatures/我的世界/史莱姆_小.tscn"]:
		var companion:Node2D=spawn(path)
		check(companion.manual_controllable_subentity and root.get_node("Game")._can_control_candidate(companion),path+" really passes C selector")
	var big_dog:Node2D=spawn("res://scenes/characters/meme/大狗叫.tscn")
	var puppy:Node2D=big_dog.get_node("小狗叫")
	check(root.get_node("Game")._can_control_candidate(big_dog),"big barking dog is C-selectable")
	check(puppy.manual_controllable_subentity and puppy.is_in_group("ManualControlSubentity") and not puppy.is_in_group("Ball") and root.get_node("Game")._can_control_candidate(puppy),"untargetable puppy is C-selectable without joining combat scans")
	current_scene = previous
	arena.queue_free()
	print("ROLE_CONTROL_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
