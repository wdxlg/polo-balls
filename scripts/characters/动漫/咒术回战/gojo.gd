extends "res://scripts/characters/动漫/咒术回战/jjk_base.gd"
## 五条悟（咒术回战）。超模角色。
## 被动：无下限（阻挡一切非必中接触）、六眼（咒力回复极快）、反转术式、近身体术+黑闪。
## 左键 苍（按住=牵引点跟随鼠标，按满0.8秒成为最大出力）  右键 赫（按住蓄力，松开发射）
## 中键 虚式 茈（松开施放；按满2.4秒=200%咏唱茈）
## 1 瞬移  2 领域展开 无量空处  3 0.2秒无量空处  4 结界翻转（对拼时抵挡外部斩击）
const U2 = preload("res://scripts/characters/我的世界/new5/utils.gd")

@export_category("五条悟")
@export var infinity_energy_per_block:float = 10.0
@export var blue_cooldown:float = 2.5
@export var blue_cost:float = 40.0
@export var blue_radius:float = 160.0
@export var blue_max_radius:float = 220.0
@export var blue_pull_speed:float = 250.0
@export var blue_damage_multiplier:float = 0.2
@export var red_cooldown:float = 1.6
@export var red_cost:float = 60.0
@export var red_damage_multiplier:float = 2.0
@export var red_charged_damage_multiplier:float = 3.5
@export var red_radius:float = 80.0
@export var red_knockback:float = 260.0
@export var purple_cooldown:float = 12.0
@export var purple_cost:float = 300.0
@export var purple_damage_multiplier:float = 4.0
@export var purple_width:float = 90.0
@export var purple_200_hold:float = 2.4
@export var purple_200_cost:float = 600.0
@export var purple_200_damage_multiplier:float = 10.0
@export var teleport_distance:float = 260.0
@export var teleport_cooldown:float = 2.5
@export var domain_cost:float = 300.0
@export var domain_duration:float = 8.0
@export var instant_domain_cost:float = 250.0
@export var instant_domain_cooldown:float = 20.0
@export var flip_cost:float = 60.0
@export var punch_multiplier:float = 1.2

var blue_cd:float = 0.0
var red_cd:float = 0.0
var purple_cd:float = 0.0
var teleport_cd:float = 0.0
var instant_cd:float = 0.0
var punch_cd:float = 0.0
var blue_active:bool = false
var blue_pos:Vector2 = Vector2.ZERO
var blue_left:float = 0.0
var blue_max:bool = false
var blue_steer:bool = false
var _blue_tick:float = 0.0
var _blue_pulled:Dictionary = {}
var red_charge:float = -1.0
var purple_charge:float = -1.0
var purple_cast_left:float = -1.0
var _purple_pending_200:bool = false
var _purple_dir:Vector2 = Vector2.RIGHT
var _ripple_cd:float = 0.0
var _base_speed:float = 135.0
var _ai_blue_follow:float = 0.0
var infinity_blocks:int = 0

func _ready() -> void:
	intro_sound = "gojo_intro"
	super._ready()
	_base_speed = Speed
	add_to_group("JJKGojo")

# ---------------------------------------------------------------- 输入
func controlled_attack_action() -> void: press(0)
func controlled_skill_action() -> void: press(1)
func controlled_middle_action() -> void: press(2)
func player_control_extra_actions() -> Array[StringName]:
	return [&"controlled_teleport",&"controlled_domain",&"controlled_instant_domain",&"controlled_barrier_flip"]
func controlled_teleport() -> void:
	if is_player_controlled(): teleport_to(player_control_aim_world_position(global_position + direction * teleport_distance))
func controlled_domain() -> void:
	if is_player_controlled(): cast_domain()
func controlled_instant_domain() -> void:
	if is_player_controlled(): cast_instant_domain()
func controlled_barrier_flip() -> void:
	if is_player_controlled(): flip_barrier()

func Attack() -> void: Attacking = false
func Skill() -> void: Using_Skill = false

func on_press(index:int) -> bool:
	match index:
		0: return cast_blue(aim_point(global_position + direction * 150.0),true)
		1: return begin_red_charge()
		2: return begin_purple_charge()
	return false

func on_hold_released(index:int,time:float) -> void:
	match index:
		0: blue_steer = false
		1: release_red(aim_dir(direction),time)
		2: release_purple(aim_dir(direction),time)

# ---------------------------------------------------------------- 无下限
func infinity_active() -> bool:
	return health > 0 and technique_ready() and cursed_energy > 20.0

func _infinity_blocks(source:Variant) -> bool:
	if not infinity_active(): return false
	var ctx:Dictionary = JJK.ctx_of(self)
	if bool(ctx.get("sure_hit",false)) or bool(ctx.get("bypass_infinity",false)): return false
	if source == null and ctx.get("source") is Node: source = ctx.get("source")
	if is_instance_valid(source) and source is Node and (source as Node).has_method("jjk_neutralizes_infinity"):
		if bool((source as Node).call("jjk_neutralizes_infinity",self)): return false
	return true

