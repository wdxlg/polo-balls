extends ball

var status_texture := "parry"

func tick_physics(state:State,delta:float) -> void:
	super(state,delta)

	if not Master:Game.free_node(self)
	if default_properties and "rotation" in default_properties:
		global_rotation = default_properties.rotation + direction.angle()
	else:
		global_rotation = direction.angle()

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	var world = get_tree().current_scene
	
	if Master and Master.state_machine.current_state != ball.State.Die:
		Audios.play_sfx("Defense" + str(randi_range(1,4)))
		#Master.set_status_image(status_texture)
		if is_multiplayer_authority():world.set_status_image.rpc(status_texture,Master.global_position)
		
		Master.block += Damage/2
