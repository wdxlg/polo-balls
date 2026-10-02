extends Node
## Mojang Bedrock bone animations baked offline, not whole-image oscillation.
## Full-frame Texture2Ds deliberately preserve the existing shader's 0..1 UV,
## hit tint, facing, afterimages and death snapshots. No runtime 3D or disk reads.
const CATCH_LAYERS=preload("res://Images/characters/我的世界/native_frames/catch_recoil/catch_layers.gd")
const HAND_LAYERS = preload("res://Images/characters/我的世界/native_frames/hand_pounce/drowned_hand_layers.gd")
const SPIDER_ACTIONS = preload("res://Images/characters/我的世界/native_frames/hand_pounce/spider_pounce.tres")
const DROWNED_HANDS = preload("res://Images/characters/我的世界/native_frames/drowned_hands.gd")
const MC_LEGS = preload("res://scripts/effects/我的世界/mc_legs.gd")
const FRAMES:Dictionary = {
	"enderman":preload("res://Images/characters/我的世界/native_frames/enderman.tres"),
	"evoker":preload("res://Images/characters/我的世界/native_frames/evoker.tres"),
	"vex":preload("res://Images/characters/我的世界/native_frames/vex.tres"),
	"spider":preload("res://Images/characters/我的世界/native_frames/spider.tres"),
	"drowned":preload("res://Images/characters/我的世界/native_frames/drowned.tres"),
	"shulker":preload("res://Images/characters/我的世界/native_frames/shulker.tres"),
}
const BOUNDS:Dictionary = {"enderman": [59, 45, 107, 214], "evoker": [34, 43, 116, 202], "vex": [43, 94, 147, 174], "shulker": [37, 129, 123, 208], "spider": [19, 94, 143, 161], "drowned": [29, 56, 117, 201]}
var unit:ball
var role:String
var frames:SpriteFrames
var sprite:Sprite2D
var current_clip:StringName = &""
var frame_index:int = -1
var clip_time:float = 0.0
var shell_peek:float = 0.0
var ready_visual:bool = false
var _cast_left:float = 0.0
var _evoker_celebrate_left:float = 0.0
var _evoker_remote_left:float = 0.0
var _attack_left:float = 0.0
var _attack_facing:int = 0
var _remote_action_facing:int = 0
var _action_left:float = 0.0
var _action_clip:StringName = &""
var _moving_left:float = 0.0
var _last_position:Vector2
var _motion_rate:float = 1.0
var _remote_pose:String = ""
var _last_sent_pose:String = ""
var _network_wait:float = 0.0
var _semantic_pose:String = ""
## 独立腿部步态（mc_legs.gd）：走路相位由真实位移/标准移速推进，上半身动作期间腿照常迈。
var gait:RefCounted
var legs_key:String = ""
var _leg_index:int = -1

static func attach(target:ball, kind:String) -> Node:
	if not FRAMES.has(kind): return null
	var driver:Node = load("res://scripts/effects/我的世界/mc_native_animation.gd").new()
	driver.name = "MinecraftAnimation"
	driver.unit = target
	driver.role = kind
	target.add_child(driver)
	return driver

func _ready() -> void:
	# Character-specific _ready() still initializes shell anchors and visual scale.
	call_deferred("_setup")

