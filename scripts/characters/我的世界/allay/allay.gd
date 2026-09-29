extends "res://scripts/characters/我的世界/new5/base.gd"
const CAPTURE = preload("res://scripts/characters/我的世界/allay/capture.gd")
const NOTE_SCENE = preload("res://scenes/shooter/我的世界/悦灵音符.tscn")
const NOTE_TEXTURE = preload("res://Images/characters/我的世界/allay/note.png")
const CUBE_TEXTURE = preload("res://Images/characters/我的世界/allay/generic_0.png")
const NATIVE_FRAMES = preload("res://Images/characters/我的世界/allay/allay.tres")
const NATIVE_SOUNDS = preload("res://scripts/characters/我的世界/allay/native_sounds.gd")
const ORBIT = preload("res://scripts/characters/我的世界/allay/orbit.gd")
const MC_AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const CRITICAL_HIT_DAMAGE:float = 50.0
@export_category("悦灵 / 音符")
@export var note_interval:float = 1.5
@export var note_capacity:int = 4
@export var note_growth_interval:float = 2.6
@export var note_interval_reduction:float = 0.15
@export var note_min_interval:float = 0.3
@export var note_max_capacity:int = 20
@export var note_range:float = 110.0
@export var note_fire_interval:float = 0.25
@export var note_speed:float = 94.0
@export var note_lifetime:float = 3.0
@export var note_turn_rate:float = 0.45
@export_category("悦灵 / 近身音符召回")
@export var recall_trigger:float = 40.0
@export var recall_spin_time:float = 0.7
@export var recall_collapse_time:float = 0.2
@export var recall_cooldown:float = 3.0
@export var recall_wave_radius:float = 55.0
var _recall:RefCounted
@export_category("悦灵 / 收集")
@export var cube_capacity:int = 8
@export var return_interval:float = 0.2
@export var return_trigger:float = 120.0
@export var windup_back:float = 0.2
@export var windup_dash:float = 0.14
@export var windup_pull:float = 20.0
@export var windup_reach:float = 26.0
@export_range(0.0,1.0,0.05) var giggle_chance:float = 0.45
@export_range(0.0,1.0,0.05) var joy_chance:float = 0.7
var notes:int = 0
var cargo:Array[Dictionary] = []
var _generate_left:float = 0.0
var _note_growth_stage:int = 0
var _note_left:float = 0.0
var _return_left:float = 0.0
var _windup:Dictionary = {}
var _remote_wind:Array = []
var _lines:Array[Dictionary] = []
var _absorbs:Array[Dictionary] = []
var _image_base:Vector2 = Vector2.ZERO
var _note_cloud = preload("res://scripts/characters/我的世界/allay/smooth_orbit.gd").new()
var _note_visual:Node2D
var _cube_cloud = ORBIT.new()
var _visual_delta:float = 0.0
var _native_sfx_left:Dictionary = {}
var _remote_kinds:Array = []
var _flash:float = 0.0
var _art_origin:Vector2

func _ready() -> void:
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Dead_Audio = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	super._ready()
	_image_base = image.scale
	add_to_group("MinecraftAllay")
	_art_origin = image.position
	Ignore_Team_Damage_Setting = true
	_generate_left = current_note_interval()
	_recall = preload("res://scripts/characters/我的世界/allay/recall_burst.gd").new(self)
	_note_visual = Node2D.new()
	_note_visual.name = "UnclippedNotes"
	_note_visual.z_as_relative = false
	_note_visual.z_index = 102
	add_child(_note_visual)
	_note_visual.draw.connect(_draw_notes)

func note_growth_stage() -> int:
	# The base clock advances only during live, unpaused combat, even when stunned.
	var elapsed:float = clock if is_multiplayer_authority() else _view_clock
	return maxi(int(floor((maxf(elapsed,0.0)+0.000001)/maxf(note_growth_interval,0.05))),0)

func _note_interval_at_stage(stage:int) -> float:
	return maxf(maxf(note_min_interval,0.05),note_interval-float(stage)*maxf(note_interval_reduction,0.0))

func current_note_interval() -> float:
	return _note_interval_at_stage(note_growth_stage())

func current_note_capacity() -> int:
	return mini(maxi(note_capacity,1)+note_growth_stage(),maxi(note_max_capacity,maxi(note_capacity,1)))

func _update_note_growth() -> void:
	var stage:int = note_growth_stage()
	if stage==_note_growth_stage: return
	# Preserve the current production cycle's progress when the interval changes.
	_generate_left *= _note_interval_at_stage(stage)/_note_interval_at_stage(_note_growth_stage)
	_note_growth_stage = stage

