extends Area2D

# V180：Sans 的“完全闪避”必须让箭把 Sans 当成空气。
# 骷髅箭使用自定义 PhysicsDirectSpaceState2D 射线，不经过公共 hitbox.gd，
# 因此必须在射线层显式触发闪避并把该碰撞体加入本次查询的 exclude。

const WOUND_CONTROLLER_SCRIPT:Script = preload("res://scripts/effects/我的世界/骷髅箭伤控制.gd")
const MC_DAMAGE_SFX:Script = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
const TERRAIN_HIT_SFX = [
	preload("res://audio/characters/骷髅/箭击中1.ogg"),
	preload("res://audio/characters/骷髅/箭击中2.ogg"),
	preload("res://audio/characters/骷髅/箭击中4.ogg"),
]
const BLAZE_ROD_BLOCK_SFX:AudioStream = preload("res://audio/sfx/防御/BlockAtt.ogg")
const NEW6_FX = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")

enum ArrowMode { FLYING, STUCK_TERRAIN, EMBEDDED_ENEMY }

var _mode:ArrowMode = ArrowMode.FLYING
var _source_ref:WeakRef = null
var _source_team:String = ""
var _direction:Vector2 = Vector2.RIGHT
var _speed:float = 520.0
var _normal_speed:float = 520.0
var _direct_damage:float = 8.0
var _pickup_damage:float = 3.0
var _knockback_distance:float = 3.0
var _knockback_speed:float = 90.0
var _terrain_lifetime:float = 5.5
var _terrain_left:float = 0.0
var _configured:bool = false
var _force_no_friendly_fire:bool = false
# 弓箭盔甲架使用“普通箭”模式：只造成一次普通伤害，不插入角色、不进入处决控制器；
# 插墙后也只是视觉残留，触碰没有伤害，等待 terrain_lifetime 后自动消失。
var _plain_arrow_mode:bool = false
var _new6_hit_sfx:bool = false
var _new6_max_dist:float = 0.0
var _new6_travelled:float = 0.0
# Opt-in for the new6 bow only; skeleton/armor-stand arrows keep their old motion.
var _ballistic_enabled:bool = false
var _ballistic_gravity:float = 0.0
var _damage_per_speed:float = 0.0
var _afterimage_speed:float = 0.0
var _afterimage_elapsed:float = 0.0
var _embed_parent_ref:WeakRef
var _embed_target_id:int = 0
var _embed_local_pose:Transform2D
var _embed_root_pose:Transform2D
var _flight_world_scale:Vector2 = Vector2.ONE

@onready var _sensor_shape:CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MinecraftSkeletonArrow")
	body_entered.connect(_on_body_entered)
	if _sensor_shape != null:
		_sensor_shape.disabled = true


func configure(
	source:ball,
	team:String,
	direction:Vector2,
	speed:float,
	direct_damage:float,
	pickup_damage:float,
	knockback_distance:float,
	knockback_speed:float,
	terrain_lifetime:float
) -> void:
	_flight_world_scale = global_scale
	_source_ref = weakref(source) if source != null else null
	_source_team = team
	_direction = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_speed = maxf(speed,1.0)
	_normal_speed = _speed
	_direct_damage = maxf(direct_damage,0.0)
	_pickup_damage = maxf(pickup_damage,0.0)
	_knockback_distance = maxf(knockback_distance,0.0)
	_knockback_speed = maxf(knockback_speed,1.0)
	_terrain_lifetime = maxf(terrain_lifetime,0.25)
	rotation = _direction.angle()
	_plain_arrow_mode = false
	_ballistic_enabled = false
	_afterimage_elapsed = 0.0
	_configured = true


func configure_plain(
	source:ball,
	team:String,
	direction:Vector2,
	speed:float,
	direct_damage:float,
	knockback_distance:float,
	knockback_speed:float,
	terrain_lifetime:float
) -> void:
	configure(
		source,
		team,
		direction,
		speed,
		direct_damage,
		0.0,
		knockback_distance,
		knockback_speed,
		terrain_lifetime
	)
	_plain_arrow_mode = true


