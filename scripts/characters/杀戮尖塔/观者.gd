extends ball

enum Char_states {
	normal,
	red,
	blue,
	god
}
var red_texture := "eruption"
var blue_texture := "vigilance"
var god_texture := "deva_form"

func _ready() -> void:
	super()
	
	char_state = Char_states.normal

func Skill() -> void:
	super()
	var world:World = get_tree().current_scene
	
	char_state = char_state + 1 if char_state + 1 < Char_states.size() else 0
	if char_state == 0:
		world.new_buff(self,self,"攻击",Buff.new(),"delete")
		world.new_buff(self,self,"速度",Buff.new(),"delete")
		world.new_buff(self,self,"伤害减免",Buff.new(),"delete")

		Audios.play_sfx("Debuff" + str(randi_range(1,3)))
	elif char_state == 1:
		world.new_buff(self,self,"攻击",Buff.new(2,Skill_Cooling,Buff.Buff_types.Damage,2,Buff.Algorithms.mul))
		world.new_buff(self,self,"速度",Buff.new(2,Skill_Cooling,Buff.Buff_types.Speed,2,Buff.Algorithms.mul))
		world.new_buff(self,self,"伤害减免",Buff.new(3,Skill_Cooling,Buff.Buff_types.Damage_reduction,-1,Buff.Algorithms.Set))
		
		if is_multiplayer_authority():world.set_status_image.rpc(red_texture,global_position)
		Audios.play_sfx("Red")
	elif char_state == 2:
		world.new_buff(self,self,"攻击",Buff.new(2,Skill_Cooling,Buff.Buff_types.Damage,0.5,Buff.Algorithms.mul))
		world.new_buff(self,self,"速度",Buff.new(2,Skill_Cooling,Buff.Buff_types.Speed,0.5,Buff.Algorithms.mul))
		world.new_buff(self,self,"伤害减免",Buff.new(3,Skill_Cooling,Buff.Buff_types.Damage_reduction,1,Buff.Algorithms.Set))
		
		if is_multiplayer_authority():world.set_status_image.rpc(blue_texture,global_position)
		Audios.play_sfx("Blue")
	elif char_state == 3:
		world.new_buff(self,self,"攻击",Buff.new(2,Skill_Cooling,Buff.Buff_types.Damage,2,Buff.Algorithms.mul))
		world.new_buff(self,self,"速度",Buff.new(2,Skill_Cooling,Buff.Buff_types.Speed,2,Buff.Algorithms.mul))
		world.new_buff(self,self,"伤害减免",Buff.new(3,Skill_Cooling,Buff.Buff_types.Damage_reduction,1,Buff.Algorithms.Set))
		
		if is_multiplayer_authority():world.set_status_image.rpc(god_texture,global_position)
		Audios.play_sfx("God")

func Die() -> void:
	super()
	
	await get_tree().create_timer(2).timeout
	Game.free_node(self)
