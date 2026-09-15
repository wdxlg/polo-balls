extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const Z_PROJECTILE_SCRIPT = preload("res://scripts/effects/投稿/疲倦Z.gd")
const ANGRY_FORM:PackedScene = preload("res://scenes/characters/人物/形态/疲倦的人_愤怒形态.tscn")
const SAD_FORM:PackedScene = preload("res://scenes/characters/人物/形态/疲倦的人_悲伤形态.tscn")

const TEX_TIRED:Texture2D = preload("res://Images/characters/人物/疲倦的人/睡眼惺忪的晨间伸展男士.png")
const TEX_ASLEEP:Texture2D = preload("res://Images/characters/人物/疲倦的人/蓝色睡衣男子安睡在白色枕被间.png")
const SFX_YAWN:AudioStream = preload("res://audio/characters/疲倦的人/哈欠(1).mp3")
const SFX_SNORE:AudioStream = preload("res://audio/characters/疲倦的人/打呼噜(1).mp3")

@export_category("疲倦的人")
@export_range(0.2,10.0,0.1) var fall_asleep_delay:float = 2.8
@export_range(40.0,140.0,1.0) var sleeping_move_speed:float = 90.0
@export_range(80.0,260.0,1.0) var tired_visual_height:float = 185.0
@export_range(100.0,1200.0,10.0) var z_speed:float = 360.0
@export_range(1.0,20.0,0.5) var z_hit_radius:float = 7.0
@export_range(6.0,64.0,1.0) var z_spawn_forward:float = 34.0
@export_range(-20.0,20.0,1.0) var z_spawn_vertical:float = 0.0
@export_range(2.0,35.0,0.5) var z_spread_degrees:float = 13.0
@export_range(0.02,0.5,0.01) var z_shot_gap:float = 0.14
@export_range(100.0,1200.0,10.0) var target_range:float = 720.0

@export_category("疲倦的人 - 音效")
@export_range(-36.0,12.0,0.5) var yawn_volume_db:float = 1.0
@export_range(-36.0,12.0,0.5) var snore_volume_db:float = -1.0
@export_range(120.0,2400.0,20.0) var tired_sfx_max_distance:float = 900.0
@export_range(0.05,2.0,0.05) var tired_sfx_attenuation:float = 0.75

var _sleep_left:float = 0.0
var _asleep:bool = false
var _firing:bool = false
var _resurrection_started:bool = false
var _sleep_label:Label = null
var _opening_yawn_played:bool = false
var _yawn_player:AudioStreamPlayer2D = null
var _snore_player:AudioStreamPlayer2D = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/人物/疲倦的人.gd:_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	Type = Ball_Type.Ball
	# V399：睡眠形态生命统一为 250。该角色睡前/睡后是同一实例，因此在 super._ready() 前写入，
	# 确保公共 ball 初始化 health/default_properties 时就使用新上限。
	Max_health = 250
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	# V394：疲惫状态使用中等移速；睡着后继续保持完全相同的移动速度。
	Speed = sleeping_move_speed
	_sleep_left = maxf(fall_asleep_delay,0.0)
	super._ready()
	if default_properties != null:
		default_properties["Speed"] = sleeping_move_speed
		default_properties["Damage"] = Damage
		default_properties["Max_health"] = Max_health
	_setup_sleep_label()
	_ensure_tired_audio_players()
	_apply_sleep_visual(false)


func _process(_delta:float) -> void:
	_update_tired_audio_runtime()


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health > 0 and not _resurrection_started:
		if not _asleep and is_combat_runtime_active():
			_sleep_left = maxf(_sleep_left - delta,0.0)
			if _sleep_left <= 0.0:
				_fall_asleep()
	super.tick_physics(state,delta)

func _fall_asleep() -> void:
	if _asleep:
		return
	_asleep = true
	Can_Attack = true
	# V394：睡着只改变状态/视觉/攻击资格，不改变疲惫阶段已有的中等移动速度。
	if multiplayer.has_multiplayer_peer():
		_apply_sleep_visual_rpc.rpc(true)
	else:
		_apply_sleep_visual(true)


@rpc("authority","call_local","reliable")
func _apply_sleep_visual_rpc(asleep_value:bool) -> void:
	_apply_sleep_visual(asleep_value)


func _apply_sleep_visual(asleep_value:bool) -> void:
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		var texture_value:Texture2D = TEX_ASLEEP if asleep_value else TEX_TIRED
		sprite.texture = texture_value
		sprite.visible = true
		sprite.self_modulate = Color.WHITE
		var source_height:float = maxf(float(texture_value.get_height()),1.0)
		sprite.scale = Vector2.ONE * (tired_visual_height / source_height)
	if _sleep_label != null:
		_sleep_label.visible = asleep_value

