extends "res://scripts/characters/动漫/咒术回战/jjk_base.gd"
## 嵌合暗兽 阿吉托（咒术回战）。由鵺、大蛇、虎葬、圆鹿融合而成的十影式神；宿傩赋予其反转术式。
## 被动：反转术式光环（周围友军持续回血），并使友方魔虚罗的适应法阵转得更快。
## 左键 撕咬  右键 鵺 落雷（定身）  中键 圆鹿 反转（群体大治疗+净化，并抵消范围内敌方的苍）
const U2 = preload("res://scripts/characters/我的世界/new5/utils.gd")

@export_category("嵌合暗兽")
@export var aura_radius:float = 230.0
@export var aura_heal_ratio_per_second:float = 0.015
@export var wheel_boost_value:float = 1.6
@export var bite_cooldown:float = 0.8
@export var bite_damage_multiplier:float = 1.3
@export var thunder_cooldown:float = 3.5
@export var thunder_radius:float = 70.0
@export var thunder_delay:float = 0.35
@export var thunder_damage_multiplier:float = 1.8
@export var deer_cooldown:float = 12.0
@export var deer_radius:float = 260.0
@export var deer_heal_ratio:float = 0.12

var summoner:Node = null
var bite_cd:float = 0.0
var thunder_cd:float = 0.0
var deer_cd:float = 0.0
var _thunder_at:Vector2 = Vector2.ZERO
var _thunder_left:float = -1.0
var _aura_carry:Dictionary = {}
var _bite_visual:float = 0.0

func _ready() -> void:
	intro_sound = "agito_roar"
	cursed_energy_max = 800.0
	cursed_energy_regen = 25.0
	rct_heal_ratio_per_second = 0.02
	black_flash_chance = 0.0
	super._ready()
	add_to_group("JJKAgito")

func controlled_attack_action() -> void:
	if is_player_controlled(): bite(player_control_aim_direction(direction))
func controlled_skill_action() -> void:
	if is_player_controlled(): thunder(player_control_aim_world_position(global_position + direction * 200.0))
func controlled_middle_action() -> void:
	if is_player_controlled(): round_deer()

func wheel_boost() -> float:
	return wheel_boost_value if health > 0 else 1.0

func jjk_step(delta:float) -> void:
	bite_cd = maxf(0.0,bite_cd - delta)
	thunder_cd = maxf(0.0,thunder_cd - delta)
	deer_cd = maxf(0.0,deer_cd - delta)
	_bite_visual = maxf(0.0,_bite_visual - delta)
	for ally:ball in JJK.allies_in_circle(self,global_position,aura_radius,false):
		if ally.health >= ally.Max_health: continue
		var id:int = ally.get_instance_id()
		var carry:float = float(_aura_carry.get(id,0.0)) + float(ally.Max_health) * aura_heal_ratio_per_second * delta
		if carry >= 1.0:
			ally.heal(int(carry))
			carry -= int(carry)
		_aura_carry[id] = carry
	if _thunder_left >= 0.0:
		_thunder_left -= delta
		if _thunder_left < 0.0: _strike()

func bite(dir:Vector2) -> bool:
	if not can_act() or bite_cd > 0.0: return false
	bite_cd = bite_cooldown
	_bite_visual = 0.2
	var d:Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var best:ball = null
	for t:ball in JJK.enemies_in_circle(self,global_position + d * 34.0,60.0):
		if best == null or t.global_position.distance_to(global_position) < best.global_position.distance_to(global_position): best = t
	if best == null: return false
	JJK.hit(self,best,attack_damage(bite_damage_multiplier),best.global_position,&"ordinary",{"phenomenon":"agito_bite"})
	fx("slash",{"a":best.global_position + Vector2(-14,-10),"b":best.global_position + Vector2(14,10),"color":Color(0.9,0.2,0.2),"width":4.0,"world":true},0.2)
	return true

func thunder(at:Vector2) -> bool:
	if not can_act() or thunder_cd > 0.0 or _thunder_left >= 0.0 or not spend(60.0): return false
	thunder_cd = thunder_cooldown
	_thunder_at = global_position + (at - global_position).limit_length(420.0)
	_thunder_left = thunder_delay
	fx("shockwave",{"pos":_thunder_at,"radius":thunder_radius,"color":Color(0.6,0.8,1.0)},thunder_delay)
	return true

