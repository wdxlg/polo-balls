extends "res://tests/test_ding_sleep.gd"
func reset_cat() -> void:
	cat._damage_output_disabled_until_msec=0
	cat.dizziness=false
	cat.awake=false
	cat._reset_z_pose()
	cat.sleep_left=60
	cat._burst_wait=100
	cat.global_position=Vector2.ZERO
	cat._sync_wave(false)
func run() -> void:
	create_timer(35).timeout.connect(func():print("DING_BOUNDARY_TIMEOUT");quit(2))
	game=root.get_node("Game");game.now_stop_state=false;game.Game_Settings.Have_Team_Damage=false
	AudioServer.set_bus_mute(0,true)
	arena=Node2D.new();root.add_child(arena);current_scene=arena
	node_added.connect(heard)
	cat=load(CAT_PATH).instantiate();cat.Team="Team0";arena.add_child(cat)
	cat.direction=Vector2.RIGHT
	await create_timer(0.3).timeout
	check(cat.global_position.length()>10.0,"normal movement runs in real physics, not a stationary caster")
	cat.state_machine.set_physics_process(false);reset_cat()
	var enemy:Node2D=target(Vector2(120,0),100)
	enemy.max_block=500;enemy.block=500
	var z:Node2D=shot()
	await physics_frame
	z.move(220,1.0)
	check(enemy.health==100 and enemy.block<500,"ordinary Z uses public block instead of bypassing it")
	check(not enemy.dizziness,"blocked/no effective HP damage has no stun")
	await flush()
	check(sounds.get("entity.player.hurt",0)==0,"blocked Z has no MC damage sound")
	enemy.health=37;enemy.Damage_reduction=999;enemy.block=500
	cat._wake();cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time);cat.step_sleep(0.4)
	check(enemy.health==0 and enemy.block==500,"wake uses CURRENT 37 HP and bypasses block/reduction")
	await flush()
	reset_cat()
	var absorbing:Node2D=target(Vector2(100,0),80)
	var status:Variant=load("res://scripts/effects/我的世界/mc_status_effects.gd")
	check(status.apply_effect(absorbing,"absorption",1,30,cat),"shared absorption fixture attached")
	await flush()
	var shield:Node=absorbing.get_node("MinecraftStatus_absorption")
	var amount:float=shield.absorption_remaining
	cat._wake();cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time);cat.step_sleep(0.3)
	check(absorbing.health==mini(int(amount),80),"raw-health wave retains shared absorption policy")
	check(cat.get_ai_attack_threats(absorbing).is_empty(),"already-hit target no longer receives wave threat")
	absorbing.queue_free();await flush();reset_cat()
	var other:Node2D=target(Vector2(100,0),100)
	cat._wake();cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time);cat.apply_damage_disable(1.0);cat.step_sleep(0.3)
	check(other.health==100 and cat.get_ai_attack_threats(other).is_empty(),"damage disable suppresses live wave and threat")
	reset_cat()
	var wall:=StaticBody2D.new();wall.collision_layer=1;wall.collision_mask=0;wall.position=Vector2(50,0)
	var collider:=CollisionShape2D.new();var shape:=RectangleShape2D.new();shape.size=Vector2(8,120)
	collider.shape=shape;wall.add_child(collider);arena.add_child(wall)
	await physics_frame
	cat._wake();cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time);cat.step_sleep(0.4)
	check(other.health==100,"public wall occlusion blocks wave health damage")
	check(cat.get_ai_attack_threats(other).is_empty(),"occluded receiver has no declared wave threat")
	z=shot();z.move(220,1.0)
	check(z._spent and other.health==100,"Z expires at wall instead of tunneling")
	wall.queue_free();other.queue_free();await flush();reset_cat()
	var reflector:Node2D=target(Vector2(100,0),100)
	z=shot()
	var protocol:Variant=load("res://classes/projectile_interactions.gd")
	for capability:String in ["reflect","capture","block","predict","wool"]:
		check(protocol.supports(z,capability),"public projectile capability "+capability)
	check(protocol.reflect(z,reflector,20.0),"public reflection accepts Z")
	check(protocol.team_of(z)==reflector.Team and z.direction.x<0.0,"reflection updates faction and reverses actual velocity")
	z.expire();reflector.queue_free();await flush();reset_cat()
	cat._burst_wait=0;cat.player_control_peer_id=1;cat.controlled_burst()
	cat.apply_stun(0.1,cat)
	cat.step_sleep(0.2)
	check(cat._shots_left==0,"stun interrupts remaining burst shots")
	await clear_shots()
	await create_timer(0.15).timeout
	reset_cat()
	cat._emit_sound("sleep");await flush()
	var ref:WeakRef=cat._ambient_ticket.get("player")
	var player:AudioStreamPlayer2D=ref.get_ref()
	game.now_stop_state=true;cat._process(0)
	check(player.stream_paused,"game pause freezes current native sleep stream")
	game.now_stop_state=false;cat._process(0)
	check(not player.stream_paused,"unpause resumes existing stream without overlap")
	cat._wake();cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time);await flush()
	check(not is_instance_valid(player),"wake cancels real ongoing sleep stream")
	reset_cat();await flush()
	var edge:Node2D=target(Vector2(330,0),50)
	var hurt:CollisionShape2D=edge.self_hurtbox.get_node("CollisionShape2D")
	edge.position.x=320.0+3.5+hurt.shape.get_rect().size.x*hurt.global_scale.x*0.5-0.5
	await physics_frame
	cat._wake();cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time);cat.step_sleep(0.79)
	check(edge.health==50,"edge fixture is outside penultimate swept radius")
	cat.step_sleep(0.02)
	check(edge.health==0,"last radius interval is swept even when delta crosses duration")
	if is_instance_valid(edge):edge.queue_free()
	cat.queue_free();await create_timer(1.1).timeout
	for n:Node in get_nodes_in_group("BattleTransient"):n.queue_free()
	await flush()
	check(get_nodes_in_group("DingWakeWave").is_empty() and get_nodes_in_group("DingSleepZ").is_empty(),"battle transient cleanup leaves no projectile or wave")
	arena.queue_free();await flush()
	print("DING_BOUNDARIES_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
