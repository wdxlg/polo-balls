extends Area2D

@export var Master_name:String = ""
@export var Team:String = ""
@export var damage_amount:float = 25.0
@export var speed:float = 430.0
@export var max_distance:float = 520.0
@export var direction:Vector2 = Vector2.RIGHT
@export var visual_radius:float = 8.0
@export var pixel_size:float = 2.0

var _travelled:float = 0.0
var _finished:bool = false


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MagicHornBullet")
	if direction.length_squared() <= 0.000001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _draw() -> void:
	var r:float = maxf(visual_radius,2.0)
	var px:float = maxf(pixel_size,1.0)
	var cells:int = int(ceil(r / px))
	for y:int in range(-cells,cells + 1):
		for x:int in range(-cells,cells + 1):
			var center:Vector2 = Vector2(float(x),float(y)) * px
			if center.length() > r:
				continue
			var edge:bool = false
			for neighbor in [Vector2(px,0),Vector2(-px,0),Vector2(0,px),Vector2(0,-px)]:
				if (center + neighbor).length() > r:
					edge = true
					break
			var color_value:Color
			if edge:
				color_value = Color(0.015,0.012,0.014,1.0)
			elif ((x + y) & 1) == 0:
				color_value = Color(0.13,0.12,0.13,1.0)
			else:
				color_value = Color(0.20,0.18,0.19,1.0)
			draw_rect(Rect2(center - Vector2.ONE * px * 0.5,Vector2.ONE * px),color_value,true)


func _physics_process(delta:float) -> void:
	if not is_multiplayer_authority() or _finished:
		return
	var master:ball = _resolve_master()
	if master == null or not is_instance_valid(master) or master.health <= 0 or master.is_damage_output_disabled():
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
	var hit:Dictionary = _raycast_motion(start,finish,master)
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
			_apply_hit(target,master)
	_finish()


func _raycast_motion(start:Vector2,finish:Vector2,master:ball) -> Dictionary:
	var exclude:Array[RID] = []
	if master != null and is_instance_valid(master):
		exclude.append(master.get_rid())
	for _pass:int in range(10):
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
	if target == master:
		return true
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return true
	# V179：Sans 闪避时射线把他当成不存在，继续检查同一路径后面的目标/墙。
	if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)):
		return true
	return false


func _can_damage_target(target:ball,master:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0 or not target.is_combat_targetable():
		return false
	if target == master or master == null or not is_instance_valid(master) or master.is_damage_output_disabled():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true


func _apply_hit(target:ball,master:ball) -> void:
	var outgoing:float = master.effective_outgoing_damage(damage_amount)
	if outgoing <= 0.0:
		return
	if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,outgoing)):
		return

	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	var did_hit:bool = target.receive_positional_damage(outgoing,global_position,false,self)
	var health_loss:float = maxf(before_health - float(target.health),0.0)
	var block_loss:float = maxf(before_block - float(target.block),0.0)
	if did_hit and master.has_method("play_magic_horn_collision_sfx"):
		master.call("play_magic_horn_collision_sfx",outgoing)
	if health_loss > 0.0:
		var hit_seed:int = Game.battle_rng_seed_or("scripts/shooter/魔角猎人_黑弹.gd:hit_seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(target.get_instance_id()))
		target.notify_hit_burst_feedback(
			global_position,
			outgoing,
			health_loss,
			block_loss,
			maxf(visual_radius * 0.85,2.0),
			hit_seed,
			direction
		)

	# 魔角猎人的核心机制是“命中即推进标记”；护盾吸收伤害也算命中。
	if master.has_method("apply_magic_horn_mark"):
		master.call("apply_magic_horn_mark",target,global_position)

	# 三层爆炸后开启的窗口只影响主黑弹；窗口内每次主弹命中都会抛出小爆弹。
	if master.has_method("is_magic_horn_bomb_window_active") and bool(master.call("is_magic_horn_bomb_window_active")):
		if master.has_method("spawn_magic_horn_small_bombs"):
			master.call("spawn_magic_horn_small_bombs",global_position)


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
