extends ball

const NATIVE_MODEL_ANIMATION = preload("res://scripts/effects/我的世界/mc_native_batch2.gd")
var _native_mob_animation:Node

const BODY_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/蠹虫/本体.webp")
const STONE_FIELD_SCRIPT:Script = preload("res://scripts/effects/我的世界/蠹虫石砖场.gd")
const DEATH_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")

const HISS_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/蠹虫/嘶嘶.ogg"),
	preload("res://audio/characters/我的世界/蠹虫/嘶嘶2.ogg"),
	preload("res://audio/characters/我的世界/蠹虫/嘶嘶3.ogg"),
]
const FOOTSTEP_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/蠹虫/脚步.ogg"),
	preload("res://audio/characters/我的世界/蠹虫/脚步2.ogg"),
	preload("res://audio/characters/我的世界/蠹虫/脚步3.ogg"),
]
const DEATH_SOUND:AudioStream = preload("res://audio/characters/我的世界/蠹虫/死亡.ogg")

const FIELD_GROUP:StringName = &"MinecraftSilverfishStoneField"
const SILVERFISH_GROUP:StringName = &"MinecraftSilverfish"
const DEATH_POSE_DURATION:float = 0.90
const DAMAGE_STONE_TRIGGER_COOLDOWN:float = 0.24
const MAX_ACTIVE_SILVERFISH:int = 10
const DEATH_BRIDGE_ACTIVE_META:StringName = &"battle_death_bridge_active"
const DEATH_BRIDGE_VICTORY_META:StringName = &"battle_death_bridge_victory_side_key"
const DEATH_BRIDGE_PRESENTATION_META:StringName = &"battle_death_bridge_presentation_side_key"
const DEATH_BRIDGE_DISPLAY_META:StringName = &"battle_death_bridge_display_name"

@onready var hiss_audio:AudioStreamPlayer2D = $HissAudio
@onready var footstep_audio:AudioStreamPlayer2D = $FootstepAudio
@onready var death_audio:AudioStreamPlayer2D = $DeathAudio

var _rng := RandomNumberGenerator.new()
var _hiss_time_left:float = 1.0
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
# 按基础速度行走时的脚步间隔；实际间隔随当前移速缩放（越快越密、越慢越稀，可与上一声重叠）。
@export var footstep_base_interval:float = 0.61
var _footstep_cadence = FOOTSTEP.new()
var _footstep_overlaps:Array[AudioStreamPlayer2D] = []
var _audio_last_position:Vector2 = Vector2.ZERO
var _stone_trigger_cooldown_left:float = 0.0
var _stone_field:Node = null
var _death_sequence_started:bool = false
var _death_visual_started_local:bool = false