func step_mob(delta:float) -> void:
	if not active(): return
	_update_note_growth()
	CAPTURE.scan_orbit(self)
	# Player movement/aim must not turn the passive notes into click-to-fire attacks.
	if not can_act() and not (is_player_controlled() and not dizziness and not is_damage_output_disabled()): return
	_recall.advance(delta)
	if not _windup.is_empty(): _wind_step(delta)
	_generate_left -= delta
	if _generate_left <= 0:
		_generate_left = current_note_interval()
		notes = mini(notes+1,current_note_capacity())
	_note_left -= delta
	_return_left -= delta
	if is_player_controlled(): return # Keep stock, capture, and already-started actions; stop AI starts.
	if not _recall.busy(): _recall.try_start()
	if not _recall.busy(): _auto_fire_note()
	_begin_cargo_throw(U.nearest(self))
func _aimed_enemy() -> ball:
	if not has_player_control_aim(): return null
	var point:Vector2=player_control_aim_world_position()
	var chosen:ball=null
	var nearest:float=INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,raw) or not raw.is_combat_lockable(): continue
		var distance:float=ball.body_point(raw,point).distance_to(point)
		if distance<=U.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	return chosen
func controlled_attack_action() -> void:
	if not is_player_controlled() or not active() or dizziness or is_damage_output_disabled() or _recall.busy() or notes<=0 or _note_left>0.0: return
	var target:ball=_aimed_enemy()
	if target==null: return
	_note_cloud.resize(notes,global_position)
	var idx:int=-1
	var best:float=note_range*note_range
	for i:int in mini(notes,_note_cloud.positions.size()):
		var distance:float=_note_cloud.positions[i].distance_squared_to(target.global_position)
		if distance<=best:
			idx=i
			best=distance
	if idx<0: return
	fire_note(target,idx)
	notes-=1
	_note_left=maxf(note_fire_interval,0.05)
func controlled_skill_action() -> void:
	if is_player_controlled() and active() and _recall!=null:
		var target:ball=_aimed_enemy()
		if target!=null: _recall.try_start(target)
func controlled_middle_action() -> void:
	if is_player_controlled() and active() and not dizziness and not is_damage_output_disabled(): _begin_cargo_throw(_aimed_enemy())
func _begin_cargo_throw(target:ball) -> void:
	if target==null: return
	if not U.line_clear(self,global_position,ball.body_point(target,global_position)): return
	if cargo.is_empty() or _return_left>0 or not _windup.is_empty(): return
	# Each cube guards itself: whichever is closest to the enemy strikes.
	var idx:int = -1
	var best:float = return_trigger
	for i:int in cargo.size():
		if i>=_cube_cloud.positions.size(): break
		var d:float = _cube_cloud.positions[i].distance_to(target.global_position)
		if d<best:
			best = d
			idx = i
	if idx<0: return
	var start:Vector2 = _cube_cloud.positions[idx]
	var aim:Vector2 = start.direction_to(ball.body_point(target,start))
	_windup = {"dir":aim.normalized() if aim!=Vector2.ZERO else Vector2.RIGHT,"target":weakref(target),"t":0.0,"idx":idx}

func spawn_recall_wave(point:Vector2,damage:float,authoritative:bool) -> Node2D:
	var wave:Node2D=preload("res://scripts/characters/我的世界/allay/recall_wave.gd").new()
	wave.source_ref=weakref(self)
	wave.damage=damage
	wave.max_radius=recall_wave_radius
	wave.authoritative=authoritative
	wave.position=point
	get_tree().current_scene.add_child(wave)
	return wave

@rpc("authority","call_remote","reliable")
func _allay_recall_wave(point:Vector2) -> void:
	spawn_recall_wave(point,0.0,false)

func _auto_fire_note() -> void:
	if notes<=0 or _note_left>0.0: return
	_note_cloud.resize(notes,global_position)
	var chosen:ball = null
	var index:int = -1
	var best:float = note_range*note_range
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,candidate) or not candidate.is_combat_lockable(): continue
		for i:int in mini(notes,_note_cloud.positions.size()):
			var distance:float = _note_cloud.positions[i].distance_squared_to(candidate.global_position)
			if distance<=best:
				best=distance; chosen=candidate; index=i
	if chosen==null: return
	fire_note(chosen,index)
	notes-=1
	_note_left=maxf(note_fire_interval,0.05)

