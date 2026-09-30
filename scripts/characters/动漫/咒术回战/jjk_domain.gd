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
var _q:Dictionary = {}
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
	for i2:int in 26:
		var a:float = r.randf() * TAU
		_cracks.append([a,r.randf_range(0.1,0.35),r.randi()])
	call_deferred("_open_juice")

## 着色器面片（按名字复用）。parent: 0 = 本节点（角色之下），1 = 覆盖层（角色之上）。
func _qd(qname:String,mode:int,where:int,layer:int,pos:Vector2,size:Vector2,params:Dictionary) -> void:
	var sp:Sprite2D = _q.get(qname)
	if sp == null:
		sp = V.quad(self if where == 0 else _over,mode,layer)
		_q[qname] = sp
	if not params.has("time"): params["time"] = _vt
	if not params.has("seed"): params["seed"] = float(id % 97) * 1.37
	V.qset(sp,pos,size,0.0,params)

func _qhide(qname:String) -> void:
	var sp:Sprite2D = _q.get(qname)
	if sp != null: sp.visible = false

## 展开瞬间：后处理 + 震屏 + 扭曲。
func _open_juice() -> void:
	if not is_inside_tree(): return
	match domain_kind:
		"uv","uv_instant":
			var inst:bool = domain_kind == "uv_instant"
			V.screen(self,center,0.6 if inst else 1.0,{"blur":0.012,"flash":Color(0.6,0.85,1.0,0.55),"flash_time":0.14,"invert":0.6 if inst else 0.0,"invert_time":0.07,"vignette":0.4},Vector3(0.03,0.35,1.0))
			V.shake(self,10.0)
			V.hitstop(self,1.0,center)
			V.distort(self,0,center,Vector2.ONE * radius * 3.2,0.7,40.0)
		"shrine":
			V.screen(self,center,1.6,{"tint":Color(1.0,0.35,0.35,0.3),"desat":0.25,"vignette":0.4,"flash":Color(1.0,0.2,0.2,0.5),"flash_time":0.12},Vector3(0.05,0.9,1.0))
			V.shake(self,12.0)
			V.hitstop(self,1.0,center)
			V.distort(self,0,center,Vector2.ONE * 1400.0,0.9,36.0)

func _process(delta:float) -> void:
	if ended or Game.now_stop_state: return
	_vt += delta
	_update_quads()
	queue_redraw()
	if is_instance_valid(_add): _add.queue_redraw()
	if is_instance_valid(_over): _over.queue_redraw()
	if is_instance_valid(_over_add): _over_add.queue_redraw()

func _update_quads() -> void:
	match domain_kind:
		"uv","uv_instant":
			var r:float = _uv_r()
			var fade:float = minf(1.0,_vt / 0.3)
			var flip:bool = flip_left > 0.0
			# 无量空处本体：对数螺旋星云 + 奔向中心的无限信息流 + 中心之眼（着色器）
			_qd("void",V.Q.VOID,0,1,center,Vector2.ONE * r * 2.0 * 1.08,{"alpha":fade,"c0":Color(0.92,0.96,1.0),"c1":Color(1.0,0.8,0.35) if flip else Color(0.45,0.72,1.0),"c2":Color(0.36,0.22,0.9),"c3":Color(0.0,0.0,0.03),"p0":Vector4(0.926,0.9,0.12,0.95),"p1":Vector4(1.0,1.0,1.0,0.0)})
			# 展开冲击环
			var e:float = V.seg(_vt,0.0,0.7)
			if e < 1.0:
				_qd("open",V.Q.RING,1,2,center,Vector2.ONE * radius * 2.9,V.pal("cyan",{"alpha":1.2 * (1.0 - V.seg(e,0.25,1.0)),"p0":Vector4(0.2 + 0.75 * V.out_expo(e / 0.6),0.05 * (1.0 - e) + 0.012,0.2 + 0.6 * e,0.0),"p1":Vector4(0.006,0.3,0.7,0.0)}))
			else:
				_qhide("open")
		"shrine":
			var fade2:float = minf(1.0,_vt / 0.5)
			var rect:Rect2 = JJK.map_rect(self)
			if shrunk and is_instance_valid(caster):
				_qhide("pool")
				var cp:Vector2 = caster.global_position
				_qd("storm",V.Q.STORM,0,2,cp,Vector2.ONE * 600.0,{"alpha":fade2,"c0":Color(1,0.97,0.97),"c1":Color(1.0,0.22,0.25),"c2":Color(1.0,0.25,0.3),"c3":Color(0,0,0),"p0":Vector4(80.0,18.0,0.3,2.0),"p1":Vector4(0.35,0.8,1.0,0)})
				_qd("edge",V.Q.RING,1,2,cp,Vector2.ONE * 640.0,V.pal("red",{"alpha":0.9 * fade2,"p0":Vector4(0.935,0.03,0.25,0.0),"p1":Vector4(0.006,0.0,0.5,0.0)}))
				return
			_qhide("edge")
			# 血池：覆盖整张地图的暗红水面，涟漪 + 焦散
			_qd("pool",V.Q.POOL,0,1,rect.get_center(),rect.size,{"alpha":fade2,"c1":Color(0.95,0.2,0.22),"c2":Color(0.55,0.03,0.06),"c3":Color(0.2,0.0,0.02),"p0":Vector4(0.55,0.35,0.22,0.08)})
			# 满图「解」「捌」：着色器里按格子随机落刀，白/红斩痕 + 黑缝
			var area:Rect2 = _shrine_area()
			_qd("storm",V.Q.STORM,0,2,area.get_center(),area.size,{"alpha":fade2,"c0":Color(1,0.97,0.97),"c1":Color(1.0,0.22,0.25),"c2":Color(1.0,0.25,0.3),"c3":Color(0,0,0),"p0":Vector4(110.0,18.0,0.18,2.2),"p1":Vector4(0.3,0.8,0.0,0)})

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
	if domain_kind == "shrine": _draw_shrine_base()

