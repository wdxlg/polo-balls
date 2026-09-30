extends ball

const DOCUMENT_SCENE:PackedScene = preload("res://scenes/shooter/领导处分文件.tscn")
const DROP_SCENE:PackedScene = preload("res://scenes/effects/领导掉落物.tscn")
const PROPERTY_UNIT_SCENE:PackedScene = preload("res://scenes/characters/小弟/愤怒的人.tscn")
const LEADER_BODY_TEXTURE:Texture2D = preload("res://Images/characters/人物/领导/领导本体(2).png")
const DOCUMENT_THROW_SFX:AudioStream = preload("res://audio/characters/领导/扔纸.mp3")
const DOCUMENT_HIT_SFX:AudioStream = preload("res://audio/sfx/physics/balls_hit1.sfxr")
const DROP_COIN_HIT_SFX:AudioStream = preload("res://audio/characters/收债人/金币1.mp3")
const DROP_OBJECT_HIT_SFX:AudioStream = preload("res://audio/characters/面包车/铁棍打人.mp3")
const PROPERTY_FIST_SWING_SFX:AudioStream = preload("res://audio/characters/面包车/拳头挥舞.mp3")
const PROPERTY_FIST_HIT_SFX:AudioStream = preload("res://audio/characters/面包车/拳头命中.mp3")

enum LeaderAudioCue {
	DOCUMENT_THROW,
	DOCUMENT_HIT,
	DROP_COIN_HIT,
	DROP_OBJECT_HIT,
	PROPERTY_FIST_SWING,
	PROPERTY_FIST_HIT,
}

@export_category("领导 - 处分攻击")
@export_range(80.0,900.0,10.0) var document_speed:float = 340.0
@export_range(0.2,8.0,0.1) var document_lifetime:float = 3.2
@export_range(0.1,8.0,0.05) var document_damage_multiplier_min:float = 0.45
@export_range(0.1,8.0,0.05) var document_damage_multiplier_max:float = 0.65
@export_range(0.0,4.0,0.05) var document_repeat_hit_multiplier_step:float = 0.20

@export_category("领导 - 挨打掉落")
# V350：每一次真实生命伤害都独立掷掉落。概率与数量都由这次实际掉血量决定。
@export_range(0.0,1.0,0.01) var drop_base_chance:float = 0.18
@export_range(1.0,1000.0,1.0) var drop_damage_reference:float = 80.0
@export_range(0.0,1.0,0.01) var drop_damage_chance_bonus:float = 0.72
@export_range(0.0,1.0,0.01) var drop_damage_chance_cap:float = 0.90
@export_range(1.0,1000.0,1.0) var drop_damage_per_extra_item:float = 120.0
@export_range(1,12,1) var drop_max_items_per_hit:int = 5
# V356：高级掉落明显稀有化。默认总权重为1.0：金币78% / 车钥匙17% / 房产证5%。
@export_range(0.0,1.0,0.01) var coin_weight:float = 0.78
@export_range(0.0,1.0,0.01) var car_key_weight:float = 0.17
@export_range(0.0,1.0,0.01) var property_deed_weight:float = 0.05
@export_range(0.1,3.0,0.05) var drop_arc_duration:float = 0.84
@export_range(10.0,180.0,1.0) var drop_arc_height_min:float = 52.0
@export_range(10.0,220.0,1.0) var drop_arc_height_max:float = 92.0
@export_range(5.0,160.0,1.0) var drop_ground_distance_min:float = 40.0
@export_range(5.0,220.0,1.0) var drop_ground_distance_max:float = 90.0
@export_range(4.0,80.0,1.0) var drop_pickup_radius:float = 18.0
@export_range(0.0,3.0,0.05) var drop_pickup_grace:float = 0.70
@export_range(0.0,1.2,0.05) var drop_boundary_bounce:float = 0.72
@export_range(0.0,20.0,0.1) var drop_spin_speed_min:float = 7.0
@export_range(0.0,30.0,0.1) var drop_spin_speed_max:float = 12.0

