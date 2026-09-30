extends Node2D
## 咒术回战一次性视觉特效（纯视觉，不结算伤害）。坐标全部为世界坐标。
## 由角色 RPC 在各端本地生成，随机种子随包下发，各端动画一致。
## 画风按原作动画：硬边赛璐璐三阶色 + 墨线描边（jjk_fxshader），形状按 24fps 逐拍、轮廓按 12fps 抖动，
## 命中瞬间用全屏冲击帧（黑白二值/反相/双色，V.impact）与集中线；碎石、墨点、火星为带描边的实心图形。
## 绘制顺序：本节点 _draw（墨迹/地面裂痕）→ 着色器面片（按首次创建顺序）→ TopLayer（碎片、火星、文字）。
const V = preload("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd")
const Q = V.Q
const JJK_FONT_OUTLINE:int = 8
const FPS:float = 24.0

var kind:String = ""
var data:Dictionary = {}
var life:float = 0.5
var t:float = 0.0
var _seed:int = 0
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()
var _top:Node2D
var _cache:Array = []
var _qs:Dictionary = {}
var _qused:Dictionary = {}
var _bits:Bits = Bits.new()

static func spawn(parent:Node,fx_kind:String,fx_data:Dictionary,duration:float) -> Node2D:
	if not is_instance_valid(parent) or not parent.is_inside_tree(): return null
	var fx:Node2D = (load("res://scripts/characters/动漫/咒术回战/jjk_fx.gd") as GDScript).new()
	fx.name = "JJKFx_" + fx_kind
	fx.set("kind",fx_kind)
	fx.set("data",fx_data)
	fx.set("life",maxf(duration,0.05))
	fx.set("_seed",int(fx_data.get("seed",randi())))
	fx.top_level = true
	fx.z_as_relative = false
	fx.z_index = int(fx_data.get("z",88))
	# 世界级特效（世界斩、领域文字）挂到当前场景，其余挂在角色下。
	if bool(fx_data.get("world",false)) and parent.get_tree().current_scene != null:
		parent.get_tree().current_scene.add_child(fx)
		fx.add_to_group("JJKWorldFx")
	else:
		parent.add_child(fx)
	fx.global_position = Vector2.ZERO
	fx.global_rotation = 0.0
	fx.global_scale = Vector2.ONE
	return fx

## 持续性部分沉到角色之下（z -1）的时刻（占 life 的比例）：爆发瞬间在上层，余烬/裂痕/火墙不挡角色。
const SINK_AT:Dictionary = {"fuga_burst":0.3,"red_burst":0.35,"web":0.3,"world_slash":0.35,"wheel_turn":0.0,"heal":0.0,"shockwave":0.4,"thunder":0.4,"black_flash":0.45,"purple_beam":0.45,"cleave":0.55,"teleport":0.4,"ripple":0.0}
var _sunk:bool = false
## 纯视觉的最短演出时长（不影响任何判定）。
const MIN_LIFE:Dictionary = {"red_burst":0.8,"cleave":0.75,"web":1.0,"fuga_burst":1.5,"world_slash":1.5,"black_flash":0.75,"thunder":0.6,"ripple":0.4,"teleport":0.4,"wheel_turn":0.9,"purple_beam":1.1,"slash":0.36,"shockwave":0.5,"heal":0.6}

func _ready() -> void:
	life = maxf(life,float(MIN_LIFE.get(kind,0.0)))
	_rng.seed = _seed
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_top = Node2D.new()
	_top.name = "TopLayer"
	add_child(_top)
	_top.draw.connect(_draw_top)
	if kind == "cutin":
		var face_path:String = str(data.get("face",""))
		V.cutin(self,load(face_path) if ResourceLoader.exists(face_path) else null,str(data.get("title","")),str(data.get("sub","")),_c("color",Color(0.5,0.7,1.0)),bool(data.get("right",false)),life)
		life = 0.05
		return
	_init_kind()
	_juice()
	if float(SINK_AT.get(kind,1.0)) <= 0.0:
		_sunk = true
		z_index = -1
	_update_quads()

func _process(delta:float) -> void:
	if Game.now_stop_state: return
	t += delta
	if t >= life + (0.3 if _bits.alive > 0 else 0.0):
		queue_free()
		return
	if not _sunk and SINK_AT.has(kind) and _k() >= float(SINK_AT[kind]):
		_sunk = true
		z_index = -1
	_bits.step(delta)
	_update_quads()
	queue_redraw()
	_top.queue_redraw()

func _v(key:String,fallback:Vector2 = Vector2.ZERO) -> Vector2:
	var value:Variant = data.get(key,fallback)
	return value if value is Vector2 else fallback

func _f(key:String,fallback:float) -> float:
	return float(data.get(key,fallback))

func _c(key:String,fallback:Color) -> Color:
	var value:Variant = data.get(key,fallback)
	return value if value is Color else fallback

## 逐拍时间（24fps）：形状变化一拍一跳，是动画感的关键。
func _ts() -> float:
	return floorf(t * FPS) / FPS

func _k() -> float:
	return clampf(_ts() / life,0.0,1.0)

## 以秒计的区间进度（逐拍）。
func _sk(a:float,b:float) -> float:
	return clampf((_ts() - a) / maxf(b - a,0.0001),0.0,1.0)

# ================================================================= 着色器面片
func _qd(qname:String,mode:int,pos:Vector2,size:Vector2,rot:float,params:Dictionary) -> void:
	var s:Sprite2D = _qs.get(qname)
	if s == null:
		s = V.quad(self,mode,2)
		_qs[qname] = s
		move_child(_top,-1)
	if not params.has("time"): params["time"] = t
	if not params.has("seed"): params["seed"] = float(_seed % 997) * 0.173
	V.qset(s,pos,size,rot,params)
	_qused[qname] = true

func _update_quads() -> void:
	_qused.clear()
	_quads()
	for qname:Variant in _qs.keys():
		if not _qused.has(qname): (_qs[qname] as Sprite2D).visible = false

func _pal(name:String,extra:Dictionary) -> Dictionary:
	return V.pal(name,extra)

## 以下 q_* 为 V.*_q 的薄包装（名字复用面片）。
func _qa(qname:String,mode:int,pos:Vector2,q:Array,rot:float = 0.0,extra:Dictionary = {}) -> void:
	var params:Dictionary = q[1]
	params.merge(extra,true)
	_qd(qname,mode,pos,q[0],rot,params)

func q_orb(qname:String,pos:Vector2,radius:float,pal:String,a:float = 1.0,boil:float = 0.06,spikes:float = 0.0,spike_n:float = 9.0,swirl:float = 0.0,hollow:float = 0.0,crackle:float = 0.0,outline:float = 2.0,bands:Vector2 = Vector2(0.22,0.25)) -> void:
	_qa(qname,Q.ORB,pos,V.orb_q(pal,radius,a,boil,spikes,spike_n,swirl,hollow,crackle,outline,bands))

