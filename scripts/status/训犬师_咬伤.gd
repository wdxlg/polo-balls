extends Node2D

@export_range(1.0,60.0,0.5) var duration:float = 20.0
@export_range(1,8,1) var max_stacks:int = 2
@export_range(0.0,2.0,0.005) var damage_per_second_multiplier:float = 0.03

var target:ball = null
var source:ball = null
var stacks:int = 1
var remaining:float = 20.0
var _tick_left:float = 1.0
var _damage_bank:float = 0.0

func setup(new_target:ball,new_source:ball) -> void:
	target = new_target
	source = new_source
	stacks = 1
	remaining = duration
	_tick_left = 1.0

func add_stack(new_source:ball) -> void:
	if new_source != null and is_instance_valid(new_source):
		source = new_source
	stacks = mini(stacks + 1,maxi(max_stacks,1))
	remaining = duration

func _process(_delta:float) -> void:
	if target != null and is_instance_valid(target):
		global_position = target.global_position

func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		queue_free()
		return
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
		return
	_tick_left -= delta
	while _tick_left <= 0.0:
		_tick_left += 1.0
		if source == null or not is_instance_valid(source):
			continue
		_damage_bank += source.attack_damage(damage_per_second_multiplier) * float(stacks)
		var whole_damage:int = int(floor(_damage_bank))
		if whole_damage <= 0:
			continue
		_damage_bank -= float(whole_damage)
		target.receive_positional_damage(float(whole_damage),target.global_position,false,source)
