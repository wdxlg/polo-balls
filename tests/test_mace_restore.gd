extends SceneTree
var failures:int = 0
var checks:int = 0
func check(value:bool,message:String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("RESTORE_FAIL ",message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	var ball_script:Script = load("res://classes/ball.gd")
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var locale:String = game.current_locale
	game.Game_Settings.Have_Team_Damage = false
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var center:Vector2 = rect.get_center()
	var mace:Node2D = load("res://scenes/characters/我的世界/重锤.tscn").instantiate()
	mace.Team = "Team0"
	mace.position = center
	world.add_child(mace,true)
	var insects:Array[Node2D] = []
	for i:int in range(10):
		var insect:Node2D = load("res://scenes/characters/我的世界/蠹虫.tscn").instantiate()
		insect.Team = "Team1"
		insect.Max_health = 100
		insect.position = center + Vector2(i * 2,10)
		world.add_child(insect,true)
		insects.append(insect)
		check(insect.health_bar.max_live_damage_texts == 0,"silverfish full text policy")
	# Deliberately exceed the old global 80-label budget.
	for i:int in range(80):
		var placeholder:Node = Node.new()
		world.add_child(placeholder)
		placeholder.add_to_group("__damage_text_runtime")
	for count:int in [1,4,5,10]:
		for i:int in range(10):
			insects[i].position = center + (Vector2(i*2,10) if i < count else Vector2(3000+i*100,3000))
		var before:int = get_node_count_in_group("__damage_text_runtime")
		var before_sfx:int = count_damage_sfx(world)
		var previous_health:Array = []
		for insect:Node2D in insects:
			previous_health.append(insect.health)
		var result:Dictionary = mace._damage_area(center,100.0,3.0,0.0,0.0,100.0)
		check(count_damage_sfx(world) - before_sfx == count,"every victim has damage audio")
		for i:int in range(10):
			check(insects[i].health == previous_health[i] - (3 if i < count else 0),"exact health and outside-area exclusion")
		check(result.hits == count,"hits="+str(count))
		check(result.retrigger_hits == count,"retrigger="+str(count))
		check(get_node_count_in_group("__damage_text_runtime") - before == count,"one text per victim="+str(count))
		for i:int in range(count):
			check(insects[i].state_machine.current_state == ball_script.State.Hurt,"Hurt restored")
			check(not insects[i].health_bar.force_instant_update_once,"no instant suppression")
		print("RESTORE_CASE ",count," hits=",result.hits," texts=",get_node_count_in_group("__damage_text_runtime") - before)
	for i:int in range(10):
		insects[i].position = center + Vector2(i*2,10)
	var before_death:int = get_node_count_in_group("__damage_text_runtime")
	var result:Dictionary = mace._damage_area(center,100.0,1000.0,0.0,0.0)
	check(result.hits == 10,"lethal hits")
	check(get_node_count_in_group("__damage_text_runtime") - before_death == 10,"lethal texts")
	for insect:Node2D in insects:
		check(insect.health == 0,"lethal health")
		insect.state_machine.current_state = ball_script.State.Die
		check(insect._death_visual_started_local,"death starts without frame staggering")
		check(insect.death_audio.playing,"every death has audio")
	var fields:Array[Node] = get_nodes_in_group("MinecraftSilverfishStoneField")
	check(fields.size() == 1,"chunked field retained")
	if not fields.is_empty():
		var field:Node = fields[0]
		var origin:Vector2i = field._used_rect.position + Vector2i(2,2)
		for i:int in range(12):
			var coord:Vector2i = origin + Vector2i(i,0)
			field._begin_crack(coord,0,42+i)
			check(field._transition_sprites.has(coord),"stone feedback starts immediately "+str(i))
		check(field._render_chunks.size() > 0,"render cache retained")
		check(field._pending_spawn_count <= 10,"spawn reservation cap retained")
	game.Game_Settings = saved
	game.current_locale = locale
	print("MACE_RESTORE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	current_scene = null
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func count_damage_sfx(world:Node) -> int:
	var sounds:Script = load("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
	var count:int = 0
	for child:Node in world.get_children():
		if child is AudioStreamPlayer2D and child.stream in sounds.DAMAGE_SFX:
			count += 1
	return count
