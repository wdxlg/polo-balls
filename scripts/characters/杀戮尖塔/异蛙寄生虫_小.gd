extends ball

func _ready() -> void:
	var auto_fit := get_node_or_null("CharacterAutoFit")
	if auto_fit != null:
		auto_fit.set("visual_size_multiplier",0.52)
		auto_fit.set("collision_width_ratio",0.84)
		auto_fit.set("collision_height_ratio",0.80)
		if auto_fit.has_method("apply_fit"):
			auto_fit.call("apply_fit")
	super._ready()

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	if not is_multiplayer_authority() or state_machine.current_state == State.Die:return
	var world:World = get_tree().current_scene
	
	var target:ball = _hurtbox_target_ball(hurt)
	if target != null:
		world.new_buff(target,self,"寄生",Buff.new(1,Skill_Cooling,Buff.Buff_types.Infection,1,Buff.Algorithms.Set),"add")

func Die() -> void:
	super()
	var world:World = get_tree().current_scene
	
	Audios.play_sfx.rpc("蛆爆浆",{},true)
	world.create_new_particle.rpc("蛆",self,Vector2.ZERO,0.2,null,true)
	world.create_new_particle.rpc("汁液",self,Vector2.ZERO,0.2,null,true)
	
	Game.free_node(self)
