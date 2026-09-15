class_name MoonSanityCharacter
extends ball

const SANITY_BAR_SCRIPT = preload("res://scripts/ui/月计理智条.gd")
const SANITY_MIN:float = -45.0
const SANITY_MAX:float = 45.0

@export_category("月计 - 理智")
@export_range(-45.0,45.0,1.0) var sanity:float = 0.0
# 对一个满血目标累计造成 100% Max_health 的真实生命伤害，大约获得这些理智。
@export_range(0.0,45.0,0.5) var sanity_gain_per_enemy_healthbar:float = 9.0
# 单次真实伤害至少提供少量变化，确保“造成伤害就会增加”。
@export_range(0.0,5.0,0.05) var sanity_min_gain_per_damage_event:float = 0.25
# 自己累计损失 100% Max_health 的真实生命，大约损失这些理智。
@export_range(0.0,45.0,0.5) var sanity_loss_per_own_healthbar:float = 12.0
@export_range(0.0,5.0,0.05) var sanity_min_loss_per_damage_event:float = 0.30
# 击杀额外奖励。按“致死伤害发生前，敌人还剩多少比例生命”线性缩放；
# 敌人越残，击杀奖励越低。
@export_range(0.0,45.0,0.5) var sanity_kill_bonus_at_full_health:float = 12.0
@export_range(0.0,45.0,0.5) var sanity_teammate_death_loss:float = 10.0
@export var sanity_bar_offset:Vector2 = Vector2(-120.0, 145.0)

var _sanity_bar:MoonSanityBar = null

func _ready() -> void:
	super._ready()
	_create_sanity_bar()
	_set_sanity_local(sanity, true)
	if not Game.combat_damage_resolved.is_connected(_on_combat_damage_resolved):
		Game.combat_damage_resolved.connect(_on_combat_damage_resolved)
	if not Game.combatant_died.is_connected(_on_combatant_died):
		Game.combatant_died.connect(_on_combatant_died)

func _create_sanity_bar() -> void:
	if _sanity_bar != null and is_instance_valid(_sanity_bar):
		return
	_sanity_bar = SANITY_BAR_SCRIPT.new() as MoonSanityBar
	_sanity_bar.name = "MoonSanityBar"
	_sanity_bar.position = sanity_bar_offset
	_sanity_bar.z_index = 40
	add_child(_sanity_bar)

func _set_sanity_local(value:float, instant:bool = false) -> void:
	sanity = clampf(value, SANITY_MIN, SANITY_MAX)
	if _sanity_bar != null and is_instance_valid(_sanity_bar):
		_sanity_bar.set_sanity(sanity, instant)

func change_sanity(delta:float) -> void:
	if is_zero_approx(delta):
		return
	_set_sanity_local(sanity + delta, false)
	if multiplayer.has_multiplayer_peer():
		_remote_sync_sanity.rpc(sanity)

@rpc("authority","call_remote","unreliable")
func _remote_sync_sanity(value:float) -> void:
	_set_sanity_local(value, false)

func _on_combat_damage_resolved(
	source:Node,
	target:Node,
	actual_health_damage:float,
	_target_health_before:float
) -> void:
	if not is_inside_tree() or not is_multiplayer_authority():
		return
	if source != self or target == null or actual_health_damage <= 0.0:
		return
	var target_max_health:float = maxf(float(target.get("Max_health")), 1.0)
	var ratio:float = actual_health_damage / target_max_health
	var gain:float = maxf(
		sanity_min_gain_per_damage_event,
		ratio * sanity_gain_per_enemy_healthbar
	)
	change_sanity(gain)

# ball.health setter 的统一钩子：任何真实扣血路径都会进入这里。
func on_actual_health_damage_received(actual_health_damage:float, _health_before:float) -> void:
	if not is_inside_tree() or not is_multiplayer_authority() or actual_health_damage <= 0.0:
		return
	var ratio:float = actual_health_damage / maxf(float(Max_health), 1.0)
	var loss:float = maxf(
		sanity_min_loss_per_damage_event,
		ratio * sanity_loss_per_own_healthbar
	)
	change_sanity(-loss)

func _on_combatant_died(victim:Node, killer:Node, health_before_lethal:float) -> void:
	if not is_inside_tree() or not is_multiplayer_authority():
		return
	if victim == null or victim == self:
		return

	if killer == self and _is_enemy_combatant(victim):
		var victim_max_health:float = maxf(float(victim.get("Max_health")), 1.0)
		var pre_kill_ratio:float = clampf(health_before_lethal / victim_max_health, 0.0, 1.0)
		change_sanity(sanity_kill_bonus_at_full_health * pre_kill_ratio)

	if _is_real_teammate(victim):
		change_sanity(-sanity_teammate_death_loss)

func _is_enemy_combatant(other:Node) -> bool:
	if not (other is ball) or other == self:
		return false
	var other_ball:= other as ball
	var my_team:String = str(Team).strip_edges()
	var other_team:String = str(other_ball.Team).strip_edges()
	# 空 Team 在本项目里表示各自独立阵营，因此彼此仍算敌人。
	if my_team.is_empty() or other_team.is_empty():
		return true
	return my_team != other_team


func _is_real_teammate(other:Node) -> bool:
	if not (other is ball):
		return false
	var other_ball:= other as ball
	if other_ball.Type != Ball_Type.Ball:
		return false
	# 有 Master 的单位属于召唤/附属，不把召唤物死亡算作“队友死亡”。
	if other_ball.Master != null and is_instance_valid(other_ball.Master):
		return false
	var my_team:String = str(Team).strip_edges()
	var other_team:String = str(other_ball.Team).strip_edges()
	# 项目现有规则：空 Team 表示各自独立阵营。
	return not my_team.is_empty() and my_team == other_team
