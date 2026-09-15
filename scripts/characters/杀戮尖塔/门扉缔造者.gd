extends ball

enum Char_states {
	normal,
	eat,
	eye,
	hand
}
var Hand := preload("res://scenes/creatures/门扉缔造者_手.tscn")
var hand_random_range:float = 10

func _ready() -> void:
	super()
	var world:World = get_tree().current_scene
	
	char_state = Char_states.normal
	world.new_buff(self,self,"攻击",Buff.new(3,Skill_Cooling,Buff.Buff_types.Damage,0,Buff.Algorithms.Set))
	world.new_buff(self,self,"伤害减免",Buff.new(3,Skill_Cooling,Buff.Buff_types.Damage_reduction,1,Buff.Algorithms.Set))

func Skill() -> void:
	super()
	var world:World = get_tree().current_scene
	
	char_state = char_state + 1 if char_state + 1 < Char_states.size() else 0
	if char_state == 0:
		image.animation = "default"
		for c in Creatures:
			if c:Game.free_node(c)
		world.new_buff(self,self,"攻击",Buff.new(3,Skill_Cooling,Buff.Buff_types.Damage,0,Buff.Algorithms.Set))
		world.new_buff(self,self,"伤害减免",Buff.new(3,Skill_Cooling,Buff.Buff_types.Damage_reduction,1,Buff.Algorithms.Set))

		Audios.play_sfx("Buff" + str(randi_range(1,3)))
	elif char_state == 1:
		image.animation = "eat"
		
		var enemy:ball = Target_Enemy if Target_Enemy else Nearest_Enemy
		if enemy and enemy != null:
			var buffs = enemy.Buff_Dic
			var id := enemy.get_instance_id()
			if id in buffs:
				for buff:String in buffs[id]:
					var target_buff:Buff = buffs[id][buff]
					
					world.new_buff(enemy,enemy,buff,Buff.new(),"delete")
					world.new_buff(self,self,buff,Buff.new(
						target_buff.index,
						Skill_Cooling,
						target_buff.buff_type,
						target_buff.amount,
						target_buff.algorithm
					))
		Audios.play_sfx("Buff" + str(randi_range(1,3)))
	elif char_state == 2:
		image.animation = "eye"
		
		var enemy:ball = Target_Enemy if Target_Enemy else Nearest_Enemy
		if enemy:
			world.new_buff(enemy,self,"速度",Buff.new(3,Skill_Cooling,Buff.Buff_types.Speed,1,Buff.Algorithms.Set))
		
		
		Audios.play_sfx("Debuff" + str(randi_range(1,3)))
	elif char_state == 3:
		image.animation = "hand"
		
		var new_hand := Hand.instantiate()
		new_hand.Master = self
		new_hand.Master_name = self.name
		new_hand.Team = Team
		Creatures.append(new_hand)
	
		new_hand.global_position = global_position
		var border:Dictionary = get_tree().current_scene.return_now_map_border()
	
		new_hand.global_position = Vector2(
			clampf(global_position.x + randf_range(-hand_random_range,hand_random_range),border.start.x,border.end.x),
			clampf(global_position.y + randf_range(-hand_random_range,hand_random_range),border.start.y,border.end.y)
			)
		
		#var spawner = world.return_spawner()
		new_hand.name = Game.return_random_name(new_hand)
		world.add_child(new_hand,true)
		Audios.play_sfx("Debuff" + str(randi_range(1,3)))

func Die() -> void:
	super()
	
	await get_tree().create_timer(2).timeout
	Game.free_node(self)
