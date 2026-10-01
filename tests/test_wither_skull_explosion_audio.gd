extends "res://scripts/training/test_mc_new5.gd"
## Real World: Wither skull impacts and awakening blast use the vanilla generic explosion sound.
var heard:Array[AudioStreamPlayer2D] = []
func _record(node:Node) -> void:
	if node is AudioStreamPlayer2D: heard.append(node)
func explosion_players() -> Array[AudioStreamPlayer2D]:
	var found:Array[AudioStreamPlayer2D] = []
	for player:AudioStreamPlayer2D in heard:
		if is_instance_valid(player) and str(player.get_meta("mc_sound_event","")) == "entity.generic.explode": found.append(player)
	return found
func old_explosion_count(sounds:GDScript) -> int:
	var count:int = 0
	for player:AudioStreamPlayer2D in heard:
		if is_instance_valid(player) and player.stream == sounds.STREAMS["explode"] and not player.has_meta("mc_sound_event"): count += 1
	return count
func settle() -> void:
	await process_frame
	await physics_frame
	await process_frame
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var sounds:GDScript = load("res://scripts/characters/我的世界/wither/audio.gd")
	var generic:GDScript = load("res://scripts/characters/我的世界/new5/audio.gd")
	var variants:Array = []
	for record:Dictionary in generic.EVENTS["entity.generic.explode"]: variants.append(record["stream"])
	var wither:Node2D = spawn("凋灵",Vector2.ZERO,"Team0")
	var enemy:Node2D = spawn("",Vector2(160,0),"Team1")
	enemy.Max_health = 100000
	enemy.health = 100000
	await settle()
	world.child_entered_tree.connect(_record)
	heard.clear()
	var skull:Node2D = load("res://scripts/characters/我的世界/wither/skull.gd").new()
	world.add_child(skull,true)
	skull.global_position = enemy.global_position-Vector2(80,0)
	skull.configure(wither,Vector2.RIGHT)
	skull._physics_process(0.5)
	var exploded:bool = skull.exploded
	var impact:Vector2 = skull.global_position
	await settle()
	var booms:Array[AudioStreamPlayer2D] = explosion_players()
	check(exploded and booms.size() == 1,"one real skull impact plays exactly one vanilla explosion sound")
	check(old_explosion_count(sounds) == 0,"the single legacy explode clip no longer plays alongside it")
	if not booms.is_empty():
		var boom:AudioStreamPlayer2D = booms[0]
		check(variants.has(boom.stream),"skull explosion uses one of the four entity.generic.explode variants")
		check(boom.pitch_scale >= 0.56-0.0001 and boom.pitch_scale <= 0.84+0.0001,"pitch follows vanilla (1+(r1-r2)*0.2)*0.7, got "+str(boom.pitch_scale))
		check(boom.playing and boom.global_position.distance_to(enemy.global_position) < 40.0 and boom.global_position.x > impact.x,"explosion plays where the skull struck the target")
		check(boom.bus == &"GameplayRecord" or AudioServer.get_bus_index(&"GameplayRecord") < 0,"explosion is routed to the gameplay recording bus")
		check(boom.volume_db >= 0.0 and boom.max_distance >= 1800.0,"explosion is loud and carries across the arena")
		var choice:Dictionary = sounds.explosion_choice(boom.global_position)
		check(choice.stream == boom.stream and is_equal_approx(choice.pitch,boom.pitch_scale),"variant and pitch derive from the blast point so every peer hears the same sound")
	if is_instance_valid(skull): skull.free()
	var picked:Dictionary = {}
	var pitch_min:float = 9.0
	var pitch_max:float = 0.0
	for i:int in 64:
		var c:Dictionary = sounds.explosion_choice(Vector2(i*37.5,i*-13.25))
		picked[c.stream] = true
		pitch_min = minf(pitch_min,c.pitch)
		pitch_max = maxf(pitch_max,c.pitch)
	check(picked.size() == 4 and pitch_min >= 0.56 and pitch_max <= 0.84 and pitch_max-pitch_min > 0.1,"different blasts spread over all four variants and the vanilla pitch range")
	for player:AudioStreamPlayer2D in heard:
		if is_instance_valid(player): player.free()
	heard.clear()
	wither._sync_event("explode",wither.global_position+Vector2(0,30))
	await settle()
	check(explosion_players().size() == 1 and old_explosion_count(sounds) == 0,"client explode event plays the same vanilla explosion sound")
	heard.clear()
	wither._sync_event("skull_blast",wither.global_position+Vector2(0,60))
	await settle()
	check(explosion_players().is_empty(),"client skull_blast visual stays silent so the explode event is never doubled")
	world.child_entered_tree.disconnect(_record)
	await clear_units()
	finish(0 if failures == 0 else 1)