func _ready() -> void:
	# 玩法定位：低血量、中等移动、中等碰撞伤害；没有普通攻击或主动技能。
	Has_Collision_Damage = true
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	if image is Sprite2D:
		(image as Sprite2D).texture = BODY_TEXTURE
		(image as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	super._ready()
	_native_mob_animation = NATIVE_MODEL_ANIMATION.attach(self,"silverfish")
	# 每次真实受伤均保留跳字，不能被全场其他跳字挤掉。
	if health_bar != null:
		health_bar.max_live_damage_texts = 0
	add_to_group(SILVERFISH_GROUP)

	# 石砖孵化个体在 add_child() 前已写入稳定的比赛阵营键。
	# 再镜像到既有 victory_side_key，确保原始本体先死亡/释放后仍被胜负系统识别为同一方。
	if has_meta(&"battle_continuation_victory_side_key"):
		var continuation_key:String = str(get_meta(&"battle_continuation_victory_side_key","")).strip_edges()
		if not continuation_key.is_empty():
			set_meta(&"victory_side_key",continuation_key)

	# V80：这是全地图硬上限，不只限制石砖孵化；手动放置/其它来源生成第 11 只也会被 authority 拒绝。
	if _count_active_silverfish() > MAX_ACTIVE_SILVERFISH:
		if is_multiplayer_authority():
			call_deferred("_remove_over_cap_silverfish")
		return

	_rng.seed = Game.battle_rng_seed_or("scripts/characters/我的世界/蠹虫.gd:_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1))
	_audio_last_position = global_position
	_hiss_time_left = _rng.randf_range(0.85,2.0)
	_footstep_cadence.ready_now()

	_stone_field = _ensure_stone_field()
	if _stone_field != null and is_instance_valid(_stone_field) and _stone_field.has_method("register_silverfish"):
		_stone_field.call("register_silverfish",get_instance_id())


func _count_active_silverfish() -> int:
	var count:int = 0
	for node:Node in get_tree().get_nodes_in_group(SILVERFISH_GROUP):
		if node is ball and (node as ball).health > 0:
			count += 1
	return count


func _stable_victory_side_key(candidate:ball) -> String:
	if candidate == null or not is_instance_valid(candidate):
		return ""
	# 孵化个体已经带有冻结的 continuation key，优先使用。
	if candidate.has_meta(&"battle_continuation_victory_side_key"):
		var continuation:String = str(candidate.get_meta(&"battle_continuation_victory_side_key","")).strip_edges()
		if not continuation.is_empty():
			return continuation
	if candidate.has_meta(DEATH_BRIDGE_VICTORY_META):
		var bridged:String = str(candidate.get_meta(DEATH_BRIDGE_VICTORY_META,"")).strip_edges()
		if not bridged.is_empty():
			return bridged

	# 无 Team 的手动对战中，原角色和它孵化出的蠹虫仍必须属于同一方。
	# battle_setup_id 比空 Team 更稳定，也优先于 world 里可能残留的旧 victory_side_key。
	if candidate.has_meta(&"battle_setup_id"):
		return "solo_setup:" + str(int(candidate.get_meta(&"battle_setup_id")))

	if candidate.has_meta(&"victory_side_key"):
		var cached:String = str(candidate.get_meta(&"victory_side_key","")).strip_edges()
		if not cached.is_empty():
			return cached

	var forced_team:String = ""
	if candidate.has_meta(&"forced_combat_team"):
		forced_team = str(candidate.get_meta(&"forced_combat_team","")).strip_edges()
	if not forced_team.is_empty() and forced_team != "Ball":
		return "team:" + forced_team

	var team_name:String = str(candidate.Team).strip_edges()
	if not team_name.is_empty() and team_name != "Ball":
		return "team:" + team_name

	# 最后的回退只用于尚未被 World 记录 setup_id 的极端动态实例。
	return "solo_instance:" + str(candidate.get_instance_id())


func _stable_presentation_side_key(candidate:ball) -> String:
	if candidate == null or not is_instance_valid(candidate):
		return ""
	if candidate.has_meta(&"battle_continuation_presentation_side_key"):
		var inherited:String = str(candidate.get_meta(&"battle_continuation_presentation_side_key","")).strip_edges()
		if not inherited.is_empty():
			return inherited
	if candidate.has_meta(DEATH_BRIDGE_PRESENTATION_META):
		var bridged:String = str(candidate.get_meta(DEATH_BRIDGE_PRESENTATION_META,"")).strip_edges()
		if not bridged.is_empty():
			return bridged
	var team_name:String = str(candidate.Team).strip_edges()
	if not team_name.is_empty() and team_name != "Ball":
		return "team:" + team_name
	return "solo:" + str(candidate.get_instance_id())


func can_receive_hit_contact(incoming_hit:hitbox,_hurt:hurtbox) -> bool:
	# V83：同一窝/同一比赛阵营的蠹虫永远不互相造成碰撞伤害。
	# 这条保护独立于全局 Have_Team_Damage，专门解决“无 Team 的原蠹虫 + 孵化蠹虫”
	# 在有敌人后开始追逐、彼此挤撞时互伤的问题；实体碰撞/推挤仍然保留。
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return true
	var attacker_node:Node = incoming_hit.get_parent()
	if not (attacker_node is ball):
		return true
	var attacker:ball = attacker_node as ball
	if attacker == self:
		return false
	if not attacker.is_in_group(SILVERFISH_GROUP):
		return true
	var my_side:String = _stable_victory_side_key(self)
	var attacker_side:String = _stable_victory_side_key(attacker)
	if not my_side.is_empty() and my_side == attacker_side:
		return false
	return true


func _arm_death_bridge() -> void:
	# 胜负/UI 以“死亡演出结束、节点真正退场”为这一方可能消失的最早时刻。
	# 这样 HP 归零到 0.90s 红色翻转结束之间不会先响铃；若死亡触发裂纹砖孵化，
	# 新蠹虫会在 0.18s 石砖震动结束后接棒，整个过程中阵营不会出现一帧空窗。
	set_meta(DEATH_BRIDGE_ACTIVE_META,true)
	set_meta(DEATH_BRIDGE_VICTORY_META,_stable_victory_side_key(self))
	set_meta(DEATH_BRIDGE_PRESENTATION_META,_stable_presentation_side_key(self))
	set_meta(DEATH_BRIDGE_DISPLAY_META,"蠹虫")


func _remove_over_cap_silverfish() -> void:
	if is_instance_valid(self) and is_inside_tree() and is_multiplayer_authority():
		Game.free_node(self)


func _exit_tree() -> void:
	# V177：自然死亡的蠹虫真正离开 SceneTree 后，通知 World 在下一帧复核这一方是否已经彻底断代。
	# 不能在 HP 归零时就判胜：死亡石砖仍可能在演出期间孵化同阵营的新蠹虫。
	var victory_recheck_side:String = ""
	if _death_sequence_started or health <= 0:
		victory_recheck_side = _stable_victory_side_key(self)

	if _stone_field != null and is_instance_valid(_stone_field) and _stone_field.has_method("unregister_silverfish"):
		_stone_field.call("unregister_silverfish",get_instance_id())

	if not victory_recheck_side.is_empty():
		var world:Node = get_tree().current_scene if get_tree() != null else null
		if world != null and is_instance_valid(world) and world.has_method("request_silverfish_extinction_victory_recheck"):
			world.call_deferred("request_silverfish_extinction_victory_recheck",victory_recheck_side)


func get_preview_texture() -> Texture2D:
	return BODY_TEXTURE


# 纯碰撞伤害角色：主动攻击/技能状态永远立即结束。
func Attack() -> void:
	Attacking = false


func Skill() -> void:
	Using_Skill = false


func tick_physics(state:State,delta:float) -> void:
	_stone_trigger_cooldown_left = maxf(_stone_trigger_cooldown_left - delta,0.0)
	super.tick_physics(state,delta)

	if _death_visual_started_local:
		_audio_last_position = global_position
		return
	_update_living_audio(delta)


func _update_living_audio(delta:float) -> void:
	# 使用跨帧真实位置差分，所以 authority 与收到同步位置的远端都能判断“正在移动”。
	var moved_distance:float = global_position.distance_to(_audio_last_position)
	_audio_last_position = global_position
	var moving:bool = moved_distance > 0.18 and health > 0

	_hiss_time_left -= delta
	if _hiss_time_left <= 0.0 and hiss_audio != null and not hiss_audio.playing:
		_play_random_hiss()

	# 脚步按当前实际移速计步：越快越密、越慢越稀；停下后下一次起步先响一声。
	if _footstep_cadence.tick(moved_distance if moving else 0.0,delta,FOOTSTEP.base_speed(self),footstep_base_interval):
		_play_random_footstep()


func _play_random_hiss() -> void:
	if HISS_SOUNDS.is_empty() or hiss_audio == null:
		return
	var stream:AudioStream = HISS_SOUNDS[_rng.randi_range(0,HISS_SOUNDS.size() - 1)]
	hiss_audio.stream = stream
	hiss_audio.pitch_scale = 1.0
	hiss_audio.play()
	# 下一声从“本声完整时长 + 随机静默”之后才允许开始，严格不会比当前嘶嘶声本身更短。
	_hiss_time_left = maxf(stream.get_length(),0.05) + _rng.randf_range(1.20,3.40)


func _play_random_footstep() -> void:
	if FOOTSTEP_SOUNDS.is_empty() or footstep_audio == null:
		return
	var stream:AudioStream = FOOTSTEP_SOUNDS[_rng.randi_range(0,FOOTSTEP_SOUNDS.size() - 1)]
	var player:AudioStreamPlayer2D = footstep_audio
	if footstep_audio.playing:
		# 跑得快时下一步可在上一声结束前开始：另开临时播放器叠加，播完自动释放。
		player = footstep_audio.duplicate() as AudioStreamPlayer2D
		add_child(player)
		player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
		_footstep_overlaps = _footstep_overlaps.filter(func(p:AudioStreamPlayer2D) -> bool: return is_instance_valid(p))
		_footstep_overlaps.append(player)
	player.stream = stream
	player.pitch_scale = 1.0
	player.play()


func on_actual_health_damage_received(actual_health_damage:float,_health_before:float) -> void:
	if actual_health_damage <= 0.0 or not is_inside_tree() or not is_multiplayer_authority():
		return
	# 致死一击只交给 Die() 的“死亡触发”，避免同一击先普通触发再强触发两遍。
	if health <= 0:
		return
	if _stone_trigger_cooldown_left > 0.0:
		return
	_stone_trigger_cooldown_left = DAMAGE_STONE_TRIGGER_COOLDOWN
	_emit_stone_reaction(false)


func _emit_stone_reaction(strong:bool) -> void:
	if not is_multiplayer_authority() or not is_inside_tree():
		return
	_stone_field = _ensure_stone_field()
	if _stone_field == null or not is_instance_valid(_stone_field):
		return

	# 全地图最多同时 10 只蠹虫。达到上限时连“第一段裂纹”都不触发，
	# 避免玩家看到砖已经裂/碎却因为人数上限没有新蠹虫。
	var remaining_slots:int = MAX_ACTIVE_SILVERFISH
	if _stone_field.has_method("get_remaining_silverfish_slots"):
		remaining_slots = int(_stone_field.call("get_remaining_silverfish_slots"))
	if remaining_slots <= 0:
		return

	var seed_value:int = Game.battle_rng_seed_or("scripts/characters/我的世界/蠹虫.gd:seed_value",int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(round(float(health) * 131.0)))
	seed_value = maxi(abs(seed_value),1)
	var event_position:Vector2 = global_position
	var source_name:String = str(name)
	var source_team:String = Team.strip_edges()

	# V81：把触发者名字与阵营一起交给石砖场。孵化蠹虫会把触发者写成 Master / Master_name，
	# 利用 ball.gd 已有的跨网络主人解析再次强制继承 Team，避免生成物在 peer 上掉回默认 "Ball" 阵营。
	if _stone_field.has_method("trigger_near"):
		_stone_field.call(
			"trigger_near",event_position,source_team,strong,seed_value,true,remaining_slots,source_name
		)
	if multiplayer.has_multiplayer_peer():
		_rpc_stone_reaction.rpc(event_position,source_team,strong,seed_value,remaining_slots,source_name)


@rpc("authority","call_remote","reliable")
func _rpc_stone_reaction(
	event_position:Vector2,
	team:String,
	strong:bool,
	seed_value:int,
	remaining_slots:int,
	source_name:String
) -> void:
	var field:Node = _ensure_stone_field()
	if field != null and is_instance_valid(field) and field.has_method("trigger_near"):
		field.call("trigger_near",event_position,team,strong,seed_value,false,remaining_slots,source_name)


func _ensure_stone_field() -> Node:
	if _stone_field != null and is_instance_valid(_stone_field):
		return _stone_field

	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var map_group_value:Variant = world.get("map_group")
	if not (map_group_value is Dictionary):
		return null
	var map_group:Dictionary = map_group_value as Dictionary
	var map_name:String = str(world.get("now_choose_map"))
	if not map_group.has(map_name):
		return null
	var map_value:Variant = map_group[map_name]
	# 普通 TileMapLayer 或多岛 PortalMap 都可以铺石砖；石砖场自己会把各岛格子归一到基准岛坐标。
	if not (map_value is TileMapLayer or map_value is PortalMap):
		return null
	var map_layer:Node = map_value as Node

	for node:Node in get_tree().get_nodes_in_group(FIELD_GROUP):
		if not is_instance_valid(node):
			continue
		if node.has_method("is_for_map") and bool(node.call("is_for_map",map_layer)):
			_stone_field = node
			return _stone_field

	# V81：World 会把所有 TileMapLayer.visible=false，只保留碰撞/导航。
	# CanvasItem 子节点会继承隐藏状态，所以 V79/V80 把石砖场挂在 map_layer 下必然不可见。
	# 现在改为直接挂到可见的 World，并让石砖场自己把 TileMap 坐标转换到世界坐标。
	var created:Node2D = STONE_FIELD_SCRIPT.new() as Node2D
	if created == null:
		return null
	world.add_child(created,true)
	if created.has_method("setup"):
		created.call("setup",world,map_layer)
	_stone_field = created
	return _stone_field


func _has_death_animation() -> bool:
	return true


func Die() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true

	# V83：先冻结这只蠹虫的比赛阵营，并把它作为“死亡演出桥”保留到节点真正退场。
	# 防止 HP 归零的这一帧就让 VS 消失/胜利铃提前响。
	_arm_death_bridge()

	# 保留公共死亡入口（击杀统计/通用音效钩子由父链负责）。
	super.Die()
	var death_position:Vector2 = global_position

	# 死亡、石砖反应和演出同步开始，不按目标序号延后。
	_emit_stone_reaction(true)
	_broadcast_death_visual(death_position)

	await get_tree().create_timer(DEATH_POSE_DURATION).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


func _broadcast_death_visual(death_position:Vector2,play_death_audio:bool = true) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_start_death_visual.rpc(death_position,play_death_audio)
	else:
		_rpc_start_death_visual(death_position,play_death_audio)


@rpc("authority","call_local","reliable")
func _rpc_start_death_visual(death_position:Vector2,play_death_audio:bool = true) -> void:
	if _death_visual_started_local:
		return
	_death_visual_started_local = true

	if hiss_audio != null:
		hiss_audio.stop()
	if footstep_audio != null:
		footstep_audio.stop()
	for extra:AudioStreamPlayer2D in _footstep_overlaps:
		if is_instance_valid(extra): extra.queue_free()
	_footstep_overlaps.clear()
	if play_death_audio and death_audio != null:
		death_audio.stream = DEATH_SOUND
		death_audio.pitch_scale = 1.0
		death_audio.play()

	if health_bar != null and is_instance_valid(health_bar):
		health_bar.hide()

	var graphics:Node2D = get_node_or_null("Graphics") as Node2D
	if graphics != null:
		# Minecraft 风格：死亡瞬间整体压成红色，并在死亡声期间翻转约 90°，让横向虫体“竖起来”。
		var rotate_sign:float = -1.0 if direction.x >= 0.0 else 1.0
		var tween:Tween = graphics.create_tween()
		tween.set_parallel(true)
		tween.tween_property(graphics,"modulate",Color(1.0,0.22,0.22,1.0),0.10)
		tween.tween_property(
			graphics,
			"rotation",
			graphics.rotation + rotate_sign * PI * 0.5,
			DEATH_POSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_create_delayed_death_smoke(death_position)


func _create_delayed_death_smoke(death_position:Vector2) -> void:
	var visual_parent:Node = _get_runtime_visual_parent()
	if visual_parent == null:
		return

	var smoke := AnimatedSprite2D.new()
	smoke.name = "蠹虫死亡烟雾"
	smoke.sprite_frames = DEATH_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 6
	smoke.scale = Vector2.ONE * 0.46
	smoke.visible = false
	visual_parent.add_child(smoke)
	smoke.global_position = death_position
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)

	# Smoke 节点先独立挂到地图静态子树；即使蠹虫随后被 MultiplayerSpawner 删除，延时仍能继续。
	var delayed:Tween = smoke.create_tween()
	delayed.tween_interval(DEATH_POSE_DURATION)
	delayed.tween_callback(Callable(smoke,"show"))
	delayed.tween_callback(Callable(smoke,"play").bind(&"死亡烟雾"))


func _get_runtime_visual_parent() -> Node:
	# V81：死亡烟雾不能再挂 TileMapLayer，因为 World 运行时明确把所有地图层 visible=false。
	# 优先挂到已经可见的石砖场；它的清理延迟长于死亡烟雾完整播放时间。
	_stone_field = _ensure_stone_field()
	if _stone_field != null and is_instance_valid(_stone_field):
		return _stone_field
	var world:Node = get_tree().current_scene
	if world != null:
		return world
	return null