func q_burst(qname:String,pos:Vector2,radius:float,pal:String,a:float = 1.0,rays:float = 12.0,jag:float = 0.35,fps:float = 24.0,rot:float = 0.0,outline:float = 2.5,bands:Vector2 = Vector2(0.3,0.3)) -> void:
	_qa(qname,Q.BURST,pos,V.burst_q(pal,radius,a,rays,jag,fps,rot,outline,bands))

func q_ring(qname:String,pos:Vector2,radius:float,thick:float,pal:String,a:float = 1.0,breakup:float = 0.4,segs:float = 10.0,outline:float = 2.0,bands:Vector2 = Vector2(0.3,0.3)) -> void:
	_qa(qname,Q.RING,pos,V.ring_q(pal,radius,thick,a,breakup,segs,outline,bands))

func q_lines(qname:String,pos:Vector2,radius:float,color:Color,a:float = 1.0,inner:float = 0.35,count:float = 70.0,width:float = 0.5,fps:float = 12.0,inward:float = 0.0) -> void:
	_qa(qname,Q.LINES,pos,V.lines_q(radius,color,a,inner,count,width,fps,inward))

func q_beam(qname:String,a:Vector2,b:Vector2,hw:float,pal:String,alpha_v:float = 1.0,head:float = 1.0,tail:float = 0.0,wobble:float = 0.08,outline:float = 3.0,bands:Vector2 = Vector2(0.28,0.3),flow:float = 6.0) -> void:
	var L:float = a.distance_to(b)
	if L < 2.0: return
	_qa(qname,Q.BEAM,(a + b) * 0.5,V.beam_q(pal,L,hw,alpha_v,head,tail,wobble,outline,bands,flow),(b - a).angle())

## 斩痕：a→b 的新月形刃，thick 为最厚处半宽像素，bend 为弧度像素。
func q_slash(qname:String,a:Vector2,b:Vector2,thick:float,pal:String,alpha_v:float = 1.0,reveal:float = 1.0,tail:float = 0.0,bend:float = 0.0,outline:float = 1.5,core:float = 0.3) -> void:
	var L:float = a.distance_to(b)
	if L < 2.0 or reveal <= tail: return
	var half:float = thick + absf(bend) + outline + 2.0
	_qd(qname,Q.SLASH,(a + b) * 0.5,Vector2(L,half * 2.0),(b - a).angle(),_pal(pal,{"alpha":alpha_v,"p0":Vector4(reveal,tail,bend / half,outline),"p1":Vector4(thick / half,core,0,0)}))

## 火焰：shape 0 火柱/火墙，1 火球。
func q_fire(qname:String,pos:Vector2,radius:float,intensity:float,shape:float = 1.0,a:float = 1.0,speed:float = 2.2,scale:float = 2.2,outline:float = 0.07,pal:String = "fire") -> void:
	_qa(qname,Q.FIRE,pos,V.fire_q(radius,intensity,shape,a,speed,scale,outline,pal))

## 放射裂纹：count 条，reach 0..1 长度，width 像素。
func q_crack(qname:String,pos:Vector2,radius:float,count:float,width:float,edge:Color,core:Color = Color(0,0,0),a:float = 1.0,jag:float = 0.25) -> void:
	_qd(qname,Q.CRACK,pos,Vector2.ONE * radius * 2.0,0.0,{"alpha":a,"c1":edge,"c3":core,"p0":Vector4(count,1.0,width,jag)})

