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
	check(smith.Damage == 100 and smith.sword_visual_scale >= 0.13 and smith.sword_swing_duration >= 0.44,"real villager keeps 100 base sword damage and enlarged readable swing")
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
