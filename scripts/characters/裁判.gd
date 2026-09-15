extends ball

const YELLOW_CARD_SCENE:PackedScene = preload("res://scenes/shooter/裁判黄牌.tscn")
const BLUE_CARD_SCENE:PackedScene = preload("res://scenes/shooter/裁判蓝牌.tscn")
const RED_CARD_SCENE:PackedScene = preload("res://scenes/shooter/裁判红牌.tscn")
const SHARED_WHISTLE = preload("res://scripts/audio/投稿吹哨音效.gd")

# ============================================================
# 裁判（代码-only 安全版）
# - 普攻：吹哨，对附近敌人造成伤害并击退。
# - 短时间内实际生命值下降达到阈值：自动向最近有效敌人出牌。
# - 黄牌：伤害 + 眩晕。
# - 蓝牌：高伤害。
# - 红牌：伤害 + 更长时间禁止目标输出伤害。
#
# 这版不依赖图片路径，也不依赖“受击前缓存 Hitbox 来源”。
# 立绘全部是可选 Texture2D 槽位；不填图片时仍能运行逻辑。
# ============================================================

@export_category("裁判 - 外观（可留空）")
@export var normal_texture:Texture2D
@export var whistle_texture:Texture2D
@export var throw_texture:Texture2D
@export_range(0.02,1.0,0.01) var throw_pose_time:float = 0.20

@export_category("裁判 - 吹哨")
@export_range(20.0,500.0,5.0) var whistle_radius:float = 135.0
@export_range(0.0,10.0,0.05) var whistle_damage_multiplier:float = 1.40625
@export_range(0.0,300.0,5.0) var whistle_knockback_distance:float = 78.0
@export_range(50.0,1800.0,10.0) var whistle_knockback_speed:float = 720.0
@export_range(0.02,1.0,0.01) var whistle_pose_time:float = 0.16
@export var whistle_audio:String = ""

@export_category("裁判 - 出牌条件")
@export_range(0.2,8.0,0.1) var card_damage_window:float = 2.2
@export_range(1.0,2000.0,5.0) var card_damage_threshold:float = 150.0
@export_range(0.0,5.0,0.05) var card_reaction_cooldown:float = 0.55
@export_range(50.0,1500.0,10.0) var card_speed:float = 470.0
@export_range(0.0,200.0,1.0) var card_spawn_offset:float = 30.0
@export_range(0.0,10.0,0.05) var yellow_card_damage_multiplier:float = 1.1875
@export_range(0.0,10.0,0.05) var blue_card_damage_multiplier:float = 3.28125
@export_range(0.0,10.0,0.05) var red_card_damage_multiplier:float = 1.0

@export_category("裁判 - 牌概率")
@export_range(0.0,10.0,0.1) var yellow_card_weight:float = 4.5
@export_range(0.0,10.0,0.1) var blue_card_weight:float = 3.0
@export_range(0.0,10.0,0.1) var red_card_weight:float = 2.0

const VISUAL_NORMAL:int = 0
const VISUAL_WHISTLE:int = 1
const VISUAL_THROW:int = 2

var _damage_samples:Array[Dictionary] = []
var _card_reaction_cooldown_left:float = 0.0
var _visual_token:int = 0
var _last_health_snapshot:float = 0.0
var _default_texture:Texture2D = null


func _ready() -> void:
	super._ready()
	_auto_load_textures()
	_last_health_snapshot = float(health)
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_set_visual_state_local(VISUAL_NORMAL)


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _try_load_texture("res://Images/characters/人物/裁判/裁判_正常.png")
	if whistle_texture == null:
		whistle_texture = _try_load_texture("res://Images/characters/人物/裁判/裁判_吹哨.png")
	if throw_texture == null:
		throw_texture = _try_load_texture("res://Images/characters/人物/裁判/裁判_扔牌.png")


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority():
		_track_actual_health_loss()
		_card_reaction_cooldown_left = maxf(_card_reaction_cooldown_left - delta,0.0)
		_prune_damage_samples(Time.get_ticks_msec())
		_try_react_with_card()
	super.tick_physics(state,delta)


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled():
		Attacking = false
		return

	Attacking = true
	_show_timed_visual(VISUAL_WHISTLE,maxf(whistle_pose_time,0.02))
	_play_whistle_audio()
	_show_whistle_everywhere(whistle_radius)

	var outgoing_damage:float = attack_damage(whistle_damage_multiplier)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue
		if global_position.distance_to(target.global_position) > whistle_radius:
			continue

		if outgoing_damage > 0.0:
			target.receive_spatial_damage(
				outgoing_damage,
				{"shape":"circle","center":global_position,"radius":whistle_radius,"source":self},
				false
			)

		if whistle_knockback_distance > 0.0:
			var push_dir:Vector2 = target.global_position - global_position
			if push_dir.length_squared() <= 0.000001:
				push_dir = Vector2.RIGHT.rotated(randf_range(0.0,TAU))
			target.apply_knockback(
				push_dir.normalized(),
				whistle_knockback_distance,
				whistle_knockback_speed,
				0.35,
				0.0,
				{
					"source": self,
					"max_wall_bounces": 1,
					"stop_on_character": true,
					"smooth_motion": true,
				}
			)

	await get_tree().create_timer(maxf(whistle_pose_time,0.02)).timeout
	if is_instance_valid(self):
		Attacking = false


