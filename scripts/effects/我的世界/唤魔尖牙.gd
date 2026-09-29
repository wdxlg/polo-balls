extends Node2D
const NATIVE_FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/native_frames/fang.tres")
const DRAW_SCALE:float = 19.0/98.0
const GROUND_Y:float = 199.0
const AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const RUNTIME = preload("res://scripts/effects/我的世界/mc_explosion.gd")
var _emerged:bool = false
var _caster:WeakRef
var _delay:float
var _age:float = 0.0
var _damage:float
var _hit:bool = false
var _hits:Dictionary
var _push_back:bool = false
var _push_distance:float = 18.0
var _push_speed:float = 90.0
func setup(caster:ball,delay:float,damage:float,hits:Dictionary,push_back:bool = false,push_distance:float = 18.0,push_speed:float = 90.0) -> void:
	_caster = weakref(caster)
	_delay = delay
	_damage = damage
	_hits = hits
	_push_back = push_back
	_push_distance = push_distance
	_push_speed = push_speed
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1
	add_to_group("BattleTransient")
	add_to_group("MCEvokerFang")
func _physics_process(delta:float) -> void:
	var caster:Variant = _caster.get_ref() if _caster != null else null
	if not is_instance_valid(caster) or caster.health <= 0:
		queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	_age += delta
	if not _emerged and native_animation_progress() >= 0.0:
		_emerged = true
		_emit_emergence()
	if _age >= _delay and not _hit:
		_hit = true
		_emit_bite()
		if not bool(_hits.get("_native_sound",false)):
			_hits["_native_sound"] = true
			AUDIO.play(caster,"entity.evoker_fangs.attack",global_position,-5.0)
			caster.mc_play("cast_spell",-7.0)
		for target:Node in get_tree().get_nodes_in_group("Ball"):
			if target is ball and caster.mc_enemy(target) and not _hits.has(target.get_instance_id()):
				if global_position.distance_to(ball.body_point(target,global_position)) <= 5.5 + target.get_crowd_separation_radius_world() and caster.mc_line_clear(global_position,ball.body_point(target,global_position)):
					_hits[target.get_instance_id()] = true
					var applied:bool = caster.mc_damage_with_impact(target,_damage,global_position)
					if applied and _push_back and target.health > 0:
						target.apply_knockback(caster.global_position.direction_to(ball.body_point(target,caster.global_position)),_push_distance,_push_speed,0.0,0.0,{"source":caster,"stop_on_character":true})
	if _age > _delay + 0.34: queue_free()
	queue_redraw()
func native_animation_progress() -> float:
	# The original hit time is unchanged: map the native fully-closed jaw pose
	# (progress 0.5) exactly to _delay, with a short pre-hit emerging/open stage.
	var lead:float = minf(maxf(_delay,0.0),0.14)
	var start:float = _delay-lead
	if _age < start: return -1.0
	if _age < _delay: return 0.5*clampf((_age-start)/maxf(lead,0.00001),0.0,1.0)
	return 0.5+0.5*clampf((_age-_delay)/0.34,0.0,1.0)

func native_frame_index() -> int:
	var progress:float = native_animation_progress()
	if progress < 0.0: return -1
	return clampi(int(round(progress*float(NATIVE_FRAMES.get_frame_count(&"bite")-1))),0,NATIVE_FRAMES.get_frame_count(&"bite")-1)

func _draw() -> void:
	var index:int = native_frame_index()
	if index < 0: return
	var texture:Texture2D = NATIVE_FRAMES.get_frame_texture(&"bite",index)
	# A fixed canvas/ground anchor. Actual jaw rotations and terrain clipping
	# were baked from Mojang's bones; no more stretching a static fang picture.
	draw_texture_rect(texture,Rect2(Vector2(-80.0*DRAW_SCALE,5.0-GROUND_Y*DRAW_SCALE),Vector2(160,224)*DRAW_SCALE),false)

func _emit_emergence() -> void:
	# One cast can raise dozens of jaws, so the shared hit ledger doubles as a local
	# burst budget: only a few fangs kick up debris, while every jaw still closes.
	var budget:int = int(_hits.get("_fang_debris_budget",4))
	if budget <= 0: return
	_hits["_fang_debris_budget"] = budget - 1
	var fx:Node2D = ABILITIES.ground_impact(RUNTIME.runtime_container(self),global_position+Vector2(0,5),12.0,{
		"name":"MCFangGround", "show_impact_ring":false, "show_impact_streaks":false,
		"block_source_min_count":6, "block_source_max_count":6,
		"blocks_per_source_min":2, "blocks_per_source_max":3,
		"block_source_inner_radius_scale":0.70, "block_source_radius_max_scale":0.95,
		"block_exclusion_radius":7.0, "block_source_scatter":0.5,
		"block_min_size":1.0, "block_max_size":2.0,
		"block_min_height":2.0, "block_max_height":4.0,
		"block_min_flight_time":0.25, "block_max_flight_time":0.36,
		"block_min_ground_hold":0.06, "block_max_ground_hold":0.12,
		"block_travel_min":3.0, "block_travel_max":6.0,
		"block_landing_jitter":0.0, "block_delay_max":0.015})
	fx.add_to_group("MCFangGround")
	fx.set_meta("fang_id",get_instance_id())

func _emit_bite() -> void:
	# Vanilla EvokerFangs fires twelve CRIT sparks on jaw closure; one cast raises
	# dozens of jaws here, so keep just a few per bite. They still spread across the
	# jaw box instead of stacking, and fire whether or not the bite found a victim.
	ABILITIES.critical_burst(self,global_position+Vector2(0,-10),get_instance_id(),{
		"count":4, "radius":10.0, "neutral_tone":true, "tone_min":0.86, "tone_max":1.0,
		"side_min":12.0, "side_max":26.0, "up_min":24.0, "up_max":42.0,
		"gravity_min":100.0, "gravity_max":140.0})
