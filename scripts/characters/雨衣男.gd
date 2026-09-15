extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

@export_category("雨衣男 - 沉沦")
@export_range(0.2,5.0,0.05) var umbrella_attack_interval:float = 1.55
@export_range(0.0,10.0,0.05) var umbrella_damage_multiplier:float = 1.0
@export_range(20.0,120.0,2.0) var umbrella_range:float = 52.0
@export_range(1,8,1) var drowning_max_stacks:int = 4
@export_range(0.01,0.5,0.01) var drowning_per_stack:float = 0.10
@export_range(1.0,30.0,0.5) var drowning_duration:float = 8.0
@export_range(0.0,10.0,0.05) var bandage_damage_multiplier:float = 4.0
@export_range(0.05,2.0,0.05) var bandage_duration:float = 0.32

var _attack_elapsed:float = 0.0
var _self_stacks:int = 0
var _enemy_stacks:Dictionary = {}
var _enemy_stack_times:Dictionary = {}

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	# V107：本轮未提供雨衣男场景；旧脚本曾强制把基础攻击写成50。
	# 仅当场景仍沿用 ball 默认10时做兼容迁移；任何显式设置成其它数值的 Damage 都保留。
	if Damage == 10:
		Damage = 50
	super._ready()
	if self_hitbox != null:
		self_hitbox.monitoring = false

func _process(delta:float) -> void:
	if not is_multiplayer_authority() or health <= 0:
		return
	_attack_elapsed += delta
	_cleanup_expired_stacks()
	if _attack_elapsed < umbrella_attack_interval:
		return
	var target:ball = TOOLS.nearest_enemy(self,umbrella_range)
	if target == null:
		return
	_attack_elapsed = 0.0
	_swing_umbrella(target)

func _swing_umbrella(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var self_multiplier:float = 1.0 + float(_self_stacks) * drowning_per_stack
	target.receive_positional_damage(attack_damage(umbrella_damage_multiplier * self_multiplier),global_position,false,self)
	_apply_enemy_stack(target)
	_self_stacks = mini(_self_stacks + 1,drowning_max_stacks)
	_refresh_self_buff()
	if _self_stacks >= drowning_max_stacks:
		_bandage_strike(target)
		_self_stacks = 0
		_refresh_self_buff()

func _apply_enemy_stack(target:ball) -> void:
	var id:int = target.get_instance_id()
	var stacks:int = mini(int(_enemy_stacks.get(id,0)) + 1,drowning_max_stacks)
	_enemy_stacks[id] = stacks
	_enemy_stack_times[id] = Time.get_ticks_msec()
	var world = get_tree().current_scene
	if world != null and world.has_method("new_buff"):
		var multiplier:float = maxf(0.1,1.0 - float(stacks) * drowning_per_stack)
		world.new_buff(target,self,"沉沦",Buff.new(2,drowning_duration,Buff.Buff_types.Damage,multiplier,Buff.Algorithms.mul),"cover")

func _refresh_self_buff() -> void:
	var world = get_tree().current_scene
	if world == null or not world.has_method("new_buff"):
		return
	if _self_stacks <= 0:
		world.new_buff(self,self,"沉沦_自身",Buff.new(),"delete")
		return
	var multiplier:float = 1.0 + float(_self_stacks) * drowning_per_stack
	world.new_buff(self,self,"沉沦_自身",Buff.new(2,drowning_duration,Buff.Buff_types.Damage,multiplier,Buff.Algorithms.mul),"cover")

func _cleanup_expired_stacks() -> void:
	var now:int = Time.get_ticks_msec()
	var expired:Array[int] = []
	for raw_id:Variant in _enemy_stack_times.keys():
		var id:int = int(raw_id)
		if now - int(_enemy_stack_times[id]) > int(drowning_duration * 1000.0):
			expired.append(id)
	for id:int in expired:
		_enemy_stack_times.erase(id)
		_enemy_stacks.erase(id)

func _bandage_strike(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var rect:Rect2 = TOOLS.map_rect(self)
	var start:Vector2 = target.global_position
	if rect.size.x > 1.0 and rect.size.y > 1.0:
		var distances := PackedFloat32Array([
			absf(target.global_position.x - rect.position.x),
			absf(rect.end.x - target.global_position.x),
			absf(target.global_position.y - rect.position.y),
			absf(rect.end.y - target.global_position.y),
		])
		var best:int = 0
		for i:int in range(1,distances.size()):
			if distances[i] < distances[best]:
				best = i
		match best:
			0: start = Vector2(rect.position.x,target.global_position.y)
			1: start = Vector2(rect.end.x,target.global_position.y)
			2: start = Vector2(target.global_position.x,rect.position.y)
			_: start = Vector2(target.global_position.x,rect.end.y)
	_show_bandage(start,target.global_position)
	target.receive_positional_damage(attack_damage(bandage_damage_multiplier),target.global_position,true,self)

func _show_bandage(start:Vector2,end:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var line := Line2D.new()
	line.width = 7.0
	line.default_color = Color(0.75,0.03,0.08,0.95)
	line.antialiased = true
	line.z_index = 15
	line.points = PackedVector2Array([start,end])
	world.add_child(line)
	var tween:Tween = line.create_tween()
	tween.tween_property(line,"modulate:a",0.0,bandage_duration)
	tween.finished.connect(line.queue_free)
