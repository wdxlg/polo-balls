extends "res://scripts/characters/动漫/咒术回战/jjk_base.gd"
## 两面宿傩（咒术回战，不含真身）。超模角色。
## 被动：诅咒之王（反转术式、黑闪）；残血锁血：第一次受到致命伤时锁在 1 血，无敌咏唱并放出世界斩。
## 左键 解（按住0.5秒=蜘蛛网；领域展延中变为无视无下限的拳脚）  右键 捌（贴身，按对方耐久校准）
## 中键 开 竈（火矢，领域中增强）
## 1 领域展延  2 领域展开 伏魔御厨子（全场开放领域；展开中再按=缩小范围提升威力）
## 3 召唤 八握剑异戒神将魔虚罗  4 召唤 嵌合暗兽 阿吉托  5 世界斩（魔虚罗适应无下限后习得）
const U2 = preload("res://scripts/characters/我的世界/new5/utils.gd")
const MAHORAGA_SCENE_PATH:String = "res://scenes/characters/动漫/魔虚罗.tscn"
const AGITO_SCENE_PATH:String = "res://scenes/characters/动漫/嵌合暗兽.tscn"

@export_category("两面宿傩")
@export var dismantle_cooldown:float = 0.35
@export var dismantle_damage_multiplier:float = 1.2
@export var dismantle_length:float = 440.0
@export var web_cooldown:float = 5.0
@export var web_radius:float = 150.0
@export var web_damage_multiplier:float = 3.0
@export var cleave_cooldown:float = 2.5
@export var cleave_range:float = 120.0
@export var cleave_damage_multiplier:float = 2.0
@export var cleave_health_ratio:float = 0.10
@export var fuga_cooldown:float = 10.0
@export var fuga_cost:float = 250.0
@export var fuga_radius:float = 160.0
@export var fuga_damage_multiplier:float = 5.0
@export var amplification_seconds:float = 6.0
@export var amplification_cooldown:float = 14.0
@export var punch_multiplier:float = 2.0
@export var domain_cost:float = 400.0
@export var domain_duration:float = 8.0
@export var domain_seal_seconds:float = 20.0
@export var uv_exposure_to_seal:float = 3.0
@export var world_slash_cost:float = 500.0
@export var world_slash_cooldown:float = 18.0
@export var world_slash_chant:float = 1.2
@export var world_slash_lock_time:float = 0.25
@export var world_slash_width:float = 70.0
@export var world_slash_health_ratio:float = 0.45
@export var world_slash_damage_multiplier:float = 6.0
@export var hp_lock_seconds:float = 1.6

var dismantle_cd:float = 0.0
var web_cd:float = 0.0
var cleave_cd:float = 0.0
var fuga_cd:float = 0.0
var amp_left:float = 0.0
var amp_cd:float = 0.0
var punch_cd:float = 0.0
var world_slash_cd:float = 0.0
var domain_seal_left:float = 0.0
var uv_exposure:float = 0.0
var world_slash_learned:bool = false
var hp_lock_used:bool = false
var hp_lock_left:float = -1.0
var chant_left:float = -1.0
var chant_dir:Vector2 = Vector2.RIGHT
var chant_locked:bool = false
var chant_empowered:bool = false
var casting:bool = false
var mahoraga_summoned:bool = false
var agito_summoned:bool = false
var _chant_step:int = 0
var _summons:Array = []

func _ready() -> void:
	intro_sound = "sukuna_intro"
	cursed_energy_max = maxf(cursed_energy_max,2000.0)
	super._ready()
	add_to_group("JJKSukuna")

# ---------------------------------------------------------------- 输入
func controlled_attack_action() -> void: press(0)
func controlled_skill_action() -> void: press(1)
func controlled_middle_action() -> void: press(2)
func player_control_extra_actions() -> Array[StringName]:
	return [&"controlled_amplification",&"controlled_domain",&"controlled_mahoraga",&"controlled_agito",&"controlled_world_slash"]
func controlled_amplification() -> void:
	if is_player_controlled(): cast_amplification()
func controlled_domain() -> void:
	if is_player_controlled():
		if not shrink_domain(): cast_domain()
func controlled_mahoraga() -> void:
	if is_player_controlled(): summon_mahoraga()
func controlled_agito() -> void:
	if is_player_controlled(): summon_agito()
