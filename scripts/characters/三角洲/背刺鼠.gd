extends ball

var bullet := preload("res://scenes/shooter/子弹.tscn")

func _ready() -> void:
	# 背刺鼠：
	# 同时允许敌军和友军成为目标，然后只比较距离。
	# 最近的是友军就打友军，最近的是敌军就打敌军。
	#
	# Ignore_Team_Damage_Setting=true：
	# 即使全局关闭友伤，锁到友军后自己的子弹仍然可以造成伤害。
	#
	# 这三个属性都来自公共 ball.gd，其他角色也可以在 Inspector 中复用。
	Can_Target_Teammates = true
	Prefer_Teammates = false
	Ignore_Team_Damage_Setting = true
	super._ready()

func tick_physics(state:State,delta:float) -> void:
	super(state,delta)
	if has_player_control_aim():
		return
	
	var enemy = return_reusable_combat_target()
	if enemy and direction.dot(combat_target_position(enemy) - global_position) > 0 and enemy.direction.dot(global_position - combat_target_position(enemy)) < 0 and not Attacking:
		Attacking = true
		image.animation = "Attack"
		Audios.play_sfx.rpc("我的浮木死了")
	elif (not enemy or direction.dot(combat_target_position(enemy) - global_position) <= 0 or enemy.direction.dot(global_position - combat_target_position(enemy)) >= 0) and Attacking:
		Attacking = false
		image.animation = "default"
		Audios.play_sfx.rpc("蜂医新年快乐")
func Attack() -> void:
	super()
	if not has_player_control_aim() or not is_multiplayer_authority():
		return
	if state_machine.current_state == State.Die or is_damage_output_disabled():
		Attacking = false
		return
	Attacking = true
	image.animation = "Attack"
	continue_attack()
	await get_tree().create_timer(maxf(continue_attack_cooling + 0.04,0.10)).timeout
	if is_instance_valid(self) and state_machine != null and state_machine.current_state != State.Die:
		Attacking = false
		image.animation = "default"

func continue_attack() -> void:
	super()
	
	if state_machine.current_state == State.Die or not is_multiplayer_authority():return
	var world:World = get_tree().current_scene
	
	var enemy = return_reusable_combat_target()
	if enemy or has_player_control_aim():
		var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(enemy) - global_position)
		if dir.length_squared() <= 0.000001:
			return
		var angle:float = dir.angle()
		var new_bullet:ball
		new_bullet = bullet.instantiate()
		new_bullet.set_collision_layer_value(2,false)
		new_bullet.Master = self
		new_bullet.Master_name = self.name
		new_bullet.Team = Team
		new_bullet.Speed += Speed
		new_bullet.Damage = Damage
		
		new_bullet.global_position = global_position
		new_bullet.global_rotation = new_bullet.Default_Rotation + angle
		new_bullet.direction = dir.normalized()
		
	#var spawner = world.return_spawner()
		new_bullet.name = Game.return_random_name(new_bullet)
		world.add_child(new_bullet,true)
		Audios.play_sfx.rpc("Mp7单发",{},true,true)
	
func Die() -> void:
	super()
	
	await get_tree().create_timer(1).timeout
	Game.free_node(self)
