extends Node2D
## One Wither effect per victim, regardless of Witch potion / skull / rose.
const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const POTION_PARTICLE = preload("res://scripts/effects/我的世界/女巫药水粒子.gd")
const DAMAGE_SFX = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
const PARTICLE_INTERVAL:float = 0.14
const PARTICLE_COLOR:Color = Color(0.12,0.12,0.12,0.98)
const WITHER_TINT:Color = Color(0.24,0.21,0.28,1.0)
var effect_type:String = "wither"
var target:ball
var source:Node
var source_ref:WeakRef
var level:int = 1
var remaining:float = 0.0
var applications:Dictionary = {}
var tick_left:float = 2.0
var saved_color:Color = Color.WHITE
var painted:bool = false
var _particle_left:float = PARTICLE_INTERVAL

func setup(new_target:ball,_kind:String,duration:float,new_source:Node = null,_options:Dictionary = {},new_level:int = 1) -> void:
	target = new_target
	level = maxi(new_level,1)
	EFFECTS.remember_source(applications,new_source,level,duration)
	_choose_application()
	remaining = duration
	tick_left = float(EFFECTS.properties(effect_type,level).period_ticks)/20.0
	if target.image is CanvasItem:
		saved_color = target.image.modulate
		target.image.modulate = WITHER_TINT
		painted = true
	_particle_left = PARTICLE_INTERVAL
	_spawn_particle()

func refresh(duration:float,new_source:Node = null,_options:Dictionary = {},new_level:int = 1) -> void:
	EFFECTS.remember_source(applications,new_source,new_level,duration)
	_choose_application()
	_particle_left = PARTICLE_INTERVAL
	_spawn_particle()

func remove_source(caster:Node) -> void:
	EFFECTS.forget_source(applications,caster)
	_choose_application()

func _choose_application() -> void:
	var best:Dictionary = EFFECTS.strongest_source(applications)
	if best.is_empty():
		remaining = 0.0
		queue_free()
		return
	var previous:int = level
	level = int(best.grade)
	remaining = float(best.time)
	source_ref = best.source_ref as WeakRef
	var caster:Variant = source_ref.get_ref() if source_ref != null else null
	source = caster as Node if is_instance_valid(caster) and caster is Node else null
	if level != previous: tick_left = float(EFFECTS.properties(effect_type,level).period_ticks)/20.0

func _physics_process(delta:float) -> void:
	if not is_instance_valid(target) or target.health <= 0:
		queue_free()
		return
	var ratio:float = target.get_minecraft_potion_effect_ratio(false)
	if ratio <= 0.000001:
		remaining = 0.0
		queue_free()
		return
	var step:float = minf(maxf(delta,0.0),maxf(remaining,0.0)) if not is_inf(remaining) else maxf(delta,0.0)
	if target.is_multiplayer_authority():
		tick_left -= step
		var period:float = float(EFFECTS.properties(effect_type,level).period_ticks)/20.0
		while tick_left <= 0.000001 and target.health > 0:
			tick_left += period
			# Flat 1 HP per pulse; amplifier changes INTERVAL, not amount, and
			# a caster's Strength does not increase periodic effect damage.
			var context:Dictionary = {"point":target.global_position,"shape":"all"}
			var caster:Variant = source_ref.get_ref() if source_ref != null else null
			if is_instance_valid(caster): context["source"] = caster
			if target.receive_spatial_raw_health_damage(ratio,context):
				DAMAGE_SFX.play(target,target.global_position)
	EFFECTS.elapse_sources(applications,delta)
	_choose_application()

func _process(delta:float) -> void:
	if remaining <= 0.0 or not is_instance_valid(target) or target.health <= 0: return
	_particle_left -= delta
	while _particle_left <= 0.0:
		_particle_left += PARTICLE_INTERVAL
		_spawn_particle()

func _spawn_particle() -> void:
	if not is_instance_valid(target) or target.health <= 0 or target.get_tree() == null: return
	var world:Node = target.get_tree().current_scene
	if world == null: return
	var particle:Sprite2D = POTION_PARTICLE.new()
	world.add_child(particle)
	particle.name = "WitherPotionParticle"
	particle.add_to_group("WitherPotionParticle")
	particle.setup(
		target.global_position + Vector2(randf_range(-13.0,13.0),randf_range(-18.0,8.0)),
		PARTICLE_COLOR,
		Vector2(randf_range(-7.0,7.0),randf_range(-48.0,-34.0)),
		randf_range(0.020,0.030),
		randf_range(0.060,0.072),82
	)

func _exit_tree() -> void:
	if painted and is_instance_valid(target) and target.image is CanvasItem and target.image.modulate.is_equal_approx(WITHER_TINT):
		target.image.modulate = saved_color
