extends "res://scripts/characters/我的世界/new5/base.gd"
const BODY:Texture2D = preload("res://Images/characters/我的世界/cactus_note/jukebox.png")
const PEAKS = preload("res://scripts/characters/我的世界/cactus_note/music_features.gd")
const EXTRA_MUSIC = preload("res://scripts/characters/我的世界/cactus_note/extra_library.gd")
const SHAPES = preload("res://scripts/characters/我的世界/cactus_note/music_shape_features.gd")
const IMPACT_AUDIO = preload("res://scripts/characters/我的世界/cactus_note/block_audio.gd")
var impact_count:int = 0
var last_impact_damage:float = 0.0
var last_impact_event:String = ""
var last_impact_gain:float = 0.0
const WAVE = preload("res://scripts/characters/我的世界/cactus_note/note_wave.gd")
const FX = preload("res://scripts/effects/我的世界/mc_explosion.gd")
const TRACKS:Array[String] = ["pigstep","otherside","cat","creator","precipice","relic"]
const MUSIC:Array[AudioStream] = [preload("res://audio/characters/我的世界/音符盒/pigstep.ogg"),preload("res://audio/characters/我的世界/音符盒/otherside.ogg"),preload("res://audio/characters/我的世界/音符盒/cat.ogg"),preload("res://audio/characters/我的世界/音符盒/creator.ogg"),preload("res://audio/characters/我的世界/音符盒/precipice.ogg"),preload("res://audio/characters/我的世界/音符盒/relic.ogg")]
const DISC_FLIGHT = preload("res://scripts/characters/我的世界/cactus_note/disc_flight.gd")
const DISCS:Array[Texture2D] = [preload("res://Images/characters/我的世界/cactus_note/disc_pigstep.png"),preload("res://Images/characters/我的世界/cactus_note/disc_otherside.png"),preload("res://Images/characters/我的世界/cactus_note/disc_cat.png"),preload("res://Images/characters/我的世界/cactus_note/disc_creator.png"),preload("res://Images/characters/我的世界/cactus_note/disc_precipice.png"),preload("res://Images/characters/我的世界/cactus_note/disc_relic.png")]
var record_phase:int = 0 # inserting, playing, waiting for ejected disc to fall outside map
var record_age:float = 0.0
var inserted_records:int = 0
var ejected_records:int = 0
var eject_sound_count:int = 0
var _pending_start_time:float = 0.0
var _disc_sprite:Sprite2D
var _ejected_record:Sprite2D
var music:AudioStreamPlayer2D
var peak_data:Dictionary = {}
var track_index:int = 0
var peak_index:int = 0
var playhead:float = 0.0
var streak:float = 0.0
var combo_decaying:bool = false
var _last_hit_sequence:int = -1
const DECAY_PER_SECOND:float = 5.0
var playback_rate:float = 1.0 # Always original tempo; retained for snapshot compatibility.
var combo_damage_multiplier:float = 1.0
var wave_angle_degrees:float = 15.0
var music_volume_db:float = -10.0
var emitted_peaks:int = 0
var _next_resolution:int = 0
var _outcomes:Dictionary = {}
var _channel_groups:Dictionary = {}
var pulse:float = 0.0
var body_punch:float = 0.0
# Continuous body-only music shape: -1 is low/fat, 0 neutral, +1 is high/tall.
var music_shape_target:float = 0.0
var music_shape:float = 0.0
var music_shape_energy:float = 0.0
var _body_shape_index:int = 0
var _music_rest_offset:Vector2 = Vector2.ZERO
var _music_base_scale:Vector2 = Vector2.ONE
var musical_events:int = 0
var rest_events:int = 0
func get_preview_texture() -> Texture2D: return BODY
func _ready() -> void:
	super._ready()
	_music_rest_offset = image.offset
	_music_base_scale = image.scale
	peak_data = PEAKS.DATA.duplicate()
	peak_data.merge(EXTRA_MUSIC.DATA)
	music = AudioStreamPlayer2D.new()
	music.name = "RecordMusic"
	music.volume_db = -10.0
	music.max_distance = 700.0
	music.attenuation = 0.7
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: music.bus = &"GameplayRecord"
	add_child(music)
	music.finished.connect(_track_finished)
	_disc_sprite = Sprite2D.new()
	_disc_sprite.name = "InsertingRecord"
	_disc_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_disc_sprite.z_as_relative = false
	_disc_sprite.z_index = 7
	image.get_parent().add_child(_disc_sprite)
	start_track(rng.randi_range(0,TRACKS.size()-1))
