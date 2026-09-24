extends Node
const PARTICLE = preload("res://scripts/effects/我的世界/女巫药水粒子.gd")
const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const META:StringName = &"mc_shulker_levitation"
var target:ball
var effect_type:String = "levitation"
var source:Node
var level:int = 1
var remaining:float = 3.0
var applications:Dictionary = {}
var _particle_wait:float = 0.0
var _world:Node

static func ceiling_blocked(unit:ball) -> bool:
	if unit.collision_shape_2d == null or unit.collision_shape_2d.shape == null: return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = unit.collision_shape_2d.shape
	query.transform = unit.collision_shape_2d.global_transform
	query.transform.origin += Vector2.UP * 5.0
	query.collision_mask = 1
	query.exclude = [unit.get_rid()]
	return not unit.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

static func apply(unit:ball,source:Node,duration:float = 3.0,level:int = 1) -> void:
	EFFECTS.apply_effect(unit,"levitation",level,duration,source)

## Called by the catalog. Both Shulker bullets and future sources share ONE
## real gravity node; the duration is not multiplied by the effect's level.
static func install(unit:ball,new_source:Node,duration:float,grade:int) -> void:
	if not is_instance_valid(unit) or unit.health <= 0 or not unit.can_receive_negative_effects(): return
	var old_ref:WeakRef = (unit.get_meta(META) as WeakRef) if unit.has_meta(META) else null
	var old:Variant = old_ref.get_ref() if old_ref != null else null
	if ceiling_blocked(unit):
		if is_instance_valid(old): old.finish()
		# 只做一次向上冲量，实体碰撞会截住它，不穿过头顶障碍，也不刷新浮空。
		unit.apply_knockback(Vector2.UP,4.0,90.0*grade,0.0,0.0,{"source":new_source,"stop_on_character":true})
		return
	if is_instance_valid(old) and not old.is_queued_for_deletion():
		old.refresh(duration,new_source,grade)
		return
	if is_instance_valid(old) and old.get_parent() == unit: unit.remove_child(old)
	var effect:Node = load("res://scripts/effects/我的世界/潜影浮空.gd").new()
	effect.name = EFFECTS.node_name("levitation")
	effect.target = unit
	effect.source = new_source
	effect.level = grade
	effect.remaining = duration
	EFFECTS.remember_source(effect.applications,new_source,grade,duration)
	unit.add_child(effect)
	unit.set_meta(META,weakref(effect))
	effect.begin()

func refresh(duration:float,new_source:Node = null,grade:int = 1) -> void:
	EFFECTS.remember_source(applications,new_source,grade,duration)
	_choose_application()

func remove_source(caster:Node) -> void:
	EFFECTS.forget_source(applications,caster)
	_choose_application()

func _choose_application() -> void:
	var best:Dictionary = EFFECTS.strongest_source(applications)
	if best.is_empty():
		finish()
		return
	var old_level:int = level
	level = int(best.grade)
	remaining = float(best.time)
	var ref:WeakRef = best.source_ref as WeakRef
	var caster:Variant = ref.get_ref() if ref != null else null
	source = caster as Node if is_instance_valid(caster) and caster is Node else null
	if old_level != level:
		if is_instance_valid(_world): _world.call("clear_directional_gravity",self,"levitation")
		begin()

func begin() -> void:
	_world = get_tree().current_scene
	if _world == null or not _world.has_method("register_directional_gravity"):
		finish()
		return
	# 独立的、只作用于该受击者的外力键；不覆盖 Sans 的重力状态。
	var strength:float = 90.0 * level * target.get_minecraft_potion_effect_ratio(false) + maxf(target.get_external_directional_gravity().y,0.0)
	_world.call("register_directional_gravity",self,"levitation",Vector2.UP,strength,false,target)

func _physics_process(delta:float) -> void:
	if not is_instance_valid(target) or target.health <= 0:
		finish()
		return
	if target.get_minecraft_potion_effect_ratio(false) <= 0.000001:
		finish()
		return
	if not target.is_combat_runtime_active(): return
	EFFECTS.elapse_sources(applications,delta)
	_choose_application()
	if remaining <= 0.0 or ceiling_blocked(target):
		finish()
		return
	_particle_wait -= delta
	if _particle_wait <= 0.0:
		_particle_wait = 0.18
		if get_tree().get_nodes_in_group("MCLevitationParticle").size() < 96:
			var particle:Node2D = PARTICLE.new()
			_world.add_child(particle)
			particle.add_to_group("BattleTransient")
			particle.add_to_group("MCLevitationParticle")
			particle.setup(target.global_position + Vector2(randf_range(-8,8),randf_range(-10,5)),Color.WHITE,Vector2(0,-22),0.026)
func finish() -> void:
	if is_instance_valid(_world) and _world.has_method("clear_directional_gravity"):
		_world.call("clear_directional_gravity",self,"levitation")
	if is_instance_valid(target):
		var own_ref:WeakRef = (target.get_meta(META) as WeakRef) if target.has_meta(META) else null
		if own_ref != null and own_ref.get_ref() == self: target.remove_meta(META)
	remaining = 0.0
	queue_free()
func _exit_tree() -> void:
	if is_instance_valid(_world) and _world.has_method("clear_directional_gravity"):
		_world.call("clear_directional_gravity",self,"levitation")
	if is_instance_valid(target):
		var own_ref:WeakRef = (target.get_meta(META) as WeakRef) if target.has_meta(META) else null
		if own_ref != null and own_ref.get_ref() == self: target.remove_meta(META)
