extends ball

const NON_EXISTENT_TEXTURE:Texture2D = preload("res://Images/characters/meme/棍母/棍母全身.png")

@export_category("棍母 / non-existent")
@export_range(0.05,1.0,0.01) var contact_damage_interval:float = 0.05
@export_range(0.0,10.0,0.05) var contact_damage_multiplier:float = 1.0
@export_range(0.8,1.5,0.01) var contact_area_multiplier:float = 1.06

@onready var contact_damage_area:Area2D = $ContactDamageArea
@onready var contact_damage_shape:CollisionShape2D = $ContactDamageArea/CollisionShape2D

var _contact_damage_left:float = 0.0


func _ready() -> void:
	# 本体只和 layer 1 的地形发生实体碰撞。
	# 自己的 CharacterBody2D 不放在角色 layer 2，因此别的角色也不会被它实体阻挡。
	collision_layer = 0
	collision_mask = 1
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	side_status_ui_enabled = false

	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = NON_EXISTENT_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = true
		sprite.self_modulate = Color.WHITE

	super._ready()

	# V49：CharacterAutoFit 子节点的 _ready() 会早于角色根节点 _ready()。
	# 场景已直接挂正式棍母图片，这里再重跑一次作为保险，让运行时尺寸与放置预览一致。
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_fit"):
		auto_fit.call("apply_fit")

	if health_bar != null:
		health_bar.visible = false

	contact_damage_area.collision_layer = 0
	contact_damage_area.collision_mask = 2
	contact_damage_area.monitoring = true
	contact_damage_area.monitorable = false
	contact_damage_area.set_meta("threat_debug_damage",attack_damage(contact_damage_multiplier))
	_sync_contact_shape_to_body()
	_update_non_existent_alpha()


func get_preview_texture() -> Texture2D:
	return NON_EXISTENT_TEXTURE


func _process(_delta:float) -> void:
	_update_non_existent_alpha()


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not is_multiplayer_authority():
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	if not is_combat_runtime_active():
		return

	_contact_damage_left -= delta
	if _contact_damage_left <= 0.0:
		_contact_damage_left += maxf(contact_damage_interval,0.05)
		_damage_contact_enemies()


func _sync_contact_shape_to_body() -> void:
	if contact_damage_shape == null or collision_shape_2d == null:
		return
	if collision_shape_2d.shape == null:
		return

	if collision_shape_2d.shape is RectangleShape2D:
		var source := collision_shape_2d.shape as RectangleShape2D
		var rect := RectangleShape2D.new()
		rect.size = source.size * maxf(contact_area_multiplier,0.1)
		contact_damage_shape.shape = rect
		contact_damage_shape.position = collision_shape_2d.position
	elif collision_shape_2d.shape is CircleShape2D:
		var source_circle := collision_shape_2d.shape as CircleShape2D
		var circle := CircleShape2D.new()
		circle.radius = source_circle.radius * maxf(contact_area_multiplier,0.1)
		contact_damage_shape.shape = circle
		contact_damage_shape.position = collision_shape_2d.position


func _damage_contact_enemies() -> void:
	var outgoing:float = attack_damage(contact_damage_multiplier)
	if outgoing <= 0.0:
		return
	var hit_ids:Dictionary = {}
	for area:Area2D in contact_damage_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var target_node:Node = area.get_parent()
		if not target_node is ball:
			target_node = area.owner
		if not target_node is ball:
			continue
		var target:ball = target_node as ball
		if not _is_non_existent_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		if hit_ids.has(target_id):
			continue
		hit_ids[target_id] = true

		var before_health:float = float(target.health)
		var before_block:float = float(target.block)
		var hit_point:Vector2 = target.global_position
		target.receive_positional_damage(outgoing,hit_point,false,self)
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		if health_loss > 0.0 or block_loss > 0.0:
			var seed:int = Game.battle_rng_seed_or("scripts/characters/meme/棍母.gd:seed",int(Time.get_ticks_usec()) ^ target_id ^ get_instance_id())
			target.notify_hit_burst_feedback(
				hit_point,
				outgoing,
				health_loss,
				block_loss,
				30.0,
				seed,
				(target.global_position - global_position).normalized()
			)
			_play_non_existent_hit_sfx(outgoing)


func _is_non_existent_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Team.is_empty() and target.Team == Team:
		return false
	return true


func _update_non_existent_alpha() -> void:
	if image == null or not is_instance_valid(image):
		return
	var ratio:float = 0.0
	if Max_health > 0:
		ratio = clampf(float(health) / float(Max_health),0.0,1.0)
	# 1000血时100%不透明；随着受伤连续降低，到0血时完全透明。
	image.self_modulate = Color(1.0,1.0,1.0,ratio)


func _play_non_existent_hit_sfx(raw_damage:float) -> void:
	if Hit_Audio.is_empty():
		return
	var params:Dictionary = {
		"volume":clampf(raw_damage - 24.0,-20.0,-3.0),
		"pitch":randf_range(0.97,1.03)
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(Hit_Audio,params,true)
	else:
		Audios.play_sfx(Hit_Audio,params,true)