func _draw_shrine_base() -> void:
	var fade:float = minf(1.0,_vt / 0.5)
	var pulse:float = 0.5 + 0.5 * sin(_vt * 3.2)
	if shrunk and is_instance_valid(caster):
		var cp:Vector2 = caster.global_position
		draw_circle(cp,300.0,Color(0.4,0.0,0.03,(0.22 + 0.08 * pulse) * fade))
		V.ring(self,cp,220.0,300.0,Color(0.5,0.0,0.05,0.0),Color(0.6,0.0,0.05,0.5 * fade),64)
	# 厨子背后翻滚的黑烟
	var rise0:float = V.out_back(minf(1.0,_vt / 0.9),1.4)
	for i:int in 5:
		var ph:float = fmod(_vt * 0.12 + i * 0.2,1.0)
		var sx:float = (i - 2) * 70.0 + sin(_vt * 0.7 + i) * 12.0
		V.sprite(self,"k_smoke07" if i % 2 == 0 else "k_smoke04",center + Vector2(sx,-80.0 - ph * 240.0) * rise0,(140.0 + ph * 170.0) * rise0,Color(0.06,0.0,0.02,0.5 * sin(ph * PI) * fade),_vt * 0.2 + i)
	_draw_shrine_building(fade)

## 厨子：骨山 + 石阶 + 四柱 + 獠牙巨口 + 两重上翘飞檐 + 牛角。从地面升起，全部带墨线。
func _draw_shrine_building(fade:float) -> void:
	var rise:float = V.out_back(minf(1.0,_vt / 0.9),1.4)
	if rise <= 0.01: return
	var base:Vector2 = center + Vector2(0,-6)
	var s:float = 1.2 * rise
	var ink:Color = Color(0.03,0.0,0.01,0.95 * fade)
	var dark:Color = Color(0.13,0.01,0.03,0.95 * fade)
	var wood:Color = Color(0.36,0.04,0.07,0.95 * fade)
	var wood_hi:Color = Color(0.62,0.1,0.12,0.95 * fade)
	var roof:Color = Color(0.1,0.02,0.04,0.96 * fade)
	var roof_hi:Color = Color(0.85,0.2,0.18,0.9 * fade)
	var bone:Color = Color(0.88,0.83,0.74,0.95 * fade)
	var bone_sh:Color = Color(0.55,0.48,0.42,0.95 * fade)
	var P:Callable = func(x:float,y:float) -> Vector2: return base + Vector2(x,y) * s
	var poly:Callable = func(pts:Array,fill:Color,line_w:float) -> void:
		var pk:PackedVector2Array = []
		for q:Variant in pts: pk.append(P.call(q.x,q.y))
		draw_colored_polygon(pk,fill)
		if line_w > 0.0:
			pk.append(pk[0])
			draw_polyline(pk,ink,line_w * s,true)
	# 骨山：椭圆土丘上堆三排骷髅
	var mound:Array = []
	for m:int in 17:
		var u:float = float(m) / 16.0
		mound.append(Vector2(lerpf(-130,130,u),10.0 - sin(u * PI) * 34.0))
	poly.call(mound,dark,2.0)
	var rows:Array = [[-112.0,112.0,4.0,11],[-92.0,92.0,-10.0,9],[-66.0,66.0,-22.0,7]]
	for row:Variant in rows:
		var n:int = int(row[3])
		for k:int in n:
			var bx:float = lerpf(float(row[0]),float(row[1]),float(k) / float(n - 1))
			var by:float = float(row[2]) + sin(k * 2.3) * 2.0
			var c:Vector2 = P.call(bx,by)
			draw_circle(c,8.2 * s,ink)
			draw_circle(c,7.0 * s,bone)
			draw_circle(c + Vector2(1.5,2.0) * s,5.0 * s,bone_sh)
			draw_circle(c + Vector2(-0.5,-0.8) * s,5.0 * s,bone)
			draw_circle(c + Vector2(-2.6,-0.5) * s,1.9 * s,ink)
			draw_circle(c + Vector2(2.6,-0.5) * s,1.9 * s,ink)
			draw_rect(Rect2(c + Vector2(-2.2,3.0) * s,Vector2(4.4,1.2) * s),ink)
	# 石阶
	for st:int in 3:
		var w:float = 64.0 - st * 10.0
		var y0:float = -22.0 - st * 6.0
		poly.call([Vector2(-w,y0),Vector2(w,y0),Vector2(w - 4,y0 - 6),Vector2(-w + 4,y0 - 6)],Color(0.2,0.03,0.05,0.95 * fade),1.2)
	# 台基
	poly.call([Vector2(-84,-40),Vector2(84,-40),Vector2(78,-50),Vector2(-78,-50)],dark,1.6)
	# 立柱
	for x:float in [-66.0,-42.0,42.0,66.0]:
		poly.call([Vector2(x - 5,-50),Vector2(x + 5,-50),Vector2(x + 5,-112),Vector2(x - 5,-112)],wood,1.4)
		draw_line(P.call(x + 2.5,-52),P.call(x + 2.5,-110),wood_hi,1.5 * s,true)
	# 巨口：圆角的黑红深洞 + 牙龈 + 上下獠牙
	var mouth:Array = []
	for mi:int in 21:
		var a:float = PI * float(mi) / 20.0
		mouth.append(Vector2(cos(a) * 34.0,-80.0 - sin(a) * 28.0))
	for mi2:int in range(1,20):
		var a2:float = PI * float(mi2) / 20.0
		mouth.append(Vector2(-cos(a2) * 34.0,-80.0 + sin(a2) * 24.0))
	poly.call(mouth,Color(0.55,0.04,0.07,0.95 * fade),2.0)
	var inner:Array = []
	for mv:Variant in mouth: inner.append(Vector2(mv.x * 0.82,-80.0 + (mv.y + 80.0) * 0.78))
	poly.call(inner,Color(0.04,0.0,0.0,0.97 * fade),0.0)
	for t:int in 7:
		var tx:float = -27.0 + t * 9.0
		var ty_top:float = -80.0 - sqrt(maxf(0.0,1.0 - pow((tx + 4.5) / 30.0,2.0))) * 22.0
		poly.call([Vector2(tx,ty_top),Vector2(tx + 9,ty_top),Vector2(tx + 4.5,ty_top + 11 + (t % 2) * 4)],bone,0.9)
		var ty_bot:float = -80.0 + sqrt(maxf(0.0,1.0 - pow((tx + 4.5) / 30.0,2.0))) * 18.0
		poly.call([Vector2(tx,ty_bot),Vector2(tx + 9,ty_bot),Vector2(tx + 4.5,ty_bot - 9 - ((t + 1) % 2) * 3)],bone,0.9)
	# 斗拱：一排小方块
	poly.call([Vector2(-76,-112),Vector2(76,-112),Vector2(76,-120),Vector2(-76,-120)],dark,1.4)
	for b:int in 9:
		var bx2:float = -64.0 + b * 16.0
		poly.call([Vector2(bx2 - 4,-120),Vector2(bx2 + 4,-120),Vector2(bx2 + 4,-126),Vector2(bx2 - 4,-126)],wood,1.0)
	# 下层飞檐：两端大幅上翘
	var e1:Array = []
	var e2:Array = []
	for i2:int in 17:
		var u2:float = float(i2) / 16.0
		var lift:float = pow(absf(u2 - 0.5) * 2.0,3.2) * 22.0
		e1.append(Vector2(lerpf(-118,118,u2),-126 - lift))
		e2.append(Vector2(lerpf(-84,84,u2),-150 - lift * 0.4))
	var r1:Array = e1.duplicate()
	for i3:int in range(16,-1,-1): r1.append(e2[i3])
	poly.call(r1,roof,2.0)
	var hl1:PackedVector2Array = []
	for q1:Variant in e1: hl1.append(P.call(q1.x,q1.y - 2.5))
	draw_polyline(hl1,roof_hi,1.6 * s,true)
	# 上层：墙身 + 屋顶 + 屋脊
	poly.call([Vector2(-52,-150),Vector2(52,-150),Vector2(52,-164),Vector2(-52,-164)],wood,1.4)
	var t1:Array = []
	var t2:Array = []
	for i4:int in 13:
		var u3:float = float(i4) / 12.0
		var lift2:float = pow(absf(u3 - 0.5) * 2.0,3.0) * 18.0
		t1.append(Vector2(lerpf(-88,88,u3),-164 - lift2))
		t2.append(Vector2(lerpf(-40,40,u3),-188 - lift2 * 0.3))
	var r2:Array = t1.duplicate()
	for i5:int in range(12,-1,-1): r2.append(t2[i5])
	poly.call(r2,roof,2.0)
	var hl2:PackedVector2Array = []
	for q2:Variant in t1: hl2.append(P.call(q2.x,q2.y - 2.5))
	draw_polyline(hl2,roof_hi,1.6 * s,true)
	poly.call([Vector2(-44,-188),Vector2(44,-188),Vector2(44,-194),Vector2(-44,-194)],dark,1.4)
	# 屋脊两端的牛角（向外再向上弯）
	for sg:float in [-1.0,1.0]:
		var cl:Array = []
		for h:int in 10:
			var hu:float = float(h) / 9.0
			cl.append(Vector2(sg * (40.0 + hu * 22.0 - hu * hu * 6.0),-192.0 - hu * hu * 34.0))
		var left:Array = []
		var right:Array = []
		for h2:int in 10:
			var tg:Vector2 = (cl[mini(h2 + 1,9)] - cl[maxi(h2 - 1,0)]).normalized()
			var nn:Vector2 = tg.orthogonal()
			var hw:float = 5.0 * (1.0 - float(h2) / 9.0) + 0.4
			left.append(cl[h2] + nn * hw)
			right.append(cl[h2] - nn * hw)
		var horn:Array = left.duplicate()
		for h3:int in range(9,-1,-1): horn.append(right[h3])
		poly.call(horn,bone,1.4)
	# 宝珠
	draw_circle(P.call(0,-200),6.5 * s,ink)
	draw_circle(P.call(0,-200),5.0 * s,Color(0.7,0.08,0.1,0.95 * fade))

