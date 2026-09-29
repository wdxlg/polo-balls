extends "res://tests/test_mc_frontier.gd"
const EVENTS:Array[String] = ["entity.player.attack.sweep","entity.player.attack.weak","entity.player.hurt","entity.player.attack.crit","entity.item.break","block.crafter.craft","entity.breeze.deflect"]
func sounds(event:String) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if not node.is_queued_for_deletion() and node.get_meta("mc_sound_event","")==event: result.append(node)
	return result
func reset_audio(unit:Node2D) -> void:
	for event:String in EVENTS:
		for player:Node in sounds(event):
			player.stop()
			player.remove_from_group("MCNativeSFX")
			player.queue_free()
		unit.set_meta("mc_event_sound_"+event.replace(".","_"),-10000)
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	for kind:int in [0,1,2]:
		var unit:Node2D = actor("木剑",center+Vector2(kind*170-170,0))
		unit.part_kind = kind
		unit.bench_destroyed = kind!=0
		unit.direction = Vector2.RIGHT
		unit.visual_mob()
		unit.ensure_attack_shape()
		var target:Node2D = dummy(unit.global_position+Vector2(12 if kind==0 else 5 if kind==1 else 21,0))
		await physics_frame
		await process_frame
		reset_audio(unit)
		unit.sword_charge = 1.0
		check(unit.begin_swing(),"form starts its physical attack "+str(kind))
		var attack_event:String = "entity.player.attack.weak" if kind==2 else "entity.player.attack.sweep"
		check(sounds(attack_event).size()==1,"form emits correct action audio "+str(kind))
		check(sounds("entity.player.hurt").is_empty() and sounds("entity.player.attack.crit").is_empty(),"windup alone creates no impact sound")
		var hp:int = target.health
		unit.advance_attack(unit.attack_duration())
		var actual:float = hp-target.health
		check(actual>0,"real swept collision lands "+str(kind))
		var impacts:Array[Node] = sounds(unit.impact_sound_event(actual))
		check(impacts.size()==1,"real physical hit emits one ordinary or critical sound")
		if impacts.size()==1: check(is_equal_approx(impacts[0].volume_db,unit.impact_volume(actual)),"physical hit gain matches actual damage")
		unit.advance_attack(0.2)
		check(sounds(unit.impact_sound_event(actual)).size()==1,"same swing cannot repeat hit audio")
		var previous:float = -INF
		for amount:float in [10.0,49.0,50.0,51.0,100.0]:
			reset_audio(unit)
			hp = target.health
			check(unit.damage_with_impact_sound(target,amount,target.global_position),"form hit accepted")
			actual = hp-target.health
			var expected:String = "entity.player.attack.crit" if actual>50.0 else "entity.player.hurt"
			impacts = sounds(expected)
			check(impacts.size()==1,"all forms use actual 50-damage boundary")
			if impacts.size()==1:
				check(impacts[0].volume_db>previous,"higher damage increases sound volume across threshold")
				previous = impacts[0].volume_db
		reset_audio(unit)
		target.Damage_reduction = 0.8
		unit.damage_with_impact_sound(target,100.0,target.global_position)
		check(sounds("entity.player.hurt").size()==1 and sounds("entity.player.attack.crit").is_empty(),"damage reduction controls event rather than raw attack")
		reset_audio(unit)
		target.Damage_reduction = 0.0
		target.max_block = 500
		target.block = 500
		unit.damage_with_impact_sound(target,100.0,target.global_position)
		check(sounds("entity.player.hurt").is_empty() and sounds("entity.player.attack.crit").is_empty(),"shield-only impact emits neither hurt nor crit")
		unit.queue_free()
		target.queue_free()
		await process_frame
	var sword:Node2D = actor("木剑",center)
	reset_audio(sword)
	sword.durability = 1
	sword.sword_charge = 1.0
	sword.begin_swing()
	check(sounds("entity.item.break").is_empty(),"last durability does not play break before swing finishes")
	sword.advance_attack(sword.attack_duration())
	await process_frame
	await process_frame
	check(sword.part_kind==1 and sounds("entity.item.break").size()==1,"actual split emits item-break sound exactly once")
	check(sounds("entity.breeze.deflect").is_empty(),"breaking keeps its item-break sound without a crafting transformation cue")
	sword.split_sword()
	check(sounds("entity.item.break").size()==1,"duplicate split call does not replay break")
	var bench:Node2D = sword.workbench
	bench.set_physics_process(false)
	for piece:Node2D in bench.living_pieces():
		piece.state_machine.set_physics_process(false)
		piece.dock_delay = 0
		piece.global_position = bench.global_position+Vector2(-8 if piece==sword else 8,0)
	reset_audio(sword)
	bench.age = 0.0
	bench.advance(3.0)
	check(sounds("block.crafter.craft").is_empty(),"materialization and incomplete repair stay silent")
	bench.advance(2.41)
	check(sword.part_kind==0 and sword.durability==sword.MAX_DURABILITY and sounds("block.crafter.craft").size()==1,"successful workbench reassembly emits native crafting sound")
	check(sounds("entity.breeze.deflect").size()==1,"reassembly also emits the bat transformation sound exactly once")
	if sounds("entity.breeze.deflect").size()==1:
		var transform:Node = sounds("entity.breeze.deflect")[0]
		var bat_audio:Script = load("res://scripts/characters/我的世界/bat/bat_audio.gd")
		var original_stream:bool = false
		for variant:Dictionary in bat_audio.EVENTS["entity.breeze.deflect"]:
			if variant.stream == transform.stream: original_stream = true
		check(original_stream,"transformation uses an original bat sound variant")
		check(transform.global_position==sword.global_position,"transformation sound originates at the crafting position")
		check(transform.get_meta("mc_sound_priority",false),"transformation sound has priority under load")
	if sounds("block.crafter.craft").size()==1:
		check(sounds("block.crafter.craft")[0].global_position==sword.global_position,"craft sound stays at bench position after bench removal")
	bench.complete_repair()
	check(sounds("block.crafter.craft").size()==1 and sounds("entity.breeze.deflect").size()==1,"duplicate repair completion cannot replay either sound")
	sword._sword_audio(sword._last_wood_sound,"block.crafter.craft",sword.global_position,-6.0)
	check(sounds("block.crafter.craft").size()==1,"duplicate network sound event is ignored")
	sword._sword_audio(sword._last_wood_sound,"entity.breeze.deflect",sword.global_position,-4.0)
	check(sounds("entity.breeze.deflect").size()==1,"duplicate network transformation event is ignored")
	print("WOOD AUDIO CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