# ================================================================= 初始化（碎片、火星等一次性发射）
func _init_kind() -> void:
	match kind:
		"ripple":
			_bits.sparks(_rng,_v("pos"),6,90.0,180.0,0.22,6.0,Color(0.6,0.95,1.0))
		"red_burst":
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",80.0)
			_bits.shards(_rng,p,14,r * 3.0,r * 7.0,0.7,r * 0.1,Color(0.16,0.1,0.1),360.0)
			_bits.sparks(_rng,p,22,r * 4.0,r * 9.0,0.35,r * 0.35,Color(1.0,0.35,0.25))
		"purple_beam":
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			var w:float = _f("width",90.0)
			var d:Vector2 = (b - a).normalized()
			for i:int in 26:
				var at:Vector2 = a.lerp(b,_rng.randf_range(0.05,0.95))
				var side:float = 1.0 if _rng.randf() < 0.5 else -1.0
				_bits.shard(at + d.orthogonal() * side * w * 0.6,d * _rng.randf_range(200,700) + d.orthogonal() * side * _rng.randf_range(80,300),_rng.randf_range(0.5,0.9),_rng.randf_range(3.0,7.0),Color(0.14,0.08,0.16),_rng,200.0)
			# 地面沟壑：沿光束两侧的锯齿边线（沉到角色下后保留一会儿）。
			for side2:int in 2:
				var pts:PackedVector2Array = []
				var sgn:float = 1.0 if side2 == 0 else -1.0
				var L:float = a.distance_to(b)
				var steps:int = int(clampf(L / 24.0,8,90))
				for i2:int in steps + 1:
					var u:float = float(i2) / steps
					pts.append(a.lerp(b,u) + d.orthogonal() * sgn * w * (0.72 + _rng.randf_range(-0.12,0.12)))
				_cache.append(pts)
		"slash":
			var a2:Vector2 = _v("a")
			var b2:Vector2 = _v("b")
			var mid:Vector2 = a2.lerp(b2,0.5)
			var n:Vector2 = (b2 - a2).orthogonal().normalized()
			_cache = [_rng.randf_range(-1.0,1.0)]
			_bits.sparks(_rng,mid,6,120.0,320.0,0.2,8.0,Color(1,1,1),(b2 - a2).angle(),0.8)
			for i3:int in 5:
				_bits.drop(mid + (b2 - a2) * _rng.randf_range(-0.2,0.2),n * _rng.randf_range(-90,90) + Vector2(0,-_rng.randf_range(30,90)),0.5,_rng.randf_range(1.6,2.8),Color(0.75,0.0,0.06),420.0)
		"cleave":
			var p3:Vector2 = _v("pos")
			var r3:float = _f("radius",34.0)
			var base_ang:float = _rng.randf() * PI
			for i3:int in 10:
				var grp:int = i3 % 2
				var ang3:float = base_ang + (PI * 0.5 + _rng.randf_range(-0.2,0.2)) * grp + _rng.randf_range(-0.1,0.1)
				var lane:float = (float(i3 >> 1) - 2.0) * r3 * 0.42 + _rng.randf_range(-3,3)
				_cache.append([ang3,_rng.randf_range(1.4,1.9),i3 * 0.028,lane,_rng.randf_range(-1.0,1.0)])
			_bits.shards(_rng,p3,12,r3 * 4.0,r3 * 9.0,0.6,r3 * 0.16,Color(0.2,0.05,0.07),420.0)
			for i4:int in 10:
				_bits.drop(p3 + Vector2.from_angle(_rng.randf() * TAU) * r3 * 0.5,Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(80,240) + Vector2(0,-80),0.7,_rng.randf_range(2.0,3.5),Color(0.75,0.0,0.06),520.0)
		"web":
			var p4:Vector2 = _v("pos")
			var r4:float = _f("radius",150.0)
			var spokes:int = 12
			var angs:Array = []
			for i4:int in spokes: angs.append(TAU * i4 / spokes + _rng.randf_range(-0.14,0.14))
			_cache = [angs]
			# 蛛网横丝：每圈在相邻辐条间连一段略下垂的折线
			var rings:Array = []
			for rr:float in [0.3,0.52,0.74,0.95]:
				var ringpts:PackedVector2Array = []
				for i5:int in spokes + 1:
					var ang:float = angs[i5 % spokes]
					ringpts.append(p4 + Vector2.from_angle(ang) * r4 * rr * _rng.randf_range(0.92,1.06))
				rings.append(ringpts)
			_cache.append(rings)
			_bits.shards(_rng,p4,20,r4 * 1.5,r4 * 3.5,0.8,r4 * 0.04,Color(0.2,0.16,0.15),380.0)
			_bits.dust(_rng,p4,10,r4 * 0.85,r4 * 1.05,r4 * 0.07,Color(0.84,0.82,0.8),Color(0.5,0.47,0.46))
		"fuga_burst":
			var p5:Vector2 = _v("pos")
			var r5:float = _f("radius",160.0)
			_bits.embers(_rng,p5,40,r5 * 1.5,r5 * 4.0,1.0,r5 * 0.03)
			_bits.shards(_rng,p5,14,r5 * 1.5,r5 * 4.0,0.8,r5 * 0.04,Color(0.15,0.05,0.03),300.0)
		"world_slash":
			var a6:Vector2 = _v("a")
			var b6:Vector2 = _v("b")
			var n6:Vector2 = (b6 - a6).orthogonal().normalized()
			for i6:int in 40:
				var at6:Vector2 = a6.lerp(b6,_rng.randf())
				var side6:float = 1.0 if _rng.randf() < 0.5 else -1.0
				_bits.shard(at6,n6 * side6 * _rng.randf_range(120,520) + (b6 - a6).normalized() * _rng.randf_range(-80,80),_rng.randf_range(0.5,1.0),_rng.randf_range(3.0,8.0),Color(0.1,0.1,0.12),_rng,260.0)
			# 空间裂纹：从斩线斜向崩开的锯齿短裂缝
			for i8:int in 14:
				var u8:float = _rng.randf_range(0.05,0.95)
				var sd8:float = 1.0 if i8 % 2 == 0 else -1.0
				var dir8:Vector2 = (n6 * sd8 + (b6 - a6).normalized() * _rng.randf_range(-0.9,0.9)).normalized()
				var st8:Vector2 = a6.lerp(b6,u8)
				_cache.append([V.bolt(_rng,st8,st8 + dir8 * _rng.randf_range(50.0,170.0),10.0,3),_rng.randf_range(0.0,0.1)])
		"black_flash":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",70.0)
			_bits.shards(_rng,p8,12,r8 * 3.0,r8 * 7.0,0.5,r8 * 0.08,Color(0.02,0.0,0.0),200.0)
			_bits.sparks(_rng,p8,18,r8 * 4.0,r8 * 10.0,0.3,r8 * 0.4,Color(1.0,0.1,0.16))
		"thunder":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",70.0)
			_bits.sparks(_rng,p9,18,r9 * 3.0,r9 * 7.0,0.3,r9 * 0.3,Color(0.75,0.9,1.0))
		"teleport":
			var b10:Vector2 = _v("b")
			_bits.sparks(_rng,b10,10,140.0,300.0,0.2,10.0,Color(0.7,0.95,1.0))
		"wheel_turn":
			_bits.sparks(_rng,_v("pos"),12,90.0,220.0,0.35,10.0,Color(1.0,0.85,0.4))
		"shockwave":
			var p12:Vector2 = _v("pos")
			var r12:float = _f("radius",200.0)
			if r12 >= 60.0:
				_bits.dust(_rng,p12,int(clampf(r12 / 18.0,6,14)),r12 * 0.85,r12 * 1.0,clampf(r12 * 0.05,4.0,12.0),Color(0.84,0.82,0.8),Color(0.5,0.47,0.46))
				_bits.shards(_rng,p12,int(clampf(r12 / 20.0,4,14)),r12 * 1.5,r12 * 3.0,0.6,clampf(r12 * 0.02,2.5,6.0),Color(0.18,0.16,0.2),300.0)
		"heal":
			var p13:Vector2 = _v("pos")
			var r13:float = _f("radius",30.0)
			for i13:int in 10:
				var a13:float = _rng.randf() * TAU
				_bits.plus(p13 + Vector2.from_angle(a13) * r13 * _rng.randf_range(0.3,1.1),Vector2(cos(a13) * 12.0,-_rng.randf_range(40,90)),_rng.randf_range(0.5,0.9),_rng.randf_range(3.0,5.0),Color(0.45,1.0,0.55))