func _on_infinity_block(source:Variant,point:Vector2) -> void:
	infinity_blocks += 1
	cursed_energy = maxf(0.0,cursed_energy - infinity_energy_per_block)
	if is_instance_valid(source) and source is Node and (source as Node).has_method("on_jjk_blocked_by_infinity"):
		(source as Node).call("on_jjk_blocked_by_infinity",self)
	if _ripple_cd <= 0.0:
		_ripple_cd = 0.08
		var at:Vector2 = global_position + (point - global_position).limit_length(30.0)
		fx("ripple",{"pos":at,"radius":22.0},0.35)

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if damage > 0.0 and _infinity_blocks(source):
		_on_infinity_block(source,impact_position)
		return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)

func _receive_spatial_damage_untyped(damage:float,damage_space:Variant,ignore_block:bool,raw_health:bool) -> bool:
	if raw_health and damage > 0.0:
		var source:Variant = null
		var point:Vector2 = global_position
		if damage_space is Dictionary:
			source = (damage_space as Dictionary).get("source")
			if (damage_space as Dictionary).get("point") is Vector2: point = damage_space["point"]
		if _infinity_blocks(source):
			_on_infinity_block(source,point)
			return false
	return super._receive_spatial_damage_untyped(damage,damage_space,ignore_block,raw_health)

func receive_internal_status_damage(damage:float,kind:StringName,source:Node = null) -> float:
	if _infinity_blocks(source): return 0.0
	return super.receive_internal_status_damage(damage,kind,source)

func apply_knockback(knockback_direction:Vector2,knockback_distance:float,knockback_speed:float = 700.0,wall_bounce_strength:float = 0.0,stun_duration:float = 0.0,options:Dictionary = {}) -> Node:
	var source:Variant = options.get("source",null)
	if source != self and _infinity_blocks(source):
		return null
	return super.apply_knockback(knockback_direction,knockback_distance,knockback_speed,wall_bounce_strength,stun_duration,options)

func is_knockback_displacement_immune() -> bool:
	return infinity_active()

func can_receive_negative_effects() -> bool:
	if _infinity_blocks(null): return false
	return super.can_receive_negative_effects()

# ---------------------------------------------------------------- 每帧
func jjk_step(delta:float) -> void:
	blue_cd = maxf(0.0,blue_cd - delta)
	red_cd = maxf(0.0,red_cd - delta)
	purple_cd = maxf(0.0,purple_cd - delta)
	teleport_cd = maxf(0.0,teleport_cd - delta)
	instant_cd = maxf(0.0,instant_cd - delta)
	punch_cd = maxf(0.0,punch_cd - delta)
	_ripple_cd = maxf(0.0,_ripple_cd - delta)
	_step_blue(delta)
	if red_charge >= 0.0: red_charge += delta
	if purple_charge >= 0.0:
		purple_charge += delta
		_step_chant()
	Speed = _base_speed * (0.25 if purple_charge >= 0.0 or purple_cast_left >= 0.0 else 1.0)
	if purple_cast_left >= 0.0:
		purple_cast_left -= delta
		if purple_cast_left < 0.0: _fire_purple()
	_try_punch()

func _step_blue(delta:float) -> void:
	if not blue_active: return
	blue_left -= delta
	if blue_steer and is_player_controlled():
		var want:Vector2 = player_control_aim_world_position(blue_pos)
		blue_pos = blue_pos.move_toward(want,520.0 * delta)
		if held_time(0) >= 0.8 and not blue_max:
			blue_max = true
			fx("shockwave",{"pos":blue_pos,"radius":blue_max_radius,"color":Color(0.3,0.5,1.0)},0.4)
		if held_time(0) < 2.5: blue_left = maxf(blue_left,0.15)
		cursed_energy = maxf(0.0,cursed_energy - (35.0 if blue_max else 15.0) * delta)
	elif _ai_blue_follow > 0.0 and is_instance_valid(Target_Enemy):
		_ai_blue_follow -= delta
		blue_pos = blue_pos.move_toward(Target_Enemy.global_position.lerp(global_position,0.35),300.0 * delta)
	var radius:float = blue_max_radius if blue_max else blue_radius
	var pull:float = blue_pull_speed * (1.45 if blue_max else 1.0)
	var touched:Dictionary = {}
	for t:ball in JJK.enemies_in_circle(self,blue_pos,radius):
		var to:Vector2 = blue_pos - t.global_position
		var dist:float = to.length()
		touched[t.get_instance_id()] = t
		if dist > 6.0:
			# 适应/无下限等由目标自己的位移免疫接口处理。
			KNOCKBACK.set_pull(t,self,to.normalized() * pull * clampf(dist / radius + 0.35,0.35,1.0))
	for id:Variant in _blue_pulled.keys():
		if not touched.has(id) and is_instance_valid(_blue_pulled[id]): KNOCKBACK.release_pull(_blue_pulled[id],self)
	_blue_pulled = touched
	_blue_tick -= delta
	if _blue_tick <= 0.0:
		_blue_tick = 0.2
		var mult:float = blue_damage_multiplier * (1.7 if blue_max else 1.0)
		for t2:ball in JJK.enemies_in_circle(self,blue_pos,radius * 0.6):
			JJK.hit(self,t2,attack_damage(mult),t2.global_position,&"magic",{"phenomenon":"gojo_blue"})
	if blue_left <= 0.0 or not technique_ready(): _end_blue()

func _end_blue() -> void:
	blue_active = false
	blue_steer = false
	blue_max = false
	for id:Variant in _blue_pulled.keys():
		if is_instance_valid(_blue_pulled[id]): KNOCKBACK.release_pull(_blue_pulled[id],self)
	_blue_pulled.clear()

