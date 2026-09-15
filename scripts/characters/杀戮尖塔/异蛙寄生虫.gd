extends ball

var bug := preload("res://scenes/characters/杀戮尖塔/异蛙寄生虫_小.tscn")
var bug_random_range:float = 10

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	
	if not is_multiplayer_authority() or state_machine.current_state == State.Die:return
	var world:World = get_tree().current_scene
	
	var target:ball = _hurtbox_target_ball(hurt)
	if target != null:
		world.new_buff(target,self,"寄生",Buff.new(1,Skill_Cooling,Buff.Buff_types.Infection,1,Buff.Algorithms.Set),"add")
	
func Skill() -> void:
	super()
	if not is_multiplayer_authority():return
	var world:World = get_tree().current_scene
	
	world.create_new_particle.rpc("蛆",self,Vector2.ZERO,0.2,null,true)
	world.create_new_particle.rpc("汁液",self,Vector2.ZERO,0.2,null,true)
	Audios.play_sfx.rpc("蛆生",{},true)

	var border:Dictionary = world.return_now_map_border()
	create_newbug(border)
func create_newbug(border:Dictionary) -> ball:
	var world:World = get_tree().current_scene
	
	var new_bug:ball = bug.instantiate()
	new_bug.Master = self
	new_bug.Master_name = self.name
	new_bug.Team = Team
	new_bug.Target_Enemy = Target_Enemy if is_instance_valid(Target_Enemy) else Nearest_Enemy

	new_bug.global_position = Vector2(
		clampf(global_position.x + randf_range(-bug_random_range,bug_random_range),border.start.x,border.end.x),
		clampf(global_position.y + randf_range(-bug_random_range,bug_random_range),border.start.y,border.end.y)
		)
	
	new_bug.name = Game.return_random_name(new_bug)
	world.add_child(new_bug,true)
	return new_bug
	
func Die() -> void:
	super()
	var world:World = get_tree().current_scene
	
	world.create_new_particle.rpc("蛆",self,Vector2.ZERO,1,null,true)
	world.create_new_particle.rpc("汁液",self,Vector2.ZERO,1,null,true)
	Audios.play_sfx.rpc("蛆爆炸",{},true)
	for i in 4:
		var border:Dictionary = world.return_now_map_border()
		create_newbug(border)
	
	await get_tree().create_timer(1).timeout
	Game.free_node(self)
	
