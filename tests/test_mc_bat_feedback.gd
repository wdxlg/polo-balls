extends "res://tests/test_mc_bat_transform.gd"
func clear_feedback() -> void:
	world._damage_focus_pending_strength = -1.0
	world._damage_focus_started_usec = 0
	world._damage_focus_next_usec = 0
	world._damage_shake_pending_peak = 0.0
	world._damage_shake_pending_sum = 0.0
	for n:Node in get_nodes_in_group("__damage_text_runtime"): n.free()
func eat_sounds() -> Array:
	return get_nodes_in_group("MCNativeSFX").filter(func(n:Node): return n.get_meta("mc_sound_event","") == "entity.generic.eat")
func run() -> void:
	var center:Vector2 = await setup_world()
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	b.state_machine.set_physics_process(false)
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,200),"Team1")
	enemy.state_machine.set_physics_process(false)
	enemy.Has_Collision_Damage = false
	enemy.self_hitbox.monitoring = false
	enemy.Max_health = 1000
	enemy.default_properties.Max_health = 1000
	enemy.health = 1000
	await physics_frame
	await process_frame
	pause_members(b)
	settle_fusion(b)
	clear_feedback()
	var conserved:Vector2i = totals(b)
	b.split_swarm()
	pause_members(b)
	check(totals(b) == conserved and b.living_members().size() == 5,"silent split still conserves both HP totals")
	check(world._damage_focus_pending_strength < 0.0,"150 to 30 split cannot request damage focus")
	check(world._damage_shake_pending_peak == 0.0 and world._damage_shake_pending_sum == 0.0,"split cannot request hit camera shake")
	check(get_nodes_in_group("__damage_text_runtime").is_empty(),"neither retained nor spawned bats produce damage/heal popups")
	check(not b.health_bar._bar_tweens.has(b.health_bar.health_bar),"split uses an instant health display, no fake damage countdown tween")
	check(not b.health_bar.suppress_floating_text and not b.health_bar.force_instant_update_once and not b._redistributing,"silent transaction restores normal feedback flags")
	await create_timer(0.3).timeout
	pause_members(b)
	check(get_nodes_in_group("__damage_text_runtime").is_empty(),"no delayed split popups appear")
	settle_fusion(b)
	clear_feedback()
	check(get_nodes_in_group("__damage_text_runtime").is_empty(),"fusion also avoids fake healing popups")
	b.take_damage(50,true)
	check(world._damage_focus_pending_strength >= 0.0,"real large damage still requests camera focus")
	check(world._damage_shake_pending_peak > 0.0,"real damage retains camera shake")
	check(not get_nodes_in_group("__damage_text_runtime").is_empty(),"real damage still creates floating text")
	b.assign_vitals(150,150)
	b.split_swarm()
	pause_members(b)
	BAT.BAT_AUDIO._last.erase("entity.generic.eat")
	var actual:int = b.drain_target(enemy)
	var sounds:Array = eat_sounds()
	check(actual == 2 and not sounds.is_empty(),"successful bat drain plays native eating audio")
	check(not sounds.is_empty() and is_equal_approx(sounds.back().volume_db,-2.0),"two actual damage now plays at -2 dB instead of -11 dB")
	check(BAT.feeding_volume_db(1) < BAT.feeding_volume_db(2) and BAT.feeding_volume_db(2) < BAT.feeding_volume_db(13) and BAT.feeding_volume_db(13) < BAT.feeding_volume_db(32),"feeding volume rises monotonically with actual damage")
	check(BAT.feeding_volume_db(1000000) == 2.0,"extreme damage retains the native +2 dB safety ceiling")
	for n:Node in eat_sounds(): n.free()
	settle_fusion(b)
	b.assign_vitals(150,150)
	enemy.health = 1000
	BAT.BAT_AUDIO._last.erase("entity.generic.eat")
	actual = b.drain_target(enemy)
	sounds = eat_sounds()
	check(actual == 13 and not sounds.is_empty() and is_equal_approx(sounds.back().volume_db,BAT.feeding_volume_db(13)),"vampire drain uses its larger actual damage for audio gain")
	for n:Node in eat_sounds(): n.free()
	enemy.health = 1
	BAT.BAT_AUDIO._last.erase("entity.generic.eat")
	actual = b.drain_target(enemy)
	sounds = eat_sounds()
	check(actual == 1 and not sounds.is_empty() and is_equal_approx(sounds.back().volume_db,-3.0),"overkill audio scales from one actual HP, not nominal attack")
	for n:Node in eat_sounds(): n.free()
	check(b.drain_target(enemy) == 0 and eat_sounds().is_empty(),"zero actual damage emits no feeding sound")
	finish(0 if failures == 0 else 1)
