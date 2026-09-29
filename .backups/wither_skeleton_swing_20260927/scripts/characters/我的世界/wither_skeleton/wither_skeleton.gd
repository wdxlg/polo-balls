extends "res://scripts/characters/我的世界/new5/base.gd"
## One active move: two real stone-sword sweeps. Shared hurt-shape geometry,
## classified damage, status potency/source lifetimes, audio and death effects.
## The swing is a fully eased arc (wind-up, slash, re-wind, slash, follow-through)
## and closes with a smooth recover that eases blade and body back to idle.
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/wither_skeleton/frames.tres")
const POSES = preload("res://Images/characters/我的世界/wither_skeleton/poses.gd")
const STONE:Texture2D = preload("res://Images/characters/我的世界/wither_skeleton/stone_sword.png")
const VOICE = preload("res://scripts/effects/我的世界/mc_creature_voice.gd")
const SOUNDS = preload("res://scripts/characters/我的世界/wither_skeleton/sounds.gd")
const GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const WITHER_SECONDS:float = 3.0
const MAX_WITHER_LEVEL:int = 255 # Existing public potency limit, not a new balance cap.
const WINDOWS:Array[Vector2] = [Vector2(0.15,0.31),Vector2(0.41,0.57)]
const COMBO_DURATION:float = 0.74
const RECOVER_END:float = 0.98 # Damage ends at COMBO_DURATION; the blade then eases home.
const BODY_SCALE:float = 0.85 # 148 visible pixels -> ~126 world units, shared humanoid footprint.
const BODY_OFFSET_Y:float = -13.5 # Feet pixel 202 lands on the collider bottom (+63).
@export var blade_length:float = 14.0
@export var blade_radius:float = 2.0
@export var acquisition_range:float = 58.0
var combo_time:float = -1.0
var combo_heading:Vector2 = Vector2.RIGHT
var cooldown_left:float = 0.0
var swings_started:int = 0
var hits_landed:int = 0
var _hit_sets:Array[Dictionary] = [{},{}]
var _sounded:Array[bool] = [false,false]
var _damage_regions:Array[Dictionary] = []
var _revision:int = 0
var _accepted_revision:int = -1
var _accepted_clock:float = -1.0
var _wither_serial:int = 0
var _received_wither:int = 0
var _status_targets:Dictionary = {}
var _body_clip:StringName = &"idle"
var _body_frame:int = 0
var _prev_clip:StringName = &""
var _fade_t:float = 1.0
var _fade_sprite:Sprite2D
var _last_position:Vector2
var _walking:bool = false
var _sword:Sprite2D
var voice:Node

func _ready() -> void:
	Can_Attack = true
	Can_Skill = false
	set_meta("mc_hook_hurt_only",true)
	super._ready()
	_last_position = global_position
	add_to_group("MinecraftWitherSkeleton")
	voice = VOICE.new()
	voice.name = "NativeVoice"
	voice.unit = self
	voice.events = SOUNDS.EVENTS.duplicate()
	voice.events["swing"] = AUDIO.EVENTS["entity.player.attack.sweep"]
	voice.events["hit"] = AUDIO.EVENTS["entity.player.hurt"]
	voice.events["crit"] = AUDIO.EVENTS["entity.player.attack.crit"]
	add_child(voice)
	_sword = Sprite2D.new()
	_sword.name = "StoneSword"
	_sword.texture = STONE
	_sword.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sword.offset = Vector2(4.5,-4.5) # Original 16px sword: grip (3.5,12.5), tip (14,2).
	_sword.z_index = 3
	add_child(_sword)
	_sword.top_level = true
	_fade_sprite = Sprite2D.new()
	_fade_sprite.name = "BodyFade"
	_fade_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fade_sprite.visible = false
	image.add_child(_fade_sprite)
	visual_mob()

func player_control_action_ids() -> Array[StringName]: return [&"controlled_attack_action"]
func controlled_attack_action() -> void:
	if is_player_controlled(): begin_combo(player_control_aim_direction(direction))
func Attack() -> void:
	if is_player_controlled(): controlled_attack_action()
	else:
		var target:ball = U.nearest(self)
		if is_instance_valid(target) and global_position.distance_to(target.global_position) <= acquisition_range:
			begin_combo(global_position.direction_to(target.global_position))