func _try_punch() -> void:
	if punch_cd > 0.0 or not can_act(): return
	var t:ball = JJK.nearest_enemy(self)
	if not is_instance_valid(t) or t.global_position.distance_to(global_position) > 20.0 + U2.radius(t) + U2.radius(self): return
	punch_cd = 0.8
	var point:Vector2 = global_position.lerp(t.global_position,0.6)
	var mult:float = punch_multiplier * roll_black_flash(point)
	JJK.hit(self,t,attack_damage(mult),point,&"ordinary",{"phenomenon":"gojo_taijutsu"})
	JJK.knock(self,t,t.global_position - global_position,60.0 * (2.0 if mult > punch_multiplier else 1.0),500.0,0.0,{"phenomenon":"gojo_taijutsu"})

# ---------------------------------------------------------------- 术式
func cast_blue(at:Vector2,steer_with_mouse:bool = false) -> bool:
	if not can_act() or not technique_ready() or blue_cd > 0.0 or not spend(blue_cost): return false
	if blue_active: _end_blue()
	var offset:Vector2 = at - global_position
	blue_pos = global_position + offset.limit_length(320.0)
	blue_active = true
	blue_max = false
	blue_left = 0.8 if steer_with_mouse else 1.1
	blue_steer = steer_with_mouse
	blue_cd = blue_cooldown
	_blue_tick = 0.0
	sfx("gojo_blue",-6.0)
	return true

func begin_red_charge() -> bool:
	if not can_act() or not technique_ready() or red_cd > 0.0 or red_charge >= 0.0: return false
	red_charge = 0.0
	return true

func release_red(dir:Vector2,time:float) -> bool:
	if red_charge < 0.0: return false
	red_charge = -1.0
	var charged:bool = time >= 0.7
	var cost:float = red_cost * (2.3 if charged else 1.0)
	if not can_act() or not technique_ready() or not spend(cost): return false
	red_cd = red_cooldown
	var d:Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var speed:float = 720.0 if charged else 560.0
	launch("red_max" if charged else "red",global_position + d * 24.0,d * speed,16.0 if charged else 13.0,1.6)
	sfx("gojo_red",-4.0 if charged else -8.0)
	return true

func on_projectile_impact(kind:String,_target:ball,point:Vector2) -> void:
	if kind != "red" and kind != "red_max": return
	var charged:bool = kind == "red_max"
	var r:float = red_radius * (1.45 if charged else 1.0)
	var mult:float = red_charged_damage_multiplier if charged else red_damage_multiplier
	for t:ball in JJK.enemies_in_circle(self,point,r):
		JJK.hit(self,t,attack_damage(mult),t.global_position,&"magic",{"phenomenon":"gojo_red"})
		JJK.knock(self,t,t.global_position - point,red_knockback * (1.6 if charged else 1.0),900.0,0.25 if charged else 0.0,{"phenomenon":"gojo_red"})
	fx("red_burst",{"pos":point,"radius":r},0.35)

func begin_purple_charge() -> bool:
	if not can_act() or not technique_ready() or purple_cd > 0.0 or purple_charge >= 0.0 or purple_cast_left >= 0.0: return false
	if cursed_energy < purple_cost: return false
	purple_charge = 0.0
	return true

var _chant_step:int = 0
func _step_chant() -> void:
	var lines_zh:Array[String] = ["九纲","偏光","乌与声明","表里之间"]
	var lines_en:Array[String] = ["Nine Ropes","Polarized Light","Crow and Declaration","Between Front and Back"]
	var step:int = int(purple_charge / (purple_200_hold / 4.0))
	if step > _chant_step and step <= 4:
		_chant_step = step
		fx("text",{"pos":global_position + Vector2(0,-54 - step * 4),"text":(lines_en if JJK.english() else lines_zh)[step - 1],"size":18,"color":Color(0.8,0.6,1.0)},0.8)

func release_purple(dir:Vector2,time:float) -> bool:
	if purple_charge < 0.0: return false
	purple_charge = -1.0
	_chant_step = 0
	var full:bool = time >= purple_200_hold and cursed_energy >= purple_200_cost
	if not can_act() or not technique_ready() or not spend(purple_200_cost if full else purple_cost): return false
	_purple_pending_200 = full
	_purple_dir = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	purple_cast_left = 0.35 if full else 0.5
	purple_cd = purple_cooldown
	sfx("gojo_purple_200" if full else "gojo_purple",0.0)
	if full: cutin("虚式 茈","Hollow Technique: Purple","九纲 偏光 乌与声明 表里之间","Nine Ropes, Polarized Light, Crow and Declaration...",Color(0.6,0.3,1.0))
	return true