# ================================================================= 每帧面片编排
func _quads() -> void:
	var ts:float = _ts()
	match kind:
		"ripple":
			# 无下限：两道青色硬边环向接触点收缩，中心一颗小爆闪。
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",24.0)
			for i:int in 2:
				var kk:float = _sk(i * 0.06,i * 0.06 + 0.22)
				if kk > 0.0 and kk < 1.0:
					q_ring("rip%d" % i,p,lerpf(r * 1.6,r * 0.35,V.out_cubic(kk)),lerpf(2.0,4.0,kk),"cyan",1.0,0.3,8.0,1.5)
			var fk:float = _sk(0.0,0.12)
			if fk < 1.0: q_burst("star",p,r * (0.6 + 0.5 * fk),"cyan",1.0,8.0,0.25,24.0,0.0,1.5)
		"shockwave":
			var p2:Vector2 = _v("pos")
			var r2:float = _f("radius",200.0)
			var c2:Color = _c("color",Color(0.6,0.9,1.0))
			var pal2:String = _pal_for(c2)
			var e:float = V.out_expo(_sk(0.0,life * 0.7))
			var th:float = lerpf(maxf(6.0,r2 * 0.12),1.5,e)
			if e < 1.0: q_ring("ring",p2,r2 * (0.15 + 0.85 * e),th,pal2,1.0,0.35 + 0.4 * e,12.0,2.0)
			if r2 >= 60.0:
				var lk:float = _sk(0.0,0.2)
				if lk < 1.0: q_lines("lines",p2,r2 * 1.6,Color(0.02,0.02,0.05,0.85),1.0,0.45 + 0.2 * lk,60.0,0.45)
		"red_burst":
			# 赫：白芯红边的尖刺爆闪（两拍撑满、抖两拍、收缩）→ 白色冲击环 → 地面裂痕。
			var p3:Vector2 = _v("pos")
			var r3:float = _f("radius",80.0)
			var grow:float = _sk(0.0,0.084)
			var shrink:float = _sk(0.2,0.42)
			if shrink < 1.0:
				q_burst("star",p3,r3 * (0.7 + 0.9 * grow) * (1.0 - shrink * 0.85),"red",1.0,14.0,0.5,24.0,0.0,3.0,Vector2(0.16,0.2))
				q_orb("core",p3,r3 * 0.42 * (1.0 - shrink),"red",1.0,0.12,0.25,8.0,9.0,0.0,0.6,2.5,Vector2(0.18,0.3))
			var rk:float = _sk(0.04,0.5)
			if rk > 0.0 and rk < 1.0:
				q_ring("ring",p3,r3 * (0.6 + 2.2 * V.out_cubic(rk)),lerpf(r3 * 0.14,1.5,rk),"red",1.0,0.3 + 0.6 * rk,10.0,2.0,Vector2(0.25,0.4))
			var lk3:float = _sk(0.0,0.25)
			if lk3 < 1.0: q_lines("lines",p3,r3 * 5.0,Color(0.03,0.0,0.0,0.9),1.0,0.2 + 0.1 * lk3,80.0,0.55)
			var ck:float = _sk(0.02,0.1)
			q_crack("crack",p3,r3 * 1.5,9.0,4.0,Color(0.45,0.06,0.04,0.8),Color(0.05,0.0,0.0),ck * (1.0 - _sk(life * 0.6,life)))
		"purple_beam":
			_quads_purple()
		"slash":
			# 解：一拍划过的白刃（黑描边），随后从起点收尾。
			var a4:Vector2 = _v("a")
			var b4:Vector2 = _v("b")
			var w4:float = maxf(_f("width",3.0),2.0)
			var col:Color = _c("color",Color.WHITE)
			var rv:float = _sk(0.0,0.05)
			var tl:float = V.in_cubic(_sk(0.06,0.3))
			var bend:float = float(_cache[0]) * a4.distance_to(b4) * 0.07 if not _cache.is_empty() else 0.0
			q_slash("blade",a4,b4,w4 * 1.4,_pal_for(col,"white"),1.0,rv,tl,bend,1.5,0.35)
			# 超出刃长的细切线（一拍）
			if _sk(0.0,0.084) < 1.0:
				var d4:Vector2 = (b4 - a4)
				q_slash("hair",a4 - d4 * 0.25,b4 + d4 * 0.25,1.2,"white",1.0,1.0,0.0,bend * 1.4,1.0,0.5)
		"cleave":
			var p5:Vector2 = _v("pos")
			var r5:float = _f("radius",34.0)
			for i5:int in _cache.size():
				var c5:Array = _cache[i5]
				var st:float = float(c5[2])
				var kk5:float = _sk(st,st + 0.05)
				var tl5:float = _sk(st + 0.08,st + 0.3)
				if kk5 <= 0.0 or tl5 >= 1.0: continue
				var d5:Vector2 = Vector2.from_angle(float(c5[0]))
				var off:Vector2 = d5.orthogonal() * float(c5[3])
				var half:float = r5 * float(c5[1])
				q_slash("c%d" % i5,p5 + off - d5 * half,p5 + off + d5 * half,3.0,"blood",1.0,kk5,V.in_cubic(tl5),float(c5[4]) * r5 * 0.15,1.5,0.4)
			var bk:float = _sk(0.3,0.44)
			if bk > 0.0 and bk < 1.0: q_burst("star",p5,r5 * (1.2 + 0.8 * bk),"blood",1.0,10.0,0.3,24.0,0.0,2.5)
		"web":
			var p6:Vector2 = _v("pos")
			var r6:float = _f("radius",150.0)
			var ck6:float = _sk(0.0,0.084)
			var fade6:float = 1.0 - _sk(life * 0.55,life)
			q_crack("crack",p6,r6 * 1.08,14.0,maxf(3.0,r6 * 0.025),Color(1.0,0.25,0.3),Color(0.02,0.0,0.0),ck6 * fade6,0.3)
			var sk6:float = _sk(0.0,0.2)
			if sk6 < 1.0:
				var angs:Array = _cache[0]
				for i6:int in angs.size():
					var d6:Vector2 = Vector2.from_angle(float(angs[i6]))
					q_slash("s%d" % i6,p6 + d6 * r6 * 0.1,p6 + d6 * r6 * 1.05,2.5,"white",1.0,_sk(0.0,0.05),V.in_cubic(sk6),0.0,1.5,0.4)
			var bk6:float = _sk(0.0,0.12)
			if bk6 < 1.0: q_burst("star",p6,r6 * 0.45 * (0.6 + bk6),"white",1.0,12.0,0.3,24.0,0.0,2.5)
		"fuga_burst":
			_quads_fuga()
		"world_slash":
			_quads_world()
		"black_flash":
			# 黑闪：黑芯红边的尖刺爆闪 + 红色细环；黑色闪电在 _draw_top 里画。
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",70.0)
			var g8:float = _sk(0.0,0.042)
			var s8:float = _sk(0.16,0.34)
			if s8 < 1.0:
				q_burst("star",p8,r8 * (0.9 + 0.7 * g8) * (1.0 - 0.8 * s8),"black",1.0,16.0,0.3,24.0,0.0,3.0,Vector2(0.22,0.5))
			var rk8:float = _sk(0.03,0.35)
			if rk8 > 0.0 and rk8 < 1.0: q_ring("ring",p8,r8 * (0.8 + 1.8 * V.out_cubic(rk8)),lerpf(8.0,1.5,rk8),"black",1.0,0.5,14.0,2.0,Vector2(0.4,0.3))
			var lk8:float = _sk(0.0,0.3)
			if lk8 < 1.0: q_lines("lines",p8,r8 * 6.0,Color(0.0,0.0,0.0,0.95),1.0,0.18 + 0.12 * lk8,90.0,0.6)
		"thunder":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",70.0)
			var g9:float = _sk(0.0,0.2)
			if g9 < 1.0: q_burst("star",p9,r9 * (0.8 + 0.4 * g9) * (1.0 - g9 * 0.6),"cyan",1.0,10.0,0.35,24.0,0.0,2.5)
			var rk9:float = _sk(0.02,0.35)
			if rk9 > 0.0 and rk9 < 1.0: q_ring("ring",p9,r9 * (0.5 + 1.2 * V.out_cubic(rk9)),lerpf(6.0,1.5,rk9),"cyan",1.0,0.4,10.0,2.0)
		"teleport":
			var a10:Vector2 = _v("a")
			var b10:Vector2 = _v("b")
			var sk10:float = _sk(0.0,0.2)
			if sk10 < 1.0 and a10.distance_to(b10) > 8.0:
				q_slash("streak",a10,b10,5.0,"cyan",1.0,1.0,V.in_cubic(sk10),0.0,1.5,0.4)
			var bk10:float = _sk(0.0,0.125)
			if bk10 < 1.0: q_burst("star",b10,18.0 + 14.0 * bk10,"cyan",1.0,8.0,0.3,24.0,0.0,1.5)
			var rk10:float = _sk(0.0,0.3)
			if rk10 < 1.0: q_ring("ring",a10,10.0 + 22.0 * V.out_cubic(rk10),lerpf(4.0,1.0,rk10),"cyan",1.0,0.5,8.0,1.2)
		"wheel_turn":
			var p11:Vector2 = _v("pos")
			var r11:float = _f("radius",22.0) * 2.4
			var rk11:float = _sk(0.12,0.5)
			if rk11 > 0.0 and rk11 < 1.0: q_ring("ring",p11,r11 * (1.0 + 1.2 * V.out_cubic(rk11)),lerpf(5.0,1.0,rk11),"gold",1.0,0.3,8.0,1.5)
			var lk11:float = _sk(0.12,0.32)
			if lk11 > 0.0 and lk11 < 1.0: q_lines("lines",p11,r11 * 3.0,Color(1.0,0.85,0.35,0.9),1.0,0.45,48.0,0.4)
		"heal":
			var p14:Vector2 = _v("pos")
			var r14:float = _f("radius",30.0)
			for i14:int in 2:
				var kk14:float = _sk(i14 * 0.15,i14 * 0.15 + 0.4)
				if kk14 > 0.0 and kk14 < 1.0: q_ring("r%d" % i14,p14,r14 * (0.5 + 0.8 * kk14),lerpf(3.0,1.0,kk14),"green",1.0 - kk14 * 0.5,0.3,8.0,1.2)

