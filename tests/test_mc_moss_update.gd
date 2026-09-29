extends "res://tests/test_mc_frontier.gd"
func sounds(event:String) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if not node.is_queued_for_deletion() and node.get_meta("mc_sound_event","")==event: result.append(node)
	return result
func reset_sound(context:Node,event:String) -> void:
	for player:Node in sounds(event):
		player.stop()
		player.remove_from_group("MCNativeSFX")
		player.queue_free()
	context.set_meta("mc_event_sound_"+event.replace(".","_"),-10000)
func clear_place_particles() -> void:
	for node:Node in get_nodes_in_group("MCMossPlaceDebris"):
		node.remove_from_group("MCMossPlaceDebris")
		node.queue_free()
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	var point:Vector2 = Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position = point
	var target:Node2D = dummy(point)
	moss.FOOTSTEPS.ensure(moss).set_physics_process(false)
	await physics_frame
	check(moss.moss_sound_gain_db==16.0,"moss environmental gain increased from eight to sixteen dB")
	for event:String in ["block.moss.place","block.moss.break","block.moss.step"]:
		var base:float = -11.0 if event.ends_with("place") else -9.0 if event.ends_with("break") else -15.0
		var context:Node = target if event.ends_with("step") else moss
		reset_sound(context,event)
		moss.emit_moss_sound(event,point,base,target if event.ends_with("step") else null)
		var players:Array[Node] = sounds(event)
		check(players.size()==1,"native environmental sound emits")
		if players.size()==1:
			check(players[0].volume_db>=minf(base+15.0,6.0) and players[0].volume_db<=minf(base+16.01,6.0),"actual moss playback preserves stronger gain with a moss-only six-dB ceiling")
			check(is_equal_approx(players[0].attenuation,0.3) and is_equal_approx(players[0].max_distance,2200.0),"distance attenuation no longer buries moss sounds")
			if event != "block.moss.step": check(players[0].volume_db>2.0,"placement and breaking are not flattened by shared audio ceiling")
	clear_place_particles()
	moss.plant(point)
	check(get_nodes_in_group("MCMossPlaceDebris").size()==1,"successful placement emits a local particle burst")
	var fx:Node2D = get_nodes_in_group("MCMossPlaceDebris")[0]
	check(fx.global_position==point and fx.blocks.size()==6,"placement emits only six moss chips at the placed cell")
	for block:Dictionary in fx.blocks:
		check(block.size<=1.8 and block.upward<=60.0,"placement chips are small and low, distinct from destruction burst")
	moss.plant(point)
	moss.plant(point)
	check(get_nodes_in_group("MCMossPlaceDebris").size()==3,"adding layers also emits placement particles")
	check(not moss.plant(point) and get_nodes_in_group("MCMossPlaceDebris").size()==3,"full cells cannot create fake particles")
	clear_place_particles()
	moss.patches.clear()
	moss.growth_left = 0.0
	moss.cultivate()
	complete_moss_growth(moss)
	var positions:Dictionary = {}
	for effect:Node2D in get_nodes_in_group("MCMossPlaceDebris"): positions[effect.global_position] = true
	check(positions.size()==6,"automatic cultivation emits particles at all six distinct planted cells")
	moss.patches.clear()
	moss.plant(point)
	reset_sound(moss,"entity.player.hurt")
	reset_sound(moss,"entity.player.attack.crit")
	var hp:int = target.health
	moss.check_trampling()
	check(target.health==hp-10 and sounds("entity.player.hurt").size()==1,"ten-damage moss tick uses ordinary hit audio")
	check(sounds("entity.player.attack.crit").is_empty(),"weak tick does not create critical audio")
	for amount:float in [49.0,50.0,51.0,120.0]:
		reset_sound(moss,"entity.player.hurt")
		reset_sound(moss,"entity.player.attack.crit")
		moss.damage_with_moss_sound(target,amount,point)
		var players:Array[Node] = sounds("entity.player.attack.crit" if amount>50.0 else "entity.player.hurt")
		check(players.size()==1,"impact audio follows the exact 50-damage boundary")
		if players.size()==1: check(is_equal_approx(players[0].volume_db,moss.impact_volume(amount)),"impact gain uses same actual-damage curve as cart and sword")
	check(moss.impact_volume(20)<moss.impact_volume(50) and moss.impact_volume(50)<moss.impact_volume(60) and moss.impact_volume(60)<moss.impact_volume(120),"higher actual damage produces louder hits")
	reset_sound(moss,"entity.player.hurt")
	reset_sound(moss,"entity.player.attack.crit")
	moss.burrow_wait = 0.0
	check(moss.begin_burrow(),"drill attack starts")
	moss.burrow_left = 0.0
	hp = target.health
	check(moss.finish_burrow() and target.health==hp-60,"emergence now deals sixty base damage")
	check(sounds("entity.player.attack.crit").size()==1 and sounds("entity.player.hurt").is_empty(),"sixty-damage emergence plays critical hit audio")
	reset_sound(moss,"entity.player.hurt")
	reset_sound(moss,"entity.player.attack.crit")
	target.Damage_reduction = 0.5
	moss.damage_with_moss_sound(target,60,point)
	check(sounds("entity.player.hurt").size()==1 and sounds("entity.player.attack.crit").is_empty(),"mitigated drill hit below threshold uses ordinary audio")
	reset_sound(moss,"entity.player.hurt")
	target.Damage_reduction = 0.0
	target.max_block = 1000
	target.block = 1000
	moss.damage_with_moss_sound(target,60,point)
	check(sounds("entity.player.hurt").is_empty() and sounds("entity.player.attack.crit").is_empty(),"shield-only damage does not play health-hit audio")
	print("MOSS UPDATE CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