func fire_note(target:ball,note_index:int=0) -> ball:
	var shot:ball = NOTE_SCENE.instantiate()
	shot.Master = self
	shot.Master_name = str(name)
	shot.Team = Team
	shot.Ignore_Team_Damage_Setting = true
	shot.Target_Enemy = target
	shot.target_ref = weakref(target)
	shot.Damage = int(attack_damage(0.45))
	shot.Speed = note_speed
	shot.life = note_lifetime
	shot.turn_rate = note_turn_rate
	shot.position = _note_cloud.take_at(note_index,global_position)
	shot.direction = shot.position.direction_to(ball.body_point(target,shot.position))
	shot.name = Game.return_random_name(shot)
	get_tree().current_scene.add_child(shot,true)
	shot.add_to_group("BattleTransient")
	_flash = 0.55
	play_sound("block.note_block.harp",-10.0)
	if _voice_rng.randf()<giggle_chance: play_sound("entity.allay.item_given",-6.0)
	return shot

func wind_offset(dir:Vector2,t:float) -> Vector2:
	if t<=0.0: return Vector2.ZERO
	if t<windup_back:
		var p:float = t/maxf(windup_back,0.01)
		return -dir*windup_pull*(1.0-pow(1.0-p,2.0))
	var q:float = clampf((t-windup_back)/maxf(windup_dash,0.01),0.0,1.0)
	return (-dir*windup_pull).lerp(dir*windup_reach,pow(q,1.5))

func _active_wind() -> Dictionary:
	if not _windup.is_empty(): return _windup
	if not is_multiplayer_authority() and _remote_wind.size()==4: return {"dir":Vector2(_remote_wind[0],_remote_wind[1]),"t":float(_remote_wind[2]),"idx":int(_remote_wind[3])}
	return {}

func _wind_step(delta:float) -> void:
	if _windup.is_empty(): return
	_windup["t"] = float(_windup["t"])+delta
	if float(_windup["t"]) < windup_back+windup_dash: return
	# Never type-test a freed instance. Accept raw references from an existing windup too.
	var candidate:Variant = _windup.get("target")
	if is_instance_valid(candidate) and candidate is WeakRef: candidate = candidate.get_ref()
	var target:ball = null
	if is_instance_valid(candidate) and candidate is ball:
		if not candidate.is_queued_for_deletion() and candidate.is_inside_tree() and candidate.health>0: target = candidate
	var widx:int = int(_windup.get("idx",0))
	var data:Dictionary = cargo[widx] if widx>=0 and widx<cargo.size() else {}
	var point:Vector2 = (_cube_cloud.positions[widx]+wind_offset(_windup["dir"],float(_windup["t"]))) if widx>=0 and widx<_cube_cloud.positions.size() else global_position
	var launched:Node2D = null
	if target != null and not data.is_empty(): launched = CAPTURE.launch(self,data,target,point)
	if launched != null:
		if widx<cargo.size(): cargo.pop_at(widx)
		_cube_cloud.take_at(widx,global_position)
		if _voice_rng.randf()<joy_chance: play_sound("entity.allay.item_thrown",-5.0)
		var aim:Vector2 = point.direction_to(ball.body_point(target,point)) if is_instance_valid(target) else Vector2(_windup["dir"])
		_spawn_burst(point,aim)
		if multiplayer.has_multiplayer_peer(): _allay_burst.rpc(point,aim)
		_flash = 1.0
		_return_left = maxf(return_interval,0.05)
	else:
		_return_left = 0.25
	_windup = {}

func _spawn_burst(point:Vector2,dir:Vector2) -> void:
	for i:int in range(12):
		var life:float = randf_range(0.28,0.5)
		_lines.append({"pos":point,"dir":dir.rotated(randf_range(-0.35,0.35)),"speed":randf_range(150.0,260.0),"len":randf_range(14.0,34.0),"life":life,"max":life})

@rpc("authority","call_remote","reliable")
func _allay_burst(point:Vector2,dir:Vector2) -> void:
	if not is_multiplayer_authority(): _spawn_burst(point,dir)

@rpc("authority","call_remote","reliable")
func _allay_absorb(point:Vector2) -> void:
	if is_multiplayer_authority(): return
	_cube_cloud.has_spawn = true
	_cube_cloud.next_spawn = point
	_absorbs.append({"from":point,"cur":point,"t":0.38,"dur":0.38,"idx":_remote_kinds.size()})