func begin_combo(heading:Vector2) -> bool:
	if not can_act() or not is_combat_runtime_active() or combo_time >= 0.0 or cooldown_left > 0.0 or heading.is_zero_approx(): return false
	combo_heading = heading.normalized()
	combo_time = 0.0
	cooldown_left = maxf(Attack_Cooling,RECOVER_END)
	_hit_sets = [{},{}]
	_sounded = [false,false]
	Attacking = true
	_face_right = combo_heading.x >= 0.0
	_revision += 1
	_publish_pose()
	return true

func step_mob(delta:float) -> void:
	_damage_regions.clear()
	if not is_combat_runtime_active(): return
	cooldown_left = maxf(0.0,cooldown_left-delta)
	if not can_act():
		cancel_combo()
		return
	if combo_time >= 0.0:
		advance_combo(delta)
		return
	if is_player_controlled(): return
	var target:ball = U.nearest(self)
	if not is_instance_valid(target): return
	if not is_direction_change_locked(): direction = global_position.direction_to(target.global_position)
	if global_position.distance_to(target.global_position) <= acquisition_range and U.line_clear(self,global_position,target.global_position):
		begin_combo(global_position.direction_to(target.global_position))

func advance_combo(delta:float) -> void:
	_damage_regions.clear()
	if combo_time < 0.0 or not is_combat_runtime_active(): return
	if not can_act():
		cancel_combo()
		return
	var previous:float = combo_time
	var next:float = minf(combo_time+maxf(delta,0.0),RECOVER_END)
	# Interval intersection means even a long frame crosses each slash exactly once.
	for slash:int in range(2):
		var window:Vector2 = WINDOWS[slash]
		if next < window.x or previous > window.y: continue
		if not _sounded[slash]:
			_sounded[slash] = true
			swings_started += 1
			voice.request("swing",global_position,0.0)
		var a:float = clampf((previous-window.x)/(window.y-window.x),0.0,1.0)
		var b:float = clampf((next-window.x)/(window.y-window.x),0.0,1.0)
		var steps:int = maxi(1,ceili((b-a)*24.0))
		for i:int in range(steps+1):
			var progress:float = lerpf(a,b,float(i)/float(steps))
			var sample:float = lerpf(window.x,window.y,progress)
			var geometry:Dictionary = blade_segment(sample)
			_damage_regions.append(geometry)
			for contact:Dictionary in SWEEP.contacts(self,geometry.start,geometry.end,blade_radius,_hit_sets[slash],global_position):
				var target:ball = contact.target
				_hit_sets[slash][target.get_instance_id()] = true
				deal_sword_hit(target,contact.point)
	combo_time = next
	if combo_time >= RECOVER_END: cancel_combo()

func deal_sword_hit(target:ball,point:Vector2) -> bool:
	if not can_act() or not U.enemy(self,target) or target.health <= 0: return false
	var amount:float = attack_damage(1.0)
	var before:float = maxf(float(target.health),0.0)
	set_meta("blood_damage_kind","slash")
	var accepted:bool = target.receive_classified_positional_damage(amount,point,&"ordinary",false,self)
	var actual:float = maxf(before-(maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0),0.0)
	if not accepted or actual <= 0.0: return false
	hits_landed += 1
	voice.request("crit" if actual > 50.0 else "hit",point,GAIN.damage_gain(actual))
	if is_instance_valid(target) and target.health > 0: apply_stacking_wither(target)
	return true

func apply_stacking_wither(target:ball) -> bool:
	if not can_act() or not U.enemy(self,target): return false
	var level:int = mini(EFFECTS.level_of(target,"wither")+1,MAX_WITHER_LEVEL)
	if not EFFECTS.apply_effect(target,"wither",level,WITHER_SECONDS,self): return false
	_status_targets[target.get_instance_id()] = weakref(target)
	_wither_serial += 1
	if multiplayer.has_multiplayer_peer(): _receive_wither.rpc(_wither_serial,get_tree().current_scene.get_path_to(target),level,WITHER_SECONDS)
	return true