func controlled_attack_action() -> void:
	# The already inserted/playing disc keeps its music-driven attack to completion.
	# Only loading the NEXT disc is a fresh manual action.
	if is_player_controlled() and is_multiplayer_authority() and can_act() and record_phase==3:
		start_track(track_index+1)
func set_player_control_peer(peer_id:int) -> void:
	var was_controlled:bool=is_player_controlled()
	super.set_player_control_peer(peer_id)
	if was_controlled and not is_player_controlled() and record_phase==3 and health>0 and is_multiplayer_authority():
		start_track(track_index+1)
func start_track(index:int,at:float = 0.0) -> void:
	track_index = posmod(index,TRACKS.size())
	_pending_start_time = maxf(at,0)
	playhead = _pending_start_time
	peak_index = 0
	record_phase = 0
	record_age = 0
	_body_shape_index = 0
	music_shape = 0.0
	set_music_shape(0.0,0.0)
	if is_instance_valid(music): music.stop()
	update_record_pose()
func _play_track(index:int,at:float = 0.0) -> void:
	record_phase = 1
	record_age = 0
	inserted_records += 1
	track_index = posmod(index,TRACKS.size())
	playhead = maxf(0,at)
	peak_index = 0
	_body_shape_index = 0
	music_shape = 0.0
	set_music_shape(0.0,0.0)
	var peaks:Array = peak_data[TRACKS[track_index]].peaks
	while peak_index<peaks.size() and float(peaks[peak_index][0])<playhead: peak_index+=1
	music.stream = MUSIC[track_index]
	music.pitch_scale = 1.0
	music.volume_db = music_volume_db
	music.play(playhead)
	music.stream_paused = not is_combat_runtime_active() or dizziness or not Can_Attack
	update_record_pose()
func _track_finished() -> void:
	if health<=0 or record_phase!=1 or not is_multiplayer_authority(): return
	var point:Vector2 = image.get_parent().to_global(Vector2(0,-36))
	var side:float = -1.0 if is_character_visual_flipped_h() else 1.0
	var bounds:Rect2 = record_arena()
	if multiplayer.has_multiplayer_peer(): _eject_record.rpc(track_index,point,side,bounds)
	else: _eject_record(track_index,point,side,bounds)
func _process(delta:float) -> void:
	super._process(delta)
	if is_instance_valid(music):
		music.stream_paused = not is_combat_runtime_active() or health<=0 or dizziness or not Can_Attack
		music.pitch_scale = 1.0
		music.volume_db = music_volume_db
	if is_combat_runtime_active():
		pulse = maxf(0,pulse-delta*4.0)
		body_punch = maxf(0,body_punch-delta*8.0)
		if record_phase==1 and is_instance_valid(music) and music.playing and not music.stream_paused:
			var audio_time:float = music.get_playback_position()+AudioServer.get_time_since_last_mix()
			sync_music_shape(maxf(playhead,audio_time))
		elif record_phase!=1:
			set_music_shape(0.0,0.0)
		advance_music_shape(delta)
func step_mob(_delta:float) -> void:
	advance_combo_decay(_delta)
	if record_phase!=1:
		advance_record(_delta)
		return
	if not can_act() or not is_instance_valid(music) or not music.playing or music.stream_paused: return
	# The decoded audio clock, not a fabricated fixed attack timer, is authoritative.
	var audio_time:float = music.get_playback_position()+AudioServer.get_time_since_last_mix()
	process_audio_peaks(maxf(playhead,audio_time))
func process_audio_peaks(at:float) -> void:
	playhead = at
	var peaks:Array = peak_data[TRACKS[track_index]].peaks
	while peak_index < peaks.size() and float(peaks[peak_index][0]) <= playhead:
		var event:Array = peaks[peak_index]
		peak_index += 1
		# Two-column legacy/mono peaks mirror; stereo records carry separate L/R.
		emit_peak(float(event[1]),float(event[2]) if event.size()>2 else float(event[1]),event[3] if event.size()>3 else [],event[4] if event.size()>4 else [])
