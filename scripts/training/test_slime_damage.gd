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
	for stage:int in range(3):
		var slime:Node2D=spawn(["史莱姆","史莱姆_中","史莱姆_小"][stage],Vector2.ZERO,"Team0","characters" if stage==0 else "creatures")
		var target:Node2D=spawn("",Vector2(18,0),"Team1")
		target.health=10000
		target.block=0
		target.Damage_reduction=0
		for landing:bool in [false,true]:
			await clear_sounds(slime)
			var hp:float=target.health
			slime._pulse(landing)
			var expected:float=([44.0,22.0,9.0] if landing else [16.0,9.0,4.0])[stage]
			check(is_equal_approx(hp-target.health,expected),"doubled actual damage stage "+str(stage)+" landing "+str(landing))
			check(hit_sounds()==1,"successful pulse plays MC hit sound")
		await clear_sounds(slime)
		target.global_position=center+Vector2(300,0)
		slime._pulse(true)
		check(hit_sounds()==0,"miss has no hit sound")
		target.global_position=center+Vector2(18,0)
		target.Team="Team0"
		var hp:float=target.health
		slime._pulse(true)
		check(hit_sounds()==0 and target.health==hp,"friendly ignored without sound")
		target.Team="Team1"
		var second:Node2D=spawn("",Vector2(-18,0),"Team1")
		second.health=10000
		slime._pulse(true)
		check(hit_sounds()==1,"multiple victims produce only one impact cue")
		check(second.health<10000 and target.health<hp,"AOE still damages both victims")
		await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
func hit_sounds() -> int:
	var count:int=0
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if node.get_meta("mc_sound_event","")=="entity.player.hurt" and not node.is_queued_for_deletion(): count+=1
	return count
func clear_sounds(slime:Node) -> void:
	for node:Node in get_nodes_in_group("MCNativeSFX"): node.queue_free()
	await process_frame
	slime.AUDIO._last.erase("entity.player.hurt")
