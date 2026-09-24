extends Node

const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const POTION_PARTICLE = preload("res://scripts/effects/我的世界/女巫药水粒子.gd")
const DAMAGE_SFX = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")

const INVISIBILITY_CONTACT_DAMAGE:float = 2.0
const INVISIBILITY_CONTACT_INTERVAL:float = 0.05
const INVISIBILITY_CONTACT_AREA_MULTIPLIER:float = 1.06
const IGNORE_LOCKING_META:StringName = &"ignore_combat_locking"
const IGNORE_BODY_COLLISION_META:StringName = &"mc_ignore_character_body_collision"

var target:ball = null
var source:Node = null
var effect_type:String = ""
var level:int = 1
var remaining:float = INF
var applications:Dictionary = {} # source ID -> independent level + remaining
var tick_interval:float = 1.0
var tick_left:float = 1.0
var absorption_remaining:float = 0.0
var invis_alpha:float = 0.22
var particle_color:Color = Color.WHITE
var particle_interval:float = 0.18
var _particle_left:float = 0.0

var _saved_collision_layer:int = 0
var _saved_collision_mask:int = 0
var _saved_alpha:float = 1.0
var _invisibility_applied:bool = false
var _saved_ignore_locking_had_meta:bool = false
var _saved_ignore_locking_value:bool = false
var _saved_ignore_body_had_meta:bool = false
var _saved_ignore_body_value:bool = false
var _invisibility_contact_area:Area2D = null
var _invisibility_contact_shape:CollisionShape2D = null
var _invisibility_contact_left:float = 0.0
var _invisibility_lock_clear_left:float = 0.0
var _cleaned:bool = false
var _death_triggered:bool = false


func setup(
	new_target:ball,
	new_effect_type:String,
	duration:float,
	new_source:Node = null,
	options:Dictionary = {},
	new_level:int = 1
) -> void:
	target = new_target
	effect_type = new_effect_type
	level = maxi(new_level,1)
	remaining = duration
	source = new_source
	EFFECTS.remember_source(applications,new_source,level,duration)
	var p:Dictionary = EFFECTS.properties(effect_type,level)
	absorption_remaining = float(p.get("absorption",0.0)) * _potion_effect_ratio(true)
	tick_interval = float(p.get("period_ticks",20)) / 20.0
	invis_alpha = clampf(float(options.get("invis_alpha",invis_alpha)),0.02,1.0)
	_apply_particle_options(options)
	tick_left = tick_interval
	_particle_left = 0.0

	if effect_type == "invisibility":
		_apply_invisibility()
	EFFECTS.apply_runtime_buffs(target,self,effect_type,level)
	if effect_type in ["infested","oozing","weaving","wind_charged"] and target.health_bar != null:
		target.health_bar.health_changed.connect(_on_health_changed)


func refresh(duration:float,new_source:Node = null,options:Dictionary = {},new_level:int = 1) -> void:
	EFFECTS.remember_source(applications,new_source,new_level,duration)
	_choose_application()
	if options.has("invis_alpha"):
		invis_alpha = minf(invis_alpha,clampf(float(options["invis_alpha"]),0.02,1.0))
	_apply_particle_options(options)
	if effect_type == "invisibility":
		_apply_invisibility()
	EFFECTS.apply_runtime_buffs(target,self,effect_type,level)


func remove_source(caster:Node) -> void:
	EFFECTS.forget_source(applications,caster)
	_choose_application()
	if remaining > 0.0: EFFECTS.apply_runtime_buffs(target,self,effect_type,level)


func _choose_application() -> void:
	var best:Dictionary = EFFECTS.strongest_source(applications)
	if best.is_empty():
		remaining = 0.0
		queue_free()
		return
	var old_level:int = level
	level = int(best.grade)
	remaining = float(best.time)
	var ref:WeakRef = best.source_ref as WeakRef
	var caster:Variant = ref.get_ref() if ref != null else null
	source = caster as Node if is_instance_valid(caster) and caster is Node else null
	if level != old_level:
		var old_cap:float = float(EFFECTS.properties(effect_type,old_level).get("absorption",0.0)) * _potion_effect_ratio(true)
		var cap:float = float(EFFECTS.properties(effect_type,level).get("absorption",0.0)) * _potion_effect_ratio(true)
		absorption_remaining = minf(cap,absorption_remaining+maxf(cap-old_cap,0.0))
		tick_interval = float(EFFECTS.properties(effect_type,level).get("period_ticks",20))/20.0
		tick_left = tick_interval