func collect_projectile(shot:Node,point:Vector2,orbit_index:int=-1,flying_note:Node=null) -> bool:
	if not active() or not is_instance_valid(shot): return false
	if not is_multiplayer_authority() or not shot.is_inside_tree() or not shot.is_multiplayer_authority(): return false
	if bool(shot.get_meta("allay_captured",false)): return false
	if flying_note != null:
		if not is_instance_valid(flying_note) or flying_note.is_queued_for_deletion() or flying_note._spent or flying_note.Master != self: return false
	elif orbit_index<0 or orbit_index>=mini(notes,_note_cloud.positions.size()): return false
	if not CAPTURE.hostile(self,shot): return false
	var data:Dictionary = CAPTURE.describe(shot)
	if data.is_empty(): return false
	# Consume exactly the note that made contact, not an arbitrary reserve note.
	if flying_note != null:
		flying_note._spent = true
		flying_note.queue_free()
	else:
		notes -= 1
		_note_cloud.take_at(orbit_index,global_position)
	var stored:bool = cargo.size()<cube_capacity and not bool(shot.get_meta("allay_returned",false))
	if stored: cargo.append(CAPTURE.NATIVE_RETURN.snapshot(shot,data))
	_cube_cloud.has_spawn = stored
	_cube_cloud.next_spawn = point
	_absorbs.append({"from":point,"cur":point,"t":0.38,"dur":0.38,"idx":cargo.size()-1 if stored else -1})
	if multiplayer.has_multiplayer_peer(): _allay_absorb.rpc(point)
	_flash = 1.0
	play_sound("entity.allay.item_given",-5.0)
	CAPTURE.discard(shot)
	return true

func _process(delta:float) -> void:
	_visual_delta = delta if health>0 and is_combat_runtime_active() else 0.0
	super._process(delta)

func _constrain_point(desired:Vector2) -> Vector2:
	var origin:Vector2 = global_position
	var p:Vector2 = desired
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world != null and "map_group" in world and world.map_group is Dictionary and world.map_group.has(world.now_choose_map):
		var rect:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
		p = p.clamp(rect.position+Vector2(6,6),rect.end-Vector2(6,6))
	if p.distance_squared_to(origin)>1.0:
		var query := PhysicsPointQueryParameters2D.new()
		query.collision_mask = 1
		query.position = p
		if not get_world_2d().direct_space_state.intersect_point(query,1).is_empty():
			# Squeeze back along the orbit toward the allay until the spot is clear.
			for f:float in [0.75,0.5,0.3,0.15,0.0]:
				var candidate:Vector2 = origin.lerp(p,f)
				query.position = candidate
				if get_world_2d().direct_space_state.intersect_point(query,1).is_empty(): return candidate
			return origin
	return p

func visual_mob() -> void:
	frame(NATIVE_FRAMES,&"fly" if velocity.length_squared()>25.0 else &"idle")
	image.position = _art_origin
	var w:Dictionary = _active_wind()
	var lean:float = 0.0
	if not w.is_empty():
		var sd:float = signf(Vector2(w["dir"]).x)
		if sd==0.0: sd = 1.0
		var wt:float = float(w["t"])
		lean = sd*(-0.07*clampf(wt/maxf(windup_back,0.01),0.0,1.0)) if wt<windup_back else sd*lerpf(-0.07,0.12,clampf((wt-windup_back)/maxf(windup_dash,0.01),0.0,1.0))
	image.rotation = lean
	image.scale = _image_base
	var tint:Color = Color.WHITE
	if _flash>0.0: tint = tint.lerp(Color(1.45,1.65,1.95),clampf(_flash,0.0,1.0)*0.8)
	image.modulate = tint
	_flash = maxf(0,_flash-_visual_delta*3.6)
	if not is_multiplayer_authority() and not _remote_wind.is_empty(): _remote_wind[2] = float(_remote_wind[2])+_visual_delta
	if _visual_delta>0.0 and not _lines.is_empty():
		for i:int in range(_lines.size()-1,-1,-1):
			var streak:Dictionary = _lines[i]
			streak["pos"] = Vector2(streak["pos"])+Vector2(streak["dir"])*float(streak["speed"])*_visual_delta
			streak["life"] = float(streak["life"])-_visual_delta
			if float(streak["life"])<=0.0: _lines.remove_at(i)
	var count:int = cargo.size() if is_multiplayer_authority() else _remote_kinds.size()
	_note_cloud.advance(notes,global_position,_view_clock,_visual_delta,30.0,1.4,1.0,0.0,0.0)
	_cube_cloud.advance(count,global_position,_view_clock,_visual_delta,34.0,-0.42,0.72,5.0,2.0,_constrain_point)
	if _visual_delta>0.0 and not _absorbs.is_empty():
		for i:int in range(_absorbs.size()-1,-1,-1):
			var a:Dictionary = _absorbs[i]
			var goal:Vector2 = global_position
			var ai:int = int(a["idx"])
			if ai>=0 and ai<_cube_cloud.positions.size(): goal = _cube_cloud.positions[ai]
			a["cur"] = Vector2(a["cur"]).lerp(goal,1.0-exp(-9.0*_visual_delta))
			a["t"] = float(a["t"])-_visual_delta
			if float(a["t"])<=0.0: _absorbs.remove_at(i)
	queue_redraw()
	if is_instance_valid(_note_visual): _note_visual.queue_redraw()

