extends ball
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")
const DEATH_FX=preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
const ITEM_DEATH=preload("res://scripts/effects/我的世界/item_fragments.gd")
var _death_visual_done:bool=false
@export var secondary_ambient_gap_min:float=12.0
@export var secondary_ambient_gap_max:float=22.0
var _secondary_wait:float=8.0
var _secondary_player:AudioStreamPlayer2D
const AUDIO=preload("res://scripts/characters/我的世界/new5/audio.gd")
@export_range(0.0,1.0,0.05) var hurt_voice_chance:float=0.45
@export var ambient_gap_min:float=3.0
@export var ambient_gap_max:float=7.0
var _voice_rng:=RandomNumberGenerator.new()
var _ambient_left:float=2.0
var _ambient_player:AudioStreamPlayer2D
var _death_sound_done:bool=false
var _face_right:bool=false
var rng:=RandomNumberGenerator.new()
var clock:float=0.0
var _send_wait:float=0.0
var _view_clock:float=0.0
func _ready() -> void:
	Has_Collision_Damage=false
	Health_Restore=0
	rng.seed=Game.battle_rng_seed_or("mc_new5:"+str(name),int(get_instance_id()))
	super._ready()
	_voice_rng.randomize()
	_ambient_left=_voice_rng.randf_range(2,5)
	_secondary_wait=_voice_rng.randf_range(8,14)
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	set_process(true)
	if not is_multiplayer_authority(): call_deferred("_request_initial_state")
func active() -> bool: return is_multiplayer_authority() and health>0 and is_combat_runtime_active()
func can_act() -> bool: return active() and not dizziness and Can_Attack and not is_damage_output_disabled()
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:int=State.Move
	if health<=0: next=State.Die
	elif not is_combat_runtime_active() or dizziness: next=State.Stand
	return -1 if state==next else next
func Attack() -> void: Attacking=false
func Skill() -> void: Using_Skill=false
func tick_physics(state:State,delta:float) -> void:
	if active():
		clock+=delta
		step_mob(delta)
		tick_ambient(delta)
	super.tick_physics(state,delta)
	if active():
		_send_wait-=delta
		if _send_wait<=0:
			_send_wait=0.075
			if multiplayer.has_multiplayer_peer(): _new5_visual.rpc(network_visual_state())
func _process(delta:float) -> void:
	if is_instance_valid(_secondary_player):
		_secondary_player.global_position=global_position
		_secondary_player.stream_paused=not is_combat_runtime_active()
	if is_instance_valid(_ambient_player):
		_ambient_player.global_position=global_position
		_ambient_player.stream_paused=not is_combat_runtime_active()
	if health>0 and is_combat_runtime_active(): _view_clock+=delta
	if is_multiplayer_authority(): _view_clock=clock
	if not is_multiplayer_authority(): client_visual_step(delta)
	visual_mob()
func client_visual_step(_delta:float) -> void: pass
func step_mob(_delta:float) -> void: pass
func visual_mob() -> void: pass
func visual_state() -> Dictionary: return {"time":clock}
func accept_visual(data:Dictionary) -> void:
	_view_clock=float(data.get("time",_view_clock))
	_face_right=bool(data.get("face_right",_face_right))
@rpc("authority","call_remote","unreliable_ordered")
func _new5_visual(data:Dictionary) -> void: accept_visual(data)
func _request_initial_state() -> void:
	if multiplayer.has_multiplayer_peer(): _new5_request.rpc_id(get_multiplayer_authority())
@rpc("any_peer","call_remote","reliable")
func _new5_request() -> void:
	if is_multiplayer_authority(): _new5_visual.rpc_id(multiplayer.get_remote_sender_id(),network_visual_state())
func frame(frames:SpriteFrames,clip:StringName = &"idle") -> void:
	if image is Sprite2D:
		image.texture=frames.get_frame_texture(clip,int(_view_clock*frames.get_animation_speed(clip))%frames.get_frame_count(clip))

func network_visual_state() -> Dictionary:
	var data:Dictionary=visual_state()
	data["face_right"]=_face_right
	return data