func _setup() -> void:
	if not is_instance_valid(unit) or not unit.image is Sprite2D: return
	sprite = unit.image as Sprite2D
	if sprite.texture == null: return
	frames = FRAMES[role] as SpriteFrames
	if role=="drowned":
		frames=frames.duplicate() as SpriteFrames
		# Dedicated native arm recoil: hand goes behind the throwing pose, then settles.
		for suffix:String in ["","_empty"]:
			var source_clip:StringName=StringName("throw"+suffix)
			var catch_clip:StringName=StringName("catch"+suffix)
			if not frames.has_animation(source_clip): continue
			frames.add_animation(catch_clip)
			frames.set_animation_loop(catch_clip,false)
			var count:int=CATCH_LAYERS.FRAMES.size()
			frames.set_animation_speed(catch_clip,float(count)/maxf(unit.trident_catch_duration,0.01))
			for frame:Dictionary in CATCH_LAYERS.FRAMES: frames.add_frame(catch_clip,frame.body)
	if role=="spider":
		frames = frames.duplicate() as SpriteFrames
		for clip:StringName in SPIDER_ACTIONS.get_animation_names():
			if frames.has_animation(clip): frames.remove_animation(clip)
			frames.add_animation(clip)
			frames.set_animation_speed(clip,SPIDER_ACTIONS.get_animation_speed(clip))
			frames.set_animation_loop(clip,SPIDER_ACTIONS.get_animation_loop(clip))
			for i:int in range(SPIDER_ACTIONS.get_frame_count(clip)):
				frames.add_frame(clip,SPIDER_ACTIONS.get_frame_texture(clip,i))
	var old_texture:Texture2D = sprite.texture
	var old_scale:Vector2 = sprite.scale
	var old_position:Vector2 = sprite.position
	var old_bounds:Rect2i = Rect2i(Vector2i.ZERO,Vector2i(old_texture.get_size()))
	var source:Image = unit._get_cached_after_image_source_image(old_texture)
	if source != null and not source.is_empty(): old_bounds = source.get_used_rect()
	var bounds:Array = BOUNDS[role]
	var neutral:Rect2 = Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]-bounds[0]),float(bounds[3]-bounds[1]))
	var fit:float = float(old_bounds.size.y) * absf(old_scale.y) / maxf(neutral.size.y,1.0)
	if role == "shulker": fit = 100.0 / neutral.size.x
	elif role == "vex": fit = 70.0 / neutral.size.x
	elif role == "spider": fit = float(old_bounds.size.x) * absf(old_scale.x) / maxf(neutral.size.x,1.0)
	var foot:float = old_position.y + (float(old_bounds.end.y)-old_texture.get_height()*0.5)*old_scale.y
	if role == "shulker": foot = float(unit.get("_shell_anchor_y"))
	sprite.scale = Vector2.ONE * fit
	sprite.position = Vector2(old_position.x,foot-(neutral.end.y-112.0)*fit)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_last_position = unit.global_position
	var walk_cycle:float = float(frames.get_frame_count(&"walk"))/maxf(frames.get_animation_speed(&"walk"),0.001) if frames.has_animation(&"walk") else 1.0
	legs_key = role if MC_LEGS.layer_data(role) != null else ""
	gait = MC_LEGS.for_set(legs_key,walk_cycle) if not legs_key.is_empty() else MC_LEGS.create(walk_cycle)
	gait.observe(unit)
	MC_LEGS.prewarm(legs_key)
	if role in ["enderman","spider"] and unit.self_hitbox != null:
		unit.self_hitbox.on_hit.connect(_on_contact_attack)
	ready_visual = true
	_set_clip(&"closed" if role == "shulker" else &"fly" if role == "vex" else &"idle")
	_render_frame()
	unit.refresh_character_ground_shadow()

func trigger_cast(duration:float = 0.65) -> void:
	if role == "evoker": _evoker_celebrate_left = 0.0 # A real new spell supersedes an old victory gesture.
	_cast_left = maxf(_cast_left,duration)
	if role in ["evoker","spider"] and ready_visual:
		_set_clip(&"cast")
		_render_frame()

func trigger_evoker_celebration(duration:float = 1.6) -> void:
	if role != "evoker": return
	_evoker_celebrate_left = maxf(duration,0.0)
	_cast_left = 0.0
	if ready_visual:
		_set_clip(&"celebrate")
		_render_frame()

func trigger_action(clip:StringName,duration:float = 0.4) -> void:
	if role not in ["drowned","spider"] or frames==null or not frames.has_animation(clip): return
	# A throw must not be interrupted by a lower-priority splash in the same tick.
	if clip == &"splash" and _action_clip in [&"throw",&"catch"] and _action_left > 0.0: return
	_action_clip = clip
	_action_left = maxf(duration,0.0)
	if ready_visual and _action_left > 0.0:
		_set_clip(StringName(_local_pose()))
		clip_time = 0.0
		frame_index = -1
		_render_frame()

func _on_contact_attack(_hurt:hurtbox) -> void:
	if not unit.is_multiplayer_authority() or unit.health <= 0 or unit.dizziness: return
	if _attack_left > 0.12: return
	_attack_facing = 0
	_attack_left = 0.28 if role=="spider" else 0.5
	clip_time = 0.0
	if role=="spider" and ready_visual:
		_set_clip(&"attack")
		frame_index = -1
		_render_frame()

func trigger_spider_impact(point:Vector2) -> void:
	if role!="spider": return
	_on_contact_attack(null)
	_attack_facing = int(signf(point.x-unit.global_position.x))
	_face_spider_action("attack")
