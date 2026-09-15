extends ball

# 赌徒的实弹继续直接复用军火商普通子弹：投射物贴图、命中/撞墙反馈与军火商一致。
const ARMS_DEALER_BULLET_SCENE:PackedScene = preload("res://scenes/shooter/军火商_子弹.tscn")

const GAMBLER_SHOOT_TEXTURE_PATH:String = "res://Images/characters/人物/赌徒/赌徒_射击.png"
const GAMBLER_RELOAD_TEXTURE_PATH:String = "res://Images/characters/人物/赌徒/赌徒_装填.png"
const GAMBLER_SELF_TEXTURE_PATH:String = "res://Images/characters/人物/赌徒/赌徒_自射.png"
const GAMBLER_CYLINDER_TEXTURE_PATH:String = "res://Images/characters/人物/赌徒/赌徒_转轮.png"
const GAMBLER_ROUND_TEXTURE_PATH:String = "res://Images/characters/人物/赌徒/赌徒_子弹.png"

const GAMBLER_FIRE_SFX:AudioStream = preload("res://audio/characters/赌徒/左轮射击.mp3")
const GAMBLER_RELOAD_SFX:AudioStream = preload("res://audio/characters/赌徒/装填.mp3")
const GAMBLER_DRY_SFX:AudioStream = preload("res://audio/characters/赌徒/卡壳.mp3")

const VISUAL_NORMAL:int = 0
const VISUAL_SHOOT:int = 1
const VISUAL_RELOAD:int = 2
const VISUAL_SELF:int = 3

const SFX_FIRE:int = 0
const SFX_RELOAD:int = 1
const SFX_DRY:int = 2

# 转轮原图约 625x628。下列位置是六个膛室相对图片中心的坐标。
# 索引顺序故意从右上开始，再逆时针排列；转轮每次顺时针转 60°，
# 下一索引就会正好转到右上装填/击发位置。
const CYLINDER_SLOT_POSITIONS:Array[Vector2] = [
	Vector2(108.0,-139.0), # 0 右上
	Vector2(-108.0,-139.0), # 1 左上
	Vector2(-199.0,18.0), # 2 左
	Vector2(-108.0,169.0), # 3 左下
	Vector2(108.0,169.0), # 4 右下
	Vector2(199.0,18.0), # 5 右
]

@export_category("俄罗斯轮盘")
@export_range(0,6,1) var chamber_count:int = 6
@export_range(0.0,10.0,0.05) var enemy_bullet_damage_multiplier:float = 1.0
@export_range(80.0,900.0,10.0) var bullet_speed:float = 520.0
@export_range(0.0,0.8,0.01) var trigger_interval:float = 0.0
@export_range(0.0,2.0,0.05) var opening_delay:float = 0.45
@export_range(0.5,10.0,0.1) var reload_pause:float = 3.2
@export_range(0.0,80.0,1.0) var muzzle_offset:float = 28.0

@export_category("赌徒 - 动作")
@export_range(0.08,0.8,0.01) var trigger_pose_duration:float = 0.24
@export_range(0.08,0.8,0.01) var reload_round_interval:float = 0.28

@export_category("赌徒 - 转轮显示")
@export var cylinder_visual_offset:Vector2 = Vector2(76.0,10.0)
@export_range(0.06,0.30,0.01) var cylinder_visual_scale:float = 0.13
@export_range(0.20,1.00,0.01) var cylinder_round_scale:float = 0.54
@export_range(0.02,0.40,0.01) var cylinder_turn_duration:float = 0.08

var _rng := RandomNumberGenerator.new()
var _cylinder:Array[bool] = []
var _visible_rounds:Array[bool] = []
var _cycle_running:bool = false
var _cycle_left:float = 0.0
var _loaded_live_rounds:int = 0
var _current_chamber:int = 0
var _cylinder_rotation_step:int = 0

var _default_texture:Texture2D = null
var _shoot_texture:Texture2D = null
var _reload_texture:Texture2D = null
var _self_texture:Texture2D = null