func face_horizontal(hint:Vector2,native_faces_left:bool=true) -> void:
	if is_multiplayer_authority() and absf(hint.x)>0.01: _face_right=hint.x>0
	image.rotation=0.0
	set_character_visual_flip_h(_face_right if native_faces_left else not _face_right)
func voice_role() -> String: return ""
func voice_event(kind:String) -> String:
	return "entity."+voice_role()+"."+kind if not voice_role().is_empty() else ""
func play_sound(event:String,volume_db:float=-5.0) -> AudioStreamPlayer2D:
	if event.is_empty() or not is_multiplayer_authority(): return null
	if multiplayer.has_multiplayer_peer(): _receive_sound.rpc(event,global_position,volume_db)
	return _receive_sound(event,global_position,volume_db)
@rpc("authority","call_remote","reliable")
func _receive_sound(event:String,point:Vector2,volume_db:float) -> AudioStreamPlayer2D:
	return AUDIO.play(self,event,point,volume_db,event.contains(".death"),event.contains(".death"))
func tick_ambient(delta:float) -> void:
	if voice_role() not in ["guardian","ghast"]: return
	if voice_role()=="guardian": tick_secondary_ambient(delta)
	_ambient_left=maxf(0,_ambient_left-delta)
	if _ambient_left>0 or (is_instance_valid(_ambient_player) and _ambient_player.playing): return
	var event:String=voice_event("flop") if voice_role()=="guardian" else voice_event("ambient")
	if multiplayer.has_multiplayer_peer(): _receive_ambient.rpc(event)
	_receive_ambient(event)
	if is_instance_valid(_ambient_player):
		_ambient_left=_ambient_player.stream.get_length()/maxf(_ambient_player.pitch_scale,0.01)+_voice_rng.randf_range(ambient_gap_min,ambient_gap_max)
	else: _ambient_left=0.2
@rpc("authority","call_remote","reliable")
func _receive_ambient(event:String) -> void:
	if is_instance_valid(_ambient_player) and _ambient_player.playing: return
	_ambient_player=AUDIO.play(self,event,global_position,-8.0)
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if not bool(get_meta("mc_hook_hurt_only",false)) and health>0 and is_multiplayer_authority() and _voice_rng.randf()<hurt_voice_chance: play_sound(voice_event("hurt"),-5.0)
func Die() -> void:
	if _death_sound_done: return
	_death_sound_done=true
	play_sound(voice_event("death"),-4.0)
	stop_ambient()
	if is_multiplayer_authority():
		if multiplayer.has_multiplayer_peer(): _death_visual.rpc()
		else: _death_visual()
	super.Die()
@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done=true
	if voice_role() in ["slime","guardian","ghast"]:
		DEATH_FX.death_pose(self,image,direction.x>=0)
	elif get_script().resource_path.get_file().get_basename() in ["piston","fishing_rod"]:
		ITEM_DEATH.spawn(self)
func stop_ambient() -> void:
	if is_instance_valid(_secondary_player):
		_secondary_player.stop()
		_secondary_player.queue_free()
	_secondary_player=null
	if is_instance_valid(_ambient_player):
		_ambient_player.stop()
		_ambient_player.queue_free()
	_ambient_player=null
func _exit_tree() -> void: stop_ambient()

func tick_secondary_ambient(delta:float) -> void:
	_secondary_wait=maxf(0,_secondary_wait-delta)
	if _secondary_wait>0 or (is_instance_valid(_secondary_player) and _secondary_player.playing): return
	if multiplayer.has_multiplayer_peer(): _receive_secondary.rpc()
	_receive_secondary()
	if is_instance_valid(_secondary_player):
		_secondary_wait=_secondary_player.stream.get_length()/maxf(_secondary_player.pitch_scale,0.01)+_voice_rng.randf_range(secondary_ambient_gap_min,secondary_ambient_gap_max)
	else: _secondary_wait=0.2
@rpc("authority","call_remote","reliable")
func _receive_secondary() -> void:
	if is_instance_valid(_secondary_player) and _secondary_player.playing: return
	_secondary_player=AUDIO.play(self,"entity.guardian.ambient_land",global_position,-9.0)