func _fire_purple() -> void:
	purple_cast_left = -1.0
	if health <= 0: return
	if is_player_controlled(): _purple_dir = player_control_aim_direction(_purple_dir)
	var full:bool = _purple_pending_200
	var width:float = purple_width * (2.0 if full else 1.0)
	var rect:Rect2 = JJK.map_rect(self)
	var length:float = rect.size.length() * 1.2
	var a:Vector2 = global_position + _purple_dir * 20.0
	var b:Vector2 = a + _purple_dir * length
	var mult:float = purple_200_damage_multiplier if full else purple_damage_multiplier
	for t:ball in JJK.enemies_on_segment(self,a,b,width * 0.5):
		JJK.hit(self,t,attack_damage(mult),t.global_position,&"magic",{"phenomenon":"gojo_purple","unadaptable":true,"ignore_block":true})
	# 茈抹消沿线的咒术弹。
	for unit:Node in get_tree().get_nodes_in_group("JJKUnit"):
		if unit == self or not JJK.U.enemy(self,unit): continue
		for child:Node in unit.get_children():
			if child is PROJECTILE and U2.segment_distance((child as Node2D).global_position,a,b) <= width * 0.5:
				child.call("_finish",null,(child as Node2D).global_position)
	fx("purple_beam",{"a":a,"b":b,"width":width,"world":true},0.9 if full else 0.6)
	sfx("gojo_purple_sfx",0.0)

func teleport_to(dest:Vector2) -> bool:
	if not can_act() or not technique_ready() or teleport_cd > 0.0 or not spend(25.0): return false
	var from:Vector2 = global_position
	var target:Vector2 = resolve_teleport(dest)
	teleport_cd = teleport_cooldown
	global_position = target
	fx("teleport",{"a":from,"b":target},0.3)
	sfx("gojo_teleport",-6.0)
	return true

## 瞬移落点：地图内、闭合结界里外不可穿越、不穿墙。
func resolve_teleport(dest:Vector2) -> Vector2:
	var from:Vector2 = global_position
	var offset:Vector2 = (dest - from).limit_length(teleport_distance)
	var target:Vector2 = JJK.clamp_to_map(self,from + offset,26.0)
	# 闭合结界：里外不可穿越。
	for d:Variant in DOMAIN.active_domains(get_tree()):
		if not bool(d.call("barrier_intact")): continue
		var inside_now:bool = d.center.distance_to(from) < d.radius
		var inside_then:bool = d.center.distance_to(target) < d.radius
		if inside_now and not inside_then: target = d.center + (target - d.center).limit_length(d.radius - 26.0)
		elif not inside_now and inside_then: target = d.center + (target - d.center).normalized() * (d.radius + 26.0)
	var wall:Dictionary = JJK.U.trace(self,from,target,false,false)
	if not wall.is_empty() and wall.get("position") is Vector2 and wall.get("collider") != null:
		var node:Node = wall.get("collider")
		if not bool(node.get_meta("jjk_domain_barrier",false)):
			target = (wall["position"] as Vector2) - (target - from).normalized() * 22.0
	return target

func cast_domain() -> bool:
	if not can_act() or not can_open_domain() or not spend(domain_cost): return false
	var rect:Rect2 = JJK.map_rect(self)
	var r:float = maxf(260.0,minf(rect.size.x,rect.size.y) * 0.45)
	open_domain("uv",global_position,r,domain_duration)
	sfx("gojo_domain",2.0)
	cutin("领域展开 无量空处","Domain Expansion: Unlimited Void","五条悟","Satoru Gojo",Color(0.3,0.55,1.0))
	return true

func cast_instant_domain() -> bool:
	if not can_act() or not technique_ready() or instant_cd > 0.0 or not spend(instant_domain_cost): return false
	instant_cd = instant_domain_cooldown
	var rect:Rect2 = JJK.map_rect(self)
	var r:float = maxf(220.0,minf(rect.size.x,rect.size.y) * 0.3)
	open_domain("uv_instant",global_position,r,0.25)
	sfx("gojo_teleport",0.0)
	fx("text",{"pos":global_position + Vector2(0,-70),"text":"0.2s Unlimited Void" if JJK.english() else "0.2秒 无量空处","size":24,"color":Color(0.75,0.9,1.0),"world":true},1.2)
	return true

func flip_barrier() -> bool:
	var d:Node = own_domain()
	if d == null or str(d.get("domain_kind")) != "uv" or cursed_energy < flip_cost: return false
	if not bool(d.call("flip")): return false
	cursed_energy -= flip_cost
	fx("text",{"pos":global_position + Vector2(0,-66),"text":"Barrier Flipped" if JJK.english() else "结界翻转","size":20,"color":Color(1.0,0.85,0.35)},1.0)
	return true

func on_domain_closed(kind:String,broken:bool) -> void:
	if kind == "uv" and broken:
		fx("text",{"pos":global_position + Vector2(0,-80),"text":"Barrier Shattered" if JJK.english() else "结界被斩破","size":22,"color":Color(1,0.4,0.4),"world":true},1.4)

# ---------------------------------------------------------------- 威胁/调试区域
func get_debug_attack_regions() -> Array:
	var regions:Array = []
	if blue_active: regions.append({"shape":"circle","position":blue_pos,"radius":blue_max_radius if blue_max else blue_radius,"damage":attack_damage(blue_damage_multiplier),"source":self,"kind":"gojo_blue"})
	if purple_cast_left >= 0.0:
		var width:float = purple_width * (2.0 if _purple_pending_200 else 1.0)
		regions.append({"shape":"segment","start":global_position,"end":global_position + _purple_dir * 3000.0,"radius":width * 0.5,"damage":attack_damage(purple_damage_multiplier),"source":self,"kind":"gojo_purple"})
	return regions
