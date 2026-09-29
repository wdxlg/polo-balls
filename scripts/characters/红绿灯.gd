extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

enum LightPhase { GREEN, YELLOW, RED }

@export_category("红绿灯 - 循环")
@export_range(0.5,30.0,0.5) var green_duration:float = 10.0
@export_range(0.5,10.0,0.5) var yellow_duration:float = 3.0
@export_range(0.5,30.0,0.5) var red_duration:float = 10.0
@export_range(0.0,1.0,0.05) var yellow_speed_multiplier:float = 0.5

@export_category("红绿灯 - 灯色图片")
@export var green_texture:Texture2D
@export var yellow_texture:Texture2D
@export var red_texture:Texture2D

@export_category("红绿灯 - 灯光发光")
@export var glow_enabled:bool = true
# 下面三个位置使用原始 1122×1402 图片、以图片中心为原点的像素坐标。
# GlowHalo 是 Image 的子节点，所以 CharacterAutoFit 缩放人物时光晕会同步缩放。
@export var green_glow_position:Vector2 = Vector2(-379.0,-63.0)
@export var yellow_glow_position:Vector2 = Vector2(-379.0,-220.0)
@export var red_glow_position:Vector2 = Vector2(-382.0,-380.0)
@export var green_glow_color:Color = Color(0.12,1.0,0.18,0.72)
@export var yellow_glow_color:Color = Color(1.0,0.72,0.05,0.72)
@export var red_glow_color:Color = Color(1.0,0.08,0.04,0.72)
@export_range(0.5,3.0,0.05) var glow_scale:float = 1.35

@export_category("红绿灯 - 切灯地图闪色")
@export var map_flash_enabled:bool = true
@export_range(0.03,0.8,0.01) var map_flash_duration:float = 0.16
@export var green_map_flash_color:Color = Color(0.08,1.0,0.16,0.24)
@export var yellow_map_flash_color:Color = Color(1.0,0.72,0.04,0.24)
@export var red_map_flash_color:Color = Color(1.0,0.05,0.03,0.28)

@export_category("红绿灯 - 黄灯惩罚")
@export_range(0.2,2.0,0.05) var yellow_movement_window:float = 1.0
@export_range(10.0,300.0,5.0) var yellow_damage_distance:float = 80.0
@export_range(0.0,10.0,0.05) var yellow_damage_multiplier:float = 1.0

@export_category("红绿灯 - 红灯惩罚")
@export_range(5.0,200.0,5.0) var red_damage_distance:float = 40.0
@export_range(0.0,10.0,0.05) var red_damage_per_step_multiplier:float = 1.0
@export_range(0.0,10.0,0.1) var movement_deadzone:float = 0.8

@onready var character_image:Sprite2D = $Graphics/Image
@onready var glow_halo:Sprite2D = $Graphics/Image/GlowHalo
@onready var switch_sfx_1:AudioStreamPlayer2D = $SwitchSfx1
@onready var switch_sfx_2:AudioStreamPlayer2D = $SwitchSfx2
@onready var switch_sfx_3:AudioStreamPlayer2D = $SwitchSfx3

var phase:LightPhase = LightPhase.GREEN
var _phase_left:float = 0.0
var _normal_speed:float = 0.0
var _last_positions:Dictionary = {}
var _movement_banks:Dictionary = {}
var _yellow_elapsed:Dictionary = {}
var _yellow_distances:Dictionary = {}

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	super._ready()
	_normal_speed = maxf(Speed,0.0)
	_set_phase(LightPhase.GREEN,false)

func _physics_process(delta:float) -> void:
	if health <= 0 or not is_multiplayer_authority():
		return
	# V80：不是只在切灯瞬间写一次，而是每个物理帧重新落实当前灯色的移动速度。
	# 项目里其它运行时逻辑即使写过 Speed，也不会让黄/红灯失去自己的速度规则。
	Speed = _phase_move_speed()
	if phase == LightPhase.RED:
		velocity = Vector2.ZERO
	if not is_combat_runtime_active():
		return
	_phase_left -= delta
	if phase == LightPhase.YELLOW:
		_apply_yellow_movement_damage(delta)
	elif phase == LightPhase.RED:
		_apply_red_movement_damage()
	if _phase_left <= 0.0 and not is_player_controlled():
		_advance_light_phase()

func controlled_attack_action() -> void:
	# 左键：原绿-黄-红循环逐段切换，仍须等待当前灯色的最低持续时间。
	if is_player_controlled() and is_multiplayer_authority() and health > 0 and is_combat_runtime_active() and _phase_left <= 0.0:
		_advance_light_phase()

func _advance_light_phase() -> void:
	match phase:
		LightPhase.GREEN:
			_set_phase(LightPhase.YELLOW)
		LightPhase.YELLOW:
			_set_phase(LightPhase.RED)
		LightPhase.RED:
			_set_phase(LightPhase.GREEN)

# state_machine 真正移动角色时也再读取一次灯色速度，避免 Node 物理处理顺序造成一帧甚至持续失配。
func tick_physics(state:State,delta:float) -> void:
	Speed = _phase_move_speed()
	super.tick_physics(state,delta)
	if phase == LightPhase.RED:
		velocity = Vector2.ZERO