func consume_absorption(amount:float) -> float:
	var used:float = minf(maxf(amount,0.0),absorption_remaining)
	absorption_remaining -= used
	return maxf(amount - used,0.0)


func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		queue_free()
		return
	if target.health <= 0:
		if effect_type in ["oozing","weaving","wind_charged"]: _on_owner_death()
		queue_free()
		return
	if _potion_effect_ratio(EFFECTS.positive(effect_type)) <= 0.000001:
		remaining = 0.0
		queue_free()
		return

	_update_status_particles(delta)

	if effect_type == "invisibility":
		_maintain_invisibility()
		# 只跳过角色身体碰撞；独立 Hitbox/Hurtbox 仍照常攻击、受伤。
		# 每物理帧清掉已有 AI 锁定，不增加额外接触伤害。
		_clear_existing_enemy_locks()
	if effect_type == "slow_falling" and target.velocity.y > 40.0:
		# 0.125 block/tick terminal velocity, converted at 16 px per block.
		target.velocity.y = 40.0

	if effect_type == "regen" or effect_type == "poison":
		tick_left -= minf(delta,remaining) if not is_inf(remaining) else delta
		while tick_left <= 0.000001:
			tick_left += tick_interval
			_tick_periodic_health_effect()
			if target == null or not is_instance_valid(target) or target.health <= 0:
				break

	EFFECTS.elapse_sources(applications,delta)
	_choose_application()
	if remaining <= 0.0: return
	EFFECTS.apply_runtime_buffs(target,self,effect_type,level)


func _on_health_changed(before:int,after:int,_max_health:int,_tween:bool) -> void:
	if after >= before or not is_instance_valid(target) or not target.is_multiplayer_authority(): return
	if effect_type == "infested" and randf() < float(EFFECTS.properties(effect_type,level).on_hurt_chance):
		_spawn_mobs("res://scenes/characters/我的世界/蠹虫.tscn",randi_range(1,2))
	if after <= 0 and effect_type in ["oozing","weaving","wind_charged"]: _on_owner_death()

func _on_owner_death() -> void:
	if _death_triggered or not is_instance_valid(target) or not target.is_multiplayer_authority(): return
	_death_triggered = true
	var world:Node = target.get_tree().current_scene if target.get_tree() != null else null
	if world == null: return
	match effect_type:
		"oozing":
			# The optional New5 slime scene belongs to another uncommitted update.
			# Never fail a clean checkout without that independent resource.
			var slime_path:String = "res://scenes/creatures/我的世界/史莱姆_小.tscn"
			if ResourceLoader.exists(slime_path): _spawn_mobs(slime_path,2)
		"weaving":
			var web_script:GDScript = load("res://scripts/effects/我的世界/mc_weaving_web.gd") as GDScript
			for i:int in range(3):
				var web:Area2D = web_script.new() as Area2D
				world.add_child(web,true)
				web.global_position = target.global_position + Vector2.from_angle(float(i)*TAU/3.0)*12.0
		"wind_charged":
			for node:Node in target.get_tree().get_nodes_in_group("Ball"):
				if not node is ball or node == target: continue
				var other:ball = node as ball
				if other.health <= 0 or other.global_position.distance_to(target.global_position) > 80.0: continue
				var heading:Vector2 = target.global_position.direction_to(other.global_position)
				if heading == Vector2.ZERO: heading = Vector2.UP
				other.apply_knockback(heading,72.0,450.0,0.0,0.0,{"source":source})

func _spawn_mobs(scene_path:String,count:int) -> void:
	if not is_instance_valid(target) or target.get_tree() == null: return
	var world:Node = target.get_tree().current_scene
	if world == null: return
	var scene:PackedScene = load(scene_path) as PackedScene
	if scene == null: return
	for i:int in range(count):
		var mob:ball = scene.instantiate() as ball
		if mob == null: continue
		mob.name = "MC状态召唤_%d_%d" % [target.get_instance_id(),i]
		var caster:ball = source as ball if is_instance_valid(source) and source is ball else null
		mob.Team = caster.Team if caster != null else target.Team
		mob.Master = caster
		world.add_child(mob,true)
		mob.global_position = target.global_position + Vector2(randf_range(-12.0,12.0),randf_range(-12.0,12.0))
		mob.add_to_group("BattleTransient")
		mob.add_to_group("MCStatusSpawn")


