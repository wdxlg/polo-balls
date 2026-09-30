extends Node2D
## 咒术回战直线术式弹（赫 / 开）。各端同参数生成：只有 authority 实例做命中扫描，
## 命中后由施术者 RPC 统一结束所有端的实例。视觉在 _draw 中绘制。
const JJK = preload("res://scripts/characters/动漫/咒术回战/jjk_common.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const V = preload("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd")
var caster:ball
var id:int = 0
var kind:String = "red"
var velocity:Vector2 = Vector2.ZERO
var radius:float = 14.0
var life:float = 2.0
var authority:bool = false
var age:float = 0.0
var _ended:bool = false
# ---- 纯视觉
var _parts:V.Parts = V.Parts.new()
var _add:Node2D
var _vt:float = 0.0
var _vrng:RandomNumberGenerator = RandomNumberGenerator.new()
var _q_orb:Sprite2D
var _q_beam:Sprite2D

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 86
	_vrng.seed = id * 31 + 7
	# 普通混合的顶层（箭头等带墨线的实心图形画在面片之上）
	_add = Node2D.new()
	_add.name = "TopLayer"
	add_child(_add)
	_add.draw.connect(_draw_add)
	if DisplayServer.get_name() != "headless":
		# 先建球再建拖尾：两者都放到最底层，后建的在更下面 → 拖尾在球下、箭头(_add)在最上。
		_q_orb = V.quad(self,V.Q.ORB,1)
		_q_beam = V.quad(self,V.Q.BEAM,1)

func _physics_process(delta:float) -> void:
	if _ended or Game.now_stop_state: return
	if not is_instance_valid(caster):
		queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	age += delta
	var from:Vector2 = global_position
	var to:Vector2 = from + velocity * delta
	global_position = to
	queue_redraw()
	if not authority:
		if age > life + 0.5: queue_free()
		return
	var hits:Array[ball] = JJK.enemies_on_segment(caster,from,to,radius)
	if not hits.is_empty():
		var best:ball = hits[0]
		for h:ball in hits:
			if h.global_position.distance_squared_to(from) < best.global_position.distance_squared_to(from): best = h
		_finish(best,Geometry2D.get_closest_point_to_segment(best.global_position,from,to))
		return
	var wall:Dictionary = U.trace(caster,from,to)
	if not wall.is_empty() and wall.get("position") is Vector2:
		_finish(null,wall["position"])
		return
	if age >= life or not JJK.map_rect(caster).grow(60.0).has_point(to):
		_finish(null,to)

func _finish(target:ball,point:Vector2) -> void:
	if _ended: return
	_ended = true
	if is_instance_valid(caster) and caster.has_method("on_jjk_projectile_end"):
		caster.call("on_jjk_projectile_end",id,kind,target,point)
	queue_free()

func end_remote() -> void:
	_ended = true
	queue_free()

# ================================================================= 视觉
## 赫 = 带刺白芯红球 + 硬边红色拖尾 + 身后黑色速度线；開 = 火焰箭头（墨线描边）+ 赛璐璐火焰拖尾 + 余烬。
func _process(delta:float) -> void:
	if _ended or Game.now_stop_state: return
	_vt += delta
	var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
	if kind == "fuga" and _vrng.randf() < 0.6:
		var side:Vector2 = dir.orthogonal() * _vrng.randf_range(-radius,radius) * 0.6
		_parts.emit(global_position - dir * radius * 1.5 + side,-velocity * 0.12 + Vector2(0,-_vrng.randf_range(20,60)),0.45,_vrng.randf_range(1.5,2.8),Color(1.0,_vrng.randf_range(0.5,0.85),0.2),1,2.0,-60.0)
	_parts.step(delta)
	_update_quads(dir)
	queue_redraw()
	_add.queue_redraw()

func _update_quads(dir:Vector2) -> void:
	if _q_orb == null: return
	var spd:float = velocity.length()
	var step:float = floorf(_vt * 24.0) / 24.0
	var seedv:float = float(id % 97) * 0.71
	match kind:
		"red","red_max":
			var r:float = radius * (1.2 if kind == "red_max" else 0.95)
			var q:Array = V.orb_q("red",r * (1.0 + 0.06 * sin(step * 50.0)),1.0,0.12,0.4,9.0,10.0,0.0,0.7,2.5,Vector2(0.2,0.3))
			q[1]["time"] = _vt
			q[1]["seed"] = seedv
			V.qset(_q_orb,global_position,q[0],0.0,q[1])
			var L:float = minf(age * spd,r * 9.0)
			if L > r:
				var qb:Array = V.beam_q("red",L,r * 0.7,1.0,1.0,0.0,0.15,2.0,Vector2(0.25,0.35),10.0)
				qb[1]["time"] = _vt
				qb[1]["seed"] = seedv
				V.qset(_q_beam,global_position - dir * L * 0.5,qb[0],dir.angle(),qb[1])
			else: _q_beam.visible = false
		"fuga":
			var qf:Array = V.fire_q(radius * 2.0,0.85,1.0,1.0,4.0,2.4,0.08)
			qf[1]["time"] = _vt
			qf[1]["seed"] = seedv
			V.qset(_q_orb,global_position - dir * radius * 0.4,qf[0],0.0,qf[1])
			var L2:float = minf(age * spd,radius * 12.0)
			if L2 > radius:
				var qt:Array = V.beam_q("fire",L2,radius * 0.9,1.0,1.0,0.0,0.3,2.5,Vector2(0.3,0.35),12.0)
				qt[1]["time"] = _vt
				qt[1]["seed"] = seedv
				V.qset(_q_beam,global_position - dir * L2 * 0.5,qt[0],dir.angle(),qt[1])
			else: _q_beam.visible = false

func _draw() -> void:
	# 身后的黑色速度线（逐拍重掷）
	var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
	var n:Vector2 = dir.orthogonal()
	var lr:RandomNumberGenerator = RandomNumberGenerator.new()
	lr.seed = id * 7 + int(_vt * 24.0)
	var span:float = radius * (1.6 if kind == "fuga" else 1.3)
	for i:int in 5:
		var off:float = lr.randf_range(-span,span)
		var st:float = lr.randf_range(radius * 1.2,radius * 3.0)
		var ln:float = lr.randf_range(radius * 3.0,radius * 7.0)
		draw_line(n * off - dir * st,n * off - dir * (st + ln),Color(0,0,0,0.75),lr.randf_range(1.0,2.2),true)
	draw_set_transform(-global_position,0.0,Vector2.ONE)
	_parts.draw_normal(self)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw_add() -> void:
	var ci:CanvasItem = _add
	var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
	if kind == "fuga":
		# 火焰箭头（原作：宿傩拉弓射出的火矢）——黑描边 + 橙 + 黄白芯
		var n2:Vector2 = dir.orthogonal()
		var tip_o:PackedVector2Array = [dir * radius * 3.0,-dir * radius * 0.35 + n2 * radius * 1.15,dir * radius * 0.35,-dir * radius * 0.35 - n2 * radius * 1.15]
		var tip:PackedVector2Array = [dir * radius * 2.6,-dir * radius * 0.1 + n2 * radius * 0.9,dir * radius * 0.4,-dir * radius * 0.1 - n2 * radius * 0.9]
		var tip2:PackedVector2Array = [dir * radius * 2.1,n2 * radius * 0.45,dir * radius * 0.7,-n2 * radius * 0.45]
		ci.draw_colored_polygon(tip_o,Color(0.2,0.03,0.0,1.0))
		ci.draw_colored_polygon(tip,Color(1.0,0.6,0.15,1.0))
		ci.draw_colored_polygon(tip2,Color(1.0,0.97,0.8,1.0))