func _setup_sleep_label() -> void:
	_sleep_label = Label.new()
	_sleep_label.name = "SleepZzz"
	_sleep_label.text = "Zzz"
	_sleep_label.position = Vector2(-24.0,-104.0)
	_sleep_label.z_index = 30
	_sleep_label.visible = false
	_sleep_label.add_theme_font_size_override("font_size",22)
	_sleep_label.add_theme_color_override("font_color",Color(0.82,0.92,1.0,0.96))
	_sleep_label.add_theme_color_override("font_shadow_color",Color(0.0,0.0,0.1,0.75))
	_sleep_label.add_theme_constant_override("shadow_offset_x",2)
	_sleep_label.add_theme_constant_override("shadow_offset_y",2)
	add_child(_sleep_label)

func Attack() -> void:
	if not is_multiplayer_authority() or not _asleep or _firing or health <= 0:
		Attacking = false
		return
	var target:ball = TOOLS.nearest_enemy(self,target_range)
	if target == null or not is_instance_valid(target):
		Attacking = false
		return

	# V402：恢复原本的锁定规则。整组三发只在攻击起手这一刻读取一次目标位置。
	# 后两发不会重新读取移动中的敌人，也不做速度预判；三发始终围绕同一条起手方向形成扇形。
	var target_snapshot:Vector2 = target.global_position
	var base_direction:Vector2 = target_snapshot - global_position
	if base_direction.length_squared() <= 0.000001:
		base_direction = Vector2.RIGHT
	base_direction = base_direction.normalized()
	_firing = true
	Attacking = true
	_play_snore_networked()
	_run_z_volley(base_direction)

func _run_z_volley(base_direction:Vector2) -> void:
	var spread:float = deg_to_rad(z_spread_degrees)
	_spawn_z(base_direction.rotated(-spread))
	await get_tree().create_timer(z_shot_gap,false).timeout
	if not _volley_valid():
		_finish_volley()
		return
	_spawn_z(base_direction)
	await get_tree().create_timer(z_shot_gap,false).timeout
	if not _volley_valid():
		_finish_volley()
		return
	_spawn_z(base_direction.rotated(spread))
	await get_tree().create_timer(0.05,false).timeout
	_finish_volley()

func _volley_valid() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and health > 0 and _asleep

func _finish_volley() -> void:
	_firing = false
	Attacking = false

func _spawn_z(direction_value:Vector2) -> void:
	if Z_PROJECTILE_SCRIPT == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var projectile:Node2D = Z_PROJECTILE_SCRIPT.new()
	# 先加入场景树再写 global_position，避免 current_scene 存在非单位 Transform 时，
	# 未入树 Node2D 的 global 坐标被当成本地坐标解释。
	world.add_child(projectile)
	var shot_direction:Vector2 = direction_value.normalized()
	if shot_direction.length_squared() <= 0.000001:
		shot_direction = Vector2.RIGHT
	# V394：旧版固定向上28px，贴上下墙时出生点可能直接落到墙边。
	# 现在沿实际射击方向向前推出，先离开人物占据区；真正飞到墙才正常销毁。
	var spawn_position:Vector2 = _safe_z_spawn_position(shot_direction)
	projectile.call(
		"setup",
		self,
		spawn_position,
		shot_direction * z_speed,
		attack_damage(),
		2.4,
		z_hit_radius
	)


