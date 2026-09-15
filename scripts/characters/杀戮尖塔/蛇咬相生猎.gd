extends ball

var knife := preload("res://scenes/shooter/蛇咬.tscn")
var knife_random_range:float = 5

func Attack() -> void:
	super()
	var world:World = get_tree().current_scene
	
	var new_knife:ball
	var enemy = Target_Enemy if Target_Enemy else Nearest_Enemy
	if (enemy or has_player_control_aim()) and is_multiplayer_authority():
		Attacking = true
		var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(enemy) - global_position)
		var angle:float = dir.angle()
		var border:Dictionary = world.return_now_map_border()
		
		var attack_amount:int = 1
		var self_buffs:Dictionary = Buff_Dic.get(self.get_instance_id(), {})
		var count_buff = self_buffs.get("次数", null)
		if count_buff != null:
			attack_amount = maxi(1, int(count_buff.amount))
		
		for i in attack_amount:
			new_knife = knife.instantiate()
			new_knife.set_collision_layer_value(2,false)
			new_knife.Master = self
			new_knife.Master_name = self.name
			new_knife.Team = Team
			new_knife.Speed += Speed
			new_knife.global_position = Vector2(
				clampf(global_position.x + randf_range(-knife_random_range,knife_random_range),border.start.x,border.end.x),
				clampf(global_position.y + randf_range(-knife_random_range,knife_random_range),border.start.y,border.end.y)
			)

			new_knife.global_rotation = new_knife.Default_Rotation + angle
			new_knife.direction = dir.normalized()

			new_knife.name = Game.return_random_name(new_knife)
			world.add_child(new_knife,true)
			
		Audios.play_sfx.rpc("蛇叫",{},true)
		
		if attack_amount <= 32:
			world.new_buff(self,self,"次数",Buff.new(3,INF,Buff.Buff_types.Attack_Amount,2,Buff.Algorithms.Set),"mul")
		
		
		await get_tree().create_timer(0.18).timeout
		Attacking = false
	

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