func _track_actual_health_loss() -> void:
	var current_health:float = float(health)
	if current_health < _last_health_snapshot:
		var actual_damage:float = _last_health_snapshot - current_health
		_damage_samples.append({
			"time": Time.get_ticks_msec(),
			"damage": actual_damage,
		})
	_last_health_snapshot = current_health


func _prune_damage_samples(now_msec:int) -> void:
	var keep_from:int = now_msec - int(round(maxf(card_damage_window,0.0) * 1000.0))
	var kept:Array[Dictionary] = []
	for sample:Dictionary in _damage_samples:
		if int(sample.get("time",0)) >= keep_from:
			kept.append(sample)
	_damage_samples = kept


func _current_window_damage() -> float:
	var total:float = 0.0
	for sample:Dictionary in _damage_samples:
		total += float(sample.get("damage",0.0))
	return total


func _try_react_with_card() -> void:
	if _card_reaction_cooldown_left > 0.0:
		return
	if _current_window_damage() < card_damage_threshold:
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	if is_damage_output_disabled():
		return

	var target:ball = _find_card_target()
	if not _is_valid_enemy(target):
		return

	_damage_samples.clear()
	_card_reaction_cooldown_left = maxf(card_reaction_cooldown,0.0)
	_throw_card(target)


func _find_card_target() -> ball:
	if Nearest_Enemy is ball:
		var nearest:ball = Nearest_Enemy as ball
		if _is_valid_enemy(nearest):
			return nearest

	var best:ball = null
	var best_distance_sq:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_valid_enemy(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = candidate
	return best


func _throw_card(target:ball) -> void:
	if not is_multiplayer_authority() or is_damage_output_disabled():
		return
	if not _is_valid_enemy(target):
		return

	var packed:PackedScene = _roll_card_scene()
	if packed == null:
		return

	var card:ball = packed.instantiate() as ball
	if card == null:
		return

	var aim:Vector2 = combat_target_position(target) - global_position
	if aim.length_squared() <= 0.000001:
		aim = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	aim = aim.normalized()

	_show_timed_visual(VISUAL_THROW,maxf(throw_pose_time,0.02))

	# MultiplayerSpawner 会在 add_child 时读取初始属性，所以先填参数再加入世界。
	card.Master = self
	card.Master_name = name
	card.Team = Team
	# V107：裁判所有牌伤害都继承裁判整体攻击力；牌场景本身不再保存独立攻击值。
	card.inherit_master_attack_power = true
	card.master_attack_damage_multiplier = _card_damage_multiplier(card)
	card.Damage = 0
	card.Target_Enemy = target
	card.Speed = card_speed
	card.direction = aim
	card.global_position = global_position + aim * card_spawn_offset
	card.global_rotation = aim.angle()
	card.name = Game.return_random_name(card)
	get_tree().current_scene.add_child(card,true)



func _card_damage_multiplier(card:ball) -> float:
	if card == null or not is_instance_valid(card):
		return 1.0
	var raw_type:Variant = card.get("card_type")
	var card_type_value:int = int(raw_type) if raw_type != null else 0
	match card_type_value:
		0:
			return maxf(yellow_card_damage_multiplier,0.0)
		1:
			return maxf(blue_card_damage_multiplier,0.0)
		2:
			return maxf(red_card_damage_multiplier,0.0)
	return 1.0

func _roll_card_scene() -> PackedScene:
	var yellow:float = maxf(yellow_card_weight,0.0)
	var blue:float = maxf(blue_card_weight,0.0)
	var red:float = maxf(red_card_weight,0.0)
	var total:float = yellow + blue + red
	if total <= 0.0:
		return YELLOW_CARD_SCENE

	var roll:float = randf() * total
	if roll < yellow:
		return YELLOW_CARD_SCENE
	roll -= yellow
	if roll < blue:
		return BLUE_CARD_SCENE
	return RED_CARD_SCENE


func _show_timed_visual(state_value:int,duration:float) -> void:
	_visual_token += 1
	var token:int = _visual_token
	_broadcast_visual_state(state_value)
	_restore_normal_visual_after(duration,token)


func _restore_normal_visual_after(delay:float,token:int) -> void:
	await get_tree().create_timer(maxf(delay,0.02)).timeout
	if not is_instance_valid(self) or health <= 0 or token != _visual_token:
		return
	_broadcast_visual_state(VISUAL_NORMAL)


func _broadcast_visual_state(state_value:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_visual_state.rpc(state_value)
	else:
		_rpc_set_visual_state(state_value)


@rpc("authority","call_local","reliable")
func _rpc_set_visual_state(state_value:int) -> void:
	_set_visual_state_local(state_value)


func _set_visual_state_local(state_value:int) -> void:
	if not (image is Sprite2D):
		return

	var fallback_normal:Texture2D = normal_texture if normal_texture != null else _default_texture
	var wanted:Texture2D = fallback_normal
	match state_value:
		VISUAL_WHISTLE:
			wanted = whistle_texture if whistle_texture != null else fallback_normal
		VISUAL_THROW:
			wanted = throw_texture if throw_texture != null else fallback_normal
		_:
			wanted = fallback_normal

	if wanted != null:
		(image as Sprite2D).texture = wanted
		_refit_visual_only()


func _refit_visual_only() -> void:
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _is_valid_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == self or not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and Team != ""
		and target.Team != ""
		and Team == target.Team
	):
		return false
	return true


func _play_whistle_audio() -> void:
	var pick:int = SHARED_WHISTLE.random_index()
	if multiplayer.has_multiplayer_peer():
		_rpc_play_shared_whistle.rpc(pick,global_position)
	else:
		_rpc_play_shared_whistle(pick,global_position)

@rpc("authority","call_local","unreliable")
func _rpc_play_shared_whistle(index:int,position_value:Vector2) -> void:
	SHARED_WHISTLE.play_at(self,index,position_value,-1.0,randf_range(0.98,1.02))


func _show_whistle_everywhere(radius:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_whistle_pulse.rpc(radius)
	else:
		_rpc_show_whistle_pulse(radius)


@rpc("authority","call_local","reliable")
func _rpc_show_whistle_pulse(radius:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color(1.0,0.95,0.35,0.88)
	ring.closed = true
	ring.z_index = 30
	var points := PackedVector2Array()
	const SEGMENTS:int = 42
	for i:int in range(SEGMENTS):
		var angle:float = TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(angle),sin(angle)) * radius)
	ring.points = points
	ring.global_position = global_position
	ring.scale = Vector2(0.22,0.22)
	world.add_child(ring)

	var tween:Tween = ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring,"scale",Vector2.ONE,0.20)
	tween.tween_property(ring,"modulate",Color(1.0,1.0,1.0,0.0),0.24)
	tween.finished.connect(ring.queue_free)


