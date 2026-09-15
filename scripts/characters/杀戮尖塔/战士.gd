extends ball

func Attack() -> void:
	super()
	var world:World = get_tree().current_scene

	Attacking = true
	
	Audios.play_sfx("战士attack1",{},true)
	
	world.new_buff(self,self,"攻击",Buff.new(2,0.5,Buff.Buff_types.Damage,6,Buff.Algorithms.mul))
	world.new_buff(self,self,"速度",Buff.new(2,1,Buff.Buff_types.Speed,0.1,Buff.Algorithms.mul))

	self_hitbox.scale.x = 2.3
	self_hitbox.position.x = 110

	await get_tree().create_timer(1).timeout
	Attacking = false
		
	#Damage = default_properties.Damage
	#Speed = default_properties.Speed
	self_hitbox.scale = defualt_collision.Hitbox.scale
	self_hitbox.position = defualt_collision.Hitbox.position

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	
	if Attacking:
		var target:ball = _hurtbox_target_ball(hurt)
		if target != null:
			# V10.1：旧版这里直接写一帧 Repel，会产生明显的瞬移式小抖动，
			# 也绕过了通用击退的距离、末段刹车和多人命中合并。
			# 改成统一走 apply_knockback()，保留“伤害越高推得越明显”的感觉。
			var attack_direction:Vector2 = direction
			if attack_direction.length_squared() <= 0.0001:
				attack_direction = global_position.direction_to(target.global_position)
			target.apply_knockback(
				attack_direction,
				clampf(float(Damage) * 1.15,18.0,72.0),
				clampf(float(Damage) * 22.0,360.0,760.0),
				0.0,
				0.0,
				{
					"source": self,
					"lock_control": true,
					"stop_on_character": true,
				}
			)

func transition_state(from:State,to:State) -> void:
	super(from,to)

	match to:
		State.Stand:
			image.animation = "Idle"
		State.Attack:
			image.animation = "Attack"
		State.Die:
			image.animation = "Die"
		State.Hurt:
			hurting_timer.start(0.5)
			image.animation = "Hurt"
			
func Die() -> void:
	super()
	
	await get_tree().create_timer(2).timeout
	Game.free_node(self)
