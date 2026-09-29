extends "res://tests/test_sulfur_cube_balance.gd"
## Native decoded streams + actual gameplay cue sites + real AudioEffectCapture PCM.
var AUDIO:Script
var NATIVE:Script
var victim:Node2D
var origin:Vector2
var capture:AudioEffectCapture
var capture_bus:int = -1
var capture_index:int = -1
var audition_frames:PackedVector2Array = PackedVector2Array()

func sounds(event:StringName) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sulfur_event",&"") == event: result.append(node)
	return result

func settle() -> void:
	await process_frame
	await process_frame

func clear_sounds() -> void:
	await settle()
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		node.stop()
		node.free()
	source._sound_time.clear()
	if source.get("_motion_audio_ticket") is Dictionary: source._motion_audio_ticket.clear()
	if capture != null: capture.clear_buffer()

func set_form(mode:int) -> void:
	source.fuse_left = 0.0
	source.set_block(source.Block.EMPTY)
	source.set_block(mode)
	await clear_sounds()

func pcm(label:String) -> void:
	await create_timer(0.12,true,false,true).timeout
	var frames:PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	var peak:float = 0.0
	for frame:Vector2 in frames: peak = maxf(peak,maxf(absf(frame.x),absf(frame.y)))
	check(frames.size()>128 and peak>0.00001,"actual recorded PCM is non-silent: "+label)
	audition_frames.append_array(frames)
	print("SULFUR_PCM event=",label," frames=",frames.size()," peak=",peak)

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): print("SULFUR_AUDIO_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	AUDIO = load("res://scripts/characters/我的世界/sulfur_cube_audio.gd")
	NATIVE = load("res://scripts/effects/我的世界/mc_native_audio.gd")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var stopped:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,false)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	origin = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	source = fighter("AudioRevisionCube",origin,true)
	source.set_process(false)
	source.Damage = 48.0
	source.default_properties.Damage = 48.0
	victim = fighter("AudioRevisionVictim",origin+Vector2(5,0))
	victim.scale = Vector2.ONE
	victim.block = 0.0
	victim.Damage_reduction = 0.0
	capture_bus = AudioServer.get_bus_index(&"GameplayRecord")
	check(capture_bus>=0,"native effects route through the actual game-recording bus")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 8.0
	capture_index = AudioServer.get_bus_effect_count(capture_bus)
	AudioServer.add_bus_effect(capture_bus,capture)
	await clear_sounds()

	var required:Array[StringName] = [&"absorb",&"eject",&"jump",&"squish",&"hurt",&"death",&"bounce",&"ice_hit",&"magma_hit",&"honey_grab",&"honey_release",&"iron_hit",&"tnt_hit",&"ice_form",&"magma_form",&"honey_form",&"iron_form",&"tnt_form",&"amethyst_grow",&"amethyst_hit",&"amethyst_launch",&"amethyst_break",&"ice_crack",&"ice_break",&"magma_sizzle",&"fuse",&"explosion",&"entity.player.hurt",&"entity.player.attack.crit"]
	for event:StringName in required:
		check(AUDIO.EVENTS.has(event),"native cue bank registers "+String(event))
	var loaded:bool = true
	for variants:Array in AUDIO.EVENTS.values():
		for stream:AudioStream in variants:
			loaded = loaded and stream != null and stream.get_length()>0.0 and not stream.resource_path.is_empty()
	check(loaded,"every selected native sound really loads and decodes with a positive duration")
	check(source.mc_ambient_event().is_empty() and not AUDIO.EVENTS.has(&"ambient") and not AUDIO.EVENTS.has(&"breathing"),"explicit user exception: no breathing or ambient bank/loop")
	for i:int in range(20): source.mc_tick_ambient(1.0)
	await settle()
	check(get_nodes_in_group("MCNativeSFX").is_empty(),"twenty seconds of stationary ambient polling stay silent")

	var forms:Array[StringName] = [&"",&"ice_form",&"magma_form",&"honey_form",&"iron_form",&"tnt_form",&"amethyst_grow"]
	for mode:int in range(1,7):
		source.fuse_left = 0.0
		source.set_block(source.Block.EMPTY)
		await clear_sounds()
		source.set_block(mode)
		await settle()
		check(sounds(forms[mode]).size()==1,"acquiring block %d has its own one-shot material cue" % mode)
		if mode==source.Block.TNT: check(sounds(&"fuse").size()==1,"TNT arms exactly one original fuse without a breathing loop")
		await pcm(String(forms[mode]))
		var before:int = sounds(forms[mode]).size()
		source.set_block(mode)
		await settle()
		check(sounds(forms[mode]).size()==before,"unchanged block %d does not replay its insertion cue" % mode)

	await set_form(source.Block.HONEY)
	victim.global_position = source.global_position+Vector2(5,0)
	var hp:float = victim.health
	source._pull_touching_enemies(0.0)
	await settle()
	check(sounds(&"honey_grab").size()==1,"a real successful honey capture plays the native sticky contact")
	check(victim.health==hp and sounds(&"entity.player.hurt").is_empty() and sounds(&"entity.player.attack.crit").is_empty(),"non-damaging honey capture does not pretend to be a damage hit")
	await pcm("honey_grab")
	await clear_sounds()
	for i:int in range(20): source._pull_touching_enemies(0.02)
	await settle()
	check(sounds(&"honey_grab").is_empty(),"refreshing an existing grab cannot spam a new sticking sound")
	source._pull_touching_enemies(0.6)
	await settle()
	check(sounds(&"honey_release").size()==1,"the one-second deadline produces one disconnect cue")
	await pcm("honey_release")
	await clear_sounds()
	for i:int in range(20): source._pull_touching_enemies(0.02)
	await settle()
	check(sounds(&"honey_grab").is_empty() and sounds(&"honey_release").is_empty(),"continued expired overlap produces neither recapture nor repeated release sounds")

	await set_form(source.Block.ICE)
	var tile:Node2D = floor_tile(Rect2(origin-Vector2(12,12),Vector2(24,24)))
	tile.age = tile.CRACK_START-0.01
	tile._physics_process(0.02)
	await settle()
	check(sounds(&"ice_crack").size()==1,"real crack-state transition produces a quiet native contact tick")
	await pcm("ice_crack")
	await clear_sounds()
	for i:int in range(8): tile._physics_process(0.05)
	await settle()
	check(sounds(&"ice_crack").is_empty(),"crack texture updates do not restart the sound every frame")
	tile.age = tile.LIFETIME-0.01
	tile._physics_process(0.02)
	await settle()
	check(sounds(&"ice_break").size()==1,"real trail expiry makes a glass/ice shatter cue after the tile is deleted")
	await pcm("ice_break")
	await clear_sounds()
	for i:int in range(16):
		var batch:Node2D = floor_tile(Rect2(origin+Vector2(i*24,0),Vector2(24,24)))
		batch._break_tile()
	await settle()
	check(sounds(&"ice_break").size()==1,"a simultaneous row of broken trail cells is coalesced instead of sixteen overlapping cracks")

	await set_form(source.Block.IRON)
	source._start_single_slam()
	await settle()
	check(sounds(&"iron_form").size()==1,"iron slam startup has its native heavy-material push cue")
	await clear_sounds()
	source._slam_time = 0.81
	source._step_single_slam(0.02)
	await settle()
	check(sounds(&"iron_land").is_empty() and not AUDIO.EVENTS.has(&"iron_land"),"user-removed iron landing stays silent while slam mechanics remain intact")

	await set_form(source.Block.AMETHYST)
	source._native_model.animate(0.0,0.3,true,0.0)
	source._release_crystals()
	await settle()
	check(sounds(&"amethyst_launch").size()==1,"one volley has one crystal-launch cue, not one per shard")
	await pcm("amethyst_launch")
	for node:Node in world.get_children():
		if node.get_script()==source.SHARD: node.queue_free()
	await clear_sounds()
	source.crystals_out = true
	source._crystal_timer = 0.01
	source.tick_physics(source.State.Stand,0.02)
	await settle()
	check(sounds(&"amethyst_grow").size()==1,"actual crystal regrowth has its own native cluster-place cue")
	await pcm("amethyst_grow")

	await set_form(source.Block.MAGMA)
	victim.fire_effect_ratio = 1.0
	victim.global_position = source.global_position+Vector2.UP*(source.get_crowd_separation_radius_world()+victim.get_crowd_separation_radius_world()-0.1)
	source._next_hit_at["%d:%d" % [source.Block.MAGMA,victim.get_instance_id()]] = source._clock+100.0
	source._top_hit_at.clear()
	hp = victim.health
	source._pulse_block_contact(source.Block.MAGMA)
	await settle()
	check(victim.health<hp and sounds(&"magma_sizzle").size()==1,"real hot-top damage triggers a restrained lava-pop cue without another body/burn hit")
	await pcm("magma_sizzle")
	await set_form(source.Block.TNT)
	victim.global_position = source.global_position+Vector2(20,0)
	source._detonate()
	source._detonate()
	await settle()
	check(sounds(&"explosion").size()==1,"a real TNT detonation has one explosion layer and a consumed TNT cannot replay it")
	await pcm("explosion")
	for retained_mode:int in [source.Block.IRON,source.Block.ICE]:
		await set_form(source.Block.HONEY)
		victim.global_position = source.global_position+Vector2(5,0)
		source._pull_touching_enemies(0.0)
		source.acquire_block(retained_mode)
		await clear_sounds()
		source._on_honey_wall_impact(170.0,victim.global_position,victim)
		await settle()
		var impact:StringName = &"iron_hit" if retained_mode==source.Block.IRON else &"ice_hit"
		check(sounds(impact).size()==1,"retained trait wall callback plays the actual iron/ice material, never a separate honey damage sound")

	# The actual hurt threshold, current defenses and uncapped gain policy remain shared.
	await set_form(source.Block.EMPTY)
	for amount:float in [1.0,50.0,51.0,200.0]:
		await clear_sounds()
		var applied:bool = source._damage_with_impact(victim,amount,victim.global_position)
		await settle()
		var event:StringName = &"entity.player.attack.crit" if amount>50.0 else &"entity.player.hurt"
		var clips:Array[Node] = sounds(event)
		check(applied and clips.size()==1,"one effective %s damage result has exactly one correct normal/critical sound" % amount)
		if not clips.is_empty():
			check(is_equal_approx(clips[0].volume_db,source.sulfur_impact_gain(amount)) and clips[0].volume_db>=0.0,"actual damage gain starts at default level and follows the shared live-damage policy")
		await pcm("damage_"+str(amount))
	await clear_sounds()
	victim.Damage_reduction = 0.5
	source._damage_with_impact(victim,80.0,victim.global_position)
	await settle()
	check(sounds(&"entity.player.hurt").size()==1 and sounds(&"entity.player.attack.crit").is_empty(),"80 raw reduced to40 uses actual health loss, not a false critical")
	victim.Damage_reduction = 0.0
	await clear_sounds()
	victim.Team = source.Team
	source._damage_with_impact(victim,60.0,victim.global_position)
	await settle()
	check(get_nodes_in_group("MCNativeSFX").is_empty(),"rejected friendly damage does not play material or damage feedback")
	victim.Team = "Team1"

	await clear_sounds()
	game.now_stop_state = true
	source._emit_sound(&"ice_hit")
	await settle()
	check(get_nodes_in_group("MCNativeSFX").is_empty(),"paused gameplay does not start a cue")
	game.now_stop_state = false
	source.set_multiplayer_authority(2)
	source._emit_sound(&"ice_hit")
	await settle()
	check(get_nodes_in_group("MCNativeSFX").is_empty(),"a non-authoritative actor cannot originate gameplay audio RPCs")
	source.set_multiplayer_authority(1)
	await set_form(source.Block.EMPTY)
	source.first_block_delay = 100.0
	source._previous_motion_position = source.global_position
	source._motion_sample_valid = true
	source.Speed = 600.0
	source._hop_timer = 0.0
	for i:int in range(10): source.tick_physics(source.State.Stand,0.02)
	await settle()
	check(sounds(&"jump").is_empty() and sounds(&"squish").is_empty(),"a large Speed value without real displacement cannot produce footsteps")
	victim.global_position = origin+Vector2(60,60)
	source.player_control_direction = Vector2.RIGHT
	source.Repel = Vector2.ZERO
	var start:Vector2 = source.global_position
	await physics_frame
	source.move(170.0/source.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,1.0/60.0)
	source._hop_timer = 0.0
	source.tick_physics(source.State.Stand,1.0/60.0)
	await settle()
	check(source.global_position.distance_to(start)>0.2 and sounds(&"jump").size()==1,"genuine Move displacement starts the native movement cue even for the empty shell")
	await check_queue_and_motion()

	# Native death supplements the existing project bell; lifecycle cancellation is tested separately.
	await clear_sounds()
	check(not source.Dead_Audio.is_empty(),"native death does not replace the default project death bell")
	var bell:AudioStreamPlayer = root.get_node("Audios").Sfx.get_node_or_null(source.Dead_Audio) as AudioStreamPlayer
	if bell != null: bell.stop()
	source.Die()
	source.Die()
	await settle()
	check(bell != null and bell.playing,"the real default project death bell starts alongside the native creature voice")
	check(sounds(&"death").size()==1,"the actual death callback plays one native voice and repeated Die cannot replay it")
	await pcm("native_death")
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.stereo = true
	wave.mix_rate = AudioServer.get_mix_rate()
	var bytes:PackedByteArray = PackedByteArray()
	bytes.resize(audition_frames.size()*4)
	for i:int in range(audition_frames.size()):
		bytes.encode_s16(i*4,roundi(clampf(audition_frames[i].x,-1.0,1.0)*32767.0))
		bytes.encode_s16(i*4+2,roundi(clampf(audition_frames[i].y,-1.0,1.0)*32767.0))
	wave.data = bytes
	wave.save_to_wav("user://sulfur_audio_actual_pcm.wav")
	print("SULFUR_AUDIO_PCM_FILE ",ProjectSettings.globalize_path("user://sulfur_audio_actual_pcm.wav"))
	AudioServer.remove_bus_effect(capture_bus,capture_index)
	world.queue_free()
	await settle()
	await create_timer(0.25,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("SULFUR_AUDIO_REVISION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func check_queue_and_motion() -> void:
	check(NATIVE.has_method("queue_stream"),"native shared library exposes whole-operation deferred playback")
	if not NATIVE.has_method("queue_stream"): return
	await clear_sounds()
	var legacy:AudioStreamPlayer2D = NATIVE.play(source,"entity.spider.hurt",origin,-4.0)
	check(is_instance_valid(legacy) and legacy.is_inside_tree() and legacy.playing and is_equal_approx(legacy.volume_db,-4.0),"existing public native play keeps its immediate-player and gain contract")
	await clear_sounds()
	var rng_state:int = source._random.state
	for i:int in range(12): AUDIO.choose_variant(&"ice_hit")
	check(source._random.state==rng_state,"sound variant choice does not consume the character's gameplay RNG")
	var ticket:Dictionary = source._emit_sound(&"jump")
	check(not ticket.is_empty() and get_nodes_in_group("MCNativeSFX").is_empty(),"a queued cue allocates no unattached player while the scene child list may be busy")
	check(source._emit_sound(&"squish").is_empty(),"movement channel cannot overlap even while its first sound is pending")
	await settle()
	check(ticket.state=="playing" and sounds(&"jump").size()==1,"deferred cue actually attaches and starts on the following idle boundary")
	var player:AudioStreamPlayer2D = ticket.player.get_ref()
	check(source._emit_sound(&"squish").is_empty(),"landing waits for the actual selected jump clip instead of a guessed fixed duration")
	await create_timer(player.stream.get_length()/player.pitch_scale+0.15,true,false,true).timeout
	check(not source._emit_sound(&"squish").is_empty(),"movement can resume after the previously selected clip's full duration")
	await clear_sounds()
	var cancelled:Dictionary = source._emit_sound(&"ice_hit")
	var alternate := Node.new()
	root.add_child(alternate)
	current_scene = alternate
	await settle()
	check(cancelled.state=="cancelled" and get_nodes_in_group("MCNativeSFX").is_empty(),"a scene switch cancels pending audio without creating an orphan or playing into the new scene")
	current_scene = world
	alternate.free()
	await clear_sounds()
	var removed := Node2D.new()
	world.add_child(removed)
	var stale:Dictionary = AUDIO.play(removed,&"ice_hit",origin)
	removed.free()
	await settle()
	check(stale.state=="cancelled" and get_nodes_in_group("MCNativeSFX").is_empty(),"an ordinary action from a removed source is cancelled instead of becoming a ghost cue")
	var transient := Node2D.new()
	world.add_child(transient)
	var tail:Dictionary = AUDIO.play(transient,&"death",origin)
	transient.free()
	await settle()
	check(tail.state=="playing" and sounds(&"death").size()==1,"a native death request survives immediate source deletion without a dangling player")
	await clear_sounds()
	for i:int in range(24): AUDIO.play(source,&"amethyst_hit",origin)
	check(AUDIO.play(source,&"amethyst_hit",origin).is_empty(),"pending native requests participate in the shared24-voice budget")
	var priority:Dictionary = AUDIO.play(source,&"entity.player.attack.crit",origin,source.sulfur_impact_gain(100.0))
	await settle()
	check(priority.state=="playing" and get_nodes_in_group("MCNativeSFX").size()==24,"actual damage gets a voice by replacing material chatter without exceeding the budget")
