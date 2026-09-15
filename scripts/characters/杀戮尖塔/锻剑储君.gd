extends ball

var status_texture := "heirloom_hammer"
var Sword := preload("res://scenes/creatures/储君_sword.tscn")
var sword_random_range:float = 10

func _ready() -> void:
	super()
	var world:World = get_tree().current_scene
	
	var new_swrod := Sword.instantiate()
	new_swrod.Master = self
	new_swrod.Master_name = self.name
	new_swrod.Team = Team
	Creatures.append(new_swrod)
	
	new_swrod.global_position = global_position
	var border:Dictionary = get_tree().current_scene.return_now_map_border()
	
	new_swrod.global_position = Vector2(
		clampf(global_position.x + randf_range(-sword_random_range,sword_random_range),border.start.x,border.end.x),
		clampf(global_position.y + randf_range(-sword_random_range,sword_random_range),border.start.y,border.end.y)
		)
	#var spawner = world.return_spawner()
	new_swrod.name = Game.return_random_name(new_swrod)
	world.add_child(new_swrod,true)
	
func Attack() -> void:
	super()
	var world:World = get_tree().current_scene
	
	Attacking = true
	
	for b:ball in Creatures:
		if b:
			Audios.play_sfx("Mc锻造",{},true)
			
			#b.set_status_image(status_texture)
			if is_multiplayer_authority():world.set_status_image.rpc(status_texture,b.global_position)
			world.new_buff(b,self,"攻击",Buff.new(1,INF,Buff.Buff_types.Damage,default_properties.Damage,Buff.Algorithms.add),"add")
	
	await get_tree().create_timer(0.8).timeout
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
