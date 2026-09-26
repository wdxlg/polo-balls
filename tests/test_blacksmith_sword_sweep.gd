extends SceneTree
## Blacksmith's real scene: exact swing-SFX threshold, continuous sword arc,
## spaced source-texture afterimages, and (with a GPU) three visible poses.

var checks:int = 0
var failures:int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BLACKSMITH_SWING_FAIL: " + label)


func latest_audio(actor:Node) -> AudioStreamPlayer2D:
	for index:int in range(actor.get_child_count()-1,-1,-1):
		var child:Node = actor.get_child(index)
		if child is AudioStreamPlayer2D:
			return child as AudioStreamPlayer2D
	return null


func expect_swing_audio(actor:Node,damage:float,want_sweep:bool) -> void:
	actor.call("_broadcast_attack_sfx",damage)
	var player:AudioStreamPlayer2D = latest_audio(actor)
	check(player != null and player.stream != null,"swing %.3f creates one audible attack stream" % damage)
	if player == null or player.stream == null:
		return
	var path:String = player.stream.resource_path
	check(path.contains("/近战/横扫/") == want_sweep,"swing %.3f uses %s, got %s" % [damage,"sweep" if want_sweep else "strong",path])
	check(is_equal_approx(player.volume_db,actor.sword_swing_base_volume_db + actor._damage_audio_bonus_db(damage)),"swing %.3f keeps damage-dependent volume" % damage)
	player.stop()
	player.free()


func sword_ghosts(actor:Node) -> Array[Sprite2D]:
	var ghosts:Array[Sprite2D] = []
	for child:Node in actor.get_children():
		# Godot automatically renames later siblings sharing the same requested name.
		if child is Sprite2D and child.top_level and child.z_index == 3 and child.texture == actor._sword_sprite.texture:
			ghosts.append(child as Sprite2D)
	return ghosts


func pixel_difference(a:Color,b:Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))


func changed_pixels(before:Image,after:Image,area:Rect2i) -> int:
	var changed:int = 0
	for y:int in range(area.position.y,area.end.y,2):
		for x:int in range(area.position.x,area.end.x,2):
			if pixel_difference(before.get_pixel(x,y),after.get_pixel(x,y)) > 0.10:
				changed += 1
	return changed