func _strike() -> void:
	_thunder_left = -1.0
	for t:ball in JJK.enemies_in_circle(self,_thunder_at,thunder_radius):
		JJK.hit(self,t,attack_damage(thunder_damage_multiplier),t.global_position,&"magic",{"phenomenon":"agito_thunder"})
		JJK.stun(self,t,0.8,{"phenomenon":"agito_thunder"})
	fx("thunder",{"pos":_thunder_at,"radius":thunder_radius},0.45)
	sfx("agito_thunder",-3.0)

func round_deer() -> bool:
	if not can_act() or deer_cd > 0.0 or not spend(200.0): return false
	deer_cd = deer_cooldown
	for ally:ball in JJK.allies_in_circle(self,global_position,deer_radius,true):
		ally.heal(float(ally.Max_health) * deer_heal_ratio)
		if ally.has_method("cleanse_negative_effects"): ally.cleanse_negative_effects()
		fx("heal",{"pos":ally.global_position,"radius":30.0},0.6)
	# 圆鹿的反转术式可以抵消术式：范围内敌方的苍被消去。
	for unit:Node in get_tree().get_nodes_in_group("JJKGojo"):
		if not JJK.U.enemy(self,unit) or not bool(unit.get("blue_active")): continue
		var p:Vector2 = unit.get("blue_pos")
		if p.distance_to(global_position) <= deer_radius and unit.has_method("_end_blue"): unit.call("_end_blue")
	fx("shockwave",{"pos":global_position,"radius":deer_radius,"color":Color(0.5,1.0,0.6)},0.5)
	return true

func jjk_ai() -> void:
	var target:ball = ai_target()
	# 治疗优先：友军（尤其魔虚罗/宿傩）低血时圆鹿。
	if deer_cd <= 0.0 and cursed_energy >= 200.0:
		for ally:ball in JJK.allies_in_circle(self,global_position,deer_radius,true):
			if ally.health < ally.Max_health * 0.6:
				round_deer()
				break
	if deer_cd <= 0.0 and cursed_energy >= 200.0:
		for unit:Node in get_tree().get_nodes_in_group("JJKGojo"):
			if JJK.U.enemy(self,unit) and bool(unit.get("blue_active")) and (unit.get("blue_pos") as Vector2).distance_to(global_position) < deer_radius:
				round_deer()
				break
	if not is_instance_valid(target): return
	var d:float = global_position.distance_to(target.global_position)
	if thunder_cd <= 0.0 and d < 420.0: thunder(target.global_position + target.velocity * thunder_delay)
	if d < 70.0 + U2.radius(target): bite(global_position.direction_to(target.global_position))
	# 跟随友方魔虚罗（加速适应），否则与敌人保持中距离。
	var anchor:ball = null
	for unit:Node in get_tree().get_nodes_in_group("JJKMahoraga"):
		if unit is ball and (unit as ball).health > 0 and not JJK.U.enemy(self,unit): anchor = unit
	if anchor != null and anchor.global_position.distance_to(global_position) > 200.0: steer(global_position.direction_to(anchor.global_position))
	elif target.is_in_group("JJKGojo"): steer_keep_distance(target,200.0,60.0)
	else: steer(global_position.direction_to(target.global_position))

func visual_particles(_dt:float) -> void:
	# 治疗光环中漂浮的绿色光点
	if _vrng.randf() < 0.35:
		var a:float = _vrng.randf() * TAU
		var d:float = sqrt(_vrng.randf()) * aura_radius
		vparts.emit(global_position + Vector2.from_angle(a) * d,Vector2(0,-_vrng.randf_range(15,35)),1.2,_vrng.randf_range(1.5,3.0),Color(0.5,1.0,0.6,0.7),0,0.5)
	if _thunder_left >= 0.0 and _vrng.randf() < 0.5:
		var a2:float = _vrng.randf() * TAU
		vparts.emit(_thunder_at + Vector2.from_angle(a2) * thunder_radius,Vector2.from_angle(a2) * -thunder_radius * 1.5,0.4,2.0,Color(0.7,0.85,1.0),2,1.0)

