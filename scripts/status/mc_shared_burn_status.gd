extends "res://scripts/status/战争女神_灼烧.gd"
## Original Blaze burn status and visual are inherited without copying their
## tick or immunity algorithm. Minecraft sources add one native impact sound per
## effective burn tick; Sulfur's own RPC keeps that sound on both battle peers.
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const NATIVE_AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const SOUL_BURN_FRAMES:SpriteFrames = preload("res://particles/mc_burning_soul_fire.tres")
## 与 BURN_TINT 同等强度的灵魂火青色（按 soul_fire_1 平均色换算）。
const SOUL_BURN_TINT := Color(0.52,0.98,1.0,1.0)

## 这次燃烧来自灵魂火：原版 soul_fire_1 燃烧动画与青色染色。任何刷新先回到普通火，由施加方重新声明。
var soul:bool = false

func set_soul(value:bool) -> void:
	soul = value
	_apply_burn_tint()
	_sync_minecraft_burn_visual()

func refresh(new_source:ball,duration:float,new_tick_damage:float) -> void:
	soul = false
	super.refresh(new_source,duration,new_tick_damage)

func _burn_tint() -> Color:
	return SOUL_BURN_TINT if soul else BURN_TINT

func _minecraft_burn_frames() -> SpriteFrames:
	return SOUL_BURN_FRAMES if soul else MINECRAFT_BURN_FRAMES

func _physics_process(delta:float) -> void:
	var old_health:float = maxf(target.health,0.0) if is_instance_valid(target) else 0.0
	super._physics_process(delta)
	if not is_instance_valid(source) or not is_instance_valid(target) or not source.is_multiplayer_authority(): return
	if not source.Type_Tags.has("我的世界"): return
	if preload("res://scripts/effects/我的世界/mc_hit_feedback.gd").manages(source): return # The receive path already emitted each tick.
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
