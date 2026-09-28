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

var unit:Node2D
var frame_set_name:StringName
var frames:SpriteFrames
var sprite:Sprite2D
var clip:StringName = &""
var clip_time:float = 0.0
var frame_index:int = -1
var observed_speed:float = 0.0
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
	var wanted:StringName = &"walk" if observed_speed > 6.0 else &"idle"
	if unit.has_method(&"wt_visual_clip"): wanted = StringName(unit.call(&"wt_visual_clip",observed_speed))
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
	_apply(clip,index)

func _apply(clip_name:StringName,index:int) -> void:
	if sprite == null or not frames.has_animation(clip_name): return
	if clip_name == clip and index == frame_index and sprite.texture != null: return
	frame_index = index
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
