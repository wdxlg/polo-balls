extends Sprite2D
## 羊驼口水的原版 spit 烟雾粒子。Java LlamaSpit.recreateFromPacket 在口水生成时沿发射速度放出
## 7 个 ParticleTypes.SPIT（SpitParticle extends ExplodeParticle）：速度 = 口水速度 × (0.4 + 0.1·i)
## 加 ±0.05 格/tick 抖动，每 tick 摩擦 0.9，灰白色 (0.7..1.0)，quadSize 0.1·(r·r·6 + 1)，
## 寿命 16/(r·0.8 + 0.2) + 2 tick，贴图 generic_7 -> generic_0 按寿命播放（Bedrock
## particles/llama_spit.json 的 flipbook 也是 56 -> 0，同一套 poof 帧）。俯视战场不加重力。
const FRAMES = [
	preload("res://Images/effects/我的世界/通用粒子/generic_7.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_6.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_5.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_4.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_3.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_2.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_1.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_0.png"),
]
const BLOCK_PX:float = 16.0 # 口水模型按 1 格 ≈ 16 世界像素烘焙
const TICK:float = 1.0/20.0
const FRICTION_PER_TICK:float = 0.9
const COUNT:int = 7

var velocity:Vector2
var age:float = 0.0
var life:float = 1.0
var width_px:float = 4.0

## 口水出生时调用：每个端都自己生成（纯视觉，不同步）。
static func emit_for_shot(context:Node,point:Vector2,shot_velocity:Vector2,rng:RandomNumberGenerator = null) -> Array[Sprite2D]:
	var made:Array[Sprite2D] = []
	if not is_instance_valid(context) or not context.is_inside_tree(): return made
	var parent:Node = context.get_parent() if context.get_parent() != null else context.get_tree().current_scene
	if parent == null: return made
	var random:RandomNumberGenerator = rng
	if random == null:
		random = RandomNumberGenerator.new()
		random.randomize()
	var script:Script = load("res://scripts/characters/我的世界/wandering_trader/spit_smoke.gd")
	# 原版抖动 0.05 格/tick 对应口水 1.5 格/tick；按本项目口水速度同比例换算。
	var jitter:float = shot_velocity.length()*(0.05/1.5)
	for i:int in range(COUNT):
		var puff:Sprite2D = script.new()
		var motion:Vector2 = shot_velocity*(0.4 + 0.1*float(i)) + Vector2(random.randf_range(-1.0,1.0),random.randf_range(-1.0,1.0))*jitter
		var shade:float = random.randf()*0.3 + 0.7
		var quad:float = 0.1*(random.randf()*random.randf()*6.0 + 1.0)
		var ticks:float = floorf(16.0/(random.randf()*0.8 + 0.2)) + 2.0
		puff.call(&"setup",point,motion,Color(shade,shade,shade,1.0),quad*2.0*BLOCK_PX,ticks*TICK)
		parent.add_child(puff)
		puff.global_position = point
		made.append(puff)
	return made

func setup(point:Vector2,motion:Vector2,tint:Color,width:float,lifetime:float) -> void:
	name = "LlamaSpitSmoke"
	position = point
	velocity = motion
	self_modulate = tint
	width_px = maxf(width,0.5)
	life = maxf(lifetime,0.05)
	texture = FRAMES[0]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2.ONE*(width_px/float(texture.get_width()))
	z_index = 3
	add_to_group(&"BattleTransient")
	add_to_group(&"MCLlamaSpitSmoke")

func _process(delta:float) -> void:
	if delta <= 0.0 or get_tree().paused: return
	if Game.now_stop_state: return
	age += delta
	global_position += velocity*delta
	velocity *= pow(FRICTION_PER_TICK,delta/TICK)
	var t:float = clampf(age/life,0.0,1.0)
	texture = FRAMES[mini(int(t*FRAMES.size()),FRAMES.size() - 1)]
	scale = Vector2.ONE*(width_px/float(texture.get_width()))
	if age >= life: queue_free()
