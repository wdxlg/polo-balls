extends Node2D
## 附魔符文粒子（纯视觉，各端本地随机）：整场共用一个发射器节点，按原版粒子画法自绘。
## - 字形碎片（原版 enchant 粒子 particle/sga_*）：从符文身后飘出，减速、缩小、淡出。
## - 附魔星芒（原版 enchanted_hit 粒子，CritParticle 的魔法青色；原版靠发光叠加显亮，这里不叠加，
##   取浅一些的青色并去掉逐 tick 变暗，深色地图上也看得见）：尺寸在寿命前 1/32 长满，按 0.7/tick 阻尼。
## - 上浮字形（附魔台常驻）：从台子周围升起，向书的方向略收拢，左右正弦轻摆，淡入淡出。
## 回复符文的粒子染成绿色，便于和伤害符文区分。
const GLYPH_SCRIPT_PATH:String = "res://scripts/characters/我的世界/enchanting_table/enchanting_rune.gd"
const SPARK:Texture2D = preload("res://Images/characters/我的世界/enchanting_table/enchanted_hit.png")
const NODE_NAME:String = "MCEnchantRuneParticles"
const DRAW_Z:int = 93
const CAP:int = 1600
const KIND_GLYPH:int = 0
const KIND_SPARK:int = 1
const KIND_FLOAT:int = 2
const TICK:float = 0.05
const HEAL_TINT:Color = Color(0.55,1.0,0.55)

var particles:Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _glyphs:Array = []


static func find_or_create(context:Node) -> Node2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var scene:Node = context.get_tree().current_scene
	if scene == null: return null
	var existing:Node = scene.get_node_or_null(NODE_NAME)
	if existing != null and not existing.is_queued_for_deletion(): return existing as Node2D
	var fx:Node2D = (load("res://scripts/characters/我的世界/enchanting_table/rune_particles.gd") as Script).new()
	fx.name = NODE_NAME
	fx.z_as_relative = false
	fx.z_index = DRAW_Z
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.rng.randomize()
	fx.add_to_group(&"BattleTransient")
	scene.add_child(fx)
	fx.global_position = Vector2.ZERO
	return fx


func _ready() -> void:
	if _glyphs.is_empty(): _glyphs = (load(GLYPH_SCRIPT_PATH) as Script).get_script_constant_map().get("GLYPHS",[])


## 飞行拖尾：一个小字形碎片，偶尔带一颗附魔星芒。heading 为符文飞行方向。
func trail(pos:Vector2,heading:Vector2,shade:float,heal:bool,unit_scale:float = 1.0) -> void:
	var back:Vector2 = -heading.normalized() if heading.length_squared() > 0.0001 else Vector2.ZERO
	var side:Vector2 = back.orthogonal()*rng.randf_range(-9.0,9.0)
	var bright:float = maxf(shade,0.8)
	var color:Color = Color(bright*0.88,bright*0.82,bright)
	if heal: color *= HEAL_TINT
	_add({"kind":KIND_GLYPH,"glyph":rng.randi_range(0,25),"pos":pos + back*rng.randf_range(1.0,4.0)*unit_scale,
		"vel":(back*rng.randf_range(10.0,22.0) + side)*unit_scale + Vector2(0.0,-rng.randf_range(2.0,7.0))*unit_scale,
		"drag":0.12,"age":0.0,"life":rng.randf_range(0.45,0.8),"size":rng.randf_range(3.5,5.0)*unit_scale,"color":color})
	if rng.randf() < 0.45: spark(pos,back*rng.randf_range(6.0,16.0)*unit_scale + side*0.6*unit_scale,heal,unit_scale)


