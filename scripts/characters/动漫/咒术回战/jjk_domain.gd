extends Node2D
## 领域展开节点（无量空处 / 0.2秒无量空处 / 伏魔御厨子）。
## - 各端由施术者 RPC 以相同参数生成；只有 authority 结算必中效果与结界耐久。
## - 无量空处：闭合结界（Terrain 层圆环碰撞），圈内外都无法穿越；必中=信息过载眩晕。
## - 伏魔御厨子：开放领域，覆盖全图；每 0.2 秒对范围内全部敌人“解/捌”，并持续斩击敌方结界外壁。
## - 领域对拼：处在自己完好结界内的单位不受伏魔御厨子必中；同时展开时双方施术者互相抵消必中，
##   结界被斩破或一方先结束，另一方的必中立即生效。
const JJK = preload("res://scripts/characters/动漫/咒术回战/jjk_common.gd")
const FX = preload("res://scripts/characters/动漫/咒术回战/jjk_fx.gd")
const V = preload("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd")
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
# ---- 纯视觉
var _vt:float = 0.0
var _add:Node2D
var _over:Node2D
var _over_add:Node2D
var _streams:Array = []
var _cracks:Array = []
var _drng:RandomNumberGenerator = RandomNumberGenerator.new()

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
	_setup_visuals()

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
		var amount:float = (caster.attack_damage(0.15) + float(t.Max_health) * 0.0025) * mult
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

# ================================================================= 视觉（纯表现，不影响结算）
func _setup_visuals() -> void:
	_add = V.make_add_layer(self,_draw_add)
	# 角色之上的覆盖层：伏魔御厨子的斩击、无量空处的结界亮边。
	_over = Node2D.new()
	_over.name = "DomainOverlay"
	_over.z_as_relative = false
	_over.z_index = 70
	add_child(_over)
	_over.draw.connect(_draw_over)
	_over_add = V.make_add_layer(_over,_draw_over_add)
	var r:RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = id * 104729 + 3
	for i:int in 46:
		_streams.append([r.randf() * TAU,r.randf(),r.randf_range(0.25,0.6),r.randf_range(12,50),r.randf()])
	for i2:int in 26:
		var a:float = r.randf() * TAU
		_cracks.append([a,r.randf_range(0.1,0.35),r.randi()])
	call_deferred("_open_juice")

func _lens_follow(d:Node2D) -> bool:
	if ended or not is_inside_tree(): return false
	d.global_position = center
	d.set("size",Vector2.ONE * maxf(_uv_r(),8.0) / 0.42)
	return true

## 展开瞬间：后处理 + 震屏 + 扭曲；无量空处的结界边缘常驻透镜折射。
func _open_juice() -> void:
	if not is_inside_tree(): return
	match domain_kind:
		"uv","uv_instant":
			var inst:bool = domain_kind == "uv_instant"
			V.screen(self,center,0.6 if inst else 1.1,{"blur":0.06,"aberration":0.012,"flash":Color(0.6,0.85,1.0,0.8),"flash_time":0.18,"invert":0.6 if inst else 0.0,"invert_time":0.08,"vignette":0.45},Vector3(0.03,0.35,1.0))
			V.shake(self,10.0)
			V.hitstop(self,1.0,center)
			V.distort(self,0,center,Vector2.ONE * radius * 3.2,0.7,46.0,{"aberration":2.5})
			V.distort(self,0,center,Vector2.ONE * radius / 0.42,duration,14.0,{"persistent":true,"fixed_radius":0.42,"thickness":0.05,"aberration":2.0,"z_index":69,"follow":_lens_follow})
		"shrine":
			V.screen(self,center,1.6,{"tint":Color(1.0,0.35,0.35,0.35),"desat":0.25,"vignette":0.4,"flash":Color(1.0,0.2,0.2,0.6),"flash_time":0.15,"aberration":0.01},Vector3(0.05,0.9,1.0))
			V.shake(self,12.0)
			V.hitstop(self,1.0,center)
			V.distort(self,0,center,Vector2.ONE * 1400.0,0.9,40.0,{"aberration":2.5})

