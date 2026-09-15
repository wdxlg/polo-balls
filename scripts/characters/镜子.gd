extends ball

@export_category("镜子 - 外观")
@export var normal_texture:Texture2D
@export var reflect_texture:Texture2D

@export_category("随机反射窗口")
@export_range(0.05,5.0,0.05) var reflect_duration_min:float = 0.55
@export_range(0.05,5.0,0.05) var reflect_duration_max:float = 1.35
@export_range(0.05,10.0,0.05) var reflect_cooldown_min:float = 1.25
@export_range(0.05,10.0,0.05) var reflect_cooldown_max:float = 3.1
@export_range(0.0,100.0,1.0) var reflect_push_out:float = 24.0
@export var reflect_audio:String = "BlockAtk1"

var _reflect_active:bool = false
var _phase_left:float = 0.0


func _ready() -> void:
	super._ready()
	# 开局不固定是“立刻开盾”还是“先等一会”，让镜子的节奏本身也不可预测。
	if randf() < 0.5:
		_begin_reflect_window()
	else:
		_begin_cooldown(true)


func tick_physics(state:State,delta:float) -> void:
	if state != State.Die and health > 0:
		_phase_left -= delta
		if _phase_left <= 0.0:
			if _reflect_active:
				_begin_cooldown(false)
			else:
				_begin_reflect_window()
	super.tick_physics(state,delta)


func _begin_reflect_window() -> void:
	_reflect_active = true
	_set_character_texture(reflect_texture)
	_phase_left = _random_between(reflect_duration_min,reflect_duration_max,0.05)


func _begin_cooldown(initial:bool) -> void:
	_reflect_active = false
	_set_character_texture(normal_texture)
	_phase_left = _random_between(reflect_cooldown_min,reflect_cooldown_max,0.05)
	if initial:
		_phase_left *= randf_range(0.25,1.0)


func _set_character_texture(texture:Texture2D) -> void:
	if image is Sprite2D and texture != null:
		(image as Sprite2D).texture = texture


func _random_between(a:float,b:float,minimum:float) -> float:
	var low:float = maxf(minf(a,b),minimum)
	var high:float = maxf(maxf(a,b),low)
	return randf_range(low,high)


# 被 hitbox.gd 在伤害真正结算前调用。
# 反射窗口内可以反射多颗投射物；窗口之外近战/远程都正常受伤。
func can_receive_hit_from(incoming_hit) -> bool:
	if not _reflect_active or incoming_hit == null:
		return true
	var projectile:Node = incoming_hit.get_parent()
	if not (projectile is ball) and incoming_hit.owner is ball:
		projectile = incoming_hit.owner
	if projectile == null or not is_instance_valid(projectile) or not (projectile is ball):
		return true
	var shot:ball = projectile as ball
	if shot.Type != Ball_Type.Shooter and shot.Type != Ball_Type.Shooter_with_Health:
		return true
	if shot.has_meta(&"__mirror_reflect_pending"):
		return false

	shot.set_meta(&"__mirror_reflect_pending",true)
	call_deferred("_reflect_projectile",shot)
	if reflect_audio != "":
		Audios.play_sfx.rpc(reflect_audio,{},true)
	return false


# 通用格挡系统默认会销毁被拒绝的投射物；镜子是例外，
# 因为 can_receive_hit_from() 已经安排了反射，所以必须保留弹丸。
func should_destroy_projectile_on_rejected_hit(incoming_hit:hitbox) -> bool:
	if not _reflect_active or incoming_hit == null:
		return true
	var node:Node = incoming_hit.get_parent()
	if node is ball:
		var shot:ball = node as ball
		if shot.Type == Ball_Type.Shooter or shot.Type == Ball_Type.Shooter_with_Health:
			return false
	return true


func _reflect_projectile(shot:ball) -> void:
	if shot == null or not is_instance_valid(shot):
		return
	shot.remove_meta(&"__mirror_reflect_pending")

	var new_dir:Vector2 = -shot.direction
	if new_dir.length_squared() <= 0.000001:
		new_dir = shot.global_position - global_position
	if new_dir.length_squared() <= 0.000001:
		new_dir = Vector2.RIGHT
	new_dir = new_dir.normalized()

	var old_master = shot.Master
	shot.Master = self
	shot.Master_name = name
	shot.Team = Team
	shot.Ignore_Team_Damage_Setting = Ignore_Team_Damage_Setting
	shot.Target_Enemy = old_master if old_master != null and is_instance_valid(old_master) else Nearest_Enemy
	shot.direction = new_dir
	shot.global_position = global_position + new_dir * maxf(reflect_push_out,4.0)
	shot.velocity = Vector2.ZERO
	shot.Repel = Vector2.ZERO
	if shot.Type != Ball_Type.Ball:
		shot.global_rotation = shot.Default_Rotation + new_dir.angle()


func Die() -> void:
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)


# AI 战略接口：反射窗口不是“应该躲的空间”，而是“此时继续攻击可能把伤害弹回来”的目标风险。
func get_ai_strategy_info(_receiver:ball) -> Dictionary:
	return {
		"reflect_risk":1.0 if _reflect_active else 0.0,
	}