## 附魔台常驻上浮字形：start 处出现，向上飘过 toward（书）附近后淡出。
func float_glyph(start:Vector2,toward:Vector2,shade:float,unit_scale:float = 1.0) -> void:
	var life:float = rng.randf_range(1.3,2.1)
	var rise:float = rng.randf_range(11.0,19.0)*unit_scale
	var pull:float = (toward.x - start.x)*rng.randf_range(0.35,0.7)/life
	var bright:float = maxf(shade,0.85)
	_add({"kind":KIND_FLOAT,"glyph":rng.randi_range(0,25),"pos":start,"vel":Vector2(pull,-rise),"drag":0.8,"age":0.0,"life":life,
		"size":rng.randf_range(4.5,6.5)*unit_scale,"color":Color(bright*0.88,bright*0.82,bright),
		"sway":rng.randf_range(0.8,2.0)*unit_scale,"phase":rng.randf()*TAU,"freq":rng.randf_range(2.0,3.5)})


## 原版附魔星芒。
func spark(pos:Vector2,vel:Vector2,heal:bool,unit_scale:float = 1.0) -> void:
	var gray:float = rng.randf()*0.2 + 0.8
	var color:Color = Color(gray*0.55,gray*0.92,gray) if not heal else Color(gray*0.5,gray,gray*0.5)
	_add({"kind":KIND_SPARK,"pos":pos,"vel":vel,"drag":pow(0.7,1.0/TICK),"age":0.0,
		"life":TICK*6.0/(rng.randf()*0.8 + 0.6),"size":rng.randf_range(3.0,5.0)*unit_scale,"color":color,"heal":heal})


## 符文送达：一圈星芒 + 几片字形向外散开。
func burst(pos:Vector2,heal:bool,shade:float,unit_scale:float = 1.0) -> void:
	for i:int in range(12):
		var dir:Vector2 = Vector2.RIGHT.rotated(rng.randf()*TAU)
		spark(pos + dir*rng.randf_range(0.0,3.0)*unit_scale,dir*rng.randf_range(40.0,90.0)*unit_scale,heal,unit_scale)
	for i:int in range(5):
		trail(pos,Vector2.RIGHT.rotated(rng.randf()*TAU),shade,heal,unit_scale)


func count(kind:int) -> int:
	var n:int = 0
	for p:Dictionary in particles:
		if int(p.kind) == kind: n += 1
	return n


func _add(p:Dictionary) -> void:
	if particles.size() >= CAP: particles.pop_front()
	particles.append(p)


func _process(delta:float) -> void:
	var game:Node = get_node_or_null("/root/Game")
	if get_tree().paused or (game != null and bool(game.get("now_stop_state"))): return
	for i:int in range(particles.size() - 1,-1,-1):
		var p:Dictionary = particles[i]
		p.age = float(p.age) + delta
		if float(p.age) >= float(p.life):
			particles.remove_at(i)
			continue
		p.pos = (p.pos as Vector2) + (p.vel as Vector2)*delta
		p.vel = (p.vel as Vector2)*pow(float(p.drag),delta)
	queue_redraw()


func _draw() -> void:
	for p:Dictionary in particles:
		var k:float = clampf(float(p.age)/float(p.life),0.0,1.0)
		var color:Color = p.color
		var s:float = float(p.size)
		var tex:Texture2D
		var draw_pos:Vector2 = p.pos
		if int(p.kind) == KIND_GLYPH:
			if _glyphs.is_empty(): continue
			tex = _glyphs[posmod(int(p.glyph),_glyphs.size())]
			s *= 1.0 - k*0.55
			color.a = 1.0 - smoothstep(0.35,1.0,k)
		elif int(p.kind) == KIND_FLOAT:
			if _glyphs.is_empty(): continue
			tex = _glyphs[posmod(int(p.glyph),_glyphs.size())]
			draw_pos.x += sin(float(p.age)*float(p.freq) + float(p.phase))*float(p.sway)
			s *= 1.0 - k*0.35
			color.a = smoothstep(0.0,0.15,k)*(1.0 - smoothstep(0.6,1.0,k))
		else:
			tex = SPARK
			s *= clampf(k*32.0,0.0,1.0)
			color.a = 1.0 - smoothstep(0.7,1.0,k)
		if s <= 0.05: continue
		draw_texture_rect(tex,Rect2(draw_pos - Vector2(s,s)*0.5,Vector2(s,s)),false,color)