func controlled_world_slash() -> void:
	if is_player_controlled(): begin_world_slash(player_control_aim_direction(direction),false)

func on_press(index:int) -> bool:
	var aim:Vector2 = aim_point(global_position + direction * 150.0)
	match index:
		0:
			if amp_left > 0.0: return punch_toward(aim)
			return can_act() and technique_ready() and (dismantle_cd <= 0.0 or web_cd <= 0.0)
		1: return cast_cleave(aim)
		2: return cast_fuga(global_position.direction_to(aim))
	return false

func on_hold_released(index:int,time:float) -> void:
	if index != 0 or amp_left > 0.0: return
	var aim:Vector2 = aim_point(global_position + direction * 150.0)
	if time >= 0.5: cast_web(aim)
	else: cast_dismantle(global_position.direction_to(aim))

func jjk_step(delta:float) -> void:
	for n:String in ["dismantle_cd","web_cd","cleave_cd","fuga_cd","amp_cd","punch_cd","world_slash_cd","domain_seal_left"]:
		set(n,maxf(0.0,float(get(n)) - delta))
	if amp_left > 0.0:
		amp_left -= delta
		cursed_energy = maxf(0.0,cursed_energy - 25.0 * delta)
		if amp_left <= 0.0 or cursed_energy <= 0.0: amp_left = 0.0
	uv_exposure = maxf(0.0,uv_exposure - delta * 0.1)
	if not world_slash_learned: _check_learn_world_slash()
	if hp_lock_left >= 0.0:
		hp_lock_left -= delta
	if chant_left >= 0.0:
		chant_left -= delta
		_step_chant()
		if chant_left <= (world_slash_lock_time if chant_empowered else world_slash_lock_time * 2.0) and not chant_locked:
			chant_locked = true
			if not is_player_controlled() or chant_empowered:
				var t:ball = JJK.nearest_enemy(self)
				if is_instance_valid(t): chant_dir = global_position.direction_to(t.global_position)
			else: chant_dir = player_control_aim_direction(chant_dir)
		if chant_left < 0.0: _fire_world_slash()
	if amp_left > 0.0 and is_player_controlled() and is_held(0) and punch_cd <= 0.0:
		punch_toward(player_control_aim_world_position(global_position + direction * 100.0))

func _check_learn_world_slash() -> void:
	for unit:Node in get_tree().get_nodes_in_group("JJKMahoraga"):
		if unit.has_method("adaptation_level") and int(unit.call("adaptation_level","gojo_infinity")) >= 2 and not JJK.U.enemy(self,unit):
			world_slash_learned = true
			fx("text",{"pos":global_position + Vector2(0,-70),"text":"World Slash learned" if JJK.english() else "习得：世界斩","size":22,"color":Color(1,0.3,0.3)},1.6)
			return

# ---------------------------------------------------------------- 锁血与领域展延
func health_after_lethal_prevention(health_before:int) -> int:
	if hp_lock_left >= 0.0: return maxi(1,health_before)
	if hp_lock_used: return 0
	hp_lock_used = true
	return 1

func on_lethal_health_loss_prevented() -> void:
	if hp_lock_left >= 0.0 or not is_multiplayer_authority(): return
	hp_lock_left = hp_lock_seconds
	cursed_energy = cursed_energy_max
	burnout_left = 0.0
	chant_left = -1.0
	begin_world_slash(direction,true)
	fx("text",{"pos":global_position + Vector2(0,-80),"text":"HP Locked" if JJK.english() else "锁血","size":26,"color":Color(1,0.1,0.1),"world":true},1.4)

func hp_locked() -> bool:
	return hp_lock_left >= 0.0

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if hp_locked() and damage > 0.0: return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)

func _receive_spatial_damage_untyped(damage:float,damage_space:Variant,ignore_block:bool,raw_health:bool) -> bool:
	if hp_locked() and damage > 0.0: return false
	return super._receive_spatial_damage_untyped(damage,damage_space,ignore_block,raw_health)

func receive_internal_status_damage(damage:float,kind:StringName,source:Node = null) -> float:
	if hp_locked(): return 0.0
	return super.receive_internal_status_damage(damage,kind,source)

func can_receive_negative_effects() -> bool:
	if hp_locked(): return false
	return super.can_receive_negative_effects()