func _process(delta:float) -> void:
	if ended or Game.now_stop_state: return
	_vt += delta
	queue_redraw()
	if is_instance_valid(_add): _add.queue_redraw()
	if is_instance_valid(_over): _over.queue_redraw()
	if is_instance_valid(_over_add): _over_add.queue_redraw()

func _uv_r() -> float:
	# 瞳孔般张开：先快后慢，末端轻微回弹。
	return radius * V.out_back(minf(1.0,_vt / 0.55),1.2)

func _hp_ratio() -> float:
	return clampf(barrier_hp / BARRIER_MAX,0.0,1.0)

func _shrine_area() -> Rect2:
	if shrunk and is_instance_valid(caster): return Rect2(caster.global_position - Vector2(300,300),Vector2(600,600))
	return JJK.map_rect(self)

# ---------------------------------------------------------------- 普通层（角色之下）
func _draw() -> void:
	match domain_kind:
		"uv","uv_instant": _draw_uv_base()
		"shrine": _draw_shrine_base()

func _draw_uv_base() -> void:
	var r:float = _uv_r()
	var fade:float = minf(1.0,_vt / 0.3)
	# 深空：中心近黑、向边缘带一点蓝紫。
	draw_circle(center,r,Color(0.0,0.0,0.03,0.9 * fade))
	V.ring(self,center,r * 0.55,r,Color(0.02,0.02,0.1,0.0),Color(0.08,0.05,0.25,0.7 * fade),72)
	# 结界裂痕（耐久下降时出现）。
	if domain_kind == "uv":
		var hp:float = _hp_ratio()
		var n:int = int((1.0 - hp) * _cracks.size())
		for i:int in n:
			var c:Array = _cracks[i]
			_drng.seed = int(c[2])
			var a:float = float(c[0])
			var p0:Vector2 = center + Vector2.from_angle(a) * r
			var p1:Vector2 = center + Vector2.from_angle(a + _drng.randf_range(-0.08,0.08)) * r * (1.0 - float(c[1]))
			var pts:PackedVector2Array = V.bolt(_drng,p0,p1,r * 0.03,4)
			draw_polyline(pts,Color(0,0,0,0.9),4.0,true)

func _draw_shrine_base() -> void:
	var fade:float = minf(1.0,_vt / 0.5)
	var pulse:float = 0.5 + 0.5 * sin(_vt * 3.2)
	var rect:Rect2 = JJK.map_rect(self)
	if shrunk and is_instance_valid(caster):
		var cp:Vector2 = caster.global_position
		draw_circle(cp,300.0,Color(0.4,0.0,0.03,(0.22 + 0.08 * pulse) * fade))
		V.ring(self,cp,220.0,300.0,Color(0.5,0.0,0.05,0.0),Color(0.6,0.0,0.05,0.5 * fade),64)
	else:
		draw_rect(rect,Color(0.35,0.0,0.02,(0.12 + 0.06 * pulse) * fade))
		_vignette(rect,minf(rect.size.x,rect.size.y) * 0.22,Color(0.3,0.0,0.02,0.75 * fade))
	# 厨子背后翻滚的黑烟
	var rise0:float = V.out_back(minf(1.0,_vt / 0.9),1.4)
	for i:int in 5:
		var ph:float = fmod(_vt * 0.12 + i * 0.2,1.0)
		var sx:float = (i - 2) * 60.0 + sin(_vt * 0.7 + i) * 12.0
		V.sprite(self,"k_smoke07" if i % 2 == 0 else "k_smoke04",center + Vector2(sx,-40.0 - ph * 220.0) * rise0,(120.0 + ph * 160.0) * rise0,Color(0.08,0.0,0.02,0.55 * sin(ph * PI) * fade),_vt * 0.2 + i)
	_draw_shrine_building(fade)