# ---------------------------------------------------------------- 叠加层（角色之下）
func _draw_add() -> void:
	match domain_kind:
		"uv","uv_instant": _draw_uv_add()
		"shrine": _draw_shrine_add()

func _draw_uv_add() -> void:
	var ci:CanvasItem = _add
	var r:float = _uv_r()
	# 展开瞬间的闪光（其余全部在着色器里）
	var flash:float = 1.0 - V.seg(_vt,0.0,0.3)
	if flash > 0.0:
		V.core(ci,center,r * 0.3 * (1.0 + flash),Color(1,1,1,flash))
		V.sprite(ci,"k_flare01",center,r * 4.0,Color(0.7,0.9,1.0,flash),0.0,Vector2(1.0,0.3))

func _draw_shrine_add() -> void:
	var ci:CanvasItem = _add
	var fade:float = minf(1.0,_vt / 0.5)
	var rise:float = V.out_back(minf(1.0,_vt / 0.9),1.4)
	var s:float = 1.2 * rise
	var base:Vector2 = center + Vector2(0,-6)
	var pulse:float = 0.5 + 0.5 * sin(_vt * 5.0)
	# 背光与口中红光
	V.glow(ci,base + Vector2(0,-110) * s,190.0 * rise,Color(0.9,0.05,0.08,(0.3 + 0.12 * pulse) * fade))
	V.glow(ci,base + Vector2(0,-80) * s,40.0 * rise,Color(1.0,0.2,0.1,(0.55 + 0.4 * pulse) * fade))
	V.sprite(ci,"k_magic04",base + Vector2(0,-110) * s,360.0 * rise,Color(0.9,0.08,0.1,0.28 * fade),_vt * 0.25)
	# 两侧火盆
	for tx:float in [-100.0,100.0]:
		V.anim(ci,"a_fire",base + Vector2(tx,-58.0) * s,64.0 * rise,_vt * 1.2 + tx,Color(1.0,0.45,0.35,0.95 * fade),0.0,true,Vector2(1.0,1.5))
	V.anim(ci,"a_fire",base + Vector2(0,-84.0) * s,44.0 * rise,_vt * 0.9,Color(1.0,0.25,0.2,0.7 * fade),0.0,true)
	# 升腾的火星
	for i:int in 16:
		var ph:float = fmod(_vt * 0.4 + i * 0.137,1.0)
		var x:float = sin(i * 12.9) * 120.0 + sin(_vt * 2.0 + i) * 6.0
		V.core(ci,base + Vector2(x,-ph * 220.0) * rise,2.2,Color(1.0,0.35,0.15,sin(ph * PI) * fade))

