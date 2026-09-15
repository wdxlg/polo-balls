extends "res://scripts/characters/我的世界/mc_mob_base.gd"
@export var lifetime:float = 6.0
@export var enderman_clone:bool = false
var _life_left:float
var _retired:bool = false
func _ready() -> void:
	Type = Ball_Type.Creature
	collision_layer = 0
	collision_mask = 1 if enderman_clone else 0
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	_life_left = lifetime
	add_to_group("MCEndermanClone" if enderman_clone else "MCVex")
	_apply_creature_tint()
func _apply_creature_tint() -> void:
	if not is_instance_valid(image): return
	if enderman_clone:
		image.self_modulate = Color(0.8,0.52,1.0,0.52)
		image_color = Color(0.62,0.16,0.88)
		image_color_mix = 0.48
		set_image_color()
	else:
		image.self_modulate = Color(1.0,1.0,1.0,0.82)
func tick_physics(state:State,delta:float) -> void:
	# Creature 的公共状态机不会自动删 0HP 生物；先做生命周期检查，不可放在 mc_live() 内。
	if _retired: return
	if health <= 0 or not is_instance_valid(Master):
		retire()
		return
	if mc_live():
		_life_left -= delta
		if _life_left <= 0.0:
			health = 0
			retire()
			return
		# 分身保留公共移动/碰墙反弹，不再向敌人持续改写方向。
	super.tick_physics(state,delta)
	_apply_creature_tint()
func move(speed:float,delta:float) -> void:
	var before:Vector2 = global_position
	super.move(speed,delta)
	var dx:float = global_position.x-before.x
	if absf(dx) > 0.001: set_character_visual_flip_h(dx > 0.0 if dir_left else dx < 0.0)
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _retired: return
	super.take_damage(damage,ignore_block)
	if health <= 0: retire()
func retire() -> void:
	if _retired: return
	_retired = true
	mc_play("death",-8.0)
	if enderman_clone:
		MC_FX.portal(self,global_position,28,true)
		MC_FX.smoke(self,global_position,0.0,0.18)
	else: mc_death_visual()
	hide()
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	for group:String in ["Ball","MCEndermanClone","MCVex"]:
		if is_in_group(group): remove_from_group(group)
	queue_free()
func Die() -> void: retire()

func is_combat_targetable() -> bool:
	# 这些是可战斗的召唤物，不是默认不可锁定的装饰 Creature。
	if _retired or health <= 0 or is_queued_for_deletion(): return false
	if has_meta(&"ignore_combat_targeting") and bool(get_meta(&"ignore_combat_targeting")): return false
	return state_machine == null or state_machine.current_state != State.Die
