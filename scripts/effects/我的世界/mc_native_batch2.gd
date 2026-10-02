extends Node
## Second native-model batch. Visual-only: never calls Attack, moves a body,
## resizes a hitbox, consumes RNG, or schedules gameplay damage.
const FRAMES:Dictionary = {
	"witch":preload("res://Images/characters/我的世界/native_frames/witch.tres"),
	"blaze":preload("res://Images/characters/我的世界/native_frames/blaze.tres"),
	"creeper":preload("res://Images/characters/我的世界/native_frames/creeper.tres"),
	"silverfish":preload("res://Images/characters/我的世界/native_frames/silverfish.tres"),
	"skeleton":preload("res://Images/characters/我的世界/native_frames/skeleton.tres"),
}
const BOUNDS:Dictionary = {"witch": [40, 37, 111, 204], "blaze": [41, 56, 133, 183], "creeper": [48, 57, 112, 197], "silverfish": [59, 125, 138, 167], "skeleton": [19, 55, 109, 203]}
const MC_LEGS = preload("res://scripts/effects/我的世界/mc_legs.gd")
const WITCH_MOUTH:Vector2 = Vector2(66.35,114.36093537489617)
var unit:ball
var role:String
var sprite:Node2D
var frames:SpriteFrames
var ready_visual:bool = false
var current_clip:StringName = &""
var frame_index:int = -1
var clip_time:float = 0.0
var fuse_progress:float = 0.0
var _moving_left:float = 0.0
var _shoot_left:float = 0.0
var _last_position:Vector2
var _remote_pose:String = ""
var _remote_fuse:float = 0.0
var _network_wait:float = 0.0
var _last_sent_pose:String = ""
## 独立腿部步态（mc_legs.gd）：腿由真实位移/自身标准移速推进，女巫喝药、骷髅拉弓、苦力怕引爆时照常迈步。
var gait:RefCounted
var legs_key:String = ""
var _leg_index:int = -1

static func attach(target:ball,kind:String) -> Node:
	if not FRAMES.has(kind): return null
	var driver:Node = load("res://scripts/effects/我的世界/mc_native_batch2.gd").new()
	driver.name = "MinecraftNativeAnimation"
	driver.unit = target
	driver.role = kind
	target.add_child(driver)
	return driver

func _ready() -> void: call_deferred("_setup")

func _setup() -> void:
	if not is_instance_valid(unit): return
	sprite = unit.image as Node2D
	if not sprite is Sprite2D and not sprite is AnimatedSprite2D: return
	var old:Texture2D
	if sprite is Sprite2D: old = (sprite as Sprite2D).texture
	else:
		var animated := sprite as AnimatedSprite2D
		old = animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
		animated.pause()
	if old == null: return
	var bounds:Rect2i = unit._get_cached_after_image_source_image(old).get_used_rect()
	var data:Array = BOUNDS[role]
	var neutral := Rect2(float(data[0]),float(data[1]),float(data[2]-data[0]),float(data[3]-data[1]))
	var old_scale:Vector2 = sprite.scale
	var old_position:Vector2 = sprite.position
	var fit:float = float(bounds.size.y)*absf(old_scale.y)/maxf(neutral.size.y,1.0)
	if role == "silverfish": fit = float(bounds.size.x)*absf(old_scale.x)/maxf(neutral.size.x,1.0)
	var foot:float = old_position.y + (float(bounds.end.y)-old.get_height()*0.5)*old_scale.y
	sprite.scale = Vector2.ONE*fit
	sprite.position = Vector2(old_position.x,foot-(neutral.end.y-112.0)*fit)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frames = FRAMES[role]
	var walk_cycle:float = float(frames.get_frame_count(&"walk"))/maxf(frames.get_animation_speed(&"walk"),0.001) if frames.has_animation(&"walk") else 1.0
	legs_key = role if MC_LEGS.layer_data(role) != null else ""
	gait = MC_LEGS.for_set(legs_key,walk_cycle) if not legs_key.is_empty() else MC_LEGS.create(walk_cycle)
	gait.observe(unit)
	MC_LEGS.prewarm(legs_key)
	if sprite is AnimatedSprite2D:
		(sprite as AnimatedSprite2D).sprite_frames = frames
		(sprite as AnimatedSprite2D).animation = &"idle"
		(sprite as AnimatedSprite2D).pause()
	if role == "witch":
		# Align the existing bottle tween to the rendered model's mouth. Keep the
		# same potion object, three drinking bobs, duration, effect and throw logic.
		var mouth:Vector2 = sprite.position+(WITCH_MOUTH-Vector2(80,112))*fit
		if is_equal_approx(float(unit.get("drink_mouth_offset_x")),18.0): unit.set("drink_mouth_offset_x",absf(mouth.x))
		if is_equal_approx(float(unit.get("drink_mouth_offset_y")),-48.0): unit.set("drink_mouth_offset_y",mouth.y)
	_last_position = unit.global_position
	ready_visual = true
	_set_clip(&"idle")
	_render_frame()
	unit.refresh_character_ground_shadow()

func trigger_shot(duration:float) -> void:
	_shoot_left = maxf(duration,0.05)
	if ready_visual:
		_set_clip(&"shoot")
		clip_time = 0.0
		_render_frame()

func _process(delta:float) -> void: advance(delta)