## 茈：蓄力点白色爆闪 → 巨大光束（白芯紫边墨线）从 a 推到 b，光头为带电弧的紫球 → 尾部由近及远碎散。
func _quads_purple() -> void:
	var a:Vector2 = _v("a")
	var b:Vector2 = _v("b")
	var w:float = _f("width",90.0)
	var L:float = a.distance_to(b)
	var d:Vector2 = (b - a).normalized()
	var ts:float = _ts()
	var travel:float = clampf(life * 0.32,0.18,0.3)
	var head:float = V.out_cubic(_sk(0.0,travel))
	var tail:float = V.in_cubic(_sk(life * 0.45,life * 0.95))
	var thin:float = 1.0 - 0.45 * _sk(life * 0.4,life * 0.9)
	var hw:float = w * 0.62 * thin * (1.0 + 0.06 * sin(ts * 60.0))
	if tail < 1.0:
		q_beam("beam",a,b,hw,"purple",1.0,maxf(head,0.02),tail,0.1,3.0,Vector2(0.22,0.3),9.0)
	var hp:Vector2 = a.lerp(b,head)
	if head < 1.0 or _sk(travel,travel + 0.15) < 1.0:
		q_orb("head",hp,w * 0.95,"purple",1.0,0.1,0.35,10.0,12.0,0.0,0.9,3.0,Vector2(0.2,0.3))
	var fk:float = _sk(0.0,0.125)
	if fk < 1.0:
		q_burst("muzzle",a,w * (1.2 + 0.8 * fk),"purple",1.0,14.0,0.35,24.0,d.angle(),3.0,Vector2(0.25,0.35))
	var lk:float = _sk(0.0,travel + 0.1)
	if lk < 1.0: q_lines("lines",a,w * 7.0,Color(0.04,0.0,0.08,0.95),1.0,0.12,90.0,0.55)

## 開（竈）：命中点白黄尖刺爆闪 → 火球膨胀 → 留下向上翻卷的火柱，逐渐矮下去。
func _quads_fuga() -> void:
	var p:Vector2 = _v("pos")
	var r:float = _f("radius",160.0)
	var g:float = V.out_cubic(_sk(0.0,0.16))
	var ball_fade:float = _sk(0.2,0.45)
	if ball_fade < 1.0:
		q_fire("ball",p,r * (0.5 + 0.75 * g),1.0 - ball_fade * 0.7,1.0,1.0,2.6,2.0,0.07)
	var pk:float = _sk(0.12,0.3)
	var pend:float = _sk(life * 0.45,life)
	if pk > 0.0 and pend < 1.0:
		q_fire("pillar",p + Vector2(0,-r * 0.35),r * 1.05,(0.55 + 0.45 * pk) * (1.0 - pend),0.0,1.0,3.2,2.4,0.07)
	var bk:float = _sk(0.0,0.14)
	if bk < 1.0: q_burst("star",p,r * (0.7 + 0.6 * bk),"fire",1.0,14.0,0.35,24.0,0.0,3.0)
	var rk:float = _sk(0.03,0.45)
	if rk > 0.0 and rk < 1.0: q_ring("ring",p,r * (0.6 + 1.1 * V.out_cubic(rk)),lerpf(r * 0.12,2.0,rk),"fire",1.0,0.4,12.0,2.5)
	var lk:float = _sk(0.0,0.3)
	if lk < 1.0: q_lines("lines",p,r * 3.5,Color(0.12,0.02,0.0,0.9),1.0,0.28,80.0,0.5)

## 世界斩：先一拍贯穿全屏的黑线，冲击帧中白刃撑开，随后收成细线并残留空间裂纹。
func _quads_world() -> void:
	var a:Vector2 = _v("a")
	var b:Vector2 = _v("b")
	var w:float = _f("width",70.0)
	var open:float = _sk(0.042,0.125)
	var close:float = _sk(0.2,life * 0.6)
	if open > 0.0 and close < 1.0:
		var thick:float = w * 0.35 * V.out_cubic(open) * (1.0 - 0.85 * V.in_cubic(close))
		q_slash("blade",a,b,maxf(thick,1.5),"white",1.0,1.0,0.0,0.0,2.5,0.45)
	var fk:float = _sk(0.042,0.2)
	if fk > 0.0 and fk < 1.0:
		var mid:Vector2 = a.lerp(b,0.5)
		q_lines("lines",mid,a.distance_to(b) * 0.6,Color(0.0,0.0,0.0,0.9),1.0,0.1,120.0,0.5)

## 按主色挑一套调色板。
func _pal_for(c:Color,fallback:String = "cyan") -> String:
	if c.v < 0.25: return "curse" if c.h > 0.7 and c.h < 0.95 and c.s > 0.3 else "black"
	if c.s < 0.2: return fallback if fallback != "cyan" else "white"
	var h:float = c.h
	if h < 0.05 or h > 0.93: return "red"
	if h < 0.14: return "fire"
	if h < 0.2: return "gold"
	if h < 0.45: return "green"
	if h < 0.58: return "cyan"
	if h < 0.7: return "blue"
	return "purple"

