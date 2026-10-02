extends Node
## Baked Bedrock frames (scripts/training/mc_native_assets/bake_wandering_trader.py) for the
## 流浪商人 and his trader llamas. Pure visual: every peer derives the clip from the unit's
## semantic state (wt_visual_clip) and its own observed motion, so nothing extra is synced.
## Same canvas for every frame of a set, so the scene's Image scale/offset never changes.
const FRAMES:Dictionary = {
	&"trader":preload("res://Images/characters/我的世界/流浪商人/frames/trader.tres"),
	&"llama_creamy":preload("res://Images/characters/我的世界/流浪商人/frames/llama_creamy.tres"),
	&"llama_brown":preload("res://Images/characters/我的世界/流浪商人/frames/llama_brown.tres"),
}
const MILK_TEXTURE = preload("res://Images/characters/我的世界/流浪商人/items/milk_bucket.png")
const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")
const WALK_SPEED_REFERENCE:float = 46.0 # world px/s that plays the walk clip at 1x
const MC_LEGS = preload("res://scripts/effects/我的世界/mc_legs.gd")

var unit:Node2D
var frame_set_name:StringName
var frames:SpriteFrames
var sprite:Sprite2D
var clip:StringName = &""
var clip_time:float = 0.0
var frame_index:int = -1
var observed_speed:float = 0.0
## 独立腿部步态（mc_legs.gd）：走/跑帧由真实位移 / 自身标准移速推进；喝药、吐口水时腿照常迈，停下回到站姿。
var gait:RefCounted
var _leg_index:int = -1
var _last_position:Vector2
var _has_last:bool = false
var _frozen:bool = false

static func attach(target:Node2D,frame_set:StringName) -> Node:
	if not FRAMES.has(frame_set) or not is_instance_valid(target): return null
	var driver:Node = load("res://scripts/characters/我的世界/wandering_trader/visual.gd").new()
	driver.name = "WanderingTraderVisual"
	driver.unit = target
	driver.frame_set_name = frame_set
	driver.frames = FRAMES[frame_set]
	target.add_child(driver)
	return driver

func _ready() -> void:
	sprite = unit.get("image") as Sprite2D if is_instance_valid(unit) else null
	if sprite != null:
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_apply(&"idle",0)

func current_texture() -> Texture2D:
	return sprite.texture if sprite != null else null

func freeze() -> void:
	_frozen = true

func _process(delta:float) -> void:
	if _frozen or sprite == null or not is_instance_valid(unit) or delta <= 0.0: return
	if float(unit.get("health")) <= 0.0:
		_frozen = true # MC death pose keeps the last frame.
		return
	var now:Vector2 = unit.global_position
	if _has_last:
		var instant:float = now.distance_to(_last_position)/delta
		observed_speed = lerpf(observed_speed,instant,clampf(delta*12.0,0.0,1.0))
	_last_position = now
	_has_last = true
	var legs:RefCounted = _gait()
	legs.tick(unit,delta,unit.get("dizziness") != true)
	var wanted:StringName = &"walk" if observed_speed > 6.0 else &"idle"
	var forced_walk:bool = false
	if unit.has_method(&"wt_visual_clip"):
		wanted = StringName(unit.call(&"wt_visual_clip",observed_speed))
		# Wall entry / emerging request walk even without displacement: keep their old timing.
		forced_walk = StringName(unit.call(&"wt_visual_clip",0.0)) == &"walk"
	if not forced_walk and wanted in [&"walk",&"idle"]:
		wanted = &"walk" if not legs.at_rest else &"idle" # real displacement, settle to the rest pose
	if not frames.has_animation(wanted): wanted = &"idle"
	if wanted != clip:
		clip = wanted
		clip_time = 0.0
	var rate:float = 1.0
	if clip in [&"walk",&"run"]: rate = clampf(observed_speed/WALK_SPEED_REFERENCE,0.55,2.4)
	clip_time += delta*rate
	var count:int = frames.get_frame_count(clip)
	var index:int = int(floor(clip_time*frames.get_animation_speed(clip)))
	index = posmod(index,count) if frames.get_animation_loop(clip) else mini(index,count-1)
	if not forced_walk:
		if clip == &"walk": index = legs.walk_index(count)
		# The baked run clip spans half a leg cycle (diagonal pairs swap): 2 run loops per stride.
		elif clip == &"run": index = legs.walk_index(count*2) % count
	var leg:int = -1
	var key:String = str(frame_set_name)
	if not legs.at_rest and MC_LEGS.has_upper(key,clip): leg = legs.walk_index(int(MC_LEGS.layer_data(key).WALK))
	if leg >= 0:
		if _composite_drawn and clip == _last_clip_drawn and index == frame_index and leg == _leg_index: return
		var running:bool = observed_speed > 110.0 and (MC_LEGS.layer_data(key).LEGS as Array).size() > 1
		var composed:Texture2D = MC_LEGS.compose(key,clip,index,leg,1 if running else 0)
		if composed != null:
			frame_index = index
			_leg_index = leg
			_last_clip_drawn = clip
			_composite_drawn = true
			sprite.texture = composed
			return
	_leg_index = -1
	_apply(clip,index)

