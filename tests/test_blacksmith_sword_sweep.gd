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
	print("BLACKSMITH_SWING_RESULT checks=%d failures=%d max_step_deg=%.2f ghost_count=%d distinct=%d" % [checks,failures,rad_to_deg(max_step),ghosts.size(),distinct.size()])
	current_scene = saved_scene
	arena.queue_free()
	backdrop.queue_free()
	game.now_stop_state = saved_stop
	root.size = saved_size
	await process_frame
	quit(1 if failures>0 else 0)

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
