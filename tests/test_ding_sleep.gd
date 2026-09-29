extends SceneTree
const CAT_PATH:String="res://scenes/characters/默认/丁某人睡觉.tscn"
const Z_PATH:String="res://scenes/shooter/默认/丁某人_Z.tscn"
var checks:int=0
var failures:int=0
var arena:Node2D
var cat:Variant
var game:Node
var sounds:Dictionary={}
var sound_players:Array[WeakRef]=[]
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func heard(node:Node) -> void:
	if node is AudioStreamPlayer2D and node.has_meta("mc_sound_event"):
		var event:String=node.get_meta("mc_sound_event")
		sounds[event]=int(sounds.get(event,0))+1
		sound_players.append(weakref(node))
func flush() -> void:
	await process_frame
	await process_frame
func clear_shots() -> void:
	for shot:Node in get_nodes_in_group("DingSleepZ"): shot.queue_free()
	await flush()
func target(point:Vector2,hp:int=200,team:String="Team1") -> Node2D:
	var unit:Node2D=load("res://scenes/ball.tscn").instantiate()
	unit.Max_health=hp
	unit.Team=team
	unit.Health_Restore=0
	unit.Has_Collision_Damage=false
	unit.Can_Attack=false
	unit.Can_Skill=false
	unit.disable_mode=CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(unit)
	unit.global_position=point
	unit.state_machine.set_physics_process(false)
	return unit
func shot(point:Vector2=Vector2.ZERO) -> Node2D:
	var z:Node2D=load(Z_PATH).instantiate()
	z.Master=cat
	z.Team=cat.Team
	z.direction=Vector2.RIGHT
	arena.add_child(z)
	z.global_position=point
	z.state_machine.set_physics_process(false)
	return z
