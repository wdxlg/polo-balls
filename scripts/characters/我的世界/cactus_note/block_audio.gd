extends RefCounted
const NORMAL = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
const DEFLATE:Array[AudioStream] = [preload("res://audio/characters/我的世界/cactus_note/blow_out_0.ogg"),preload("res://audio/characters/我的世界/cactus_note/blow_out_1.ogg")]
const STING:Array[AudioStream] = [preload("res://audio/characters/我的世界/cactus_note/sting_0.ogg"),preload("res://audio/characters/我的世界/cactus_note/sting_1.ogg")]
const CRIT:Array[AudioStream] = [preload("res://audio/characters/我的世界/cactus_note/crit_0.ogg"),preload("res://audio/characters/我的世界/cactus_note/crit_1.ogg"),preload("res://audio/characters/我的世界/cactus_note/crit_2.ogg")]
const DISPENSE:Array[AudioStream] = [preload("res://audio/characters/我的世界/cactus_note/dispense.ogg")]
class PausableSound extends AudioStreamPlayer2D:
	func _process(_delta:float) -> void:
		stream_paused = Game.now_stop_state or get_tree().paused
static func impact_gain(actual_damage:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual_damage)
static func play(context:Node,event:String,point:Vector2,gain:float,actual_damage:float = -1) -> AudioStreamPlayer2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree:SceneTree = context.get_tree()
	if tree.current_scene == null: return null
	var streams:Array = NORMAL.DAMAGE_SFX
	if event == "entity.puffer_fish.blow_out": streams = DEFLATE
	elif event == "entity.puffer_fish.sting": streams = STING
	elif event == "entity.player.attack.crit": streams = CRIT
	elif event == "block.dispenser.dispense": streams = DISPENSE
	var active:Array[Node] = tree.get_nodes_in_group("MCBlockActionSFX")
	if active.size()>=32:
		active[0].stop()
		active[0].remove_from_group("MCBlockActionSFX")
		active[0].queue_free()
	var player := PausableSound.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = streams.pick_random()
	var hit_event:bool=preload("res://scripts/effects/我的世界/hit_audio_gain.gd").is_hit_event(event)
	player.volume_db = clampf(gain,0.0,6.0) if hit_event else clampf(gain,-16.0,4.0)
	player.max_distance = 1300
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
	tree.current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("MCBlockActionSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sound_event",event)
	player.set_meta("actual_damage",actual_damage)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.stream_paused = Game.now_stop_state or tree.paused
	player.play()
	return player
