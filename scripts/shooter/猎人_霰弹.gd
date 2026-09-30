extends Area2D

const ARMS_DEALER_BULLET_TEXTURE_PATH:String = "res://Images/characters/人物/军火商/弹药/步枪子弹.png"
const BULLET_IMPACT_PERSON:int = 1
const BULLET_IMPACT_HARD:int = 2

# 猎人的单颗霰弹丸：使用逐帧射线避免高速穿透，并用累计距离硬限制射程。

@export var Master_name:String = ""
@export var Team:String = ""
@export var damage_amount:float = 22.0
@export var speed:float = 780.0
@export var max_distance:float = 150.0
@export var direction:Vector2 = Vector2.RIGHT
@export var knockback_distance:float = 10.0
@export var knockback_speed:float = 360.0
@export var visual_size:float = 4.0

var _travelled:float = 0.0
var _finished:bool = false

@onready var _sprite:Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _trail:Line2D = get_node_or_null("Trail") as Line2D
@onready var _body_visual:Polygon2D = get_node_or_null("BodyVisual") as Polygon2D


func _ready() -> void:
	add_to_group("AllayExtendedProjectile")
	add_to_group("BattleTransient")
	add_to_group("HunterPellet")
	if direction.length_squared() <= 0.000001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	_setup_visual()


func _setup_visual() -> void:
	# 霰弹丸直接复用军火商普通子弹的“步枪子弹.png”，只保留猎人自己的弹道/射程逻辑。
	var texture:Texture2D = _load_arms_dealer_bullet_texture()
	if _sprite != null and texture != null:
		_sprite.texture = texture
		_sprite.flip_h = false
		_sprite.flip_v = direction.x < 0.0
		var size:Vector2 = texture.get_size()
		var max_dim:float = maxf(size.x,size.y)
		if max_dim > 0.0:
			# 与军火商普通子弹使用同一套显示尺寸映射。
			var display_dimension:float = clampf(maxf(visual_size,1.0) * 3.2,10.0,24.0)
			_sprite.scale = Vector2.ONE * (display_dimension / max_dim)
		_sprite.visible = true
		if _body_visual != null:
			_body_visual.visible = false
	elif _body_visual != null:
		# 如果原图资源缺失，仍用旧几何图形兜底，避免出现隐形子弹。
		_body_visual.visible = true
		var r:float = maxf(visual_size,1.0)
		_body_visual.polygon = PackedVector2Array([
			Vector2(r * 1.65,0.0),
			Vector2(-r * 0.70,-r * 0.50),
			Vector2(-r * 0.70,r * 0.50)
		])
	if _trail != null:
		_trail.width = maxf(visual_size * 0.34,1.0)
		_trail.points = PackedVector2Array([Vector2.ZERO,Vector2(-maxf(visual_size * 3.2,7.0),0.0)])


func _load_arms_dealer_bullet_texture() -> Texture2D:
	if not ResourceLoader.exists(ARMS_DEALER_BULLET_TEXTURE_PATH):
		return null
	var resource:Resource = ResourceLoader.load(ARMS_DEALER_BULLET_TEXTURE_PATH)
	return resource as Texture2D if resource is Texture2D else null


func _physics_process(delta:float) -> void:
	if not is_multiplayer_authority() or _finished:
		return

	var master:ball = _resolve_master()
	if master == null or not is_instance_valid(master) or master.health <= 0:
		_finish()
		return

	var remaining:float = maxf(max_distance - _travelled,0.0)
	if remaining <= 0.0:
		_finish()
		return

	var step_distance:float = minf(maxf(speed,0.0) * delta,remaining)
	if step_distance <= 0.0:
		_finish()
		return

	var start:Vector2 = global_position
	var finish:Vector2 = start + direction * step_distance
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,start,finish): return
	var hit:Dictionary = _raycast_motion(start,finish)
	if hit.is_empty():
		global_position = finish
		_travelled += step_distance
		if _travelled >= max_distance - 0.001:
			_finish()
		return

	global_position = hit.get("position",finish)
	_travelled += start.distance_to(global_position)
	var collider:Variant = hit.get("collider",null)
	if collider is ball:
		var target:ball = collider as ball
		if _can_damage_target(target,master):
			var impact_result:int = _apply_hit(target,master)
			if impact_result == BULLET_IMPACT_HARD:
				_play_bullet_impact_sfx("子弹打墙",-3.0)
			elif impact_result == BULLET_IMPACT_PERSON:
				_play_bullet_impact_sfx("子弹打人",-4.0)
	else:
		# 霰弹撞到地形/实体障碍：使用“子弹打墙”。
		_play_bullet_impact_sfx("子弹打墙",-3.0)
	_finish()