func draw_overlay(o:Node2D) -> void:
	if _bite_visual > 0.0:
		# 撕咬：上下两排獠牙合拢（墨线描边）。
		var k:float = floorf(clampf(_bite_visual * 4.0,0.0,1.0) * 4.0) / 4.0
		var d:Vector2 = direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT
		var c:Vector2 = global_position + d * 30.0
		var n:Vector2 = d.orthogonal()
		var gap:float = 12.0 * k
		for side:int in 2:
			var sgn:float = 1.0 if side == 0 else -1.0
			for i:int in 4:
				var x:float = -9.0 + i * 6.0
				var root:Vector2 = c + d * x + n * sgn * (gap + 4.0)
				var tip:Vector2 = c + d * x + n * sgn * gap * 0.2
				o.draw_colored_polygon(PackedVector2Array([root - d * 4.2 + n * sgn * 1.2,root + d * 4.2 + n * sgn * 1.2,tip - n * sgn * 1.5]),Color(0,0,0,1))
				o.draw_colored_polygon(PackedVector2Array([root - d * 3.0,root + d * 3.0,tip]),Color(0.97,0.94,0.86,1))

## 光环与落雷预警在角色之下：淡绿色虚线环（逐拍转动）；落雷为收缩的警戒环 + 地面电弧。
func draw_under(o:Node2D) -> void:
	var t:float = floorf(_view_clock * 12.0) / 12.0
	for i:int in 6:
		var a:float = t * 0.5 + TAU * i / 6.0
		o.draw_arc(global_position,aura_radius,a,a + 0.5,12,Color(0.0,0.12,0.03,0.25),3.5,true)
		o.draw_arc(global_position,aura_radius,a,a + 0.5,12,Color(0.55,1.0,0.65,0.35),1.4,true)
	if _thunder_left >= 0.0:
		var k:float = clampf(1.0 - _thunder_left / maxf(thunder_delay,0.01),0.0,1.0)
		var rr:float = thunder_radius * (1.0 - floorf(k * 8.0) / 8.0 * 0.9)
		for pass_i:int in 2:
			var col:Color = Color(0.0,0.03,0.1,0.85) if pass_i == 0 else Color(0.75,0.9,1.0,0.95)
			var w:float = 4.0 if pass_i == 0 else 1.6
			o.draw_arc(_thunder_at,thunder_radius,0.0,TAU,48,col,w,true)
			o.draw_arc(_thunder_at,rr,0.0,TAU,48,col,w,true)
		var brng:RandomNumberGenerator = RandomNumberGenerator.new()
		brng.seed = int(t * 12.0) + 5
		for i2:int in 2:
			var a2:float = brng.randf() * TAU
			var pts:PackedVector2Array = V.bolt(brng,_thunder_at + Vector2.from_angle(a2) * thunder_radius * 0.2,_thunder_at + Vector2.from_angle(a2 + 0.5) * thunder_radius,10.0,3)
			o.draw_polyline(pts,Color(0.0,0.03,0.1,0.9 * k),4.0,true)
			o.draw_polyline(pts,Color(0.8,0.95,1.0,k),1.6,true)

func visual_state() -> Dictionary:
	var data:Dictionary = super.visual_state()
	data["tl"] = _thunder_left
	data["ta"] = _thunder_at
	data["bv"] = _bite_visual
	return data

func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_thunder_left = float(data.get("tl",-1.0))
	_thunder_at = data.get("ta",_thunder_at)
	_bite_visual = float(data.get("bv",0.0))

func get_armor_test_effect_summary() -> String:
	if JJK.english():
		return "Ten Shadows fusion shikigami (Nue, Great Serpent, Tiger Funeral, Round Deer) given Reverse Cursed Technique by Sukuna. Healing aura for allies nearby and it speeds up an allied Mahoraga's adaptation wheel.\nLeft bite, Right Nue lightning (stun), Middle Round Deer: big group heal plus cleanse, and it erases an enemy Blue in range."
	return "十影融合式神（鵺、大蛇、虎葬、圆鹿），由宿傩赋予反转术式。周围友军持续回血，并加快友方魔虚罗的适应法阵。\n左键 撕咬；右键 鵺 落雷（定身）；中键 圆鹿：群体大治疗并净化，同时消去范围内敌方的苍。"