var _last_clip_drawn:StringName = &""
var _composite_drawn:bool = false

func _gait() -> RefCounted:
	if gait == null:
		var cycle:float = float(frames.get_frame_count(&"walk"))/maxf(frames.get_animation_speed(&"walk"),0.001) if frames.has_animation(&"walk") else 1.0
		var key:String = str(frame_set_name)
		gait = MC_LEGS.for_set(key,cycle) if MC_LEGS.layer_data(key) != null else MC_LEGS.create(cycle)
		gait.observe(unit)
		MC_LEGS.prewarm(key)
	return gait

func _apply(clip_name:StringName,index:int) -> void:
	if sprite == null or not frames.has_animation(clip_name): return
	if clip_name == clip and clip_name == _last_clip_drawn and index == frame_index and sprite.texture != null and not _composite_drawn: return
	frame_index = index
	_last_clip_drawn = clip_name
	_composite_drawn = false
	sprite.texture = frames.get_frame_texture(clip_name,clampi(index,0,frames.get_frame_count(clip_name)-1))

# ------------------------------------------------------------------ held item
static func item_texture(kind:StringName) -> Texture2D:
	if kind == &"milk": return MILK_TEXTURE
	return POTION_EFFECTS.texture_for("invisibility")

# ------------------------------------------------------------------ particles
## Square vanilla-like block chips (stone for wall entry/exit, white-cyan for spit, white for milk).
static func burst(context:Node,point:Vector2,color:Color,amount:int = 14,spread:float = 60.0,size:float = 1.4,lifetime:float = 0.55,up:Vector2 = Vector2.UP) -> CPUParticles2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree:SceneTree = context.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var particles := CPUParticles2D.new()
	particles.name = "WTBurst"
	particles.one_shot = true
	particles.emitting = false
	particles.amount = maxi(amount,1)
	particles.lifetime = lifetime
	particles.explosiveness = 0.92
	particles.direction = up
	particles.spread = 180.0
	particles.initial_velocity_min = spread*0.35
	particles.initial_velocity_max = spread
	particles.gravity = Vector2(0.0,140.0)
	particles.scale_amount_min = size*0.7
	particles.scale_amount_max = size*1.25
	particles.color = color
	var ramp := Gradient.new()
	ramp.set_color(0,Color(1,1,1,1))
	ramp.set_color(1,Color(1,1,1,0))
	particles.color_ramp = ramp
	particles.z_index = 30
	particles.add_to_group(&"MCWanderingTraderFx")
	parent.add_child(particles)
	particles.global_position = point
	particles.emitting = true
	tree.create_timer(lifetime + 0.4,false).timeout.connect(particles.queue_free)
	return particles
