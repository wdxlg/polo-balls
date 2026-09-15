extends ball

var knife := preload("res://scenes/shooter/knife.tscn")
const KNIFE_TEXTURE:Texture2D = preload("res://Images/shooter/Knife.png")

func _ready() -> void:
	# 角色生成时预热一次刀纹理 CPU Image，避免第一次投刀时 GPU -> CPU 读取造成顿帧。
	ball.prewarm_after_image_texture(KNIFE_TEXTURE)
	super._ready()

func Attack() -> void:
	super()
	var world:World = get_tree().current_scene
	
	var new_knife:ball
	var enemy = Target_Enemy if Target_Enemy else Nearest_Enemy
	if (enemy or has_player_control_aim()) and is_multiplayer_authority():
		Attacking = true
		var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (combat_target_position(enemy) - global_position)
		var angle:float = dir.angle()

		new_knife = world.get_meta("_fresh_knife_supply").take() if world.has_meta("_fresh_knife_supply") else knife.instantiate()
		new_knife.set_collision_layer_value(2,false)
		new_knife.Master = self
		new_knife.Master_name = self.name
		new_knife.Team = Team
		new_knife.Speed += Speed
		new_knife.Damage = Damage
		
		new_knife.global_position = global_position
		new_knife.global_rotation = new_knife.Default_Rotation + angle
		new_knife.direction = dir.normalized()
		
		#var spawner = world.return_spawner()
		new_knife.name = Game.return_random_name(new_knife)
		world.add_child(new_knife,true)
		Audios.play_sfx.rpc("KnifeThrow1",{},true)
		
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