func configure_ballistics(gravity:float,damage_per_speed:float,afterimage_speed:float) -> void:
	_ballistic_enabled = true
	_ballistic_gravity = maxf(gravity,0.0)
	_damage_per_speed = maxf(damage_per_speed,0.0)
	_afterimage_speed = maxf(afterimage_speed,1.0)
	_afterimage_elapsed = 0.0
	_direct_damage = _speed * _damage_per_speed


func _physics_process(delta:float) -> void:
	if is_queued_for_deletion():
		return
	if not _ballistic_enabled or _mode != ArrowMode.FLYING:
		_step_flight(delta)
		return
	# Short swept segments follow the parabola without tunnelling at high speed.
	var remaining:float = maxf(delta,0.0)
	while remaining > 0.000001:
		var step:float = minf(remaining,1.0 / 120.0)
		_step_flight(step)
		remaining -= step
		if is_queued_for_deletion() or _mode != ArrowMode.FLYING or not _configured:
			break


func _step_flight(delta:float) -> void:
	if _mode == ArrowMode.STUCK_TERRAIN:
		_terrain_left -= maxf(delta,0.0)
		if _terrain_left <= 0.0:
			queue_free()
		return
	if _mode != ArrowMode.FLYING or not is_multiplayer_authority() or not _configured:
		return
	var dt:float = maxf(delta,0.0)
	var start:Vector2 = global_position
	var initial_velocity:Vector2 = _direction * _speed
	var acceleration:Vector2 = Vector2.DOWN * _ballistic_gravity if _ballistic_enabled else Vector2.ZERO
	var motion:Vector2 = initial_velocity * dt + acceleration * (0.5 * dt * dt)
	var expires:bool = false
	if _new6_max_dist > 0.0:
		var remaining_distance:float = maxf(_new6_max_dist - _new6_travelled,0.0)
		if remaining_distance <= 0.000001:
			queue_free()
			return
		if motion.length() >= remaining_distance:
			# Sweep the final in-range segment before expiring; never hit beyond it.
			var fraction:float = remaining_distance / maxf(motion.length(),0.000001)
			motion *= fraction
			dt *= fraction
			expires = true
	var finish:Vector2 = start + motion
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,start,finish): return
	var hit:Dictionary = _raycast_motion(start,finish)
	var impact:Vector2 = hit.get("position",finish)
	var travelled:float = start.distance_to(impact)
	_new6_travelled += travelled if _new6_max_dist > 0.0 else 0.0
	if _ballistic_enabled:
		var hit_fraction:float = 1.0 if hit.is_empty() else clampf(travelled / maxf(motion.length(),0.000001),0.0,1.0)
		var velocity_now:Vector2 = initial_velocity + acceleration * dt * hit_fraction
		_speed = velocity_now.length()
		if _speed > 0.000001:
			_direction = velocity_now / _speed
			rotation = _direction.angle()
		# Re-evaluate at impact, not just at release: rising loses damage, falling gains it.
		_direct_damage = _speed * _damage_per_speed
	global_position = impact
	if hit.is_empty():
		if _ballistic_enabled:
			_update_afterimage(dt)
		if expires:
			queue_free()
		return
	var collider:Variant = hit.get("collider",null)
	if _is_blaze_rod(collider):
		_block_on_blaze_rod(collider,global_position)
		return
	var target:ball = _resolve_ball_from_collider(collider)
	if target != null and _can_damage_target(target):
		# 烈焰棒现在是骷髅箭的格挡体：命中棒子直接销毁箭，不把伤害传给烈焰人本体。
		if not _plain_arrow_mode: _capture_embed_anchor(target)
		_apply_damage(target,_direct_damage)
		if _plain_arrow_mode:
			# 普通箭只命中一次；不插在敌人身上，因此也永远不会创建 MinecraftArrowWoundController。
			if _new6_hit_sfx:
				var src:ball = _source_ball()
				if src != null:
					NEW6_FX.hit_sfx(src,global_position,_direct_damage)
			_configured = false
			queue_free()
		else:
			_request_embed_in_enemy(target)
		return
	_stick_to_terrain(collider)


