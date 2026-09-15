extends ball

var knife := preload("res://scenes/shooter/knife.tscn")
const RUNTIME_KNIFE_SCENE = preload("res://classes/runtime_knife_scene.gd")
const KNIFE_TEXTURE:Texture2D = preload("res://Images/shooter/Knife.png")

func _ready() -> void:
	# 角色生成时预热一次刀纹理 CPU Image，避免第一次投刀时 GPU -> CPU 读取造成顿帧。
	ball.prewarm_after_image_texture(KNIFE_TEXTURE)
	Audios.prewarm_sfx_playbacks("KnifeThrow1")
	if get_tree().current_scene is World:
		RUNTIME_KNIFE_SCENE.prepare(get_tree().current_scene,knife)
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

		new_knife = RUNTIME_KNIFE_SCENE.instantiate(world,knife)
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