func _phase_move_speed() -> float:
	match phase:
		LightPhase.YELLOW:
			return _normal_speed * clampf(yellow_speed_multiplier,0.0,1.0)
		LightPhase.RED:
			return 0.0
		_:
			return _normal_speed

func _set_phase(next_phase:LightPhase,play_switch_sound:bool = true) -> void:
	phase = next_phase
	match phase:
		LightPhase.GREEN:
			_phase_left = green_duration
		LightPhase.YELLOW:
			_phase_left = yellow_duration
		LightPhase.RED:
			_phase_left = red_duration
	Speed = _phase_move_speed()
	if phase == LightPhase.RED:
		velocity = Vector2.ZERO
	_update_phase_texture()
	_reset_movement_tracking()
	if play_switch_sound:
		_play_random_switch_sfx()
		_play_phase_map_flash()

func _play_phase_map_flash() -> void:
	if not map_flash_enabled:
		return
	var phase_value:int = int(phase)
	# 和切灯音效一样，由 authority 决定切灯时机；联机时把这一瞬间的地图闪色同步给各端。
	if multiplayer.has_multiplayer_peer():
		_show_phase_map_flash.rpc(phase_value)
	else:
		_show_phase_map_flash(phase_value)

@rpc("authority","call_local","unreliable")
func _show_phase_map_flash(phase_value:int) -> void:
	if not map_flash_enabled:
		return
	var rect:Rect2 = _get_current_map_world_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null or not is_instance_valid(scene_root):
		return
	# 参考棋盘控制器五连：直接在世界画布用 Polygon2D 覆盖当前地图真实矩形，
	# 所以只闪战场，不覆盖 CanvasLayer 里的顶部 UI / 按钮。
	var flash:Polygon2D = Polygon2D.new()
	flash.name = "TrafficLightMapFlash_%d" % Time.get_ticks_usec()
	flash.z_as_relative = false
	flash.z_index = 500
	flash.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x,rect.position.y),
		rect.end,
		Vector2(rect.position.x,rect.end.y)
	])
	flash.color = _map_flash_color_for_phase(phase_value)
	scene_root.add_child(flash)
	flash.add_to_group("BattleTransient")
	var tween:Tween = flash.create_tween()
	tween.tween_property(flash,"modulate:a",0.0,maxf(map_flash_duration,0.03))
	tween.finished.connect(flash.queue_free)

func _get_current_map_world_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not is_instance_valid(world) or not world.has_method("return_map_world_rect"):
		return Rect2()
	var map_name:String = str(world.get("now_choose_map"))
	var map_group_value:Variant = world.get("map_group")
	if not map_group_value is Dictionary:
		return Rect2()
	var maps:Dictionary = map_group_value as Dictionary
	if not maps.has(map_name):
		return Rect2()
	var map_node:Variant = maps[map_name]
	if not map_node is TileMapLayer:
		return Rect2()
	var rect_value:Variant = world.call("return_map_world_rect",map_node)
	if rect_value is Rect2:
		return rect_value as Rect2
	return Rect2()

func _map_flash_color_for_phase(phase_value:int) -> Color:
	match phase_value:
		int(LightPhase.YELLOW):
			return yellow_map_flash_color
		int(LightPhase.RED):
			return red_map_flash_color
		_:
			return green_map_flash_color

func _play_random_switch_sfx() -> void:
	var players:Array[AudioStreamPlayer2D] = [switch_sfx_1,switch_sfx_2,switch_sfx_3]
	var available_indices:Array[int] = []
	for index:int in range(players.size()):
		var candidate:AudioStreamPlayer2D = players[index]
		if candidate != null and candidate.stream != null:
			available_indices.append(index)
	if available_indices.is_empty():
		return
	var chosen_index:int = available_indices.pick_random()
	if multiplayer.has_multiplayer_peer():
		_play_switch_sfx_index.rpc(chosen_index)
	else:
		_play_switch_sfx_index(chosen_index)

@rpc("authority","call_local","unreliable")
func _play_switch_sfx_index(index:int) -> void:
	var players:Array[AudioStreamPlayer2D] = [switch_sfx_1,switch_sfx_2,switch_sfx_3]
	if index < 0 or index >= players.size():
		return
	var player:AudioStreamPlayer2D = players[index]
	if player == null or player.stream == null:
		return
	player.stop()
	player.play()

func _play_collision_hit_sfx(damage_amount:float) -> void:
	# 与 ball.gd / 巡逻车的普通碰撞伤害命中声统一使用 balls_hit1。
	var hit_volume:float = clampf(maxf(damage_amount,0.0) - 12.0,-100.0,0.0)
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",{volume = hit_volume},true,true)
	else:
		Audios.play_sfx("balls_hit1",{volume = hit_volume},true,true)

func _deal_movement_damage(enemy:ball,damage_amount:float) -> bool:
	if enemy == null or damage_amount <= 0.0:
		return false
	var did_damage:bool = enemy.receive_positional_damage(damage_amount,enemy.global_position,false,self)
	if did_damage:
		_play_collision_hit_sfx(damage_amount)
	return did_damage

