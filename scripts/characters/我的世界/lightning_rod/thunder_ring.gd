extends Node2D
## 避雷针能量充满时释放的扩散雷圈：几道电环从释放点先后向外扩散。
## 环带扫过敌人时按固定间隔高频结算小伤害并刷新短眩晕；同一目标的间隔在各道环之间共享。
## 伤害、威胁显示与渲染共用同一扩张时钟和真实环带（expanding_ring_sweep），权威端结算、客机只播放。
## 画面用共享像素圈（pixel_arc）：环带范围一层淡色，加原版式三层电光圈。
const PALETTE = preload("res://scripts/effects/我的世界/mc_electric_palette.gd")
const ARC = preload("res://scripts/effects/我的世界/pixel_arc.gd")
const RING_SWEEP = preload("res://classes/expanding_ring_sweep.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")

var waves:int = 3
var wave_gap:float = 0.25
var max_radius:float = 480.0
var expand_time:float = 1.3
var half_width:float = 22.0
var age:float = 0.0
var _source:WeakRef
var _previous:PackedFloat32Array = PackedFloat32Array()
var _next_tick:Dictionary = {}


func setup(caster:ball,point:Vector2) -> void:
	_source = weakref(caster)
	waves = maxi(int(caster.get("ring_waves")),1)
	wave_gap = maxf(float(caster.get("ring_wave_gap")),0.0)
	max_radius = maxf(float(caster.get("ring_radius")),1.0)
	expand_time = maxf(float(caster.get("ring_expand_time")),0.05)
	half_width = maxf(float(caster.get("ring_half_width")),1.0)
	_previous.resize(waves)
	_previous.fill(0.0)
	top_level = true
	global_position = point
	z_as_relative = false
	z_index = 149
	add_to_group("BattleTransient")
	add_to_group("MCLightningRodRing")


func source_unit() -> ball:
	return _source.get_ref() as ball if _source != null else null


func total_time() -> float:
	return wave_gap * float(waves - 1) + expand_time


func wave_radius(index:int,at:float = -1.0) -> float:
	var t:float = (age if at < 0.0 else at) - wave_gap * float(index)
	if t <= 0.0 or t > expand_time: return -1.0
	var p:float = t / expand_time
	return max_radius * (1.0 - pow(1.0 - p,1.6))


func can_deal_damage() -> bool:
	var caster:ball = source_unit()
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() and caster.get_world_2d() == get_world_2d() \
		and caster.is_multiplayer_authority() and caster.health > 0 and caster.is_combat_runtime_active() and not caster.is_damage_output_disabled()


func _physics_process(delta:float) -> void:
	if delta <= 0.0 or get_tree().paused or Game.now_stop_state or is_queued_for_deletion(): return
	var caster:ball = source_unit()
	if is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_combat_runtime_active(): return
	age += delta
	if can_deal_damage(): _strike(caster)
	for i:int in range(waves): _previous[i] = maxf(wave_radius(i),0.0)
	queue_redraw()
	if age >= total_time(): queue_free()


func _strike(caster:ball) -> void:
	var excluded:Dictionary = {}
	for id:Variant in _next_tick:
		if float(_next_tick[id]) > age: excluded[id] = true
	var damage:float = caster.attack_damage(float(caster.get("ring_damage_ratio")))
	for i:int in range(waves):
		var radius:float = wave_radius(i)
		if radius < 0.0: continue
		for contact:Dictionary in RING_SWEEP.contacts(caster,global_position,_previous[i],radius,half_width,excluded):
			if not can_deal_damage(): return
			var target:ball = contact.target
			if not is_instance_valid(target) or target.is_queued_for_deletion() or not U.enemy(caster,target): continue
			excluded[target.get_instance_id()] = true
			_next_tick[target.get_instance_id()] = age + maxf(float(caster.get("ring_tick")),0.02)
			var accepted:bool = target.receive_classified_spatial_damage(damage,{"shape":"circle","point":contact.point,"origin":global_position,"radius":half_width,
				"source":caster,"focus_position":contact.point,"carrier":"area"},&"ordinary",false,false)
			if accepted and is_instance_valid(target) and target.health > 0: target.apply_stun(float(caster.get("ring_stun")),caster)


func threats(receiver:ball = null) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	if not can_deal_damage() or age >= total_time() or is_queued_for_deletion(): return result
	var caster:ball = source_unit()
	if is_instance_valid(receiver) and not U.enemy(caster,receiver): return result
	var damage:float = caster.attack_damage(float(caster.get("ring_damage_ratio")))
	for i:int in range(waves):
		var radius:float = wave_radius(i)
		if radius < 0.0: continue
		for band:Dictionary in RING_SWEEP.segments(global_position,_previous[i],radius,half_width):
			result.append({"shape":"segment","start":band.a,"end":band.b,"radius":band.r,"damage":damage,"source":caster,"kind":"lightning_rod_ring","danger_in":0.0,"danger_duration":0.03})
	return result


func _draw() -> void:
	var palette := PackedColorArray([PALETTE.OUTER,PALETTE.MIDDLE,PALETTE.CORE])
	for i:int in range(waves):
		var radius:float = wave_radius(i)
		if radius < 0.0: continue
		var alpha:float = clampf(1.0 - pow(radius / max_radius,2.2),0.0,1.0)
		ARC.draw(self,Vector2.ZERO,radius,0.0,TAU,96,Color(PALETTE.OUTER,0.22 * alpha),half_width * 2.0)
		ARC.draw_ring(self,Vector2.ZERO,radius,Color.WHITE,alpha,palette)