func _update_afterimage(delta:float) -> void:
	if _speed < _afterimage_speed:
		_afterimage_elapsed = 0.0
		return
	var source:ball = _source_ball()
	if source != null and not source.allows_character_motion_effects():
		return
	var density:float = source.get_large_battle_visual_density() if source != null else 1.0
	var interval:float = 0.025 / clampf(density,0.15,1.0)
	_afterimage_elapsed += delta
	if _afterimage_elapsed < interval:
		return
	_afterimage_elapsed = fmod(_afterimage_elapsed,interval)
	var sprite:Sprite2D = get_node_or_null("ArrowSprite") as Sprite2D
	var world:Node = get_tree().current_scene
	if sprite == null or world == null:
		return
	var ghost:Sprite2D = Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.texture_filter = sprite.texture_filter
	ghost.centered = sprite.centered
	ghost.offset = sprite.offset
	ghost.modulate = Color(1.0,1.0,1.0,0.42)
	ghost.z_index = z_index - 1
	_runtime_container(world).add_child(ghost)
	ghost.global_transform = sprite.global_transform
	ghost.add_to_group("BattleTransient")
	ghost.add_to_group("BowArrowAfterimage")
	# Bind to the ghost, not the arrow: impact must not cancel cleanup.
	var fade:Tween = ghost.create_tween()
	fade.tween_property(ghost,"modulate:a",0.0,0.16)
	fade.tween_callback(ghost.queue_free)


func _raycast_motion(start:Vector2,finish:Vector2) -> Dictionary:
	var exclude:Array[RID] = []
	var source:ball = _source_ball()
	if source != null and is_instance_valid(source):
		exclude.append(source.get_rid())
	for _pass:int in range(10):
		var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start,finish,3,exclude)
		query.collide_with_areas = true # 可战斗 Creature 没有实体角色碰撞层，箭仍需命中其 Hurtbox。
		query.collide_with_bodies = true
		query.hit_from_inside = true
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider:Variant = hit.get("collider",null)
		if collider is Area2D and not collider is hurtbox:
			exclude.append(collider.get_rid())
			continue
		if _is_blaze_rod(collider):
			return hit
		var owner_ball:ball = _resolve_ball_from_collider(collider)
		if owner_ball != null:
			if not _can_damage_target(owner_ball):
				# 普通友军角色子件仍按友伤规则跳过；烈焰棒已在上方单独作为格挡体处理。
				_append_raycast_exclusion(exclude,collider,owner_ball)
				continue
			# V180：命中 Sans 这类支持“完全投射物闪避”的目标时，
			# 先让目标完成闪避，再把它从“这一支箭的这一段射线”中排除，
			# 继续查询后面的物体。这样箭不会停、不会插身上、也不会改变轨迹。
			if _target_fully_dodged(owner_ball):
				_append_raycast_exclusion(exclude,collider,owner_ball)
				continue
		return hit
	return {}



func _append_raycast_exclusion(exclude:Array[RID],collider:Variant,target:ball) -> void:
	var rid:RID = RID()
	if collider is CollisionObject2D and is_instance_valid(collider):
		rid = (collider as CollisionObject2D).get_rid()
	elif target != null and is_instance_valid(target):
		rid = target.get_rid()
	if is_instance_valid(target):
		if not exclude.has(target.get_rid()): exclude.append(target.get_rid())
		if is_instance_valid(target.self_hurtbox) and not exclude.has(target.self_hurtbox.get_rid()): exclude.append(target.self_hurtbox.get_rid())
	if rid.is_valid() and not exclude.has(rid):
		exclude.append(rid)