func _face_spider_action(pose:String) -> int:
	if role!="spider" or pose not in ["lunge","lunge_air","attack"]: return 0
	var face:int = _attack_facing if pose=="attack" else int(signf(unit._lunge_direction.x))
	if not unit.is_multiplayer_authority(): face = _remote_action_facing
	if face!=0: unit.set_character_visual_flip_h(face>0 if unit.dir_left else face<0)
	return face
func _process(delta:float) -> void:
	advance(delta)

func advance(delta:float) -> void:
	if not ready_visual or not is_instance_valid(unit): return
	_last_position = unit.global_position
	# Do not use mc_live(): it is authority-only and would freeze all clients.
	if unit.health <= 0 or get_tree().paused or Game.now_stop_state:
		gait.observe(unit)
		return
	if role in ["spider","drowned"] and unit.dizziness:
		gait.observe(unit)
		return
	# Let a pending Evoker gesture finish after combat closes, but preserve pause.
	var evoker_finishing:bool = role == "evoker" and (_cast_left > 0.0 or _evoker_celebrate_left > 0.0 or _evoker_remote_left > 0.0 or current_clip in [&"cast",&"celebrate"])
	if not unit.is_combat_runtime_active() and not evoker_finishing:
		gait.observe(unit)
		return
	var step:float = maxf(delta,0.0)
	if role == "evoker":
		_evoker_celebrate_left = maxf(0.0,_evoker_celebrate_left-step)
		_evoker_remote_left = maxf(0.0,_evoker_remote_left-step)
		if _evoker_remote_left <= 0.0: _remote_pose = ""
		if unit.dizziness: _cast_left = 0.0
	_cast_left = maxf(0.0,_cast_left-step)
	_attack_left = maxf(0.0,_attack_left-step)
	_action_left = maxf(0.0,_action_left-step)
	# Legs advance from real displacement regardless of attack/cast/throw upper-body clips.
	var stepping:bool = not unit.dizziness
	if role == "spider" and float(unit.get("_lunge_left")) > 0.0: stepping = false # airborne pounce, not a stride
	gait.tick(unit,step,stepping)
	_moving_left = 0.0 if gait.at_rest else 0.12
	var desired:String = _local_pose()
	if not unit.is_multiplayer_authority() and not _remote_pose.is_empty(): desired = _remote_pose
	_semantic_pose = desired
	var action_facing:int = _face_spider_action(desired)
	if role == "shulker":
		# Reversible peek interpolation: changing gravity never re-anchors the image,
		# and closing halfway through opening does not jump to an endpoint.
		var target_peek:float = 1.0 if desired == "shell_open" else 0.0
		shell_peek = move_toward(shell_peek,target_peek,step/0.5)
		if shell_peek <= 0.00001: _set_clip(&"closed")
		elif shell_peek >= 0.99999: _set_clip(&"hold")
		else: _set_clip(&"open" if target_peek > shell_peek else &"close")
	else:
		_set_clip(StringName(desired))
	clip_time += step
	_render_frame()
	# Keep these block-model characters rigid; retain shader facing and hit tint.
	sprite.set_instance_shader_parameter("motion_params",Vector4.ZERO)
	sprite.set_instance_shader_parameter("bounce_params_a",Vector4(1.0,0.0,0.0,0.0))
	_network_wait -= step
	if unit.is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and (_network_wait <= 0.0 or desired != _last_sent_pose):
		_network_wait = 0.2
		_last_sent_pose = desired
		_receive_pose.rpc(desired,clip_time,shell_peek,action_facing)

func _local_pose() -> String:
	match role:
		"enderman":
			var rage:Variant = unit.get("rage_remaining") # clones have no rage field
			var prefix:String = "angry_" if rage != null and float(rage)>0.0 else ""
			return prefix + ("attack" if _attack_left>0.0 else "walk" if _moving_left>0.0 else "idle")
		"evoker":
			if _evoker_celebrate_left > 0.0: return "celebrate"
			return "cast" if _cast_left>0.0 else "walk" if _moving_left>0.0 else "idle"
		"spider":
			if _attack_left>0.0: return "attack"
			if float(unit.get("_lunge_left")) > 0.0: return "lunge" if float(unit.get("_lunge_elapsed"))<0.12 else "lunge_air"
			if _action_left>0.0: return str(_action_clip)
			return "cast" if _cast_left>0.0 else "walk" if _moving_left>0.0 else "idle"
		"drowned":
			var pose:String = str(_action_clip) if _action_left>0.0 else "walk" if _moving_left>0.0 else "idle"
			return pose if bool(unit.get("has_trident")) else pose+"_empty"
		"vex": return "charge" if bool(unit.get("_charging")) or float(unit.get("_windup"))>0.0 else "fly"
		"shulker": return "shell_open" if bool(unit.get("shell_open")) else "shell_closed"
	return "idle"

