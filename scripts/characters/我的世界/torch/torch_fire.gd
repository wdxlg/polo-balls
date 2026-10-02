extends "res://scripts/effects/我的世界/烈焰火场.gd"
## 火把火星落地生成的火：复用烈焰人火场的原版 3D 火焰方块、地面伤害与共享燃烧（只在权威端结算）。
## 灵魂火改用原版 soul_fire_0/1 贴图，伤害与燃烧倍率由火把翻倍后传入。注册为 AI_Hazard，威胁圆即真实伤害圆。
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const PARTICLES = preload("res://scripts/characters/我的世界/torch/torch_particles.gd")

var soul:bool = false
var fire_id:int = 0
var cell:Vector2i = Vector2i.ZERO
var _fx_rng := RandomNumberGenerator.new()
var _fx_wait:float = -1.0


func setup_torch(source:ball,id:int,point:Vector2,soul_fire:bool,radius:float,duration:float,area_multiplier:float,burn_seconds:float,burn_multiplier:float) -> void:
	soul = soul_fire
	fire_id = id
	add_to_group("BattleTransient")
	add_to_group("AI_Hazard")
	add_to_group("MCTorchFire")
	setup(source,source.Team,point,radius,duration,0.5,area_multiplier,burn_seconds,burn_multiplier)


## 施加燃烧：soul_fire 为灵魂火燃烧（原版灵魂火外观）。同一火把已有更强的燃烧（灵魂火）时
## 保留较高的每跳伤害和它的灵魂火外观，只刷新时长。
static func apply_burn(source:ball,target:ball,seconds:float,tick:float,soul_fire:bool = false) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(target): return false
	var existing:Node = target.get_node_or_null(NodePath(String(SHARED_BURN.NODE_NAME)))
	if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.get("source") == source:
		var held:float = float(existing.get("tick_damage"))
		if held >= tick and existing.get("soul") == true: soul_fire = true
		tick = maxf(tick,held)
	return SHARED_BURN.apply_amount(source,target,seconds,tick,SHARED_BURN.TICK_INTERVAL,soul_fire)


func _soul_fire_visual() -> bool:
	return soul


## 火把的火持续冒原版大烟（共用火把粒子发射器，纯视觉本地随机），不再用烈焰人火场的稀疏烟。
func _update_fire_smoke(delta:float) -> void:
	if _fx_wait < 0.0:
		_fx_rng.randomize()
		_fx_wait = _fx_rng.randf_range(0.0,0.2)
	_fx_wait -= delta
	if _fx_wait > 0.0: return
	_fx_wait = _fx_rng.randf_range(0.14,0.26)
	var fx:Node2D = PARTICLES.find_or_create(self)
	if fx == null: return
	var base:Vector2 = global_position + _fire_visual_local_position
	var top:Vector2 = base + Vector2(_fx_rng.randf_range(-_fire_base_width * 0.32,_fire_base_width * 0.32),-_fire_base_height * _fx_rng.randf_range(0.2,0.5))
	fx.smoke(top,true)
	if _fx_rng.randf() < 0.5: fx.flame(top + Vector2(0.0,3.0),soul,_fx_rng.randf_range(2.4,3.2))


func damage_center() -> Vector2:
	return global_position + _damage_center_offset


func damage_radius() -> float:
	return _radius


func time_left() -> float:
	return maxf(_duration - _elapsed,0.0)


func tick_damage() -> float:
	var source:ball = _source_ball()
	return source.attack_damage(_area_tick_damage_multiplier) if source != null else 0.0


func burn_tick_damage() -> float:
	var source:ball = _source_ball()
	return source.attack_damage(_burn_tick_damage_multiplier) if source != null else 0.0


## 火把死亡等场合让火很快熄灭（各端各自执行）。
func extinguish(after:float = 0.4) -> void:
	_duration = minf(_duration,_elapsed + maxf(after,0.0))


func _can_damage(target:ball) -> bool:
	var source:ball = _source_ball()
	return source != null and source.health > 0 and U.enemy(source,target) and target.health > 0


func _apply_burn(source:ball,target:ball) -> void:
	apply_burn(source,target,_burn_duration,source.attack_damage(_burn_tick_damage_multiplier),soul)


func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	var source:ball = _source_ball()
	if source == null or source.health <= 0 or time_left() <= 0.0: return {}
	return {"shape":"circle","position":damage_center(),"radius":_radius,"damage":tick_damage(),"source":source,
		"danger_duration":time_left(),"kind":"torch_soul_fire" if soul else "torch_fire"}