func get_ai_attack_threats(_receiver:Node = null) -> Array: return get_debug_attack_regions()
func get_debug_detection_regions() -> Array[Dictionary]: return []
func jjk_threats() -> Array: return get_debug_attack_regions()

# ---------------------------------------------------------------- AI（博弈）
func jjk_ai() -> void:
	var target:ball = ai_target()
	if not is_instance_valid(target): return
	var d:float = global_position.distance_to(target.global_position)
	if _ai_dodge(): return
	if not technique_ready():
		# 术式烧断：无下限失效，拉开距离等待大脑用反转术式修复。
		steer_keep_distance(target,420.0,60.0)
		return
	var tree:SceneTree = get_tree()
	var enemy_shrine:bool = false
	for dom:Variant in DOMAIN.active_domains(tree):
		if dom.domain_kind == "shrine" and JJK.U.enemy(self,dom.caster): enemy_shrine = true
	var mine:Node = own_domain()
	# 领域对拼：对方开伏魔御厨子，立刻以闭合结界对拼；结界吃紧就翻转。
	if enemy_shrine and mine == null and can_open_domain() and cursed_energy >= domain_cost:
		cast_domain()
		return
	if mine != null and float(mine.get("barrier_hp")) < 60.0 and float(mine.get("flip_left")) <= 0.0:
		flip_barrier()
	var target_domain_ready:bool = target.has_method("can_open_domain") and bool(target.call("can_open_domain")) and float(target.get("cursed_energy")) >= 300.0
	var rect:Rect2 = JJK.map_rect(self)
	var uv_r:float = maxf(260.0,minf(rect.size.x,rect.size.y) * 0.45)
	if mine == null and can_open_domain() and cursed_energy >= domain_cost and d < uv_r * 0.75:
		# 对方无法还手（烧断/次数用尽）时开领域必中；对方能对拼时只用 0.2 秒版骗招。
		if not target_domain_ready or not target.is_in_group("JJKUnit"):
			if not target.is_in_group("JJKUnit") and rng.randf() > 0.25: pass
			else:
				cast_domain()
				return
	if instant_cd <= 0.0 and d < 200.0 and target.is_in_group("JJKUnit") and target.get("casting") == true and cursed_energy >= instant_domain_cost:
		cast_instant_domain()
		return
	# 进攻。
	var stunned:bool = target.dizziness
	var mahoraga:ball = _ai_find_mahoraga()
	if purple_cd <= 0.0 and purple_cast_left < 0.0 and cursed_energy >= purple_cost:
		var aim_unit:ball = mahoraga if is_instance_valid(mahoraga) else target
		var reserve_ok:bool = cursed_energy - purple_cost >= domain_cost + 60.0 or not can_open_domain()
		if stunned or (reserve_ok and (is_instance_valid(mahoraga) or target.health < target.Max_health * 0.35 or rng.randf() < 0.04)):
			var full:bool = stunned and cursed_energy >= purple_200_cost
			_purple_dir = global_position.direction_to(lead(aim_unit,4000.0))
			purple_charge = 0.0
			release_purple(_purple_dir,purple_200_hold if full else 0.0)
			return
	if cursed_energy < 90.0:
		steer_keep_distance(target,260.0,60.0)
		return
	if blue_cd <= 0.0 and not blue_active and d > 90.0 and d < 360.0:
		cast_blue(target.global_position.lerp(global_position,0.35))
		_ai_blue_follow = 0.8
	if red_cd <= 0.0 and red_charge < 0.0 and U2.line_clear(self,global_position,target.global_position):
		red_charge = 0.0
		release_red(global_position.direction_to(lead(target,560.0)),0.8 if (blue_active and blue_pos.distance_to(target.global_position) < 100.0) else 0.0)
	# 走位：与宿傩/魔虚罗拉开距离，其余情况贴近用体术。
	var dangerous_melee:bool = target.is_in_group("JJKUnit") and target.has_method("jjk_neutralizes_infinity") and bool(target.call("jjk_neutralizes_infinity",self))
	if dangerous_melee: steer_keep_distance(target,240.0,50.0)
	elif target.is_in_group("JJKUnit"): steer_keep_distance(target,180.0,60.0)
	else: steer(global_position.direction_to(target.global_position))
	if dangerous_melee and d < 70.0 and teleport_cd <= 0.0:
		teleport_to(global_position - global_position.direction_to(target.global_position) * teleport_distance)

func _ai_find_mahoraga() -> ball:
	for unit:Node in get_tree().get_nodes_in_group("JJKMahoraga"):
		if unit is ball and (unit as ball).health > 0 and JJK.U.enemy(self,unit) and global_position.distance_to((unit as ball).global_position) < 700.0: return unit
	return null

