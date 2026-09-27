extends "res://scripts/characters/动漫/咒术回战/jjk_base.gd"
## 八握剑异戒神将 魔虚罗（咒术回战）。独立角色，可单独上场、可被 C 键操控，也可由宿傩召唤。
## 被动：适应。受到某种“现象”（任何角色的任何攻击/击退/状态/领域）后，头顶法阵转动 3 秒完成一次适应：
##   第1级 该现象伤害-50%，第2级 完全免疫；每转一次回复 8% 最大生命。嵌合暗兽在旁时转得更快。
##   适应无下限后攻击可以穿透无下限；适应无量空处后不再被定身，挥剑可直接斩破无量空处结界。
##   茈（虚式）无法适应，并且对其造成 1.5 倍伤害。
## 左键 退魔之剑  右键 突进斩  中键 咆哮（震慑周围）
const U2 = preload("res://scripts/characters/我的世界/new5/utils.gd")

@export_category("魔虚罗")
@export var wheel_turn_seconds:float = 3.0
@export var wheel_heal_ratio:float = 0.08
@export var sword_cooldown:float = 1.0
@export var sword_range:float = 95.0
@export var sword_damage_multiplier:float = 2.5
@export var lunge_cooldown:float = 4.0
@export var lunge_distance:float = 230.0
@export var lunge_damage_multiplier:float = 2.0
@export var roar_cooldown:float = 10.0
@export var roar_radius:float = 140.0
@export var barrier_damage_per_swing:float = 35.0

var summoner:Node = null
var adaptation:Dictionary = {}     # key -> level (1..2)
var pending:Dictionary = {}        # key -> exposure weight
var wheel_key:String = ""
var wheel_progress:float = 0.0
var wheel_turns:int = 0
var sword_cd:float = 0.0
var lunge_cd:float = 0.0
var roar_cd:float = 0.0
var _swing_visual:float = 0.0
var _swing_dir:Vector2 = Vector2.RIGHT
var _adapt_text_cd:float = 0.0

func _ready() -> void:
	intro_sound = "mahoraga_summon"
	cursed_energy_max = 600.0
	cursed_energy_regen = 20.0
	rct_heal_ratio_per_second = 0.0
	black_flash_chance = 0.0
	super._ready()
	add_to_group("JJKMahoraga")

# ---------------------------------------------------------------- 输入
func controlled_attack_action() -> void:
	if is_player_controlled(): swing(player_control_aim_direction(direction))
func controlled_skill_action() -> void:
	if is_player_controlled(): lunge(player_control_aim_direction(direction))
func controlled_middle_action() -> void:
	if is_player_controlled(): roar()

# ---------------------------------------------------------------- 适应
func adaptation_level(key:String) -> int:
	return int(adaptation.get(key,0))

func _key_for(source:Variant,kind:String) -> String:
	var ctx:Dictionary = JJK.ctx_of(self)
	if ctx.has("phenomenon"): return str(ctx["phenomenon"])
	if is_instance_valid(source) and source is Node:
		var script:Script = (source as Node).get_script()
		var base:String = script.resource_path.get_file().get_basename() if script != null else str((source as Node).name)
		return "%s:%s" % [base,kind]
	return "unknown:%s" % kind

func _unadaptable() -> bool:
	return bool(JJK.ctx_of(self).get("unadaptable",false))

func expose(key:String,weight:float = 1.0) -> void:
	if key.is_empty() or adaptation_level(key) >= 2: return
	pending[key] = float(pending.get(key,0.0)) + weight
	if wheel_key.is_empty(): _start_next_turn()

func _start_next_turn() -> void:
	wheel_key = ""
	wheel_progress = 0.0
	var best:float = 0.0
	for key:Variant in pending.keys():
		if adaptation_level(str(key)) >= 2: continue
		if float(pending[key]) > best:
			best = float(pending[key])
			wheel_key = str(key)
	if not wheel_key.is_empty(): pending.erase(wheel_key)

func wheel_speed() -> float:
	var speed:float = 1.0
	for unit:Node in get_tree().get_nodes_in_group("JJKAgito"):
		if unit is ball and (unit as ball).health > 0 and not JJK.U.enemy(self,unit) and (unit as ball).global_position.distance_to(global_position) < 320.0:
			speed = maxf(speed,float(unit.call("wheel_boost")) if unit.has_method("wheel_boost") else 1.6)
	return speed

func _complete_turn() -> void:
	var key:String = wheel_key
	adaptation[key] = mini(2,adaptation_level(key) + 1)
	wheel_turns += 1
	heal(float(Max_health) * wheel_heal_ratio)
	cleanse_negative_effects()
	sfx("mahoraga_wheel",-2.0)
	fx("wheel_turn",{"pos":global_position + Vector2(0,-44),"radius":22.0},0.6)
	fx("text",{"pos":global_position + Vector2(0,-72),"text":_adapt_label(key,int(adaptation[key])),"size":16,"color":Color(1,0.9,0.5)},1.3)
	_start_next_turn()