func _apply_particle_options(options:Dictionary) -> void:
	var color_value:Variant = options.get("particle_color",particle_color)
	if color_value is Color:
		particle_color = color_value
	particle_interval = clampf(float(options.get("particle_interval",particle_interval)),0.06,0.8)


func _update_status_particles(delta:float) -> void:
	_particle_left -= delta
	while _particle_left <= 0.0:
		_particle_left += particle_interval
		_spawn_status_particle()


func _spawn_status_particle() -> void:
	if target == null or not is_instance_valid(target):
		return
	var world:Node = target.get_tree().current_scene
	if world == null:
		return
	# 粒子从角色身体/头部附近生成，然后使用世界坐标独立向上飘，
	# 角色继续移动时已经生成的粒子不会被硬拖着走。
	var spawn_position:Vector2 = target.global_position + Vector2(
		randf_range(-13.0,13.0),
		randf_range(-18.0,8.0)
	)
	var particle:Sprite2D = POTION_PARTICLE.new()
	world.add_child(particle)
	particle.call(
		"setup",
		spawn_position,
		particle_color,
		Vector2(randf_range(-7.0,7.0),randf_range(-48.0,-34.0)),
		randf_range(0.020,0.030),
		randf_range(0.060,0.072),
		82
	)


func _tick_periodic_health_effect() -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0 or not target.is_multiplayer_authority():
		return

	var positive:bool = effect_type == "regen"
	var effect_ratio:float = _potion_effect_ratio(positive)
	if effect_ratio <= 0.000001:
		# 运行时把倍率改成 0 时，已有药水状态也立刻失效。
		queue_free()
		return

	var inverted:bool = _healing_damage_inverted()
	if effect_type == "regen":
		var amount:float = float(EFFECTS.properties(effect_type,level).health_per_tick) * effect_ratio
		if inverted:
			_apply_periodic_raw_damage(amount,false)
		else:
			target.heal(amount)
		return

	if effect_type == "poison":
		var amount:float = -float(EFFECTS.properties(effect_type,level).health_per_tick) * effect_ratio
		if inverted:
			target.heal(amount)
		else:
			# 非反转中毒仍保留原规则：最多压到 1 HP，不成为最终击杀来源。
			_apply_periodic_raw_damage(amount,true)
		return

func _apply_periodic_raw_damage(amount:float,leave_one_hp:bool) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	var damage:float = maxf(amount,0.0)
	if leave_one_hp:
		damage = minf(damage,maxf(float(target.health - 1),0.0))
	if damage <= 0.0:
		return
	var context:Dictionary = {
		"point": target.global_position,
		"shape": "all",
	}
	if is_instance_valid(source):
		context["source"] = source
	var damage_applied:bool = target.receive_spatial_raw_health_damage(damage,context)
	if damage_applied:
		DAMAGE_SFX.play(target,target.global_position)


func _potion_effect_ratio(positive:bool) -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	if target.has_method("get_minecraft_potion_effect_ratio"):
		return maxf(float(target.call("get_minecraft_potion_effect_ratio",positive)),0.0)
	return 1.0


func _healing_damage_inverted() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_minecraft_potion_healing_damage_inverted"):
		return bool(target.call("is_minecraft_potion_healing_damage_inverted"))
	return false


func _apply_invisibility() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not _invisibility_applied:
		_saved_collision_layer = target.collision_layer
		# 大规模模式本来就会临时关闭 mask 2；记录场景原始设置，
		# 这样即使在大规模模式中获得隐身，普通模式恢复后也能正确还原。
		_saved_collision_mask = target._large_battle_original_collision_mask if target.is_large_battle_performance_mode() else target.collision_mask
		_saved_ignore_locking_had_meta = target.has_meta(IGNORE_LOCKING_META)
		if _saved_ignore_locking_had_meta:
			_saved_ignore_locking_value = bool(target.get_meta(IGNORE_LOCKING_META))
		_saved_ignore_body_had_meta = target.has_meta(IGNORE_BODY_COLLISION_META)
		if _saved_ignore_body_had_meta:
			_saved_ignore_body_value = bool(target.get_meta(IGNORE_BODY_COLLISION_META))
		var graphics:CanvasItem = target.get_node_or_null("Graphics") as CanvasItem
		if graphics != null:
			_saved_alpha = graphics.modulate.a
		_invisibility_applied = true
		_clear_existing_enemy_locks()
	_maintain_invisibility()


