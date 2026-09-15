extends ball

const MINION_SCENE:PackedScene = preload("res://scenes/creatures/投稿随从.tscn")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const MINION_SCRIPT = preload("res://scripts/creatures/投稿随从.gd")
const KING_NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/国王/胖国王_普通.png")
const KING_PANIC_TEXTURE:Texture2D = preload("res://Images/characters/人物/国王/胖国王_慌乱抓头.png")

@export_category("国王")
@export_range(1.0,20.0,0.1) var summon_interval:float = 5.0
@export_range(1,8,1) var normal_summon_count:int = 2
@export_range(1,8,1) var low_health_summon_count:int = 3
@export_range(1,20,1) var guard_cap:int = 8
@export_range(0.1,0.9,0.01) var general_trigger_ratio:float = 0.5
@export_range(0.05,0.8,0.01) var frenzy_trigger_ratio:float = 0.333
@export_range(1.0,2.0,0.01) var frenzy_speed_multiplier:float = 1.30

var _summon_elapsed:float = 0.0
var _general_summoned:bool = false
var _frenzy:bool = false
var _owned:Array[WeakRef] = []

func get_health_threshold_values() -> PackedFloat32Array:
	# 半血召唤将军；约 1/3 血后提高守卫召唤数量。
	return PackedFloat32Array([
		float(Max_health) * general_trigger_ratio,
		float(Max_health) * frenzy_trigger_ratio,
	])

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	super._ready()
	if self_hitbox != null:
		self_hitbox.monitoring = false

func _process(delta:float) -> void:
	_prune_owned()
	if not is_multiplayer_authority() or health <= 0:
		return
	var ratio:float = float(health) / maxf(float(Max_health),1.0)
	if not _general_summoned and ratio <= general_trigger_ratio:
		_general_summoned = true
		_spawn_minion(MINION_SCRIPT.Kind.KING_GENERAL)
	if not _frenzy and ratio <= frenzy_trigger_ratio:
		_enter_frenzy()
	_summon_elapsed += delta
	if _summon_elapsed >= summon_interval:
		_summon_elapsed = 0.0
		var count:int = low_health_summon_count if _frenzy else normal_summon_count
		for i:int in range(count):
			if _count_kind(MINION_SCRIPT.Kind.KING_GUARD) >= guard_cap:
				break
			_spawn_minion(MINION_SCRIPT.Kind.KING_GUARD)


func _enter_frenzy() -> void:
	_frenzy = true
	_set_king_texture(KING_PANIC_TEXTURE)
	# world.gd 会周期性从 default_properties 恢复基础属性，
	# 因此阶段加速必须同步更新默认 Speed 才能持续生效。
	var base_speed:float = float(default_properties.get("Speed",Speed))
	var panic_speed:float = base_speed * frenzy_speed_multiplier
	Speed = panic_speed
	default_properties["Speed"] = panic_speed

func _set_king_texture(texture:Texture2D) -> void:
	if not image is Sprite2D or texture == null:
		return
	(image as Sprite2D).texture = texture
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		fitter.call_deferred("apply_visual_fit_only")

func _spawn_minion(kind_value:int) -> void:
	var minion:ball = MINION_SCENE.instantiate() as ball
	if minion == null:
		return
	minion.Master = self
	minion.Master_name = name
	minion.Team = Team
	minion.inherit_master_attack_power = true
	minion.Target_Enemy = Target_Enemy
	minion.name = Game.return_random_name(minion)
	minion.set("kind",kind_value)
	var angle:float = randf_range(0.0,TAU)
	var point:Vector2 = TOOLS.safe_spawn_position(self,global_position + Vector2.from_angle(angle) * randf_range(34.0,70.0),22.0)
	get_tree().current_scene.add_child(minion,true)
	minion.global_position = point
	_owned.append(weakref(minion))

func _owned_balls() -> Array[ball]:
	var alive:Array[ball] = []
	var kept:Array[WeakRef] = []
	for ref:WeakRef in _owned:
		if ref == null:
			continue
		var raw:Variant = ref.get_ref()
		if raw is ball:
			var minion:ball = raw as ball
			if is_instance_valid(minion):
				alive.append(minion)
				kept.append(ref)
	_owned = kept
	return alive

func _count_kind(kind_value:int) -> int:
	var count:int = 0
	for minion:ball in _owned_balls():
		if int(minion.get("kind")) == kind_value and minion.health > 0:
			count += 1
	return count

func _prune_owned() -> void:
	_owned_balls()

func _kill_owned() -> void:
	for minion:ball in _owned_balls():
		minion.health = 0
	_owned.clear()

func Die() -> void:
	_kill_owned()
	super()
	queue_free()

func _exit_tree() -> void:
	_kill_owned()
