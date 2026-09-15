extends ball

func move(speed:float,delta:float):
	super(speed,delta)

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	if not is_multiplayer_authority():return
	var world:World = get_tree().current_scene
	var target:ball = _hurtbox_target_ball(hurt)

	if target != null:
		world.new_buff(target,self,"毒",Buff.new(3,INF,Buff.Buff_types.poison,7,Buff.Algorithms.Set),"add")
	state_machine.current_state = State.Die

func when_collide(_speed:float,_collision:KinematicCollision2D):
	if not is_multiplayer_authority():return
	
	if Collide_Audio != "":
		Audios.play_sfx(Collide_Audio ,{},true)
	
	state_machine.current_state = State.Die
	
func Die() -> void:
	if not is_multiplayer_authority():return
	image.visible = false
	
	await get_tree().create_timer(0.1).timeout
	Game.free_node(self)
