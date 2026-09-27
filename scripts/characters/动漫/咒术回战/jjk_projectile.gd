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
var _trail:PackedVector2Array = []
var _parts:V.Parts = V.Parts.new()
var _add:Node2D
var _vt:float = 0.0
var _vrng:RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 86
	_vrng.seed = id * 31 + 7
	_add = V.make_add_layer(self,_draw_add)

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
	_trail.append(global_position)
	if _trail.size() > 14: _trail.remove_at(0)
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
	queue_redraw()
	_add.queue_redraw()

func _draw() -> void:
	draw_set_transform(-global_position,0.0,Vector2.ONE)
	_parts.draw_normal(self)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw_add() -> void:
	var ci:CanvasItem = _add
	var t:float = _vt
	var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
	# 拖尾（世界坐标 → 本地）
	var n:int = _trail.size()
	for i:int in range(1,n):
		var a:Vector2 = _trail[i - 1] - global_position
		var b:Vector2 = _trail[i] - global_position
		var u:float = float(i) / n
		match kind:
			"red","red_max": V.streak(ci,a,b,radius * 1.6 * u,Color(1.0,0.2,0.1,0.5 * u))
			"fuga":
				V.streak(ci,a,b,radius * 2.4 * u,Color(1.0,0.35,0.05,0.55 * u))
				V.streak(ci,a,b,radius * 1.0 * u,Color(1.0,0.8,0.3,0.7 * u))
	match kind:
		"red","red_max":
			var r:float = radius * (1.25 if kind == "red_max" else 1.0)
			var pulse:float = 1.0 + 0.1 * sin(t * 30.0)
			V.glow(ci,Vector2.ZERO,r * 3.2 * pulse,Color(1.0,0.12,0.05,0.8))
			V.flame_blob(ci,Vector2.ZERO,r * 1.05 * pulse,0.2,t * 2.0,Color(1.0,0.2,0.08,0.9),3.0)
			V.core(ci,Vector2.ZERO,r * 0.6,Color(1.0,0.9,0.85,1.0))
			for i2:int in 4:
				var a2:float = t * 12.0 + TAU * i2 / 4.0
				ci.draw_arc(Vector2.ZERO,r * 1.5,a2,a2 + 0.9,10,Color(1.0,0.5,0.4,0.8),2.0,true)
			V.shock(ci,Vector2.ZERO,r * (1.6 + fmod(t * 4.0,1.0) * 1.2),4.0,Color(1.0,0.4,0.3,0.6 * (1.0 - fmod(t * 4.0,1.0))))
		"fuga":
			var n2:Vector2 = dir.orthogonal()
			V.glow(ci,Vector2.ZERO,radius * 4.0,Color(1.0,0.4,0.05,0.7))
			V.flame_blob(ci,-dir * radius * 0.8,radius * 1.2,0.25,t * 2.5,Color(1.0,0.45,0.08,0.8),1.0)
			# 箭头
			var tip:PackedVector2Array = [dir * radius * 2.2,-dir * radius * 0.2 + n2 * radius * 0.8,-dir * radius * 0.6,-dir * radius * 0.2 - n2 * radius * 0.8]
			ci.draw_colored_polygon(tip,Color(1.0,0.9,0.55,1.0))
			V.core(ci,dir * radius * 0.6,radius * 0.7,Color(1,1,0.9,1))
	draw_parts_world(ci)

func draw_parts_world(ci:CanvasItem) -> void:
	ci.draw_set_transform(-global_position,0.0,Vector2.ONE)
	_parts.draw_add(ci)
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