func _maintain_invisibility() -> void:
	if target == null or not is_instance_valid(target):
		return
	# 只关闭 CharacterBody2D 的第 2 层（角色身体）双向扫描；第 1 层地图墙、
	# self_hitbox/self_hurtbox 的 Area2D 层和伤害规则均保持不变。
	if target.get_collision_layer_value(2): target.set_collision_layer_value(2,false)
	if target.get_collision_mask_value(2): target.set_collision_mask_value(2,false)
	target.set_meta(IGNORE_BODY_COLLISION_META,true)
	target.set_crowd_separation_velocity(Vector2.ZERO)
	# 索敌锁定仍独立于能否被伤害命中。
	target.set_meta(IGNORE_LOCKING_META,true)
	var graphics:CanvasItem = target.get_node_or_null("Graphics") as CanvasItem
	if graphics != null:
		var c:Color = graphics.modulate
		c.a = minf(c.a,invis_alpha)
		graphics.modulate = c


func _setup_invisibility_contact_area() -> void:
	if target == null or not is_instance_valid(target):
		return
	if _invisibility_contact_area != null and is_instance_valid(_invisibility_contact_area):
		return

	_invisibility_contact_area = Area2D.new()
	_invisibility_contact_area.name = "WitchInvisibilityContactDamageArea"
	_invisibility_contact_area.collision_layer = 0
	_invisibility_contact_area.collision_mask = 2
	_invisibility_contact_area.monitoring = true
	_invisibility_contact_area.monitorable = false
	target.add_child(_invisibility_contact_area)

	_invisibility_contact_shape = CollisionShape2D.new()
	_invisibility_contact_shape.name = "CollisionShape2D"
	_invisibility_contact_area.add_child(_invisibility_contact_shape)
	_sync_invisibility_contact_shape()
	_invisibility_contact_left = 0.0
	_invisibility_lock_clear_left = 0.0


func _sync_invisibility_contact_shape() -> void:
	if target == null or not is_instance_valid(target):
		return
	if _invisibility_contact_shape == null or not is_instance_valid(_invisibility_contact_shape):
		return
	var source_shape:CollisionShape2D = target.collision_shape_2d
	if source_shape == null or not is_instance_valid(source_shape) or source_shape.shape == null:
		var fallback:=CircleShape2D.new()
		fallback.radius = 16.0 * INVISIBILITY_CONTACT_AREA_MULTIPLIER
		_invisibility_contact_shape.shape = fallback
		_invisibility_contact_shape.position = Vector2.ZERO
		return

	_invisibility_contact_shape.position = source_shape.position
	_invisibility_contact_shape.rotation = source_shape.rotation
	_invisibility_contact_shape.scale = source_shape.scale
	if source_shape.shape is RectangleShape2D:
		var source_rect:RectangleShape2D = source_shape.shape as RectangleShape2D
		var rect:=RectangleShape2D.new()
		rect.size = source_rect.size * INVISIBILITY_CONTACT_AREA_MULTIPLIER
		_invisibility_contact_shape.shape = rect
	elif source_shape.shape is CircleShape2D:
		var source_circle:CircleShape2D = source_shape.shape as CircleShape2D
		var circle:=CircleShape2D.new()
		circle.radius = source_circle.radius * INVISIBILITY_CONTACT_AREA_MULTIPLIER
		_invisibility_contact_shape.shape = circle
	else:
		# 其它自定义 Shape2D 沿用原 Shape，避免因为未知形状擅自改写角色碰撞结构。
		_invisibility_contact_shape.shape = source_shape.shape