## 世界斩/开/领域展延拳：锁定后才瞬移——太早瞬移会被重新瞄准。
func _ai_dodge() -> bool:
	var can_tp:bool = teleport_cd <= 0.0 and technique_ready() and cursed_energy >= 25.0
	for unit:Node in get_tree().get_nodes_in_group("JJKUnit"):
		if unit == self or not JJK.U.enemy(self,unit) or not unit.has_method("jjk_threats"): continue
		for th:Variant in unit.call("jjk_threats"):
			if not th is Dictionary or not bool(th.get("locked",false)): continue
			if str(th.get("shape")) == "segment":
				var a:Vector2 = th["start"]
				var b:Vector2 = th["end"]
				if U2.segment_distance(global_position,a,b) <= float(th.get("radius",20.0)) + 30.0:
					var n:Vector2 = (b - a).orthogonal().normalized()
					if n.dot(global_position - a) < 0.0: n = -n
					if can_tp:
						# 选择真正能离开斩线最远的一侧（角落里往外侧瞬移会被地图边缘卡住）。
						var best:Vector2 = global_position
						var best_gap:float = U2.segment_distance(global_position,a,b)
						for cand:Vector2 in [n,-n,(n + (b - a).normalized()).normalized(),(n - (b - a).normalized()).normalized(),(-n + (b - a).normalized()).normalized(),(-n - (b - a).normalized()).normalized()]:
							var p2:Vector2 = resolve_teleport(global_position + cand * teleport_distance)
							var gap:float = U2.segment_distance(p2,a,b)
							if gap > best_gap:
								best_gap = gap
								best = p2
						if best != global_position and teleport_to(best): return true
					steer(n)
					return true
			elif str(th.get("shape")) == "circle":
				var p:Vector2 = th["position"]
				if p.distance_to(global_position) <= float(th.get("radius",60.0)) + 30.0:
					if can_tp and teleport_to(global_position + (global_position - p).normalized() * teleport_distance): return true
					steer(global_position - p)
					return true
	return false

# ---------------------------------------------------------------- 视觉
func visual_state() -> Dictionary:
	var data:Dictionary = super.visual_state()
	data["ba"] = blue_active
	data["bp"] = blue_pos
	data["bm"] = blue_max
	data["rc"] = red_charge
	data["pc"] = purple_charge if purple_charge >= 0.0 else (0.01 if purple_cast_left >= 0.0 else -1.0)
	data["p2"] = _purple_pending_200
	return data

func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	blue_active = bool(data.get("ba",false))
	blue_pos = data.get("bp",blue_pos)
	blue_max = bool(data.get("bm",false))
	red_charge = float(data.get("rc",-1.0))
	purple_charge = float(data.get("pc",-1.0))
	_purple_pending_200 = bool(data.get("p2",false))

func _red_charge_pos() -> Vector2:
	return global_position + (aim_dir(direction) if is_multiplayer_authority() else direction.normalized()) * 26.0

func _purple_center() -> Vector2:
	return global_position + Vector2(0,-34)

var _blue_lens:Node2D

func _blue_lens_follow(d:Node2D) -> bool:
	if not blue_active or health <= 0 or not is_inside_tree(): return false
	var r:float = blue_max_radius if blue_max else blue_radius
	d.global_position = blue_pos
	d.set("size",Vector2.ONE * r * 2.4)
	return true

func visual_particles(_dt:float) -> void:
	if blue_active and not is_instance_valid(_blue_lens):
		# 苍：真实的屏幕空间漩涡折射，跟随苍的位置，苍结束后自动消失。
		_blue_lens = V.distort(self,1,blue_pos,Vector2.ONE * blue_radius * 2.4,1.0,1.2,{"persistent":true,"follow":_blue_lens_follow,"aberration":1.5,"z_index":85})
	if blue_active:
		var r:float = blue_max_radius if blue_max else blue_radius
		for i:int in (3 if blue_max else 2):
			var a:float = _vrng.randf() * TAU
			var from:Vector2 = blue_pos + Vector2.from_angle(a) * r * _vrng.randf_range(0.7,1.05)
			var vel:Vector2 = (blue_pos - from) * 1.6 + (blue_pos - from).orthogonal() * 1.2
			vparts.emit(from,vel,0.6,_vrng.randf_range(1.5,3.0),Color(0.45,0.7,1.0),2,0.0)
	if red_charge >= 0.0:
		var p:Vector2 = _red_charge_pos()
		var a2:float = _vrng.randf() * TAU
		var from2:Vector2 = p + Vector2.from_angle(a2) * _vrng.randf_range(26,44)
		vparts.emit(from2,(p - from2) * 3.2,0.3,2.0,Color(1.0,0.35,0.25),2,0.0)
	if purple_charge >= 0.0:
		var c:Vector2 = _purple_center()
		var a3:float = _vrng.randf() * TAU
		var from3:Vector2 = c + Vector2.from_angle(a3) * _vrng.randf_range(30,60)
		vparts.emit(from3,(c - from3) * 2.5,0.4,2.0,Color(0.75,0.5,1.0),2,0.0)

