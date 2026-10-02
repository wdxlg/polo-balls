extends Node2D
var _caster:WeakRef
var _age:float = 0.0
var _delay:float = 0.14
const INK:Color = Color("17251f")
const GUM:Color = Color("4f6b45")
const IVORY:Color = Color("f4efd6")
const SHADE:Color = Color("b3baa0")

func setup(caster:Node2D,delay:float) -> void:
	_caster = weakref(caster)
	_delay = maxf(delay,0.01)
	z_index = 9
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("BattleTransient")
	add_to_group("MCZombieBite")
func jaw_gap() -> float:
	var closing:float = clampf((_age/_delay-0.45)/0.55,0.0,1.0)
	return snappedf(8.0*(1.0-closing*closing),1.0)
func _physics_process(delta:float) -> void:
	var caster:Variant = _caster.get_ref() if _caster != null else null
	if not is_instance_valid(caster) or caster.health <= 0:
		queue_free()
		return
	if get_tree().paused or not caster.is_combat_runtime_active(): return
	_age += delta
	if _age > _delay+0.18: queue_free()
	queue_redraw()
func _draw() -> void:
	modulate.a = 1.0-clampf((_age-_delay-0.06)/0.12,0.0,1.0)
	var gap:float = jaw_gap()
	for side:float in [1.0,-1.0]:
		draw_set_transform(Vector2(0.0,-gap*side),0.0,Vector2(1.0,side))
		draw_rect(Rect2(-11,-8,22,5),INK)
		draw_rect(Rect2(-10,-7,20,3),GUM)
		for i:int in range(5):
			var x:float = -9.0+float(i)*4.0
			draw_rect(Rect2(x-1,-5,5,6),INK)
			draw_rect(Rect2(x,-5,3,4),IVORY)
			draw_rect(Rect2(x,-5,1,4),SHADE)
			draw_rect(Rect2(x+1,-1,1,1),IVORY)
	draw_set_transform(Vector2.ZERO)
