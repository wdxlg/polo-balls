extends "res://tests/test_iron_golem_pair.gd"
func hit_players(source:Node2D) -> Array[AudioStreamPlayer2D]:
	var result:Array[AudioStreamPlayer2D] = []
	for node:Node in arena.get_children():
		if node is AudioStreamPlayer2D and int(node.get_meta("mc_damage_source",0))==source.get_instance_id(): result.append(node)
	return result
func clear_hit_players(source:Node2D) -> void:
	for player:AudioStreamPlayer2D in hit_players(source): player.free()
func run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("GOLEM_HIT_AUDIO_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var g:Node2D = golem(Vector2.ZERO)
	var v:Node2D = g.companion
	v.global_position = Vector2(500,0)
	var target:Node2D = enemy(Vector2(30,0))
	g.set_character_visual_flip_h(true)
	var previous_gain:float = -1.0
	for amount:int in [1,48,50,51,72,100,1000]:
		clear_hit_players(g)
		clear_control(target)
		target.health = 10000
		g.Damage = amount
		g.resolve_upswing()
		var players:Array[AudioStreamPlayer2D] = hit_players(g)
		check(players.size()==1,"one real upswing hit produces one damage sound at "+str(amount))
		if players.is_empty(): continue
		var event:String = str(players[0].get_meta("mc_sound_event"))
		check(event==("entity.player.attack.crit" if amount>50 else "entity.player.hurt"),"correct hurt/crit threshold at "+str(amount))
		check(players[0].volume_db>=0 and players[0].volume_db>previous_gain and players[0].volume_db<=6,"default-or-louder, increasing actual playback gain at "+str(amount))
		previous_gain = players[0].volume_db
		check(players[0].stream!=null and players[0].stream.resource_path.ends_with(".ogg"),"hit uses existing native OGG stream")
	clear_hit_players(g)
	clear_control(target)
	g.Damage = 100
	target.health = 10000
	target.Damage_reduction = 0.6
	g.resolve_upswing()
	check(hit_players(g).size()==1 and hit_players(g)[0].get_meta("mc_sound_event")=="entity.player.hurt","reduced actual damage below 50 selects hurt instead of nominal crit")
	check(is_equal_approx(hit_players(g)[0].volume_db,g.mc_outgoing_impact_volume(40.0)),"playback gain uses post-reduction health loss")
	clear_hit_players(g)
	clear_control(target)
	target.Damage_reduction = 0.0
	target.max_block = 1000
	target.block = 1000
	g.resolve_upswing()
	check(hit_players(g).is_empty(),"pure armor absorption produces no health-damage sound")
	target.block = 0
	target.Damage_reduction = 1.0
	g.resolve_upswing()
	check(hit_players(g).is_empty(),"zero actual damage is silent")
	target.Damage_reduction = 0.0
	target.health = 10
	g.resolve_upswing()
	check(hit_players(g).size()==1 and hit_players(g)[0].get_meta("mc_sound_event")=="entity.player.hurt","overkill uses only remaining life lost for sound threshold")
	target.health = 10000
	clear_hit_players(g)
	g.Damage = 48
	g.resolve_upswing()
	g.resolve_upswing()
	check(hit_players(g).size()==2,"independent same-frame hits are not swallowed by audio debounce")
	clear_hit_players(g)
	game.now_stop_state = true
	g.resolve_upswing()
	check(hit_players(g).is_empty(),"paused combat produces no damage sound")
	game.now_stop_state = false
	g.set_multiplayer_authority(2)
	g.resolve_upswing()
	check(hit_players(g).is_empty(),"remote replica does not double-settle damage sounds")
	g.set_multiplayer_authority(1)
	clear_control(target)
	g.Damage = 48
	g.enraged = true
	g.resolve_upswing()
	check(hit_players(g).size()==1 and hit_players(g)[0].get_meta("mc_sound_event")=="entity.player.attack.crit","rage's 72 damage uses native critical hit sound")
	clear_hit_players(g)
	g.health = 0
	v.global_position = Vector2.ZERO
	target.global_position = Vector2(80,0)
	target.health = 10000
	clear_control(target)
	for amount:int in [50,70]:
		clear_hit_players(v)
		v.launch_iron(Vector2.RIGHT)
		var shot:Node2D = get_nodes_in_group("GolemIronProjectile").back()
		shot.damage = amount
		shot.advance(0.4)
		var players:Array[AudioStreamPlayer2D] = hit_players(v)
		check(players.size()==1 and players[0].get_meta("mc_sound_event")==("entity.player.hurt" if amount==50 else "entity.player.attack.crit"),"ingot uses same damage audio threshold at "+str(amount))
		check(players.size()==1 and is_equal_approx(players[0].volume_db,v.mc_outgoing_impact_volume(amount)),"ingot playback uses full damage-based gain")
		shot.advance(0.4)
		check(hit_players(v).size()==1,"spent ingot cannot repeat its damage sound")
		clear_control(target)
	var anvil_count:int = 0
	for node:Node in arena.get_children():
		if str(node.get_meta("mc_sound_event",""))=="block.anvil.hit": anvil_count += 1
	check(anvil_count==0,"enemy hit no longer layers a quiet anvil hit over damage audio")
	clear_hit_players(v)
	wall_at(Vector2(45,0))
	await physics_frame
	await process_frame
	v.launch_iron(Vector2.RIGHT)
	var shot:Node2D = get_nodes_in_group("GolemIronProjectile").back()
	shot.advance(0.4)
	check(hit_players(v).is_empty(),"wall impact does not fake health-damage audio")
	anvil_count = 0
	for node:Node in arena.get_children():
		if str(node.get_meta("mc_sound_event",""))=="block.anvil.hit": anvil_count += 1
	check(anvil_count==1,"wall impact still uses its native anvil sound once")
	print("GOLEM_HIT_AUDIO_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
