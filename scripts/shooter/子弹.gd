extends ball

# 通用“枪械子弹”：目前由三角洲的两名角色，以及小丑的坏手枪使用。
# 只替换命中/撞墙音效，不改任何贴图、尺寸或飞行视觉。

var _impact_sfx_played:bool = false


func _ready() -> void:
	# 避免 ball.gd 再额外播放旧的 balls_hit1 / 默认碰撞音，
	# 子弹命中结果统一由下面的“打人 / 打墙(含被防御)”两套音效负责。
	Hit_Audio = ""
	Collide_Audio = ""
	super._ready()


func move(speed:float,delta:float):
	super(speed,delta)


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if not is_multiplayer_authority():
		return

	var target:ball = _hurtbox_target_ball(hurt)

	# V361 AWM 特例：仍然使用这一个“夺舍狼同款 子弹.tscn”，
	# 但这颗子弹带 berserker_raw_health_damage metadata 时直接扣目标 health。
	# 不调用 receive_positional_damage / receive_spatial_damage / take_damage，
	# 因而不会被 block、Damage_reduction 或角色覆写的伤害免疫入口拦截。
	if bool(get_meta(&"berserker_raw_health_damage",false)):
		_apply_berserker_raw_health_hit(target)
		state_machine.current_state = State.Die
		return

	var before_health:float = float(target.health) if target != null and is_instance_valid(target) else 0.0
	var before_block:float = float(target.block) if target != null and is_instance_valid(target) else 0.0

	# 其它所有使用该通用子弹的角色继续走公共 ball.gd 伤害规则。
	super(hurt)

	if target != null and is_instance_valid(target):
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		# 只要发生格挡/护盾吸收，或者完全没有伤到生命，都视为“硬碰撞/被防御”。
		if block_loss > 0.0 or health_loss <= 0.0:
			_play_bullet_impact_sfx("子弹打墙",1.0)
		else:
			_play_bullet_impact_sfx("子弹打人",0.0)

	state_machine.current_state = State.Die


func _apply_berserker_raw_health_hit(target:ball) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		_play_bullet_impact_sfx("子弹打墙",1.0)
		return

	var before_health:float = float(target.health)
	var raw_damage:int = maxi(int(Damage),0)
	if raw_damage <= 0:
		_play_bullet_impact_sfx("子弹打墙",1.0)
		return

	# 直接走 health setter：仍会触发角色自己的真实扣血/死亡/第二命等生命周期，
	# 但跳过所有“能否受伤”和护盾/减伤判断。
	target.hit_white(true)
	target.health -= raw_damage
	var health_loss:float = maxf(before_health - float(target.health),0.0)

	if health_loss > 0.0:
		var source:Node = Master if Master != null and is_instance_valid(Master) else self
		if Game.has_method("report_combat_damage"):
			Game.report_combat_damage(source,target,health_loss,before_health)

		var incoming:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT

		# V368：AWM绝对生命伤害命中后追加大击退。
		# 数值由发射者写入metadata；其它使用通用子弹.tscn的角色完全不受影响。
		var raw_knockback_distance:float = maxf(
			float(get_meta(&"berserker_raw_knockback_distance",0.0)),
			0.0
		)
		var raw_knockback_speed:float = maxf(
			float(get_meta(&"berserker_raw_knockback_speed",0.0)),
			0.0
		)
		if raw_knockback_distance > 0.0:
			target.apply_knockback(
				incoming,
				raw_knockback_distance,
				maxf(raw_knockback_speed,50.0),
				0.0,
				0.0,
				{"source":source,"lock_control":true,"stop_on_character":true}
			)

		var seed:int = Game.battle_rng_seed_or("scripts/shooter/子弹.gd:seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(target.get_instance_id()))
		target.notify_hit_burst_feedback(
			global_position,
			float(raw_damage),
			health_loss,
			0.0,
			8.0,
			seed,
			incoming
		)
		target.notify_ranged_hit_feedback(self,float(raw_damage),health_loss,0.0)
		_play_bullet_impact_sfx("子弹打人",0.0)
	else:
		_play_bullet_impact_sfx("子弹打墙",1.0)


func when_collide(_speed:float,_collision:KinematicCollision2D):
	if not is_multiplayer_authority():
		return

	_play_bullet_impact_sfx("子弹打墙",1.0)
	Speed = 0
	direction = Vector2.ZERO

	if collide_tween:
		collide_tween.kill()

	state_machine.current_state = State.Die


func _play_bullet_impact_sfx(sfx_name:String,volume_offset:float = 0.0) -> void:
	# CharacterBody2D 的实体碰撞与 Hitbox Area 在同一物理帧都可能报告命中，
	# 每颗子弹只允许播一次撞击音，避免“打人声 + 打墙声”叠在一起。
	if _impact_sfx_played:
		return
	_impact_sfx_played = true
	var params:Dictionary = {
		"volume": volume_offset,
		"pitch": randf_range(0.96,1.05),
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,false,true)
	else:
		Audios.play_sfx(sfx_name,params,false,true)


func Die() -> void:
	if not is_multiplayer_authority():
		return
	image.visible = false

	await get_tree().create_timer(0.1).timeout
	Game.free_node(self)