func jjk_neutralizes_infinity(_target:Node) -> bool:
	return amp_left > 0.0

func jjk_uv_resistance() -> float:
	return 0.6 if amp_left > 0.0 else 0.0

func on_jjk_uv_exposure(seconds:float) -> void:
	uv_exposure += seconds
	if uv_exposure >= uv_exposure_to_seal and domain_seal_left <= 0.0:
		uv_exposure = 0.0
		domain_seal_left = domain_seal_seconds
		fx("text",{"pos":global_position + Vector2(0,-70),"text":"Domain sealed (brain burnt)" if JJK.english() else "脑被烧坏：领域封印","size":20,"color":Color(0.7,0.8,1)},1.6)

func can_open_domain() -> bool:
	return super.can_open_domain() and domain_seal_left <= 0.0

func cast_amplification() -> bool:
	if not can_act() or amp_cd > 0.0 or amp_left > 0.0 or not spend(150.0): return false
	amp_left = amplification_seconds
	amp_cd = amplification_cooldown
	fx("text",{"pos":global_position + Vector2(0,-60),"text":"Domain Amplification" if JJK.english() else "领域展延","size":20,"color":Color(0.9,0.4,1)},1.0)
	fx("shockwave",{"pos":global_position,"radius":60.0,"color":Color(0.7,0.2,0.9)},0.3)
	return true

func technique_ready() -> bool:
	return super.technique_ready() and amp_left <= 0.0

# ---------------------------------------------------------------- 术式
func cast_dismantle(dir:Vector2) -> bool:
	if not can_act() or not technique_ready() or dismantle_cd > 0.0 or not spend(15.0): return false
	dismantle_cd = dismantle_cooldown
	var d:Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var a:Vector2 = global_position + d * 16.0
	var b:Vector2 = a + d * dismantle_length
	var wall:Dictionary = JJK.U.trace(self,a,b)
	if not wall.is_empty() and wall.get("position") is Vector2: b = wall["position"]
	var mult:float = dismantle_damage_multiplier * (1.3 if black_flash_zone_left > 0.0 else 1.0)
	for t:ball in JJK.enemies_on_segment(self,a,b,16.0):
		JJK.hit(self,t,attack_damage(mult),t.global_position,&"ordinary",{"phenomenon":"sukuna_dismantle"})
	_hit_barriers_on_segment(a,b,3.0)
	fx("slash",{"a":a,"b":b,"color":Color(1,0.9,0.9),"width":3.0,"world":true},0.22)
	sfx("sukuna_dismantle",-8.0)
	return true

func _hit_barriers_on_segment(a:Vector2,b:Vector2,amount:float) -> void:
	for d:Variant in DOMAIN.active_domains(get_tree()):
		if not bool(d.call("barrier_intact")) or not JJK.U.enemy(self,d.caster): continue
		var near:float = U2.segment_distance(d.center,a,b)
		if near <= d.radius and (a.distance_to(d.center) > d.radius or b.distance_to(d.center) > d.radius):
			d.call("damage_barrier",amount * (0.3 if d.flip_left > 0.0 else 1.0))

func cast_web(at:Vector2) -> bool:
	if not can_act() or not technique_ready() or web_cd > 0.0 or not spend(120.0): return false
	web_cd = web_cooldown
	var p:Vector2 = global_position + (at - global_position).limit_length(260.0)
	for t:ball in JJK.enemies_in_circle(self,p,web_radius):
		JJK.hit(self,t,attack_damage(web_damage_multiplier),t.global_position,&"ordinary",{"phenomenon":"sukuna_dismantle"})
		JJK.stun(self,t,0.5,{"phenomenon":"sukuna_dismantle"})
	fx("web",{"pos":p,"radius":web_radius,"world":true},0.6)
	sfx("sukuna_dismantle",-3.0)
	return true

func cast_cleave(at:Vector2) -> bool:
	if not can_act() or not technique_ready() or cleave_cd > 0.0: return false
	var best:ball = null
	var best_d:float = INF
	for t:ball in JJK.enemies_in_circle(self,global_position,cleave_range):
		var score:float = t.global_position.distance_to(at)
		if score < best_d:
			best_d = score
			best = t
	if best == null or not spend(80.0): return false
	cleave_cd = cleave_cooldown
	var point:Vector2 = best.global_position
	var mult:float = roll_black_flash(point)
	var amount:float = (attack_damage(cleave_damage_multiplier) + float(best.Max_health) * cleave_health_ratio) * mult
	JJK.hit(self,best,amount,point,&"ordinary",{"phenomenon":"sukuna_cleave"})
	fx("cleave",{"pos":point,"radius":34.0,"world":true},0.35)
	sfx("sukuna_cleave",-4.0)
	return true