func emit_peak(left_peak:float,right_peak:float = -2.0,left_profile:Array = [],right_profile:Array = []) -> void:
	if right_peak == -2.0: right_peak = left_peak
	# Body animation is clocked from the continuous shape track in _process,
	# not from this attack event or its hit/miss result.
	if left_profile.size()>=8 and bool(left_profile[7]): left_peak = -1
	if right_profile.size()>=8 and bool(right_profile[7]): right_peak = -1
	if left_peak<0 and right_peak<0:
		rest_events += 1
		return
	var profiles:Array = [left_profile,right_profile]
	var id:int = emitted_peaks
	emitted_peaks += 1
	pulse = maxf(left_peak,right_peak)
	var peaks:Array[float] = [left_peak,right_peak]
	var expected:int = int(left_peak>=0)+int(right_peak>=0)
	if expected==0:
		resolve_wave(id,false)
		return
	_channel_groups[id] = {"expected":expected,"done":{}}
	# Capture both channels before either can alter combo state.
	var multiplier:float = combo_damage_multiplier
	var arc:float = wave_angle_degrees
	for channel:int in range(2):
		if peaks[channel]<0: continue
		var amplitude:float = clampf(peaks[channel],0,1)
		var aim:Vector2 = Vector2.LEFT if channel==0 else Vector2.RIGHT
		var point:Vector2 = to_global(Vector2(42*aim.x,0))
		var amount:float = attack_damage(lerpf(0.10,1.7,amplitude)*multiplier)
		if multiplayer.has_multiplayer_peer(): _launch_wave.rpc(id,point,aim,amplitude,amount,track_index,arc,channel,profiles[channel])
		else: _launch_wave(id,point,aim,amplitude,amount,track_index,arc,channel,profiles[channel])
func resolve_channel(id:int,channel:int,hit:bool) -> void:
	if not _channel_groups.has(id): return
	var group:Dictionary = _channel_groups[id]
	if group.done.has(channel): return
	group.done[channel] = true
	if hit or group.done.size()>=int(group.expected):
		_channel_groups.erase(id)
		resolve_wave(id,hit)
@rpc("authority","call_local","reliable")
func _launch_wave(id:int,point:Vector2,aim:Vector2,amplitude:float,amount:float,song:int = -1,arc_degrees:float = -1.0,channel:int = -1,profile:Array = []) -> void:
	if get_tree().get_nodes_in_group("MCNoteWave").size()>=64:
		if is_multiplayer_authority():
			if channel>=0: resolve_channel(id,channel,false)
			else: resolve_wave(id,false)
		return
	var wave:Node2D = WAVE.new()
	wave.set_multiplayer_authority(get_multiplayer_authority())
	FX.runtime_container(self).add_child(wave)
	wave.configure(self,id,point,aim,amplitude,amount,song,arc_degrees)
	wave.channel_index = channel
	wave.apply_music_profile(profile)
	if profile.size()>=8:
		musical_events += 1
		body_punch = maxf(body_punch,wave.kick_strength*wave.beat_strength)
func resolve_wave(id:int,hit:bool) -> void:
	if id<_next_resolution or _outcomes.has(id): return
	if hit: register_music_hit(id)
	elif id>_last_hit_sequence: combo_decaying = streak>0
	_outcomes[id] = hit
	# Fast high peaks can overtake older waves: resolve in musical emission order.
	while _outcomes.has(_next_resolution):
		if bool(_outcomes[_next_resolution]): streak = minf(20.0,streak+1.0)
		_outcomes.erase(_next_resolution)
		_next_resolution += 1
	refresh_combo_bonuses()
func refresh_combo_bonuses() -> void:
	playback_rate = 1.0
	var volume_progress:float = clampf(float(streak)/20.0,0,1)
	combo_damage_multiplier = lerpf(1.0,3.0,volume_progress)
	wave_angle_degrees = lerpf(15.0,180.0,volume_progress)
	music_volume_db = lerpf(-10.0,-2.0,volume_progress)
	if is_instance_valid(music):
		music.pitch_scale = 1.0
		music.volume_db = music_volume_db
func visual_mob() -> void:
	image.rotation = 0
	# High music pulls the body up and narrows it; low music flattens and
	# fattens it. This is body animation only, never uniform scaling.
	var shape:float = clampf(music_shape,-1,1)
	var beat_wave:float = sin(clock*95.0)*clampf(body_punch,0,1)*0.045
	var y:float = maxf(0.60,1.0+shape*0.46+beat_wave)
	var x:float = maxf(0.64,1.0-shape*0.32-beat_wave*0.25)
	image.scale = Vector2(x*_music_base_scale.x,y*_music_base_scale.y)
	var height:float = float(BODY.get_height())
	var anchored_bottom:float = _music_base_scale.y*(_music_rest_offset.y+height*0.5)
	image.offset = Vector2(_music_rest_offset.x,anchored_bottom/maxf(image.scale.y,0.001)-height*0.5)
	face_horizontal(velocity if velocity.length_squared()>1.0 else direction,false)
	update_record_pose()