func _safe_z_spawn_position(shot_direction:Vector2) -> Vector2:
	var desired:Vector2 = global_position + shot_direction * z_spawn_forward + Vector2(0.0,z_spawn_vertical)
	var world_2d:World2D = get_world_2d()
	if world_2d == null:
		return desired
	# 只检查地图层：如果人物真的正贴着一面位于射击方向上的墙，就不能把出生点硬塞到墙另一侧。
	# 没有墙时使用完整前推距离；有墙时停在墙前2px，随后第一帧会正常撞墙，而不是穿墙。
	var query := PhysicsRayQueryParameters2D.create(global_position,desired,1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit:Dictionary = world_2d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	var point:Vector2 = hit.get("position",global_position)
	return point - shot_direction * 2.0

# ================================
# V400 疲倦的人音效
# ================================
func _configure_tired_audio_player(player:AudioStreamPlayer2D,stream_value:AudioStream,volume_value:float) -> void:
	if player == null:
		return
	player.stream = stream_value
	player.volume_db = volume_value
	player.max_distance = maxf(tired_sfx_max_distance,50.0)
	player.attenuation = maxf(tired_sfx_attenuation,0.05)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"


func _ensure_tired_audio_players() -> void:
	if _yawn_player == null or not is_instance_valid(_yawn_player):
		_yawn_player = AudioStreamPlayer2D.new()
		_yawn_player.name = "TiredOpeningYawn"
		_configure_tired_audio_player(_yawn_player,SFX_YAWN,yawn_volume_db)
		add_child(_yawn_player)
	if _snore_player == null or not is_instance_valid(_snore_player):
		_snore_player = AudioStreamPlayer2D.new()
		_snore_player.name = "TiredAttackSnore"
		_configure_tired_audio_player(_snore_player,SFX_SNORE,snore_volume_db)
		add_child(_snore_player)


func _update_tired_audio_runtime() -> void:
	_ensure_tired_audio_players()
	var runtime_active:bool = health > 0 and is_combat_runtime_active()
	# 哈欠是开场音：布阵、SceneTree 暂停、Game.now_stop_state 或 time_scale=0 时都不启动。
	# 真正恢复战斗时间后的第一个处理帧才播放一次。
	if runtime_active and not _opening_yawn_played:
		_opening_yawn_played = true
		_yawn_player.stream_paused = false
		_yawn_player.play()
	if _yawn_player != null and is_instance_valid(_yawn_player) and _yawn_player.playing:
		_yawn_player.stream_paused = not runtime_active
	if _snore_player != null and is_instance_valid(_snore_player) and _snore_player.playing:
		_snore_player.stream_paused = not runtime_active


func _play_snore_networked() -> void:
	if multiplayer.has_multiplayer_peer():
		_play_snore_rpc.rpc()
	else:
		_play_snore_rpc()


@rpc("authority","call_local","unreliable")
func _play_snore_rpc() -> void:
	_ensure_tired_audio_players()
	if not is_combat_runtime_active() or health <= 0:
		return
	_snore_player.stream_paused = false
	_snore_player.stop()
	_snore_player.play()


func get_next_state(state:State) -> int:
	if health <= 0 and not _resurrection_started and is_multiplayer_authority():
		_begin_resurrection()
		return -1
	if _resurrection_started:
		return -1
	return super.get_next_state(state)

func _begin_resurrection() -> void:
	if _resurrection_started:
		return
	_resurrection_started = true
	_firing = false
	Attacking = false
	Using_Skill = false
	Can_Attack = false
	Can_Skill = false
	Speed = 0.0
	# 在替身真正加入场景树前暂时保持 1HP，避免胜负系统在中间一帧把本方判定为消失。
	health = 1
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred(&"disabled",true)
	if self_hitbox != null:
		self_hitbox.set_deferred(&"monitoring",false)
	if self_hurtbox != null:
		self_hurtbox.set_deferred(&"monitorable",false)
	call_deferred("_spawn_resurrection_form")

func _spawn_resurrection_form() -> void:
	if not is_inside_tree() or not is_multiplayer_authority():
		return
	var use_angry:bool = _rng.randf() < 0.5
	var packed:PackedScene = ANGRY_FORM if use_angry else SAD_FORM
	var instance:Node = packed.instantiate()
	if not instance is ball:
		if instance != null:
			instance.queue_free()
		queue_free()
		return
	var form:ball = instance as ball
	form.Team = Team
	form.Master = Master if Master != null and is_instance_valid(Master) else null
	form.Master_name = Master_name
	if not str(Team).strip_edges().is_empty():
		form.set_meta(&"forced_combat_team",Team)
	form.global_position = global_position
	_copy_battle_identity(form,"愤怒的男人" if use_angry else "悲伤的男人")
	var world:Node = get_tree().current_scene
	if world == null:
		form.queue_free()
		queue_free()
		return
	world.add_child(form,true)
	queue_free()

func _copy_battle_identity(form:ball,display_name:String) -> void:
	for key:StringName in [
		&"victory_side_key",
		&"battle_setup_id",
		&"continuation_side_key",
		&"dice_enemy_copy",
		&"dice_self_copy"
	]:
		if has_meta(key):
			form.set_meta(key,get_meta(key))

	var team_name:String = str(Team).strip_edges()
	var victory_key:String = ""
	if has_meta(&"battle_continuation_victory_side_key"):
		victory_key = str(get_meta(&"battle_continuation_victory_side_key","")).strip_edges()
	if victory_key.is_empty() and has_meta(&"victory_side_key"):
		victory_key = str(get_meta(&"victory_side_key","")).strip_edges()
	if victory_key.is_empty() and not team_name.is_empty():
		victory_key = "team:" + team_name
	if victory_key.is_empty() and has_meta(&"battle_setup_id"):
		victory_key = "solo_setup:" + str(int(get_meta(&"battle_setup_id")))
	if victory_key.is_empty():
		victory_key = "solo_instance:" + str(get_instance_id())

	# 只有玩家实际放下的主角色（或本来就已经是 continuation 的角色）需要在变身期间
	# 继续占住 VS/胜负席位。若疲倦的人本身是掷骰子复制出的召唤物，则新形态仍作为
	# 普通召唤物挂在原 Master 下，不能凭空出现在 VS 顶部。
	var was_runtime_summon:bool = (Master != null and is_instance_valid(Master)) or not Master_name.is_empty()
	var had_continuation:bool = has_meta(&"battle_continuation_victory_side_key")
	if not was_runtime_summon or had_continuation:
		var presentation_key:String = "team:" + team_name if not team_name.is_empty() else "solo:" + str(get_instance_id())
		if has_meta(&"battle_continuation_presentation_side_key"):
			var inherited_presentation:String = str(get_meta(&"battle_continuation_presentation_side_key","")).strip_edges()
			if not inherited_presentation.is_empty():
				presentation_key = inherited_presentation
		form.set_meta(&"battle_continuation_victory_side_key",victory_key)
		form.set_meta(&"battle_continuation_presentation_side_key",presentation_key)
		form.set_meta(&"battle_continuation_display_name",display_name)
	form.set_meta(&"tired_person_resurrection_form",true)
