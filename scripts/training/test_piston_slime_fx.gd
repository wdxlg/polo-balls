extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	var piston:Node2D=spawn("粘性活塞",Vector2.ZERO,"Team0")
	piston.direction=Vector2.RIGHT
	piston.facing=Vector2.RIGHT
	var target:Node2D=spawn("",Vector2(25,0),"Team1")
	target.health=10000
	target.block=0
	target.Damage_reduction=0
	var hp:float=target.health
	piston.step_mob(0.18)
	check(target.has_meta("mc_sticky_hold"),"piston captures victim")
	check(target.health<hp,"sticky attack still damages victim")
	var hurt_count:int=0
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if sound.get_meta("mc_sound_event","")=="entity.player.hurt": hurt_count+=1
	check(hurt_count==1,"successful piston hit plays native MC hurt sound")
	var effects:Array[Node]=get_nodes_in_group("MCPistonSlimeFX")
	check(effects.size()==1,"one slime burst on successful sticky hit")
	if effects.size()==1:
		var fx:Node2D=effects[0]
		check(fx.particles.size()==10,"ten native slime texture chips")
		for particle:Dictionary in fx.particles:
			check(particle.velocity.dot(piston.facing)>0,"every chip shoots forwards")
			check(particle.sprite.texture.atlas==fx.TEX,"uses original slimeball texture")
		var first:Sprite2D=fx.particles[0].sprite
		var before:Vector2=first.position
		fx.update_visual(0.1)
		check((first.position-before).dot(piston.facing)>0,"slime travels along piston facing")
		check(first.modulate.a>0 and first.modulate.a<1,"slime progressively fades")
		var age:float=fx.age
		game.now_stop_state=true
		fx._process(0.1)
		check(fx.age==age,"paused combat freezes slime FX")
		game.now_stop_state=false
		piston.step_mob(0.001)
		check(get_nodes_in_group("MCPistonSlimeFX").size()==1,"same stroke does not spam particles")
		fx.update_visual(0.5)
		check(fx.is_queued_for_deletion(),"particles cleaned up after fading")
	for heading:Vector2 in [Vector2.UP,Vector2.LEFT,Vector2.DOWN]:
		var fx:Node2D=piston.SLIME_FX.spawn(piston,piston.global_position,heading,42)
		for particle:Dictionary in fx.particles: check(particle.velocity.dot(heading)>0,"spray supports rotated piston direction")
		fx.queue_free()
	var cleanup_fx:Node2D=piston.SLIME_FX.spawn(piston,piston.global_position,Vector2.RIGHT,43)
	piston.health=0
	game.now_stop_state=true
	cleanup_fx._process(0.01)
	check(cleanup_fx.is_queued_for_deletion() and not cleanup_fx.visible,"owner death cleans FX even when combat stops")
	game.now_stop_state=false
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