## 着色器面片：苍 = 向内吸的蓝色漩涡球 + 引力透镜环；赫蓄力 = 逐渐膨胀的红球；茈蓄力 = 公转的苍与赫合为紫球。
func visual_quads() -> void:
	var t:float = _view_clock
	if blue_active:
		var r:float = blue_max_radius if blue_max else blue_radius
		var s:float = 1.25 if blue_max else 1.0
		ovq("blue",V.Q.ORB,2,blue_pos,Vector2.ONE * 40.0 * s,0.0,V.pal("blue",{"alpha":1.3,"p0":Vector4(0.42,-2.6,0.45,1.0),"p1":Vector4(-6.0,0.16,1.0,0.9),"p2":Vector4(0.0,2.6,0,0)}))
		ovq("blens",V.Q.RING,0,blue_pos,Vector2.ONE * r * 2.1,0.0,V.pal("blue",{"alpha":0.5,"p0":Vector4(0.9 + 0.03 * sin(t * 5.0),0.05,0.35,0.0),"p1":Vector4(0.0,0.0,0.6,0.0)}))
	if red_charge >= 0.0:
		var k:float = clampf(red_charge / 0.7,0.0,1.0)
		var pulse:float = 0.92 + 0.08 * sin(t * (18.0 + 20.0 * k))
		ovq("redc",V.Q.ORB,2,_red_charge_pos(),Vector2.ONE * (30.0 + 46.0 * k) * pulse,0.0,V.pal("red",{"alpha":1.3,"p0":Vector4(0.4,1.8,0.4 + 0.5 * k,1.0),"p1":Vector4(8.0,0.2,1.0,0.9),"p2":Vector4(0.0,2.6,0,0)}))
	if purple_charge >= 0.0:
		var k2:float = clampf(purple_charge / purple_200_hold,0.0,1.0)
		var c:Vector2 = _purple_center()
		var orbit:float = 22.0 * (1.0 - V.in_out(k2))
		var ang2:float = t * (4.0 + 14.0 * k2)
		var sep:float = 1.0 - V.seg(k2,0.75,1.0)
		ovq("pb",V.Q.ORB,2,c + Vector2.from_angle(ang2) * orbit,Vector2.ONE * 34.0,0.0,V.pal("blue",{"alpha":1.3 * sep,"p0":Vector4(0.42,-2.2,0.4,1.0),"p1":Vector4(-7.0,0.16,0.9,0.9)}))
		ovq("pr",V.Q.ORB,2,c - Vector2.from_angle(ang2) * orbit,Vector2.ONE * 34.0,0.0,V.pal("red",{"alpha":1.3 * sep,"p0":Vector4(0.42,2.2,0.4,1.0),"p1":Vector4(7.0,0.16,0.9,0.9)}))
		var m:float = V.seg(k2,0.45,1.0)
		if m > 0.0:
			ovq("pp",V.Q.ORB,1,c,Vector2.ONE * (24.0 + 70.0 * m) * (1.0 + 0.05 * sin(t * 25.0)),0.0,V.pal("purple",{"alpha":1.3 * m,"p0":Vector4(0.44,1.2,0.5 * m,1.0),"p1":Vector4(5.0,0.14,1.0,0.92),"p2":Vector4(0.0,2.2,0,0)}))

func draw_under(o:Node2D) -> void:
	if blue_active:
		# 苍：空间被吸向中心的黑洞感（角色之下先压暗中心）。
		var r:float = blue_max_radius if blue_max else blue_radius
		V.ring(o,blue_pos,0.0,r * 0.5,Color(0.0,0.02,0.1,0.45),Color(0.0,0.02,0.1,0.0),40)

## 无下限与苍的持续视觉都在角色之下：被吸过来的敌人始终看得见。
func draw_under_add(o:Node2D) -> void:
	var t:float = _view_clock
	if infinity_active():
		# 无下限：极淡的蓝色空间折射，偶尔闪过一圈。
		var sh:float = 0.5 + 0.5 * sin(t * 3.0)
		V.ring(o,global_position,11.0,16.0,Color(0.5,0.85,1.0,0.0),Color(0.5,0.85,1.0,0.12 + 0.08 * sh),40)
		V.sprite(o,"k_circle05",global_position,34.0,Color(0.55,0.9,1.0,0.18 + 0.1 * sh),t * 0.5)
		for i:int in 3:
			var a:float = t * (1.2 + 0.4 * i) + i * 2.1
			o.draw_arc(global_position,15.0 + i,a,a + 0.5,10,Color(0.7,0.95,1.0,0.35),1.0,true)
	if blue_active:
		var r:float = blue_max_radius if blue_max else blue_radius
		var s:float = 1.25 if blue_max else 1.0
		V.glow(o,blue_pos,r * 0.9,Color(0.15,0.3,1.0,0.35))
		V.sprite(o,"k_light03",blue_pos,r * 2.0,Color(0.2,0.4,1.0,0.4),t * 0.4)
		# 螺旋吸入臂
		for arm:int in 4:
			var pts:PackedVector2Array = []
			for j:int in 18:
				var u:float = float(j) / 17.0
				var ang:float = -t * 4.0 + arm * TAU / 4.0 + u * 3.2
				pts.append(blue_pos + Vector2.from_angle(ang) * r * (0.12 + 0.8 * u))
			o.draw_polyline(pts,Color(0.4,0.65,1.0,0.5),2.0 * s,true)
		# 核心
		V.glow(o,blue_pos,34.0 * s,Color(0.25,0.5,1.0,0.6))
		o.draw_arc(blue_pos,18.0 * s,-t * 9.0,-t * 9.0 + 4.0,20,Color(0.7,0.9,1.0,0.8),1.5,true)

