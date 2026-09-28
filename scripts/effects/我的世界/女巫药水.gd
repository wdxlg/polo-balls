extends Node2D

# V180：药水瓶使用自己的线段扫掠，不走公共 hitbox。
# Sans 完全闪避成功时，瓶子继续飞，不施加瓶身效果、不碎裂。

const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")
const AREA_SCRIPT = preload("res://scripts/effects/我的世界/女巫药水区域.gd")
const SHATTER_SFX = preload("res://audio/characters/女巫/药水碎裂.ogg")
const DAMAGE_SFX = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")

var effect_type:String = ""
var source_witch:Node = null
var _launch_impact_damage:float = 30.0
var start_position:Vector2 = Vector2.ZERO
var target_position:Vector2 = Vector2.ZERO
var flight_duration:float = 0.85
var arc_height:float = 105.0
var spin_speed:float = 11.5
var bottle_hit_radius:float = 9.0
var area_radius:float = 64.0
var area_duration:float = 5.2

var _elapsed:float = 0.0
var _last_position:Vector2 = Vector2.ZERO
var _exploded:bool = false
var _sprite:Sprite2D = null


func setup(start:Vector2,target:Vector2,new_effect_type:String,new_source:Variant = null,held_visual_transform:Variant = null) -> void:
	start_position = start
	target_position = target
	effect_type = new_effect_type
	source_witch = _valid_source_node(new_source)
	_launch_impact_damage = get_projectile_damage()
	var distance:float = start.distance_to(target)
	flight_duration = clampf(distance / 330.0,0.62,1.18)
	arc_height = clampf(distance * 0.38,72.0,145.0)
	_ensure_sprite()

	# V392：若由女巫手里的 PotionImage 直接投出，则继承那一刻的完整世界 Transform。
	# 这样出生帧不会突然改大小、镜像或初始角度；之后才在该角度基础上继续飞行自转。
	if held_visual_transform is Transform2D:
		var inherited_transform:Transform2D = held_visual_transform
		global_transform = inherited_transform
		global_position = start_position
		if _sprite != null:
			_sprite.position = Vector2.ZERO
			_sprite.rotation = 0.0
			_sprite.scale = Vector2.ONE
	else:
		global_position = start_position
	_last_position = start_position
	if _sprite != null:
		_sprite.texture = POTION_EFFECTS.texture_for(effect_type)


func _ready() -> void:
	z_as_relative = false
	z_index = 95
	_ensure_sprite()
	if _sprite != null and not effect_type.is_empty():
		_sprite.texture = POTION_EFFECTS.texture_for(effect_type)


func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_sprite = Sprite2D.new()
	_sprite.name = "PotionSprite"
	_sprite.centered = true
	_sprite.scale = Vector2.ONE * 0.024
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _physics_process(delta:float) -> void:
	if _exploded:
		return
	_elapsed += delta
	var t:float = clampf(_elapsed / maxf(flight_duration,0.001),0.0,1.0)
	var previous:Vector2 = global_position
	var base:Vector2 = start_position.lerp(target_position,t)
	var lift:float = -4.0 * arc_height * t * (1.0 - t)
	global_position = base + Vector2(0.0,lift)
	rotation += spin_speed * delta

	var hit_target:ball = _find_segment_hit(previous,global_position)
	if hit_target != null:
		# 命中施加一次可升级药效；瓶身基础30（女巫20攻击×1.5），与药效伤害分开。
		# 撞击伤害走项目现有 receive_positional_damage()；真实结算后随机播放用户提供的三段药水伤害音。
		var active_source:Node = _valid_source_node(source_witch)
		POTION_EFFECTS.apply_stacking_effect(hit_target,effect_type,active_source)
		var bottle_damage_applied:bool = false
		if is_instance_valid(hit_target) and not hit_target.is_queued_for_deletion() and hit_target.health > 0:
			bottle_damage_applied = hit_target.receive_positional_damage(get_projectile_damage(),global_position,false,active_source)
		if bottle_damage_applied:
			DAMAGE_SFX.play(hit_target,global_position)
		_explode(global_position)
		return

	_last_position = global_position
	if t >= 1.0:
		_explode(target_position)


func get_projectile_damage() -> float:
	# Native protocol overrides the legacy 50-point descriptor for capture/threats.
	# Keep live attack scaling, or the launch snapshot if the caster has disappeared.
	var caster:Node = _valid_source_node(source_witch)
	return caster.attack_damage(1.5) if caster is ball else _launch_impact_damage


func _valid_source_node(candidate:Variant) -> Node:
	if candidate == null or not is_instance_valid(candidate):
		return null
	if candidate is Node:
		return candidate as Node
	return null


func _find_segment_hit(a:Vector2,b:Vector2) -> ball:
	var active_source:Node = _valid_source_node(source_witch)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if candidate.Type != ball.Ball_Type.Ball and candidate.Type != ball.Ball_Type.Creature:
			continue
		if active_source != null and candidate == active_source:
			continue
		if candidate.health <= 0 or candidate.is_queued_for_deletion():
			continue
		var hit_radius:float = bottle_hit_radius + _estimate_target_radius(candidate)
		if _distance_to_segment(candidate.global_position,a,b) <= hit_radius:
			# 先给支持完全投射物闪避的目标一次机会。成功时，这个瓶子
			# 继续当前抛物线路径，不触发药效、撞击伤害、碎裂或范围区。
			if candidate.has_method("try_full_projectile_dodge") and bool(candidate.call("try_full_projectile_dodge",self)):
				continue
			return candidate
	return null


func _estimate_target_radius(target:ball) -> float:
	var shape_node:CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return 16.0
	var sx:float = absf(target.global_scale.x)
	var sy:float = absf(target.global_scale.y)
	if shape_node.shape is RectangleShape2D:
		var rect:RectangleShape2D = shape_node.shape as RectangleShape2D
		return maxf(rect.size.x * sx,rect.size.y * sy) * 0.5
	if shape_node.shape is CircleShape2D:
		var circle:CircleShape2D = shape_node.shape as CircleShape2D
		return circle.radius * maxf(sx,sy)
	return 16.0


func _distance_to_segment(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return point.distance_to(a)
	var q:float = clampf((point - a).dot(ab) / len_sq,0.0,1.0)
	return point.distance_to(a + ab * q)



func _explode(at_position:Vector2) -> void:
	if _exploded:
		return
	_exploded = true
	_play_shatter(at_position)
	var area:Node2D = AREA_SCRIPT.new()
	get_tree().current_scene.add_child(area)
	area.global_position = at_position
	area.call("setup",effect_type,_valid_source_node(source_witch),area_radius,area_duration)
	queue_free()


func _play_shatter(at_position:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.stream = SHATTER_SFX
	player.volume_db = 1.5
	player.pitch_scale = randf_range(0.97,1.04)
	world.add_child(player)
	player.global_position = at_position
	player.finished.connect(player.queue_free)
	player.play()
