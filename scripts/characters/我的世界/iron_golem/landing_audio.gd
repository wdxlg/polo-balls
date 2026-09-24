extends RefCounted
# Native generic fall sounds (damage/fallsmall and damage/fallbig), not mace impacts.
# Keep existing height tiers/RPC variant interface; medium and heavy both use big_fall.
const PLAYER:Script = preload("res://scripts/characters/我的世界/iron_golem/native_audio_player.gd")
const POOLS:Array = [
	[preload("res://audio/characters/我的世界/iron_golem/09236e1a725cec0229b8c564f5b3e4fe05cd7a5f.ogg")],
	[preload("res://audio/characters/我的世界/iron_golem/1d183c36f596e85c4fb564ff2667332211e49659.ogg")],
	[preload("res://audio/characters/我的世界/iron_golem/1d183c36f596e85c4fb564ff2667332211e49659.ogg")]]
static func tier(height:float) -> int: return 2 if height>=170.0 else 1 if height>=100.0 else 0
static func variant(height:float) -> int: return randi_range(0,POOLS[tier(height)].size()-1)
static func play(context:Node,point:Vector2,height:float,index:int = -1) -> AudioStreamPlayer2D:
	if not is_instance_valid(context) or context.get_tree().current_scene==null: return null
	var level:int = tier(height)
	var pool:Array = POOLS[level]
	var choice:int = index if index>=0 and index<pool.size() else variant(height)
	var player:AudioStreamPlayer2D = PLAYER.new()
	player.stream = pool[choice]
	player.volume_db = clampf(height/121.0*3.0,0.0,6.0)
	player.max_distance = 1700.0
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
	context.get_tree().current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("BattleTransient")
	player.add_to_group("GolemLandingAudio")
	player.set_meta("mc_sound_event","golem.landing."+["light","medium","heavy"][level])
	player.set_meta("mc_landing_height",height)
	player.set_meta("mc_native_event","entity.generic.small_fall" if level==0 else "entity.generic.big_fall")
	player.set_meta("mc_pair_variant",choice)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player
