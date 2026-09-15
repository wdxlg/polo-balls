extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

@export_category("伪军子弹")
@export_range(0.0,200.0,1.0) var enemy_damage:float = 15.0
@export_range(0.0,200.0,1.0) var friendly_damage:float = 25.0
@export_range(20.0,1200.0,10.0) var max_travel_distance:float = 430.0

var owner_soldier:ball = null
var _spawn_position:Vector2 = Vector2.ZERO
var _dying:bool = false

func _ready() -> void:
	Type = Ball_Type.Shooter
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	# 伪军子弹的友伤是角色硬规则，不受全局“关闭队伤”设置影响。
	Ignore_Team_Damage_Setting = true
	Hit_Audio = ""
	Collide_Audio = ""
	super._ready()
	_spawn_position = global_position

func _physics_process(_delta:float) -> void:
	if not is_multiplayer_authority() or _dying:
		return
	if _spawn_position.distance_to(global_position) >= maxf(max_travel_distance,1.0):
		_kill_projectile()

func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if not is_multiplayer_authority() or _dying:
		return
	var target:ball = _hurtbox_target_ball(hurt)
	if target == null or not is_instance_valid(target):
		return
	if target == owner_soldier or target == Master:
		return
	if target.has_method("is_fake_army_boss") and bool(target.call("is_fake_army_boss")):
		_kill_projectile()
		return
	var raw_damage:float = friendly_damage if TOOLS.same_side(self,target) else enemy_damage
	if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,raw_damage)):
		_kill_projectile()
		return
	var source:ball = owner_soldier if owner_soldier != null and is_instance_valid(owner_soldier) else self
	target.receive_positional_damage(raw_damage,global_position,false,source)
	_kill_projectile()

func when_collide(_speed:float,_collision:KinematicCollision2D) -> void:
	if is_multiplayer_authority():
		_kill_projectile()

func _kill_projectile() -> void:
	if _dying:
		return
	_dying = true
	Speed = 0.0
	direction = Vector2.ZERO
	velocity = Vector2.ZERO
	call_deferred("_finish_free")

func _finish_free() -> void:
	if is_instance_valid(self) and is_inside_tree():
		Game.free_node(self)
