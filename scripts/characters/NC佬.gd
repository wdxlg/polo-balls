extends "res://scripts/creatures/投稿随从.gd"

const MINION_SCENE:PackedScene = preload("res://scenes/creatures/投稿随从.tscn")
const TOOLS_NC = preload("res://scripts/characters/投稿角色工具.gd")

@export_range(1,4,1) var squad_size:int = 4
@export_range(1,12,1) var global_nc_cap:int = 12
@export_range(1.0,240.0,1.0) var tank_trigger_time:float = 120.0

var _squad_spawned:bool = false
var _tank_spawned:bool = false
var _squad_elapsed:float = 0.0

func _enter_tree() -> void:
	# NC佬本体必须在 ball 的 @onready 生命初始化前就确定种类。
	kind = Kind.NC_RIFLE
	super._enter_tree()

func _ready() -> void:
	kind = Kind.NC_RIFLE
	super._ready()
	if is_multiplayer_authority():
		call_deferred("_spawn_squad")

func _physics_process(delta:float) -> void:
	super(delta)
	if not is_multiplayer_authority() or health <= 0:
		return
	_squad_elapsed += delta
	if not _tank_spawned and _squad_elapsed >= tank_trigger_time:
		_tank_spawned = true
		_spawn_unit(Kind.NC_TANK,true)

func _spawn_squad() -> void:
	if _squad_spawned:
		return
	_squad_spawned = true
	# 自己已经算一个；只补到“单个场景最多四个”。
	for i:int in range(maxi(squad_size - 1,0)):
		if get_tree().get_nodes_in_group("SubmissionNCUnit").size() >= global_nc_cap:
			break
		_spawn_unit(Kind.NC_RIFLE,false)

func _spawn_unit(kind_value:int,is_tank:bool) -> void:
	var rect:Rect2 = TOOLS_NC.map_rect(self)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var unit:ball = MINION_SCENE.instantiate() as ball
	if unit == null:
		return
	unit.Master = self
	unit.Master_name = name
	unit.Team = Team
	unit.inherit_master_attack_power = true
	unit.Target_Enemy = Target_Enemy
	unit.set("kind",kind_value)
	unit.name = Game.return_random_name(unit)
	get_tree().current_scene.add_child(unit,true)
	var side:int = randi_range(0,3)
	var p:Vector2
	match side:
		0: p = Vector2(randf_range(rect.position.x + 20.0,rect.end.x - 20.0),rect.position.y + 24.0)
		1: p = Vector2(randf_range(rect.position.x + 20.0,rect.end.x - 20.0),rect.end.y - 24.0)
		2: p = Vector2(rect.position.x + 24.0,randf_range(rect.position.y + 20.0,rect.end.y - 20.0))
		_: p = Vector2(rect.end.x - 24.0,randf_range(rect.position.y + 20.0,rect.end.y - 20.0))
	unit.global_position = p
	if is_tank:
		unit.scale *= 1.35
