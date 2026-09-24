extends "res://tests/test_mc_frontier.gd"
func sounds(event:String) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if not node.is_queued_for_deletion() and node.get_meta("mc_sound_event","")==event: result.append(node)
	return result
func reset_sound(context:Node,event:String) -> void:
	for sound:Node in sounds(event):
		sound.stop()
		sound.remove_from_group("MCNativeSFX")
		sound.queue_free()
	context.set_meta("mc_event_sound_"+event.replace(".","_"),-10000)
func clear_debris() -> void:
	for effect:Node in get_nodes_in_group("MCMossBreakDebris"):
		effect.remove_from_group("MCMossBreakDebris")
		effect.queue_free()
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	var moss:Node2D = actor("苔藓",center)
	var point:Vector2 = Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position = point
	var target:Node2D = dummy(point)
	var friendly:Node2D = dummy(point,"Team0")
	var scheduler:Node = moss.FOOTSTEPS.ensure(moss)
	scheduler.set_physics_process(false)
	await physics_frame
	reset_sound(moss,"block.moss.place")
	check(moss.plant(point) and sounds("block.moss.place").size()==1,"successful planting plays native moss placement")
	moss.plant(point)
	moss.plant(point)
	reset_sound(moss,"block.moss.place")
	check(not moss.plant(point) and sounds("block.moss.place").is_empty(),"full cell does not play fake placement")
	moss.patches.clear()
	for x:int in range(-1,2):
		for y:int in range(-1,2):
			for layer:int in range(2): moss.plant(point+Vector2(x,y)*moss.CELL)
	reset_sound(moss,"block.moss.break")
	clear_debris()
	moss.burrow_wait = 0.0
	check(moss.begin_burrow(),"burrow starts on occupied 3x3")
	moss.burrow_left = 0.0
	check(moss.finish_burrow(),"burrow resolves successfully")
	var effects:Array[Node] = get_nodes_in_group("MCMossBreakDebris")
	check(effects.size()==9,"every consumed 3x3 cell emits its own shared block burst")
	var seen:Dictionary = {}
	for effect:Node2D in effects:
		seen[effect.global_position] = true
		check(effect.get_script().resource_path.ends_with("block_fragments.gd") and effect.pieces.size()==16 and effect.pieces[0].height>0,"per-cell destruction uses native moss texture and shared landing arcs")
	check(seen.size()==9 and moss.patches.size()==9,"distinct cells burst even when an underlying layer remains")
	check(not sounds("block.moss.break").is_empty(),"burrow layer consumption plays moss break")
	clear_debris()
	reset_sound(moss,"block.moss.break")
	var serial:int = moss.patch_at(point).serial
	moss.destroy_moss_obstacle(point,serial)
	check(get_nodes_in_group("MCMossBreakDebris").size()==1 and sounds("block.moss.break").size()==1,"explosion-style destruction plays moss break and square debris")
	moss.destroy_moss_obstacle(point,serial)
	check(get_nodes_in_group("MCMossBreakDebris").size()==1 and sounds("block.moss.break").size()==1,"duplicate destruction does not replay feedback")
	moss.patches.clear()
	moss.plant(point)
	moss.burrow_wait = 999.0
	target.global_position = point
	friendly.global_position = point
	scheduler.states.clear()
	reset_sound(target,"block.moss.step")
	scheduler.sample(0.1)
	target.velocity = Vector2(999,0)
	scheduler.sample(1.0)
	check(sounds("block.moss.step").is_empty(),"stationary enemies do not produce steps even with fake velocity")
	var intervals:Dictionary = {}
	for i:int in range(20):
		var interval:float = scheduler.next_interval()
		intervals[interval] = true
		check(interval>=scheduler.longest_step+0.079 and interval<=scheduler.longest_step+0.321,"random silence is added after the longest native clip")
	check(intervals.size()>1,"footstep intervals actually vary")
	target.global_position += Vector2(1,0)
	friendly.global_position += Vector2(1,0)
	scheduler.sample(0.1)
	check(sounds("block.moss.step").size()==1,"only moving enemy, not friendly, produces a step")
	var first:AudioStreamPlayer2D = target.get_meta("mc_moss_step_player").get_ref()
	check(scheduler.states[target.get_instance_id()].remaining>=first.stream.get_length()/first.pitch_scale,"next interval covers the actual sound duration")
	first.stream_paused = true
	target.global_position += Vector2(1,0)
	scheduler.sample(100.0)
	check(sounds("block.moss.step").size()==1,"even accelerated combat time cannot overlap a still-playing clip")
	var before_serial:int = moss._moss_sound_serial
	moss.emit_moss_sound("block.moss.step",target.global_position,-15,target)
	check(sounds("block.moss.step").size()==1 and moss._moss_sound_serial==before_serial+1,"receiver independently rejects overlapping step playback")
	var saved:float = scheduler.states[target.get_instance_id()].remaining
	game.now_stop_state = true
	target.global_position += Vector2(1,0)
	scheduler.sample(2.0)
	check(scheduler.states[target.get_instance_id()].remaining==saved,"pause does not advance footstep cooldown")
	game.now_stop_state = false
	reset_sound(target,"block.moss.step")
	scheduler.states[target.get_instance_id()].remaining = 0.05
	target.global_position += Vector2(1,0)
	scheduler.sample(0.01)
	check(sounds("block.moss.step").is_empty(),"random gap remains enforced after old clip stops")
	target.global_position += Vector2(1,0)
	scheduler.sample(0.1)
	check(sounds("block.moss.step").size()==1,"moving enemy can step again after duration plus random gap")
	reset_sound(target,"block.moss.step")
	target.global_position = point+Vector2(96,0)
	scheduler.sample(10.0)
	check(sounds("block.moss.step").is_empty(),"moving off moss produces no moss footsteps")
	target.global_position = point
	scheduler.sample(1.0)
	first = target.get_meta("mc_moss_step_player").get_ref()
	first.stream_paused = true
	var second_owner:Node2D = actor("苔藓",point+Vector2(24,0))
	second_owner.plant(point+Vector2(24,0))
	check(second_owner.FOOTSTEPS.ensure(second_owner)==scheduler,"all moss owners share one per-enemy scheduler")
	target.global_position = point+Vector2(24,0)
	scheduler.sample(100.0)
	check(sounds("block.moss.step").size()==1,"crossing between moss owners cannot reset an active enemy footstep")
	reset_sound(target,"block.moss.step")
	var another:Node2D = dummy(point)
	scheduler.states.clear()
	target.global_position = point
	scheduler.sample(0.1)
	target.global_position += Vector2(1,0)
	another.global_position += Vector2(-1,0)
	scheduler.sample(0.1)
	check(sounds("block.moss.step").size()==2,"two moving enemies have independent sound channels")
	reset_sound(target,"block.moss.step")
	another.queue_free()
	await process_frame
	scheduler.sample(0.1)
	check(scheduler.states.size()<=get_nodes_in_group("Ball").size(),"departed targets are pruned from cooldown state")
	print("MOSS FEEDBACK CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
