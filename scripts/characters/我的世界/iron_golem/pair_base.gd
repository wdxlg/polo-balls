extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const AUDIO_PLAYER:Script = preload("res://scripts/characters/我的世界/iron_golem/native_audio_player.gd")
const PAIR_SOUNDS = preload("res://scripts/characters/我的世界/iron_golem/native_sounds.gd")
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
@export var continuation_victory_key:String = ""
@export var continuation_presentation_key:String = ""
@export var visual_clip:String = "idle"
@export var visual_clock:float = 0.0
@export var visual_stage:int = 0
@export var visual_rage:bool = false
var pair_frames:SpriteFrames
@export var breath_silence:Vector2 = Vector2(2.0,5.0)
@export var step_silence:Vector2 = Vector2(0.25,0.7)
var _breath_wait:float = 0.0
var _step_cadence = FOOTSTEP.new()
var _step_length:float = 0.45
var _step_last_position:Vector2
var _voice_player:AudioStreamPlayer2D
var _step_player:AudioStreamPlayer2D
var _death_voice_played:bool = false
var _pair_audio_rng := RandomNumberGenerator.new()
var _pair_death_done:bool = false

func _ready() -> void:
	super._ready()
	Has_Collision_Damage = false
	self_hitbox.set_deferred("monitoring",false)
	motion_blur_enabled = false
	motion_stretch_enabled = false
	bind_continuation_identity()
	_pair_audio_rng.seed = Game.battle_rng_seed_or("golem_pair_voice:"+str(name),int(get_instance_id()))
	_breath_wait = _random_gap(breath_silence)
	_step_last_position = global_position

func bind_continuation_identity() -> void:
	if continuation_victory_key.is_empty(): return
	set_meta("battle_continuation_victory_side_key",continuation_victory_key)
	set_meta("victory_side_key",continuation_victory_key)
	set_meta("battle_continuation_presentation_side_key",continuation_presentation_key)
	set_meta("battle_continuation_display_name","铁傀儡")

func has_collision_damage() -> bool: return false
func _on_hitbox_on_hit(_hurt:hurtbox) -> void: pass
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var desired:State = State.Die if health <= 0 else State.Move if is_combat_runtime_active() else State.Stand
	return -1 if desired == state else desired

func set_pair_clip(clip:String) -> void:
	if visual_clip != clip:
		visual_clip = clip
		visual_clock = 0.0

func tick_physics(state:State,delta:float) -> void:
	if not continuation_victory_key.is_empty() and not has_meta("battle_continuation_victory_side_key"): bind_continuation_identity()
	var from:Vector2 = global_position
	if is_multiplayer_authority() and health > 0 and is_combat_runtime_active():
		if not dizziness: visual_clock += delta
	super.tick_physics(state,delta)
	update_pair_visual()
	var walking:bool = from.distance_squared_to(global_position)>0.000001 and not dizziness and not direction.is_zero_approx() and Speed>0.0 and bool(Game.Game_Settings.get("Ball_Can_Move",true)) and float(get_meta("golem_air_height",0.0))<=0.001
	tick_pair_audio(delta,walking)

# Pair lifecycle audio is scheduled only here, never by the generic mob timer.
func mc_tick_ambient(_delta:float) -> void: pass
func _random_gap(bounds:Vector2) -> float:
	return _pair_audio_rng.randf_range(maxf(minf(bounds.x,bounds.y),0.0),maxf(maxf(bounds.x,bounds.y),0.0))
func _audio_busy(player:Variant) -> bool:
	return is_instance_valid(player) and not player.is_queued_for_deletion() and player.playing
func _audio_duration(player:Variant) -> float:
	return player.stream.get_length()/maxf(player.pitch_scale,0.01) if is_instance_valid(player) and player.stream!=null else 0.0
func _stop_sound(player:Variant) -> void:
	if is_instance_valid(player):
		player.stop()
		player.queue_free()

func _stop_all_steps() -> void:
	_stop_sound(_step_player)
	for node:Node in get_tree().get_nodes_in_group("GolemPairAudio"):
		if node.get_meta("mc_pair_owner",0)==get_instance_id() and str(node.get_meta("mc_sound_event","")).ends_with(".step"):
			_stop_sound(node)

func tick_pair_audio(delta:float,walking:bool) -> void:
	if health<=0:
		_stop_all_steps()
		if is_instance_valid(_voice_player) and not str(_voice_player.get_meta("mc_sound_event","")).ends_with(".death"): _stop_sound(_voice_player)
		return
	if not is_combat_runtime_active(): return
	if not is_multiplayer_authority(): return
	if not walking and _audio_busy(_step_player):
		_stop_all_steps()
		if multiplayer.has_multiplayer_peer(): _pair_stop_step.rpc()
	_breath_wait = maxf(_breath_wait-maxf(delta,0.0),0.0)
	if mc_audio_role=="villager" and _breath_wait<=0.0 and not _audio_busy(_voice_player):
		mc_play("ambient",-8.0)
	var moved:float = global_position.distance_to(_step_last_position)
	_step_last_position = global_position
	if not walking:
		_step_cadence.tick(0.0,delta,1.0,1.0)
		return
	var base_interval:float = _step_length+(step_silence.x+step_silence.y)*0.5
	if _step_cadence.tick(moved,delta,FOOTSTEP.base_speed(self),base_interval): mc_play("step",-10.0)