func run() -> void:
	create_timer(50.0,true,false,true).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	var saved_stop:bool = game.now_stop_state
	var saved_scene:Node = current_scene
	var saved_size:Vector2i = root.size
	game.now_stop_state = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(680,480)
	var backdrop:=ColorRect.new()
	backdrop.color = Color("27323a")
	backdrop.size = Vector2(680,480)
	backdrop.z_index = -8
	root.add_child(backdrop)
	var arena:=Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var smith:Node2D = (load("res://scenes/characters/我的世界/铁匠村民.tscn") as PackedScene).instantiate()
	smith.position = Vector2(310,235)
	smith.set("Team","A")
	arena.add_child(smith,true)
	smith.set_physics_process(false)
	smith.set_process(false)
	smith.sword_tier = smith.TIER_NETHERITE
	smith._apply_equipment_stats(false)
	smith._update_equipment_visuals()
	print("BLACKSMITH_VISUAL_METRICS canvas=%s graphics=%s image_global=%s sword_global=%s" % [root.get_canvas_transform().get_scale(),smith.get_node("Graphics").scale,smith.get_node("Graphics/Image").get_global_transform_with_canvas().get_scale(),smith._sword_sprite.get_global_transform_with_canvas().get_scale()])
	check(smith.Damage == 100 and is_equal_approx(smith.sword_visual_scale,0.12) and smith.sword_swing_duration >= 0.44,"real villager keeps damage/timing with slightly smaller sword")
	check(smith._sword_sprite.texture != null and not smith._sword_sprite.visible,"original sword art stays hidden before attack")
	check(smith.SWEEP_ATTACK_SFX.size() == 7,"reuse seven existing Minecraft sweep variants")
	expect_swing_audio(smith,20.0,false)
	expect_swing_audio(smith,99.9,false)
	expect_swing_audio(smith,100.0,false)
	expect_swing_audio(smith,100.001,true)
	expect_swing_audio(smith,210.0,true)
	smith.post_max_damage_bonus = 1
	smith._apply_equipment_stats(false)
	var outgoing:float = smith.attack_damage(1.0)
	check(outgoing > 100.0,"permanent +1 damage is reflected in actual outgoing attack")
	expect_swing_audio(smith,outgoing,true)
	check(smith._is_critical_sword_hit(100.0) and not smith._is_critical_sword_hit(99.0),"existing hit-crit threshold remains independent of swing sound")

	# Advance the exact real tween at 60 Hz, not just check its configured duration.
	smith._play_sword_swing_local(Vector2.RIGHT,false)
	var start_angle:float = smith._sword_pivot.rotation
	var previous_angle:float = start_angle
	var max_step:float = 0.0
	var step_count:int = 0
	var angle_at_hit:float = start_angle
	for i:int in range(36):
		smith._sword_tween.custom_step(1.0/60.0)
		if not smith._sword_pivot.visible:
			break
		var angle:float = smith._sword_pivot.rotation
		max_step = maxf(max_step,absf(wrapf(angle-previous_angle,-PI,PI)))
		previous_angle = angle
		step_count += 1
		if i == int(roundf(smith.sword_hit_delay*60.0))-1:
			angle_at_hit = angle
	check(step_count >= 23 and max_step < deg_to_rad(23.0),"arc animates over >=23 frames without abrupt angular jumps (max %.1f deg)" % rad_to_deg(max_step))
	check(absf(wrapf(angle_at_hit-deg_to_rad(49.0),-PI,PI)) < deg_to_rad(37.0),"blade crosses forward near real damage frame")
	var ghosts:Array[Sprite2D] = sword_ghosts(smith)
	var distinct:Dictionary = {}
	for ghost:Sprite2D in ghosts:
		distinct[int(roundf(rad_to_deg(ghost.global_rotation)/4.0))] = true
	check(ghosts.size() >= 9 and distinct.size() >= 8,"even a skipped frame samples visible afterimages along the arc, not one piled-up pose")
	if DisplayServer.get_name() != "headless":
		# Let the previous afterimages fade; compare actual rendered output to idle.
		var camera:=Camera2D.new()
		camera.position = smith.position
		camera.zoom = Vector2(2.2,2.2)
		arena.add_child(camera)
		camera.make_current()
		await create_timer(0.26).timeout
		await RenderingServer.frame_post_draw
		var idle:Image = root.get_texture().get_image()
		var save_dir:String = "user://blacksmith_sword_revision"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
		smith._play_sword_swing_local(Vector2.RIGHT,false)
		var phases:Array[float] = [0.11,0.12,0.12]
		var labels:Array[String] = ["windup","contact","follow"]
		var area:=Rect2i(Vector2i(165,65),Vector2i(360,340))
		var previous_frame:Image = idle
		var pixel_counts:Array[int] = []
		for i:int in range(phases.size()):
			await create_timer(phases[i]).timeout
			await RenderingServer.frame_post_draw
			var frame:Image = root.get_texture().get_image()
			var changed:int = changed_pixels(idle,frame,area)
			pixel_counts.append(changed)
			check(changed > 110,"real GPU shows original sword/trail during %s, changed=%d" % [labels[i],changed])
			if i > 0:
				check(changed_pixels(previous_frame,frame,area) > 150,"real GPU shows distinct animated poses between %s and %s" % [labels[i-1],labels[i]])
			check(frame.save_png(save_dir.path_join("swing_"+labels[i]+".png")) == OK,"save %s GPU frame" % labels[i])
			previous_frame = frame
		print("BLACKSMITH_SWING_GPU renderer=%s changed=%s" % [RenderingServer.get_current_rendering_method(),pixel_counts])
	await check_sword_revision(smith,arena)
	# A new attack in the opposite direction starts on the other side; interruption hides it.
	smith._play_sword_swing_local(Vector2.LEFT,true)
	check(absf(absf(wrapf(smith._sword_pivot.rotation-start_angle,-PI,PI))-PI) < 0.06,"left-side attack uses reversed sword facing")
	smith._interrupt_sword_attack()
	check(not smith._sword_pivot.visible and not smith._sword_sprite.visible,"interrupted swing leaves no active sword")
	await check_threat_and_fade(smith,arena)
	await check_actual_sword_sector(smith,arena)
	print("BLACKSMITH_SWING_RESULT checks=%d failures=%d max_step_deg=%.2f ghost_count=%d distinct=%d" % [checks,failures,rad_to_deg(max_step),ghosts.size(),distinct.size()])
	current_scene = saved_scene
	arena.queue_free()
	backdrop.queue_free()
	game.now_stop_state = saved_stop
	root.size = saved_size
	await process_frame
	quit(1 if failures>0 else 0)