# ================================================================= CPU 绘制：地面层（本节点）
func _draw() -> void:
	var fade:float = 1.0 - _sk(life * 0.6,life)
	match kind:
		"purple_beam":
			# 光束犁出的沟壑边线（墨线）
			var shown:float = V.out_cubic(_sk(0.0,clampf(life * 0.32,0.18,0.3)))
			for i:int in mini(_cache.size(),2):
				var pts:PackedVector2Array = _cache[i]
				var n:int = int(pts.size() * shown)
				if n >= 2: draw_polyline(pts.slice(0,n),Color(0.08,0.02,0.12,0.9 * fade),3.0,true)
		"web":
			if _cache.size() >= 2:
				var ck:float = _sk(0.0,0.1)
				for ringpts:Variant in _cache[1]:
					var pts2:PackedVector2Array = ringpts
					if ck > 0.0:
						draw_polyline(pts2,Color(0.02,0.0,0.0,0.85 * fade),3.5,true)
						draw_polyline(pts2,Color(1.0,0.3,0.32,0.8 * fade),1.2,true)
		"world_slash":
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			# 第一拍：贯穿全屏的黑线
			if _ts() < 0.042:
				draw_line(a,b,Color(0,0,0,1),3.0,true)
			# 残留的空间裂纹
			var ck2:float = _sk(0.08,0.16)
			for i2:int in range(0,_cache.size()):
				var c:Array = _cache[i2]
				var pts3:PackedVector2Array = c[0]
				var appear:float = _sk(0.08 + float(c[1]),0.16 + float(c[1]))
				if appear <= 0.0: continue
				var n3:int = maxi(2,int(pts3.size() * appear))
				draw_polyline(pts3.slice(0,n3),Color(0,0,0,0.9 * fade),4.0,true)
				draw_polyline(pts3.slice(0,n3),Color(1,1,1,0.85 * fade * ck2),1.3,true)
			var hold:float = 1.0 - _sk(life * 0.5,life)
			if _ts() >= 0.042 and hold > 0.0:
				draw_line(a,b,Color(0,0,0,0.9 * hold),2.0,true)
				draw_line(a,b,Color(1,1,1,0.9 * hold),0.8,true)
	_bits.draw_ground(self)

# ================================================================= CPU 绘制：顶层（碎片、闪电、文字）
func _draw_top() -> void:
	var ci:CanvasItem = _top
	match kind:
		"black_flash":
			# 黑色闪电（红色外描边），每 1/12 秒重掷一次形状。
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",70.0)
			var on:float = 1.0 - _sk(0.3,0.42)
			if on > 0.0:
				var brng:RandomNumberGenerator = RandomNumberGenerator.new()
				brng.seed = _seed + int(t * 12.0) * 131
				for i:int in 9:
					var ang:float = brng.randf() * TAU
					var blen:float = r * brng.randf_range(1.2,2.6) * (0.6 + 0.4 * _sk(0.0,0.08))
					var pts:PackedVector2Array = V.bolt(brng,p + Vector2.from_angle(ang) * r * 0.2,p + Vector2.from_angle(ang + brng.randf_range(-0.3,0.3)) * blen,r * 0.16,4)
					var w:float = brng.randf_range(3.0,6.0) * on
					ci.draw_polyline(pts,Color(1.0,0.08,0.14,on),w + 4.0,true)
					ci.draw_polyline(pts,Color(0.0,0.0,0.0,on),w,true)
		"thunder":
			var p2:Vector2 = _v("pos")
			var r2:float = _f("radius",70.0)
			var on2:float = 1.0 - _sk(0.18,0.3)
			if on2 > 0.0:
				var brng2:RandomNumberGenerator = RandomNumberGenerator.new()
				brng2.seed = _seed + int(t * 12.0) * 97
				for i2:int in 6:
					var ang2:float = brng2.randf() * TAU
					var pts2:PackedVector2Array = V.bolt(brng2,p2,p2 + Vector2.from_angle(ang2) * r2 * brng2.randf_range(1.0,2.0),r2 * 0.14,4)
					ci.draw_polyline(pts2,Color(0.0,0.02,0.08,on2),6.0,true)
					ci.draw_polyline(pts2,Color(0.55,0.85,1.0,on2),3.5,true)
					ci.draw_polyline(pts2,Color(1,1,1,on2),1.4,true)
		"purple_beam":
			# 光头周围的紫白闪电
			var a3:Vector2 = _v("a")
			var b3:Vector2 = _v("b")
			var w3:float = _f("width",90.0)
			var travel:float = clampf(life * 0.32,0.18,0.3)
			var head:float = V.out_cubic(_sk(0.0,travel))
			if _ts() < travel + 0.15:
				var hp:Vector2 = a3.lerp(b3,head)
				var brng3:RandomNumberGenerator = RandomNumberGenerator.new()
				brng3.seed = _seed + int(t * 12.0) * 53
				for i3:int in 6:
					var ang3:float = brng3.randf() * TAU
					var pts3:PackedVector2Array = V.bolt(brng3,hp,hp + Vector2.from_angle(ang3) * w3 * brng3.randf_range(0.9,1.6),w3 * 0.1,3)
					ci.draw_polyline(pts3,Color(0.1,0.0,0.18,1.0),5.0,true)
					ci.draw_polyline(pts3,Color(1.0,0.9,1.0,1.0),2.0,true)
		"wheel_turn":
			var p12:Vector2 = _v("pos")
			var r12:float = _f("radius",22.0) * 2.4
			var appear:float = V.out_back(_sk(0.0,0.17))
			var fade12:float = 1.0 - _sk(life * 0.65,life)
			# 转动一格（1/8 圈），按拍“咔、咔、咔”三段转完
			var turn:float = floorf(_sk(0.12,0.36) * 3.0) / 3.0
			if fade12 > 0.0: V.dharma_wheel(ci,p12,r12 * appear,turn * TAU / 8.0,fade12)
		"text":
			_draw_text(ci)
	_bits.draw_top(ci)

