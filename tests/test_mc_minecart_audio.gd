extends "res://tests/test_mc_frontier.gd"
func clear_hit_audio(cart:Node2D) -> void:
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if str(node.get_meta("mc_sound_event","")).begins_with("entity.player."):
			node.stop()
			node.remove_from_group("MCNativeSFX")
			node.queue_free()
	for event:String in ["entity.player.hurt","entity.player.attack.crit"]:
		cart.set_meta("mc_event_sound_"+event.replace(".","_"),-10000)
func hit_players() -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if str(node.get_meta("mc_sound_event","")).begins_with("entity.player."): result.append(node)
	return result
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var cart:Node2D = actor("矿车",center)
	var victim:Node2D = dummy(center+Vector2(24,0))
	await physics_frame
	cart.rush_phase = cart.RushPhase.DASHING
	cart.launch_distance = 0
	check(cart.impact_sound_event(49)=="entity.player.hurt","below 50 selects MC ordinary hurt")
	check(cart.impact_sound_event(50)=="entity.player.hurt","exactly 50 stays ordinary")
	check(cart.impact_sound_event(51)=="entity.player.attack.crit","above 50 selects MC critical hit")
	var previous:float = -INF
	for amount:float in [1.0,5.0,20.0,49.0,50.0,51.0,100.0,500.0,10000.0]:
		var volume:float = cart.impact_volume(amount)
		check(volume>previous and volume>=-24.0 and volume<=2.0,"volume increases smoothly and remains bounded at damage "+str(amount))
		previous = volume
	for nominal:float in [20.0,40.0,80.0,160.0]:
		clear_hit_audio(cart)
		cart._hit_until.clear()
		cart.drive_speed = cart.rush_speed*sqrt((nominal/cart.attack_damage()-0.35)/cart.speed_damage_factor)
		var before:int = victim.health
		check(cart.hit_enemy(victim,cart.global_position),"real collision accepted")
		var actual:float = before-victim.health
		var players:Array[Node] = hit_players()
		check(players.size()==1,"exactly one impact sound emitted")
		if players.size()==1:
			check(players[0].get_meta("mc_sound_event")==cart.impact_sound_event(actual),"actual damage determines live audio event")
			check(is_equal_approx(players[0].volume_db,cart.impact_volume(actual)),"live audio gain scales with actual damage")
			check(players[0].global_position==victim.global_position,"impact audio originates at victim")
		check(not cart.hit_enemy(victim,cart.global_position) and hit_players().size()==1,"overlap cooldown prevents duplicate audio")
	clear_hit_audio(cart)
	cart._hit_until.clear()
	victim.Damage_reduction = 0.8
	cart.drive_speed = cart.rush_speed*sqrt((160.0/cart.attack_damage()-0.35)/cart.speed_damage_factor)
	check(cart.hit_enemy(victim,cart.global_position),"mitigated collision accepted")
	var players:Array[Node] = hit_players()
	check(players.size()==1 and players[0].get_meta("mc_sound_event")=="entity.player.hurt","high raw damage reduced below 50 plays ordinary hurt")
	clear_hit_audio(cart)
	cart._hit_until.clear()
	victim.Damage_reduction = 0.0
	victim.max_block = 1000
	victim.block = 1000
	cart.hit_enemy(victim,cart.global_position)
	check(hit_players().is_empty(),"shield-only impact does not play health-damage hurt/crit")
	clear_hit_audio(cart)
	cart.emit_impact_sound(0.0,center)
	check(hit_players().is_empty(),"zero damage cannot create impact audio")
	cart._hit_until.clear()
	victim.block = 0
	victim.health = 20
	check(cart.hit_enemy(victim,cart.global_position),"lethal collision accepted")
	players = hit_players()
	check(players.size()==1 and players[0].get_meta("mc_sound_event")=="entity.player.hurt","overkill sound uses actual remaining health damage")
	print("MINECART AUDIO CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
