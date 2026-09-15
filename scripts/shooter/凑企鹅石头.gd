extends CharacterBody2D

const COLLISION_AUDIO:AudioStream = preload("res://audio/sfx/physics/balls_hit1.sfxr")

@export var Master:ball
@export var Master_name:String = ""
@export var Team:String = ""
@export_range(10.0,1500.0,10.0) var travel_speed:float = 320.0
@export_range(0.0,1440.0,10.0) var spin_degrees_per_second:float = 720.0
# 飞行中正面砸中：角色的高伤攻击。
@export_range(1.0,500.0,1.0) var impact_damage:float = 86.0
# 落地后别人撞到石头：只有普通、偏低的碰撞伤害。
@export_range(0.0,100.0,1.0) var ground_contact_damage:float = 18.0
@export_range(0.0,200.0,1.0) var knockback_distance:float = 72.0
@export_range(0.0,200.0,1.0) var ground_knockback_distance:float = 0.0
@export_range(50.0,1800.0,10.0) var knockback_speed:float = 520.0
@export_range(0.0,2.0,0.05) var pickup_delay:float = 0.18

var direction:Vector2 = Vector2.RIGHT
var flying:bool = true
var _grounded_for:float = 0.0
var _ground_contact_tick:float = 0.0
var _recent_damage:Dictionary = {}
var _owned_audio_players:Array[AudioStreamPlayer] = []

@onready var rock_sprite:Sprite2D = $Sprite2D
@onready var damage_area:Area2D = $DamageArea


func _ready() -> void:
	add_to_group("CouPenguinRock")
	# V286：飞行石头也是投射物，加入统一 BattleTransient，
	# 使菊花茶定向重力能改变它的 direction/travel_speed；落地后速度为0，不会继续被拖。
	add_to_group("BattleTransient")
	if direction.length_squared() <= 0.000001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	if is_instance_valid(Master):
		add_collision_exception_with(Master)
		# 主人需要能穿过自己的石头才能进入拾取 Area；碰撞例外双向设置。
		if Master is PhysicsBody2D:
			(Master as PhysicsBody2D).add_collision_exception_with(self)
	if damage_area != null:
		damage_area.body_entered.connect(_on_damage_area_body_entered)
		# 飞行阶段由 CharacterBody2D 的真实实体碰撞造成高伤；
		# 地面 DamageArea 只有落地后才启用。
		damage_area.monitoring = false
	_refresh_threat_debug_meta()


func _physics_process(delta:float) -> void:
	# 唯一石头属于当前凑企鹅本人：主人死亡、被同化删除或离场时一起消失。
	# 不留下孤立的地面石头，也不会继续保留碰撞/伤害区域。
	if not _owner_can_make_sound():
		_stop_owned_audio()
		queue_free()
		return

	_cleanup_damage_cooldowns()
	if flying:
		if rock_sprite != null:
			rock_sprite.rotation += deg_to_rad(spin_degrees_per_second) * delta
		velocity = direction * travel_speed
		var collision:KinematicCollision2D = move_and_collide(velocity * delta)
		if collision != null:
			var collider:Variant = collision.get_collider()
			_land(collider)
	else:
		velocity = Vector2.ZERO
		_grounded_for += delta
		_ground_contact_tick += delta
		if _ground_contact_tick >= 0.08:
			_ground_contact_tick = 0.0
			_process_ground_overlaps()


func _land(collider:Variant) -> void:
	if not flying:
		return
	flying = false
	remove_from_group("BattleTransient")
	velocity = Vector2.ZERO
	if damage_area != null and is_instance_valid(damage_area):
		damage_area.set_deferred("monitoring",true)
	_refresh_threat_debug_meta()
	if is_instance_valid(collider) and collider is ball:
		_try_damage_character(collider as ball,true)
	else:
		# 撞墙/地图实体同样是普通碰撞伤害声音。
		_play_collision_hit_sound()


func _refresh_threat_debug_meta() -> void:
	# 标准化真实伤害几何：
	# - 飞行：根 CharacterBody2D 碰撞圈 = impact_damage
	# - 落地：根碰撞圈只是实体碰撞（绿色），DamageArea = ground_contact_damage
	set_meta("threat_debug_damage",impact_damage if flying else 0.0)
	if damage_area != null and is_instance_valid(damage_area):
		damage_area.set_meta("threat_debug_damage",0.0 if flying else ground_contact_damage)


func _process_ground_overlaps() -> void:
	if flying or damage_area == null or _grounded_for < pickup_delay:
		return
	for body:Node2D in damage_area.get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if is_instance_valid(Master) and body == Master and body.has_method("pickup_penguin_rock"):
			body.call("pickup_penguin_rock", self)
			return
		if body is ball:
			_try_damage_character(body as ball,false)


