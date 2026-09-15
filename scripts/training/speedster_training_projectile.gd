extends ball

signal training_hit(target:ball)
signal training_expired(projectile:ball)

@export var max_lifetime:float = 3.0

var _age:float = 0.0
var _reported:bool = false


func _ready() -> void:
	super._ready()
	if health_bar != null:
		health_bar.visible = false
	if status_image != null:
		status_image.visible = false


func _physics_process(delta:float) -> void:
	_age += maxf(delta,0.0)
	if _age >= max_lifetime:
		_report_expired()


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	var target:ball = _hurtbox_target_ball(hurt)
	var health_before:float = float(target.health) if target != null else 0.0
	super._on_hitbox_on_hit(hurt)
	if target != null and float(target.health) < health_before:
		if not _reported:
			_reported = true
			training_hit.emit(target)
		queue_free()


func when_collide(_speed:float,collision:KinematicCollision2D) -> void:
	# 与角色的实体接触伤害已经在 ball.move() 的 _process_physical_contact_hits()
	# 里先结算。若撞的是墙/场地，则视为这颗训练弹结束。
	if collision == null:
		return
	var collider:Variant = collision.get_collider()
	if collider is ball:
		return
	_report_expired()


func Die() -> void:
	# 训练弹不播放死亡音效。
	pass


func _report_expired() -> void:
	if _reported:
		return
	_reported = true
	training_expired.emit(self)
	queue_free()
