extends ball

const MARKET_CONTROLLER_SCRIPT = preload("res://scripts/characters/投资者_地图控制器.gd")
const RED_BAR_AUDIO:AudioStream = preload("res://audio/characters/投资者/投资者_红条.mp3")

# ========================================================
# 投资者
#
# 地图会逐列生成“行情矩形”：
# - 从当前地图左下开始，矩形从下向上长出，然后一路向右。
# - 铺满后，已有矩形整体向左滚动一列，右侧继续生成新矩形。
# - 绿色通常更高：限制空间大，但投资者伤害低。
# - 红色通常更低：给敌人更多空间，但投资者伤害高。
# - 所有尺寸都根据 World.return_map_world_rect() 和当前角色碰撞尺寸计算，
#   不写死 10x10 地图。
# ========================================================

@export_category("行情生成")
@export_range(0.1,10.0,0.05) var column_interval:float = 1.35
@export_range(0.0,2.0,0.01) var grow_duration:float = 0.30
@export_range(0.0,2.0,0.01) var scroll_duration:float = 0.24
@export_range(1,20,1) var min_columns:int = 3
@export_range(1,30,1) var max_columns:int = 10
@export_range(0.2,2.0,0.05) var preferred_column_width_by_actor:float = 0.75
@export_range(0.1,0.98,0.01) var bar_width_ratio_min:float = 0.62
@export_range(0.1,0.98,0.01) var bar_width_ratio_max:float = 0.88
@export_range(0.0,0.15,0.001) var map_inner_padding_ratio:float = 0.012
@export_range(0.05,0.8,0.01) var minimum_open_space_ratio:float = 0.26
@export_range(0.5,3.0,0.05) var actor_clearance_multiplier:float = 1.12

@export_category("绿色行情：限制大 / 伤害低")
@export_range(0.0,1.0,0.01) var green_height_fraction_min:float = 0.58
@export_range(0.0,1.0,0.01) var green_height_fraction_max:float = 0.95
@export_range(0.0,500.0,1.0) var green_damage_multiplier_at_low_bar:float = 3.4
@export_range(0.0,500.0,1.0) var green_damage_multiplier_at_high_bar:float = 1.0
@export var green_bar_color:Color = Color(0.15,0.78,0.28,0.88)

@export_category("红色行情：空间大 / 伤害高")
@export_range(0.0,1.0,0.01) var red_height_fraction_min:float = 0.12
@export_range(0.0,1.0,0.01) var red_height_fraction_max:float = 0.48
@export_range(0.0,500.0,1.0) var red_damage_multiplier_at_low_bar:float = 9.2
@export_range(0.0,500.0,1.0) var red_damage_multiplier_at_high_bar:float = 5.4
@export var red_bar_color:Color = Color(0.95,0.18,0.18,0.88)
@export_range(1.0,1.5,0.01) var red_speed_max_multiplier:float = 1.20

@export_category("红条音效")
@export_range(-40.0,12.0,0.5) var red_bar_audio_volume_db:float = -4.0
@export_range(100.0,3000.0,10.0) var red_bar_audio_max_distance:float = 900.0

@export_category("角色贴图")
@export var normal_texture:Texture2D
@export var angry_texture:Texture2D

var _market_controller:Node = null
var _last_market_green:bool = true
var _last_market_height_normalized:float = 0.0
var _market_base_speed:float = 0.0
var _market_damage_multiplier:float = 1.0


func _ready() -> void:
	super._ready()
	_market_base_speed = maxf(float(default_properties.get("Speed",Speed)),0.0)
	_set_character_texture(normal_texture)
	# V276：行情控制器是 script.new()，不受 MultiplayerSpawner 自动复制。
	# 每个 peer 都建立同路径控制器；仅 authority 生成行情，远端通过控制器 RPC 重建柱子视觉。
	call_deferred("_create_market_controller")


