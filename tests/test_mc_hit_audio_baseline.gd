extends "res://tests/test_mc16_spider_drowned.gd"
const GAIN=preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
var AUDIO:Script
var BLOCK:Script
func run() -> void:
	AUDIO=load("res://scripts/characters/我的世界/new5/audio.gd")
	BLOCK=load("res://scripts/characters/我的世界/cactus_note/block_audio.gd")
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true);saved_stop=game.now_stop_state
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Ball_Can_Move=true;game.now_stop_state=false
	AudioServer.set_bus_mute(0,true);create_timer(45).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.3).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var context:Node=dummy(center)
	var routes:Dictionary={
		"res://scripts/characters/我的世界/mc_mob_base.gd":"mc_impact_volume",
		"res://scripts/characters/我的世界/溺尸.gd":"mc_outgoing_impact_volume",
		"res://scripts/characters/我的世界/minecart/minecart.gd":"impact_volume",
		"res://scripts/characters/我的世界/new5/guardian.gd":"impact_volume",
		"res://scripts/characters/我的世界/frontier/moss.gd":"impact_volume",
		"res://scripts/characters/我的世界/frontier/warden.gd":"impact_volume",
		"res://scripts/characters/我的世界/frontier/wooden_sword.gd":"impact_volume",
		"res://scripts/characters/我的世界/allay/allay.gd":"hit_volume_db",
		"res://scripts/characters/我的世界/cactus_note/block_audio.gd":"impact_gain",
		"res://scripts/effects/我的世界/女巫药水伤害音效.gd":"impact_volume"}
	for path:String in routes:
		var script:Script=load(path)
		check(script!=null and script.can_instantiate(),"volume route compiles: "+path.get_file())
		if script==null or not script.can_instantiate(): continue
		var unit:Object=script.new()
		var previous:float=-1.0
		for damage:float in [0.0,1.0,10.0,50.0,51.0,100.0,200.0,1000.0]:
			var gain:float=unit.call(routes[path],damage)
			check(gain>=0.0 and gain<=6.0 and gain>previous and is_equal_approx(gain,GAIN.damage_gain(damage)),"native baseline and increasing bounded gain: "+path.get_file()+" damage="+str(damage))
			previous=gain
		if unit is Node: unit.free()
	for event:String in ["entity.player.hurt","entity.player.attack.crit"]:
		for amount:float in [0.0,1.0,50.0,51.0,100.0,200.0,1000.0]:
			var gain:float=GAIN.damage_gain(amount)
			var sound:AudioStreamPlayer2D=AUDIO.play(context,event,center,gain,false,true,true,true)
			check(is_instance_valid(sound) and sound.playing and is_equal_approx(sound.volume_db,gain),"native player does not secretly attenuate or clamp growing hit gain")
			var block_sound:AudioStreamPlayer2D=BLOCK.play(context,event,center,gain,amount)
			check(is_instance_valid(block_sound) and block_sound.playing and is_equal_approx(block_sound.volume_db,gain),"jukebox player honors the same baseline and gain")
		var legacy:AudioStreamPlayer2D=AUDIO.play(context,event,center,-18.0,false,true,true,true)
		check(legacy.volume_db==0.0,"legacy negative hit gain cannot lower native baseline")
		var loud:AudioStreamPlayer2D=AUDIO.play(context,event,center,20.0,false,true,true,true)
		check(loud.volume_db==6.0,"playback enforces bounded hit gain")
	var step_sound:AudioStreamPlayer2D=AUDIO.play(context,"block.moss.step",center,-8.0,false,true,true,true)
	check(step_sound.volume_db==-8.0,"non-hit native sound attenuation remains untouched")
	var action_sound:AudioStreamPlayer2D=BLOCK.play(context,"entity.puffer_fish.blow_out",center,-6.0)
	check(action_sound.volume_db==-6.0,"non-hit block/character action audio remains untouched")
	check(GAIN.damage_gain(0)==0 and is_equal_approx(GAIN.damage_gain(50),3.0) and is_equal_approx(GAIN.damage_gain(100),4.0),"documented original-level baseline and representative gains")
	print("MC_HIT_AUDIO_BASELINE checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