func check_actual_sword_sector(smith:Node2D,arena:Node2D) -> void:
	var samples:Array[float] = [0.0,-40.0,40.0,-44.0,44.0,-90.0,90.0,180.0,0.0]
	var targets:Array[Node2D] = []
	for i:int in range(samples.size()):
		var victim:Node2D = load("res://scenes/ball.tscn").instantiate()
		victim.Team = "B"
		victim.Max_health = 10000
		arena.add_child(victim,true)
		victim.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		victim.set_physics_process(false)
		victim.set_process(false)
		victim.Health_Restore = 0
		victim.Damage_reduction = 0
		targets.append(victim)
	for tier:int in [1,2,3]:
		smith.sword_tier = tier
		smith._apply_equipment_stats(false)
		for manual:bool in [false,true]:
			smith.set_player_control_peer(1 if manual else 0)
			for heading:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
				smith._interrupt_sword_attack()
				smith.set_player_control_aim_position(smith.global_position+heading*100.0)
				for i:int in range(targets.size()):
					targets[i].global_position = smith.global_position+heading.rotated(deg_to_rad(samples[i]))*(90.0 if i==8 else 32.0)
					targets[i].health = 10000
					targets[i].block = 0
				await physics_frame
				await physics_frame
				smith._deal_sword_damage(heading)
				for i:int in range(targets.size()):
					var expected:bool = i<3
					check((targets[i].health<10000)==expected,"actual sword tier=%d manual=%s heading=%s angle=%.0f range=%s expected_hit=%s" % [tier,manual,heading,samples[i],90 if i==8 else 32,expected])
	# Aim only decides the initial swing; moving the mouse later cannot relocate victims.
	smith.set_player_control_peer(1)
	smith.set_player_control_aim_position(smith.global_position+Vector2.RIGHT*100.0)
	smith._play_sword_swing_local(Vector2.RIGHT,false)
	smith._sword_tween.pause()
	for i:int in range(targets.size()):
		targets[i].global_position = smith.global_position+Vector2.RIGHT.rotated(deg_to_rad(samples[i]))*(90.0 if i==8 else 32.0)
		targets[i].health = 10000
		targets[i].block = 0
	smith.set_player_control_aim_position(smith.global_position+Vector2.LEFT*100.0)
	await physics_frame
	await physics_frame
	smith._deal_sword_damage(Vector2.RIGHT)
	check(targets[0].health<10000 and targets[7].health==10000,"mouse movement after windup cannot turn a locked front strike into circle/back strike")
	check(smith.get_debug_attack_regions().size()==1 and smith.get_debug_attack_regions()[0].direction.is_equal_approx(Vector2.RIGHT),"actual hit and threat sector keep the same committed direction")
	smith.set_player_control_peer(0)
	smith._interrupt_sword_attack()
	for victim:Node2D in targets: victim.free()

func smith_regions(analyzer:Node,smith:Node) -> Array[Dictionary]:
	analyzer._refresh_debug_world()
	var result:Array[Dictionary] = []
	for info:Dictionary in analyzer.get_world_threats():
		if str(info.get("kind","")).begins_with("blacksmith_sword") and info.get("source_id",0) == smith.get_instance_id(): result.append(info)
	return result

