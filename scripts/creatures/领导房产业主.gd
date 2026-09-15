extends Node2D

const VAN_FIST_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/拳头.png")

var target_leader:Node = null
var authoritative_logic:bool = false
var move_speed:float = 105.0
var attack_interval:float = 0.82
var punch_damage:float = 18.0
var knockback_distance:float = 8.0
var knockback_speed:float = 105.0
var attack_cooldown:float = 0.0
var escaping:bool = false
var escape_direction:Vector2 = Vector2.RIGHT
var escape_elapsed:float = 0.0
var _punching:bool = false
@onready var _fist_sprite:Sprite2D = $Fist


func configure(leader_node:Node,config:Dictionary,is_authority:bool) -> void:
	target_leader = leader_node
	authoritative_logic = is_authority
	global_position = config.get("origin",global_position)
	move_speed = maxf(float(config.get("speed",105.0)),10.0)
	attack_interval = maxf(float(config.get("attack_interval",0.82)),0.1)
	punch_damage = maxf(float(config.get("damage",18.0)),0.0)
	knockback_distance = maxf(float(config.get("knockback_distance",8.0)),0.0)
	knockback_speed = maxf(float(config.get("knockback_speed",105.0)),10.0)
	z_as_relative = false
	z_index = 72
	add_to_group("BattleTransient")
	_ensure_fist_visual()
	queue_redraw()


func _physics_process(delta:float) -> void:
	attack_cooldown = maxf(attack_cooldown - delta,0.0)
	if target_leader == null or not is_instance_valid(target_leader) or not (target_leader is ball) or (target_leader as ball).health <= 0:
		_begin_escape()
	if escaping:
		_update_escape(delta)
		queue_redraw()
		return

	var leader:ball = target_leader as ball
	var delta_to:Vector2 = leader.global_position - global_position
	var distance:float = delta_to.length()
	if distance > 48.0 and not _punching:
		var dir:Vector2 = delta_to.normalized()
		global_position += dir * move_speed * delta
		rotation = 0.0
	elif attack_cooldown <= 0.0 and not _punching:
		attack_cooldown = attack_interval
		_punching = true
		_animate_fist_attack(leader)
	queue_redraw()


func _ensure_fist_visual() -> void:
	if _fist_sprite == null or not is_instance_valid(_fist_sprite):
		return
	_fist_sprite.texture = VAN_FIST_TEXTURE
	_fist_sprite.visible = false
	_fist_sprite.z_index = 5
	var source_length:float = maxf(float(VAN_FIST_TEXTURE.get_height()),1.0)
	var visual_scale:float = 30.4 / source_length
	_fist_sprite.scale = Vector2.ONE * visual_scale


func _animate_fist_attack(leader:ball) -> void:
	_ensure_fist_visual()
	if _fist_sprite == null:
		_punching = false
		return
	if leader == null or not is_instance_valid(leader):
		_punching = false
		return
	var attack_dir:Vector2 = leader.global_position - global_position
	if attack_dir.length_squared() <= 0.0001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()
	_fist_sprite.visible = true
	_fist_sprite.rotation = attack_dir.angle() + PI * 0.5
	if authoritative_logic:
		_play_property_fist_swing_audio(global_position)
	var hit_done:bool = false
	var steps:int = 12
	for i:int in range(steps):
		if escaping or target_leader == null or not is_instance_valid(target_leader):
			break
		var t:float = float(i) / float(maxi(steps - 1,1))
		var extension:float = sin(t * PI) * 12.8
		var handle_distance:float = 3.2 + extension
		var center_distance:float = handle_distance + 15.2
		_fist_sprite.position = attack_dir * center_distance
		_fist_sprite.rotation = attack_dir.angle() + PI * 0.5
		if authoritative_logic and not hit_done and _fist_reaches_leader(leader,attack_dir,handle_distance):
			hit_done = true
			if punch_damage > 0.0:
				var dealt:bool = leader.receive_spatial_damage(punch_damage,{"point":leader.global_position,"source":self},false,false)
				if dealt:
					var knock_dir:Vector2 = leader.global_position - global_position
					if knock_dir.length_squared() <= 0.0001:
						knock_dir = attack_dir
					leader.apply_knockback(knock_dir.normalized(),knockback_distance,knockback_speed,0.0,0.0,{"source":self,"stop_on_character":true})
					_play_property_fist_hit_audio(leader.global_position)
		await get_tree().physics_frame
	_fist_sprite.visible = false
	_fist_sprite.position = Vector2.ZERO
	_punching = false


