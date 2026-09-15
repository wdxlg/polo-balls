extends ball

const MONEY_PROJECTILE_SCRIPT = preload("res://scripts/shooter/收债人_钱.gd")

const COLLECTOR_NORMAL_TEXTURE_PATH:String = "res://Images/characters/人物/收债人/收债人_普通.png"
const COLLECTOR_GIVE_TEXTURE_PATH:String = "res://Images/characters/人物/收债人/收债人_送钱.png"
const COLLECTOR_ANGRY_TEXTURE_PATH:String = "res://Images/characters/人物/收债人/收债人_愤怒收债.png"

const COLLECTOR_COIN_1_SFX:AudioStream = preload("res://audio/characters/收债人/金币1.mp3")
const COLLECTOR_COIN_2_SFX:AudioStream = preload("res://audio/characters/收债人/金币2.mp3")
const COLLECTOR_BILL_SFX:AudioStream = preload("res://audio/characters/收债人/钞票.mp3")
const COLLECTOR_CHECKOUT_SFX:AudioStream = preload("res://audio/characters/收债人/结账.mp3")

const SFX_COIN_1:int = 0
const SFX_COIN_2:int = 1
const SFX_BILL:int = 2
const SFX_CHECKOUT:int = 3

const VISUAL_NORMAL:int = 0
const VISUAL_GIVE:int = 1
const VISUAL_ANGRY:int = 2

# ========================================================
# 收债人
# - 攻击发射“钱”，本身 0 伤害。
# - 命中会永久给敌人一项随机正面属性，同时记一笔债务。
# - 债务按期复利增长；债务越接近目标 Max_health，本期增长百分比越高。
# - 债务 >= 目标当前 health 时直接斩杀，绕过 Block / Damage_reduction 等防御。
# - 债务永久显示在欠债敌人自己身上，只保留“债务:xxx$”的实际数值。
# ========================================================

@export_category("收债人 - 图片")
@export var normal_texture:Texture2D
@export var give_money_texture:Texture2D
@export var angry_collect_texture:Texture2D
@export_range(0.05,1.0,0.01) var give_pose_duration:float = 0.34
@export_range(0.05,1.5,0.01) var angry_pose_duration:float = 0.58

@export_category("收债人 - 射击")
@export_range(40.0,500.0,5.0) var attack_range:float = 190.0
@export_range(60.0,800.0,10.0) var money_speed:float = 270.0
@export_range(0.2,3.0,0.05) var money_lifetime:float = 1.20

@export_category("收债人 - 债务")
@export_range(0.0,100.0,1.0) var debt_per_hit_flat:float = 6.0
@export_range(0.01,0.50,0.01) var debt_per_hit_health_ratio:float = 0.07
@export_range(0.25,10.0,0.25) var debt_tick_interval:float = 2.0
@export_range(0.0,1.0,0.01) var debt_growth_base_ratio:float = 0.05
@export_range(0.0,1.0,0.01) var debt_growth_bonus_at_full_ratio:float = 0.18
@export_range(0.01,1.0,0.01) var debt_growth_ratio_cap:float = 0.35

@export_category("收债人 - 送钱属性")
@export_range(0.01,0.50,0.01) var gift_stat_ratio_min:float = 0.08
@export_range(0.01,0.50,0.01) var gift_stat_ratio_max:float = 0.16
@export_range(0.0,0.30,0.01) var gift_damage_reduction_min:float = 0.03
@export_range(0.0,0.30,0.01) var gift_damage_reduction_max:float = 0.06
@export_range(0,20,1) var gift_restore_min:int = 1
@export_range(0,20,1) var gift_restore_max:int = 3
@export_range(0.2,3.0,0.1) var gift_text_duration:float = 1.25

var _debtors:Dictionary = {}
var _debt_tick_left:float = 0.0
var _debt_ui_refresh_left:float = 0.0
var _visual_state:int = -1
var _visual_pose_serial:int = 0
var _default_texture:Texture2D = null