func check_threat_and_fade(smith:Node2D,arena:Node2D) -> void:
	var game:Node = root.get_node("Game")
	var old_debug:bool = bool(game.Game_Settings.get("Training_Debug_Mode",false))
	game.Game_Settings.Training_Debug_Mode = true
	var analyzer:Node2D = load("res://scripts/training/combat_threat_analyzer.gd").new()
	analyzer.name = "CombatThreatAnalyzer"
	arena.add_child(analyzer)
	smith._interrupt_sword_attack()
	var regions:Array[Dictionary] = smith_regions(analyzer,smith)
	check(regions.size()==1 and regions[0].debug_role=="detection" and regions[0].shape=="circle" and is_equal_approx(regions[0].radius,smith.sword_attack_range),"settings threat overlay shows real 360-degree detection range without training")
	for dir:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		smith._play_sword_swing_local(dir,false)
		regions = smith_regions(analyzer,smith)
		check(regions.size()==1 and regions[0].shape=="polygon" and regions[0].debug_role=="detection","windup is a blue sector, not a damaging circle")
		var points:PackedVector2Array = regions[0].points
		var half:float = deg_to_rad(smith.sword_half_angle_degrees)
		check(points[0].is_equal_approx(smith.global_position) and points[1].is_equal_approx(smith.global_position+dir.rotated(-half)*smith.sword_attack_range) and points[65].is_equal_approx(smith.global_position+dir.rotated(half)*smith.sword_attack_range),"sector uses exact world center, range and both angular boundaries")
		smith._deal_sword_damage(dir)
		regions = smith_regions(analyzer,smith)
		var damage_regions:Array[Dictionary] = []
		for region:Dictionary in regions:
			if region.debug_role=="damage": damage_regions.append(region)
		check(damage_regions.size()==1 and damage_regions[0].shape=="polygon" and damage_regions[0].direction.is_equal_approx(dir) and is_equal_approx(damage_regions[0].damage,smith.attack_damage(1.0)),"actual strike publishes its locked direction and current attribute damage")
		await physics_frame
		check(smith.get_debug_attack_regions().is_empty(),"instant strike threat clears on following physics frame")
		smith._interrupt_sword_attack()
	smith.sword_tier = 0
	check(smith_regions(analyzer,smith).is_empty(),"no weapon means no weapon threat")
	smith.sword_tier = 3
	smith.dizziness = true
	check(smith_regions(analyzer,smith).is_empty(),"stunned character has no enabled sword region")
	smith.dizziness = false
	# Fixed source pose demonstrates true renderer alpha, not just a hidden flag.
	smith._kill_spin_direction = Vector2.RIGHT
	smith._start_kill_spin_local()
	smith._sword_tween.pause()
	check(is_equal_approx(smith.sword_kill_spin_duration,0.45),"three turns take 0.45 seconds, twice as fast")
	var alphas:Array[float] = []
	for progress:float in [0.0,0.65,0.8,0.95,1.0]:
		smith._apply_kill_spin_progress(progress,0.0)
		alphas.append(smith._sword_sprite.self_modulate.a)
	check(is_equal_approx(alphas[0],1.0) and is_equal_approx(alphas[1],1.0) and alphas[2]>alphas[3] and alphas[3]>0.0 and is_zero_approx(alphas[4]),"last 35 percent fades continuously to zero before hiding")
	check(smith.get_debug_attack_regions().is_empty(),"cosmetic spin creates no damage threat")
	if DisplayServer.get_name() != "headless":
		# Capture exact same sword orientation with different progress/opacity.
		game.Game_Settings.Training_Debug_Mode = false
		analyzer._physics_process(0.05)
		for ghost:Sprite2D in sword_ghosts(smith): ghost.free()
		var frames:Array[Image] = []
		for progress:float in [0.0,0.84,1.0]:
			smith._apply_kill_spin_progress(progress,-TAU*3.0*progress)
			await process_frame
			await RenderingServer.frame_post_draw
			await process_frame
			await RenderingServer.frame_post_draw
			frames.append(root.get_texture().get_image())
		var full:float = 0.0
		var faded:float = 0.0
		for y:int in range(65,405):
			for x:int in range(165,525):
				full += pixel_difference(frames[0].get_pixel(x,y),frames[2].get_pixel(x,y))
				faded += pixel_difference(frames[1].get_pixel(x,y),frames[2].get_pixel(x,y))
		# Readback color is gamma/tone-mapped; alpha 0.44 is not a linear RGB ratio.
		check(full>10 and faded>0 and faded<full*0.85,"GPU sword opacity smoothly diminishes at fixed pose full=%.1f faded=%.1f" % [full,faded])
		smith._interrupt_sword_attack()
		game.Game_Settings.Training_Debug_Mode = true
		smith._play_sword_swing_local(Vector2.RIGHT,false)
		smith._sword_tween.pause()
		# Hold the real sector geometry for a GPU-only visibility comparison.
		smith._sword_threat_pending = false
		smith._sword_hit_active = true
		analyzer._physics_process(0.05)
		analyzer._refresh_debug_world()
		analyzer.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var shown:Image = root.get_texture().get_image()
		game.Game_Settings.Training_Debug_Mode = false
		analyzer._physics_process(0.05)
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden:Image = root.get_texture().get_image()
		check(changed_pixels(shown,hidden,Rect2i(165,65,360,340))>40,"settings toggle visibly draws/removes real attack sector on GPU")
	check(not analyzer.visible and analyzer._debug_threats.is_empty() if not bool(game.Game_Settings.Training_Debug_Mode) else true,"turning threat setting off clears cached regions")
	smith._interrupt_sword_attack()
	smith._play_sword_swing_local(Vector2.RIGHT,false)
	check(is_equal_approx(smith._sword_sprite.self_modulate.a,1.0),"next attack resets faded sword opacity")
	smith._interrupt_sword_attack()
	game.Game_Settings.Training_Debug_Mode = true
	smith._death_sequence_started = true
	check(smith_regions(analyzer,smith).is_empty(),"death removes sword detection and damage regions")
	smith._death_sequence_started = false
	analyzer._physics_process(0.05)
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.05)
	check(not analyzer.visible and analyzer._debug_threats.is_empty(),"off switch clears data without a receiver")
	analyzer.free()
	game.Game_Settings.Training_Debug_Mode = old_debug

