extends "res://tests/test_diamond_spear.gd"
var saved_settings:Dictionary
var saved_stop:bool
func impact_players() -> Array[Node]:
	var found:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if not node.is_queued_for_deletion() and node.get_meta("mc_damage_source",-1)==spear.get_instance_id(): found.append(node)
	return found
func clear_impacts() -> void:
	for node:Node in impact_players(): node.free()
func hit_for(amount:int,starting_hp:int=10000) -> Array[Node]:
	clear_impacts()
	enemy.health = starting_hp
	enemy.block = 0
	enemy.Damage_reduction = 0.0
	spear.Damage = amount
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	return impact_players()
func validate_sound(players:Array[Node],event:String,actual:float,label:String) -> void:
	check(players.size()==1,label+" creates exactly one impact")
	if players.is_empty(): return
	var player:AudioStreamPlayer2D = players[0]
	check(player.get_meta("mc_sound_event","")==event,label+" correct event")
	check(absf(player.volume_db-spear.HIT_GAIN.damage_gain(actual))<0.0001 and player.volume_db>=0.0,label+" default-level baseline plus positive damage gain")
	check(player.global_position.distance_to(enemy.global_position)<0.001,label+" audio at victim")
	var native:bool = false
	for item:Dictionary in spear.MC_HIT_AUDIO.EVENTS[event]:
		if player.stream==item.stream: native = true
	check(native,label+" uses existing original MC sound variants")
func run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("DIAMOND_AUDIO_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	spear = load("res://scenes/characters/我的世界/钻石长矛.tscn").instantiate()
	spear.Team = "Team0"
	spear.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(spear)
	enemy = victim(Vector2(21,0))
	await physics_frame
	await physics_frame
	reset(Vector2.ZERO,180.0)
	check(spear.HIT_GAIN.damage_gain(0.0)==0.0,"zero-damage baseline is untouched 0 dB")
	validate_sound(hit_for(1),"entity.player.hurt",1.0,"one damage")
	var low:float = impact_players()[0].volume_db
	validate_sound(hit_for(50),"entity.player.hurt",50.0,"exactly fifty damage")
	var fifty:float = impact_players()[0].volume_db
	validate_sound(hit_for(51),"entity.player.attack.crit",51.0,"fifty-one damage")
	var fifty_one:float = impact_players()[0].volume_db
	validate_sound(hit_for(150),"entity.player.attack.crit",150.0,"high damage")
	check(low<fifty and fifty<fifty_one and fifty_one<impact_players()[0].volume_db,"actual playback gain increases across threshold and above it")
	validate_sound(hit_for(150,20),"entity.player.hurt",20.0,"overkill uses actual HP removed")
	enemy.health = 10000
	enemy.max_block = 1000
	enemy.block = 1000
	clear_impacts()
	spear.Damage = 26
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	check(enemy.health==10000 and impact_players().is_empty(),"full block without HP loss emits no hurt or crit")
	enemy.block = 0
	clear_impacts()
	spear.damage_segment(Vector2(-100,100),Vector2(-90,100),3.0,1.0,{},0.0)
	check(impact_players().is_empty(),"miss emits no impact")
	var hits:Dictionary = {}
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,hits,0.0)
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,hits,0.0)
	check(impact_players().size()==1,"deduplicated contact cannot double-play impact")
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	check(impact_players().size()==2,"independent rapid hits are not swallowed by debounce")
	clear_impacts()
	enemy.Team = "Team0"
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	check(impact_players().is_empty(),"friendly target emits no outgoing impact")
	enemy.Team = "Team1"
	game.now_stop_state = true
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	check(impact_players().is_empty(),"pause cannot emit damage sounds")
	game.now_stop_state = false
	# Echoes share their caster's actual-damage path even after it moves away.
	reset(Vector2.ZERO,420.0)
	spear.Damage = 26
	enemy.global_position = Vector2(21,6)
	spear._emit_echo(Vector2(0,6),Vector2.RIGHT,0.44,true,1.0)
	var echo:Node2D = spear._visual_nodes.back()
	spear.global_position = Vector2(100,100)
	echo._physics_process(0.10)
	validate_sound(impact_players(),"entity.player.hurt",26.0,"stationary attack echo")
	clear_impacts()
	reset()
	enemy.global_position = Vector2(0,15)
	spear.Damage = 70
	check(spear._begin_sweep(enemy),"sweep fixture starts")
	spear._tick_action(spear.sweep_duration*0.5)
	check(not impact_players().is_empty() and impact_players()[0].get_meta("mc_sound_event","")=="entity.player.attack.crit","rotation sweep gets its own actual-damage crit")
	clear_impacts()
	reset()
	enemy.global_position = Vector2(80,0)
	await physics_frame
	await physics_frame
	check(spear._begin_blink(enemy),"blink fixture starts")
	spear._tick_action(spear.blink_windup)
	check(not impact_players().is_empty() and impact_players()[0].get_meta("mc_sound_event","")=="entity.player.attack.crit","blink path gets its own actual-damage crit")
	clear_impacts()
	arena.queue_free()
	await process_frame
	game.Game_Settings = saved_settings
	game.now_stop_state = saved_stop
	print("DIAMOND_AUDIO_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