func _ready() -> void:
	# 收债人的本体接触不造成伤害；真正攻击只走“钱”的命中事件。
	Has_Collision_Damage = false
	Damage = 0

	# CharacterAutoFit 的子节点 _ready() 会早于人物本体执行。
	# 因此这里在父类记录 default_size 前主动换成收债人正常图并重新拟合一次，
	# 这样后续碰撞反馈恢复的也是正确人物尺寸，而不是旧占位图尺寸。
	_auto_load_collector_textures()
	var collector_sprite := $Graphics/Image as Sprite2D
	if collector_sprite != null and normal_texture != null:
		collector_sprite.texture = normal_texture
		collector_sprite.self_modulate = Color.WHITE
		var auto_fit:Node = get_node_or_null("CharacterAutoFit")
		if auto_fit != null and auto_fit.has_method("apply_fit"):
			auto_fit.call("apply_fit")

	super._ready()
	default_properties["Damage"] = 0
	_debt_tick_left = maxf(debt_tick_interval,0.25)

	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_visual_state = VISUAL_NORMAL
	_set_visual_state_local(VISUAL_NORMAL)


func _auto_load_collector_textures() -> void:
	if normal_texture == null:
		normal_texture = _try_load_texture(COLLECTOR_NORMAL_TEXTURE_PATH)
	if give_money_texture == null:
		give_money_texture = _try_load_texture(COLLECTOR_GIVE_TEXTURE_PATH)
	if angry_collect_texture == null:
		angry_collect_texture = _try_load_texture(COLLECTOR_ANGRY_TEXTURE_PATH)


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func _broadcast_visual_state(state_value:int) -> void:
	if _visual_state == state_value:
		return
	_visual_state = state_value
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
		VISUAL_GIVE:
			wanted = give_money_texture if give_money_texture != null else fallback_normal
		VISUAL_ANGRY:
			wanted = angry_collect_texture if angry_collect_texture != null else fallback_normal
		_:
			wanted = fallback_normal

	var sprite := image as Sprite2D
	if wanted != null:
		sprite.texture = wanted
		# 旧场景给占位图加过金色 self_modulate；现在使用完整人物原图时必须还原白色，
		# 否则整个人会被染黄。
		sprite.self_modulate = Color.WHITE
		_refit_visual_only()


func _refit_visual_only() -> void:
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _show_timed_pose(state_value:int,duration:float) -> void:
	if not is_multiplayer_authority():
		return
	_visual_pose_serial += 1
	var token:int = _visual_pose_serial
	_broadcast_visual_state(state_value)
	_restore_pose_after(token,maxf(duration,0.05))


func _restore_pose_after(token:int,duration:float) -> void:
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(self) or token != _visual_pose_serial:
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	_broadcast_visual_state(VISUAL_NORMAL)


func tick_physics(state:State,delta:float) -> void:
	super(state,delta)
	if not is_multiplayer_authority() or health <= 0:
		return

	_process_debts(delta)
	_check_all_debt_execution()
	_debt_ui_refresh_left -= delta
	if _debt_ui_refresh_left <= 0.0:
		_debt_ui_refresh_left = 0.20
		_refresh_all_debt_ui()

	if not has_player_control_aim():
		var enemy:ball = return_reusable_combat_target()
		var in_range:bool = (
			enemy != null
			and is_instance_valid(enemy)
			and enemy.health > 0
			and global_position.distance_to(combat_target_position(enemy)) <= attack_range
		)
		Attacking = in_range


func Attack() -> void:
	super()
	if not has_player_control_aim() or not is_multiplayer_authority():
		return
	if state_machine.current_state == State.Die or is_damage_output_disabled():
		Attacking = false
		return
	Attacking = true
	continue_attack()
	await get_tree().create_timer(maxf(continue_attack_cooling + 0.03,0.08)).timeout
	if is_instance_valid(self) and state_machine != null and state_machine.current_state != State.Die:
		Attacking = false


func continue_attack() -> void:
	super()
	if not is_multiplayer_authority() or state_machine.current_state == State.Die:
		return

	var enemy:ball = return_reusable_combat_target()
	if not has_player_control_aim() and (enemy == null or not is_instance_valid(enemy) or enemy.health <= 0):
		return
	var aim:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(enemy) - global_position)
	if aim.length_squared() <= 0.000001:
		return
	if not has_player_control_aim() and aim.length() > attack_range:
		return

	_show_timed_pose(VISUAL_GIVE,give_pose_duration)
	# “钞票”是发射钱时的射击声。素材本身较轻，因此略微提高音量。
	_play_collector_sfx_everywhere(SFX_BILL,global_position,13.0,1.0)
	_spawn_money_everywhere(global_position,aim.normalized())


