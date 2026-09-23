extends Node2D
const POTION_PARTICLE = preload("res://scripts/effects/我的世界/女巫药水粒子.gd")
const TICK_DAMAGE_RATIO:float = 0.02
const PARTICLE_INTERVAL:float = 0.14
const PARTICLE_COLOR:Color = Color(0.12,0.12,0.12,0.98)
## One status per target; refresh rather than stacking damage or tint.
var source_ref:WeakRef
var remaining:float = 0.0
var tick_left:float = 1.0
var saved_color:Color = Color.WHITE
var painted:bool = false
var _particle_left:float = PARTICLE_INTERVAL
func refresh(source:ball) -> void:
	source_ref = weakref(source)
	remaining = 3.0
	if not painted and get_parent() is ball:
		var target:ball = get_parent() as ball
		if target.image is CanvasItem:
			saved_color = target.image.modulate
			target.image.modulate = Color(0.24,0.21,0.28,1.0)
			painted = true
	_particle_left = PARTICLE_INTERVAL
	_spawn_particle()
func _physics_process(delta:float) -> void:
	var target:ball = get_parent() as ball
	var source:Variant = source_ref.get_ref() if source_ref != null else null
	if target == null or target.health <= 0 or not is_instance_valid(source) or source.health <= 0: queue_free(); return
	if not source.is_combat_runtime_active(): return
	# Count only the part of this physics frame inside the three-second effect.
	# A tick at t=3 is valid; a long frame cannot add extra damage after expiry.
	var active_step:float = minf(maxf(delta,0.0),maxf(remaining,0.0))
	remaining -= delta
	if source.is_multiplayer_authority():
		tick_left -= active_step
		while tick_left <= 0.000001 and target.health > 0:
			tick_left += 1.0
			source.impact(target,maxf(target.Max_health,0.0)*TICK_DAMAGE_RATIO,target.global_position)
	if remaining <= 0: queue_free()
func _process(delta:float) -> void:
	if remaining <= 0: return
	var target:ball = get_parent() as ball
	if target == null or target.health <= 0: return
	var source:Variant = source_ref.get_ref() if source_ref != null else null
	if not is_instance_valid(source) or source.health <= 0 or not source.is_combat_runtime_active(): return
	_particle_left -= delta
	while _particle_left <= 0:
		_particle_left += PARTICLE_INTERVAL
		_spawn_particle()
func _spawn_particle() -> void:
	var target:ball = get_parent() as ball
	if target == null or target.health <= 0 or target.get_tree() == null: return
	var world:Node = target.get_tree().current_scene
	if world == null: return
	# Share the Witch's real eight-frame potion particle, not an effect icon.
	# Spawn in world space so particles drift upward after the enemy moves.
	var particle:Sprite2D = POTION_PARTICLE.new()
	world.add_child(particle)
	particle.name = "WitherPotionParticle"
	particle.add_to_group("WitherPotionParticle")
	particle.setup(
		target.global_position+Vector2(randf_range(-13.0,13.0),randf_range(-18.0,8.0)),
		PARTICLE_COLOR,
		Vector2(randf_range(-7.0,7.0),randf_range(-48.0,-34.0)),
		randf_range(0.042,0.052),
		randf_range(0.060,0.072),
		82
	)
func _exit_tree() -> void:
	var target:ball = get_parent() as ball
	if painted and is_instance_valid(target) and target.image is CanvasItem and target.image.modulate.is_equal_approx(Color(0.24,0.21,0.28,1.0)):
		target.image.modulate = saved_color