func update_pair_visual() -> void:
	if pair_frames == null or not pair_frames.has_animation(visual_clip): return
	var count:int = pair_frames.get_frame_count(visual_clip)
	var frame:int = int(visual_clock * pair_frames.get_animation_speed(visual_clip))
	frame = frame % count if pair_frames.get_animation_loop(visual_clip) else mini(frame,count-1)
	(image as Sprite2D).texture = pair_frames.get_frame_texture(visual_clip,maxi(frame,0))
	image.self_modulate = Color(1.0,0.38,0.33) if visual_rage else Color.WHITE

func overlaps_target(target:ball,point:Vector2,radius:float) -> bool:
	if not is_instance_valid(target) or target.self_hurtbox == null: return false
	var circle := CircleShape2D.new()
	circle.radius = maxf(radius,0.1)
	for node:Node in target.self_hurtbox.find_children("*","CollisionShape2D",true,false):
		var shape:CollisionShape2D = node as CollisionShape2D
		if shape != null and not shape.disabled and shape.shape != null:
			if circle.collide(Transform2D(0.0,point),shape.shape,shape.global_transform): return true
	return false

func _pair_event_key(event:String) -> String:
	# Vanilla villagers use the walked-on block sound, not an entity.villager.step.
	if event=="step" and mc_audio_role=="villager": return "block.stone.step"
	return "entity."+mc_audio_role+"."+event

func mc_play(event:String,volume:float = -4.0) -> AudioStreamPlayer2D:
	if not is_multiplayer_authority(): return null
	if event!="death" and (health<=0 or not is_combat_runtime_active()): return null
	var key:String = _pair_event_key(event)
	if not PAIR_SOUNDS.EVENTS.has(key): return null
	var index:int = _pair_audio_rng.randi_range(0,PAIR_SOUNDS.EVENTS[key].size()-1)
	var player:AudioStreamPlayer2D = _pair_audio_local(key,global_position,volume,index)
	# Only a sound actually accepted by its channel is broadcast. Same variant,
	# duration and pitch on replicas; no autonomous replica ambient scheduler.
	if player!=null and multiplayer.has_multiplayer_peer(): _pair_audio.rpc(key,global_position,volume,index)
	return player

@rpc("authority","call_remote","reliable")
func _pair_audio(event:String,point:Vector2,volume:float,index:int = -1) -> void:
	_pair_audio_local(event,point,volume,index)

@rpc("authority","call_remote","reliable")
func _pair_stop_step() -> void:
	_stop_sound(_step_player)

func _pair_audio_local(event:String,point:Vector2,volume:float,index:int = -1) -> AudioStreamPlayer2D:
	if not PAIR_SOUNDS.EVENTS.has(event) or get_tree().current_scene == null: return null
	var kind:String = event.get_slice(".",event.get_slice_count(".")-1)
	var vocal:bool = kind in ["ambient","hurt","death","yes"]
	if kind!="death" and (health<=0 or _death_voice_played): return null
	if kind=="death":
		if _death_voice_played: return null
		_death_voice_played = true
		_stop_sound(_voice_player)
		_stop_sound(_step_player)
	elif vocal:
		if _audio_busy(_voice_player):
			# Hurt may interrupt a mutter, but a hit flurry cannot layer hurt voices.
			if kind=="hurt" and str(_voice_player.get_meta("mc_sound_event","")).ends_with(".ambient"):
				_stop_sound(_voice_player)
			else: return null
	var pool:Array = PAIR_SOUNDS.EVENTS[event]
	var choice:int = index if index>=0 and index<pool.size() else _pair_audio_rng.randi_range(0,pool.size()-1)
	var record:Dictionary = pool[choice]
	var player:AudioStreamPlayer2D = AUDIO_PLAYER.new()
	player.stream = record.stream
	player.volume_db = volume + linear_to_db(maxf(float(record.volume),0.01))
	player.pitch_scale = float(record.pitch)
	player.max_distance = 1700.0
	player.actor_ref = weakref(self)
	player.follow_actor = (vocal or kind=="step") and kind!="death"
	player.stop_with_actor = player.follow_actor
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("BattleTransient")
	player.add_to_group("GolemPairAudio")
	player.set_meta("mc_sound_event",event)
	player.set_meta("mc_pair_owner",get_instance_id())
	player.set_meta("mc_pair_variant",choice)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	if vocal:
		_voice_player = player
		_breath_wait = _audio_duration(player)+_random_gap(breath_silence)
	elif kind=="step":
		_step_player = player
		_step_length = _audio_duration(player)
	return player

func _exit_tree() -> void:
	_stop_sound(_step_player)
	if is_instance_valid(_voice_player) and not str(_voice_player.get_meta("mc_sound_event","")).ends_with(".death"): _stop_sound(_voice_player)
	super._exit_tree()

func Die() -> void:
	if _pair_death_done: return
	_pair_death_done = true
	mc_play("death",-4.0)
	mc_death_visual()