func _spawn_money_everywhere(start_position:Vector2,shot_direction:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_money.rpc(start_position,shot_direction)
	else:
		_rpc_spawn_money(start_position,shot_direction)


@rpc("authority","call_local","unreliable")
func _rpc_spawn_money(start_position:Vector2,shot_direction:Vector2) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	var projectile = MONEY_PROJECTILE_SCRIPT.new()
	if projectile == null:
		return
	world.add_child(projectile)
	projectile.call(
		"setup",
		self,
		start_position,
		shot_direction,
		money_speed,
		money_lifetime,
		Team,
		is_multiplayer_authority()
	)


func _on_money_projectile_hit(target:ball) -> void:
	if not is_multiplayer_authority() or not _is_enemy_character(target):
		return

	# 钱真正打到人时随机播放金币 1 / 2；随机结果由 authority 选好再同步给所有端。
	var coin_kind:int = SFX_COIN_1 if randi_range(0,1) == 0 else SFX_COIN_2
	_play_collector_sfx_everywhere(coin_kind,target.global_position,5.0,randf_range(0.98,1.03))

	# 每次“钱”真正命中敌人时，都永久给被命中的敌人一项随机正面属性。
	# 只显示实际增加的属性，并放在该敌人的右侧下方。
	var gift_text:String = _grant_random_attribute(target)
	if not gift_text.is_empty():
		_broadcast_show_gift(target,gift_text)

	var added_debt:float = debt_per_hit_flat + float(target.Max_health) * debt_per_hit_health_ratio
	_add_debt(target,maxf(added_debt,1.0))


func _is_enemy_character(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0:
		return false
	if Team != "" and target.Team != "" and Team == target.Team:
		return false
	return true


func _grant_random_attribute(target:ball) -> String:
	var ratio_low:float = clampf(minf(gift_stat_ratio_min,gift_stat_ratio_max),0.01,0.5)
	var ratio_high:float = clampf(maxf(gift_stat_ratio_min,gift_stat_ratio_max),ratio_low,0.5)
	var ratio:float = randf_range(ratio_low,ratio_high)
	var roll:int = randi_range(0,4)

	match roll:
		0:
			var old_damage:int = maxi(int(target.default_properties.get("Damage",target.Damage)),0)
			var delta_damage:int = maxi(int(round(maxf(float(old_damage),8.0) * ratio)),1)
			var new_damage:int = old_damage + delta_damage
			target.default_properties["Damage"] = new_damage
			target.Damage = new_damage
			return "+伤害 %d" % delta_damage
		1:
			var old_speed:float = maxf(float(target.default_properties.get("Speed",target.Speed)),0.0)
			var delta_speed:float = maxf(old_speed * ratio,2.0)
			var new_speed:float = old_speed + delta_speed
			target.default_properties["Speed"] = new_speed
			target.Speed = new_speed
			return "+速度 %s" % _format_actual_number(delta_speed)
		2:
			var old_max:int = maxi(int(target.default_properties.get("Max_health",target.Max_health)),1)
			var delta_max:int = maxi(int(round(float(old_max) * ratio)),1)
			var new_max:int = old_max + delta_max
			target.default_properties["Max_health"] = new_max
			target.Max_health = new_max
			if target.health_bar != null:
				target.health_bar.suppress_floating_text = true
			target.health = mini(target.health + delta_max,new_max)
			if target.health_bar != null:
				target.health_bar.suppress_floating_text = false
			return "+生命 %d" % delta_max
		3:
			var low_dr:float = clampf(minf(gift_damage_reduction_min,gift_damage_reduction_max),0.0,0.3)
			var high_dr:float = clampf(maxf(gift_damage_reduction_min,gift_damage_reduction_max),low_dr,0.3)
			var old_dr:float = clampf(float(target.default_properties.get("Damage_reduction",target.Damage_reduction)),0.0,0.75)
			var add_dr:float = minf(randf_range(low_dr,high_dr),maxf(0.75 - old_dr,0.0))
			if add_dr <= 0.0001:
				return _grant_fallback_speed(target,ratio)
			var new_dr:float = old_dr + add_dr
			target.default_properties["Damage_reduction"] = new_dr
			target.Damage_reduction = new_dr
			return "+减伤 %.0f%%" % (add_dr * 100.0)
		_:
			var low_restore:int = mini(gift_restore_min,gift_restore_max)
			var high_restore:int = maxi(gift_restore_min,gift_restore_max)
			var add_restore:int = randi_range(low_restore,high_restore)
			if add_restore <= 0:
				return _grant_fallback_speed(target,ratio)
			var old_restore:int = int(target.default_properties.get("Health_Restore",target.Health_Restore))
			var new_restore:int = old_restore + add_restore
			target.default_properties["Health_Restore"] = new_restore
			target.Health_Restore = new_restore
			return "+回血 %d" % add_restore


func _grant_fallback_speed(target:ball,ratio:float) -> String:
	var old_speed:float = maxf(float(target.default_properties.get("Speed",target.Speed)),0.0)
	var delta_speed:float = maxf(old_speed * ratio,2.0)
	var new_speed:float = old_speed + delta_speed
	target.default_properties["Speed"] = new_speed
	target.Speed = new_speed
	return "+速度 %s" % _format_actual_number(delta_speed)


func _format_actual_number(value:float) -> String:
	if is_equal_approx(value,round(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _broadcast_show_gift(target:ball,text_value:String) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var target_path:NodePath = target.get_path()
	if multiplayer.has_multiplayer_peer():
		_rpc_show_gift_ui.rpc(target_path,text_value)
	else:
		_rpc_show_gift_ui(target_path,text_value)


@rpc("authority","call_local","unreliable")
func _rpc_show_gift_ui(target_path:NodePath,text_value:String) -> void:
	var target:ball = _status_target_from_path(target_path)
	if target != null:
		target.side_status_push_temporary(
			"positive",
			text_value,
			Color(0.30,1.0,0.40,1.0),
			gift_text_duration
		)


func _add_debt(target:ball,amount:float) -> void:
	var id:int = target.get_instance_id()
	var entry:Dictionary = _debtors.get(id,{})
	entry["target"] = weakref(target)
	entry["debt"] = maxf(float(entry.get("debt",0.0)) + amount,0.0)
	entry["ui_key"] = str(entry.get("ui_key","debt_%s_%s" % [str(get_instance_id()),str(id)]))
	_debtors[id] = entry

	_refresh_debt_entry(id)
	_check_debt_execution(id)


func _process_debts(delta:float) -> void:
	_debt_tick_left -= delta
	if _debt_tick_left > 0.0:
		return
	_debt_tick_left += maxf(debt_tick_interval,0.25)
	if _debt_tick_left <= 0.0:
		_debt_tick_left = maxf(debt_tick_interval,0.25)

	for raw_id in _debtors.keys().duplicate():
		var id:int = int(raw_id)
		var target:ball = _debtor_target(id)
		if target == null or target.health <= 0:
			_remove_debt_entry(id)
			continue

		var entry:Dictionary = _debtors[id]
		var debt:float = maxf(float(entry.get("debt",0.0)),0.0)
		if debt <= 0.0:
			_remove_debt_entry(id)
			continue

		var debt_ratio:float = debt / maxf(float(target.Max_health),1.0)
		var growth_ratio:float = debt_growth_base_ratio + debt_ratio * debt_growth_bonus_at_full_ratio
		growth_ratio = clampf(growth_ratio,0.0,debt_growth_ratio_cap)
		var growth_amount:float = maxf(debt * growth_ratio,1.0)
		entry["debt"] = debt + growth_amount
		_debtors[id] = entry

		_refresh_debt_entry(id)
		_check_debt_execution(id)


func _check_all_debt_execution() -> void:
	for raw_id in _debtors.keys().duplicate():
		_check_debt_execution(int(raw_id))


func _refresh_all_debt_ui() -> void:
	for raw_id in _debtors.keys().duplicate():
		var id:int = int(raw_id)
		var target:ball = _debtor_target(id)
		if target == null or target.health <= 0:
			_remove_debt_entry(id)
		else:
			_refresh_debt_entry(id)


func _check_debt_execution(id:int) -> void:
	if not _debtors.has(id):
		return
	var target:ball = _debtor_target(id)
	if target == null or target.health <= 0:
		_remove_debt_entry(id)
		return
	var entry:Dictionary = _debtors[id]
	var debt:float = float(entry.get("debt",0.0))
	if debt + 0.0001 < float(target.health):
		return

	# 真正收债成功时短暂切到“愤怒收债”图片，然后播放“结账”并恢复普通状态。
	_show_timed_pose(VISUAL_ANGRY,angry_pose_duration)
	_play_collector_sfx_everywhere(SFX_CHECKOUT,target.global_position,6.0,1.0)
	# 斩杀直接归零生命，不经过 take_damage，因此 Block、减伤、无伤盾等数值防御都无法抵消。
	target.health = 0
	_remove_debt_entry(id)


func _refresh_debt_entry(id:int) -> void:
	if not _debtors.has(id):
		return
	var target:ball = _debtor_target(id)
	if target == null:
		_remove_debt_entry(id)
		return
	var entry:Dictionary = _debtors[id]
	var debt:float = maxf(float(entry.get("debt",0.0)),0.0)
	var hp:float = maxf(float(target.health),1.0)
	var danger_ratio:float = clampf(debt / hp,0.0,1.0)
	var color := Color(1.0,lerpf(0.82,0.18,danger_ratio),lerpf(0.28,0.12,danger_ratio),1.0)
	var text_value:String = "债务:%d$" % int(round(debt))
	_broadcast_set_debt(target,str(entry.get("ui_key","debt_%s_%s" % [str(get_instance_id()),str(id)])),text_value,color)


func _debtor_target(id:int) -> ball:
	if not _debtors.has(id):
		return null
	var entry:Dictionary = _debtors[id]
	var ref_value = entry.get("target")
	if ref_value is WeakRef:
		var value = (ref_value as WeakRef).get_ref()
		if value is ball and is_instance_valid(value):
			return value as ball
	return null


func _remove_debt_entry(id:int) -> void:
	if not _debtors.has(id):
		return
	var entry:Dictionary = _debtors[id]
	var target:ball = _debtor_target(id)
	var ui_key:String = str(entry.get("ui_key","debt_%s_%s" % [str(get_instance_id()),str(id)]))
	_debtors.erase(id)
	if target != null and is_instance_valid(target):
		_broadcast_remove_debt(target,ui_key)


func _broadcast_set_debt(target:ball,key:String,text_value:String,color:Color) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var target_path:NodePath = target.get_path()
	if multiplayer.has_multiplayer_peer():
		_rpc_set_debt_ui.rpc(target_path,key,text_value,color)
	else:
		_rpc_set_debt_ui(target_path,key,text_value,color)


func _broadcast_remove_debt(target:ball,key:String) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var target_path:NodePath = target.get_path()
	if multiplayer.has_multiplayer_peer():
		_rpc_remove_debt_ui.rpc(target_path,key)
	else:
		_rpc_remove_debt_ui(target_path,key)


func _status_target_from_path(target_path:NodePath) -> ball:
	var value:Node = get_node_or_null(target_path)
	if value is ball and is_instance_valid(value):
		return value as ball
	return null


@rpc("authority","call_local","unreliable")
func _rpc_set_debt_ui(target_path:NodePath,key:String,text_value:String,color:Color) -> void:
	var target:ball = _status_target_from_path(target_path)
	if target != null:
		# 债务是目标身上的负面状态，固定显示在目标左侧。
		target.side_status_set_permanent("negative",key,text_value,color)


@rpc("authority","call_local","reliable")
func _rpc_remove_debt_ui(target_path:NodePath,key:String) -> void:
	var target:ball = _status_target_from_path(target_path)
	if target != null:
		target.side_status_remove_permanent("negative",key)


func _play_collector_sfx_everywhere(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_collector_sfx.rpc(kind,position_value,volume_db,pitch)
	else:
		_rpc_play_collector_sfx(kind,position_value,volume_db,pitch)


@rpc("authority","call_local","unreliable")
func _rpc_play_collector_sfx(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	var stream:AudioStream = null
	match kind:
		SFX_COIN_1:
			stream = COLLECTOR_COIN_1_SFX
		SFX_COIN_2:
			stream = COLLECTOR_COIN_2_SFX
		SFX_BILL:
			stream = COLLECTOR_BILL_SFX
		SFX_CHECKOUT:
			stream = COLLECTOR_CHECKOUT_SFX
		_:
			return
	_play_collector_stream(stream,position_value,volume_db,pitch,1500.0)


func _play_collector_stream(stream:AudioStream,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if stream == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.attenuation = 0.45
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func Die() -> void:
	for raw_id in _debtors.keys().duplicate():
		_remove_debt_entry(int(raw_id))
	_debtors.clear()
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