func Die() -> void:
	_visual_token += 1
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)


# AI 通用威胁接口：吹哨是以裁判为中心的圆形伤害区。
func get_ai_attack_threats(receiver:ball) -> Array:
	var result:Array = []
	if receiver == null or not is_instance_valid(receiver) or not _is_valid_enemy(receiver):
		return result
	var danger_in:float = 999.0
	if Attacking:
		danger_in = 0.0
	elif state_machine != null and state_machine.last_state_dis.has(State.Attack):
		danger_in = maxf(float(state_machine.last_state_dis[State.Attack]),0.0)
	# 只暴露近期真实可能发生的吹哨，避免整个冷却周期都当成红区。
	if danger_in > 0.35:
		return result
	result.append({
		"shape":"circle",
		"position":global_position,
		"radius":maxf(whistle_radius,1.0),
		"danger_in":danger_in,
		"danger_duration":maxf(whistle_pose_time,0.04),
		"damage":attack_damage(whistle_damage_multiplier),
		"kind":"referee_whistle",
		"source":self,
	})
	return result


# AI 战略接口：短时间吃伤害越接近出牌阈值，继续猛攻的反制风险越高。
func get_ai_strategy_info(_receiver:ball) -> Dictionary:
	var threshold:float = maxf(card_damage_threshold,1.0)
	return {
		"counter_risk":clampf(_current_window_damage()/threshold,0.0,1.0),
	}
