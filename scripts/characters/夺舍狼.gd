extends ball

var bullet := preload("res://scenes/shooter/子弹.tscn")

func _ready() -> void:
	var auto_fit := get_node_or_null("CharacterAutoFit")
	if auto_fit != null:
		auto_fit.set("scan_all_animated_frames",false)
		auto_fit.set("refit_on_animation_change",true)
		auto_fit.set("collision_width_ratio",0.78)
		auto_fit.set("collision_height_ratio",0.76)
		auto_fit.set("collision_min_size",Vector2(40.0,55.0))
		auto_fit.set("collision_max_size",Vector2(160.0,170.0))
		if auto_fit.has_method("_connect_animation_refit_if_needed"):
			auto_fit.call("_connect_animation_refit_if_needed")
		if auto_fit.has_method("apply_fit"):
			auto_fit.call("apply_fit")
	super._ready()

func Skill() -> void:
	if not is_multiplayer_authority() or Attacking:return
	
	var world:World = get_tree().current_scene
	world.new_buff(self,self,"速度",Buff.new(3,INF,Buff.Buff_types.Speed,1,Buff.Algorithms.Set))
	image.animation = "Attack"
func tick_physics(state:State,delta:float) -> void:
	super(state,delta)
	var world:World = get_tree().current_scene
	
	var enemy = Target_Enemy if Target_Enemy else Nearest_Enemy
	if not has_player_control_aim() and enemy and not Attacking and (enemy.global_position - global_position).length() <= 50 and image.animation == "Attack":
		Attacking = true

		await get_tree().create_timer(2).timeout
		world.new_buff(self,self,"速度",Buff.new(),"delete")
		image.animation = "default"
		Attacking = false
func Attack() -> void:
	super()
	if not has_player_control_aim() or not is_multiplayer_authority():
		return
	if state_machine.current_state == State.Die or is_damage_output_disabled():
		Attacking = false
		return
	Attacking = true
	image.animation = "Attack"
	continue_attack()
	await get_tree().create_timer(maxf(continue_attack_cooling + 0.04,0.12)).timeout
	if is_instance_valid(self) and state_machine != null and state_machine.current_state != State.Die:
		Attacking = false
		image.animation = "default"

func continue_attack() -> void:
	super()
	
	if state_machine.current_state == State.Die or not is_multiplayer_authority():return
	var world:World = get_tree().current_scene
	
	var enemy = Target_Enemy if Target_Enemy else Nearest_Enemy
	if enemy or has_player_control_aim():
		var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(enemy) - global_position)
		if dir.length_squared() <= 0.000001:
			return
		var angle:float = dir.angle()
		var new_bullet:ball
		new_bullet = bullet.instantiate()
		new_bullet.set_collision_layer_value(2,false)
		new_bullet.Master = self
		new_bullet.Master_name = self.name
		new_bullet.Team = Team
		new_bullet.Speed += Speed
		new_bullet.Damage = Damage
		
		new_bullet.global_position = global_position
		new_bullet.global_rotation = new_bullet.Default_Rotation + angle
		new_bullet.direction = dir.normalized()
		
		#var spawner = world.return_spawner()
		new_bullet.name = Game.return_random_name(new_bullet)
		world.add_child(new_bullet,true)
		Audios.play_sfx.rpc("G18单发",{},true,true)
	
func Die() -> void:
	super()
	
	await get_tree().create_timer(1).timeout
	Game.free_node(self)