func _raycast_motion(start:Vector2,finish:Vector2) -> Dictionary:
	var exclude:Array[RID] = []
	var master:ball = _resolve_master()
	if master != null and is_instance_valid(master):
		exclude.append(master.get_rid())

	for _pass:int in range(8):
		var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start,finish,3,exclude)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = true
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider:Variant = hit.get("collider",null)
		if _should_pass_through(collider,master):
			if collider is CollisionObject2D:
				exclude.append((collider as CollisionObject2D).get_rid())
				continue
		return hit
	return {}


func _should_pass_through(collider:Variant,master:ball) -> bool:
	if not collider is ball:
		return false
	var target:ball = collider as ball
	if master != null and target == master:
		return true
	if Team != "" and target.Team != "" and target.Team == Team:
		return true
	# V179：Sans 闪避时射线把他当成不存在，继续检查同一路径后面的目标/墙。
	if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)):
		return true
	return false


func _can_damage_target(target:ball,master:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if master != null:
		if target == master or master.is_damage_output_disabled():
			return false
	if Team != "" and target.Team != "" and target.Team == Team:
		return false
	return true


func _apply_hit(target:ball,master:ball) -> int:
	var outgoing:float = damage_amount
	if master != null and is_instance_valid(master):
		outgoing = master.effective_outgoing_damage(damage_amount)
	if outgoing <= 0.0:
		return BULLET_IMPACT_HARD

	if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,outgoing)):
		return BULLET_IMPACT_HARD
	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	target.receive_positional_damage(outgoing,global_position,false,self)
	var health_loss:float = maxf(before_health - float(target.health),0.0)
	var block_loss:float = maxf(before_block - float(target.block),0.0)
	if health_loss > 0.0:
		var hit_seed:int = Game.battle_rng_seed_or("scripts/shooter/猎人_霰弹.gd:hit_seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(target.get_instance_id()))
		target.notify_hit_burst_feedback(
			global_position,
			outgoing,
			health_loss,
			block_loss,
			maxf(visual_size * 1.4,2.0),
			hit_seed,
			direction
		)

	if knockback_distance > 0.0:
		target.apply_knockback(
			direction,
			knockback_distance,
			maxf(knockback_speed,50.0),
			0.25,
			0.0,
			{"source":master,"max_wall_bounces":1,"stop_on_character":true}
		)

	if block_loss > 0.0 or health_loss <= 0.0:
		return BULLET_IMPACT_HARD
	return BULLET_IMPACT_PERSON


func _play_bullet_impact_sfx(sfx_name:String,volume_offset:float = 0.0) -> void:
	var params:Dictionary = {
		"volume": volume_offset,
		"pitch": randf_range(0.95,1.06),
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,false,true)
	else:
		Audios.play_sfx(sfx_name,params,false,true)


func _resolve_master() -> ball:
	if Master_name.is_empty():
		return null
	var world:Node = get_tree().current_scene
	if world != null:
		var direct:Node = world.get_node_or_null(NodePath(Master_name))
		if direct is ball:
			return direct as ball
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and str(node.name) == Master_name:
			return node as ball
	return null


func _finish() -> void:
	if _finished:
		return
	_finished = true
	Game.free_node(self)