@rpc("authority","call_remote","reliable")
func _receive_wither(serial:int,path:NodePath,level:int,remaining:float) -> void:
	if serial <= _received_wither: return
	_received_wither = serial
	var target:ball = get_tree().current_scene.get_node_or_null(path) as ball
	if is_instance_valid(target): EFFECTS.apply_effect(target,"wither",clampi(level,1,MAX_WITHER_LEVEL),clampf(remaining,0.0,WITHER_SECONDS),self)

func cancel_combo() -> void:
	_damage_regions.clear()
	if combo_time < 0.0: return
	combo_time = -1.0
	Attacking = false
	_revision += 1
	_publish_pose()

func move(speed:float,delta:float) -> void:
	# Player WASD stays independent. AI slows while committing a melee combination.
	super.move(speed*(0.3 if combo_time >= 0.0 and not is_player_controlled() else 1.0),delta)

func tick_physics(state:State,delta:float) -> void:
	if health <= 0 or dizziness or is_damage_output_disabled() or not Can_Attack: cancel_combo()
	_walking = global_position.distance_squared_to(_last_position) > 0.0009
	_last_position = global_position
	if _fade_t < 1.0:
		_fade_t = minf(1.0,_fade_t+delta/0.12)
		if is_instance_valid(_fade_sprite):
			_fade_sprite.modulate.a = 1.0-_fade_t*_fade_t
			_fade_sprite.visible = _fade_t < 1.0
	super.tick_physics(state,delta)

func body_pose(time:float) -> Dictionary:
	if time >= 0.0 and time < COMBO_DURATION:
		var start:float = 0.0 if time < 0.36 else 0.36
		return {"clip":&"attack","index":clampi(int((time-start)/0.31*15.0),0,15)}
	var clip:StringName = &"walk" if _walking else &"idle"
	return {"clip":clip,"index":int(_view_clock*FRAMES.get_animation_speed(clip))%FRAMES.get_frame_count(clip)}

func _hand_pixel(xy:Array) -> Vector2:
	var pixel:Vector2 = Vector2(float(xy[0])-80.0,float(xy[1])-112.0)+image.offset
	if _face_right: pixel.x = -pixel.x # Original orthographic model faces left.
	return image.global_transform * pixel

func _attack_hand(time:float) -> Vector2:
	var start:float = 0.0 if time < 0.36 else 0.36
	var index:int = clampi(int((time-start)/0.31*15.0),0,15)
	return _hand_pixel(POSES.HANDS["attack"][index])

func _rest_hand() -> Vector2:
	var clip:StringName = &"walk" if _walking else &"idle"
	var index:int = int(_view_clock*FRAMES.get_animation_speed(clip))%FRAMES.get_frame_count(clip)
	return _hand_pixel(POSES.HANDS[str(clip)][index])

func hand_position(time:float) -> Vector2:
	if time < 0.0: return _rest_hand()
	if time >= COMBO_DURATION:
		# Recover: the grip glides from the follow-through pose back to the idle hand.
		var p:float = _eo((time-COMBO_DURATION)/(RECOVER_END-COMBO_DURATION))
		return _attack_hand(0.735).lerp(_rest_hand(),p)
	var hand:Vector2 = _attack_hand(time)
	for window:Vector2 in WINDOWS:
		if time >= window.x and time <= window.y:
			hand += combo_heading*(sin(PI*(time-window.x)/(window.y-window.x))*2.0)
	return hand

func _ss(t:float) -> float:
	t = clampf(t,0.0,1.0)
	return t*t*(3.0-2.0*t)

func _eo(t:float) -> float:
	t = clampf(t,0.0,1.0)
	return 1.0-(1.0-t)*(1.0-t)*(1.0-t)

func rest_angle() -> float: return 0.85 if _face_right else PI-0.85