func cast_fuga(dir:Vector2) -> bool:
	if not can_act() or not technique_ready() or fuga_cd > 0.0 or not spend(fuga_cost): return false
	fuga_cd = fuga_cooldown
	var d:Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	launch("fuga",global_position + d * 24.0,d * 520.0,16.0,2.0)
	sfx("sukuna_fuga",-2.0)
	fx("text",{"pos":global_position + Vector2(0,-56),"text":"Open: Fuga" if JJK.english() else "开 竈","size":22,"color":Color(1,0.55,0.15)},0.9)
	return true

func on_projectile_impact(kind:String,_target:ball,point:Vector2) -> void:
	if kind != "fuga": return
	var boosted:bool = own_domain() != null
	var r:float = fuga_radius * (1.35 if boosted else 1.0)
	for t:ball in JJK.enemies_in_circle(self,point,r):
		JJK.hit(self,t,attack_damage(fuga_damage_multiplier * (1.5 if boosted else 1.0)),t.global_position,&"fire",{"phenomenon":"sukuna_fuga"})
		JJK.knock(self,t,t.global_position - point,160.0,800.0,0.0,{"phenomenon":"sukuna_fuga"})
	fx("fuga_burst",{"pos":point,"radius":r,"world":true},0.8)

func punch_toward(at:Vector2) -> bool:
	if not can_act() or punch_cd > 0.0: return false
	punch_cd = 0.45
	var d:Vector2 = global_position.direction_to(at)
	if d == Vector2.ZERO: d = Vector2.RIGHT
	var reach:float = 70.0
	var best:ball = null
	for t:ball in JJK.enemies_in_circle(self,global_position + d * 40.0,reach):
		if best == null or t.global_position.distance_to(global_position) < best.global_position.distance_to(global_position): best = t
	apply_knockback(d,60.0,700.0,0.0,0.0,{"source":self})
	if best == null: return true
	var point:Vector2 = global_position.lerp(best.global_position,0.6)
	var mult:float = punch_multiplier * roll_black_flash(point)
	JJK.hit(self,best,attack_damage(mult),point,&"ordinary",{"phenomenon":"sukuna_taijutsu","bypass_infinity":true})
	JJK.knock(self,best,d,70.0 * (2.0 if mult > punch_multiplier else 1.0),700.0,0.0,{"phenomenon":"sukuna_taijutsu","bypass_infinity":true})
	return true

func cast_domain() -> bool:
	# 解除领域展延才能发动术式。
	if amp_left > 0.0 and can_act() and super.can_open_domain() == false and burnout_left <= 0.0 and domain_seal_left <= 0.0 and domains_used < max_domains_per_battle and own_domain() == null:
		amp_left = 0.0
	if not can_act() or not can_open_domain() or not spend(domain_cost): return false
	open_domain("shrine",global_position,0.0,domain_duration)
	sfx("sukuna_domain",2.0)
	fx("text",{"pos":global_position + Vector2(0,-120),"text":"Domain Expansion: Malevolent Shrine" if JJK.english() else "领域展开 伏魔御厨子","size":34,"color":Color(1,0.25,0.25),"world":true},2.2)
	return true

func shrink_domain() -> bool:
	var d:Node = own_domain()
	if d == null or str(d.get("domain_kind")) != "shrine" or bool(d.get("shrunk")): return false
	d.set("shrunk",true)
	fx("text",{"pos":global_position + Vector2(0,-80),"text":"Shrine narrowed" if JJK.english() else "缩小领域范围","size":20,"color":Color(1,0.5,0.4)},1.0)
	return true

func begin_world_slash(dir:Vector2,empowered:bool) -> bool:
	if chant_left >= 0.0: return false
	if not empowered:
		if not can_act() or not technique_ready() or not world_slash_learned or world_slash_cd > 0.0 or not spend(world_slash_cost): return false
		world_slash_cd = world_slash_cooldown
	chant_empowered = empowered
	chant_left = world_slash_chant
	chant_dir = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	chant_locked = false
	casting = true
	_chant_step = 0
	sfx("sukuna_world_slash",0.0)
	return true

