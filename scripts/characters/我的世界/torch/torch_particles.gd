extends Node2D
## 火把粒子（纯视觉，各端本地随机）：整场共用一个发射器节点，按原版粒子画法自绘。
## - 火苗（原版 flame / soul_fire_flame 粒子）：几乎不动，略微上飘，寿命内按 1 - k²·0.5 缩小。
## - 烟（原版 smoke 粒子）：generic_7 -> generic_0 按寿命播放，起始很快长到全尺寸，向上加速飘散。
##   原版是深灰，但战场地图多为深色，取中灰才看得见。
## - 拖尾火苗：带初速度并减速，用于冲刺火焰拖尾与飞行中的火星。
const FLAME:Texture2D = preload("res://Images/characters/我的世界/torch/flame.png")
const SOUL_FLAME:Texture2D = preload("res://Images/characters/我的世界/torch/soul_fire_flame.png")
const SMOKE_FRAMES = [
	preload("res://Images/effects/我的世界/通用粒子/generic_7.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_6.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_5.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_4.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_3.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_2.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_1.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_0.png"),
]
const NODE_NAME:String = "MCTorchParticles"
const DRAW_Z:int = 93 # 火场(92)之上、地图黑边(100)之下，贴墙时烟不被地图外遮罩挡住
const CAP:int = 1500
const KIND_FLAME:int = 0
const KIND_SMOKE:int = 1

var particles:Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


static func find_or_create(context:Node) -> Node2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var scene:Node = context.get_tree().current_scene
	if scene == null: return null
	var existing:Node = scene.get_node_or_null(NODE_NAME)
	if existing != null and not existing.is_queued_for_deletion(): return existing as Node2D
	var fx:Node2D = (load("res://scripts/characters/我的世界/torch/torch_particles.gd") as Script).new()
	fx.name = NODE_NAME
	fx.z_as_relative = false
	fx.z_index = DRAW_Z
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.rng.randomize()
	fx.add_to_group(&"BattleTransient")
	scene.add_child(fx)
	fx.global_position = Vector2.ZERO
	return fx


## 原版火苗：pos 处出现，几乎原地，轻轻上飘后缩小消失。
func flame(pos:Vector2,soul:bool,size:float = 3.2) -> void:
	_add({"kind":KIND_FLAME,"soul":soul,"pos":pos,"vel":Vector2(rng.randf_range(-1.2,1.2),-rng.randf_range(2.0,5.0)),
		"drag":1.0,"rise":0.0,"age":0.0,"life":rng.randf_range(0.5,1.0),"size":size * rng.randf_range(0.88,1.12)})


## 带初速度的火苗（冲刺拖尾、火星飞行）：速度按 drag 每秒衰减。
func moving_flame(pos:Vector2,soul:bool,vel:Vector2,life:float,size:float) -> void:
	_add({"kind":KIND_FLAME,"soul":soul,"pos":pos,"vel":vel,"drag":0.08,"rise":3.0,"age":0.0,
		"life":life * rng.randf_range(0.85,1.15),"size":size * rng.randf_range(0.88,1.12)})


## 原版烟：large 为火方块冒的大烟。shade 0 黑 .. 1 白。
func smoke(pos:Vector2,large:bool = false,shade:float = -1.0) -> void:
	var s:float = rng.randf_range(6.5,9.5) if large else rng.randf_range(4.2,6.0)
	_add({"kind":KIND_SMOKE,"pos":pos,"vel":Vector2(rng.randf_range(-2.5,2.5),-rng.randf_range(6.0,11.0) * (1.4 if large else 1.0)),
		"drag":0.45,"rise":rng.randf_range(8.0,14.0),"age":0.0,"life":rng.randf_range(1.0,1.7) * (1.15 if large else 1.0),
		"size":s,"rot":rng.randf_range(-PI,PI),"shade":shade if shade >= 0.0 else rng.randf_range(0.42,0.6)})


func count(kind:int) -> int:
	var n:int = 0
	for p:Dictionary in particles:
		if int(p.kind) == kind: n += 1
	return n


func _add(p:Dictionary) -> void:
	if particles.size() >= CAP: particles.pop_front()
	particles.append(p)


func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	for i:int in range(particles.size() - 1,-1,-1):
		var p:Dictionary = particles[i]
		p.age = float(p.age) + delta
		if float(p.age) >= float(p.life):
			particles.remove_at(i)
			continue
		p.pos = (p.pos as Vector2) + (p.vel as Vector2) * delta
		p.vel = (p.vel as Vector2) * pow(float(p.drag),delta) + Vector2(0.0,-float(p.rise) * delta)
	queue_redraw()


func _draw() -> void:
	for p:Dictionary in particles:
		var k:float = clampf(float(p.age) / float(p.life),0.0,1.0)
		if int(p.kind) == KIND_FLAME:
			var s:float = float(p.size) * (1.0 - k * k * 0.5)
			var tex:Texture2D = SOUL_FLAME if bool(p.soul) else FLAME
			draw_texture_rect(tex,Rect2((p.pos as Vector2) - Vector2(s,s) * 0.5,Vector2(s,s)),false,Color(1,1,1,1.0 - smoothstep(0.75,1.0,k)))
		else:
			var tex:Texture2D = SMOKE_FRAMES[mini(int(k * SMOKE_FRAMES.size()),SMOKE_FRAMES.size() - 1)]
			var s:float = float(p.size) * clampf(k * 12.0,0.35,1.0)
			var shade:float = float(p.shade)
			draw_set_transform(p.pos,float(p.rot),Vector2.ONE)
			draw_texture_rect(tex,Rect2(-s * 0.5,-s * 0.5,s,s),false,Color(shade,shade,shade,0.9 * (1.0 - smoothstep(0.7,1.0,k))))
			draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