func _target_fully_dodged(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("try_full_projectile_dodge"):
		return bool(target.call("try_full_projectile_dodge",self))
	return false


func _is_blaze_rod(collider:Variant) -> bool:
	return collider is Node and is_instance_valid(collider) and (collider as Node).is_in_group("MinecraftBlazeRod")


func _block_on_blaze_rod(collider:Variant,impact_position:Vector2) -> void:
	_configured = false
	var owner_blaze:ball = _resolve_ball_from_collider(collider)
	if owner_blaze != null and is_instance_valid(owner_blaze):
		var seed:int = Game.battle_rng_seed_or("scripts/effects/我的世界/骷髅箭.gd:seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(owner_blaze.get_instance_id()))
		owner_blaze.notify_block_burst_feedback(
			impact_position,
			maxf(_direct_damage,1.0),
			18.0,
			seed
		)
	_play_blaze_rod_block_sfx(impact_position)
	queue_free()


func _play_blaze_rod_block_sfx(at_position:Vector2) -> void:
	if BLAZE_ROD_BLOCK_SFX == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "骷髅箭_烈焰棒格挡_%d" % get_instance_id()
	player.stream = BLAZE_ROD_BLOCK_SFX
	player.volume_db = 1.5
	player.pitch_scale = randf_range(0.97,1.04)
	player.max_distance = 1100.0
	player.attenuation = 0.78
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	var parent:Node = _runtime_container(get_tree().current_scene)
	parent.add_child(player,true)
	player.global_position = at_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _resolve_ball_from_collider(collider:Variant) -> ball:
	if collider is ball and is_instance_valid(collider):
		return collider as ball
	if not collider is Node:
		return null
	var node:Node = collider as Node
	while node != null:
		if node is ball and is_instance_valid(node):
			return node as ball
		node = node.get_parent()
	return null

func _can_damage_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0 or not target.is_combat_targetable():
		return false
	var source:ball = _source_ball()
	if source != null and target == source:
		return false
	if _source_team != "" and target.Team != "" and target.Team == _source_team:
		return false
	return true


func _apply_damage(target:ball,amount:float) -> void:
	if amount <= 0.0 or target == null or not is_instance_valid(target):
		return
	var source:ball = _source_ball()
	var outgoing:float = amount
	if source != null and is_instance_valid(source):
		outgoing = source.effective_outgoing_damage(amount)
	# 小白原版箭需要至少留 1HP 给“插箭阈值”斩杀流程。
	# 弓箭盔甲架的普通箭没有任何处决效果，因此允许这 10 点普通伤害直接击杀。
	if not _plain_arrow_mode:
		var nonlethal_cap:float = maxf(float(target.block),0.0) + maxf(float(target.health) - 1.0,0.0)
		outgoing = minf(outgoing,nonlethal_cap)
	var hit_source:Object = self
	if source != null: hit_source = source
	if outgoing > 0.0:
		var applied:bool = target.receive_positional_damage(outgoing,global_position,false,hit_source)
		# Native MC sources are handled by the victim; foreign adapters retain legacy audio.
		if applied and not preload("res://scripts/effects/我的世界/mc_hit_feedback.gd").manages(hit_source):
			MC_DAMAGE_SFX.play(target,global_position)
	if _knockback_distance > 0.0:
		target.apply_knockback(
			_direction,
			_knockback_distance,
			_knockback_speed,
			0.0,
			0.0,
			{"source":hit_source,"stop_on_character":true}
		)


func _stick_to_terrain(collider:Variant = null) -> void:
	_mode = ArrowMode.STUCK_TERRAIN
	_terrain_left = _terrain_lifetime
	# 小白箭插墙后仍可被角色碰到并转入插箭逻辑；普通箭要求“碰到了没有用”，
	# 因此普通模式保持传感碰撞关闭，只留下墙上的视觉并等待自动消失。
	if _sensor_shape != null and not _plain_arrow_mode:
		_sensor_shape.set_deferred("disabled",false)
	_play_terrain_hit_sfx(global_position)

	# “插墙”也不是钉死世界坐标：如果命中的障碍物会移动/旋转，箭应跟着它。
	# 因此保留当前世界姿态，延迟 reparent 到真实命中对象。
	var attach_id:int = 0
	if collider is Node2D and is_instance_valid(collider):
		attach_id = (collider as Node2D).get_instance_id()
		_embed_local_pose = collider.global_transform.affine_inverse()*global_transform
	if attach_id != 0:
		call_deferred("_complete_stick_to_obstacle",attach_id)


func _complete_stick_to_obstacle(obstacle_id:int) -> void:
	if _mode != ArrowMode.STUCK_TERRAIN or not is_inside_tree():
		return
	var raw_obstacle:Object = instance_from_id(obstacle_id)
	if not raw_obstacle is Node2D or not is_instance_valid(raw_obstacle):
		return
	var obstacle:Node2D = raw_obstacle as Node2D
	if obstacle == self or not obstacle.is_inside_tree():
		return
	name = "骷髅箭_障碍_%d" % get_instance_id()
	reparent(obstacle,false)
	transform = _embed_local_pose


func _play_terrain_hit_sfx(at_position:Vector2) -> void:
	var source:ball = _source_ball()
	if _new6_hit_sfx and source != null and source.has_method("play_arrow_terrain_hit"):
		# The persistent bow owns the RPC; never send RPCs from transient arrows.
		source.call("play_arrow_terrain_hit",at_position)
		return
	if TERRAIN_HIT_SFX.is_empty() or get_tree() == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = TERRAIN_HIT_SFX.pick_random()
	player.add_to_group("MCArrowTerrainSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sound_event","entity.arrow.hit")
	player.volume_db = 1.2
	player.pitch_scale = randf_range(0.97,1.03)
	player.max_distance = 1200.0
	player.attenuation = 0.75
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = at_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _on_body_entered(body:Node2D) -> void:
	if _plain_arrow_mode:
		return
	if _mode != ArrowMode.STUCK_TERRAIN or not is_multiplayer_authority():
		return
	if not body is ball:
		return
	var target:ball = body as ball
	if not _can_damage_target(target):
		return
	# 已经插在地形里的箭也不能因为 Sans 走进来就“粘”到 Sans 身上。
	# 完全闪避时箭保持原状态，目标也不受伤。
	if _target_fully_dodged(target):
		return
	_capture_embed_anchor(target)
	_apply_damage(target,_pickup_damage)
	_request_embed_in_enemy(target)


func _resolve_embed_parent(target:ball) -> Node2D:
	if target.has_method("get_projectile_embed_parent"):
		var requested:Variant = target.call("get_projectile_embed_parent")
		if requested is Node2D and is_instance_valid(requested) and requested.is_inside_tree(): return requested
	var visual:Node2D = target.get_node_or_null("Graphics")
	return visual if is_instance_valid(visual) else target
func _capture_embed_anchor(target:ball) -> void:
	# 必须早于扣血：目标可能在伤害回调中立即/延迟瞬移。
	var anchor:Node2D = _resolve_embed_parent(target)
	_embed_parent_ref = weakref(anchor)
	_embed_target_id = target.get_instance_id()
	_embed_local_pose = anchor.global_transform.affine_inverse()*global_transform
	if target.has_method("get_projectile_embed_local_transform"):
		var mapped:Variant = target.call("get_projectile_embed_local_transform",global_transform)
		if mapped is Transform2D: _embed_local_pose = mapped
	_embed_root_pose = target.global_transform.affine_inverse()*global_transform
func _request_embed_in_enemy(target:Variant) -> void:
	if not is_instance_valid(target) or not target is ball or target.is_queued_for_deletion():
		queue_free()
		return
	# body_entered 正处于 PhysicsServer flush 阶段，不能在信号里直接修改
	# monitoring/monitorable、reparent CollisionObject2D 或移除碰撞对象。
	# 先立刻锁状态阻止二次触发，再把真正的碰撞状态切换与 reparent 延迟执行。
	if _embed_target_id != target.get_instance_id(): _capture_embed_anchor(target)
	_mode = ArrowMode.EMBEDDED_ENEMY
	_configured = false
	set_deferred("monitoring",false)
	set_deferred("monitorable",false)
	if _sensor_shape != null:
		_sensor_shape.set_deferred("disabled",true)
	call_deferred("_complete_embed_in_enemy",target.get_instance_id())


func _complete_embed_in_enemy(target_id:int) -> void:
	if _mode != ArrowMode.EMBEDDED_ENEMY:
		return
	var raw_target:Object = instance_from_id(target_id)
	if not raw_target is ball or not is_instance_valid(raw_target):
		queue_free()
		return
	var target:ball = raw_target as ball
	# 多支箭插在同一目标身上时，reparent() 默认可能把重复名称改成 @Area2D@xxxx。
	# World 根又是 MultiplayerSpawner.spawn_path，之后再飞出会因为这种保留名称触发 auto-spawn 报错。
	# 在第一次插入身体前就给每支箭一个稳定且唯一的可读名称。
	name = "骷髅箭_%d" % get_instance_id()
	var saved_parent:Variant = _embed_parent_ref.get_ref() if _embed_parent_ref != null else null
	var embed_parent:Node2D = saved_parent if is_instance_valid(saved_parent) else target
	reparent(embed_parent,false)
	transform = _embed_local_pose if is_instance_valid(saved_parent) else _embed_root_pose
	z_as_relative = true
	z_index = 1
	var controller:Node = target.get_node_or_null("MinecraftArrowWoundController")
	if controller == null:
		controller = Node.new()
		controller.name = "MinecraftArrowWoundController"
		controller.set_script(WOUND_CONTROLLER_SCRIPT)
		target.add_child(controller)
		if controller.has_method("setup"):
			controller.call("setup",target)
	if controller.has_method("register_arrow"):
		controller.call("register_arrow",self,_source_ball())


func get_flight_direction() -> Vector2:
	if _mode == ArrowMode.EMBEDDED_ENEMY: return global_transform.x.normalized()
	return _direction.normalized() if _direction.length_squared() > 0.000001 else Vector2.RIGHT.rotated(global_rotation)


func launch_execution_flyout(world_direction:Vector2) -> void:
	if not is_inside_tree() or get_tree() == null or get_tree().current_scene == null:
		queue_free()
		return
	var dir:Vector2 = world_direction.normalized()
	if dir.length_squared() <= 0.000001:
		dir = get_flight_direction()

	# 处决箭穿出身体以后，不再进入“只飞一段距离后删除”的特殊模式。
	# 它恢复成完整的普通骷髅箭：使用原射速/原伤害、raycast 命中、可插敌人、可插障碍物。
	_mode = ArrowMode.FLYING
	_direction = dir
	_speed = maxf(_normal_speed,1.0)
	_configured = true
	_force_no_friendly_fire = true
	rotation = dir.angle()
	monitoring = true
	monitorable = true
	if _sensor_shape != null:
		_sensor_shape.disabled = true

	# World 根节点是 MultiplayerSpawner.spawn_path。处决时如果把箭直接 reparent 回 World，
	# Spawner 会把它当成一次新的自动出生；旧版箭名又可能是 @Area2D@xxxx，于是产生
	# “Unable to auto-spawn node with reserved name” 报错。改放入项目既有的二级运行时容器，
	# 仍然处于世界坐标系、仍可进行物理查询，但不再二次触发 MultiplayerSpawner。
	var world:Node = get_tree().current_scene
	var runtime_parent:Node = _runtime_container(world)
	name = "骷髅箭_%d" % get_instance_id()
	reparent(runtime_parent,true)
	global_rotation = dir.angle()
	global_scale = _flight_world_scale
	_embed_target_id = 0
	_embed_parent_ref = null
	z_index = 12


func _runtime_container(world:Node) -> Node:
	if world == null:
		return self
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func _source_ball() -> ball:
	if _source_ref == null:
		return null
	var raw:Variant = _source_ref.get_ref()
	return raw as ball if raw is ball and is_instance_valid(raw) else null