var _cylinder_visual_root:Node2D = null
var _cylinder_wheel:Sprite2D = null
var _cylinder_round_sprites:Array[Sprite2D] = []
var _local_visual_rotation_step:int = 0
var _cylinder_turn_tween:Tween = null
var _manual_control_action_busy:bool = false
var _manual_chambers_used:int = 6


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	super._ready()

	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_shoot_texture = _try_load_texture(GAMBLER_SHOOT_TEXTURE_PATH)
	_reload_texture = _try_load_texture(GAMBLER_RELOAD_TEXTURE_PATH)
	_self_texture = _try_load_texture(GAMBLER_SELF_TEXTURE_PATH)
	# 出场时直接处于装填状态，避免先闪出旧版正常立绘。
	_set_visual_state_local(VISUAL_RELOAD)
	_setup_cylinder_visual()

	# 赌徒右侧不再显示“轮盘/实弹/咔哒”等文字；右边只保留真正的转轮图形。
	if has_method("side_status_remove_permanent"):
		call("side_status_remove_permanent","right","gambler_cylinder")

	_rng.seed = Game.battle_rng_seed_or("scripts/characters/赌徒.gd:_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_cycle_left = maxf(opening_delay,0.0)


func has_collision_damage() -> bool:
	return false


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and state != State.Die and health > 0:
		if is_player_controlled():
			# V130：操控模式不再自动进入“对自己 -> 对敌五枪”的轮盘循环。
			# 已经开始的旧循环会在下一个 await 检查点自行退出。
			_cycle_left = maxf(_cycle_left,0.15)
		elif not _cycle_running:
			_cycle_left -= delta
			if _cycle_left <= 0.0:
				_cycle_running = true
				call_deferred("_run_roulette_cycle")
	super.tick_physics(state,delta)


func controlled_attack_action() -> void:
	if not is_multiplayer_authority() or not is_player_controlled() or _cycle_running or _manual_control_action_busy:
		return
	if health <= 0 or is_damage_output_disabled():
		return
	_manual_control_action_busy = true
	_prepare_manual_cylinder_if_needed()
	_set_visual_state_everywhere(VISUAL_SHOOT)
	_pull_trigger_on_enemy()
	await _advance_chamber()
	_manual_chambers_used += 1
	if is_instance_valid(self):
		_set_visual_state_everywhere(VISUAL_RELOAD if _manual_chambers_used >= 6 else VISUAL_SHOOT)
		_manual_control_action_busy = false


func controlled_skill_action() -> void:
	if not is_multiplayer_authority() or not is_player_controlled() or _cycle_running or _manual_control_action_busy:
		return
	if health <= 0 or is_damage_output_disabled():
		return
	_manual_control_action_busy = true
	_prepare_manual_cylinder_if_needed()
	_set_visual_state_everywhere(VISUAL_SELF)
	_pull_trigger_on_self()
	if is_instance_valid(self) and health > 0:
		await _advance_chamber()
		_manual_chambers_used += 1
	if is_instance_valid(self):
		_set_visual_state_everywhere(VISUAL_RELOAD if _manual_chambers_used >= 6 else VISUAL_SELF)
		_manual_control_action_busy = false


func _prepare_manual_cylinder_if_needed() -> void:
	if _manual_chambers_used < 6 and _cylinder.size() == 6:
		return
	_load_cylinder()
	_manual_chambers_used = 0
	# 手动模式不等待六段自动装填动画；一次装好并把真实子弹显示出来。
	for i:int in range(mini(_visible_rounds.size(),_cylinder.size())):
		_visible_rounds[i] = bool(_cylinder[i])
	_broadcast_cylinder_visual(false)


func _run_roulette_cycle() -> void:
	if not is_instance_valid(self) or health <= 0 or not is_multiplayer_authority() or is_player_controlled():
		_cycle_running = false
		return

	# 1) 切换到装填图，依次经过六个膛室。只有实际装入子弹的膛室才显示子弹并播放一次装填声。
	_load_cylinder()
	await _play_reload_sequence()
	if not is_instance_valid(self) or health <= 0 or is_player_controlled():
		_cycle_running = false
		return

	# 2) 装完后切换到“对自己扣扳机”的图片，当前右上膛室决定是否自伤。
	_set_visual_state_everywhere(VISUAL_SELF)
	await get_tree().create_timer(maxf(trigger_pose_duration,0.05)).timeout
	if not is_instance_valid(self) or health <= 0 or is_player_controlled():
		_cycle_running = false
		return
	_pull_trigger_on_self()
	if health <= 0:
		_cycle_running = false
		return
	await _advance_chamber()

	# 3) 接着固定切到对敌开枪图，依次扣完剩下五个膛室；实弹开枪，空膛卡壳。
	_set_visual_state_everywhere(VISUAL_SHOOT)
	await get_tree().create_timer(0.05).timeout
	for shot_index:int in range(5):
		if not is_instance_valid(self) or health <= 0 or is_player_controlled():
			_cycle_running = false
			return
		_pull_trigger_on_enemy()
		# 对敌连射没有额外冷却：扣扳机后只等待转轮机械转到下一膛室。
		await _advance_chamber()
		# 保留这个导出值只是为了兼容旧场景；0 表示完全没有额外射击间隔。
		if shot_index < 4 and trigger_interval > 0.0:
			await get_tree().create_timer(trigger_interval).timeout

	# 4) 六个膛室全部走完后立刻回到装填图，等待下一轮再重新装弹。
	_set_visual_state_everywhere(VISUAL_RELOAD)
	_cycle_left = maxf(reload_pause,0.5)
	_cycle_running = false


func _load_cylinder() -> void:
	var chambers:int = clampi(chamber_count,6,6)
	_loaded_live_rounds = _rng.randi_range(0,chambers)
	_cylinder.clear()
	_visible_rounds.clear()
	for i:int in range(chambers):
		_cylinder.append(i < _loaded_live_rounds)
		_visible_rounds.append(false)

	# 保证“恰好装 N 发”，但 N 发具体落在哪些膛室完全随机。
	for i:int in range(chambers - 1,0,-1):
		var j:int = _rng.randi_range(0,i)
		var temp:bool = _cylinder[i]
		_cylinder[i] = _cylinder[j]
		_cylinder[j] = temp
	_current_chamber = 0
	_broadcast_cylinder_visual(false)


func _play_reload_sequence() -> void:
	_set_visual_state_everywhere(VISUAL_RELOAD)

	# 右上孔就是当前装填孔。看一膛 -> 有实弹就放入图片并响一次 -> 转轮顺时针转一格。
	for slot:int in range(6):
		if not is_instance_valid(self) or health <= 0:
			return

		if bool(_cylinder[slot]):
			_visible_rounds[slot] = true
			_broadcast_cylinder_visual(false)
		# 每经过一个膛室都播放一次装填机械声：
		# 有实弹时会同时显示子弹，空膛则只响声音、不显示子弹。
		_play_gambler_sfx_everywhere(SFX_RELOAD,global_position,3.0,1.0)

		await get_tree().create_timer(maxf(reload_round_interval,0.08)).timeout
		await _turn_cylinder_one_step()


func _pull_trigger_on_self() -> void:
	var live:bool = _is_current_chamber_live()
	Attacking = true
	if live:
		_consume_current_round()
		_play_gambler_sfx_everywhere(SFX_FIRE,global_position,-4.0,1.0)
		var before_health:float = float(health)
		var shot_damage:float = attack_damage(enemy_bullet_damage_multiplier)
		hit_white(true)
		# 自射与对敌实弹使用完全相同的最终单发伤害。
		take_damage(shot_damage,true)
		# 对自己开出实弹时也要有正常“人物被撞击/受击”的反馈。
		# 这里复用 ball.gd 普通命中所用的 Hit_Audio（默认 balls_hit1），
		# 而不是再制作一套赌徒专用受击声。
		if float(health) < before_health:
			if Unique_Hit_Audio != null:
				play_unique_audio(Character_Audio_Slot.Hit,true)
			elif Hit_Audio != "":
				Audios.play_sfx.rpc(Hit_Audio,{volume = clampf(shot_damage - 12.0,-100.0,0.0)},true)
	else:
		# 空膛对自己扣扳机：明确播放卡壳声，不造成伤害。
		_play_gambler_sfx_everywhere(SFX_DRY,global_position,2.0,1.0)
	Attacking = false


func _pull_trigger_on_enemy() -> void:
	var live:bool = _is_current_chamber_live()
	Attacking = true
	if live:
		_consume_current_round()
		var target:Node = return_reusable_combat_target()
		var shoot_dir:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
		if target is Node2D and is_instance_valid(target):
			var to_target:Vector2 = combat_target_position(target) - global_position
			if to_target.length_squared() > 0.000001:
				shoot_dir = to_target.normalized()
		_play_gambler_sfx_everywhere(SFX_FIRE,global_position,-4.0,1.0)
		_spawn_bullet(shoot_dir)
	else:
		_play_gambler_sfx_everywhere(SFX_DRY,global_position,2.0,1.0)
	Attacking = false


func _is_current_chamber_live() -> bool:
	if _current_chamber < 0 or _current_chamber >= _cylinder.size():
		return false
	return bool(_cylinder[_current_chamber])


func _consume_current_round() -> void:
	if _current_chamber < 0 or _current_chamber >= _cylinder.size():
		return
	_cylinder[_current_chamber] = false
	if _current_chamber < _visible_rounds.size():
		_visible_rounds[_current_chamber] = false
	_broadcast_cylinder_visual(false)


func _advance_chamber() -> void:
	_current_chamber = (_current_chamber + 1) % 6
	await _turn_cylinder_one_step()


func _turn_cylinder_one_step() -> void:
	# Godot 2D 坐标中正角度视觉上是顺时针，因此 +60° 就是“向右转一格”。
	_cylinder_rotation_step += 1
	_broadcast_cylinder_visual(true)
	await get_tree().create_timer(maxf(cylinder_turn_duration,0.04)).timeout


func _spawn_bullet(shoot_dir:Vector2) -> void:
	var projectile:Area2D = ARMS_DEALER_BULLET_SCENE.instantiate() as Area2D
	if projectile == null:
		return
	var normalized_dir:Vector2 = shoot_dir.normalized() if shoot_dir.length_squared() > 0.000001 else Vector2.RIGHT
	projectile.set("Master_name",str(name))
	projectile.set("Team",Team)
	projectile.set("projectile_kind",0)
	projectile.set("damage_amount",attack_damage(enemy_bullet_damage_multiplier))
	projectile.set("speed",maxf(bullet_speed,80.0))
	projectile.set("acceleration",0.0)
	projectile.set("max_speed",maxf(bullet_speed,80.0))
	projectile.set("direction",normalized_dir)
	projectile.set("knockback_distance",0.0)
	projectile.set("knockback_speed",0.0)
	projectile.set("explosion_radius",0.0)
	projectile.set("visual_size",5.0)
	projectile.set("lifetime",5.0)
	projectile.global_position = global_position + normalized_dir * muzzle_offset
	projectile.global_rotation = normalized_dir.angle()
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func _set_visual_state_everywhere(state_value:int) -> void:
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
	var wanted:Texture2D = _default_texture
	match state_value:
		VISUAL_SHOOT:
			wanted = _shoot_texture if _shoot_texture != null else _default_texture
		VISUAL_RELOAD:
			wanted = _reload_texture if _reload_texture != null else _default_texture
		VISUAL_SELF:
			wanted = _self_texture if _self_texture != null else _default_texture
		_:
			wanted = _default_texture
	if wanted == null:
		return
	var sprite := image as Sprite2D
	sprite.texture = wanted
	sprite.self_modulate = Color.WHITE
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _setup_cylinder_visual() -> void:
	var wheel_texture:Texture2D = _try_load_texture(GAMBLER_CYLINDER_TEXTURE_PATH)
	var round_texture:Texture2D = _try_load_texture(GAMBLER_ROUND_TEXTURE_PATH)
	if wheel_texture == null or round_texture == null:
		return

	_cylinder_visual_root = Node2D.new()
	_cylinder_visual_root.name = "GamblerCylinderDisplay"
	_cylinder_visual_root.position = cylinder_visual_offset
	_cylinder_visual_root.z_index = 40
	add_child(_cylinder_visual_root)

	_cylinder_wheel = Sprite2D.new()
	_cylinder_wheel.name = "Cylinder"
	_cylinder_wheel.texture = wheel_texture
	_cylinder_wheel.scale = Vector2.ONE * cylinder_visual_scale
	_cylinder_visual_root.add_child(_cylinder_wheel)

	_cylinder_round_sprites.clear()
	for slot:int in range(6):
		var round_sprite := Sprite2D.new()
		round_sprite.name = "Round_%d" % slot
		round_sprite.texture = round_texture
		round_sprite.position = CYLINDER_SLOT_POSITIONS[slot]
		round_sprite.scale = Vector2.ONE * cylinder_round_scale
		round_sprite.visible = false
		round_sprite.z_index = 2
		_cylinder_wheel.add_child(round_sprite)
		_cylinder_round_sprites.append(round_sprite)

	_local_visual_rotation_step = _cylinder_rotation_step


func _pack_visible_rounds() -> PackedByteArray:
	var packed := PackedByteArray()
	packed.resize(6)
	for i:int in range(6):
		packed[i] = 1 if i < _visible_rounds.size() and bool(_visible_rounds[i]) else 0
	return packed


func _broadcast_cylinder_visual(animate_turn:bool) -> void:
	var packed:PackedByteArray = _pack_visible_rounds()
	if multiplayer.has_multiplayer_peer():
		_rpc_set_cylinder_visual.rpc(packed,_cylinder_rotation_step,animate_turn)
	else:
		_rpc_set_cylinder_visual(packed,_cylinder_rotation_step,animate_turn)


@rpc("authority","call_local","reliable")
func _rpc_set_cylinder_visual(visible_data:PackedByteArray,rotation_step:int,animate_turn:bool) -> void:
	_apply_cylinder_visual_local(visible_data,rotation_step,animate_turn)


func _apply_cylinder_visual_local(visible_data:PackedByteArray,rotation_step:int,animate_turn:bool) -> void:
	if _cylinder_wheel == null or not is_instance_valid(_cylinder_wheel):
		return

	for i:int in range(_cylinder_round_sprites.size()):
		var show_round:bool = i < visible_data.size() and int(visible_data[i]) != 0
		var round_sprite:Sprite2D = _cylinder_round_sprites[i]
		if round_sprite != null and is_instance_valid(round_sprite):
			round_sprite.visible = show_round

	var delta_steps:int = rotation_step - _local_visual_rotation_step
	_local_visual_rotation_step = rotation_step
	if delta_steps == 0:
		return

	if _cylinder_turn_tween != null and _cylinder_turn_tween.is_valid():
		_cylinder_turn_tween.kill()
	var target_rotation:float = _cylinder_wheel.rotation + deg_to_rad(60.0 * float(delta_steps))
	if animate_turn and abs(delta_steps) <= 2:
		_cylinder_turn_tween = create_tween()
		_cylinder_turn_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_cylinder_turn_tween.tween_property(_cylinder_wheel,"rotation",target_rotation,maxf(cylinder_turn_duration,0.04))
	else:
		_cylinder_wheel.rotation = target_rotation


func _play_gambler_sfx_everywhere(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_gambler_sfx.rpc(kind,position_value,volume_db,pitch)
	else:
		_rpc_play_gambler_sfx(kind,position_value,volume_db,pitch)


@rpc("authority","call_local","unreliable")
func _rpc_play_gambler_sfx(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	var stream:AudioStream = null
	match kind:
		SFX_FIRE:
			stream = GAMBLER_FIRE_SFX
		SFX_RELOAD:
			stream = GAMBLER_RELOAD_SFX
		SFX_DRY:
			stream = GAMBLER_DRY_SFX
		_:
			return
	_play_positional_stream(stream,position_value,volume_db,pitch,900.0)


func _play_positional_stream(stream:AudioStream,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if stream == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func Die() -> void:
	_cycle_running = false
	if _cylinder_turn_tween != null and _cylinder_turn_tween.is_valid():
		_cylinder_turn_tween.kill()
	if _cylinder_visual_root != null and is_instance_valid(_cylinder_visual_root):
		_cylinder_visual_root.visible = false
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
