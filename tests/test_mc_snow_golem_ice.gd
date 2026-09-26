extends "res://tests/test_mc_snow_golem.gd"
func close_vec(a:Vector2,b:Vector2) -> bool: return a.distance_to(b) < 0.001
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(45.0).timeout.connect(func(): finish(2))
	var source:Node2D = spawn(GOLEM_PATH,center-Vector2(192,0))
	source._field.set_physics_process(false)
	var victim:Node2D = spawn("res://scenes/characters/我的世界/苦力怕.tscn",center,"Team1")
	var cold:Node2D = COLD.ensure(victim)
	cold.add_cold(40.0,1.4)
	check(not is_instance_valid(cold._ice),"partial cold has whitening/flakes but no complete ice enclosure")
	var root_transform:Transform2D = victim.global_transform
	var hit_transform:Transform2D = victim.self_hitbox.global_transform
	var hurt_transform:Transform2D = victim.self_hurtbox.global_transform
	var graphics_transform:Transform2D = victim.graphics.transform
	cold.add_cold(60.0,1.4)
	cold.set_physics_process(false)
	cold.set_process(false)
	var shell:Node2D = cold._ice
	shell.set_process(false)
	check(is_instance_valid(shell) and shell.enclosed and shell.visible and shell.is_in_group("MCSnowIce"),"full cold creates a visible ice enclosure immediately")
	check(shell.ICE.resource_path.ends_with("/ice.png") and shell.ICE.get_size() == Vector2(16,16) and shell.CRACKS.size() == 10,"enclosure and cracking use the native Minecraft block textures")
	check(shell.get_child_count() == 0 and not shell is CollisionObject2D,"ice is pure visual geometry, not a new blocking body or hitbox")
	check(cold.amount == 0.0 and is_equal_approx(cold.freeze_total,1.4) and victim.dizziness,"meter reset and the original freeze duration/control lock are preserved")
	check(shell._mode == 1,"standard character uses the independent vertex-offset shader channel")
	check(shell.world_bounds.encloses(shell._body_rect()),"native ice enclosure contains the visible body bounds")
	check(shell.shake_strength(0.05) < shell.shake_strength(0.5) and shell.shake_strength(0.5) < shell.shake_strength(0.95),"shake envelope increases as remaining freeze time decreases")
	check(is_equal_approx(shell.shake_strength(1.0),shell.MAX_SHAKE),"maximum tremor is bounded in world pixels")
	cold.advance(0.2)
	shell.refresh()
	check(is_equal_approx(shell.progress,0.2/1.4) and shell.crack_stage() == -1,"early freeze uses light tremor before block cracks appear")
	var early:Vector2 = shell.shake_world
	cold.advance(0.071)
	shell.refresh()
	check(not close_vec(early,shell.shake_world),"frozen body changes its visual offset continuously rather than remaining a static overlay")
	check(victim.global_transform == root_transform and victim.self_hitbox.global_transform == hit_transform and victim.self_hurtbox.global_transform == hurt_transform,"tremor changes neither character root nor damage/collision transforms")
	check(victim.graphics.transform == graphics_transform,"ice shake does not overwrite the ordinary Graphics animation/stun transform")
	var actual_world_offset:Vector2 = victim.image.global_transform.basis_xform(shell._last_local)
	check(close_vec(actual_world_offset,shell.shake_world),"local shader conversion preserves requested world amplitude under character scale")
	var old_scale:Vector2 = victim.scale
	victim.scale *= 0.5
	shell.refresh()
	check(close_vec(victim.image.global_transform.basis_xform(shell._last_local),shell.shake_world),"mini/small scale does not make shake vanish or multiply physical motion")
	check(shell.world_bounds.encloses(shell._body_rect()),"ice refits the body when its visual scale changes")
	victim.scale = old_scale
	shell.refresh()
	var before:float = cold.frozen_left
	var frozen_offset:Vector2 = shell.shake_world
	game.now_stop_state = true
	cold.advance(10.0)
	shell._process(10.0)
	check(cold.frozen_left == before and shell.shake_world == frozen_offset,"gameplay pause stops both freeze countdown and tremor phase")
	game.now_stop_state = false
	paused = true
	cold.advance(10.0)
	shell._process(10.0)
	check(cold.frozen_left == before and shell.shake_world == frozen_offset,"SceneTree pause also holds the exact enclosure phase")
	paused = false
	cold.advance(cold.frozen_left-0.06)
	shell.refresh()
	check(shell.progress > 0.95 and shell.crack_stage() == 9,"last portion of freeze shows native near-breakage cracks")
	var held_id:int = shell.get_instance_id()
	cold.advance(0.061)
	check(cold.frozen_left == 0.0 and not victim.dizziness and not shell.enclosed,"timer end frees the character without extending gameplay freeze for the animation")
	check(shell.fragments.size() == 10 and shell.breakout_count == 1,"thaw creates one brief native-ice fragment release")
	check(close_vec(victim.image.get_instance_shader_parameter("snow_freeze_offset"),Vector2.ZERO),"thaw clears its per-instance visual shake immediately")
	check(victim.global_transform == root_transform and victim.graphics.transform == graphics_transform,"breakout restores visuals without displacing the unit")
	shell._process(0.1)
	var age:float = shell.fragments[0].age
	game.now_stop_state = true
	shell._process(2.0)
	check(shell.fragments[0].age == age,"pause also holds the outgoing ice fragments")
	game.now_stop_state = false
	shell._process(0.3)
	check(shell.fragments.is_empty() and not shell.visible and not shell.is_processing(),"breakout fragments expire and leave no idle drawing work")

	# Reuse must not accumulate jitter; independent ordinary stun remains intact.
	cold.add_cold(100.0,1.4)
	cold.set_physics_process(false)
	cold.set_process(false)
	check(cold._ice.get_instance_id() == held_id and cold._ice.fragments.is_empty(),"a later freeze reuses one clean shell instead of stacking overlays")
	var baseline_graphics:Vector2 = victim.graphics.position
	victim.begin_stun_visual()
	victim._update_stun_shake_visual(0.045)
	var other_offset:Vector2 = victim.graphics.position
	cold.advance(0.8)
	shell.refresh()
	check(victim.graphics.position == other_offset and other_offset != baseline_graphics,"ice tremor coexists with ordinary stun's independent Graphics offset")
	cold.advance(0.61)
	check(victim.graphics.position == other_offset and victim._stun_visual_ref_count == 1,"ice release cannot cancel an unrelated stun visual")
	victim.end_stun_visual()
	check(close_vec(victim.graphics.position,baseline_graphics),"last ordinary stun releases its own offset without ice-induced drift")

	# Custom-material fallback still affects only drawing offset, not physical geometry.
	var custom:Node2D = dummy(center+Vector2(144,0))
	custom.image.material = null
	custom.image.offset = Vector2(7,-3)
	var custom_cold:Node2D = COLD.ensure(custom)
	custom_cold.add_cold(100.0,1.4)
	custom_cold.set_physics_process(false)
	custom_cold.set_process(false)
	var custom_shell:Node2D = custom_cold._ice
	custom_shell.set_process(false)
	check(custom_shell._mode == 2,"non-shared material has a visual-only Sprite offset fallback")
	custom_cold.advance(0.8)
	custom_shell.refresh()
	check(custom.image.offset != Vector2(7,-3) and custom.global_position == center+Vector2(144,0),"fallback visibly trembles without moving the actor")
	var new_anchor := Vector2(13,-9)
	custom.image.offset = new_anchor
	custom_shell.refresh()
	custom_cold.advance(1.0)
	check(close_vec(custom.image.offset,new_anchor),"thaw preserves a new anchor written by another animation instead of restoring a stale baseline")

	# Visual replicas need the actual total duration for a correct late-join phase.
	# Minis are now cold-immune; use a susceptible replica to test the freeze timeline.
	var client:Node2D = dummy(center+Vector2(0,120),"Team1")
	var mirrored:Node2D = COLD.ensure(client)
	mirrored.set_multiplayer_authority(2)
	mirrored.accept_state(0.0,0.3,1.4)
	mirrored.set_process(false)
	mirrored._ice.set_process(false)
	check(is_equal_approx(mirrored._ice.progress,1.0-0.3/1.4) and mirrored._ice.crack_stage() >= 6,"late visual state joins the correct late-freeze tremor/crack phase")
	mirrored.accept_state(0.0,0.2,1.4)
	check(mirrored._ice.progress > 0.85 and mirrored._ice.breakout_count == 0,"periodic synchronization advances the escape instead of restarting it")
	mirrored._process(0.21)
	check(not mirrored._ice.enclosed and mirrored._ice.breakout_count == 1,"replica also removes the shell and releases its visual shake at thaw")

	var resistant:Node2D = dummy(center+Vector2(144,120))
	resistant.negative_effect_ratio = 0.5
	var reduced:Node2D = COLD.ensure(resistant)
	reduced.add_cold(200.0,1.4)
	reduced.set_physics_process(false)
	reduced.set_process(false)
	check(is_equal_approx(reduced.freeze_total,0.7),"visual timeline respects actual immunity-reduced freeze duration")
	resistant.negative_effect_ratio = 0.0
	reduced.advance(0.01)
	check(not reduced._ice.enclosed and reduced._ice.fragments.is_empty() and not resistant.dizziness,"gaining immunity cancels enclosure and jitter without a lingering lock")
	cold.add_cold(100.0,1.4)
	cold.set_physics_process(false)
	cold._ice.refresh()
	var current_shell:WeakRef = weakref(cold._ice)
	world.reset()
	await process_frame
	await process_frame
	check(not is_instance_valid(current_shell.get_ref()) and get_nodes_in_group("MCSnowIce").is_empty(),"ordinary battle reset clears ice shells, shards and visual offsets with their victims")
	print("SNOW_ICE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
