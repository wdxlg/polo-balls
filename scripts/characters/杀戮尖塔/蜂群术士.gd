extends ball

var bee := preload("res://scenes/shooter/bee.tscn")
var status_texture := "dazed"
var bee_random_range:float = 20
@export_range(0.0,10.0,0.05) var bee_damage_multiplier:float = 4.0
@export_range(0.0,10.0,0.05) var retaliation_damage_multiplier:float = 1.0

func Attack() -> void:
	super()
	if state_machine.current_state == State.Die:return
	
	var enemy = Target_Enemy if Target_Enemy else Nearest_Enemy
	if enemy or has_player_control_aim():
		Attacking = true
		Speed = default_properties.Speed/2

		await get_tree().create_timer(continue_attacking_delay).timeout
		Attacking = false
		Speed = default_properties.Speed
func continue_attack() -> void:
	super()
	if state_machine.current_state == State.Die:return
	var world:World = get_tree().current_scene
	
	var new_knife:ball
	var enemy = Target_Enemy if Target_Enemy else Nearest_Enemy
	if enemy or has_player_control_aim():
		var border:Dictionary = world.return_now_map_border()
		var new_bee:ball = bee.instantiate()
		new_bee.Master = self
		new_bee.Master_name = self.name
		new_bee.Team = Team
		new_bee.Speed = randf_range(default_properties.Speed/2,default_properties.Speed * 2)
		new_bee.Damage = maxi(int(round(attack_damage(bee_damage_multiplier))),1)
		new_bee.Target_Enemy = null if has_player_control_aim() else enemy
		
		new_bee.global_position = Vector2(
			clampf(global_position.x + randf_range(-bee_random_range,bee_random_range),border.start.x,border.end.x),
			clampf(global_position.y + randf_range(-bee_random_range,bee_random_range),border.start.y,border.end.y)
			)
		var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(enemy) - new_bee.global_position)
		if dir.length_squared() <= 0.000001:
			dir = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
		var angle:float = dir.angle()
			
		new_bee.global_rotation = new_bee.Default_Rotation + angle
		new_bee.direction = dir.normalized()
		
		#var spawner = world.return_spawner()
		new_bee.name = Game.return_random_name(new_bee)
		world.add_child(new_bee,true)
		Audios.play_sfx("Bee" + str(randi_range(1,3)),{},true)
		
		continue_attack_cooling = randf_range(0.1,0.3)

func transition_state(from:State,to:State) -> void:
	super(from,to)

	match to:
		State.Stand:
			animation_player.play("Idle")
		State.Attack:
			animation_player.play("Attack")
		State.Die:
			animation_player.play("Die")
		State.Hurt:
			animation_player.play("Hurt")
			hurting_timer.start(0.5)

func _on_hurtbox_on_hurt(hit: hitbox) -> void:
	super(hit)
	if not is_multiplayer_authority():return
	var world:World = get_tree().current_scene
	
	if state_machine.current_state == State.Die:return
	var enemy:Node
	
	if not hit.owner.Master:enemy = hit.owner as ball
	else: enemy = hit.owner.Master as ball
	
	if not enemy:return
	enemy.receive_spatial_damage(
		attack_damage(retaliation_damage_multiplier),
		{"shape":"all","source":self},
		ignore_block
	)
	
	Audios.play_sfx("Debuff" + str(randi_range(1,3)))
	#enemy.set_status_image(status_texture)
	
	if is_multiplayer_authority():world.set_status_image.rpc(status_texture,enemy.global_position)
	
	# 使用 ball 的统一眩晕接口：控制锁、叠加计数和眩晕动画都由基类处理。
	enemy.apply_stun(0.1)
	
func _ready() -> void:
	super()
	
	get_tree().current_scene.create_new_particle("Bee_In_Char",self)
	
func Die() -> void:
	super()
	
	await get_tree().create_timer(2).timeout
	Game.free_node(self)
