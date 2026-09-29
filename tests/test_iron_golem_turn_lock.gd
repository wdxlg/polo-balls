extends "res://tests/test_iron_golem_charge.gd"

func run() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("GOLEM_TURN_LOCK_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var g:Node2D = golem(Vector2.ZERO)
	g.companion.global_position = Vector2(500,300)
	var target:Node2D = enemy(Vector2(30,0))
	var rear:Node2D = enemy(Vector2(-30,0))
	await physics_frame
	await process_frame
	reset_attack(g)
	g.direction = Vector2.RIGHT
	check(g.begin_swing(target) and g.is_direction_change_locked(),"windup immediately locks direction changes")
	g.direction = Vector2.LEFT
	g.direction.x = -1.0
	g.set_character_visual_flip_h(false)
	check(g.direction==Vector2.RIGHT and g.current_attack_heading().is_equal_approx(Vector2.RIGHT),"direction writes and visual turns are discarded during windup")
	check(g.is_character_visual_flipped_h() and g.attack_facing_flipped_h,"windup preserves both displayed and replicated facing")
	var hp:int = target.health
	g.step_attack(0.25)
	check(g._phase==1 and target.health==hp,"rejected turns neither release charge nor cause early damage")
	g.release_swing()
	g.direction = Vector2.LEFT
	g.set_character_visual_flip_h(false)
	g.step_attack(g.IMPACT_TIME-0.001)
	check(target.health==hp,"damage still waits for the normal impact frame")
	g.step_attack(0.002)
	check(target.health<hp and rear.health==10000 and g.current_attack_heading().x>0.0,"impact hits the original front immediately, not a new direction or end-of-action settlement")
	clear_control(target)
	g.direction = Vector2.LEFT
	g.set_character_visual_flip_h(false)
	check(g.direction==Vector2.RIGHT and g.is_character_visual_flipped_h(),"post-impact recovery also ignores turns")
	hp = target.health
	g.step_attack(g.swing_duration)
	check(g._phase==0 and not g.is_direction_change_locked() and target.health==hp,"finishing recovery neither deals late damage nor keeps the turn lock")
	check(g.direction==Vector2.RIGHT and g.is_character_visual_flipped_h(),"attack end never replays discarded direction or visual requests")
	g.move(0.0,1.0/60.0)
	check(g.direction==Vector2.RIGHT and g.is_character_visual_flipped_h(),"first idle movement update has no hidden pending turn")
	g.direction = Vector2.LEFT
	g.move(0.0,1.0/60.0)
	check(g.direction==Vector2.LEFT and not g.is_character_visual_flipped_h(),"a fresh idle turn is accepted normally")
	# A real obstacle must still stop the body, but its reflection is not deferred.
	reset_attack(g)
	g.direction = Vector2.RIGHT
	g.begin_swing(target)
	var wall:StaticBody2D = wall_at(Vector2(12,0))
	await physics_frame
	await process_frame
	for phase:int in [1,2]:
		if phase==2: g.release_swing()
		g.global_position = Vector2.ZERO
		var collision:KinematicCollision2D = g.move_and_collide(Vector2(8,0))
		check(collision!=null and g.global_position.x<3.0,"real body collision still blocks travel in attack phase "+str(phase))
		if collision!=null: g.when_collide(g.Speed,collision)
		g.move(0.0,1.0/60.0)
		check(g.direction==Vector2.RIGHT and g.current_attack_heading().x>0.0,"real collision reflection is discarded in attack phase "+str(phase))
	wall.free()
	g.global_position = Vector2.ZERO
	g.step_attack(g.swing_duration+0.01)
	clear_control(target)
	check(g.direction==Vector2.RIGHT and g.is_character_visual_flipped_h(),"removing the obstacle before recovery ends proves there is no delayed bounce")
	# Player movement uses its own input field; it must not bypass or queue a turn.
	reset_attack(g)
	g.direction = Vector2.RIGHT
	g.set_player_control_peer(1)
	g.set_player_control_direction(Vector2.RIGHT)
	g.begin_swing(target)
	g.set_player_control_direction(Vector2.LEFT)
	check(g.player_control_direction==Vector2.RIGHT,"player turn input is ignored rather than recorded during charge")
	g.set_player_control_direction(Vector2.ZERO)
	check(g.player_control_direction==Vector2.ZERO,"releasing movement may still stop the player")
	g.set_player_control_direction(Vector2.LEFT)
	g.cancel_swing()
	check(g.player_control_direction==Vector2.ZERO and g.direction==Vector2.RIGHT,"canceling the attack does not replay rejected player inputs")
	g.set_player_control_direction(Vector2.LEFT)
	check(g.player_control_direction==Vector2.LEFT,"new input after cancellation is accepted")
	g.set_player_control_peer(0)
	# Pausing preserves the lock; interrupting a charge releases it without a replay.
	reset_attack(g)
	g.direction = Vector2.RIGHT
	g.begin_swing(target)
	game.now_stop_state = true
	g.direction = Vector2.LEFT
	g.step_attack(1.0)
	check(g._phase==1 and g.direction==Vector2.RIGHT,"pause does not consume windup or turn immunity")
	game.now_stop_state = false
	g.dizziness = true
	g.tick_physics(g.State.Move,0.01)
	check(g._phase==0 and not g.is_direction_change_locked() and g.direction==Vector2.RIGHT,"stun cancels without replaying old turns")
	g.dizziness = false
	g.direction = Vector2.LEFT
	check(g.direction==Vector2.LEFT,"new directions work after an interruption")
	# Other characters and the villager retain their ordinary direction behavior.
	target.direction = Vector2.LEFT
	g.companion.direction = Vector2.LEFT
	check(target.direction==Vector2.LEFT and g.companion.direction==Vector2.LEFT,"generic characters and the villager are not direction-locked")
	# Replicas use the reliable existing pose stream, not their local movement estimate.
	g.set_multiplayer_authority(2)
	g.visual_clip = "charge"
	g.attack_facing_flipped_h = true
	g.update_pair_visual()
	g.set_character_visual_flip_h(false)
	check(g.current_attack_heading().x>0.0 and g.is_direction_change_locked(),"replica windup follows authority facing even when local motion suggests a turn")
	g.visual_clip = "swing"
	g.attack_facing_flipped_h = false
	g.update_pair_visual()
	g.set_character_visual_flip_h(true)
	check(g.current_attack_heading().x<0.0 and g.is_direction_change_locked(),"replica swing accepts authoritative left-facing pose and ignores local flips")
	g.visual_clip = "idle"
	g.direction = Vector2.RIGHT
	g.set_character_visual_flip_h(true)
	check(not g.is_direction_change_locked() and g.current_attack_heading().x>0.0,"replica unlocks after the authoritative attack pose ends")
	var config:SceneReplicationConfig = g.get_node("PairSync").replication_config
	check(config.get_properties().has(NodePath(".:attack_facing_flipped_h")) and config.property_get_spawn(NodePath(".:attack_facing_flipped_h")),"locked facing is present in spawn and pose replication")
	g.set_multiplayer_authority(1)
	reset_attack(g)
	g.direction = Vector2.RIGHT
	g.begin_swing(target)
	g.health = 0
	check(not g.is_direction_change_locked(),"death cannot leave a character direction-locked")
	print("GOLEM_TURN_LOCK_RESULT checks=",checks," failures=",failures)
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	current_scene = null
	arena.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
