extends RefCounted
## All clips are SHA-1 verified Mojang Minecraft Java 26.2 assets; see sources.json.
const EVENTS:Dictionary = {
	&"absorb": [preload("res://audio/characters/我的世界/sulfur_cube/absorb1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/absorb2.ogg")],
	&"eject": [preload("res://audio/characters/我的世界/sulfur_cube/eject1.ogg")],
	&"jump": [preload("res://audio/characters/我的世界/sulfur_cube/jump1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/jump2.ogg")],
	&"squish": [preload("res://audio/characters/我的世界/sulfur_cube/squish1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/squish2.ogg")],
	&"hurt": [preload("res://audio/characters/我的世界/sulfur_cube/hurt1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/hurt2.ogg")],
	&"death": [preload("res://audio/characters/我的世界/sulfur_cube/death.ogg")],
	&"bounce": [preload("res://audio/characters/我的世界/sulfur_cube/bounce.ogg")],
	&"wood_hit": [preload("res://audio/characters/我的世界/sulfur_cube/wood_hit.ogg")],
	&"ice_hit": [preload("res://audio/characters/我的世界/sulfur_cube/ice_hit.ogg")],
	&"magma_hit": [preload("res://audio/characters/我的世界/sulfur_cube/magma_hit.ogg")],
	&"honey_hit": [preload("res://audio/characters/我的世界/sulfur_cube/honey_hit.ogg")],
	&"iron_hit": [preload("res://audio/characters/我的世界/sulfur_cube/iron_hit.ogg")],
	&"tnt_hit": [preload("res://audio/characters/我的世界/sulfur_cube/tnt_hit.ogg")],
	&"fuse": [preload("res://audio/characters/我的世界/sulfur_cube/fuse.ogg")],
	&"explosion": [preload("res://audio/characters/我的世界/sulfur_cube/explosion.ogg")],
	&"entity.player.hurt": [preload("res://audio/characters/我的世界/sulfur_cube/impact_hurt1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_hurt2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_hurt3.ogg")],
	&"entity.player.attack.crit": [preload("res://audio/characters/我的世界/sulfur_cube/impact_crit1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_crit2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_crit3.ogg")],
}

static func play(context:Node2D,event:StringName,point:Vector2,volume_db:float = -2.0) -> AudioStreamPlayer2D:
	if not is_instance_valid(context) or not context.is_inside_tree() or not EVENTS.has(event): return null
	var tree:SceneTree = context.get_tree()
	if tree.current_scene == null or tree.paused or Game.now_stop_state: return null
	var players:Array[Node] = tree.get_nodes_in_group("MCNativeSFX")
	if players.size() >= 24: return null
	var player := AudioStreamPlayer2D.new()
	var options:Array = EVENTS[event]
	player.stream = options[randi() % options.size()] as AudioStream
	player.volume_db = clampf(volume_db,-18.0,6.0 if event in [&"entity.player.hurt",&"entity.player.attack.crit"] else 2.0)
	player.max_distance = 1700.0
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	tree.current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("MCNativeSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sulfur_event",event)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player