func set_music_shape(shape:float,energy:float = 1.0) -> void:
	music_shape_energy = clampf(energy,0,1)
	music_shape_target = clampf(shape*(0.78+0.22*music_shape_energy),-1,1)

func sync_music_shape(at:float) -> float:
	var points:Array = SHAPES.DATA.get(TRACKS[track_index],[])
	if points.is_empty():
		set_music_shape(0.0,0.0)
		return 0.0
	if _body_shape_index>=points.size() or float(points[_body_shape_index][0])>at: _body_shape_index = 0
	while _body_shape_index+1<points.size() and float(points[_body_shape_index+1][0])<=at: _body_shape_index += 1
	var current:Array = points[_body_shape_index]
	var shape:float = float(current[1])
	var energy:float = float(current[2])
	if _body_shape_index+1<points.size():
		var next:Array = points[_body_shape_index+1]
		var span:float = maxf(float(next[0])-float(current[0]),0.001)
		var t:float = clampf((at-float(current[0]))/span,0,1)
		shape = lerpf(shape,float(next[1]),t)
		energy = lerpf(energy,float(next[2]),t)
	set_music_shape(shape,energy)
	return music_shape_target

func advance_music_shape(delta:float) -> void:
	music_shape = lerpf(music_shape,music_shape_target,1.0-exp(-16.0*maxf(delta,0)))
	music_shape_energy = lerpf(music_shape_energy,0.0,1.0-exp(-12.0*maxf(delta,0)))
func visual_state() -> Dictionary:
	return {"time":clock,"track":track_index,"playhead":playhead,"rate":1.0,"damage_multiplier":combo_damage_multiplier,"volume_db":music_volume_db,"streak":streak,"decaying":combo_decaying,"pulse":pulse,"body_punch":body_punch,"music_shape":music_shape,"shape_energy":music_shape_energy,"record_phase":record_phase,"record_age":record_age}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	streak = float(data.get("streak",0))
	combo_decaying = bool(data.get("decaying",false))
	refresh_combo_bonuses()
	pulse = float(data.get("pulse",0))
	body_punch = float(data.get("body_punch",0))
	music_shape = clampf(float(data.get("music_shape",0)),-1,1)
	music_shape_energy = clampf(float(data.get("shape_energy",0)),0,1)
	music_shape_target = music_shape
	if not is_instance_valid(music): return
	var track:int = int(data.get("track",0))
	var at:float = float(data.get("playhead",0))
	var phase:int = int(data.get("record_phase",1))
	if phase==1:
		if track!=track_index or record_phase!=1: _play_track(track,at)
		elif absf(music.get_playback_position()-at)>0.20: music.seek(at)
	else:
		music.stop()
		track_index = track
	record_phase = phase
	record_age = float(data.get("record_age",0))
	update_record_pose()
	playhead = at
@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	if is_instance_valid(music): music.stop()
	if is_instance_valid(_disc_sprite): _disc_sprite.hide()
	ITEM_DEATH.spawn(self)
func get_skill_description() -> String:
	return "先插入唱片再播放，曲终从顶部口弹盘、沿抛物线掉出地图后再插下一张。轮播Pigstep、Otherside、Cat、Creator、Precipice、Relic；当前原版音源均为单声道，因此左右同峰等强，立体声音源可按各声道峰值分别出波。实际音乐的小峰驱动攻击，本体根据独立离线60毫秒连续音高包络做明显非等比形变，高音拉长变细、低音变扁变粗，连续插值并平滑跟随音乐，和攻击事件、命中、叠层或攻击结果无关；底边中点始终原位；基础伤害6，初始角度范围3°至15°，下限随叠层平滑抬升；满20层时只要发出攻击，每侧角度均在90°至180°之间随当时响度变化。按实际音乐20毫秒RMS包络的当时响度决定每侧伤害、速度、传播半径、拖尾和发射角度；声音轻时小而弱、响时大而强，叠层决定角度上限；每道波发出后角度固定，半径扩大不改变角度。每首歌有独特色彩与特效的弧形波分别向世界左、右方向发出后不追踪，每波每人只伤一次；连续命中提高音乐音量与伤害，并将后续音波覆盖角度从15°扩大至单侧180°，最高-2dB与3倍伤害，音乐始终原速；左右共享一次攻击，任一侧命中只叠一次，20次有效命中叠满；两侧全空后开始每秒衰减5层，命中立即停止衰减；不瞬间清空。低频瞬态带短震与轻击退，高频/中频瞬态带细碎敲击纹理；混音主导音高驱动纹理疏密与音符高低，长音拖尾、断奏短促、休止留白，强弱拍有不同反馈。鼓类和音高均为混音近似识别，不是精确分轨。"