func blade_angle(time:float) -> float:
	if time < 0.0: return rest_angle()
	var base:float = combo_heading.angle()
	if time >= COMBO_DURATION:
		# Recover: ease the blade from the follow-through back to the held rest angle.
		var p:float = _eo((time-COMBO_DURATION)/(RECOVER_END-COMBO_DURATION))
		return lerp_angle(base+deg_to_rad(112.0),rest_angle(),p)
	var degrees:float
	if time < WINDOWS[0].x:
		# Wind-up starts exactly at the held rest angle: no snap when the combo begins.
		var start_rel:float = rad_to_deg(wrapf(rest_angle()-base,-PI,PI))
		degrees = lerpf(start_rel,-78.0,_eo(time/WINDOWS[0].x))
	elif time <= WINDOWS[0].y:
		degrees = lerpf(-78.0,86.0,_ss((time-WINDOWS[0].x)/(WINDOWS[0].y-WINDOWS[0].x)))
	elif time < WINDOWS[1].x:
		degrees = lerpf(86.0,-78.0,_ss((time-WINDOWS[0].y)/(WINDOWS[1].x-WINDOWS[0].y)))
	elif time <= WINDOWS[1].y:
		degrees = lerpf(-78.0,86.0,_ss((time-WINDOWS[1].x)/(WINDOWS[1].y-WINDOWS[1].x)))
	else:
		degrees = lerpf(86.0,112.0,_eo((time-WINDOWS[1].y)/(COMBO_DURATION-WINDOWS[1].y)))
	return base+deg_to_rad(degrees)

func blade_segment(time:float) -> Dictionary:
	var grip:Vector2 = hand_position(time)
	var heading:Vector2 = Vector2.RIGHT.rotated(blade_angle(time))
	return {"shape":"segment","start":grip+heading*4.0,"end":grip+heading*blade_length,"radius":blade_radius,"damage":attack_damage(1.0),"source":self,"kind":"wither_skeleton_sword"}

func visual_mob() -> void:
	if not is_instance_valid(_sword) or health <= 0: return
	if combo_time < 0.0 and absf(direction.x) > 0.01: _face_right = direction.x > 0.0
	set_character_visual_flip_h(_face_right)
	var pose:Dictionary = body_pose(combo_time)
	if _prev_clip == &"attack" and pose.clip != &"attack" and is_instance_valid(_fade_sprite):
		# Cross-fade the last attack frame out so the body never pops back to idle.
		_fade_sprite.texture = FRAMES.get_frame_texture(&"attack",15)
		_fade_sprite.modulate.a = 1.0
		_fade_sprite.visible = true
		_fade_t = 0.0
	_prev_clip = pose.clip
	_body_clip = pose.clip
	_body_frame = pose.index
	image.texture = FRAMES.get_frame_texture(_body_clip,_body_frame)
	if is_instance_valid(_fade_sprite) and image is Sprite2D: _fade_sprite.flip_h = (image as Sprite2D).flip_h
	_sword.global_position = hand_position(combo_time)
	_sword.global_rotation = blade_angle(combo_time)+PI/4.0
	_sword.global_scale = Vector2.ONE*(blade_length/Vector2(10.5,-10.5).length())

func get_preview_texture() -> Texture2D: return FRAMES.get_frame_texture(&"idle",0)
func get_debug_attack_regions() -> Array[Dictionary]:
	if health <= 0 or dizziness or not Can_Attack or is_damage_output_disabled() or not is_combat_runtime_active(): return []
	return _damage_regions
func get_ai_attack_threats(_receiver:ball) -> Array: return get_debug_attack_regions()
func get_debug_detection_regions() -> Array[Dictionary]:
	if health <= 0 or dizziness or not Can_Attack or not is_combat_runtime_active(): return []
	if combo_time >= 0.0:
		if not _damage_regions.is_empty(): return []
		var region:Dictionary = blade_segment(combo_time)
		region.damage = 0.0
		return [region]
	return [{"shape":"circle","position":global_position,"radius":acquisition_range}]

func visual_state() -> Dictionary:
	return {"time":clock,"revision":_revision,"combo":combo_time,"heading":combo_heading,"cooldown":cooldown_left,"walking":_walking,"face_right":_face_right}