func advance(delta:float) -> void:
	if not ready_visual or not is_instance_valid(unit): return
	var traveled:float = unit.global_position.distance_to(_last_position)
	_last_position = unit.global_position
	if unit.health <= 0 or not unit.is_combat_runtime_active():
		gait.observe(unit)
		return
	var step:float = maxf(delta,0.0)
	_shoot_left = maxf(0.0,_shoot_left-step)
	_moving_left = maxf(0.0,_moving_left-step)
	if legs_key.is_empty():
		if traveled>0.025 and traveled<maxf(40.0,unit.Speed*step*5.0): _moving_left = 0.12
	else:
		gait.tick(unit,step,not bool(unit.get("dizziness")))
		_moving_left = 0.0 if gait.at_rest else 0.12
	var desired:String = _local_pose()
	if not unit.is_multiplayer_authority() and not _remote_pose.is_empty():
		desired = _remote_pose
		fuse_progress = _remote_fuse
	_set_clip(StringName(desired))
	clip_time += step
	_render_frame()
	# Keep blocks rigid. Existing hit flash, charged feedback, direction and
	# character-specific death transforms remain controlled by their old scripts.
	sprite.set_instance_shader_parameter("motion_params",Vector4.ZERO)
	sprite.set_instance_shader_parameter("bounce_params_a",Vector4(1,0,0,0))
	_network_wait -= step
	if unit.is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and (_network_wait<=0.0 or desired!=_last_sent_pose):
		_network_wait = 0.2
		_last_sent_pose = desired
		_receive_pose.rpc(desired,clip_time,fuse_progress,sprite.scale,sprite.position)

func _local_pose() -> String:
	var moving:bool = _moving_left>0.0
	match role:
		"witch":
			if bool(unit.get("_action_busy")): return "drink"
			if bool(unit.get("_brewing")) or bool(unit.get("_decision_pending")): return "hold"
			return "walk" if moving else "idle"
		"creeper":
			var base:String = "walk" if moving else "idle"
			if bool(unit.get("_fusing")):
				fuse_progress = clampf(float(unit.get("_fuse_elapsed"))/maxf(float(unit.get("_current_fuse_duration")),0.05),0.0,1.0)
				# With leg layers the fuse body is composited over independently walking legs.
				base = "fuse" if (not moving or MC_LEGS.has_upper(legs_key,&"fuse")) else "fuse_walk"
			else: fuse_progress = 0.0
			return base+("_charged" if bool(unit.get("_charged")) else "")
		"skeleton": return "shoot" if _shoot_left>0.0 else "walk" if moving else "idle"
		"silverfish": return "walk" if moving else "idle"
		"blaze": return "idle" # Vanilla has continuous rod orbit, not a separate attack skeleton clip.
	return "idle"

@rpc("any_peer","call_remote","unreliable_ordered")
func _receive_pose(pose:String,time:float,progress:float,visual_scale:Vector2,visual_position:Vector2) -> void:
	if not is_instance_valid(unit) or multiplayer.get_remote_sender_id()!=unit.get_multiplayer_authority(): return
	if not (FRAMES[role] as SpriteFrames).has_animation(StringName(pose)): return
	_remote_pose = pose
	_remote_fuse = clampf(progress,0.0,1.0)
	if not ready_visual: return
	_set_clip(StringName(pose))
	clip_time = maxf(time,0.0)
	# Spawn replication may already contain the authority's fitted transform;
	# correct it rather than fitting that transform a second time on clients.
	sprite.scale = visual_scale
	sprite.position = visual_position

func _set_clip(clip:StringName) -> void:
	if current_clip == clip or frames == null or not frames.has_animation(clip): return
	current_clip = clip
	clip_time = 0.0
	frame_index = -1

func _render_frame() -> void:
	if frames == null or current_clip==&"": return
	var count:int = frames.get_frame_count(current_clip)
	var next:int = int(floor(clip_time*frames.get_animation_speed(current_clip)))
	if str(current_clip).begins_with("fuse"): next = int(round(fuse_progress*float(count-1)))
	elif frames.get_animation_loop(current_clip): next %= count
	next = clampi(next,0,count-1)
	if not legs_key.is_empty() and str(current_clip).begins_with("walk"): next = gait.walk_index(count)
	# Upper-body action while the legs are still walking/settling: composite walking legs.
	var leg:int = -1
	if not legs_key.is_empty() and not gait.at_rest and MC_LEGS.has_upper(legs_key,current_clip):
		leg = gait.walk_index(int(MC_LEGS.layer_data(legs_key).WALK))
	if next==frame_index and leg==_leg_index: return
	frame_index = next
	_leg_index = leg
	if leg >= 0:
		var composed:Texture2D = MC_LEGS.compose(legs_key,current_clip,next,leg)
		if composed != null:
			if sprite is Sprite2D: (sprite as Sprite2D).texture = composed
			else:
				# AnimatedSprite2D cannot show an ad-hoc texture; swap to a Sprite2D-style override frame.
				var animated := sprite as AnimatedSprite2D
				animated.animation = current_clip
				animated.frame = next
				animated.pause()
			return
	if sprite is Sprite2D:
		(sprite as Sprite2D).texture = frames.get_frame_texture(current_clip,next)
	else:
		var animated := sprite as AnimatedSprite2D
		animated.animation = current_clip
		animated.frame = next
		animated.pause()
