extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	# Drain World background preloads before creating actor textures in the dummy renderer.
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	var man:Node2D = actor("雾中人",center-Vector2(180,0))
	var enemy:Node2D = dummy(center+Vector2(60,0))
	enemy.velocity = Vector2.RIGHT*5.0
	await physics_frame
	man.set_player_control_peer(0)
	man.set_process(true)
	man.state_machine.set_physics_process(true)
	Engine.time_scale = 3.0
	var start:Vector2 = man.global_position
	var start_hp:int = enemy.health
	var rage_seen:bool = false
	var peak_trails:int = 0
	var rush_states:Dictionary = {}
	var peak_mist:int = 0
	var min_clock:float = man.clock+14.0
	var max_clock:float = man.clock+22.0 # Bounded slack for random hidden-attack choices.
	while man.clock<max_clock and man.health>0:
		if man.clock>=min_clock and man.discovery_count>=1: break
		await physics_frame
		# After the rage chase, the opponent turns toward the stalker; no phase injection.
		if man.clock>9.0: enemy.velocity = enemy.global_position.direction_to(man.global_position)*5.0
		rage_seen = rage_seen or man.phase==man.Phase.RAGE
		peak_trails = maxi(peak_trails,man.eye_fx.trails.size())
		if man.phase==man.Phase.RAGE and not man.lightning_wait: rush_states[man.rush] = true
		peak_mist = maxi(peak_mist,man.charge_fx.motes.size())
	Engine.time_scale = 1.0
	man.state_machine.set_physics_process(false)
	check(man.global_position.distance_to(start)>40.0,"real physics AI follows instead of standing still")
	check(rage_seen,"real AI reaches rear sector and triggers rage without injected phase")
	check(enemy.health<start_hp,"real rage attacks damage its target")
	check(peak_trails>0 and peak_trails<=12,"moving eyes generate a bounded fading glow trail")
	check(man.discovery_count>=1 and man.health<=552,"being exposed after a real chase causes self damage and disappearance")
	check(man.fog.fog_alpha>0.4,"live shared fog reaches its visible opacity")
	check(rush_states.has(man.Rush.RETREAT) and rush_states.size()>=2,"real combat cycles hidden attacks through visible retreats")
	check(man.mist_casts==0 or (peak_mist>0 and peak_mist<=12),"mist rush emits a bounded cloud trail whenever it is used")
	check(man.rush_hits>=2 and start_hp-enemy.health>=90 and man.mist_casts+man.face_casts>=3,"rage repeats random hidden attacks for real damage")
	print("FOG MAN LIVE: damage=",start_hp-enemy.health," rage=",rage_seen," discoveries=",man.discovery_count," trails=",peak_trails," casts=",man.mist_casts,"/",man.face_casts," clock=",man.clock)
	finish(0 if failures==0 else 1)