func _fist_reaches_leader(leader:ball,attack_dir:Vector2,handle_distance:float) -> bool:
	var start:Vector2 = global_position + attack_dir * handle_distance
	var finish:Vector2 = start + attack_dir * 30.4
	var radius:float = 12.0
	if leader.has_method("get_crowd_separation_radius_world"):
		radius = clampf(float(leader.call("get_crowd_separation_radius_world")),6.0,30.0)
	var segment:Vector2 = finish - start
	var denom:float = segment.length_squared()
	if denom <= 0.000001:
		return leader.global_position.distance_to(start) <= radius + 3.0
	var parameter:float = clampf((leader.global_position - start).dot(segment) / denom,0.0,1.0)
	var closest:Vector2 = start + segment * parameter
	return leader.global_position.distance_to(closest) <= radius + 3.0


func _play_property_fist_swing_audio(world_pos:Vector2) -> void:
	if target_leader != null and is_instance_valid(target_leader) and target_leader.has_method("_call_property_fist_swing_audio"):
		target_leader.call("_call_property_fist_swing_audio",world_pos)


func _play_property_fist_hit_audio(world_pos:Vector2) -> void:
	if target_leader != null and is_instance_valid(target_leader) and target_leader.has_method("_call_property_fist_hit_audio"):
		target_leader.call("_call_property_fist_hit_audio",world_pos)


func _begin_escape() -> void:
	if escaping:
		return
	escaping = true
	_punching = false
	if _fist_sprite != null and is_instance_valid(_fist_sprite):
		_fist_sprite.visible = false
	var center:Vector2 = _map_rect().get_center()
	escape_direction = global_position - center
	if escape_direction.length_squared() <= 0.000001:
		escape_direction = Vector2.RIGHT
	escape_direction = escape_direction.normalized()


func _update_escape(delta:float) -> void:
	escape_elapsed += delta
	global_position += escape_direction * move_speed * 1.9 * delta
	var rect:Rect2 = _map_rect()
	if (rect.size.x > 1.0 and rect.size.y > 1.0 and not rect.grow(70.0).has_point(global_position)) or escape_elapsed >= 5.0:
		queue_free()


func _map_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2(global_position - Vector2(500.0,350.0),Vector2(1000.0,700.0))
	var map_group:Variant = world.get("map_group")
	var map_index:int = int(world.get("now_choose_map"))
	if not (map_group is Array) or map_index < 0 or map_index >= (map_group as Array).size():
		return Rect2(global_position - Vector2(500.0,350.0),Vector2(1000.0,700.0))
	var map_node:Variant = (map_group as Array)[map_index]
	if not (map_node is TileMapLayer):
		return Rect2(global_position - Vector2(500.0,350.0),Vector2(1000.0,700.0))
	return world.call("return_map_world_rect",map_node)


func _draw() -> void:
	var body_color:Color = Color(0.42,0.35,0.25,1.0) if not escaping else Color(0.55,0.55,0.55,0.9)
	draw_circle(Vector2(0.0,-9.0),7.0,Color(0.90,0.70,0.54,1.0))
	draw_rect(Rect2(Vector2(-8.0,-2.0),Vector2(16.0,19.0)),body_color,true)
	draw_line(Vector2(-6.0,17.0),Vector2(-9.0,27.0),Color(0.12,0.10,0.08,1.0),3.0,true)
	draw_line(Vector2(6.0,17.0),Vector2(9.0,27.0),Color(0.12,0.10,0.08,1.0),3.0,true)
	draw_line(Vector2(7.0,2.0),Vector2(15.0,4.0),Color(0.90,0.70,0.54,1.0),4.0,true)