@export_category("领导 - 掉落效果")
@export_range(0.0,1000.0,1.0) var coin_heal:float = 35.0
@export_range(0.0,1000.0,1.0) var car_key_heal:float = 90.0
@export_range(0.0,1000.0,1.0) var property_deed_heal:float = 145.0
@export_range(0.0,1000.0,1.0) var enemy_coin_damage:float = 36.0
@export_range(0.0,1000.0,1.0) var enemy_car_key_damage:float = 120.0
@export_range(20.0,600.0,10.0) var hostile_item_return_speed:float = 260.0

@export_category("领导 - 房产证召唤")
@export_range(20.0,500.0,5.0) var property_unit_speed:float = 105.0
@export_range(0.1,5.0,0.05) var property_unit_attack_interval:float = 0.82
@export_range(0.1,5.0,0.05) var property_unit_damage_multiplier:float = 0.80
@export_range(0.0,50.0,0.5) var property_unit_knockback_distance:float = 8.0
@export_range(20.0,500.0,5.0) var property_unit_knockback_speed:float = 105.0

@export_category("领导 - 正式图片")
@export_range(70.0,300.0,1.0) var leader_visual_height:float = 215.0

var _drop_serial:int = 0
var _property_unit_serial:int = 0
var _suppress_drop_trigger:bool = false
var _last_drop_observed_health:int = -1
# V344：只由领导 authority 维护。key=目标 instance_id，value=该目标已经成功吃到的处分次数。
var _document_hits_by_target:Dictionary = {}


func _ready() -> void:
	# V313：领导正式生命上限固定为 1000；场景值与运行时双保险一致。
	Max_health = 1000
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	health = mini(health,Max_health)
	_apply_leader_body_texture()
	_last_drop_observed_health = int(health)


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	_poll_drop_health_fallback()


func _poll_drop_health_fallback() -> void:
	# V315：公共 ball.health setter 会同步调用 on_actual_health_damage_received()。
	# 这里再用物理帧生命差做最终兜底：即使某个特殊脚本绕过角色钩子，只要生命真的下降，
	# 领导仍会进入同一掉落判定；正常钩子会提前更新 observed 值，因此不会重复滚两次。
	var current_health:int = int(health)
	if _last_drop_observed_health < 0:
		_last_drop_observed_health = current_health
		return
	if current_health < _last_drop_observed_health:
		_try_roll_damage_drop(float(_last_drop_observed_health - current_health))
	_last_drop_observed_health = current_health


func _apply_leader_body_texture() -> void:
	if not (image is Sprite2D) or LEADER_BODY_TEXTURE == null:
		return
	var sprite:Sprite2D = image as Sprite2D
	sprite.texture = LEADER_BODY_TEXTURE
	sprite.visible = true
	var source_height:float = maxf(float(LEADER_BODY_TEXTURE.get_height()),1.0)
	var visual_scale:float = leader_visual_height / source_height
	sprite.scale = Vector2.ONE * visual_scale


func Attack() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return
	var aim:Vector2 = _attack_direction()
	if aim.length_squared() <= 0.000001:
		Attacking = false
		return
	Attacking = true
	# V344：领导普通攻击只保留处分文件。旧“小领导子弹”分支已经完全删除。
	_spawn_document(aim.normalized())
	await get_tree().create_timer(0.10).timeout
	if is_instance_valid(self):
		Attacking = false


func _attack_direction() -> Vector2:
	if has_player_control_aim():
		return player_control_aim_direction(direction)
	var target:ball = _nearest_legal_enemy()
	if target != null:
		return target.global_position - global_position
	return direction