func _update_phase_texture() -> void:
	if character_image == null:
		return
	var next_texture:Texture2D = green_texture
	match phase:
		LightPhase.YELLOW:
			next_texture = yellow_texture
		LightPhase.RED:
			next_texture = red_texture
		_:
			next_texture = green_texture
	if next_texture == null:
		return
	character_image.texture = next_texture
	# 三张图尺寸一致，但仍复用项目现有视觉适配，保证未来替换素材时不突然改变角色显示尺寸。
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call("apply_visual_fit_only")
	_update_phase_glow()

func _update_phase_glow() -> void:
	if glow_halo == null:
		return
	glow_halo.visible = glow_enabled
	if not glow_enabled:
		return
	var source_position:Vector2 = green_glow_position
	var glow_color:Color = green_glow_color
	match phase:
		LightPhase.YELLOW:
			source_position = yellow_glow_position
			glow_color = yellow_glow_color
		LightPhase.RED:
			source_position = red_glow_position
			glow_color = red_glow_color
		_:
			source_position = green_glow_position
			glow_color = green_glow_color
	# Sprite2D.flip_h 只翻父图片纹理，不会自动镜像子节点位置；
	# 因此人物朝右/朝左变化时显式镜像灯光的 X 坐标。
	if is_character_visual_flipped_h():
		source_position.x = -source_position.x
	glow_halo.position = source_position
	glow_halo.scale = Vector2.ONE * maxf(glow_scale,0.05)
	glow_halo.modulate = glow_color

func set_character_visual_flip_h(flipped:bool) -> void:
	super.set_character_visual_flip_h(flipped)
	_update_phase_glow()

func _reset_movement_tracking() -> void:
	_last_positions.clear()
	_movement_banks.clear()
	_yellow_elapsed.clear()
	_yellow_distances.clear()
	if phase != LightPhase.YELLOW and phase != LightPhase.RED:
		return
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw is ball and TOOLS.is_enemy(self,raw as ball):
			var enemy:ball = raw as ball
			var id:int = enemy.get_instance_id()
			_last_positions[id] = enemy.global_position
			if phase == LightPhase.YELLOW:
				_yellow_elapsed[id] = 0.0
				_yellow_distances[id] = 0.0

# 黄灯：在最多 1 秒的窗口里累计真实路径距离；一旦超过阈值立即扣一次血并开启新窗口。
func _apply_yellow_movement_damage(delta:float) -> void:
	var alive_ids:Dictionary = {}
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var enemy:ball = raw as ball
		if not TOOLS.is_enemy(self,enemy):
			continue
		var id:int = enemy.get_instance_id()
		alive_ids[id] = true
		var current:Vector2 = enemy.global_position
		if not _last_positions.has(id):
			_last_positions[id] = current
			_yellow_elapsed[id] = 0.0
			_yellow_distances[id] = 0.0
			continue
		var previous:Vector2 = _last_positions[id]
		var moved:float = current.distance_to(previous)
		_last_positions[id] = current
		var elapsed:float = float(_yellow_elapsed.get(id,0.0)) + delta
		var distance:float = float(_yellow_distances.get(id,0.0))
		if moved > movement_deadzone:
			distance += moved
		if distance >= maxf(yellow_damage_distance,1.0) and elapsed <= maxf(yellow_movement_window,0.05):
			_deal_movement_damage(enemy,attack_damage(yellow_damage_multiplier))
			elapsed = 0.0
			distance = 0.0
		elif elapsed >= maxf(yellow_movement_window,0.05):
			elapsed = 0.0
			distance = 0.0
		_yellow_elapsed[id] = elapsed
		_yellow_distances[id] = distance
	_cleanup_tracking(alive_ids)

func _apply_red_movement_damage() -> void:
	var alive_ids:Dictionary = {}
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var enemy:ball = raw as ball
		if not TOOLS.is_enemy(self,enemy):
			continue
		var id:int = enemy.get_instance_id()
		alive_ids[id] = true
		var current:Vector2 = enemy.global_position
		if not _last_positions.has(id):
			_last_positions[id] = current
			_movement_banks[id] = 0.0
			continue
		var previous:Vector2 = _last_positions[id]
		var moved:float = current.distance_to(previous)
		_last_positions[id] = current
		if moved <= movement_deadzone:
			continue
		var bank:float = float(_movement_banks.get(id,0.0)) + moved
		while bank >= maxf(red_damage_distance,1.0):
			bank -= maxf(red_damage_distance,1.0)
			_deal_movement_damage(enemy,attack_damage(red_damage_per_step_multiplier))
		_movement_banks[id] = bank
	_cleanup_tracking(alive_ids)

func _cleanup_tracking(alive_ids:Dictionary) -> void:
	for raw_id:Variant in _last_positions.keys():
		var id:int = int(raw_id)
		if alive_ids.has(id):
			continue
		_last_positions.erase(id)
		_movement_banks.erase(id)
		_yellow_elapsed.erase(id)
		_yellow_distances.erase(id)