func _update_invisibility_contact_damage(delta:float) -> void:
	if _invisibility_contact_area == null or not is_instance_valid(_invisibility_contact_area):
		_setup_invisibility_contact_area()
		if _invisibility_contact_area == null:
			return
	_invisibility_contact_left -= delta
	if _invisibility_contact_left > 0.0:
		return
	_invisibility_contact_left += INVISIBILITY_CONTACT_INTERVAL
	_damage_invisibility_contact_enemies()


func _damage_invisibility_contact_enemies() -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	if _invisibility_contact_area == null or not is_instance_valid(_invisibility_contact_area):
		return
	var hit_ids:Dictionary = {}
	for area:Area2D in _invisibility_contact_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var target_node:Node = area.get_parent()
		if not target_node is ball:
			target_node = area.owner
		if not target_node is ball:
			continue
		var enemy:ball = target_node as ball
		if not _is_invisibility_contact_enemy(enemy):
			continue
		var enemy_id:int = enemy.get_instance_id()
		if hit_ids.has(enemy_id):
			continue
		hit_ids[enemy_id] = true

		var before_health:float = float(enemy.health)
		var before_block:float = float(enemy.block)
		enemy.receive_positional_damage(
			INVISIBILITY_CONTACT_DAMAGE,
			enemy.global_position,
			false,
			target
		)
		var health_loss:float = maxf(before_health - float(enemy.health),0.0)
		var block_loss:float = maxf(before_block - float(enemy.block),0.0)
		if health_loss > 0.0 or block_loss > 0.0:
			DAMAGE_SFX.play(enemy,enemy.global_position)


func _is_invisibility_contact_enemy(candidate:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if candidate == null or not is_instance_valid(candidate) or candidate == target:
		return false
	if candidate.health <= 0 or candidate.is_queued_for_deletion():
		return false
	if candidate.Type == ball.Ball_Type.Creature:
		if not candidate.is_combat_targetable():
			return false
	elif candidate.Type != ball.Ball_Type.Ball:
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and not target.Team.is_empty()
		and candidate.Team == target.Team
	):
		return false
	return true


func _clear_existing_enemy_locks() -> void:
	if target == null or not is_instance_valid(target):
		return
	var tree:SceneTree = target.get_tree()
	if tree == null:
		return
	for node:Node in tree.get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var observer:ball = node as ball
		if observer == target or not is_instance_valid(observer):
			continue
		if (
			not Game.Game_Settings.Have_Team_Damage
			and not target.Team.is_empty()
			and observer.Team == target.Team
		):
			continue
		if observer.Target_Enemy == target:
			observer.Target_Enemy = null
		if observer.Nearest_Enemy == target:
			observer.Nearest_Enemy = null


func _cleanup() -> void:
	if _cleaned:
		return
	_cleaned = true
	if _invisibility_contact_area != null and is_instance_valid(_invisibility_contact_area):
		_invisibility_contact_area.queue_free()
	_invisibility_contact_area = null
	_invisibility_contact_shape = null
	if target == null or not is_instance_valid(target):
		return
	# Buffs are indexed by THIS single status, not by the Witch, beacon or
	# target. Cancel/expiry removes exactly its own strength/speed/etc.
	target.Buff_Dic.erase(get_instance_id())
	if effect_type == "invisibility" and _invisibility_applied:
		if _saved_ignore_body_had_meta:
			target.set_meta(IGNORE_BODY_COLLISION_META,_saved_ignore_body_value)
		else:
			target.remove_meta(IGNORE_BODY_COLLISION_META)
		# 只还原本状态关闭的身体位，不覆盖别的技能对其他层的修改。
		# 死亡时身体已经由角色自身关闭，不能在清理状态时重新开启。
		if target.health > 0 and not target.is_queued_for_deletion():
			target.set_collision_layer_value(2,(_saved_collision_layer & 2) != 0)
			if not target.is_large_battle_performance_mode():
				target.set_collision_mask_value(2,(_saved_collision_mask & 2) != 0)
		if _saved_ignore_locking_had_meta:
			target.set_meta(IGNORE_LOCKING_META,_saved_ignore_locking_value)
		else:
			target.remove_meta(IGNORE_LOCKING_META)
		var graphics:CanvasItem = target.get_node_or_null("Graphics") as CanvasItem
		if graphics != null:
			var c:Color = graphics.modulate
			c.a = _saved_alpha
			graphics.modulate = c


func _exit_tree() -> void:
	_cleanup()
