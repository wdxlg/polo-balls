extends Node2D
## 领域展开节点（无量空处 / 0.2秒无量空处 / 伏魔御厨子）。
## - 各端由施术者 RPC 以相同参数生成；只有 authority 结算必中效果与结界耐久。
## - 无量空处：闭合结界（Terrain 层圆环碰撞），圈内外都无法穿越；必中=信息过载眩晕。
## - 伏魔御厨子：开放领域，覆盖全图；每 0.2 秒对范围内全部敌人“解/捌”，并持续斩击敌方结界外壁。
## - 领域对拼：处在自己完好结界内的单位不受伏魔御厨子必中；同时展开时双方施术者互相抵消必中，
##   结界被斩破或一方先结束，另一方的必中立即生效。
const JJK = preload("res://scripts/characters/动漫/咒术回战/jjk_common.gd")
const FX = preload("res://scripts/characters/动漫/咒术回战/jjk_fx.gd")
const GROUP:String = "JJKDomain"
const BARRIER_MAX:float = 100.0

var caster:ball
var id:int = 0
var domain_kind:String = "uv" # uv | uv_instant | shrine
var center:Vector2 = Vector2.ZERO
var radius:float = 400.0
var duration:float = 8.0
var authority:bool = false
var age:float = 0.0
var barrier_hp:float = BARRIER_MAX
var flip_left:float = 0.0
var shrunk:bool = false
var ended:bool = false
var broken:bool = false
var _tick_left:float = 0.0
var _barrier:StaticBody2D
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()
var _stars:PackedVector2Array = []
var _instant_done:bool = false

func _ready() -> void:
	top_level = true
	z_as_relative = false
	# 画在角色(z=0)之下、地图背景(z=-2)之上，领域内角色不会被压暗。
	z_index = -1
	global_position = Vector2.ZERO
	add_to_group(GROUP)
	_rng.seed = id * 7919 + 17
	for i:int in 90:
		var a:float = _rng.randf() * TAU
		var d:float = sqrt(_rng.randf()) * radius
		_stars.append(center + Vector2.from_angle(a) * d)
	if domain_kind == "uv":
		_build_barrier()

func is_closed() -> bool: return domain_kind == "uv"
func is_open() -> bool: return domain_kind == "shrine"
func is_active() -> bool: return not ended and is_instance_valid(caster)
func barrier_intact() -> bool: return is_closed() and is_active() and not broken

func _build_barrier() -> void:
	_barrier = StaticBody2D.new()
	_barrier.name = "DomainBarrier"
	_barrier.collision_layer = 1
	_barrier.collision_mask = 0
	_barrier.set_meta("mc_wall",true)
	_barrier.set_meta("jjk_domain_barrier",true)
	add_child(_barrier)
	_barrier.global_position = Vector2.ZERO
	var segments:int = 56
	for i:int in segments:
		var a0:float = TAU * i / segments
		var a1:float = TAU * (i + 1) / segments
		var cs:CollisionShape2D = CollisionShape2D.new()
		var seg:SegmentShape2D = SegmentShape2D.new()
		seg.a = center + Vector2.from_angle(a0) * radius
		seg.b = center + Vector2.from_angle(a1) * radius
		cs.shape = seg
		_barrier.add_child(cs)

func contains(p:Vector2) -> bool:
	if is_open() and not shrunk: return JJK.map_rect(self).grow(200.0).has_point(p)
	var c:Vector2 = center
	var r:float = radius
	if is_open() and shrunk and is_instance_valid(caster):
		c = caster.global_position
		r = 300.0
	return c.distance_to(p) <= r

static func active_domains(tree:SceneTree) -> Array:
	var result:Array = []
	for node:Node in tree.get_nodes_in_group(GROUP):
		if is_instance_valid(node) and bool(node.call("is_active")): result.append(node)
	return result

static func caster_has_active(tree:SceneTree,unit:Node,kind:String = "") -> bool:
	for d:Variant in active_domains(tree):
		if d.caster == unit and (kind.is_empty() or d.domain_kind == kind): return true
	return false

## 处在任一完好无量空处结界内部的单位，伏魔御厨子的外部斩击打不进来。
static func protected_by_barrier(tree:SceneTree,unit:Node2D) -> bool:
	for d:Variant in active_domains(tree):
		if bool(d.call("barrier_intact")) and d.center.distance_to(unit.global_position) < d.radius: return true
	return false