func _step_chant() -> void:
	var zh:Array[String] = ["龙鳞","反发","双子流星"]
	var en:Array[String] = ["Dragon Scales","Recoil","Twin Meteors"]
	var step:int = int((world_slash_chant - chant_left) / (world_slash_chant / 3.0)) + 1
	if step > _chant_step and step <= 3:
		_chant_step = step
		fx("text",{"pos":global_position + Vector2(0,-50 - step * 6),"text":(en if JJK.english() else zh)[step - 1],"size":18,"color":Color(1,0.35,0.35)},0.7)

func _fire_world_slash() -> void:
	chant_left = -1.0
	casting = false
	chant_locked = false
	if health <= 0: return
	var width:float = world_slash_width * (1.6 if chant_empowered else 1.0)
	var rect:Rect2 = JJK.map_rect(self)
	var length:float = rect.size.length() * 1.3
	var a:Vector2 = global_position - chant_dir * length * 0.5
	var b:Vector2 = global_position + chant_dir * length * 0.5
	# 世界斩斩的是空间本身：无视无下限、格挡与结界。
	for t:ball in JJK.enemies_on_segment(self,a,b,width * 0.5):
		var amount:float = float(t.Max_health) * world_slash_health_ratio + attack_damage(world_slash_damage_multiplier)
		JJK.hit(self,t,amount,t.global_position,&"ordinary",{"phenomenon":"sukuna_world_slash","bypass_infinity":true,"sure_hit":true,"unadaptable":true})
	for d:Variant in DOMAIN.active_domains(get_tree()):
		if bool(d.call("barrier_intact")) and JJK.U.enemy(self,d.caster) and U2.segment_distance(d.center,a,b) < d.radius:
			d.call("damage_barrier",1000.0)
	fx("world_slash",{"a":a,"b":b,"width":width,"world":true},0.9)
	if chant_empowered:
		world_slash_learned = true
		world_slash_cd = maxf(world_slash_cd,world_slash_cooldown)
	chant_empowered = false

# ---------------------------------------------------------------- 召唤（十影法术）
func summon_mahoraga() -> bool:
	if mahoraga_summoned or not can_act() or not spend(300.0): return false
	mahoraga_summoned = true
	sfx("mahoraga_summon",0.0)
	fx("text",{"pos":global_position + Vector2(0,-70),"text":"With this treasure I summon... Mahoraga!" if JJK.english() else "布瑠部由良由良——八握剑异戒神将 魔虚罗","size":20,"color":Color(0.9,0.9,0.7),"world":true},1.8)
	_spawn_summon(MAHORAGA_SCENE_PATH,Vector2(-60,0))
	return true

func summon_agito() -> bool:
	if agito_summoned or not can_act() or not spend(250.0): return false
	agito_summoned = true
	sfx("agito_roar",0.0)
	fx("text",{"pos":global_position + Vector2(0,-70),"text":"Chimera Shadow Garden: Agito" if JJK.english() else "嵌合暗兽 阿吉托","size":20,"color":Color(0.8,0.8,1.0),"world":true},1.6)
	_spawn_summon(AGITO_SCENE_PATH,Vector2(60,0))
	return true

func _spawn_summon(path:String,offset:Vector2) -> void:
	if not ResourceLoader.exists(path): return
	var packed:PackedScene = load(path)
	var unit:ball = packed.instantiate() as ball
	if unit == null: return
	unit.Master = self
	unit.Master_name = name
	unit.Team = Team
	unit.inherit_master_attack_power = false
	unit.Target_Enemy = Target_Enemy
	unit.set("summoner",self)
	unit.name = Game.return_random_name(unit)
	get_tree().current_scene.add_child(unit,true)
	unit.global_position = JJK.clamp_to_map(self,global_position + offset,30.0)
	_summons.append(weakref(unit))
	fx("shockwave",{"pos":unit.global_position,"radius":80.0,"color":Color(0.05,0.05,0.1)},0.5)