func _adapt_label(key:String,level:int) -> String:
	var names_zh:Dictionary = {"gojo_infinity":"无下限","gojo_uv":"无量空处","gojo_blue":"苍","gojo_red":"赫","gojo_taijutsu":"体术","sukuna_dismantle":"解","sukuna_cleave":"捌","sukuna_fuga":"开","sukuna_shrine":"伏魔御厨子","sukuna_taijutsu":"体术"}
	var names_en:Dictionary = {"gojo_infinity":"Infinity","gojo_uv":"Unlimited Void","gojo_blue":"Blue","gojo_red":"Red","gojo_taijutsu":"Taijutsu","sukuna_dismantle":"Dismantle","sukuna_cleave":"Cleave","sukuna_fuga":"Fuga","sukuna_shrine":"Malevolent Shrine","sukuna_taijutsu":"Taijutsu"}
	var n:String = str((names_en if JJK.english() else names_zh).get(key,key.get_slice(":",0)))
	if JJK.english(): return "Adapted: %s %s" % [n,"(immune)" if level >= 2 else "(-50%)"]
	return "适应：%s%s" % [n,"（免疫）" if level >= 2 else "（-50%）"]

func _scaled(damage:float,source:Variant,kind:String) -> float:
	if _unadaptable():
		return damage * (1.5 if str(JJK.ctx_of(self).get("phenomenon","")) == "gojo_purple" else 1.0)
	var key:String = _key_for(source,kind)
	var level:int = adaptation_level(key)
	expose(key,damage)
	if level >= 2:
		if _adapt_text_cd <= 0.0:
			_adapt_text_cd = 0.6
			fx("ripple",{"pos":global_position,"radius":24.0,"color":Color(1,0.9,0.5)},0.3)
		return 0.0
	return damage * (0.5 if level == 1 else 1.0)

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if damage > 0.0 and is_multiplayer_authority():
		damage = _scaled(damage,source,"hit")
		if damage <= 0.0: return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)

func _receive_spatial_damage_untyped(damage:float,damage_space:Variant,ignore_block:bool,raw_health:bool) -> bool:
	if raw_health and damage > 0.0 and is_multiplayer_authority():
		var source:Variant = (damage_space as Dictionary).get("source") if damage_space is Dictionary else null
		damage = _scaled(damage,source,"raw")
		if damage <= 0.0: return false
	return super._receive_spatial_damage_untyped(damage,damage_space,ignore_block,raw_health)

func receive_internal_status_damage(damage:float,kind:StringName,source:Node = null) -> float:
	if damage > 0.0 and is_multiplayer_authority():
		damage = _scaled(damage,source,"status_" + str(kind))
		if damage <= 0.0: return 0.0
	return super.receive_internal_status_damage(damage,kind,source)

func apply_knockback(knockback_direction:Vector2,knockback_distance:float,knockback_speed:float = 700.0,wall_bounce_strength:float = 0.0,stun_duration:float = 0.0,options:Dictionary = {}) -> Node:
	var source:Variant = options.get("source",null)
	if source != self and is_multiplayer_authority() and not _unadaptable():
		var key:String = _key_for(source,"control")
		expose(key,20.0)
		if adaptation_level(key) >= 2: return null
	return super.apply_knockback(knockback_direction,knockback_distance,knockback_speed,wall_bounce_strength,stun_duration,options)

func jjk_uv_resistance() -> float:
	return clampf(adaptation_level("gojo_uv") * 0.5,0.0,1.0)

func on_jjk_uv_exposure(seconds:float) -> void:
	expose("gojo_uv",seconds * 40.0 + 1.0)

func on_jjk_blocked_by_infinity(_gojo:Node) -> void:
	expose("gojo_infinity",30.0)

func is_knockback_displacement_immune() -> bool:
	return adaptation_level("gojo_blue") >= 2

func jjk_neutralizes_infinity(_target:Node) -> bool:
	return adaptation_level("gojo_infinity") >= 2

# ---------------------------------------------------------------- 每帧
func jjk_step(delta:float) -> void:
	sword_cd = maxf(0.0,sword_cd - delta)
	lunge_cd = maxf(0.0,lunge_cd - delta)
	roar_cd = maxf(0.0,roar_cd - delta)
	_adapt_text_cd = maxf(0.0,_adapt_text_cd - delta)
	_swing_visual = maxf(0.0,_swing_visual - delta)
	if not wheel_key.is_empty():
		wheel_progress += delta * wheel_speed() / maxf(wheel_turn_seconds,0.1)
		if wheel_progress >= 1.0: _complete_turn()

