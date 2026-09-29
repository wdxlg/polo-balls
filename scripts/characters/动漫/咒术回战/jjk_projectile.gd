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
	_add = V.make_add_layer(self,_draw_add)
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
func _process(delta:float) -> void:
	if _ended or Game.now_stop_state: return
	_vt += delta
	var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
	match kind:
		"red","red_max":
			for i:int in 2:
				var a:float = _vrng.randf() * TAU
				_parts.emit(global_position + Vector2.from_angle(a) * radius,Vector2.from_angle(a) * _vrng.randf_range(60,160) - velocity * 0.1,0.3,2.0,Color(1.0,0.4,0.3),2,4.0)
		"fuga":
			for i2:int in 3:
				var side:Vector2 = dir.orthogonal() * _vrng.randf_range(-radius,radius) * 0.6
				_parts.emit(global_position - dir * radius * 1.5 + side,-velocity * 0.15 + Vector2(0,-_vrng.randf_range(20,60)),0.5,radius * _vrng.randf_range(0.35,0.6),Color(1.0,_vrng.randf_range(0.35,0.7),0.1,0.85),0,2.0,-60.0)
			if _vrng.randf() < 0.3: _parts.emit(global_position - dir * radius * 2.0,-velocity * 0.05 + Vector2(0,-30),0.8,radius * 0.6,Color(0.12,0.08,0.06,0.4),1,1.0,-20.0)
	_parts.step(delta)
	_update_quads(dir)
	queue_redraw()
	_add.queue_redraw()

## 着色器面片：赫 = 旋转的红色能量球 + 红色拖尾；开 = 火焰拖尾 + 火球头。
func _update_quads(dir:Vector2) -> void:
	if _q_orb == null: return
	var spd:float = velocity.length()
	var seedv:float = float(id % 97) * 0.71
	match kind:
		"red","red_max":
			var r:float = radius * (1.25 if kind == "red_max" else 1.0)
			var pulse:float = 1.0 + 0.06 * sin(_vt * 30.0)
			V.qset(_q_orb,global_position,Vector2.ONE * r * 5.0 * pulse,0.0,V.pal("red",{"time":_vt,"seed":seedv,"alpha":1.3,"p0":Vector4(0.36,1.6,0.6,1.0),"p1":Vector4(7.0,0.2,1.0,0.9),"p2":Vector4(0.0,2.6,0,0)}))
			var L:float = minf(age * spd,r * 9.0)
			if L > r:
				V.qset(_q_beam,global_position - dir * L * 0.5,Vector2(L,r * 2.4),dir.angle(),V.pal("red",{"time":_vt,"seed":seedv,"alpha":1.0,"p0":Vector4(0.34,14.0,0.45,1.0),"p1":Vector4(0.0,0.95,0.7,0.3),"p2":Vector4(0.0,0.0,0,0)}))
			else: _q_beam.visible = false
		"fuga":
			V.qset(_q_orb,global_position - dir * radius * 0.3,Vector2.ONE * radius * 4.6,0.0,V.pal("fire",{"time":_vt,"seed":seedv,"alpha":1.25,"p0":Vector4(0.4,0.8,0.9,1.0),"p1":Vector4(3.0,0.3,0.9,0.9),"p2":Vector4(0.0,2.4,0,0)}))
			var L2:float = minf(age * spd,radius * 13.0)
			if L2 > radius:
				V.qset(_q_beam,global_position - dir * L2 * 0.5,Vector2(L2,radius * 3.2),dir.angle(),V.pal("fire",{"time":_vt,"seed":seedv,"alpha":1.1,"p0":Vector4(0.32,12.0,0.6,1.0),"p1":Vector4(0.0,0.95,0.8,0.6),"p2":Vector4(0.0,0.0,0,0)}))
			else: _q_beam.visible = false

func _draw() -> void:
	draw_set_transform(-global_position,0.0,Vector2.ONE)
	_parts.draw_normal(self)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw_add() -> void:
	var ci:CanvasItem = _add
	var t:float = _vt
	var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
	match kind:
		"red","red_max":
			var r:float = radius * (1.25 if kind == "red_max" else 1.0)
			V.glow(ci,Vector2.ZERO,r * 3.4,Color(1.0,0.12,0.05,0.45))
			V.sprite(ci,"k_flare01",Vector2.ZERO,r * 8.0,Color(1.0,0.3,0.2,0.5),dir.angle(),Vector2(1.0,0.25))
			var ph:float = fmod(t * 4.0,1.0)
			V.shock(ci,Vector2.ZERO,r * (1.8 + ph * 1.2),3.0,Color(1.0,0.4,0.3,0.5 * (1.0 - ph)))
		"fuga":
			var n2:Vector2 = dir.orthogonal()
			V.glow(ci,Vector2.ZERO,radius * 4.0,Color(1.0,0.4,0.05,0.45))
			# 火焰箭头（原作：宿傩拉弓射出的火矢）
			var tip:PackedVector2Array = [dir * radius * 2.6,-dir * radius * 0.1 + n2 * radius * 0.9,dir * radius * 0.4,-dir * radius * 0.1 - n2 * radius * 0.9]
			ci.draw_colored_polygon(tip,Color(1.0,0.85,0.45,1.0))
			var tip2:PackedVector2Array = [dir * radius * 2.1,n2 * radius * 0.45,dir * radius * 0.7,-n2 * radius * 0.45]
			ci.draw_colored_polygon(tip2,Color(1.0,1.0,0.9,1.0))
	draw_parts_world(ci)

func draw_parts_world(ci:CanvasItem) -> void:
	ci.draw_set_transform(-global_position,0.0,Vector2.ONE)
	_parts.draw_add(ci)
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
