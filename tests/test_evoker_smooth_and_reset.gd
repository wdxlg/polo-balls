extends "res://tests/test_mc_bat_transform.gd"
class ClosedCombat extends Node2D:
	func is_combat_runtime_active() -> bool: return false
func run() -> void:
	var center:Vector2 = await setup_world()
	var e:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center)
	e.state_machine.set_physics_process(false)
	await process_frame
	var a:Node = e.mc_native_animation
	a.set_process(false)
	e.mc_cast_animation(0.85)
	a.advance(0.4)
	check(a.current_clip == &"cast","spell stays raised during its intended duration")
	a.advance(0.5)
	check(a.current_clip == &"idle","spell lowers arms after expiry without needing a target")
	e.mc_cast_animation(0.85)
	var gate:Node2D = ClosedCombat.new()
	root.add_child(gate)
	current_scene = gate
	e._cached_world = null
	check(not e.is_combat_runtime_active(),"fixture really closes combat without pausing time")
	a.advance(0.9)
	check(a.current_clip == &"idle","pending spell lowers arms even after combat gate closes")
	current_scene = world
	gate.free()
	e.mc_cast_animation(0.85)
	e.dizziness = true
	a.advance(0.01)
	check(a.current_clip == &"idle" and a._cast_left == 0.0,"stun clears raised casting pose")
	e.dizziness = false
	e.on_battle_victory()
	a.advance(0.1)
	check(a.current_clip == &"celebrate","victory still plays original celebration")
	game.now_stop_state = true
	var left:float = a._evoker_celebrate_left
	a.advance(2.0)
	check(a._evoker_celebrate_left == left,"pause freezes bounded celebration")
	game.now_stop_state = false
	a.advance(1.6)
	check(e._victory_cheered and a.current_clip == &"idle","audio one-shot flag no longer holds arms up forever")
	e.on_battle_victory()
	a.advance(0.1)
	check(a.current_clip == &"idle","duplicate victory cannot restart the gesture")
	# Replica contract: missing terminal pose cannot leave a permanent cast.
	e.set_multiplayer_authority(2)
	a._remote_pose = "cast"
	a._evoker_remote_left = 0.6
	a.advance(0.2)
	check(a.current_clip == &"cast","client can display a leased authoritative pose")
	a.advance(0.5)
	check(a.current_clip == &"idle","client stale raised pose expires without another packet")
	e.set_multiplayer_authority(1)
	var fx:Node2D = load("res://scripts/effects/我的世界/mc_totem_effect.gd").new()
	world.add_child(fx)
	fx.setup(center,e)
	fx.set_process(false)
	check(fx.LIFETIME == 2.0,"native 40-tick activation duration")
	check(absf(fx.yaw_turns(1.0)-2.4999698804) < 0.00001,"native polynomial rotation midpoint")
	check(fx.item_scale(1.0) > fx.item_scale(0.0)*4.0,"native grow then settle envelope")
	var max_jump:float = 0.0
	for i:int in range(2000):
		var t:float = float(i)*0.001
		var x1:float = fx.item_scale(t)*cos(TAU*fx.yaw_turns(t))
		var x2:float = fx.item_scale(t+0.001)*cos(TAU*fx.yaw_turns(t+0.001))
		max_jump = maxf(max_jump,absf(x2-x1))
	check(max_jump < 0.065,"edge transitions have no minimum-width discontinuity")
	check(fx.item_position(0.001).distance_to(fx.item_position(0.0)) < 0.001,"launch starts without velocity snap")
	check(fx.item_position(fx.INTRO_SECONDS-0.001).distance_to(fx.item_position(fx.INTRO_SECONDS+0.001)) < 0.04,"launch-to-hover stays continuous")
	print("EVOKER_SMOOTH_RESULT checks=",checks," failures=",failures," max_width_delta_1ms=",max_jump)
	finish(0 if failures == 0 else 1)
