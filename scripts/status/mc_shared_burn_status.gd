extends "res://scripts/status/战争女神_灼烧.gd"
## Original Blaze burn status and visual are inherited without copying their
## tick or immunity algorithm. Minecraft sources add one native impact sound per
## effective burn tick; Sulfur's own RPC keeps that sound on both battle peers.
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const NATIVE_AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")

func _physics_process(delta:float) -> void:
	var old_health:float = maxf(target.health,0.0) if is_instance_valid(target) else 0.0
	super._physics_process(delta)
	if not is_instance_valid(source) or not is_instance_valid(target) or not source.is_multiplayer_authority(): return
	if not source.Type_Tags.has("我的世界"): return
	var actual:float = maxf(old_health-maxf(target.health,0.0),0.0)
	if actual <= 0.0: return
	var event:StringName = StringName(HIT_GAIN.damage_event(actual))
	var gain:float = HIT_GAIN.damage_gain(actual)
	if source.has_method("_sulfur_impact"):
		if source.multiplayer.has_multiplayer_peer(): source.rpc("_sulfur_impact",event,target.global_position,gain)
		source.call("_sulfur_impact",event,target.global_position,gain)
	else:
		var player:AudioStreamPlayer2D = NATIVE_AUDIO.play(self,String(event),target.global_position,gain,false,true,true,true)
		if is_instance_valid(player): player.set_meta("mc_damage_source",source.get_instance_id())