func accept_visual(data:Dictionary) -> void:
	var rev:int = int(data.get("revision",-1))
	var stamp:float = float(data.get("time",0.0))
	if rev < _accepted_revision or (rev == _accepted_revision and stamp < _accepted_clock): return
	_accepted_revision = rev
	_accepted_clock = stamp
	super.accept_visual(data)
	combo_time = float(data.get("combo",-1.0))
	combo_heading = data.get("heading",Vector2.RIGHT)
	cooldown_left = float(data.get("cooldown",0.0))
	_walking = bool(data.get("walking",false))
	_damage_regions.clear()
	for window:Vector2 in WINDOWS:
		if combo_time >= window.x and combo_time <= window.y: _damage_regions.append(blade_segment(combo_time))
func client_visual_step(delta:float) -> void:
	if not is_combat_runtime_active(): return
	_damage_regions.clear()
	if combo_time >= 0.0:
		combo_time += delta
		if combo_time >= RECOVER_END: combo_time = -1.0
		for window:Vector2 in WINDOWS:
			if combo_time >= window.x and combo_time <= window.y: _damage_regions.append(blade_segment(combo_time))
func _publish_pose() -> void:
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _receive_pose.rpc(visual_state())
@rpc("authority","call_remote","reliable")
func _receive_pose(data:Dictionary) -> void: accept_visual(data)
func _request_initial_state() -> void:
	if multiplayer.has_multiplayer_peer(): _request_combat_snapshot.rpc_id(get_multiplayer_authority())
@rpc("any_peer","call_remote","reliable")
func _request_combat_snapshot() -> void:
	if not is_multiplayer_authority(): return
	var layers:Array = []
	for ref:WeakRef in _status_targets.values():
		var target:ball = ref.get_ref() as ball
		if not is_instance_valid(target): continue
		var status:Node = EFFECTS.current(target,"wither")
		if status == null or status.is_queued_for_deletion(): continue
		var own:Dictionary = status.applications.get(get_instance_id(),{})
		if own.is_empty(): continue
		layers.append({"path":get_tree().current_scene.get_path_to(target),"level":own.grade,"remaining":own.time})
	_receive_combat_snapshot.rpc_id(multiplayer.get_remote_sender_id(),visual_state(),_wither_serial,layers)
@rpc("authority","call_remote","reliable")
func _receive_combat_snapshot(pose:Dictionary,serial:int,layers:Array) -> void:
	accept_visual(pose)
	if serial < _received_wither: return
	_received_wither = serial
	for layer:Dictionary in layers:
		var target:ball = get_tree().current_scene.get_node_or_null(layer.path) as ball
		if is_instance_valid(target): EFFECTS.apply_effect(target,"wither",clampi(int(layer.level),1,MAX_WITHER_LEVEL),clampf(float(layer.remaining),0.0,WITHER_SECONDS),self)

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if is_instance_valid(voice) and health > 0 and amount > 0.0 and _voice_rng.randf() < hurt_voice_chance:
		voice.request("hurt",global_position,-3.0)
func Die() -> void:
	cancel_combo()
	if is_instance_valid(voice): voice.request("death",global_position,0.0)
	if is_instance_valid(_sword): _sword.hide()
	if is_instance_valid(_fade_sprite): _fade_sprite.hide()
	super.Die() # Retains project default death sound/lifecycle.
@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	if is_instance_valid(_sword): _sword.hide()
	if is_instance_valid(_fade_sprite): _fade_sprite.hide()
	DEATH_FX.death_pose(self,image,_face_right)
func get_armor_test_effect_summary() -> String:
	if str(Game.current_locale).begins_with("en"):
		return "Strike twice with a stone sword; each slash can hit each enemy once.\nEach damaging hit inflicts Wither I for 3 seconds. If Wither is already active, raise its current level by one and refresh this source to 3 seconds (maximum 255). Existing sources keep their own remaining time.\nControl with C: WASD moves, the mouse aims, and left click starts the two-slash combination. Stun, death or disabled attacks cancel unfinished slashes."
	return "手持石剑连续砍两下，每刀对同一敌人最多命中一次。\n每刀实际造成伤害后施加3秒凋零；没有凋零时为I级，已有凋零则在当前等级上提升一级，并刷新本来源为3秒（公共上限255级）。其他来源保留自己的剩余时间。\nC键手控：WASD移动、鼠标瞄准、左键两连砍。眩晕、死亡或禁攻会取消尚未完成的砍击。"