# ================================================================= 文字
func _draw_text(ci:CanvasItem) -> void:
	var p:Vector2 = _v("pos")
	var text:String = str(data.get("text",""))
	var size:int = int(data.get("size",34))
	var c:Color = _c("color",Color.WHITE)
	var font:Font = ThemeDB.fallback_font
	var k:float = clampf(t / life,0.0,1.0)
	var big:bool = size >= 30
	var alpha:float = clampf(minf(1.0,t * 12.0) * minf(1.0,(life - t) * 3.0),0.0,1.0)
	var width:float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	var pop:float = lerpf(1.5,1.0,floorf(minf(1.0,t / 0.125) * 3.0) / 3.0)
	var rise:float = 0.0 if big else -14.0 * V.out_cubic(k)
	var origin:Vector2 = p + Vector2(0,rise)
	if big:
		# 领域名：毛笔墨带自左向右刷开，文字逐字砸下。
		var brush:float = V.out_cubic(t / 0.3)
		var band_w:float = (width + size * 2.0) * brush
		var left:Vector2 = origin + Vector2(-(width + size * 2.0) * 0.5,0.0)
		var pts:PackedVector2Array = []
		var steps:int = 24
		for i:int in steps + 1:
			var u:float = float(i) / steps
			pts.append(left + Vector2(band_w * u,-size * 0.62 * (0.85 + 0.15 * sin(u * 17.0 + _seed))))
		for i2:int in range(steps,-1,-1):
			var u2:float = float(i2) / steps
			pts.append(left + Vector2(band_w * u2,size * 0.62 * (0.85 + 0.15 * cos(u2 * 13.0 + _seed))))
		if band_w > 2.0: ci.draw_colored_polygon(pts,Color(0.02,0.0,0.02,0.85 * alpha))
		var shown:int = int(ceil(text.length() * V.seg(t,0.1,0.1 + 0.05 * text.length())))
		var x:float = -width * 0.5
		for ch:int in text.length():
			var cs:String = text.substr(ch,1)
			var cw:float = font.get_string_size(cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
			if ch < shown:
				var ct:float = clampf((t - 0.1 - 0.05 * ch) / 0.125,0.0,1.0)
				var scl:float = lerpf(1.8,1.0,floorf(ct * 3.0) / 3.0)
				var at:Vector2 = origin + Vector2(x,size * 0.35)
				ci.draw_set_transform(at + Vector2(cw * 0.5,-size * 0.35),0.0,Vector2(scl,scl))
				ci.draw_string_outline(font,Vector2(-cw * 0.5,size * 0.35),cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size,JJK_FONT_OUTLINE,Color(0,0,0,0.95 * alpha))
				ci.draw_string(font,Vector2(-cw * 0.5,size * 0.35),cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(c,alpha))
				ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
			x += cw
		return
	ci.draw_set_transform(origin,0.0,Vector2(pop,pop))
	var at2:Vector2 = Vector2(-width * 0.5,size * 0.35)
	ci.draw_string_outline(font,at2 + Vector2(2,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,6,Color(0,0,0,0.6 * alpha))
	ci.draw_string_outline(font,at2,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,5,Color(0,0,0,0.95 * alpha))
	ci.draw_string(font,at2,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(c,alpha))
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

# ================================================================= 演出：冲击帧 / 集中线 / 扭曲 / 震屏 / 顿帧 / 推镜
func _juice() -> void:
	match kind:
		"red_burst":
			var r:float = _f("radius",80.0)
			var big:bool = r >= 90.0
			V.impact(self,_v("pos"),"red" if big else "hit",{"lines":0.7 if big else 0.0},0.3)
			V.distort(self,0,_v("pos"),Vector2.ONE * r * 5.0,0.4,30.0)
			V.shake(self,9.0 if big else 6.0)
			V.hitstop(self,0.7 if big else 0.4,_v("pos"))
			V.zoom_punch(self,_v("pos"),0.4)
		"purple_beam":
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			var w:float = _f("width",90.0)
			var big2:float = clampf(w / 90.0,0.6,2.0)
			V.impact(self,a,"purple",{"lines":0.9,"lines_color":Color(0.05,0.0,0.1),"vignette":0.35,"flash":Color(1,0.95,1,0.5),"flash_time":0.08},life * 0.5)
			V.distort(self,0,a,Vector2.ONE * w * 7.0,0.6,40.0 * big2)
			V.distort(self,2,a.lerp(b,0.5),Vector2(a.distance_to(b),w * 2.4),life,7.0 * big2,{"rot_angle":(b - a).angle()})
			V.shake(self,12.0 * big2,(b - a))
			V.hitstop(self,1.0,a)
			V.zoom_punch(self,a,0.8)
		"cleave":
			V.impact(self,_v("pos"),"cut")
			V.shake(self,4.0)
		"web":
			V.impact(self,_v("pos"),"heavy",{"lines":0.6},0.3)
			V.distort(self,0,_v("pos"),Vector2.ONE * _f("radius",150.0) * 2.6,0.5,16.0)
			V.shake(self,7.0)
			V.hitstop(self,0.5,_v("pos"))
		"fuga_burst":
			var r5:float = _f("radius",160.0)
			V.impact(self,_v("pos"),"fire",{"lines":0.8,"lines_color":Color(0.15,0.03,0.0),"tint":Color(1.0,0.6,0.3,0.2),"vignette":0.3},0.7)
			V.distort(self,0,_v("pos"),Vector2.ONE * r5 * 5.0,0.6,42.0)
			V.shake(self,14.0)
			V.hitstop(self,0.9,_v("pos"))
			V.zoom_punch(self,_v("pos"),0.7)
		"world_slash":
			var a6:Vector2 = _v("a")
			var b6:Vector2 = _v("b")
			var mid:Vector2 = a6.lerp(b6,0.5)
			V.impact(self,mid,"world",{"desat":0.5},0.9)
			V.distort(self,2,mid,Vector2(a6.distance_to(b6),_f("width",70.0) * 4.0),life,26.0,{"rot_angle":(b6 - a6).angle()})
			V.shake(self,20.0,(b6 - a6).orthogonal())
			V.hitstop(self,1.0,mid)
			V.zoom_punch(self,mid,0.6)
		"black_flash":
			var p8:Vector2 = _v("pos")
			V.impact(self,p8,"black_flash",{"lines":0.9,"aberration":0.008},0.4)
			V.distort(self,0,p8,Vector2.ONE * _f("radius",70.0) * 4.5,0.4,32.0)
			V.shake(self,10.0)
			V.hitstop(self,1.0,p8)
			V.zoom_punch(self,p8,0.9)
		"thunder":
			var p10:Vector2 = _v("pos")
			V.impact(self,p10,"hit")
			V.shake(self,6.0)
		"teleport":
			V.distort(self,0,_v("b"),Vector2.ONE * 120.0,0.3,14.0)
		"shockwave":
			var r13:float = _f("radius",200.0)
			if r13 >= 60.0: V.distort(self,0,_v("pos"),Vector2.ONE * r13 * 2.3,life,16.0 + r13 * 0.04)
		"wheel_turn":
			V.distort(self,0,_v("pos"),Vector2.ONE * 140.0,0.4,10.0)

# ================================================================= 实心描边小图形（碎石、火星、血滴、烟团）
## kind: 0 碎石（黑描边多边形，旋转、重力）1 火星（带墨边的尖梭线）2 血滴 3 烟团（赛璐璐两阶 + 描边，原地膨胀）4 余烬 5 十字光点
class Bits extends RefCounted:
	var p:PackedVector2Array = []
	var v:PackedVector2Array = []
	var age:PackedFloat32Array = []
	var life:PackedFloat32Array = []
	var size:PackedFloat32Array = []
	var grav:PackedFloat32Array = []
	var rot:PackedFloat32Array = []
	var col:PackedColorArray = []
	var col2:PackedColorArray = []
	var kind:PackedByteArray = []
	var alive:int = 0

	func add(pos:Vector2,vel:Vector2,lifetime:float,sz:float,c:Color,k:int,g:float = 0.0,r:float = 0.0,c2:Color = Color(0,0,0)) -> void:
		p.append(pos); v.append(vel); age.append(0.0); life.append(lifetime); size.append(sz); col.append(c); col2.append(c2); kind.append(k); grav.append(g); rot.append(r)
		alive += 1

	func shard(pos:Vector2,vel:Vector2,lifetime:float,sz:float,c:Color,rng:RandomNumberGenerator,g:float) -> void:
		add(pos,vel,lifetime,sz,c,0,g,rng.randf() * TAU)

	func shards(rng:RandomNumberGenerator,pos:Vector2,n:int,vmin:float,vmax:float,lifetime:float,sz:float,c:Color,g:float) -> void:
		for i:int in n:
			shard(pos,Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(vmin,vmax),lifetime * rng.randf_range(0.6,1.2),sz * rng.randf_range(0.6,1.4),c,rng,g)

	func sparks(rng:RandomNumberGenerator,pos:Vector2,n:int,vmin:float,vmax:float,lifetime:float,sz:float,c:Color,dir:float = 0.0,spread:float = TAU) -> void:
		for i:int in n:
			var a:float = dir + rng.randf_range(-spread * 0.5,spread * 0.5)
			add(pos,Vector2.from_angle(a) * rng.randf_range(vmin,vmax),lifetime * rng.randf_range(0.6,1.2),sz * rng.randf_range(0.6,1.3),c,1)

	func drop(pos:Vector2,vel:Vector2,lifetime:float,sz:float,c:Color,g:float) -> void:
		add(pos,vel,lifetime,sz,c,2,g)

	func dust(rng:RandomNumberGenerator,pos:Vector2,n:int,dmin:float,dmax:float,sz:float,light:Color,shade:Color) -> void:
		for i:int in n:
			var a:float = TAU * i / n + rng.randf_range(-0.3,0.3)
			var at:Vector2 = pos + Vector2.from_angle(a) * rng.randf_range(dmin,dmax)
			add(at,Vector2.from_angle(a) * rng.randf_range(20,60) + Vector2(0,-10),rng.randf_range(0.5,0.8),sz * rng.randf_range(0.7,1.3),light,3,-10.0,rng.randf() * TAU,shade)

	func embers(rng:RandomNumberGenerator,pos:Vector2,n:int,vmin:float,vmax:float,lifetime:float,sz:float) -> void:
		for i:int in n:
			var a:float = -PI * 0.5 + rng.randf_range(-1.6,1.6)
			add(pos,Vector2.from_angle(a) * rng.randf_range(vmin,vmax),lifetime * rng.randf_range(0.5,1.2),sz * rng.randf_range(0.6,1.4),Color(1.0,rng.randf_range(0.55,0.9),0.2),4,-40.0)

	func plus(pos:Vector2,vel:Vector2,lifetime:float,sz:float,c:Color) -> void:
		add(pos,vel,lifetime,sz,c,5)

	func step(dt:float) -> void:
		alive = 0
		for i:int in p.size():
			if age[i] >= life[i]: continue
			age[i] += dt
			var vel:Vector2 = v[i]
			var drag:float = 2.5 if kind[i] == 3 else (4.0 if kind[i] == 1 else 1.2)
			vel *= exp(-drag * dt)
			vel.y += grav[i] * dt
			v[i] = vel
			p[i] += vel * dt
			rot[i] += dt * (9.0 if kind[i] == 0 else 0.0)
			alive += 1

	## 地面层：烟团（在碎片之下）。每团三个圆合成一个轮廓：先整体描边，再画暗面，最后左上亮面。
	func draw_ground(ci:CanvasItem) -> void:
		for pass_i:int in 3:
			for i:int in p.size():
				if age[i] >= life[i] or kind[i] != 3: continue
				var k:float = age[i] / life[i]
				var s:float = size[i] * (0.6 + 0.8 * sqrt(k)) * (1.0 - 0.7 * maxf(0.0,k - 0.55) / 0.45)
				if s < 0.8: continue
				for j:int in 3:
					var off:Vector2 = Vector2.from_angle(rot[i] + j * 2.1) * s * 0.55
					var rr:float = s * (0.75 + 0.12 * j)
					match pass_i:
						0: ci.draw_circle(p[i] + off,rr + 1.5,Color(0.12,0.11,0.13,1.0))
						1: ci.draw_circle(p[i] + off,rr,col2[i])
						2: ci.draw_circle(p[i] + off + Vector2(-0.3,-0.35) * rr,rr * 0.7,col[i])

	func draw_top(ci:CanvasItem) -> void:
		for i:int in p.size():
			if age[i] >= life[i]: continue
			var k:float = age[i] / life[i]
			var c:Color = col[i]
			match kind[i]:
				0:
					var s:float = size[i] * (1.0 - k * 0.5)
					var d:Vector2 = Vector2.from_angle(rot[i])
					var tri:PackedVector2Array = [p[i] + d * s,p[i] + d.rotated(2.3) * s * 0.7,p[i] + d.rotated(-2.1) * s * 0.8]
					var tri_o:PackedVector2Array = [p[i] + d * (s + 1.5),p[i] + d.rotated(2.3) * (s * 0.7 + 1.5),p[i] + d.rotated(-2.1) * (s * 0.8 + 1.5)]
					ci.draw_colored_polygon(tri_o,Color(0,0,0,1))
					ci.draw_colored_polygon(tri,c)
				1:
					var tail:Vector2 = v[i] * 0.05
					var w:float = size[i] * 0.22 * (1.0 - k)
					if w < 0.3 or tail.length() < 1.0: continue
					ci.draw_line(p[i] - tail,p[i],Color(0,0,0,1),w + 2.0,true)
					ci.draw_line(p[i] - tail,p[i],c,w,true)
					ci.draw_line(p[i] - tail * 0.5,p[i],Color(1,1,1,1),maxf(0.6,w * 0.4),true)
				2:
					var s2:float = size[i]
					ci.draw_circle(p[i],s2 + 1.0,Color(0,0,0,1.0 - k))
					ci.draw_circle(p[i],s2,Color(c,1.0 - k * 0.5))
				4:
					var s4:float = size[i] * (1.0 - k)
					if s4 < 0.5: continue
					ci.draw_circle(p[i],s4 + 1.2,Color(0.2,0.03,0.0,1.0))
					ci.draw_circle(p[i],s4,c)
				5:
					var s5:float = size[i] * (1.0 - k * 0.6)
					var a5:float = 1.0 - k
					ci.draw_line(p[i] + Vector2(-s5,0),p[i] + Vector2(s5,0),Color(0,0.15,0.05,a5),3.2,true)
					ci.draw_line(p[i] + Vector2(0,-s5),p[i] + Vector2(0,s5),Color(0,0.15,0.05,a5),3.2,true)
					ci.draw_line(p[i] + Vector2(-s5,0),p[i] + Vector2(s5,0),Color(c,a5),1.6,true)
					ci.draw_line(p[i] + Vector2(0,-s5),p[i] + Vector2(0,s5),Color(c,a5),1.6,true)
