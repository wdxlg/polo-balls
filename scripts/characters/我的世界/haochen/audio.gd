extends RefCounted
## User-provided start phrase plus original Minecraft 1.21.11 clips (SOURCE.json).
## Task 8 (user choices 2026-09-28): charge_soul = particle.soul_escape while energy is
## gained; copy_complete = entity.illusioner.mirror_move (replaces enderman.teleport).
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const EVENTS:Dictionary = {
	&"charge_start":[preload("res://audio/characters/我的世界/haochen/charge_start.wav")],
	&"charge_soul":[preload("res://audio/characters/我的世界/haochen/particle.soul_escape_1.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_2.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_3.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_4.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_5.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_6.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_7.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_8.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_9.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_10.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_11.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_12.ogg"),preload("res://audio/characters/我的世界/haochen/particle.soul_escape_13.ogg")],
	&"copy_start":[preload("res://audio/characters/唤魔者/evoker.prepare_summon_1.ogg")],
	&"copy_complete":[preload("res://audio/characters/我的世界/haochen/illusioner.mirror_move_1.ogg"),preload("res://audio/characters/我的世界/haochen/illusioner.mirror_move_2.ogg")],
	&"step":[preload("res://audio/characters/我的世界/sulfur_cube/revision/step__stone1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/step__stone2.ogg")],
	&"ambient":[preload("res://audio/characters/唤魔者/evoker.ambient_1.ogg"),preload("res://audio/characters/唤魔者/evoker.ambient_2.ogg"),preload("res://audio/characters/唤魔者/evoker.ambient_3.ogg"),preload("res://audio/characters/唤魔者/evoker.ambient_4.ogg")],
	&"hurt":[preload("res://audio/characters/唤魔者/evoker.hurt_1.ogg"),preload("res://audio/characters/唤魔者/evoker.hurt_2.ogg")],
	&"death":[preload("res://audio/characters/唤魔者/evoker.death_1.ogg"),preload("res://audio/characters/唤魔者/evoker.death_2.ogg")]
}
static var _rng := RandomNumberGenerator.new()
static var _seeded:bool = false
static func variant(event:StringName) -> int:
	if not EVENTS.has(event): return -1
	if not _seeded:
		_rng.randomize()
		_seeded = true
	return _rng.randi_range(0,EVENTS[event].size()-1)
static func gain(event:StringName) -> float:
	match event:
		&"charge_start",&"copy_start",&"copy_complete": return 0.0
		&"charge_soul": return -3.0
		&"ambient": return -8.0
		&"step": return -5.0
	return -4.0
static func play(context:Node2D,event:StringName,point:Vector2,index:int = -1,pitch:float = 1.0) -> Dictionary:
	if not EVENTS.has(event) or not is_instance_valid(context) or not context.is_inside_tree(): return {}
	if index<0: index = variant(event)
	if index<0 or index>=EVENTS[event].size(): return {}
	return NATIVE.queue_stream(context,EVENTS[event][index],point,{"volume_db":gain(event),"pitch":pitch,"audio_parent":context.get_parent(),
		"keep_after_source":event in [&"death",&"copy_start",&"copy_complete"],"priority":event in [&"death",&"charge_start",&"copy_start",&"copy_complete"],
		"groups":["MCHaochenAudio"],"metadata":{"mc_sound_event":String(event),"haochen_event":event,"haochen_source":context.get_instance_id(),"haochen_variant":index}})
static func busy(ticket:Dictionary) -> bool: return NATIVE.channel_busy(ticket)
static func cancel(ticket:Dictionary) -> void:
	if ticket.is_empty(): return
	ticket["cancel_requested"] = true
	var reference:WeakRef = ticket.get("player") as WeakRef
	var player:Variant = reference.get_ref() if reference != null else null
	if is_instance_valid(player):
		player.stop()
		player.queue_free()
