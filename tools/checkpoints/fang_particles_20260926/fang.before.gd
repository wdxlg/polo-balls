extends Node2D
const NATIVE_FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/native_frames/fang.tres")
const DRAW_SCALE:float = 19.0/98.0
const GROUND_Y:float = 199.0
const AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
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
	if _age >= _delay and not _hit:
		_hit = true
		if not bool(_hits.get("_native_sound",false)):
			_hits["_native_sound"] = true
			AUDIO.play(caster,"entity.evoker_fangs.attack",global_position,-5.0)
			caster.mc_play("cast_spell",-7.0)
		for target:Node in get_tree().get_nodes_in_group("Ball"):
			if target is ball and caster.mc_enemy(target) and not _hits.has(target.get_instance_id()):
				if global_position.distance_to(target.global_position) <= 5.5 + target.get_crowd_separation_radius_world() and caster.mc_line_clear(global_position,target.global_position):
					_hits[target.get_instance_id()] = true
					var applied:bool = caster.mc_damage_with_impact(target,_damage,global_position)
					if applied and _push_back and target.health > 0:
						target.apply_knockback(caster.global_position.direction_to(target.global_position),_push_distance,_push_speed,0.0,0.0,{"source":caster,"stop_on_character":true})
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