func _nearest_legal_enemy() -> ball:
	var best:ball = null
	var best_dist_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball):
			continue
		var candidate:ball = raw as ball
		if candidate == self or not candidate.is_combat_targetable():
			continue
		if (
			Team != ""
			and candidate.Team != ""
			and candidate.Team == Team
		):
			continue
		var dist_sq:float = global_position.distance_squared_to(candidate.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best


func _spawn_document(shot_direction:Vector2) -> void:
	# V355：真正扔出处分文件的这一刻播放用户提供的“扔纸.mp3”。
	# 命中人物时仍使用原 DOCUMENT_HIT_SFX，两种声音职责分离。
	_call_leader_audio(LeaderAudioCue.DOCUMENT_THROW,global_position)

	var config:Dictionary = {
		"id": _next_runtime_id("document"),
		"origin": global_position + shot_direction * 18.0,
		"direction": shot_direction,
		"speed": document_speed,
		"lifetime": document_lifetime,
		# 只作为异常情况下 owner 丢失时的后备基础值；正常最终伤害在真正命中目标时计算。
		"damage": float(Damage),
		"team": Team,
	}
	_call_spawn_document(config)


func _roll_document_damage_for_target(target:ball) -> float:
	# V344：随机不再发生在“发射瞬间”，而发生在“真正命中哪个人物”的瞬间。
	# 每个目标分别累计处分次数，A 被处分很多次不会抬高 B 的伤害。
	var prior_hits:int = 0
	if target != null and is_instance_valid(target):
		prior_hits = maxi(int(_document_hits_by_target.get(target.get_instance_id(),0)),0)

	var low:float = minf(document_damage_multiplier_min,document_damage_multiplier_max)
	var high:float = maxf(document_damage_multiplier_min,document_damage_multiplier_max)
	var growth:float = maxf(document_repeat_hit_multiplier_step,0.0) * float(prior_hits)
	var rolled_multiplier:float = randf_range(low + growth,high + growth)
	return attack_damage(rolled_multiplier)


func _record_document_hit(target:ball) -> void:
	# 只有处分攻击真正被 receive_spatial_damage 接受后才加层。
	# 完全无敌/被拒绝的命中不会凭空抬高下一次处分伤害。
	if target == null or not is_instance_valid(target):
		return
	var key:int = target.get_instance_id()
	_document_hits_by_target[key] = maxi(int(_document_hits_by_target.get(key,0)),0) + 1


func on_actual_health_damage_received(actual_health_damage:float,_health_before:float) -> void:
	# V315：回到 ball.health setter 的真实生命损失钩子作为主触发。
	# setter 对所有真实生命下降都会调用这里，比依赖 UI HealthBar 信号更直接。
	_last_drop_observed_health = int(health)
	_try_roll_damage_drop(actual_health_damage)


func _try_roll_damage_drop(actual_health_damage:float) -> void:
	if actual_health_damage <= 0.0 or _suppress_drop_trigger:
		return
	if not is_multiplayer_authority() or health <= 0:
		return

	# V350：每次真实受击都独立掷一次，不再依赖固定 60% / 2 次保底 / 时间间隔。
	# 伤害越高，掉落概率越接近 cap；成功后，伤害还会继续提高本次掉落数量。
	var chance:float = _drop_chance_for_damage(actual_health_damage)
	if randf() > chance:
		return

	var item_count:int = _drop_count_for_damage(actual_health_damage)
	if item_count <= 0:
		return

	# 掉落成立的瞬间统一播放一次金币声。即使一次受击掉出多个物品也只播一次，
	# 避免多颗掉落物在同一帧把金币音效叠得过响。
	_call_leader_audio(LeaderAudioCue.DROP_COIN_HIT,global_position)
	for _drop_index:int in range(item_count):
		_spawn_random_drop()


func _drop_chance_for_damage(actual_health_damage:float) -> float:
	var damage_value:float = maxf(actual_health_damage,0.0)
	var reference:float = maxf(drop_damage_reference,1.0)

	# 饱和增长：小伤害保留基础掉落率；大伤害提升明显，但不会突破 cap。
	# scaled = 1 - e^(-damage/reference)
	var scaled:float = 1.0 - exp(-damage_value / reference)
	var chance:float = clampf(drop_base_chance,0.0,1.0)
	chance += maxf(drop_damage_chance_bonus,0.0) * scaled
	return clampf(chance,0.0,clampf(drop_damage_chance_cap,0.0,1.0))


func _drop_count_for_damage(actual_health_damage:float) -> int:
	var damage_value:float = maxf(actual_health_damage,0.0)
	var step_damage:float = maxf(drop_damage_per_extra_item,1.0)
	var max_items:int = maxi(drop_max_items_per_hit,1)

	# 每 step_damage 点伤害稳定增加 1 个物品；不足一整档的余数再按比例掷一次额外物品。
	# 因此数量随伤害平滑增长，而不是跨阈值突然跳很多。
	var extra_progress:float = damage_value / step_damage
	var guaranteed_extra:int = int(floor(extra_progress))
	var fractional_extra:float = extra_progress - float(guaranteed_extra)
	var count:int = 1 + guaranteed_extra
	if count < max_items and randf() < fractional_extra:
		count += 1
	return clampi(count,1,max_items)


func _spawn_random_drop() -> void:
	_drop_serial += 1
	var kind:int = _roll_drop_kind()
	var angle:float = randf_range(0.0,TAU)
	var distance:float = randf_range(minf(drop_ground_distance_min,drop_ground_distance_max),maxf(drop_ground_distance_min,drop_ground_distance_max))
	var target_ground:Vector2 = global_position + Vector2.from_angle(angle) * distance
	var spin_abs:float = randf_range(minf(drop_spin_speed_min,drop_spin_speed_max),maxf(drop_spin_speed_min,drop_spin_speed_max))
	var spin_speed:float = spin_abs * (-1.0 if randf() < 0.5 else 1.0)
	var drop_runtime_seed:int = Game.battle_rng_seed_or("scripts/characters/领导.gd:drop_id",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	var config:Dictionary = {
		"id": "leader_drop_%d_%d" % [_drop_serial,drop_runtime_seed],
		"kind": kind,
		"start": global_position,
		"ground": target_ground,
		"arc_duration": drop_arc_duration,
		"arc_height": randf_range(minf(drop_arc_height_min,drop_arc_height_max),maxf(drop_arc_height_min,drop_arc_height_max)),
		"pickup_radius": drop_pickup_radius,
		"pickup_grace": drop_pickup_grace,
		"boundary_bounce": drop_boundary_bounce,
		"spin_speed": spin_speed,
		"team": Team,
		"return_speed": hostile_item_return_speed,
	}
	_call_spawn_drop(config)


func _clamp_drop_to_map(point:Vector2) -> Vector2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return point
	var map_group_value:Variant = world.get("map_group")
	var map_index:int = int(world.get("now_choose_map"))
	if not (map_group_value is Array) or map_index < 0 or map_index >= (map_group_value as Array).size():
		return point
	var map_node:Variant = (map_group_value as Array)[map_index]
	if not (map_node is TileMapLayer):
		return point
	var rect:Rect2 = world.call("return_map_world_rect",map_node)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return point
	return Vector2(
		clampf(point.x,rect.position.x + 8.0,rect.end.x - 8.0),
		clampf(point.y,rect.position.y + 8.0,rect.end.y - 8.0)
	)


func _roll_drop_kind() -> int:
	var w_coin:float = maxf(coin_weight,0.0)
	var w_key:float = maxf(car_key_weight,0.0)
	var w_deed:float = maxf(property_deed_weight,0.0)
	var total:float = w_coin + w_key + w_deed
	if total <= 0.0001:
		return 0
	var roll:float = randf() * total
	if roll < w_coin:
		return 0
	if roll < w_coin + w_key:
		return 1
	return 2


func _heal_for_kind(kind:int) -> float:
	match kind:
		0: return coin_heal
		1: return car_key_heal
		_: return property_deed_heal


func _hostile_damage_for_kind(kind:int) -> float:
	return enemy_coin_damage if kind == 0 else enemy_car_key_damage


func _on_drop_picked(drop_id:String,kind:int,picker:ball) -> void:
	if not is_multiplayer_authority() or picker == null or not is_instance_valid(picker):
		return
	if picker.health <= 0:
		return
	var allied:bool = Team != "" and picker.Team != "" and picker.Team == Team
	if picker == self or allied:
		picker.heal(_heal_for_kind(kind))
		_call_resolve_drop(drop_id,"heal",picker.get_path())
		return

	if kind == 2:
		_call_resolve_drop(drop_id,"property",picker.get_path())
		_spawn_property_unit_for_enemy(picker)
		return

	_call_resolve_drop(drop_id,"hostile_return",picker.get_path())


func _on_hostile_drop_arrived(kind:int,picker_value:Variant = null) -> void:
	# V348：回飞可能持续数百毫秒，原拾取者这期间可能已经死亡并被 queue_free。
	# 参数不再声明为 ball，避免 Godot 在函数体执行前就因为 “previously freed” 对象无法转成 ball 而报错。
	if not is_multiplayer_authority() or health <= 0:
		return
	var picker:ball = null
	if picker_value is ball and is_instance_valid(picker_value):
		picker = picker_value as ball
	var source:Node = picker
	var amount:float = _hostile_damage_for_kind(kind)
	if amount <= 0.0:
		return

	# 第一层：物品本身撞到领导的材质/物件声音仍然保留。
	var cue:int = LeaderAudioCue.DROP_COIN_HIT if kind == 0 else LeaderAudioCue.DROP_OBJECT_HIT
	_call_leader_audio(cue,global_position)

	# 第二层：只有这一撞真正扣到领导生命值时，再追加项目通用 balls_hit1 碰撞伤害声。
	# 这样纯格挡、无敌或伤害被拒绝时不会假播“受伤”。
	var before_health:float = float(health)
	_suppress_drop_trigger = true
	var accepted:bool = receive_spatial_damage(
		amount,
		{"point":global_position,"source":source},
		true,
		false
	)
	_suppress_drop_trigger = false

	var actual_health_damage:float = maxf(before_health - float(health),0.0)
	if accepted and actual_health_damage > 0.0:
		_call_drop_collision_damage_audio(actual_health_damage,global_position)


func _spawn_property_unit_for_enemy(picker:ball) -> void:
	_property_unit_serial += 1
	var valid_picker:bool = picker != null and is_instance_valid(picker)
	var spawn_pos:Vector2 = picker.global_position if valid_picker else global_position + Vector2(40.0,0.0)
	# V322：房产证不再生成“只追领导、领导死就跑路”的脚本对象。
	# 现在生成真正的 ball 角色“愤怒的人”，固定200HP，并继承实际捡到房产证角色的 Team。
	var property_runtime_seed:int = Game.battle_rng_seed_or("scripts/characters/领导.gd:property_id",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	var config:Dictionary = {
		"id": "leader_property_%d_%d" % [_property_unit_serial,property_runtime_seed],
		"origin": spawn_pos,
		# V349：team 是“拾取房产证瞬间”的固定阵营快照；
		# summoner_leader_path 单独记录这张房产证来自哪一个领导。
		# Master 仍然属于 picker，不能拿领导当 Master，否则敌我阵营又会错。
		"team": picker.Team if valid_picker else "",
		"picker_path": picker.get_path() if valid_picker else NodePath(),
		"summoner_leader_path": get_path() if is_inside_tree() else NodePath(),
		"speed": property_unit_speed,
		"attack_interval": property_unit_attack_interval,
		"damage": maxf(float(Damage) * property_unit_damage_multiplier,1.0),
		"knockback_distance": property_unit_knockback_distance,
		"knockback_speed": property_unit_knockback_speed,
	}
	_call_spawn_property_unit(config)


func _call_drop_collision_damage_audio(actual_damage:float,world_pos:Vector2) -> void:
	if not is_multiplayer_authority() or actual_damage <= 0.0:
		return
	# 与项目其它“碰撞伤害真正扣到生命值”保持同一个 balls_hit1 语义。
	# 音量随本次真实生命损失提高，但最高不超过 0 dB。
	var volume_db:float = clampf(actual_damage - 12.0,-18.0,0.0)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_drop_collision_damage_audio.rpc(world_pos,volume_db)
	else:
		_rpc_play_drop_collision_damage_audio(world_pos,volume_db)


@rpc("authority","call_local","reliable")
func _rpc_play_drop_collision_damage_audio(world_pos:Vector2,volume_db:float) -> void:
	# DOCUMENT_HIT_SFX 本身就是 res://audio/sfx/physics/balls_hit1.sfxr。
	# 单独创建 AudioStreamPlayer2D，让它可以与金币/铁棍撞击声同时播放，不互相截断。
	_play_positional_stream(DOCUMENT_HIT_SFX,world_pos,volume_db,1350.0)


func _call_document_hit_audio(world_pos:Vector2) -> void:
	_call_leader_audio(LeaderAudioCue.DOCUMENT_HIT,world_pos)


func _call_property_fist_swing_audio(world_pos:Vector2) -> void:
	_call_leader_audio(LeaderAudioCue.PROPERTY_FIST_SWING,world_pos)


func _call_property_fist_hit_audio(world_pos:Vector2) -> void:
	_call_leader_audio(LeaderAudioCue.PROPERTY_FIST_HIT,world_pos)


func _call_leader_audio(cue:int,world_pos:Vector2) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_play_leader_audio.rpc(cue,world_pos)
	else:
		_rpc_play_leader_audio(cue,world_pos)


@rpc("authority","call_local","unreliable")
func _rpc_play_leader_audio(cue:int,world_pos:Vector2) -> void:
	var stream:AudioStream = null
	var volume_db:float = -2.0
	match cue:
		LeaderAudioCue.DOCUMENT_THROW:
			stream = DOCUMENT_THROW_SFX
			volume_db = 3.0
		LeaderAudioCue.DOCUMENT_HIT:
			stream = DOCUMENT_HIT_SFX
			volume_db = -4.0
		LeaderAudioCue.DROP_COIN_HIT:
			stream = DROP_COIN_HIT_SFX
			volume_db = 0.0
		LeaderAudioCue.DROP_OBJECT_HIT:
			stream = DROP_OBJECT_HIT_SFX
			volume_db = -1.0
		LeaderAudioCue.PROPERTY_FIST_SWING:
			stream = PROPERTY_FIST_SWING_SFX
			volume_db = -2.0
		LeaderAudioCue.PROPERTY_FIST_HIT:
			stream = PROPERTY_FIST_HIT_SFX
			volume_db = 0.0
	if stream == null:
		return
	_play_positional_stream(stream,world_pos,volume_db,1350.0)


func _play_positional_stream(stream:AudioStream,world_pos:Vector2,volume_db:float,max_distance:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = max_distance
	player.attenuation = 0.48
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	_runtime_container().add_child(player,true)
	player.global_position = world_pos
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _next_runtime_id(prefix:String) -> String:
	var runtime_seed:int = Game.battle_rng_seed_or("scripts/characters/领导.gd:runtime_id:" + prefix,int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	return "%s_%s" % [prefix,str(runtime_seed)]


func _runtime_container() -> Node:
	var world:Node = get_tree().current_scene
	if world == null:
		return self
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func _call_spawn_document(config:Dictionary) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_document.rpc(config)
	else:
		_rpc_spawn_document(config)


@rpc("authority","call_local","reliable")
func _rpc_spawn_document(config:Dictionary) -> void:
	var node:Node = DOCUMENT_SCENE.instantiate()
	node.name = "领导处分文件_" + str(config.get("id","0"))
	_runtime_container().add_child(node,true)
	if node.has_method("configure"):
		node.call("configure",self,config,is_multiplayer_authority())


func _call_spawn_drop(config:Dictionary) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_drop.rpc(config)
	else:
		_rpc_spawn_drop(config)


@rpc("authority","call_local","reliable")
func _rpc_spawn_drop(config:Dictionary) -> void:
	# V347：这个 RPC 可能从 ball.health setter 的真实受伤钩子触发，
	# 而该钩子又可能正处在 Godot PhysicsServer 的 query flush 内。
	# V346 在这里立即 add_child(CharacterBody2D) 并随后修改 CollisionShape2D.shape，
	# 会触发 “Can't change this state while flushing queries”。
	# 整个实例化/入树/配置链延迟到安全阶段，而不是只延迟某一个碰撞属性。
	call_deferred("_spawn_drop_after_physics",config.duplicate(true))


func _spawn_drop_after_physics(config:Dictionary) -> void:
	if not is_inside_tree():
		return
	var container:Node = _runtime_container()
	if container == null or not is_instance_valid(container):
		return
	var node:Node = DROP_SCENE.instantiate()
	node.name = "领导掉落_" + str(config.get("id","0"))
	container.add_child(node,true)
	if node.has_method("configure"):
		node.call("configure",self,config,is_multiplayer_authority())


func _call_resolve_drop(drop_id:String,resolution:String,picker_path:NodePath) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_resolve_drop.rpc(drop_id,resolution,picker_path)
	else:
		_rpc_resolve_drop(drop_id,resolution,picker_path)


@rpc("authority","call_local","reliable")
func _rpc_resolve_drop(drop_id:String,resolution:String,picker_path:NodePath) -> void:
	var container:Node = _runtime_container()
	var drop:Node = container.get_node_or_null("领导掉落_" + drop_id)
	if drop == null or not drop.has_method("resolve_pickup"):
		return
	var picker:Node = get_node_or_null(picker_path) if not picker_path.is_empty() else null
	drop.call("resolve_pickup",resolution,picker)


func _call_remove_runtime_node(node_name:String) -> void:
	if node_name.is_empty():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_remove_runtime_node.rpc(node_name)
	else:
		_rpc_remove_runtime_node(node_name)


@rpc("authority","call_local","reliable")
func _rpc_remove_runtime_node(node_name:String) -> void:
	var container:Node = _runtime_container()
	var node:Node = container.get_node_or_null(node_name)
	if node != null and is_instance_valid(node):
		node.queue_free()


func _call_spawn_property_unit(config:Dictionary) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_property_unit.rpc(config)
	else:
		_rpc_spawn_property_unit(config)


@rpc("authority","call_local","reliable")
func _rpc_spawn_property_unit(config:Dictionary) -> void:
	# 房产证拾取发生在掉落物 _physics_process 内；和 V347 掉落生成同理，
	# 不在物理查询阶段直接把新的 ball 加入场景树。
	call_deferred("_spawn_property_unit_after_physics",config.duplicate(true))


func _spawn_property_unit_after_physics(config:Dictionary) -> void:
	if not is_inside_tree():
		return
	var container:Node = _runtime_container()
	if container == null or not is_instance_valid(container):
		return

	var node:Node = PROPERTY_UNIT_SCENE.instantiate()
	node.name = "愤怒的人_" + str(config.get("id","0"))

	# V348：config["team"] 是 authority 在“拾到房产证那一刻”记录的阵营快照，
	# 即使某一客户端稍后暂时解析不到 picker_path，也必须先使用这份 Team，不允许回落到场景默认 "Ball"。
	var deed_team:String = str(config.get("team",""))
	var picker_path:NodePath = config.get("picker_path",NodePath())
	var picker:ball = null
	if not picker_path.is_empty():
		var candidate:Node = get_node_or_null(picker_path)
		if candidate is ball and is_instance_valid(candidate):
			picker = candidate as ball

	if node is ball:
		var summoned:ball = node as ball
		summoned.Team = deed_team
		summoned.Master_name = str(picker_path)
		if picker != null:
			summoned.Master = picker

	# 先把愤怒的人脚本自己的“房产证身份快照”写好，再触发 _ready()。
	if node.has_method("prime_property_deed_identity"):
		node.call("prime_property_deed_identity",config,picker)

	node.set_multiplayer_authority(get_multiplayer_authority(),true)
	container.add_child(node,true)

	if node.has_method("configure_from_property_deed"):
		node.call("configure_from_property_deed",config)

	# 入树后再写一次，抵消任何 ready/同步初始化期间的临时默认值。
	if node is ball:
		var summoned_after:ball = node as ball
		summoned_after.Team = deed_team
		summoned_after.Master_name = str(picker_path)
		if picker != null and is_instance_valid(picker):
			summoned_after.Master = picker
