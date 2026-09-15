extends ball

#引用
func Die() -> void:
	image.set_instance_shader_parameter("defualt_color_mix",0)
	Audios.play_sfx("explosion1")
	
	await get_tree().create_timer(0.1).timeout
	Game.free_node(self)