func _physics_process(delta:float) -> void:
	if ended: return
	if Game.now_stop_state: return
	if not is_instance_valid(caster) or caster.health <= 0:
		if authority: finish(false)
		else: queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	age += delta
	flip_left = maxf(0.0,flip_left - delta)
	queue_redraw()
	if not authority: return
	if domain_kind == "uv_instant":
		if not _instant_done:
			_instant_done = true
			for t:ball in JJK.enemies_in_circle(caster,center,radius):
				JJK.stun(caster,t,_uv_stun_scale(t) * 2.5,{"sure_hit":true,"phenomenon":"gojo_uv"})
				JJK.hit(caster,t,caster.attack_damage(0.4),t.global_position,&"magic",{"sure_hit":true,"phenomenon":"gojo_uv"})
				if t.has_method("on_jjk_uv_exposure"): t.call("on_jjk_uv_exposure",1.2)
		if age >= duration: finish(false)
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		var step:float = 0.2 if is_open() else 0.25
		_tick_left += step
		if is_closed(): _tick_uv(step)
		else: _tick_shrine(step)
	if age >= duration: finish(false)

func _uv_stun_scale(t:ball) -> float:
	if t.has_method("jjk_uv_resistance"): return clampf(1.0 - float(t.call("jjk_uv_resistance")),0.0,1.0)
	return 1.0

func _tick_uv(step:float) -> void:
	for t:ball in JJK.enemies_in_circle(caster,center,radius - 2.0):
		# 对拼：展开中的伏魔御厨子施术者与无量空处的必中互相抵消。
		if caster_has_active(get_tree(),t,"shrine"):
			# 领域对拼中：必中被对方领域抵消一半——不定身，但信息仍在灌入大脑。
			JJK.hit(caster,t,caster.attack_damage(0.08),t.global_position,&"magic",{"sure_hit":true,"phenomenon":"gojo_uv"})
			if t.has_method("on_jjk_uv_exposure"): t.call("on_jjk_uv_exposure",step * 0.5 * _uv_stun_scale(t))
			continue
		var scale:float = _uv_stun_scale(t)
		if scale > 0.0: JJK.stun(caster,t,step + 0.12,{"sure_hit":true,"phenomenon":"gojo_uv"})
		JJK.hit(caster,t,caster.attack_damage(0.15),t.global_position,&"magic",{"sure_hit":true,"phenomenon":"gojo_uv"})
		if t.has_method("on_jjk_uv_exposure"): t.call("on_jjk_uv_exposure",step * scale)

func _tick_shrine(_step:float) -> void:
	var tree:SceneTree = get_tree()
	var mult:float = 2.0 if shrunk else 1.0
	var targets:Array[ball] = []
	if shrunk: targets = JJK.enemies_in_circle(caster,caster.global_position,300.0)
	else:
		var rect:Rect2 = JJK.map_rect(caster).grow(200.0)
		for raw:Variant in JJK.candidates(caster):
			if raw is ball and raw.health > 0 and JJK.U.enemy(caster,raw) and rect.has_point(raw.global_position): targets.append(raw)
	for t:ball in targets:
		if protected_by_barrier(tree,t): continue
		var amount:float = (caster.attack_damage(0.35) + float(t.Max_health) * 0.005) * mult
		JJK.hit(caster,t,amount,t.global_position,&"ordinary",{"sure_hit":true,"bypass_infinity":true,"phenomenon":"sukuna_shrine"})
	# 斩击敌方结界外壁；翻转期间只有缩小后的领域能斩进去。
	for d:Variant in active_domains(tree):
		if d == self or not bool(d.call("barrier_intact")) or not JJK.U.enemy(caster,d.caster): continue
		if d.flip_left > 0.0 and not shrunk: continue
		if shrunk and d.center.distance_to(caster.global_position) > d.radius + 300.0: continue
		d.call("damage_barrier",2.4 * mult)

func damage_barrier(amount:float) -> void:
	if not authority or not barrier_intact(): return
	barrier_hp = maxf(0.0,barrier_hp - amount)
	if barrier_hp <= 0.0:
		broken = true
		finish(true)

func flip() -> bool:
	if not barrier_intact() or flip_left > 0.0: return false
	flip_left = 3.0
	return true