# ---------------------------------------------------------------- 覆盖层（角色之上）
func _draw_over() -> void:
	if not (domain_kind == "uv") : return
	# 结界裂痕（耐久下降时出现）：黑色裂缝
	var r:float = _uv_r()
	var hp:float = _hp_ratio()
	var n:int = int((1.0 - hp) * _cracks.size())
	for i:int in n:
		var c:Array = _cracks[i]
		_drng.seed = int(c[2])
		var a:float = float(c[0])
		var p0:Vector2 = center + Vector2.from_angle(a) * r
		var p1:Vector2 = center + Vector2.from_angle(a + _drng.randf_range(-0.08,0.08)) * r * (1.0 - float(c[1]))
		_over.draw_polyline(V.bolt(_drng,p0,p1,r * 0.03,4),Color(0,0,0,0.9),4.0,true)

func _draw_over_add() -> void:
	var ci:CanvasItem = _over_add
	match domain_kind:
		"uv","uv_instant":
			var r:float = _uv_r()
			var fade:float = minf(1.0,_vt / 0.3)
			var hp:float = _hp_ratio() if domain_kind == "uv" else 1.0
			var flip:bool = flip_left > 0.0
			var col:Color = Color(1.0,0.8,0.3) if flip else Color(0.6,0.85,1.0)
			# 结界外缘细亮线 + 沿边缘流动的光段
			ci.draw_arc(center,r,0.0,TAU,160,Color(col,0.85 * fade),1.2 + 1.8 * hp,true)
			for i:int in 6:
				var a:float = _vt * (0.8 if i % 2 == 0 else -0.55) + TAU * i / 6.0
				ci.draw_arc(center,r + 2.0,a,a + 0.35,16,Color(1,1,1,0.7 * fade),2.0,true)
			# 结界翻转：金色符文环
			if flip:
				for g:int in 24:
					var ga:float = TAU * g / 24.0 - _vt * 0.6
					V.sparkle(ci,center + Vector2.from_angle(ga) * (r + 14.0),6.0,Color(1.0,0.85,0.4,0.9),ga)
			# 耐久低时的裂纹光
			if domain_kind == "uv" and hp < 0.999:
				var n:int = int((1.0 - hp) * _cracks.size())
				for i2:int in n:
					var c:Array = _cracks[i2]
					_drng.seed = int(c[2])
					var a2:float = float(c[0])
					var p0:Vector2 = center + Vector2.from_angle(a2) * r
					var p1:Vector2 = center + Vector2.from_angle(a2 + _drng.randf_range(-0.08,0.08)) * r * (1.0 - float(c[1]))
					ci.draw_polyline(V.bolt(_drng,p0,p1,r * 0.03,4),Color(1.0,0.9,0.9,0.7 * (0.6 + 0.4 * sin(_vt * 9.0 + i2))),1.3,true)
		"shrine":
			pass
