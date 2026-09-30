extends ball
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")

const FOOD_BONE:int = 0
const FOOD_BIG_MEAT:int = 1
const FOOD_SAUSAGE:int = 2
const FOOD_CHEW_STICK:int = 3
const VISUAL_SIT:Texture2D = preload("res://Images/characters/布鲁斯/狗坐下.png")
const VISUAL_RUN:Texture2D = preload("res://Images/characters/布鲁斯/狗跑步.png")
const VISUAL_EAT:Texture2D = preload("res://Images/characters/布鲁斯/狗进食.png")
const VISUAL_BITE:Texture2D = preload("res://Images/characters/布鲁斯/狗咬人.png")
const TEX_BONE:Texture2D = preload("res://Images/characters/布鲁斯/骨头.png")

enum DogMode {
	ORBIT,
	GO_TO_FOOD,
	EATING,
	HOLDING_BONE,
	RETURNING,
}

@export_category("布鲁斯 - 跟随")
@export_range(18.0,90.0,1.0) var orbit_distance:float = 42.0
@export_range(40.0,220.0,1.0) var leash_soft_limit:float = 118.0
@export_range(60.0,300.0,1.0) var leash_hard_limit:float = 178.0
@export_range(40.0,500.0,5.0) var orbit_speed:float = 155.0
@export_range(60.0,650.0,5.0) var food_run_speed:float = 225.0
@export_range(8.0,60.0,1.0) var arrive_distance:float = 14.0
@export_range(140.0,340.0,5.0) var dog_visual_max_size:float = 235.0

@export_category("布鲁斯 - 咬击/冲撞")
@export_range(15.0,120.0,1.0) var bite_trigger_radius:float = 56.0
@export_range(0.0,10.0,0.05) var bite_damage_multiplier:float = 1.4444444
@export_range(0.2,4.0,0.05) var bite_cooldown:float = 1.25
@export_range(0.0,10.0,0.05) var food_run_collision_damage_multiplier:float = 1.0
@export_range(0.0,120.0,1.0) var contact_knockback_distance:float = 28.0
@export_range(80.0,1000.0,10.0) var contact_knockback_speed:float = 390.0

@export_category("布鲁斯 - 食物")
@export_range(0.1,5.0,0.05) var bone_hold_time:float = 0.65
@export_range(0.5,6.0,0.1) var big_meat_eat_time:float = 2.8
@export_range(1.0,300.0,1.0) var big_meat_total_heal:float = 112.0
@export_range(0.2,3.0,0.05) var sausage_eat_time:float = 0.85
@export_range(1.0,150.0,1.0) var sausage_heal:float = 38.0
@export_range(0.5,8.0,0.1) var sausage_speed_buff_time:float = 4.0
@export_range(1.0,2.0,0.05) var sausage_speed_multiplier:float = 1.30
@export_range(0.2,3.0,0.05) var chew_stick_eat_time:float = 0.65
@export_range(0.0,100.0,1.0) var chew_stick_heal:float = 24.0
@export_range(0.0,10.0,0.05) var chew_stick_next_bite_bonus_multiplier:float = 0.8333333

var owner_human:ball = null
var mode:int = DogMode.ORBIT
var food_target:Node2D = null
var _orbit_side:Vector2 = Vector2.RIGHT
var _bite_target:ball = null
var _bite_cooldown_left:float = 0.0
var _contact_cooldowns:Dictionary = {}
var _linked_death_started:bool = false
var _eat_serial:int = 0
var _speed_buff_left:float = 0.0
var _next_bite_bonus_multiplier:float = 0.0
var _carried_bone_visual:Node2D = null
var _bite_pose_left:float = 0.0
var _current_visual:Texture2D = null
var _manual_bite_window:float = 0.0


