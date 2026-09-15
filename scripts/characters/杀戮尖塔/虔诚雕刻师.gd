extends ball

var status_texture := "demon_form"

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	
	Audios.play_sfx("KakaHurt" + str(randi_range(1,3)))
	state_machine.current_state = State.Attack
	Attacking = true
	
	await get_tree().create_timer(0.5).timeout
	Attacking = false

func Skill() -> void:
	super()
	var world:World = get_tree().current_scene
	
	#set_status_image(status_texture)
	if is_multiplayer_authority():world.set_status_image.rpc(status_texture,global_position)
	Audios.play_sfx("Buff" + str(randi_range(1,3)))
	
	Audios.play_sfx("KakaSkill" + str(randi_range(1,3)))
	Using_Skill = true
	
	world.new_buff(self,self,"攻击",Buff.new(1,INF,Buff.Buff_types.Damage,9,Buff.Algorithms.add),"add")
	
	await get_tree().create_timer(0.5).timeout
	Using_Skill = false

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
		State.Skill:
			image.animation = "Skill"
			
func Die() -> void:
	super()
	
	await get_tree().create_timer(2).timeout
	Game.free_node(self)
