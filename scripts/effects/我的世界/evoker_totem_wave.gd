extends Node2D
const ARC = preload("res://scripts/effects/我的世界/pixel_arc.gd")
const RING_SWEEP = preload("res://classes/expanding_ring_sweep.gd")
const TOTEM = preload("res://scripts/effects/我的世界/mc_totem_effect.gd")
const HALF_WIDTH:float = 3.5
var max_radius:float = 160.0
var duration:float = 0.6
var age:float = 0.0
var radius:float = 0.0
var previous_radius:float = 0.0
var hit_ids:Dictionary = {}
var _source:WeakRef

func setup(caster:ball,point:Vector2,reach:float,seconds:float) -> void:
	_source = weakref(caster)
	top_level = true
	global_position = point
	max_radius = maxf(reach,1.0)
	duration = maxf(seconds,0.05)
	z_as_relative = false
	z_index = -1
	add_to_group("BattleTransient")
	add_to_group("MCEvokerTotemWave")
	queue_redraw()

func source_unit() -> ball:
	return _source.get_ref() as ball if _source!=null else null

func can_deal_damage() -> bool:
	var caster:ball = source_unit()
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() and caster.get_world_2d()==get_world_2d() and caster.is_multiplayer_authority() and caster.health>0 and caster.is_combat_runtime_active() and not caster.is_damage_output_disabled()

func _physics_process(delta:float) -> void:
	advance(delta)

func advance(delta:float) -> void:
	if delta<=0.0 or get_tree().paused or Game.now_stop_state or is_queued_for_deletion(): return
	var caster:ball = source_unit()
	if is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_combat_runtime_active(): return
	previous_radius = radius
	age = minf(age+delta,duration)
	radius = max_radius*age/duration
	if can_deal_damage():
		for contact:Dictionary in RING_SWEEP.contacts(caster,global_position,previous_radius,radius,HALF_WIDTH,hit_ids):
			if not can_deal_damage(): break
			var target:ball = contact.target
			if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
			hit_ids[target.get_instance_id()] = true
			var damage:float = caster.attack_damage(float(caster.get("totem_wave_damage_ratio")))
			var accepted:bool = target.receive_classified_spatial_damage(damage,{"shape":"circle","point":contact.point,"origin":global_position,"radius":HALF_WIDTH,"source":caster,"focus_position":contact.point,"carrier":"area"},&"ordinary",false,false)
			if accepted and is_instance_valid(target) and target.health>0 and is_instance_valid(caster):
				var away:Vector2 = global_position.direction_to(target.global_position)
				if away.is_zero_approx(): away = Vector2.RIGHT
				target.apply_knockback(away,float(caster.get("totem_wave_push_distance")),float(caster.get("totem_wave_push_speed")),0.15,0.0,{"source":caster})
	queue_redraw()
	if age>=duration: queue_free()

func opacity() -> float:
	return 1.0-clampf(age/duration,0.0,1.0)

func threats(receiver:ball=null) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	if not can_deal_damage() or age>=duration or is_queued_for_deletion(): return result
	var caster:ball = source_unit()
	if is_instance_valid(receiver):
		if receiver.get_world_2d()!=get_world_2d() or hit_ids.has(receiver.get_instance_id()) or not RING_SWEEP.SWEEP.TOOLS.is_enemy(caster,receiver): return result
		if not RING_SWEEP.SWEEP._clear(caster.get_world_2d().direct_space_state,caster,global_position,receiver.global_position): return result
	var damage:float = caster.attack_damage(float(caster.get("totem_wave_damage_ratio")))
	if damage<=0.0: return result
	for band:Dictionary in RING_SWEEP.segments(global_position,previous_radius,radius,HALF_WIDTH):
		result.append({"shape":"segment","start":band.a,"end":band.b,"radius":band.r,"damage":damage,"source":caster,"kind":"evoker_totem_wave","danger_in":0.0,"danger_duration":0.03})
	return result

func _draw() -> void:
	ARC.draw_ring(self,Vector2.ZERO,radius,Color.WHITE,opacity(),PackedColorArray([TOTEM.PARTICLE_COLORS[1],TOTEM.PARTICLE_COLORS[2],TOTEM.PARTICLE_COLORS[3]]))