## 边缘暗角：四条梯形带，外侧颜色、内侧透明。
func _vignette(rect:Rect2,thick:float,col:Color) -> void:
	var o:Array[Vector2] = [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var inner:Rect2 = rect.grow(-thick)
	var i:Array[Vector2] = [inner.position,Vector2(inner.end.x,inner.position.y),inner.end,Vector2(inner.position.x,inner.end.y)]
	var clear:Color = Color(col,0.0)
	for k:int in 4:
		var k2:int = (k + 1) % 4
		draw_polygon(PackedVector2Array([o[k],o[k2],i[k2],i[k]]),PackedColorArray([col,col,clear,clear]))

## 厨子：双层飞檐神龛、立柱、獠牙之口、骨堆。从地面升起。
func _draw_shrine_building(fade:float) -> void:
	var rise:float = V.out_back(minf(1.0,_vt / 0.9),1.4)
	if rise <= 0.01: return
	var base:Vector2 = center + Vector2(0,-6)
	var s:float = 1.15 * rise
	var dark:Color = Color(0.12,0.01,0.03,0.92 * fade)
	var wood:Color = Color(0.28,0.03,0.06,0.92 * fade)
	var edge:Color = Color(0.7,0.12,0.15,0.9 * fade)
	var bone:Color = Color(0.85,0.8,0.72,0.9 * fade)
	var P:Callable = func(x:float,y:float) -> Vector2: return base + Vector2(x,y) * s
	# 骨堆
	for i:int in 9:
		var bx:float = -66.0 + i * 16.5
		var by:float = 4.0 - absf(i - 4.0) * 1.5
		draw_circle(P.call(bx,by),7.0 * s,bone)
		draw_circle(P.call(bx - 2.5,by - 1.0),1.8 * s,Color(0.1,0,0,fade))
		draw_circle(P.call(bx + 2.5,by - 1.0),1.8 * s,Color(0.1,0,0,fade))
	# 台基
	draw_colored_polygon(PackedVector2Array([P.call(-80,0),P.call(80,0),P.call(70,-10),P.call(-70,-10)]),dark)
	# 立柱
	for x:float in [-54.0,-30.0,30.0,54.0]:
		draw_rect(Rect2(P.call(x - 4,-62),Vector2(8,52) * s),wood)
		draw_line(P.call(x - 4,-62),P.call(x - 4,-10),edge,1.0,true)
	# 口：暗红的洞 + 上下獠牙
	var mouth:Rect2 = Rect2(P.call(-24,-58),Vector2(48,44) * s)
	draw_rect(mouth,Color(0.05,0.0,0.0,0.95 * fade))
	for t:int in 6:
		var tx:float = -24.0 + t * 8.0
		draw_colored_polygon(PackedVector2Array([P.call(tx,-58),P.call(tx + 8,-58),P.call(tx + 4,-48)]),bone)
		draw_colored_polygon(PackedVector2Array([P.call(tx,-14),P.call(tx + 8,-14),P.call(tx + 4,-23)]),bone)
	# 下层飞檐（两端上翘）
	var eave1:PackedVector2Array = []
	var eave2:PackedVector2Array = []
	for i2:int in 13:
		var u:float = float(i2) / 12.0
		var x2:float = lerpf(-92,92,u)
		var lift:float = pow(absf(u - 0.5) * 2.0,3.0) * 14.0
		eave1.append(P.call(x2,-62 - lift))
		eave2.append(P.call(lerpf(-74,74,u),-80 - lift * 0.6))
	var roof1:PackedVector2Array = eave1.duplicate()
	for i3:int in range(12,-1,-1): roof1.append(eave2[i3])
	draw_colored_polygon(roof1,wood)
	draw_polyline(eave1,edge,2.0,true)
	# 上层屋顶
	var top1:PackedVector2Array = []
	var top2:PackedVector2Array = []
	for i4:int in 11:
		var u2:float = float(i4) / 10.0
		var lift2:float = pow(absf(u2 - 0.5) * 2.0,3.0) * 12.0
		top1.append(P.call(lerpf(-70,70,u2),-86 - lift2))
		top2.append(P.call(lerpf(-34,34,u2),-110 - lift2 * 0.3))
	var roof2:PackedVector2Array = top1.duplicate()
	for i5:int in range(10,-1,-1): roof2.append(top2[i5])
	draw_rect(Rect2(P.call(-46,-86),Vector2(92,8) * s),dark)
	draw_colored_polygon(roof2,wood)
	draw_polyline(top1,edge,2.0,true)
	# 屋脊两端的角
	draw_colored_polygon(PackedVector2Array([P.call(-34,-110),P.call(-28,-110),P.call(-40,-126)]),bone)
	draw_colored_polygon(PackedVector2Array([P.call(34,-110),P.call(28,-110),P.call(40,-126)]),bone)

# ---------------------------------------------------------------- 叠加层（角色之下）
func _draw_add() -> void:
	match domain_kind:
		"uv","uv_instant": _draw_uv_add()
		"shrine": _draw_shrine_add()

func _draw_uv_add() -> void:
	var r:float = _uv_r()
	var fade:float = minf(1.0,_vt / 0.3)
	var ci:CanvasItem = _add
	# 星云：几团缓慢公转的彩色柔光
	var neb:Array[Color] = [Color(0.25,0.35,1.0),Color(0.6,0.2,0.9),Color(0.1,0.7,0.9),Color(0.35,0.15,0.7)]
	for i:int in 6:
		var a:float = _vt * (0.12 + 0.03 * i) + i * 1.7
		var d:float = r * (0.35 + 0.1 * (i % 3))
		V.glow(ci,center + Vector2.from_angle(a) * d,r * 0.55,Color(neb[i % 4],0.22 * fade))
	# 星空（闪烁 + 十字星）
	for i2:int in _stars.size():
		var p:Vector2 = center + (_stars[i2] - center) * (r / maxf(radius,1.0))
		var tw:float = 0.5 + 0.5 * sin(_vt * (2.0 + (i2 % 5)) + i2 * 1.3)
		V.core(ci,p,1.6 + 1.6 * tw,Color(0.8,0.9,1.0,(0.35 + 0.65 * tw) * fade))
		if i2 % 9 == 0: V.sparkle(ci,p,5.0 + 5.0 * tw,Color(0.8,0.9,1.0,0.8 * tw * fade),0.0)
	# 无限的信息流：光线从边缘奔向中心
	for st:Variant in _streams:
		var ang:float = float(st[0])
		var ph:float = fmod(float(st[1]) + _vt * float(st[2]),1.0)
		var dist:float = r * (1.0 - V.in_cubic(ph) * 0.95)
		var dir:Vector2 = Vector2.from_angle(ang + ph * 0.6)
		var head:Vector2 = center + dir * dist
		var tail:Vector2 = center + Vector2.from_angle(ang + maxf(0.0,ph - 0.08) * 0.6) * minf(r,dist + float(st[3]) * (0.5 + ph))
		var col:Color = Color(0.55,0.8,1.0) if float(st[4]) < 0.7 else Color(0.85,0.6,1.0)
		ci.draw_line(tail,head,Color(col,0.55 * sin(ph * PI) * fade),1.4,true)
	# 贴图层：旋转星系漩涡 + 粒子核心 + 贴图星
	V.sprite(ci,"k_light03",center,r * 2.1,Color(0.2,0.35,0.9,0.35 * fade),_vt * 0.1)
	V.sprite(ci,"k_twirl02",center,r * 1.9,Color(0.35,0.5,1.0,0.55 * fade),-_vt * 0.35)
	V.sprite(ci,"k_twirl03",center,r * 1.35,Color(0.6,0.35,1.0,0.5 * fade),-_vt * 0.6 + 1.3)
	V.sprite(ci,"k_twirl01",center,r * 0.8,Color(0.6,0.9,1.0,0.6 * fade),-_vt * 1.1)
	V.anim(ci,"a_pfx_cyan",center,r * 0.9,_vt * 0.5,Color(1,1,1,0.9 * fade),0.0,true)
	for i4:int in _stars.size():
		if i4 % 4 != 0: continue
		var sp:Vector2 = center + (_stars[i4] - center) * (r / maxf(radius,1.0))
		var tw4:float = 0.5 + 0.5 * sin(_vt * (1.5 + (i4 % 3)) + i4 * 0.7)
		V.sprite(ci,["k_star01","k_star04","k_star06","k_star08"][i4 % 4],sp,(10.0 + 16.0 * tw4) * (1.0 + float(i4 % 7) * 0.2),Color(0.75,0.88,1.0,(0.3 + 0.7 * tw4) * fade),_vt * 0.3 * (1 if i4 % 2 == 0 else -1))
	# 中心之眼
	var eye_r:float = r * 0.16
	V.glow(ci,center,eye_r * 3.0,Color(0.5,0.75,1.0,0.5 * fade))
	V.core(ci,center,eye_r * 0.55,Color(0.9,0.95,1.0,0.9 * fade))
	for i3:int in 5:
		var rr:float = eye_r * (0.8 + 0.35 * i3)
		var a3:float = _vt * (0.9 - 0.25 * i3) * (1.0 if i3 % 2 == 0 else -1.0) + i3
		for seg:int in 3:
			var s0:float = a3 + TAU * seg / 3.0
			ci.draw_arc(center,rr,s0,s0 + 1.3,20,Color(0.6,0.85,1.0,(0.55 - 0.08 * i3) * fade),1.6,true)
	# 展开瞬间的闪光
	var flash:float = 1.0 - V.seg(_vt,0.0,0.35)
	if flash > 0.0:
		V.core(ci,center,r * 0.3 * (1.0 + flash),Color(1,1,1,flash))
		V.sprite(ci,"k_flare01",center,r * 4.0,Color(0.7,0.9,1.0,flash),0.0,Vector2(1.0,0.3))
	V.anim(ci,"a_bluering",center,r * 2.6,V.seg(_vt,0.0,0.7),Color(1,1,1,0.9))

func _draw_shrine_add() -> void:
	var ci:CanvasItem = _add
	var fade:float = minf(1.0,_vt / 0.5)
	var rise:float = V.out_back(minf(1.0,_vt / 0.9),1.4)
	var base:Vector2 = center + Vector2(0,-6)
	var pulse:float = 0.5 + 0.5 * sin(_vt * 5.0)
	# 神龛之口的红光与背光
	V.glow(ci,base + Vector2(0,-60) * rise,150.0 * rise,Color(0.9,0.05,0.08,(0.35 + 0.15 * pulse) * fade))
	V.glow(ci,base + Vector2(0,-36) * 1.15 * rise,34.0 * rise,Color(1.0,0.2,0.1,(0.6 + 0.4 * pulse) * fade))
	# 贴图层：背光法阵、两侧火把、口中火焰
	V.sprite(ci,"k_magic04",base + Vector2(0,-60) * rise,300.0 * rise,Color(0.9,0.08,0.1,0.35 * fade),_vt * 0.25)
	V.sprite(ci,"k_light03",base + Vector2(0,-60) * rise,260.0 * rise,Color(1.0,0.1,0.08,(0.3 + 0.15 * pulse) * fade))
	for tx:float in [-88.0,88.0]:
		V.anim(ci,"a_fire",base + Vector2(tx,-30.0) * 1.15 * rise,70.0 * rise,_vt * 1.2 + tx,Color(1.0,0.45,0.35,0.95 * fade),0.0,true,Vector2(1.0,1.5))
	V.anim(ci,"a_fire",base + Vector2(0,-40.0) * 1.15 * rise,56.0 * rise,_vt * 0.9,Color(1.0,0.25,0.2,0.8 * fade),0.0,true)
	# 升腾的火星
	for i:int in 14:
		var ph:float = fmod(_vt * 0.4 + i * 0.137,1.0)
		var x:float = sin(i * 12.9) * 90.0 + sin(_vt * 2.0 + i) * 6.0
		V.core(ci,base + Vector2(x,-ph * 160.0),2.2,Color(1.0,0.35,0.15,sin(ph * PI) * fade))
	if shrunk and is_instance_valid(caster):
		V.shock(ci,caster.global_position,300.0,18.0 + 8.0 * pulse,Color(1.0,0.15,0.15,0.8 * fade))

# ---------------------------------------------------------------- 覆盖层（角色之上）
func _draw_over() -> void:
	pass

func _draw_over_add() -> void:
	var ci:CanvasItem = _over_add
	match domain_kind:
		"uv","uv_instant":
			var r:float = _uv_r()
			var fade:float = minf(1.0,_vt / 0.3)
			var hp:float = _hp_ratio() if domain_kind == "uv" else 1.0
			var flip:bool = flip_left > 0.0
			var col:Color = Color(1.0,0.8,0.3) if flip else Color(0.6,0.85,1.0)
			var shimmer:float = 0.75 + 0.25 * sin(_vt * 6.0)
			# 结界亮边：内侧渐变 + 外侧细亮线
			V.ring(ci,center,r - 26.0,r,Color(col,0.0),Color(col,0.35 * fade * shimmer),96)
			ci.draw_arc(center,r,0.0,TAU,128,Color(col,0.9 * fade),1.5 + 2.5 * hp,true)
			V.sprite(ci,"k_circle02",center,r * 2.12,Color(col,0.55 * fade * shimmer),_vt * 0.2)
			V.sprite(ci,"k_circle05",center,r * 2.05,Color(col,0.3 * fade),-_vt * 0.15)
			# 沿边缘流动的光段
			for i:int in 6:
				var a:float = _vt * (0.8 if i % 2 == 0 else -0.55) + TAU * i / 6.0
				ci.draw_arc(center,r + 3.0,a,a + 0.35,16,Color(1,1,1,0.7 * fade),2.0,true)
			# 结界翻转：金色符文环
			if flip:
				for g:int in 24:
					var ga:float = TAU * g / 24.0 - _vt * 0.6
					var gp:Vector2 = center + Vector2.from_angle(ga) * (r + 14.0)
					V.sparkle(ci,gp,6.0,Color(1.0,0.85,0.4,0.9),ga)
			# 耐久低时的裂纹光
			if domain_kind == "uv" and hp < 0.999:
				var n:int = int((1.0 - hp) * _cracks.size())
				for i2:int in n:
					var c:Array = _cracks[i2]
					_drng.seed = int(c[2])
					var a2:float = float(c[0])
					var p0:Vector2 = center + Vector2.from_angle(a2) * r
					var p1:Vector2 = center + Vector2.from_angle(a2 + _drng.randf_range(-0.08,0.08)) * r * (1.0 - float(c[1]))
					var pts:PackedVector2Array = V.bolt(_drng,p0,p1,r * 0.03,4)
					ci.draw_polyline(pts,Color(1.0,0.9,0.9,0.7 * (0.6 + 0.4 * sin(_vt * 9.0 + i2))),1.3,true)
			# 展开瞬间的边缘冲击
			var e:float = V.seg(_vt,0.0,0.6)
			if e < 1.0: V.shock(ci,center,r * (1.0 + e * 0.15),40.0 * (1.0 - e),Color(col,1.0 - e))
		"shrine":
			# 满屏闪烁的“解/捌”斩痕：每个 0.05 秒一批，三批叠加渐隐。
			var area:Rect2 = _shrine_area()
			var fade2:float = minf(1.0,_vt / 0.5)
			var bucket:int = int(_vt / 0.05)
			for b:int in 3:
				var life:float = 1.0 - (fmod(_vt,0.05) / 0.05 + b) / 3.0
				_drng.seed = (bucket - b) * 131 + id
				for i3:int in 9:
					var p:Vector2 = area.position + Vector2(_drng.randf() * area.size.x,_drng.randf() * area.size.y)
					var d:Vector2 = Vector2.from_angle(_drng.randf() * TAU) * _drng.randf_range(24,70)
					var bulge:float = _drng.randf_range(-8,8)
					var red:bool = _drng.randf() < 0.3
					var c3:Color = Color(1.0,0.25,0.25) if red else Color(1,0.95,0.95)
					if i3 % 3 == 0:
						V.sprite(ci,"k_slash04",p,d.length() * 2.4,Color(c3,0.8 * life * fade2),d.angle(),Vector2(1.0,0.45))
					else:
						V.sprite_line(ci,"k_trace07",p - d,p + d,8.0,Color(c3,0.8 * life * fade2),true)
						V.crescent(ci,p - d,p + d,3.0,bulge,Color(1,1,1,0.9 * life * fade2),1.0,0.0,10)
