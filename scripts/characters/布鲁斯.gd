extends ball

const DOG_SCENE:PackedScene = preload("res://scenes/creatures/布鲁斯_狗.tscn")
const FOOD_SCRIPT = preload("res://scripts/creatures/布鲁斯_食物.gd")
const VISUAL_NORMAL:Texture2D = preload("res://Images/characters/布鲁斯/主人普通.png")
const VISUAL_THROW:Texture2D = preload("res://Images/characters/布鲁斯/主人投食.png")

const FOOD_BONE:int = 0
const FOOD_BIG_MEAT:int = 1
const FOOD_SAUSAGE:int = 2
const FOOD_CHEW_STICK:int = 3

@export_category("布鲁斯 - 人犬")
@export_range(30.0,100.0,1.0) var dog_spawn_distance:float = 44.0
@export_range(40.0,220.0,1.0) var leash_soft_limit:float = 118.0
@export_range(60.0,320.0,1.0) var leash_hard_limit:float = 178.0
@export_range(20.0,500.0,5.0) var owner_pull_min_speed:float = 95.0
@export_range(50.0,800.0,5.0) var owner_pull_max_speed:float = 285.0
@export_range(1.0,8.0,0.1) var owner_pull_stretch_gain:float = 3.2

@export_category("布鲁斯 - 投食")
@export_range(0.1,1.5,0.05) var food_throw_duration:float = 0.36
@export_range(0.0,100.0,1.0) var food_throw_arc_height:float = 28.0
@export_range(20.0,100.0,1.0) var food_map_margin:float = 34.0
@export_range(40.0,300.0,1.0) var food_min_throw_distance:float = 75.0
@export_range(80.0,500.0,1.0) var food_max_throw_distance:float = 220.0

# 权重总和不要求等于 1，代码会自动归一化。
@export_range(0.0,100.0,1.0) var bone_weight:float = 42.0
@export_range(0.0,100.0,1.0) var big_meat_weight:float = 28.0
@export_range(0.0,100.0,1.0) var sausage_weight:float = 18.0
@export_range(0.0,100.0,1.0) var chew_stick_weight:float = 12.0

var dog:ball = null
var _leash:Line2D = null
var _linked_death_started:bool = false
var _active_food:Node2D = null


func _ready() -> void:
	super._ready()
	image_color = Color.WHITE
	image_color_mix = 0.0
	set_image_color()
	_set_human_visual(VISUAL_NORMAL)
	_create_leash()
	if is_multiplayer_authority():
		call_deferred("_spawn_dog")


func get_preview_texture() -> Texture2D:
	# 放置预览不会执行 _ready()；显式告诉 world.gd 使用角色的正常立绘。
	return VISUAL_NORMAL


func _set_human_visual(texture:Texture2D) -> void:
	if not image is Sprite2D or texture == null:
		return
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture == texture:
		return
	sprite.texture = texture
	sprite.offset = Vector2.ZERO
	sprite.visible = true
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		fitter.call_deferred("apply_visual_fit_only")


func get_next_state(state:State) -> int:
	# 狗还在捡/吃/带回上一份食物时，主人不会把地图铺满食物。
	if (
		is_multiplayer_authority()
		and Can_Skill
		and not is_damage_output_disabled()
		and state_machine.last_state_dis.Skill >= Skill_Cooling
		and (dog == null or not is_instance_valid(dog) or bool(dog.call("is_busy_with_food")))
	):
		var saved_skill_time:float = float(state_machine.last_state_dis.Skill)
		Can_Skill = false
		var next_state:int = super.get_next_state(state)
		Can_Skill = true
		state_machine.last_state_dis.Skill = saved_skill_time
		return next_state
	return super.get_next_state(state)


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and not _linked_death_started:
		if dog != null and is_instance_valid(dog) and dog.health <= 0 and health > 0:
			health = 0
		_apply_leash_pull()
	super.tick_physics(state,delta)
	_update_leash_visual()


func Skill() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		Using_Skill = false
		return
	if is_damage_output_disabled() or dog == null or not is_instance_valid(dog) or bool(dog.call("is_busy_with_food")):
		Using_Skill = false
		return

	Using_Skill = true
	_set_human_visual(VISUAL_THROW)
	_throw_random_food()
	await get_tree().create_timer(maxf(minf(food_throw_duration,0.42),0.20)).timeout
	if is_instance_valid(self):
		_set_human_visual(VISUAL_NORMAL)
		Using_Skill = false


func Attack() -> void:
	# 主人本身没有造成伤害的普通攻击。
	Attacking = false


func _spawn_dog() -> void:
	if not is_instance_valid(self) or health <= 0 or dog != null:
		return
	var world := get_tree().current_scene
	if world == null:
		return

	var new_dog:ball = DOG_SCENE.instantiate()
	new_dog.Master = self
	new_dog.Master_name = str(get_path())
	new_dog.Team = Team
	new_dog.inherit_master_attack_power = true
	new_dog.master_attack_damage_multiplier = 1.0
	new_dog.Target_Enemy = Target_Enemy
	new_dog.direction = direction
	new_dog.set("owner_human",self)
	new_dog.set("leash_soft_limit",leash_soft_limit)
	new_dog.set("leash_hard_limit",leash_hard_limit)
	new_dog.name = Game.return_random_name(new_dog)
	world.add_child(new_dog,true)

	var side:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	new_dog.global_position = _clamp_point_to_map(global_position + side * dog_spawn_distance,18.0)
	dog = new_dog
	_update_leash_visual()


