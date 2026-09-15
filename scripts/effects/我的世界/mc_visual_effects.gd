extends RefCounted
const PORTAL = preload("res://scripts/effects/我的世界/末影粒子.gd")
const END_ROD = [preload("res://Images/effects/我的世界/通用粒子/glitter_7.png"),preload("res://Images/effects/我的世界/通用粒子/glitter_6.png"),preload("res://Images/effects/我的世界/通用粒子/glitter_5.png"),preload("res://Images/effects/我的世界/通用粒子/glitter_4.png"),preload("res://Images/effects/我的世界/通用粒子/glitter_3.png"),preload("res://Images/effects/我的世界/通用粒子/glitter_2.png"),preload("res://Images/effects/我的世界/通用粒子/glitter_1.png"),preload("res://Images/effects/我的世界/通用粒子/glitter_0.png")]
const SMOKE = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")
static func portal(context:Node2D,point:Vector2,count:int = 2,burst:bool = false) -> void:
	var tree:SceneTree = context.get_tree()
	if tree == null or tree.current_scene == null: return
	for i:int in range(count):
		var active:Array[Node] = tree.get_nodes_in_group("MCEnderParticle")
		if active.size() >= 320:
			if not burst: break
			active[0].remove_from_group("MCEnderParticle")
			active[0].queue_free()
		var particle:Node2D = PORTAL.new()
		tree.current_scene.add_child(particle)
		var motion:Vector2 = Vector2.RIGHT.rotated(randf()*TAU)*randf_range(22,48) if burst else Vector2(randf_range(-7,7),randf_range(-7,3))
		particle.setup(point+Vector2(randf_range(-5,5),randf_range(-9,8)),motion,randf_range(0.55,0.8),randf_range(1.75,2.5))
		particle.set_meta("mc_emitter_id",context.get_instance_id())
		if burst: particle.add_to_group("MCCloneBurst")
static func spark(context:Node2D,point:Vector2,burst:bool = false) -> void:
	var tree:SceneTree = context.get_tree()
	if tree == null or tree.current_scene == null: return
	if tree.get_nodes_in_group("MCShulkerTrail").size() >= 256: return
	var particle:Node2D = PORTAL.new()
	tree.current_scene.add_child(particle)
	particle.frames = END_ROD
	particle.set_meta("mc_emitter_id",context.get_instance_id())
	particle.setup(point,Vector2.RIGHT.rotated(randf()*TAU)*randf_range(4,13) if burst else Vector2.ZERO,0.35,0.7)
	particle.self_modulate = Color(1.0,0.96,0.94,0.9)
	particle.remove_from_group("MCEnderParticle")
	particle.add_to_group("MCShulkerTrail")
static func smoke(context:Node2D,point:Vector2,delay:float = 0.9,size:float = 0.56) -> void:
	var world:Node = context.get_tree().current_scene
	if world == null: return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = SMOKE
	sprite.animation = &"死亡烟雾"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 8
	sprite.scale = Vector2.ONE*size
	sprite.visible = false
	world.add_child(sprite)
	sprite.global_position = point
	sprite.add_to_group("BattleTransient")
	sprite.add_to_group("MCDeathSmoke")
	sprite.animation_finished.connect(sprite.queue_free,CONNECT_ONE_SHOT)
	var tween:Tween = sprite.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(sprite.show)
	tween.tween_callback(sprite.play.bind(&"死亡烟雾"))
static func death_pose(context:Node2D,source:Sprite2D,moving_right:bool) -> void:
	# 仅复制视觉，不保留死亡角色的碰撞/AI。姿势与骷髅一致：染红、90度倒下、原有烟雾。
	var world:Node = context.get_tree().current_scene
	if world == null or source == null: return
	var pose := Sprite2D.new()
	pose.texture = source.texture
	pose.offset = source.offset
	pose.centered = source.centered
	pose.flip_h = context.is_character_visual_flipped_h()
	pose.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pose.self_modulate = source.self_modulate
	world.add_child(pose)
	pose.global_transform = source.global_transform
	pose.z_index = 3
	pose.add_to_group("BattleTransient")
	pose.add_to_group("MCDeathPose")
	# 沿用角色着色器，黑色末影人也能出现死亡红色。
	pose.material = source.material
	pose.flip_h = false
	pose.set_instance_shader_parameter("sprite_flip_h",1.0 if context.is_character_visual_flipped_h() else 0.0)
	pose.set_instance_shader_parameter("default_color",Color(1.0,0.16,0.16))
	pose.set_instance_shader_parameter("defualt_color_mix",0.60)
	var tween:Tween = pose.create_tween()
	tween.tween_property(pose,"rotation",pose.rotation+(-PI*0.5 if moving_right else PI*0.5),0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(pose.queue_free)
	smoke(context,context.global_position)
