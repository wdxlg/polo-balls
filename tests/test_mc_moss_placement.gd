extends "res://tests/test_mc_frontier.gd"
func begin_growth(moss:Node2D) -> bool:
	moss.cancel_cultivation()
	moss.patches.clear()
	moss.growth_left = 0.0
	return moss.cultivate()
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	var moss:Node2D = actor("苔藓",center)
	var origin:Vector2 = Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position = origin
	moss.FOOTSTEPS.ensure(moss).set_physics_process(false)
	var target:Node2D = dummy(origin)
	await physics_frame
	moss.state_label("old moss status",Color.WHITE)
	moss.visual_mob()
	check(moss._status_text.is_empty(),"old moss status text is removed instead of recreated")
	check(moss.side_status_ui_enabled,"normal status/HUD is not globally disabled")
	var sound_serial:int = moss._moss_sound_serial
	var fx_serial:int = moss._frontier_event_id
	check(begin_growth(moss),"cultivation begins with shrink and planned cells")
	check(moss._growth_winding and moss._growth_pending.size()==6 and moss.patches.is_empty(),"six previews exist before any actual terrain")
	check(moss.placement_preview_alpha>0.0 and moss.placement_preview_alpha<=0.35,"preview uses low opacity")
	check(moss._moss_sound_serial==sound_serial and moss._frontier_event_id==fx_serial,"preview is silent and creates no placement particles")
	var chosen:Dictionary = {}
	for entry:Dictionary in moss._growth_pending:
		check(not chosen.has(entry.point) and entry.layer==0,"preview cells are distinct new ground cells")
		chosen[entry.point] = true
	check(not moss.cultivate() and not moss.begin_burrow(),"repeated growth or burrow cannot interrupt pending placement")
	target.global_position = moss._growth_pending[0].point
	var hp:int = target.health
	moss.check_trampling()
	check(target.health==hp,"preview terrain cannot damage a walker")
	moss.clock = moss._moss_pose_started+moss.placement_shrink_time*0.5
	moss.visual_mob()
	var scale_ratio:Vector2 = moss.image.scale/moss._moss_rest_scale
	check(scale_ratio.x<1.0 and scale_ratio.x>0.68 and is_equal_approx(scale_ratio.x,scale_ratio.y),"body shrinks uniformly during anticipation")
	check(not moss.finish_cultivation() and moss.patches.is_empty(),"early completion cannot place during shrink")
	var mirror:Node2D = actor("苔藓",origin+Vector2(300,0))
	mirror.set_multiplayer_authority(2)
	mirror.accept_visual(moss.visual_state())
	mirror.visual_mob()
	check(mirror._growth_pending==moss._growth_pending and mirror._growth_winding and mirror.patches.is_empty(),"network snapshot carries exact preview cells, no terrain yet")
	check(mirror.image.scale.is_equal_approx(moss.image.scale),"remote preview shares shrink phase and clock")
	check(not mirror.cultivate(),"remote preview grants no placement authority")
	var paused_clock:float = moss.clock
	game.now_stop_state = true
	moss.tick_physics(0,10.0)
	check(moss.clock==paused_clock and moss._growth_pending.size()==6 and moss.patches.is_empty(),"pause freezes preview and shrink without committing")
	game.now_stop_state = false
	moss.clock = moss._moss_pose_started+moss.placement_shrink_time+0.0001
	check(moss.finish_cultivation(),"terrain commits at start of rebound")
	check(moss.patches.size()==6 and moss._growth_pending.is_empty() and not moss._growth_winding,"commit swaps all ghosts for real terrain")
	for patch:Dictionary in moss.patches: check(chosen.has(patch.point),"committed tile exactly matches a previewed cell")
	check(moss._moss_sound_serial==sound_serial+6 and moss._frontier_event_id==fx_serial+6,"native sound and per-cell particles are emitted only at commit")
	check(not moss.finish_cultivation() and moss.growth_count==1,"commit is idempotent")
	moss.clock = moss._moss_pose_started+moss.placement_shrink_time+moss.placement_spring_time*0.28
	moss.visual_mob()
	check(moss.image.scale.x>moss._moss_rest_scale.x,"rebound elastically overshoots original size")
	mirror.accept_visual(moss.visual_state())
	mirror.visual_mob()
	check(mirror._growth_pending.is_empty() and mirror.patches==moss.patches and mirror.image.scale.is_equal_approx(moss.image.scale),"remote commit removes ghosts and reproduces spring")
	mirror.free()
	moss.clock = moss._moss_pose_started+moss.placement_shrink_time+moss.placement_spring_time+0.01
	moss.visual_mob()
	check(moss.image.scale.is_equal_approx(moss._moss_rest_scale) and not moss.placement_active(),"spring restores exact original scale")
	check(begin_growth(moss),"stun cancellation fixture starts")
	sound_serial = moss._moss_sound_serial
	moss.dizziness = true
	moss.step_mob(0.1)
	check(moss._growth_pending.is_empty() and moss.patches.is_empty() and not moss._growth_winding,"stun cancels preview without phantom planting")
	check(moss._moss_sound_serial==sound_serial and moss.image.scale.is_equal_approx(moss._moss_rest_scale),"cancellation restores body silently")
	moss.dizziness = false
	check(begin_growth(moss),"full-cell race fixture starts")
	var full_point:Vector2 = moss._growth_pending[0].point
	for i:int in range(3): moss.plant(full_point)
	var remaining:Dictionary = {}
	for entry:Dictionary in moss._growth_pending: remaining[entry.point] = true
	complete_moss_growth(moss)
	check(moss.patches.size()==6 and moss.patch_at(full_point).layers==3,"cell filled during anticipation is skipped, not overstacked or rerolled")
	for patch:Dictionary in moss.patches: check(remaining.has(patch.point),"race resolution never plants an unmarked replacement cell")
	moss.patches.clear()
	for x:int in range(-2,3):
		for y:int in range(-2,3):
			for i:int in range(3): moss.plant(origin+Vector2(x,y)*moss.CELL)
	moss.growth_left = 0.0
	check(not moss.cultivate() and moss._growth_pending.is_empty(),"full field produces no fake previews")
	moss.patch_at(origin).layers = 2
	moss.growth_left = 0.0
	check(moss.cultivate() and moss._growth_pending.size()==1 and moss._growth_pending[0].layer==2,"stack preview is positioned at the upcoming layer height")
	moss.cancel_cultivation()
	check(begin_growth(moss),"death cancellation fixture starts")
	moss.health = 0
	moss.step_mob(0.1)
	check(moss._growth_pending.is_empty() and moss.patches.is_empty(),"dead moss cannot leave or commit pending previews")
	print("MOSS PLACEMENT CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