@rpc("any_peer","call_remote","unreliable_ordered")
func _receive_pose(pose:String,time:float,peek:float,action_facing:int = 0) -> void:
	# Dynamic summon ownership can change after add_child; validate against parent,
	# not this presentation-only child's default multiplayer authority.
	if multiplayer.get_remote_sender_id() != unit.get_multiplayer_authority(): return
	if role == "shulker":
		if pose not in ["shell_open","shell_closed"]: return
		if _remote_pose.is_empty(): shell_peek = clampf(peek,0.0,1.0)
	elif frames != null and not frames.has_animation(StringName(pose)): return
	_remote_action_facing = clampi(action_facing,-1,1)
	_remote_pose = pose
	if role == "evoker": _evoker_remote_left = 0.6 # lease renewed by 0.2s pose updates; no sticky lost end packet
	if role != "shulker": _set_clip(StringName(pose))
	clip_time = maxf(time,0.0)

func _set_clip(clip:StringName) -> void:
	if current_clip == clip: return
	if frames == null or not frames.has_animation(clip): return
	current_clip = clip
	clip_time = 0.0
	frame_index = -1

func _render_frame() -> void:
	if frames == null or current_clip == &"": return
	var count:int = frames.get_frame_count(current_clip)
	if count == 0: return
	var next:int = int(floor(clip_time * frames.get_animation_speed(current_clip)))
	if current_clip == &"open": next = int(round(shell_peek*float(count-1)))
	elif current_clip == &"close": next = int(round((1.0-shell_peek)*float(count-1)))
	elif frames.get_animation_loop(current_clip): next %= count
	next = clampi(next,0,count-1)
	if _is_walk_clip(current_clip): next = gait.walk_index(count)
	# Upper-body action while the legs are still walking/settling: composite walking legs.
	var leg:int = -1
	if not legs_key.is_empty() and not gait.at_rest and MC_LEGS.has_upper(legs_key,current_clip):
		leg = gait.walk_index(int(MC_LEGS.layer_data(legs_key).WALK))
	if next == frame_index and leg == _leg_index: return
	frame_index = next
	_leg_index = leg
	if leg >= 0:
		var composed:Texture2D = MC_LEGS.compose(legs_key,current_clip,next,leg)
		if composed != null:
			sprite.texture = composed
			return
	if role=="drowned":
		var record:Dictionary = hand_frame_record()
		sprite.texture = record.body if not record.is_empty() else frames.get_frame_texture(current_clip,next)
	else:
		sprite.texture = frames.get_frame_texture(current_clip,next)

func refresh_trident_pose() -> void:
	# Catch/refill is an inventory change, not locomotion: update even while stunned.
	if role!="drowned" or not ready_visual: return
	_action_left = 0.0
	_action_clip = &""
	_set_clip(StringName(_local_pose()))
	_render_frame()

func hand_frame_record() -> Dictionary:
	if str(current_clip).begins_with("catch"):
		return CATCH_LAYERS.FRAMES[clampi(frame_index,0,CATCH_LAYERS.FRAMES.size()-1)]
	return HAND_LAYERS.frame(current_clip,frame_index)
func hand_world_position() -> Vector2:
	if role!="drowned" or not ready_visual or not is_instance_valid(sprite): return unit.global_position
	if str(current_clip).begins_with("catch"):
		var record:Dictionary=hand_frame_record()
		if not record.is_empty():
			var grip:Vector2=record.grip
			if unit._visual_facing_flipped_h: grip.x=-grip.x
			return sprite.to_global(grip)
	var track:Array = DROWNED_HANDS.TRACKS.get(str(current_clip),[])
	if track.is_empty(): return unit.global_position
	var point:Vector2 = track[clampi(frame_index,0,track.size()-1)]-Vector2(80,112)
	if unit._visual_facing_flipped_h: point.x = -point.x
	return sprite.to_global(point)

func _is_walk_clip(clip:StringName) -> bool:
	return str(clip).ends_with("walk") or clip == &"walk_empty"