func _ready() -> void:
	Type = Ball_Type.Creature
	manual_controllable_subentity = true
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	side_status_ui_enabled = false
	Speed = orbit_speed
	super._ready()
	add_to_group("BruceDog")
	# 不让默认 Hitbox 自动结算；狗使用真实 CharacterBody2D 碰撞点做咬击/冲撞。
	if self_hitbox != null:
		self_hitbox.monitoring = false
	image_color = Color.WHITE
	image_color_mix = 0.0
	set_image_color()
	_set_dog_visual(VISUAL_SIT)


func _set_dog_visual(texture:Texture2D) -> void:
	if not image is Sprite2D or texture == null:
		return
	if _current_visual == texture:
		return
	_current_visual = texture
	var sprite:Sprite2D = image as Sprite2D
	sprite.texture = texture
	sprite.offset = Vector2.ZERO
	sprite.visible = true
	var size:Vector2 = texture.get_size()
	var longest:float = maxf(size.x,size.y)
	var fit:float = maxf(dog_visual_max_size,1.0) / maxf(longest,1.0)
	sprite.scale = Vector2(fit,fit)


func _update_dog_visual() -> void:
	if mode == DogMode.EATING:
		_set_dog_visual(VISUAL_EAT)
	elif _bite_pose_left > 0.0:
		_set_dog_visual(VISUAL_BITE)
	elif direction.length_squared() > 0.0025 or velocity.length_squared() > 16.0:
		_set_dog_visual(VISUAL_RUN)
	else:
		_set_dog_visual(VISUAL_SIT)


func is_combat_targetable() -> bool:
	return health > 0 and not _linked_death_started and not is_queued_for_deletion()


# Creature 默认不会播放角色白闪；布鲁斯的狗本身是可锁定、可受伤的战斗单位，
# 因此单独保留受击反馈，但不切换到人物 Hurt 状态。
func hit_white_visual_only() -> void:
	if image == null or not is_instance_valid(image):
		return
	if hit_white_tween != null and hit_white_tween.is_valid():
		hit_white_tween.kill()
	hit_white_method(1.0)
	hit_white_tween = create_tween()
	hit_white_tween.tween_method(hit_white_method,1.0,0.0,hit_white_duration)


func hit_white(_ignore_block:bool = false) -> void:
	hit_white_visual_only()


func is_busy_with_food() -> bool:
	return mode != DogMode.ORBIT


func assign_food(food:Node2D) -> bool:
	if food == null or not is_instance_valid(food) or _linked_death_started or health <= 0:
		return false
	if mode != DogMode.ORBIT:
		return false
	food_target = food
	mode = DogMode.GO_TO_FOOD
	_bite_target = null
	return true

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or mode!=DogMode.ORBIT or _bite_cooldown_left>0.0 or not has_player_control_aim(): return
	var point:Vector2 = player_control_aim_world_position()
	var chosen:ball = null
	var nearest:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball) or raw==self or raw==owner_human or raw.health<=0 or _is_friendly(raw): continue
		var distance:float = raw.global_position.distance_to(point)
		if distance<=U.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	if chosen==null or global_position.distance_to(chosen.global_position)>bite_trigger_radius: return
	_bite_target=chosen
	_manual_bite_window=0.5 # Existing bite still needs a real physical contact.
func set_player_control_peer(peer_id:int) -> void:
	if peer_id!=player_control_peer_id:
		_bite_target=null
		_manual_bite_window=0.0
	super.set_player_control_peer(peer_id)