func _draw_notes() -> void:
	if health<=0 or not is_instance_valid(_note_visual): return
	for point:Vector2 in _note_cloud.positions:
		var p:Vector2 = _note_visual.to_local(point)
		_note_visual.draw_texture_rect(NOTE_TEXTURE,Rect2(p-Vector2.ONE*18,Vector2.ONE*36),false,Color(0.3,0.62,1,0.2))
		_note_visual.draw_texture_rect(NOTE_TEXTURE,Rect2(p-Vector2.ONE*13,Vector2.ONE*26),false,Color(0.3,0.62,1))

func _draw() -> void:
	if health<=0: return
	# All displayed particles use the unmodified vanilla particle textures.
	var wind:Dictionary = _active_wind()
	var wind_off:Vector2 = Vector2.ZERO
	var grow:float = 1.0
	var fade:float = 1.0
	var wind_idx:int = int(wind.get("idx",-1))
	if not wind.is_empty():
		grow = 1.0+0.3*clampf(float(wind["t"])/(windup_back+windup_dash),0.0,1.0)
		wind_off = wind_offset(wind["dir"],float(wind["t"]))
		if float(wind["t"])>windup_back: fade = 1.0-clampf((float(wind["t"])-windup_back)/maxf(windup_dash,0.01),0.0,1.0)
	for e:int in _cube_cloud.positions.size():
		var mine:bool = e==wind_idx
		var p:Vector2 = to_local(_cube_cloud.positions[e]+(wind_off if mine else Vector2.ZERO))
		var g:float = grow if mine else 1.0
		var a:float = fade if mine else 1.0
		draw_texture_rect_region(CUBE_TEXTURE,Rect2(p-Vector2.ONE*14*g,Vector2.ONE*28*g),Rect2(4,4,1,1),Color(0.15,0.65,1,0.17*a))
		draw_texture_rect_region(CUBE_TEXTURE,Rect2(p-Vector2.ONE*6*g,Vector2.ONE*12*g),Rect2(4,4,1,1),Color(0.35,0.85,1,a))
	for l:Dictionary in _lines:
		var sp:Vector2 = to_local(Vector2(l["pos"]))
		var k:float = clampf(float(l["life"])/maxf(float(l["max"]),0.01),0.0,1.0)
		var tail:Vector2 = sp-Vector2(l["dir"])*float(l["len"])*k
		draw_line(sp,tail,Color(0.35,0.8,1,0.22*k),5.0)
		draw_line(sp,tail,Color(0.55,0.9,1,0.9*k),1.6)
	for a:Dictionary in _absorbs:
		var q:float = 1.0-clampf(float(a["t"])/maxf(float(a["dur"]),0.01),0.0,1.0)
		var p:Vector2 = to_local(Vector2(a["cur"]))
		var s:float = 12.0-6.0*q
		preload("res://scripts/effects/我的世界/pixel_arc.gd").draw(self,to_local(Vector2(a["from"])),6.0+22.0*q,0.0,TAU,20,Color(0.4,0.85,1,0.4*(1.0-q)),1.5)
		draw_texture_rect_region(CUBE_TEXTURE,Rect2(p-Vector2.ONE*s,Vector2.ONE*s*2.0),Rect2(4,4,1,1),Color(0.15,0.65,1,0.3*(1.0-q*0.5)))
		draw_texture_rect_region(CUBE_TEXTURE,Rect2(p-Vector2.ONE*s*0.5,Vector2.ONE*s),Rect2(4,4,1,1),Color(0.55,0.9,1,0.55+0.45*(1.0-q)))

