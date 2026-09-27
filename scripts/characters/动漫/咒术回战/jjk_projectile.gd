extends Node2D
## 咒术回战直线术式弹（赫 / 开）。各端同参数生成：只有 authority 实例做命中扫描，
## 命中后由施术者 RPC 统一结束所有端的实例。视觉在 _draw 中绘制。
const JJK = preload("res://scripts/characters/动漫/咒术回战/jjk_common.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
var caster:ball
var id:int = 0
var kind:String = "red"
var velocity:Vector2 = Vector2.ZERO
var radius:float = 14.0
var life:float = 2.0
var authority:bool = false
var age:float = 0.0
var _ended:bool = false

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 86

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

func _draw() -> void:
	var t:float = age
	match kind:
		"red","red_max":
			var r:float = radius * (1.25 if kind == "red_max" else 1.0)
			draw_circle(Vector2.ZERO,r * 1.8,Color(1.0,0.1,0.05,0.18))
			draw_circle(Vector2.ZERO,r,Color(1.0,0.15,0.1,0.9))
			draw_circle(Vector2.ZERO,r * 0.45,Color(1.0,0.85,0.8,1.0))
			for i:int in 4:
				var a:float = t * 9.0 + TAU * i / 4.0
				draw_arc(Vector2.ZERO,r * 1.4,a,a + 0.9,8,Color(1.0,0.4,0.3,0.8),2.0,true)
		"fuga":
			var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
			var tail:Vector2 = -dir * radius * 4.0
			draw_line(tail,Vector2.ZERO,Color(1.0,0.4,0.05,0.7),radius * 1.2,true)
			draw_line(tail * 0.6,Vector2.ZERO,Color(1.0,0.85,0.3,0.9),radius * 0.6,true)
			var tip:PackedVector2Array = [dir * radius * 1.6,dir.orthogonal() * radius * 0.7,-dir.orthogonal() * radius * 0.7]
			draw_colored_polygon(tip,Color(1.0,0.95,0.6))
			for i2:int in 5:
				var jitter:Vector2 = Vector2.from_angle(t * 20.0 + i2) * radius * 0.5
				draw_circle(tail * (0.2 * i2) + jitter,radius * 0.35,Color(1.0,0.55,0.1,0.6))