# ---------------------------------------------------------------- 威胁
func jjk_threats() -> Array:
	var result:Array = []
	if chant_left >= 0.0:
		var width:float = world_slash_width * (1.6 if chant_empowered else 1.0)
		result.append({"shape":"segment","start":global_position - chant_dir * 3000.0,"end":global_position + chant_dir * 3000.0,"radius":width * 0.5,"locked":chant_locked,"kind":"sukuna_world_slash","source":self})
	for id:Variant in _projectiles.keys():
		var p:Node2D = _projectiles[id]
		if is_instance_valid(p):
			var v:Vector2 = p.get("velocity")
			result.append({"shape":"circle","position":p.global_position + v * 0.15,"radius":fuga_radius,"locked":p.global_position.distance_to(Target_Enemy.global_position) < 260.0 if is_instance_valid(Target_Enemy) else false,"kind":"sukuna_fuga","source":self})
	return result
func get_debug_attack_regions() -> Array: return jjk_threats()
func get_ai_attack_threats(_receiver:Node = null) -> Array: return jjk_threats()
func get_debug_detection_regions() -> Array[Dictionary]: return []

# ---------------------------------------------------------------- AI（博弈）
func jjk_ai() -> void:
	var target:ball = ai_target()
	if not is_instance_valid(target) or chant_left >= 0.0: return
	var d:float = global_position.distance_to(target.global_position)
	var is_gojo:bool = target.is_in_group("JJKGojo")
	var tree:SceneTree = get_tree()
	# 早召唤：式神分担无下限、魔虚罗去适应。
	if not mahoraga_summoned and (is_gojo or health < Max_health * 0.7) and cursed_energy >= 300.0:
		summon_mahoraga()
		return
	if not agito_summoned and mahoraga_summoned and cursed_energy >= 250.0 and clock > 6.0:
		summon_agito()
		return
	# 领域对拼：敌方开无量空处 → 立刻展开伏魔御厨子对冲；不能开就用领域展延。
	var enemy_uv:Node = null
	for dom:Variant in DOMAIN.active_domains(tree):
		if dom.domain_kind == "uv" and JJK.U.enemy(self,dom.caster): enemy_uv = dom
	var mine:Node = own_domain()
	if enemy_uv != null and mine == null:
		if cursed_energy >= domain_cost and cast_domain(): return
		if amp_left <= 0.0 and amp_cd <= 0.0 and cursed_energy >= 150.0:
			cast_amplification()
			return
	if mine != null and enemy_uv != null and not bool(mine.get("shrunk")) and float(enemy_uv.get("flip_left")) > 0.0:
		shrink_domain()
	# 对方烧断（无下限失效）→ 开领域；对方刚开完领域时最佳。
	var bo:Variant = target.get("burnout_left")
	var target_burnt:bool = bo != null and float(bo) > 0.0
	if mine == null and can_open_domain() and cursed_energy >= domain_cost and (target_burnt or not target.is_in_group("JJKUnit") or (not is_gojo and rng.randf() < 0.05)):
		cast_domain()
		return
	if world_slash_learned and world_slash_cd <= 0.0 and cursed_energy >= world_slash_cost and d < 900.0:
		begin_world_slash(global_position.direction_to(target.global_position),false)
		return
	var infinity_up:bool = is_gojo and bool(target.call("infinity_active")) and not target_burnt
	if infinity_up:
		# 无下限挡住术式：贴身开领域展延用拳头打；远处保持压制咒力消耗。
		# 无下限挡住术式：逼近后开领域展延用拳头打；接近途中用解消耗对方咒力。
		if d < 200.0 and amp_left <= 0.0 and amp_cd <= 0.0 and cursed_energy >= 150.0: cast_amplification()
		if amp_left > 0.0:
			steer(global_position.direction_to(target.global_position))
			if d < 110.0: punch_toward(target.global_position)
			return
		if dismantle_cd <= 0.0 and rng.randf() < 0.6: cast_dismantle(global_position.direction_to(target.global_position))
		if amp_cd <= 2.0: steer(global_position.direction_to(target.global_position))
		else: steer_keep_distance(target,200.0,80.0)
		return
	if amp_left > 0.0:
		steer(global_position.direction_to(target.global_position))
		if d < 110.0: punch_toward(target.global_position)
		return
	if d < cleave_range and cleave_cd <= 0.0: cast_cleave(target.global_position)
	elif fuga_cd <= 0.0 and cursed_energy >= fuga_cost + 200.0 and d > 140.0 and d < 600.0 and (target.dizziness or rng.randf() < 0.08): cast_fuga(global_position.direction_to(lead(target,520.0)))
	elif web_cd <= 0.0 and d < 280.0 and rng.randf() < 0.25: cast_web(target.global_position)
	elif dismantle_cd <= 0.0 and d < dismantle_length: cast_dismantle(global_position.direction_to(lead(target,3000.0)))
	steer_keep_distance(target,110.0,40.0)