func run() -> void:
	create_timer(55).timeout.connect(func(): print("DING_TIMEOUT"); quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Have_Team_Damage=false
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	var camera:=Camera2D.new()
	camera.position=Vector2(100,0)
	camera.zoom=Vector2(2,2)
	arena.add_child(camera)
	node_added.connect(heard)
	var indexer:Variant=load("res://scripts/world.gd").new()
	indexer._ensure_character_path_index()
	check(indexer._character_paths_by_folder.get("默认",{}).get("丁某人睡觉","")==CAT_PATH,"production character index includes Ding in Default")
	indexer.free()
	var packed:PackedScene=load(CAT_PATH)
	check(packed!=null,"production scene loads")
	if packed==null: quit(1); return
	cat=packed.instantiate()
	check(cat.has_method("begin_burst"),"derived script compiles")
	if not cat.has_method("begin_burst"): cat.free(); quit(1); return
	cat.Team="Team0"
	arena.add_child(cat)
	cat.state_machine.set_physics_process(false)
	await flush()
	check(cat.Max_health==1000 and cat.health==1000 and cat.Damage==1,"1000 HP and base 1 damage")
	check(is_equal_approx(cat.scale.x,0.14) and cat.scale==Vector2(0.14,0.14) and cat.Speed==100.0,"smaller 70 percent body and slower 100 speed")
	check(not cat.awake and cat.sleep_left==60.0 and cat.image.texture==cat.CLOSED,"spawns asleep at 60")
	check(cat._counter.visible and cat._counter.text=="60" and cat._counter.position.x>0 and cat._counter.position.y<0,"small counter is upper right")
	check(not cat.has_collision_damage() and not cat.self_hitbox.monitoring,"no accidental body attack")
	check(cat.OPEN.get_size()==cat.CLOSED.get_size(),"eye frames have identical normalized bounds")
	check(cat.player_control_action_ids()==[&"controlled_burst"],"one actual C-control action, no fake wake key")
	check(not cat.player_control_action_hold_repeat_allowed(0),"hold does not spam burst")
	var info:Dictionary=cat.get_combat_classification()
	check(info.entity_kind=="character" and info.carriers==["projectile"],"sleep stage classification")
	check(not cat.get_armor_test_effect_summary().is_empty(),"localized ability summary available")
	var enemy:Node2D=target(Vector2(160,0))
	await physics_frame
	for i:int in range(239): cat.step_sleep(1.0/60.0)
	check(cat.shots_fired==0,"no burst before four seconds")
	cat.step_sleep(1.0/60.0+0.0001)
	check(cat.shots_fired==0 and cat.z_pose_phase==1,"four seconds starts squash windup before any Z")
	cat.step_sleep(cat.z_windup_time)
	check(cat.shots_fired==1,"first Z after squash windup")
	for i:int in range(3):
		cat.step_sleep(0.2)
		check(cat.shots_fired==i+2,"four-shot cadence 0.2 seconds")
	check(cat._shots_left==0 and not cat.begin_burst(Vector2.RIGHT),"burst ends after four and respects cooldown")
	await flush()
	check(sounds.get("user.ding_sleep.z_start",0)==1,"four Z share one user snore start sound")
	check(cat.AUDIO.EVENTS.z.size()==2,"two supplied snore variations registered")
	check(sounds.get("block.bubble_column.bubble_pop",0)==0,"old per-shot bubble sound removed")
	await clear_shots()
	cat._burst_wait=0
	cat.player_control_peer_id=1
	var old:int=cat.shots_fired
	cat.step_sleep(0.5)
	check(cat.shots_fired==old,"C-control disables automatic active attack")
	cat.controlled_burst()
	cat.step_sleep(cat.z_windup_time)
	check(cat.shots_fired==old+1,"manual action starts real burst")
	await clear_shots()
	cat._shots_left=0
	cat.player_control_peer_id=0
	var saved:float=cat.sleep_left
	game.now_stop_state=true
	cat.step_sleep(1.0)
	check(cat.sleep_left==saved,"game pause freezes countdown")
	game.now_stop_state=false
	cat._burst_wait=0
	cat.dizziness=true
	check(not cat.begin_burst(Vector2.RIGHT),"stun prevents initiating Z burst")
	cat.sleep_left=0.01
	cat.step_sleep(0.02)
	check(not cat.awake and cat._counter.text=="0","stunned pending wake waits visibly at zero")
	cat.dizziness=false
	cat.sleep_left=30
	cat._burst_wait=100
	var z:Node2D=shot()
	await physics_frame
	check(z.get_combat_classification().entity_kind=="projectile","Z uses public projectile classification")
	z.move(220,1.0)
	check(enemy.health==199,"swept fast Z inflicts exactly one effective damage")
	check(enemy.dizziness,"Z applies public 0.1 second stun on damage")
	await flush()
	check(int(sounds.get("entity.player.hurt",0))==1,"one MC ordinary hit sound, not duplicate")
	await create_timer(0.15).timeout
	check(not enemy.dizziness,"0.1 second stun expires")
	cat.Damage=3
	z=shot()
	await physics_frame
	check(is_equal_approx(z.attack_damage(),3.0),"Z reads current owner's attack attributes")
	cat.Damage=1
	check(is_equal_approx(z.attack_damage(),1.0),"in-flight Z follows changed attack attributes")
	z.expire()
	await flush()
	var ally:Node2D=target(Vector2(100,100),200,"Team0")
	var foe:Node2D=target(Vector2(210,100),200)
	z=shot(Vector2(0,100))
	await physics_frame
	z.move(220,1.0)
	check(ally.health==200 and foe.health==199,"Z ignores ally and hits later enemy")
	await flush()
	z=shot(Vector2(0,-100))
	var angular_before:float=z.direction.angle()
	z.tick_physics(1,0.1)
	check(absf(angle_difference(angular_before,z.direction.angle()))<=deg_to_rad(35.0)*0.1+0.0001,"gentle homing respects 35 degree per second turn cap")
	z.expire()
	await flush()
	enemy.queue_free();ally.queue_free();foe.queue_free()
	await flush()
	var near:Node2D=target(Vector2(100,0),77)
	var far:Node2D=target(Vector2(250,0),123)
	var safe:Node2D=target(Vector2(0,100),345,"Team0")
	cat.health=12
	cat.global_position=Vector2.ZERO
	cat.sleep_left=0.01
	cat._shots_left=0
	await physics_frame
	cat.step_sleep(0.02)
	check(cat.wave_charging and cat.wakes_fired==0 and not is_instance_valid(cat._wave),"zero begins charge without premature wave")
	cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time)
	check(cat.awake and not cat._counter.visible and cat.image.texture==cat.OPEN,"zero hides number and opens eyes")
	check(cat.wakes_fired==1 and is_instance_valid(cat._wave),"zero releases exactly one wave")
	info=cat.get_combat_classification()
	check(info.carriers==["area"],"awake stage classification")
	cat.step_sleep(0.3)
	check(near.health==0 and far.health==123,"expanding front uses each target current HP, not caster 12 HP")
	check(safe.health==345,"wave does not hurt ally")
	check(cat.get_ai_attack_threats(far).size()==48,"threat uses same 48 swept annulus segments")
	var fixed_origin:Vector2=cat._wave.global_position
	cat.global_position=Vector2(25,0)
	check(cat._wave.global_position==fixed_origin,"emitted wave stays at wake origin while body moves")
	near.health=77
	cat.step_sleep(0.01)
	check(near.health==77,"one hit per target per wave")
	cat.step_sleep(0.35)
	check(far.health==0,"far target hit only when front reaches it")
	await flush()
	check(int(sounds.get("entity.player.attack.crit",0))==2,"each effective wave hit over 50 uses shared crit audio once")
	cat.step_sleep(1.4)
	check(not cat.awake and cat.sleep_left==60.0 and cat._counter.visible,"two second awake window resets sleep/countdown")
	check(cat.wakes_fired==1,"awake interval never emits extra waves")
	if is_instance_valid(near): near.queue_free()
	if is_instance_valid(far): far.queue_free()
	if is_instance_valid(safe): safe.queue_free()
	await flush()
	cat.health=1000
	cat.sleep_left=0.01
	cat.step_sleep(0.02)
	cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time)
	check(cat.wakes_fired==2,"next sleep cycle can wake again")
	cat.step_sleep(2.1)
	for role:String in ["sleep","z","wake","hurt","death"]:
		var count:int=sound_players.size()
		cat._emit_sound(role)
		await flush()
		check(sound_players.size()>count,"native role allocates safe audio: "+role)
		var player:AudioStreamPlayer2D=sound_players.back().get_ref()
		check(player.stream.get_length()>0 and player.bus==&"GameplayRecord","native stream has duration and recording bus: "+role)
		if role=="death": check(is_equal_approx(player.pitch_scale,0.9),"native cat death pitch retained")
	cat._stop_ambient()
	await flush()
	check(not cat.AUDIO.QUEUE.channel_busy(cat._ambient_ticket),"wake/death can stop ongoing sleep voice")
	if DisplayServer.get_name()!="headless": await gpu_checks()
	var before_transients:int=get_nodes_in_group("BattleTransient").size()
	cat.Die()
	await flush()
	check(cat._dead and not cat._counter.visible and not cat.image.visible,"death stops attacks and hides original sprite/counter")
	check(get_nodes_in_group("BattleTransient").size()>before_transients,"Minecraft death pose detached from body lifecycle")
	cat.queue_free()
	if DisplayServer.get_name()!="headless":
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("user://ding_sleep_death.png")
	await create_timer(1.25).timeout
	await flush()
	check(not get_nodes_in_group("DingSleepZ").size(),"no persistent Z after cleanup")
	print("DING_SLEEP_RESULT checks=%d failures=%d renderer=%s" % [checks,failures,DisplayServer.get_name()])
	arena.queue_free()
	await flush()
	quit(0 if failures==0 else 1)
func gpu_checks() -> void:
	var bus:int=AudioServer.get_bus_index("GameplayRecord")
	var capture:=AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus,capture)
	for role:String in ["sleep","z","wake","hurt","death"]:
		for player:Node in get_nodes_in_group("MCNativeSFX"): player.stop(); player.queue_free()
		await flush()
		capture.clear_buffer()
		cat._emit_sound(role)
		await create_timer(0.3).timeout
		var pcm:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
		var peak:float=0.0
		for value:Vector2 in pcm: peak=maxf(peak,maxf(absf(value.x),absf(value.y)))
		check(peak>0.00001,"real recording PCM for "+role)
		print("DING_PCM role=%s frames=%d peak=%f" % [role,pcm.size(),peak])
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	cat.sleep_left=42
	cat.awake=false
	cat._refresh_visual()
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("user://ding_sleep_asleep.png")
	cat._wake()
	cat.step_sleep(cat.wave_windup_time+cat.wave_shiver_time)
	cat.wave_age=0.45
	cat._sync_wave(false)
	cat._refresh_visual()
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("user://ding_sleep_awake.png")
	check(true,"GPU frames rendered and captured")