func _on_damage_area_body_entered(body:Node2D) -> void:
	if flying or _grounded_for < pickup_delay:
		return
	if not is_instance_valid(body):
		return

	# 唯一石头由原凑企鹅本人捡回。捡起后立刻恢复手持石头和攻击能力。
	if is_instance_valid(Master) and body == Master and body.has_method("pickup_penguin_rock"):
		body.call("pickup_penguin_rock", self)
		return

	if body is ball:
		_try_damage_character(body as ball,false)


func _try_damage_character(target:ball,direct_throw:bool) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	if is_instance_valid(Master) and target == Master:
		return
	if not bool(Game.Game_Settings.get("Have_Team_Damage", false)):
		if not Team.is_empty() and not target.Team.is_empty() and target.Team == Team:
			return

	var id:int = target.get_instance_id()
	var now:int = Time.get_ticks_msec()
	if int(_recent_damage.get(id, 0)) > now:
		return
	_recent_damage[id] = now + 350

	var push:Vector2 = target.global_position - global_position
	if push.length_squared() <= 0.000001:
		push = direction
	if push.length_squared() <= 0.000001:
		push = Vector2.RIGHT
	push = push.normalized()

	var damage_amount:float = impact_damage if direct_throw else ground_contact_damage
	# V179：飞行中的石头被 Sans 闪避时什么都不发生在石头上：继续飞，不播命中声、不击退。
	if direct_throw and target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)):
		_recent_damage.erase(id)
		return
	# 只有仍在飞行中的石头属于可被盾牌格挡的投射物；已经落地的接触伤害不是“飞行投射物”。
	if direct_throw and target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,damage_amount)):
		_land(target)
		return
	# 地面石头只有接触伤害，绝不产生击退；只有“飞行中的直接命中”才击退。
	var push_distance:float = knockback_distance if direct_throw else 0.0
	var accepted_damage:bool = false
	if damage_amount > 0.0:
		accepted_damage = target.receive_spatial_damage(
			damage_amount,
			{"point": global_position, "source": self},
			false,
			false
		)
		if accepted_damage:
			_play_collision_hit_sound()

	if accepted_damage and push_distance > 0.0 and is_instance_valid(target) and target.health > 0:
		target.apply_knockback(
			push,
			push_distance,
			knockback_speed,
			0.0,
			0.0,
			{"source": self, "stop_on_character": true}
		)


func _play_collision_hit_sound() -> void:
	# 撞人/撞墙/别人踩到地上的石头都复用普通碰撞伤害音。
	# 但主人死亡或被同化删除后，石头不再继续发出属于凑企鹅的声音。
	if not _owner_can_make_sound():
		return
	if multiplayer.has_multiplayer_peer():
		if is_multiplayer_authority():
			_remote_play_collision_sound.rpc()
	else:
		_play_collision_sound_local()


@rpc("authority","call_local","unreliable")
func _remote_play_collision_sound() -> void:
	_play_collision_sound_local()


func _play_collision_sound_local() -> void:
	if COLLISION_AUDIO == null or not _owner_can_make_sound():
		return
	var player:AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = COLLISION_AUDIO
	player.volume_db = -4.0
	player.pitch_scale = randf_range(0.94,1.06)
	player.name = "CouPenguinRockHit"
	add_child(player)
	_owned_audio_players.append(player)
	player.finished.connect(func() -> void:
		_owned_audio_players.erase(player)
		if is_instance_valid(player):
			player.queue_free()
	)
	player.play()


func _owner_can_make_sound() -> bool:
	if Master == null or not is_instance_valid(Master):
		return false
	if Master.health <= 0 or Master.is_queued_for_deletion():
		return false
	if Master.state_machine != null and Master.state_machine.current_state == ball.State.Die:
		return false
	return true


func _stop_owned_audio() -> void:
	for player:AudioStreamPlayer in _owned_audio_players.duplicate():
		if player != null and is_instance_valid(player):
			player.stop()
			player.queue_free()
	_owned_audio_players.clear()


func _cleanup_damage_cooldowns() -> void:
	if _recent_damage.is_empty():
		return
	var now:int = Time.get_ticks_msec()
	var expired:Array[int] = []
	for raw_id:Variant in _recent_damage.keys():
		var id:int = int(raw_id)
		if int(_recent_damage.get(id, 0)) <= now:
			expired.append(id)
	for id:int in expired:
		_recent_damage.erase(id)