func finish(was_broken:bool) -> void:
	if ended: return
	ended = true
	broken = was_broken
	if is_instance_valid(_barrier): _barrier.queue_free()
	if authority and is_instance_valid(caster) and caster.has_method("on_jjk_domain_end"):
		caster.call("on_jjk_domain_end",id,was_broken)
	queue_free()

func end_remote(was_broken:bool) -> void:
	if ended: return
	ended = true
	broken = was_broken
	if is_instance_valid(_barrier): _barrier.queue_free()
	queue_free()

func _draw() -> void:
	var fade_in:float = minf(1.0,age / 0.35)
	match domain_kind:
		"uv","uv_instant":
			var r:float = radius * (0.6 + 0.4 * fade_in)
			draw_circle(center,r,Color(0.02,0.02,0.08,0.82 * fade_in))
			for i:int in 7:
				var a:float = age * (0.4 + i * 0.07) + i
				draw_arc(center,r * (0.2 + 0.11 * i),a,a + 2.2,40,Color(0.5,0.75,1.0,0.25),2.0,true)
			for i2:int in _stars.size():
				var p:Vector2 = _stars[i2]
				if p.distance_to(center) > r: continue
				var tw:float = 0.5 + 0.5 * sin(age * 3.0 + i2)
				draw_circle(p,1.2 + tw,Color(0.85,0.9,1.0,0.5 + 0.5 * tw))
			draw_circle(center,r * 0.07,Color(1,1,1,0.35 * fade_in))
			var ring:Color = Color(1.0,0.85,0.35) if flip_left > 0.0 else Color(0.75,0.9,1.0)
			var hp_ratio:float = clampf(barrier_hp / BARRIER_MAX,0.0,1.0)
			draw_arc(center,r,0.0,TAU,96,Color(ring,0.9 * fade_in),3.0 + 3.0 * hp_ratio,true)
			if domain_kind == "uv" and hp_ratio < 0.999:
				_rng.seed = id
				for i3:int in int((1.0 - hp_ratio) * 24.0):
					var a3:float = _rng.randf() * TAU
					var p3:Vector2 = center + Vector2.from_angle(a3) * r
					draw_line(p3,p3 + Vector2.from_angle(a3 + _rng.randf_range(2.4,3.8)) * _rng.randf_range(10,40),Color(1,1,1,0.8),1.5,true)
		"shrine":
			var rect:Rect2 = JJK.map_rect(self)
			if shrunk and is_instance_valid(caster):
				draw_circle(caster.global_position,300.0,Color(0.55,0.0,0.05,0.28 * fade_in))
				draw_arc(caster.global_position,300.0,0.0,TAU,80,Color(1.0,0.2,0.2,0.8),3.0,true)
			else:
				draw_rect(rect,Color(0.45,0.0,0.03,0.16 * fade_in))
			# 厨子：施术者身后的神龛剪影。
			if is_instance_valid(caster):
				var base:Vector2 = center + Vector2(0,-8)
				var s:float = 1.0 + 0.1 * sin(age * 2.0)
				var roof:PackedVector2Array = [base + Vector2(-70,-60) * s,base + Vector2(70,-60) * s,base + Vector2(40,-84) * s,base + Vector2(-40,-84) * s]
				draw_colored_polygon(roof,Color(0.25,0.02,0.05,0.8 * fade_in))
				draw_rect(Rect2(base + Vector2(-48,-60) * s,Vector2(96,52) * s),Color(0.12,0.0,0.02,0.7 * fade_in))
				draw_circle(base + Vector2(0,-36) * s,12.0 * s,Color(0.9,0.1,0.1,0.8 * fade_in))
			# 满屏随机斩击（纯视觉，每帧重新随机）。
			var vis:RandomNumberGenerator = RandomNumberGenerator.new()
			vis.seed = int(age * 20.0) * 131 + id
			var area:Rect2 = rect
			if shrunk and is_instance_valid(caster): area = Rect2(caster.global_position - Vector2(300,300),Vector2(600,600))
			for i4:int in 26:
				var p4:Vector2 = area.position + Vector2(vis.randf() * area.size.x,vis.randf() * area.size.y)
				var d4:Vector2 = Vector2.from_angle(vis.randf() * TAU) * vis.randf_range(18,60)
				draw_line(p4 - d4,p4 + d4,Color(1,1,1,0.75),1.6,true)
