extends "res://scripts/effects/我的世界/唤魔尖牙.gd"
# Only the native jaw animation is reused; damage belongs to the zombie.
func _physics_process(delta:float) -> void:
	var caster:Variant = _caster.get_ref() if _caster != null else null
	if not is_instance_valid(caster) or caster.health <= 0:
		queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	_age += delta
	if _age > _delay+0.34: queue_free()
	queue_redraw()