func voice_role() -> String: return "allay"

func tick_ambient(delta:float) -> void:
	_ambient_left -= delta
	if _ambient_left>0: return
	if is_instance_valid(_ambient_player) and _ambient_player.playing:
		_ambient_left = 0.1
		return
	var breath:AudioStreamPlayer2D = play_sound("entity.allay.ambient_without_item" if cargo.is_empty() else "entity.allay.ambient_with_item",-6.0)
	if breath != null and is_instance_valid(breath) and breath.stream != null:
		# The next breath waits at least as long as the clip that just played.
		_ambient_left = breath.stream.get_length()/maxf(breath.pitch_scale,0.01)+_voice_rng.randf_range(ambient_gap_min,ambient_gap_max)
	else:
		_ambient_left = 0.4

func hit_volume_db(amount:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(amount)

func notify_allay_hit(amount:float,point:Vector2) -> AudioStreamPlayer2D:
	var actual:float = maxf(amount,0.0)
	if actual<=0.0 or not active(): return null
	var critical:bool = actual>CRITICAL_HIT_DAMAGE
	var player:AudioStreamPlayer2D = MC_AUDIO.play(self,"entity.player.attack.crit" if critical else "entity.player.hurt",point,hit_volume_db(actual),false,true,true,true)
	if player != null and is_instance_valid(player):
		# Higher dealt damage pitches the vanilla hit sound upward.
		player.pitch_scale = clampf(0.9+actual*0.006,0.9,1.5)
	return player

func play_sound(event:String,volume_db:float=-5.0) -> AudioStreamPlayer2D:
	if not is_multiplayer_authority() or not NATIVE_SOUNDS.EVENTS.has(event): return null
	# Avoid turning a single shotgun volley into many overlapping pickup sounds.
	var now:int = Time.get_ticks_msec()
	if now-int(_native_sfx_left.get(event,-10000))<120: return null
	_native_sfx_left[event] = now
	var records:Array = NATIVE_SOUNDS.EVENTS[event]
	var index:int = _voice_rng.randi_range(0,records.size()-1)
	if multiplayer.has_multiplayer_peer(): _allay_sound.rpc(event,index,global_position,volume_db)
	return _allay_sound(event,index,global_position,volume_db)

@rpc("authority","call_remote","reliable")
func _allay_sound(event:String,index:int,point:Vector2,volume_db:float) -> AudioStreamPlayer2D:
	if not NATIVE_SOUNDS.EVENTS.has(event) or get_tree().current_scene==null: return null
	if get_tree().get_nodes_in_group("MCNativeSFX").size()>=24: return null
	var records:Array = NATIVE_SOUNDS.EVENTS[event]
	if index<0 or index>=records.size(): return null
	var record:Dictionary = records[index]
	var player:=AudioStreamPlayer2D.new()
	player.stream = record.stream
	player.volume_db = clampf(volume_db+linear_to_db(maxf(float(record.volume),0.01)),-16.0,3.0)
	player.pitch_scale = float(record.pitch)
	player.max_distance = 1700.0
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus=&"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("MCNativeSFX")
	player.add_to_group("BattleTransient")
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	if event.contains(".ambient_"): _ambient_player = player
	return player

func visual_state() -> Dictionary:
	var kinds:Array = []
	for data:Dictionary in cargo: kinds.append(data.kind)
	var wind:Array = [] if _windup.is_empty() else [_windup["dir"].x,_windup["dir"].y,_windup["t"],float(_windup.get("idx",0))]
	return {"time":clock,"notes":notes,"kinds":kinds,"wind":wind}

func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	notes = int(data.get("notes",0))
	_remote_kinds = data.get("kinds",[])
	var wind:Array = data.get("wind",[])
	if wind.is_empty() or wind.size()<4: _remote_wind = []
	elif _remote_wind.is_empty() or float(wind[2])+0.05 < float(_remote_wind[2]): _remote_wind = [wind[0],wind[1],float(wind[2]),float(wind[3])]
	else: _remote_wind[2] = maxf(float(_remote_wind[2]),float(wind[2]))

func Die() -> void:
	if _recall!=null: _recall.clear()
	if is_instance_valid(_note_visual): _note_visual.hide()
	notes = 0
	cargo.clear()
	_windup = {}
	_remote_wind = []
	_lines.clear()
	_absorbs.clear()
	_note_cloud.clear()
	_cube_cloud.clear()
	remove_from_group("MinecraftAllay")
	queue_redraw()
	super.Die()