func check_sword_revision(smith:Node2D,arena:Node2D) -> void:
	# Follow the real Tween through every direction and the +/-PI seam.
	smith.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	for tier:int in [1,2,3]:
		smith.sword_tier = tier
		smith._apply_equipment_stats(false)
		for high:bool in [false,true]:
			for degrees:int in range(-180,181,30):
				var direction_value:Vector2 = Vector2.RIGHT.rotated(deg_to_rad(float(degrees)))
				smith._play_sword_swing_local(direction_value,high)
				var previous:float = smith._sword_pivot.rotation
				var travel:float = 0.0
				var peak:float = 0.0
				for frame:int in range(70):
					if not smith._sword_tween.is_running(): break
					smith._sword_tween.custom_step(1.0/120.0)
					var step:float = absf(wrapf(smith._sword_pivot.rotation-previous,-PI,PI))
					travel += step
					peak = maxf(peak,step)
					previous = smith._sword_pivot.rotation
				check(travel < deg_to_rad(220.0) and peak < deg_to_rad(12.0),"tier %d high=%s direction=%d has no extra full turn; arc=%.1f peak=%.1f" % [tier,high,degrees,rad_to_deg(travel),rad_to_deg(peak)])
				check(is_equal_approx(smith._sword_sprite.scale.x,0.12),"all sword tiers use smaller source texture scale")
				for ghost:Sprite2D in sword_ghosts(smith): ghost.free()
	smith._interrupt_sword_attack()
	smith.sword_tier = 3
	smith._apply_equipment_stats(false)
	var victim:Node2D = load("res://scenes/ball.tscn").instantiate()
	victim.Team = "B"
	victim.position = smith.position + Vector2(28,0)
	arena.add_child(victim,true)
	victim.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	victim.set_physics_process(false)
	victim.Health_Restore = 0
	victim.health = 10000
	victim.block = 0
	victim.Damage_reduction = 0
	await physics_frame
	await physics_frame
	var serial:int = smith._kill_spin_serial
	smith._deal_sword_damage(Vector2.RIGHT)
	check(victim.health < 10000 and victim.health > 0 and smith._kill_spin_serial == serial,"real nonlethal hit does not celebrate")
	victim.health = 5
	smith._play_sword_swing_local(Vector2.RIGHT,false)
	smith._deal_sword_damage(Vector2.RIGHT)
	check(victim.health <= 0 and smith._kill_spin_serial == serial+1,"actual lethal sword hit emits one kill event")
	check(smith._kill_spin_pending and not smith._kill_spin_active,"kill waits for the ordinary follow-through")
	smith._sword_tween.custom_step(smith.sword_swing_duration+0.01)
	check(smith._kill_spin_active and smith._sword_pivot.visible,"follow-through starts visible celebration")
	smith._update_sword_idle_pose(true)
	smith._update_equipment_visuals()
	check(smith._sword_sprite.visible,"attack tail and equipment sync cannot hide celebration")
	var spin_tween:Tween = smith._sword_tween
	smith._rpc_queue_kill_spin(serial+1,Vector2.LEFT)
	check(smith._sword_tween == spin_tween and not smith._kill_spin_pending,"duplicate kill packet does not replay")
	var previous:float = smith._sword_pivot.rotation
	var turns:float = 0.0
	for frame:int in range(120):
		if not spin_tween.is_running(): break
		spin_tween.custom_step(1.0/120.0)
		turns += wrapf(smith._sword_pivot.rotation-previous,-PI,PI)
		previous = smith._sword_pivot.rotation
	check(absf(turns-TAU*3.0) < 0.02,"celebration actually rotates three full turns, not shortest-angle interpolation")
	check(not smith._kill_spin_active and not smith._sword_pivot.visible,"celebration hides cleanly at its end")
	smith._deal_sword_damage(Vector2.RIGHT)
	check(smith._kill_spin_serial == serial+1,"dead victim cannot trigger a second celebration")
	victim.free()
	# Event-only branch checks do not claim real network coverage.
	smith._rpc_queue_kill_spin(serial+2,Vector2.LEFT)
	check(smith._kill_spin_active,"left-direction celebration starts")
	smith._play_sword_swing_local(Vector2.RIGHT,false)
	check(not smith._kill_spin_active and not smith._kill_spin_pending,"new attack immediately supersedes cosmetic spin")
	smith._interrupt_sword_attack()
	smith._rpc_queue_kill_spin(serial+3,Vector2.RIGHT)
	var before_pause:float = smith._sword_pivot.rotation
	paused = true
	await create_timer(0.06,true,false,true).timeout
	check(is_equal_approx(smith._sword_pivot.rotation,before_pause),"tree pause freezes kill spin")
	paused = false
	smith.dizziness = true
	smith._sword_tween.custom_step(0.02)
	check(not smith._kill_spin_active and not smith._sword_pivot.visible,"stun cancels cosmetic spin")
	smith.dizziness = false
	smith._rpc_queue_kill_spin(serial+4,Vector2.RIGHT)
	smith._death_sequence_started = true
	smith._sword_tween.custom_step(0.02)
	check(not smith._kill_spin_active and not smith._sword_pivot.visible,"death cancels cosmetic spin")
	smith._death_sequence_started = false
	if DisplayServer.get_name() != "headless":
		smith._rpc_queue_kill_spin(serial+5,Vector2.RIGHT)
		smith._sword_tween.pause()
		var frames:Array[Image] = []
		for p:float in [0.08,0.16,0.24]:
			smith._apply_kill_spin_progress(p,deg_to_rad(125.0))
			await RenderingServer.frame_post_draw
			await process_frame
			await RenderingServer.frame_post_draw
			frames.append(root.get_texture().get_image())
		check(changed_pixels(frames[0],frames[1],Rect2i(165,65,360,340)) > 30 and changed_pixels(frames[1],frames[2],Rect2i(165,65,360,340)) > 30,"GPU renders distinct original-sword celebration poses")
		smith._interrupt_sword_attack()