func draw_overlay_add(o:Node2D) -> void:
	var t:float = _view_clock
	if red_charge >= 0.0:
		var k:float = clampf(red_charge / 0.7,0.0,1.0)
		var p:Vector2 = _red_charge_pos()
		var pulse:float = 0.85 + 0.15 * sin(t * (18.0 + 20.0 * k))
		V.glow(o,p,(26.0 + 30.0 * k) * pulse,Color(1.0,0.12,0.06,0.8))
		V.sprite(o,"k_flare01",p,(60.0 + 120.0 * k),Color(1.0,0.35,0.25,0.5 + 0.4 * k),0.0,Vector2(1.0,0.25))
		V.anim(o,"a_pfx_fireburst",p,40.0 + 30.0 * k,t * 1.5,Color(1,0.6,0.5,0.6 * k),0.0,true)
		for i2:int in 6:
			var a2:float = t * 10.0 + TAU * i2 / 6.0
			var l:float = (12.0 + 12.0 * k) * (0.8 + 0.2 * sin(t * 30.0 + i2))
			o.draw_line(p + Vector2.from_angle(a2) * 6.0,p + Vector2.from_angle(a2) * l,Color(1.0,0.5,0.35,0.7 * k),1.5,true)
		if k >= 1.0: V.shock(o,p,22.0 + 6.0 * sin(t * 20.0),6.0,Color(1.0,0.5,0.4,0.8))
	if purple_charge >= 0.0:
		var k2:float = clampf(purple_charge / purple_200_hold,0.0,1.0)
		var c:Vector2 = _purple_center()
		# 苍与赫环绕公转，逐渐靠近、加速，最后合为茈。
		var orbit:float = 22.0 * (1.0 - V.in_out(k2))
		var ang2:float = t * (4.0 + 14.0 * k2)
		var pb:Vector2 = c + Vector2.from_angle(ang2) * orbit
		var pr:Vector2 = c - Vector2.from_angle(ang2) * orbit
		for tr:int in 5:
			var back:float = ang2 - tr * 0.18
			var fa:float = 0.4 * (1.0 - tr / 5.0)
			V.core(o,c + Vector2.from_angle(back) * orbit,6.0,Color(0.25,0.45,1.0,fa))
			V.core(o,c - Vector2.from_angle(back) * orbit,6.0,Color(1.0,0.2,0.12,fa))
		V.glow(o,pb,22.0,Color(0.2,0.4,1.0,0.9))
		V.glow(o,pr,22.0,Color(1.0,0.15,0.08,0.9))
		V.glow(o,c,40.0 + 50.0 * k2,Color(0.6,0.25,1.0,0.25 + 0.5 * k2))
		V.sprite(o,"k_magic03",c,(70.0 + 40.0 * k2),Color(0.75,0.5,1.0,0.3 + 0.5 * k2),t * (1.0 + 3.0 * k2))
		if k2 > 0.5: V.anim(o,"a_pfx_purple",c,60.0 + 60.0 * k2,t * 1.2,Color(1,1,1,V.seg(k2,0.5,1.0)),0.0,true)
		if k2 >= 1.0: V.sprite(o,"k_flare01",c,220.0,Color(0.85,0.6,1.0,0.7 + 0.3 * sin(t * 20.0)),0.0,Vector2(1.0,0.2))
		if k2 > 0.7:
			var m:float = V.seg(k2,0.7,1.0)
			_vrng.seed = int(t * 25.0) + 91
			for b:int in 3:
				var ba:float = _vrng.randf() * TAU
				var pts2:PackedVector2Array = V.bolt(_vrng,c,c + Vector2.from_angle(ba) * _vrng.randf_range(24,46),8.0,3)
				V.draw_bolt(o,pts2,1.0,Color(0.75,0.45,1.0,0.8 * m),Color(1,0.9,1,m))
		# 咏唱法环：随蓄力逐步点亮
		var ring_r:float = 34.0
		o.draw_arc(c,ring_r,-PI / 2.0,-PI / 2.0 + TAU * k2,48,Color(0.8,0.6,1.0,0.8),2.0,true)
		for g:int in 8:
			if float(g) / 8.0 <= k2:
				V.sparkle(o,c + Vector2.from_angle(-PI / 2.0 + TAU * g / 8.0) * ring_r,4.5,Color(0.9,0.75,1.0,0.9),t * 2.0)

func get_armor_test_effect_summary() -> String:
	if JJK.english():
		return "Infinity blocks every non-sure-hit contact (damage, knockback, statuses, projectiles) at a cursed-energy cost; only domain sure-hits, World Slash, Domain Amplification and an Infinity-adapted Mahoraga pass. Six Eyes regenerate cursed energy fast; Reverse Cursed Technique heals; close enemies eat taijutsu with Black Flash chances.\nLeft Blue pull point (hold to steer, 0.8s = Max Blue). Right Red (hold 0.7s to charge). Middle Hollow Purple (hold 2.4s for the 200% chant). 1 teleport, 2 Unlimited Void: a huge closed circular barrier nobody can leave, sure-hit paralysis, 3 0.2s Unlimited Void, 4 flip the barrier during a domain clash."
	return "无下限：阻挡一切非必中接触（伤害/击退/负面状态/术式弹），每次消耗咒力；只有领域必中、世界斩、领域展延和适应了无下限的魔虚罗能穿透。六眼回咒力极快，反转术式自愈，贴身自动体术并可能打出黑闪。\n左键 苍（按住牵引点跟随鼠标，0.8秒成最大出力）；右键 赫（按住0.7秒蓄力）；中键 虚式 茈（按满2.4秒为200%咏唱茈）。1 瞬移；2 无量空处：巨大闭合圆形结界，里外都出不去，圈内必中信息过载定身；3 0.2秒无量空处；4 领域对拼时翻转结界抵挡外部斩击。"
