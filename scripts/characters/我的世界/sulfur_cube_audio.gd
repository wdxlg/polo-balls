extends RefCounted
## Original Java 26.2 files; see AUDIO_SOURCE_20260927.json (92 verified, unmodified Oggs).
const NATIVE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const HIT = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const EVENTS:Dictionary = {
	&"absorb": [preload("res://audio/characters/我的世界/sulfur_cube/absorb1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/absorb2.ogg")],
	&"eject": [preload("res://audio/characters/我的世界/sulfur_cube/eject1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__eject2.ogg")],
	&"jump": [preload("res://audio/characters/我的世界/sulfur_cube/jump1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/jump2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__jump3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__jump4.ogg")],
	&"squish": [preload("res://audio/characters/我的世界/sulfur_cube/squish1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/squish2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__squish3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__squish4.ogg")],
	&"hurt": [preload("res://audio/characters/我的世界/sulfur_cube/hurt1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/hurt2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__hit3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__hit4.ogg")],
	&"death": [preload("res://audio/characters/我的世界/sulfur_cube/death.ogg")],
	&"bounce": [preload("res://audio/characters/我的世界/sulfur_cube/bounce.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__bounce2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__bounce3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__bounce4.ogg")],
	&"ice_hit": [preload("res://audio/characters/我的世界/sulfur_cube/ice_hit.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__fastsliding_hit2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__fastsliding_hit3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__fastsliding_hit4.ogg")],
	&"magma_hit": [preload("res://audio/characters/我的世界/sulfur_cube/magma_hit.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__hot_hit2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__hot_hit3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__hot_hit4.ogg")],
	&"honey_grab": [preload("res://audio/characters/我的世界/sulfur_cube/honey_hit.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__sticky_hit2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__sticky_hit3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__sticky_hit4.ogg")],
	&"honey_release": [preload("res://audio/characters/我的世界/sulfur_cube/revision/block__honeyblock__break1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/block__honeyblock__break2.ogg")],
	&"iron_hit": [preload("res://audio/characters/我的世界/sulfur_cube/iron_hit.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__slowflat_hit2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__slowflat_hit3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__slowflat_hit4.ogg")],
	&"tnt_hit": [preload("res://audio/characters/我的世界/sulfur_cube/tnt_hit.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__explosive_hit2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__explosive_hit3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__explosive_hit4.ogg")],
	&"ice_form": [preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__fastsliding_push1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__fastsliding_push2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__fastsliding_push3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__fastsliding_push4.ogg")],
	&"magma_form": [preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__hot_push1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__hot_push2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__hot_push3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__hot_push4.ogg")],
	&"honey_form": [preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__sticky_push1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__sticky_push2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__sticky_push3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__sticky_push4.ogg")],
	&"iron_form": [preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__slowflat_push1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__slowflat_push2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__slowflat_push3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__slowflat_push4.ogg")],
	&"tnt_form": [preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__explosive_push1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__explosive_push2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__explosive_push3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/mob__sulfur_cube__ball__explosive_push4.ogg")],
	&"amethyst_grow": [preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst_cluster__place1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst_cluster__place2.ogg")],
	&"amethyst_hit": [preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst__step1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst__step2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst__step3.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst__step4.ogg")],
	&"amethyst_launch": [preload("res://audio/characters/我的世界/new6/amethyst_break1.ogg"),preload("res://audio/characters/我的世界/new6/amethyst_break2.ogg"),preload("res://audio/characters/我的世界/new6/amethyst_break3.ogg"),preload("res://audio/characters/我的世界/new6/amethyst_break4.ogg")],
	&"amethyst_break": [preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst_cluster__break1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/block__amethyst_cluster__break2.ogg")],
	&"ice_crack": [preload("res://audio/characters/我的世界/sulfur_cube/revision/step__stone1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/step__stone2.ogg")],
	&"ice_break": [preload("res://audio/characters/女巫/药水碎裂.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/random__glass2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/revision/random__glass3.ogg")],
	&"magma_sizzle": [preload("res://audio/characters/我的世界/sulfur_cube/revision/liquid__lavapop.ogg")],
	&"fuse": [preload("res://audio/characters/我的世界/sulfur_cube/fuse.ogg")],
	&"explosion": [preload("res://audio/characters/我的世界/sulfur_cube/explosion.ogg"),preload("res://audio/characters/我的世界/new5/e55daa373e577f611565d57ec53cd28dcf472f99.ogg"),preload("res://audio/characters/我的世界/new5/3a92d0fd263265719532041f6f2ea44c7ba2f2e2.ogg"),preload("res://audio/characters/我的世界/new5/09835e0c3138faf6047506a2b6f1da087c082d2e.ogg")],
	&"entity.player.hurt": [preload("res://audio/characters/我的世界/sulfur_cube/impact_hurt1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_hurt2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_hurt3.ogg")],
	&"entity.player.attack.crit": [preload("res://audio/characters/我的世界/sulfur_cube/impact_crit1.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_crit2.ogg"),preload("res://audio/characters/我的世界/sulfur_cube/impact_crit3.ogg")],
}
const SETTINGS:Dictionary = {
	&"absorb": {"volume_db": -2.0, "interval": 0.12, "pitches": [1.0, 1.0], "volumes": [1.0, 1.0], "weights": [1, 2]},
	&"eject": {"volume_db": -2.0, "interval": 0.12, "pitches": [1.0, 1.0], "volumes": [1.0, 1.0], "weights": [1, 1]},
	&"jump": {"volume_db": -2.0, "interval": 0, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"squish": {"volume_db": -2.0, "interval": 0, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"hurt": {"volume_db": -5.0, "interval": 0.25, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"death": {"volume_db": -5.0, "interval": 0, "pitches": [1.0], "volumes": [1.0], "weights": [1]},
	&"bounce": {"volume_db": -3.0, "interval": 0.15, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"ice_hit": {"volume_db": -2.0, "interval": 0.14, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"magma_hit": {"volume_db": -2.0, "interval": 0.2, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"honey_grab": {"volume_db": -2.0, "interval": 0.1, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"honey_release": {"volume_db": -5.0, "interval": 0.15, "pitches": [1.0, 1.0], "volumes": [1.0, 1.0], "weights": [1, 1]},
	&"iron_hit": {"volume_db": -2.0, "interval": 0.15, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"tnt_hit": {"volume_db": -3.0, "interval": 0.25, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"ice_form": {"volume_db": -3.0, "interval": 0.18, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"magma_form": {"volume_db": -3.0, "interval": 0.18, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"honey_form": {"volume_db": -3.0, "interval": 0.18, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"iron_form": {"volume_db": -3.0, "interval": 0.18, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"tnt_form": {"volume_db": -3.0, "interval": 0.18, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"amethyst_grow": {"volume_db": -3.0, "interval": 0.2, "pitches": [1.0, 1.0], "volumes": [0.9, 0.9], "weights": [1, 1]},
	&"amethyst_hit": {"volume_db": -3.0, "interval": 0.12, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"amethyst_launch": {"volume_db": -2.0, "interval": 0.18, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"amethyst_break": {"volume_db": -3.0, "interval": 0.12, "pitches": [0.8, 0.8], "volumes": [0.8, 0.8], "weights": [1, 1]},
	&"ice_crack": {"volume_db": -7.0, "interval": 0.22, "pitches": [1.0, 1.0], "volumes": [1.0, 1.0], "weights": [1, 1]},
	&"ice_break": {"volume_db": -4.0, "interval": 0.18, "pitches": [1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0], "weights": [1, 1, 1]},
	&"magma_sizzle": {"volume_db": -4.0, "interval": 0.45, "pitches": [1.0], "volumes": [1.0], "weights": [1]},
	&"fuse": {"volume_db": -2.0, "interval": 0.25, "pitches": [1.0], "volumes": [1.0], "weights": [1]},
	&"explosion": {"volume_db": -2.0, "interval": 0.1, "pitches": [1.0, 1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0, 1.0], "weights": [1, 1, 1, 1]},
	&"entity.player.hurt": {"volume_db": 0.0, "interval": 0, "pitches": [1.0, 1.0, 1.0], "volumes": [1.0, 1.0, 1.0], "weights": [1, 1, 1]},
	&"entity.player.attack.crit": {"volume_db": 0.0, "interval": 0, "pitches": [1.0, 1.0, 1.0], "volumes": [0.7, 0.7, 0.7], "weights": [1, 1, 1]},
}
static var _voice_rng := RandomNumberGenerator.new()
static var _seeded:bool = false

static func choose_variant(event:StringName) -> int:
	if not EVENTS.has(event): return -1
	if not _seeded:
		_voice_rng.randomize()
		_seeded = true
	return _voice_rng.rand_weighted(PackedFloat32Array(SETTINGS[event].weights))

static func default_gain(event:StringName) -> float:
	return float(SETTINGS.get(event,{}).get("volume_db",-2.0))

static func interval_ms(event:StringName) -> int:
	return ceili(float(SETTINGS.get(event,{}).get("interval",0.1))*1000.0)

static func play(context:Node2D,event:StringName,point:Vector2,volume_db:float = INF,variant:int = -1,metadata:Dictionary = {}) -> Dictionary:
	# Explicit user exception: no ambient/breathing/idle events are registered.
	if not EVENTS.has(event): return {}
	if variant < 0: variant = choose_variant(event)
	if variant < 0 or variant >= EVENTS[event].size(): return {}
	var config:Dictionary = SETTINGS[event]
	var hit:bool = HIT.is_hit_event(String(event))
	var gain:float = default_gain(event) if volume_db == INF else volume_db
	# MCP damage feedback deliberately does NOT inherit vanilla crit's 0.7
	# event attenuation: its project baseline is 0 dB / 1x, then live-damage gain.
	if not hit: gain += linear_to_db(maxf(float(config.volumes[variant]),0.001))
	gain = clampf(gain,0.0,6.0) if hit else clampf(gain,-24.0,2.0)
	var tags:Dictionary = metadata.duplicate()
	tags.merge({"mc_sulfur_event":event,"mc_sound_event":event,"mc_sulfur_variant":variant,"mc_sulfur_source":context.get_instance_id()},true)
	var options:Dictionary = {"volume_db":gain,"pitch":config.pitches[variant],
		"priority":hit or event == &"death","keep_after_source":hit or event in [&"death",&"ice_break",&"amethyst_break"],"metadata":tags}
	var ticket:Dictionary = NATIVE.queue_stream(context,EVENTS[event][variant],point,options)
	if not ticket.is_empty():
		ticket["variant"] = variant
		ticket["pitch"] = options.pitch
	return ticket

static func moving_channel_busy(ticket:Dictionary) -> bool:
	return NATIVE.channel_busy(ticket)
