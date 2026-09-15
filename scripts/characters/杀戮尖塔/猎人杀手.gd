extends ball

var status_texture := "wound"

func _on_hurtbox_on_hurt(hit: hitbox) -> void:
	super(hit)
	if not is_multiplayer_authority():return
	
	var world = get_tree().current_scene
	
	if state_machine.current_state == State.Die:return
	var enemy:Node
	
	if not hit.owner.Master:enemy = hit.owner as ball
	else: enemy = hit.owner.Master as ball
	world.new_buff(enemy,self,"攻击",Buff.new(2,1,Buff.Buff_types.Damage,-1,Buff.Algorithms.add),"add")
	world.new_buff(enemy,self,"速度",Buff.new(2,1,Buff.Buff_types.Speed,-1,Buff.Algorithms.add),"add")
	
	Audios.play_sfx("Debuff" + str(randi_range(1,3)))
	if is_multiplayer_authority():world.set_status_image.rpc(status_texture,enemy.global_position)
	
	
func Die() -> void:
	super()
	
	await get_tree().create_timer(2).timeout
	Game.free_node(self)
	