# ---------------------------------------------------------------- 攻击
func swing(dir:Vector2) -> bool:
	if not can_act() or sword_cd > 0.0: return false
	sword_cd = sword_cooldown
	var d:Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	_swing_dir = d
	_swing_visual = 0.25
	var hit_any:bool = false
	for t:ball in JJK.enemies_in_circle(self,global_position,sword_range + 20.0):
		var to:Vector2 = t.global_position - global_position
		if to.length() > 12.0 and to.normalized().dot(d) < 0.2: continue
		hit_any = JJK.hit(self,t,attack_damage(sword_damage_multiplier),t.global_position,&"ordinary",{"phenomenon":"mahoraga_sword"}) or hit_any
		JJK.knock(self,t,to,90.0,700.0,0.0,{"phenomenon":"mahoraga_sword"})
	_cut_barrier(global_position + d * sword_range)
	fx("slash",{"a":global_position + d.rotated(-1.0) * sword_range,"b":global_position + d.rotated(1.0) * sword_range,"color":Color(1.0,0.95,0.7),"width":5.0,"world":true},0.25)
	return hit_any

func _cut_barrier(point:Vector2) -> void:
	if adaptation_level("gojo_uv") < 2: return
	for d:Variant in DOMAIN.active_domains(get_tree()):
		if not bool(d.call("barrier_intact")) or not JJK.U.enemy(self,d.caster): continue
		if absf(d.center.distance_to(global_position) - d.radius) <= sword_range + 30.0 or d.center.distance_to(point) >= d.radius - 10.0:
			d.call("damage_barrier",barrier_damage_per_swing)

func lunge(dir:Vector2) -> bool:
	if not can_act() or lunge_cd > 0.0: return false
	lunge_cd = lunge_cooldown
	var d:Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var from:Vector2 = global_position
	var to:Vector2 = JJK.clamp_to_map(self,from + d * lunge_distance,26.0)
	var wall:Dictionary = JJK.U.trace(self,from,to)
	if not wall.is_empty() and wall.get("position") is Vector2: to = (wall["position"] as Vector2) - d * 22.0
	for t:ball in JJK.enemies_on_segment(self,from,to,30.0):
		JJK.hit(self,t,attack_damage(lunge_damage_multiplier),t.global_position,&"ordinary",{"phenomenon":"mahoraga_sword"})
		JJK.knock(self,t,d,120.0,800.0,0.2,{"phenomenon":"mahoraga_sword"})
	global_position = to
	fx("slash",{"a":from,"b":to,"color":Color(1,0.95,0.7),"width":8.0,"world":true},0.3)
	_cut_barrier(to)
	return true

func roar() -> bool:
	if not can_act() or roar_cd > 0.0: return false
	roar_cd = roar_cooldown
	for t:ball in JJK.enemies_in_circle(self,global_position,roar_radius):
		JJK.stun(self,t,0.8,{"phenomenon":"mahoraga_roar"})
		JJK.knock(self,t,t.global_position - global_position,90.0,600.0,0.0,{"phenomenon":"mahoraga_roar"})
	sfx("mahoraga_roar",0.0)
	fx("shockwave",{"pos":global_position,"radius":roar_radius,"color":Color(0.95,0.95,0.85)},0.4)
	return true

# ---------------------------------------------------------------- AI
func jjk_ai() -> void:
	var target:ball = ai_target()
	if not is_instance_valid(target): return
	var d:float = global_position.distance_to(target.global_position)
	var to:Vector2 = global_position.direction_to(target.global_position)
	# 适应无量空处后，身处敌方结界时优先斩结界。
	if adaptation_level("gojo_uv") >= 2 and sword_cd <= 0.0:
		for dom:Variant in DOMAIN.active_domains(get_tree()):
			if bool(dom.call("barrier_intact")) and JJK.U.enemy(self,dom.caster) and dom.center.distance_to(global_position) < dom.radius:
				var out:Vector2 = (global_position - dom.center).normalized()
				steer(out)
				if dom.radius - dom.center.distance_to(global_position) < sword_range: swing(out)
				return
	if d < sword_range + U2.radius(target): swing(to)
	elif d < lunge_distance and lunge_cd <= 0.0: lunge(to)
	if roar_cd <= 0.0 and JJK.enemies_in_circle(self,global_position,roar_radius).size() >= 2: roar()
	steer(to)

# ---------------------------------------------------------------- 视觉
func visual_state() -> Dictionary:
	var data:Dictionary = super.visual_state()
	data["wk"] = wheel_key
	data["wp"] = wheel_progress
	data["wt"] = wheel_turns
	data["sv"] = _swing_visual
	data["sd"] = _swing_dir
	return data

