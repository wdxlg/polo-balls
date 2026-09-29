extends Area2D
## Deliberately no Ball/BattleTransient groups and no legacy direction/speed/owner fields.
var motion:Vector2 = Vector2(300,0)
var caster:WeakRef
var affiliation:String = ""
var power:float = 17.0
func _init() -> void:
	set_meta("combat_classification",{"entity_kind":"projectile"})
func get_projectile_velocity() -> Vector2: return motion
func set_projectile_velocity(value:Vector2) -> void: motion = value
func get_projectile_source() -> Node: return caster.get_ref() if caster != null else null
func get_projectile_team() -> String: return affiliation
func get_projectile_damage() -> float: return power
func bind_projectile_owner(source:Node,team:String,_target:Node) -> void:
	caster = weakref(source) if source != null else null
	affiliation = team
func _physics_process(delta:float) -> void:
	global_position += motion*delta