# ---------------------------------------------------------------- 视觉
func visual_state() -> Dictionary:
	var data:Dictionary = super.visual_state()
	data["amp"] = amp_left
	data["cl"] = chant_left
	data["cd"] = chant_dir
	data["ck"] = chant_locked
	data["ce2"] = chant_empowered
	data["hl"] = hp_lock_left
	data["seal"] = domain_seal_left
	return data

func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	amp_left = float(data.get("amp",0.0))
	chant_left = float(data.get("cl",-1.0))
	chant_dir = data.get("cd",chant_dir)
	chant_locked = bool(data.get("ck",false))
	chant_empowered = bool(data.get("ce2",false))
	hp_lock_left = float(data.get("hl",-1.0))
	domain_seal_left = float(data.get("seal",0.0))

func draw_overlay(o:Node2D) -> void:
	var t:float = _view_clock
	if amp_left > 0.0:
		o.draw_arc(global_position,28.0,0,TAU,32,Color(0.75,0.25,0.95,0.55 + 0.2 * sin(t * 10.0)),3.0,true)
	if hp_lock_left >= 0.0:
		o.draw_circle(global_position,34.0,Color(0.8,0.0,0.05,0.18))
		o.draw_arc(global_position,34.0,t * 6.0,t * 6.0 + 4.5,24,Color(1,0.1,0.1,0.9),3.0,true)
	if chant_left >= 0.0:
		var width:float = world_slash_width * (1.6 if chant_empowered else 1.0)
		var a:Vector2 = global_position - chant_dir * 2400.0
		var b:Vector2 = global_position + chant_dir * 2400.0
		if chant_locked:
			o.draw_line(a,b,Color(1,0.1,0.1,0.35),width)
			o.draw_line(a,b,Color(1,0.9,0.9,0.9),2.0)
		else:
			o.draw_line(global_position,global_position + chant_dir * 90.0,Color(1,0.2,0.2,0.6),2.0)
	if domain_seal_left > 0.0:
		o.draw_line(global_position + Vector2(-24,36),global_position + Vector2(-24 + 48 * domain_seal_left / domain_seal_seconds,36),Color(0.6,0.75,1.0,0.9),2.0)

func get_armor_test_effect_summary() -> String:
	if JJK.english():
		return "King of Curses: Reverse Cursed Technique and Black Flash. The first lethal hit locks him at 1 HP: invulnerable chant, then an empowered World Slash.\nLeft Dismantle (hold 0.5s: Spiderweb; during Domain Amplification: Infinity-piercing strikes). Right Cleave (touch range, scales with target max HP). Middle Open: Fuga fire arrow (stronger inside his domain). 1 Domain Amplification, 2 Malevolent Shrine: an open domain covering the whole map that keeps slicing everyone and every barrier (press again to narrow it for double power), 3 summon Mahoraga, 4 summon Agito, 5 World Slash (learned once Mahoraga adapts to Infinity) which cuts space itself. 3s of Unlimited Void exposure burns out his domain for 20s."
	return "诅咒之王：反转术式、黑闪。第一次受到致命伤时锁在1血，无敌咏唱后放出强化世界斩。\n左键 解（按住0.5秒=蜘蛛网；领域展延中改为无视无下限的拳脚）；右键 捌（贴身，按目标最大生命校准）；中键 开 竈火矢（领域中增强）。1 领域展延；2 伏魔御厨子：覆盖全场的开放领域，持续斩击全部敌人和敌方结界（展开中再按缩小范围、威力翻倍）；3 召唤魔虚罗；4 召唤嵌合暗兽；5 世界斩（魔虚罗适应无下限后习得），斩断空间本身。累计暴露在无量空处3秒会烧坏大脑，领域封印20秒。"
