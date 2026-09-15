extends ball

const BOARD_CONTROLLER_SCRIPT := preload("res://scripts/characters/棋盘控制器.gd")
const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")

@export_category("下棋")
@export_range(0.2,10.0,0.1) var place_interval:float = 1.25
@export_range(8.0,80.0,1.0) var board_spacing:float = 22.0
@export_range(4.0,60.0,1.0) var board_margin:float = 14.0
@export_range(2.0,20.0,0.5) var stone_radius:float = 5.0
@export_range(2.0,60.0,0.5) var stone_lifetime:float = 14.0

@export_category("落子动画")
@export_range(20.0,400.0,5.0) var stone_fall_height:float = 115.0
@export_range(0.05,1.5,0.01) var stone_fall_duration:float = 0.28

@export_category("棋子伤害")
@export_range(0.0,10.0,0.05) var stone_touch_damage_multiplier:float = 1.0
@export_range(0.0,10.0,0.05) var stone_chain_bonus_damage_multiplier:float = 0.75
@export_range(0.0,30.0,0.05) var five_link_damage_multiplier:float = 15.0
@export_range(0.05,1.0,0.01) var board_flash_duration:float = 0.16
@export var stone_hit_audio:String = "balls_hit1"
@export var five_link_audio:String = "God"

var _board_controller:Node = null
var _color_slot:int = -1
var _place_left:float = 0.0
var _registered:bool = false


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	_place_left = randf_range(0.35,maxf(place_interval,0.4))
	super._ready()
	# V276：棋盘控制器不是 PackedScene，MultiplayerSpawner 不会自动复制 script.new() 节点。
	# 因此每个 peer 都建立同名本地控制器；只有 authority 负责真正落子/伤害，
	# 棋子视觉则由控制器 RPC 按同一格子复制到所有客户端。
	call_deferred("_register_to_board")


func _register_to_board() -> void:
	if not is_instance_valid(self) or health <= 0:
		return
	_board_controller = _get_or_create_board_controller()
	if _board_controller == null:
		return
	_color_slot = int(_board_controller.call("register_player",self))
	if _color_slot < 0:
		# 规则判定只由 authority 改生命；远端只是不注册第三名棋手。
		if is_multiplayer_authority():
			health = 0
		return
	_registered = true


func _get_or_create_board_controller() -> Node:
	var existing:Array[Node] = get_tree().get_nodes_in_group("__gomoku_board_controller")
	if not existing.is_empty():
		return existing[0]
	var controller:Node = BOARD_CONTROLLER_SCRIPT.new()
	controller.name = "GomokuBoardController"
	get_tree().current_scene.add_child(controller)
	return controller


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and _registered and state != State.Die and health > 0:
		_place_left -= delta
		if _place_left <= 0.0:
			if _board_controller != null and is_instance_valid(_board_controller):
				_board_controller.call("request_place",self)
			_place_left = maxf(place_interval,0.2)
	super.tick_physics(state,delta)


func play_chess_place_sfx(position_value:Vector2) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_play_chess_place_sfx.rpc(position_value)
	else:
		_rpc_play_chess_place_sfx(position_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_chess_place_sfx(position_value:Vector2) -> void:
	LOCAL_SFX.play(self,"stone_land",position_value,-12.0,randf_range(1.10,1.24),430.0)


func _unregister() -> void:
	if not _registered:
		return
	_registered = false
	if _board_controller != null and is_instance_valid(_board_controller):
		_board_controller.call("unregister_player",self)
	_board_controller = null


func _exit_tree() -> void:
	_unregister()


func Die() -> void:
	_unregister()
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
