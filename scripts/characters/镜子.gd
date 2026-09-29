extends ball
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")

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
	if not _reflect_active or incoming_hit == null: return true
	var shot:Node = incoming_hit.get_parent()
	if not PROJECTILE_API.is_projectile(shot): shot = incoming_hit.owner
	return not try_reflect_projectile(shot)

func try_reflect_projectile(shot:Node) -> bool:
	if not _reflect_active or not is_multiplayer_authority() or not shot is Node2D: return false
	if not PROJECTILE_API.reflect(shot,self,reflect_push_out): return false
	if reflect_audio != "": Audios.play_sfx.rpc(reflect_audio,{},true)
	return true

func should_destroy_projectile_on_rejected_hit(incoming_hit:hitbox) -> bool:
	if incoming_hit == null: return true
	var shot:Node = incoming_hit.get_parent()
	return not (PROJECTILE_API.is_projectile(shot) and int(shot.get_meta("projectile_reflected_frame",-1)) == Engine.get_physics_frames())

func _reflect_projectile(shot:Node) -> void:
	try_reflect_projectile(shot)

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