func _create_leash() -> void:
	_leash = Line2D.new()
	_leash.name = "BruceLeash"
	_leash.width = 8.0
	_leash.default_color = Color(0.18,0.10,0.055,0.88)
	_leash.antialiased = true
	_leash.z_index = -4
	_leash.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_leash.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_leash)


func _update_leash_visual() -> void:
	if _leash == null or not is_instance_valid(_leash):
		return
	if dog == null or not is_instance_valid(dog) or _linked_death_started:
		_leash.visible = false
		return
	_leash.visible = true
	_leash.points = PackedVector2Array([Vector2.ZERO,to_local(dog.global_position)])


func _apply_leash_pull() -> void:
	if dog == null or not is_instance_valid(dog):
		return
	if not bool(dog.call("is_busy_with_food")):
		return
	var to_dog:Vector2 = dog.global_position - global_position
	var distance:float = to_dog.length()
	if distance <= leash_soft_limit or distance <= 0.001:
		return
	var stretch:float = distance - leash_soft_limit
	var pull_speed:float = clampf(owner_pull_min_speed + stretch * owner_pull_stretch_gain,owner_pull_min_speed,owner_pull_max_speed)
	if distance >= leash_hard_limit:
		pull_speed = owner_pull_max_speed
	Repel += to_dog / distance * pull_speed


func _throw_random_food() -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	if _active_food != null and is_instance_valid(_active_food):
		_active_food.queue_free()
		_active_food = null

	var kind:int = _roll_food_type()
	var food:Node2D = FOOD_SCRIPT.new()
	food.name = "BruceFood_%d" % Time.get_ticks_usec()
	food.call("setup",kind)
	world.add_child(food,true)
	food.global_position = global_position
	_active_food = food
	food.connect("landed",Callable(self,"_on_food_landed"))
	food.call("launch_to",_choose_food_point(),food_throw_duration,food_throw_arc_height)


func _on_food_landed(food:Node2D) -> void:
	if food == null or not is_instance_valid(food):
		return
	if dog == null or not is_instance_valid(dog) or dog.health <= 0:
		food.queue_free()
		return
	if not bool(dog.call("assign_food",food)):
		food.queue_free()


func _roll_food_type() -> int:
	var weights:Array[float] = [maxf(bone_weight,0.0),maxf(big_meat_weight,0.0),maxf(sausage_weight,0.0),maxf(chew_stick_weight,0.0)]
	var total:float = 0.0
	for value:float in weights:
		total += value
	if total <= 0.0:
		return FOOD_BONE
	var roll:float = randf() * total
	for i:int in range(weights.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return FOOD_CHEW_STICK


func _choose_food_point() -> Vector2:
	var rect:Rect2 = _get_map_rect()
	var min_distance:float = maxf(food_min_throw_distance,20.0)
	var max_distance:float = maxf(food_max_throw_distance,min_distance)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return global_position + Vector2.from_angle(randf_range(0.0,TAU)) * randf_range(min_distance,max_distance)

	var margin:float = maxf(food_map_margin,8.0)
	var best:Vector2 = global_position
	for _attempt:int in range(12):
		var candidate := Vector2(
			randf_range(rect.position.x + margin,rect.end.x - margin),
			randf_range(rect.position.y + margin,rect.end.y - margin)
		)
		var distance:float = candidate.distance_to(global_position)
		if distance >= min_distance and distance <= max_distance:
			return candidate
		if absf(distance - (min_distance + max_distance) * 0.5) < absf(best.distance_to(global_position) - (min_distance + max_distance) * 0.5):
			best = candidate
	if best == global_position:
		best = global_position + Vector2.from_angle(randf_range(0.0,TAU)) * min_distance
	return _clamp_point_to_map(best,margin)


func _get_map_rect() -> Rect2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	if not world.map_group.has(str(world.now_choose_map)):
		return Rect2()
	var map_node = world.map_group[str(world.now_choose_map)]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.return_map_world_rect(map_node)


func _clamp_point_to_map(point:Vector2,margin:float) -> Vector2:
	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return point
	var safe_margin:float = maxf(margin,4.0)
	return Vector2(
		clampf(point.x,rect.position.x + safe_margin,rect.end.x - safe_margin),
		clampf(point.y,rect.position.y + safe_margin,rect.end.y - safe_margin)
	)


func _kill_linked_dog() -> void:
	if dog != null and is_instance_valid(dog) and dog.has_method("force_linked_death"):
		dog.call("force_linked_death")


func Die() -> void:
	if _linked_death_started:
		return
	_linked_death_started = true
	if _active_food != null and is_instance_valid(_active_food):
		_active_food.queue_free()
	_active_food = null
	_kill_linked_dog()
	if _leash != null and is_instance_valid(_leash):
		_leash.visible = false
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