func tick_physics(_state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		return
	if _linked_death_started:
		velocity = Vector2.ZERO
		return
	if health <= 0:
		_start_linked_death()
		return
	if owner_human == null or not is_instance_valid(owner_human) or owner_human.health <= 0:
		force_linked_death()
		return

	_bite_cooldown_left = maxf(_bite_cooldown_left - delta,0.0)
	_bite_pose_left = maxf(_bite_pose_left - delta,0.0)
	_speed_buff_left = maxf(_speed_buff_left - delta,0.0)
	_cleanup_contact_cooldowns(delta)

	# 和人物本体保持全局“允许移动”设置一致；暂停移动时吃东西/冷却仍正常计时。
	if not bool(Game.Game_Settings.get("Ball_Can_Move",true)):
		direction = Vector2.ZERO
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	if is_player_controlled() and mode in [DogMode.ORBIT,DogMode.RETURNING]:
		# Food/eating sequences already in flight continue, but the trip back
		# after eating is walked with WASD instead of owner-follow AI.
		if mode==DogMode.RETURNING and global_position.distance_to(owner_human.global_position+_orbit_side*orbit_distance)<=arrive_distance+5.0:
			_finish_return_home()
		_manual_bite_window=maxf(0.0,_manual_bite_window-delta)
		if _manual_bite_window<=0.0 or not is_instance_valid(_bite_target): _bite_target=null
		direction=Vector2.ZERO if dizziness else player_control_direction
		_dog_move(delta)
		_update_dog_visual()
		Repel=Vector2.ZERO
		return

	match mode:
		DogMode.ORBIT:
			_update_orbit_mode()
		DogMode.GO_TO_FOOD:
			_update_food_run_mode()
		DogMode.EATING:
			direction = Vector2.ZERO
		DogMode.HOLDING_BONE:
			direction = Vector2.ZERO
		DogMode.RETURNING:
			_update_return_mode()

	_dog_move(delta)
	_update_dog_visual()
	Repel = Vector2.ZERO


func _update_orbit_mode() -> void:
	var enemy:ball = _nearest_real_enemy()
	if enemy != null:
		var owner_to_enemy:Vector2 = enemy.global_position - owner_human.global_position
		if owner_to_enemy.length_squared() > 0.000001:
			_orbit_side = owner_to_enemy.normalized()

		if _bite_cooldown_left <= 0.0 and global_position.distance_to(enemy.global_position) <= bite_trigger_radius:
			_bite_target = enemy
		else:
			_bite_target = null
	else:
		_bite_target = null
		if owner_human.direction.length_squared() > 0.000001:
			_orbit_side = owner_human.direction.normalized()

	var desired_position:Vector2 = owner_human.global_position + _orbit_side * orbit_distance
	if _bite_target != null and is_instance_valid(_bite_target):
		desired_position = _bite_target.global_position
	_set_direction_to(desired_position)


func _update_food_run_mode() -> void:
	_bite_target = null
	if food_target == null or not is_instance_valid(food_target):
		mode = DogMode.RETURNING
		return
	_set_direction_to(food_target.global_position)
	if global_position.distance_to(food_target.global_position) <= arrive_distance:
		_consume_or_pick_food()


func _update_return_mode() -> void:
	_bite_target = null
	var desired:Vector2 = owner_human.global_position + _orbit_side * orbit_distance
	_set_direction_to(desired)
	if global_position.distance_to(desired) <= arrive_distance + 5.0:
		_finish_return_home()


func _set_direction_to(point:Vector2) -> void:
	var travel:Vector2 = point - global_position
	if travel.length_squared() <= 0.000001:
		direction = Vector2.ZERO
	else:
		direction = travel.normalized()


func _current_move_speed() -> float:
	var speed_value:float = orbit_speed if mode == DogMode.ORBIT or mode == DogMode.RETURNING else food_run_speed
	if _speed_buff_left > 0.0:
		speed_value *= maxf(sausage_speed_multiplier,1.0)

	# 绳子已经被拉得很紧时，狗继续向外跑会自动减速，让主人有机会被拖上来。
	if owner_human != null and is_instance_valid(owner_human) and direction.length_squared() > 0.0:
		var from_owner:Vector2 = global_position - owner_human.global_position
		var distance:float = from_owner.length()
		if distance > leash_soft_limit and distance > 0.001 and direction.dot(from_owner / distance) > 0.0:
			var stretch:float = clampf((distance - leash_soft_limit) / maxf(leash_hard_limit - leash_soft_limit,1.0),0.0,1.0)
			speed_value *= lerpf(1.0,0.38,stretch)
	return speed_value


func _dog_move(_delta:float) -> void:
	var speed_value:float = _current_move_speed()
	if direction.length_squared() > 0.000001:
		set_character_visual_flip_h((direction.x > 0.0) if dir_left else (direction.x <= 0.0))
	velocity = direction * speed_value + Repel
	if velocity.length_squared() <= 0.000001:
		velocity = Vector2.ZERO
		return
	move_and_slide()

	for index:int in range(get_slide_collision_count()):
		var collision:KinematicCollision2D = get_slide_collision(index)
		if collision == null:
			continue
		var collider = collision.get_collider()
		if collider is ball:
			_try_contact_damage(collider as ball,collision.get_position())


func _try_contact_damage(target:ball,impact_position:Vector2) -> void:
	if target == null or target == self or target == owner_human or target.health <= 0:
		return
	if _is_friendly(target):
		return
	var id:int = target.get_instance_id()
	if float(_contact_cooldowns.get(id,0.0)) > 0.0:
		return

	var damage:float = attack_damage(food_run_collision_damage_multiplier)
	var is_bite:bool = mode == DogMode.ORBIT and _bite_target == target and _bite_cooldown_left <= 0.0
	if is_bite:
		if is_player_controlled():
			_bite_target=null
			_manual_bite_window=0.0
		_bite_pose_left = 0.28
		damage = attack_damage(bite_damage_multiplier + _next_bite_bonus_multiplier)
		_next_bite_bonus_multiplier = 0.0
		_bite_cooldown_left = maxf(bite_cooldown,0.1)

	var accepted:bool = target.receive_spatial_damage(
		damage,
		{
			"shape":"contact",
			"blocked_by_body":true,
			"source_position":global_position,
			"point":impact_position,
			"source":owner_human if owner_human != null else self
		},
		false,
		false
	)
	_contact_cooldowns[id] = 0.42 if is_bite else 0.65

	if accepted and contact_knockback_distance > 0.0:
		var push_dir:Vector2 = target.global_position - global_position
		if push_dir.length_squared() <= 0.000001:
			push_dir = direction
		target.apply_knockback(
			push_dir.normalized(),
			contact_knockback_distance,
			contact_knockback_speed,
			0.0,
			0.0,
			{"source":owner_human if owner_human != null else self,"stop_on_character":true}
		)


func _consume_or_pick_food() -> void:
	if food_target == null or not is_instance_valid(food_target):
		mode = DogMode.RETURNING
		return
	if food_target.has_method("mark_claimed") and not bool(food_target.call("mark_claimed")):
		food_target = null
		mode = DogMode.RETURNING
		return

	var kind:int = int(food_target.get("food_type"))
	match kind:
		FOOD_BONE:
			_pick_up_bone()
		FOOD_BIG_MEAT:
			_start_eating(big_meat_eat_time,big_meat_total_heal,0.0,0.0)
		FOOD_SAUSAGE:
			_start_eating(sausage_eat_time,sausage_heal,sausage_speed_buff_time,0.0)
		FOOD_CHEW_STICK:
			_start_eating(chew_stick_eat_time,chew_stick_heal,0.0,chew_stick_next_bite_bonus_multiplier)
		_:
			food_target.queue_free()
			food_target = null
			mode = DogMode.RETURNING


func _pick_up_bone() -> void:
	if food_target != null and is_instance_valid(food_target):
		food_target.queue_free()
	food_target = null
	mode = DogMode.HOLDING_BONE
	_show_carried_bone()
	_eat_serial += 1
	var token:int = _eat_serial
	call_deferred("_hold_bone_then_return",token)


func _hold_bone_then_return(token:int) -> void:
	await get_tree().create_timer(maxf(bone_hold_time,0.05)).timeout
	if not is_instance_valid(self) or token != _eat_serial or _linked_death_started:
		return
	mode = DogMode.RETURNING


func _start_eating(duration:float,total_heal:float,speed_buff_duration:float,next_bite_bonus:float) -> void:
	mode = DogMode.EATING
	direction = Vector2.ZERO
	_eat_serial += 1
	var token:int = _eat_serial
	var food:Node2D = food_target
	food_target = null
	call_deferred(
		"_eat_sequence",
		token,
		food,
		maxf(duration,0.1),
		maxf(total_heal,0.0),
		maxf(speed_buff_duration,0.0),
		maxf(next_bite_bonus,0.0)
	)


func _eat_sequence(token:int,food:Node2D,duration:float,total_heal:float,speed_buff_duration:float,next_bite_bonus:float) -> void:
	var steps:int = maxi(int(ceil(duration / 0.25)),1)
	var heal_each:float = total_heal / float(steps)
	var step_time:float = duration / float(steps)
	for _i:int in range(steps):
		await get_tree().create_timer(step_time).timeout
		if not is_instance_valid(self) or token != _eat_serial or _linked_death_started or health <= 0:
			return
		if heal_each > 0.0:
			heal(heal_each)

	if food != null and is_instance_valid(food):
		food.queue_free()
	if speed_buff_duration > 0.0:
		_speed_buff_left = maxf(_speed_buff_left,speed_buff_duration)
	if next_bite_bonus > 0.0:
		_next_bite_bonus_multiplier = maxf(_next_bite_bonus_multiplier,next_bite_bonus)
	mode = DogMode.RETURNING


func _finish_return_home() -> void:
	mode = DogMode.ORBIT
	_bite_target = null
	_clear_carried_bone()


func _show_carried_bone() -> void:
	_clear_carried_bone()
	var root := Node2D.new()
	root.name = "CarriedBone"
	root.position = Vector2(34.0,-18.0)
	root.z_index = 10
	graphics.add_child(root)
	var sprite := Sprite2D.new()
	sprite.texture = TEX_BONE
	var size:Vector2 = TEX_BONE.get_size()
	var fit:float = 28.0 / maxf(maxf(size.x,size.y),1.0)
	sprite.scale = Vector2(fit,fit)
	sprite.rotation = 0.18
	root.add_child(sprite)
	_carried_bone_visual = root


func _clear_carried_bone() -> void:
	if _carried_bone_visual != null and is_instance_valid(_carried_bone_visual):
		_carried_bone_visual.queue_free()
	_carried_bone_visual = null


func _nearest_real_enemy() -> ball:
	if is_instance_valid(Target_Enemy) and Target_Enemy is ball and _can_target(Target_Enemy as ball):
		return Target_Enemy as ball
	if is_instance_valid(Nearest_Enemy) and Nearest_Enemy is ball and _can_target(Nearest_Enemy as ball):
		return Nearest_Enemy as ball

	var best:ball = null
	var best_distance_sq:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _can_target(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = candidate
	return best


func _can_target(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or target == self or target == owner_human or target.health <= 0:
		return false
	return not _is_friendly(target)


func _is_friendly(target:ball) -> bool:
	if target == null:
		return true
	if Team.is_empty() or target.Team.is_empty():
		return false
	return Team == target.Team and not bool(Game.Game_Settings.get("Have_Team_Damage",false))


func _cleanup_contact_cooldowns(delta:float) -> void:
	var erase_ids:Array[int] = []
	for raw_id:Variant in _contact_cooldowns.keys():
		var id:int = int(raw_id)
		var left:float = maxf(float(_contact_cooldowns[id]) - delta,0.0)
		if left <= 0.0:
			erase_ids.append(id)
		else:
			_contact_cooldowns[id] = left
	for id:int in erase_ids:
		_contact_cooldowns.erase(id)


func force_linked_death() -> void:
	if _linked_death_started:
		return
	_linked_death_started = true
	_eat_serial += 1
	mode = DogMode.EATING
	direction = Vector2.ZERO
	velocity = Vector2.ZERO
	_clear_carried_bone()
	if food_target != null and is_instance_valid(food_target):
		food_target.queue_free()
	food_target = null
	health = 0
	if owner_human != null and is_instance_valid(owner_human) and owner_human.health > 0:
		owner_human.health = 0
	call_deferred("_free_after_linked_death")


func _start_linked_death() -> void:
	force_linked_death()


func _free_after_linked_death() -> void:
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(self):
		Game.free_node(self)