func play_wave_impact(point:Vector2,actual_damage:float) -> void:
	if multiplayer.has_multiplayer_peer(): _wave_impact.rpc(point,actual_damage)
	else: _wave_impact(point,actual_damage)
@rpc("authority","call_local","reliable")
func _wave_impact(point:Vector2,actual_damage:float) -> void:
	impact_count += 1
	last_impact_damage = actual_damage
	last_impact_event = "entity.player.attack.crit" if actual_damage>50.0 else "entity.player.hurt"
	last_impact_gain = IMPACT_AUDIO.impact_gain(actual_damage)
	IMPACT_AUDIO.play(self,last_impact_event,point,last_impact_gain,actual_damage)

func advance_record(delta:float) -> void:
	if record_phase!=0 or health<=0: return
	record_age = minf(0.65,record_age+delta)
	update_record_pose()
	if record_age+0.000001>=0.65: _play_track(track_index,_pending_start_time)
func client_visual_step(delta:float) -> void:
	if is_combat_runtime_active(): advance_record(delta)
func update_record_pose() -> void:
	if not is_instance_valid(_disc_sprite): return
	_disc_sprite.visible = record_phase==0 and health>0
	if not _disc_sprite.visible: return
	_disc_sprite.texture = DISCS[track_index]
	var t:float = clampf(record_age/0.65,0,1)
	var side:float = -1.0 if is_character_visual_flipped_h() else 1.0
	var approach:float = smoothstep(0,0.65,t)
	var into_slot:float = smoothstep(0.65,1.0,t)
	_disc_sprite.position = Vector2(side*80,-135).lerp(Vector2(0,-65),approach)+Vector2(0,29)*into_slot
	_disc_sprite.scale = Vector2(2.8,2.8*maxf(0.02,1.0-into_slot))
	_disc_sprite.rotation = side*lerpf(-0.4,0.0,approach)
	_disc_sprite.modulate.a = 1.0-smoothstep(0.94,1.0,t)
func record_arena() -> Rect2:
	var world:Node = get_tree().current_scene
	if world!=null and world.has_method("return_map_world_rect"):
		var map:Node = world.map_group.get(world.now_choose_map)
		if is_instance_valid(map): return world.return_map_world_rect(map)
	return Rect2(global_position-Vector2(300,300),Vector2(600,600))
@rpc("authority","call_local","reliable")
func _eject_record(song:int,point:Vector2,side:float,bounds:Rect2) -> void:
	if record_phase==2: return
	record_phase = 2
	record_age = 0
	ejected_records += 1
	eject_sound_count += 1
	# User-approved vanilla dispenser click, not a dedicated jukebox eject sound.
	IMPACT_AUDIO.play(self,"block.dispenser.dispense",point,-3.0)
	music.stop()
	update_record_pose()
	_ejected_record = DISC_FLIGHT.new()
	FX.runtime_container(self).add_child(_ejected_record)
	_ejected_record.configure(self,DISCS[posmod(song,DISCS.size())],point,side,bounds)
func finish_ejection() -> void:
	if record_phase!=2 or health<=0 or not is_multiplayer_authority(): return
	if is_player_controlled(): record_phase=3 # Waiting for the next manual left-click.
	else: start_track(track_index+1)

func register_music_hit(id:int) -> void:
	combo_decaying = false
	_last_hit_sequence = maxi(_last_hit_sequence,id)
func advance_combo_decay(delta:float) -> void:
	if not combo_decaying or Game.now_stop_state or get_tree().paused or not is_combat_runtime_active(): return
	streak = maxf(0.0,streak-DECAY_PER_SECOND*maxf(delta,0))
	if streak<=0: combo_decaying = false
	refresh_combo_bonuses()