func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	wheel_key = str(data.get("wk",""))
	wheel_progress = float(data.get("wp",0.0))
	wheel_turns = int(data.get("wt",0))
	_swing_visual = float(data.get("sv",0.0))
	_swing_dir = data.get("sd",_swing_dir)

func draw_overlay(o:Node2D) -> void:
	# 头顶八握法阵：每完成一次适应转 1/8 圈；转动中逐渐旋转。
	var c:Vector2 = global_position + Vector2(0,-44)
	var angle:float = (wheel_turns + (wheel_progress if not wheel_key.is_empty() else 0.0)) * TAU / 8.0
	var gold:Color = Color(0.95,0.78,0.3,0.95)
	var dark:Color = Color(0.35,0.25,0.05,0.9)
	o.draw_arc(c,15.0,0.0,TAU,32,dark,4.0,true)
	o.draw_arc(c,15.0,0.0,TAU,32,gold,2.0,true)
	o.draw_arc(c,6.0,0.0,TAU,16,gold,1.5,true)
	for i:int in 8:
		var a:float = angle + TAU * i / 8.0
		var dir:Vector2 = Vector2.from_angle(a)
		o.draw_line(c + dir * 6.0,c + dir * 21.0,dark,4.0,true)
		o.draw_line(c + dir * 6.0,c + dir * 21.0,gold,2.0,true)
		var knob:PackedVector2Array = [c + dir * 25.0,c + dir * 21.0 + dir.orthogonal() * 3.0,c + dir * 18.5,c + dir * 21.0 - dir.orthogonal() * 3.0]
		o.draw_colored_polygon(knob,gold)

func _swing_arc(o:Node2D,r:float,w:float,col:Color) -> void:
	if w < 1.5: return
	var a0:float = _swing_dir.angle() - 1.0
	var a1:float = _swing_dir.angle() + 1.0
	var outer:PackedVector2Array = []
	var inner:PackedVector2Array = []
	for i:int in 21:
		var u:float = float(i) / 20.0
		var a:float = lerpf(a0,a1,u)
		var th:float = w * sin(PI * u) * (0.4 + 0.6 * u)
		outer.append(global_position + Vector2.from_angle(a) * (r + th * 0.5))
		inner.append(global_position + Vector2.from_angle(a) * (r - th * 0.5))
	inner.reverse()
	var poly:PackedVector2Array = outer + inner.slice(1,inner.size() - 1)
	o.draw_colored_polygon(poly,col)

func draw_overlay_add(o:Node2D) -> void:
	var t:float = _view_clock
	var c:Vector2 = global_position + Vector2(0,-44)
	var turning:bool = not wheel_key.is_empty()
	V.glow(o,c,(34.0 if turning else 24.0) * (1.0 + 0.08 * sin(t * 6.0)),Color(1.0,0.8,0.35,0.55 if turning else 0.3))
	if turning:
		o.draw_arc(c,28.0,-PI / 2.0,-PI / 2.0 + TAU * wheel_progress,32,Color(1,0.95,0.6,0.95),2.5,true)
		var tip:Vector2 = c + Vector2.from_angle(-PI / 2.0 + TAU * wheel_progress) * 28.0
		V.glow(o,tip,10.0,Color(1,0.95,0.7,1))
		for i:int in 8:
			var a:float = t * 0.8 + TAU * i / 8.0
			V.streak(o,c,c + Vector2.from_angle(a) * 40.0,4.0,Color(1.0,0.85,0.45,0.3))
	if _swing_visual > 0.0:
		var k:float = clampf(_swing_visual / 0.25,0.0,1.0)
		_swing_arc(o,sword_range * 0.9,26.0 * k,Color(1.0,0.9,0.6,0.45 * k))
		_swing_arc(o,sword_range * 0.9,9.0 * k,Color(1,1,1,0.95 * k))

func get_armor_test_effect_summary() -> String:
	if JJK.english():
		return "Adaptation: after taking any phenomenon (any attack, knockback, status or domain from anyone) the wheel turns for 3s: level 1 halves it, level 2 makes him immune, each turn heals 8% max HP and cleanses. Adapting to Infinity lets his sword pierce it; adapting to Unlimited Void stops the paralysis and lets his sword cut the barrier open. Hollow Purple can't be adapted to and deals 1.5x. Agito nearby speeds up the wheel.\nLeft Sword of Extermination, Right lunge slash, Middle roar."
	return "适应：受到任何现象（任何角色的攻击、击退、状态、领域）后法阵转动3秒：第1级减伤50%，第2级完全免疫；每转一次回复8%最大生命并净化。适应无下限后剑能穿透无下限；适应无量空处后不再被定身，挥剑直接斩破结界。茈无法适应且造成1.5倍伤害。嵌合暗兽在旁时法阵转得更快。\n左键 退魔之剑；右键 突进斩；中键 咆哮。"