func _create_market_controller() -> void:
	if _market_controller != null and is_instance_valid(_market_controller):
		return
	if health <= 0:
		return

	var controller = MARKET_CONTROLLER_SCRIPT.new()
	# 固定作为投资者子节点，保证所有 peer 的 RPC NodePath 一致。
	controller.name = "InvestorMarketController"
	controller.investor_ref = weakref(self)
	controller.investor_instance_id = get_instance_id()

	controller.column_interval = column_interval
	controller.grow_duration = grow_duration
	controller.scroll_duration = scroll_duration
	controller.min_columns = min_columns
	controller.max_columns = max_columns
	controller.preferred_column_width_by_actor = preferred_column_width_by_actor
	controller.bar_width_ratio_min = bar_width_ratio_min
	controller.bar_width_ratio_max = bar_width_ratio_max
	controller.map_inner_padding_ratio = map_inner_padding_ratio
	controller.minimum_open_space_ratio = minimum_open_space_ratio
	controller.actor_clearance_multiplier = actor_clearance_multiplier

	controller.green_height_fraction_min = green_height_fraction_min
	controller.green_height_fraction_max = green_height_fraction_max
	controller.green_damage_multiplier_at_low_bar = green_damage_multiplier_at_low_bar
	controller.green_damage_multiplier_at_high_bar = green_damage_multiplier_at_high_bar
	controller.green_color = green_bar_color

	controller.red_height_fraction_min = red_height_fraction_min
	controller.red_height_fraction_max = red_height_fraction_max
	controller.red_damage_multiplier_at_low_bar = red_damage_multiplier_at_low_bar
	controller.red_damage_multiplier_at_high_bar = red_damage_multiplier_at_high_bar
	controller.red_color = red_bar_color

	add_child(controller)
	_market_controller = controller

func controlled_attack_action() -> void:
	# 左键：要求地图控制器生成下一列行情；原柱的生长/滚动与碰撞继续自动结算。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if _market_controller != null and is_instance_valid(_market_controller):
		_market_controller.call("request_manual_column")


func set_market_damage_multiplier(value:float,is_green:bool,height_normalized:float) -> void:
	_market_damage_multiplier = maxf(value,0.0)
	_last_market_green = is_green
	_last_market_height_normalized = clampf(height_normalized,0.0,1.0)
	_set_character_texture(normal_texture if is_green else angry_texture)

	# V107：行情只改变攻击倍率；Damage 始终是整体基础攻击力。

	# 红条越低，速度越快：normalized_height=0 表示本轮允许范围内的最低条，
	# 这时达到 red_speed_max_multiplier；越接近最高红条则平滑回到 1.0x。
	var speed_multiplier:float = 1.0
	if not is_green:
		var red_low:float = minf(red_height_fraction_min,red_height_fraction_max)
		var red_high:float = maxf(red_height_fraction_min,red_height_fraction_max)
		var red_height_ratio:float = 0.0
		if red_high > red_low + 0.0001:
			red_height_ratio = clampf(
				(_last_market_height_normalized - red_low) / (red_high - red_low),
				0.0,
				1.0
			)
		speed_multiplier = lerpf(maxf(red_speed_max_multiplier,1.0),1.0,red_height_ratio)
	var market_speed:float = _market_base_speed * speed_multiplier
	default_properties["Speed"] = market_speed
	Speed = market_speed

	# 用户指定的音频只在“红条出现”时播放；绿条不再复用之前的购买占位音效。
	if is_multiplayer_authority() and not is_green:
		_play_red_bar_audio_everywhere(global_position)


func current_hit_damage_multiplier() -> float:
	return maxf(_market_damage_multiplier,0.0)


func _play_red_bar_audio_everywhere(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_red_bar_audio.rpc(position_value)
	else:
		_rpc_play_red_bar_audio(position_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_red_bar_audio(position_value:Vector2) -> void:
	if RED_BAR_AUDIO == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "InvestorRedBarAudio"
	player.stream = RED_BAR_AUDIO
	player.volume_db = red_bar_audio_volume_db
	player.max_distance = maxf(red_bar_audio_max_distance,100.0)
	player.attenuation = 1.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _set_character_texture(texture:Texture2D) -> void:
	if image is Sprite2D and texture != null:
		(image as Sprite2D).texture = texture


func _shutdown_market_controller(broadcast_cleanup:bool=true) -> void:
	if _market_controller == null or not is_instance_valid(_market_controller):
		_market_controller = null
		return
	if _market_controller.has_method("shutdown_market"):
		_market_controller.call("shutdown_market",broadcast_cleanup)
	else:
		_market_controller.queue_free()


func _exit_tree() -> void:
	# V43：Reset/直接释放不会保证地图控制器协程还能跑到尾部，离树时必须本地兜底清场。
	_shutdown_market_controller(false)


func Die() -> void:
	# V43：投资者一进入死亡就立即撤掉行情柱，不再等 2 秒尸体消失。
	# 控制器保留到角色真正离树；若时间回溯把投资者救活，它可以自行恢复运行。
	_shutdown_market_controller(true)
	super()
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
