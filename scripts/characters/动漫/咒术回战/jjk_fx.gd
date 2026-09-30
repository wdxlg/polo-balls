extends Node2D
## 咒术回战一次性视觉特效（纯视觉，不结算伤害）。坐标全部为世界坐标。
## 由角色 RPC 在各端本地生成，随机种子随包下发，各端动画一致。
## 分层：本节点（普通混合：暗部、烟、实体）+ AddLayer（叠加：光、电、粒子）+ TopLayer（普通混合，
## 压在光之上的黑色部分）+ 着色器面片（jjk_fxshader：能量球/光束/冲击环/赛璐璐火焰/空间裂缝/集中线/卡通烟）。
const V = preload("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd")
const Q = V.Q
const JJK_FONT_OUTLINE:int = 8

var kind:String = ""
var data:Dictionary = {}
var life:float = 0.5
var t:float = 0.0
var _seed:int = 0
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()
var _drng:RandomNumberGenerator = RandomNumberGenerator.new()
var _parts:V.Parts = V.Parts.new()
var _add:Node2D
var _top:Node2D
var _emit_acc:float = 0.0
var _cache:Array = []
var _cache2:Array = []
var _qs:Dictionary = {}
var _qused:Dictionary = {}

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

## 纯视觉的最短演出时长（不影响任何判定）。
## 持续性部分沉到角色之下（z -1）的时刻（占 life 的比例）：爆发瞬间在上层，余烬/烟/裂缝/法阵不再挡住角色。
const SINK_AT:Dictionary = {"fuga_burst":0.22,"red_burst":0.25,"web":0.2,"world_slash":0.18,"wheel_turn":0.0,"heal":0.0,"shockwave":0.3,"thunder":0.35,"black_flash":0.4,"purple_beam":0.5,"cleave":0.55,"teleport":0.3,"ripple":0.0}
var _sunk:bool = false
const MIN_LIFE:Dictionary = {"red_burst":0.75,"cleave":0.8,"web":0.9,"fuga_burst":1.4,"world_slash":1.4,"black_flash":0.8,"thunder":0.8,"ripple":0.45,"teleport":0.55,"wheel_turn":0.9,"purple_beam":1.0,"slash":0.42,"shockwave":0.55}

func _ready() -> void:
	life = maxf(life,float(MIN_LIFE.get(kind,0.0)))
	_rng.seed = _seed
	# 项目默认是最近邻采样：特效贴图放大后会出现方块和锯齿，这里统一改为线性（带 mipmap）。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_add = V.make_add_layer(self,_draw_add)
	# 普通混合的顶层：画在叠加光之上，黑色部分不会被红光冲淡。
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
	if t >= life + _linger():
		queue_free()
		return
	if not _sunk and SINK_AT.has(kind) and _k() >= float(SINK_AT[kind]):
		_sunk = true
		z_index = -1
	_tick_kind(delta)
	_parts.step(delta)
	_update_quads()
	queue_redraw()
	_add.queue_redraw()
	_top.queue_redraw()

## 效果结束后让粒子自然消散的额外时间。
func _linger() -> float:
	return 0.35 if _parts.alive > 0 else 0.0

func _v(key:String,fallback:Vector2 = Vector2.ZERO) -> Vector2:
	var value:Variant = data.get(key,fallback)
	return value if value is Vector2 else fallback

func _f(key:String,fallback:float) -> float:
	return float(data.get(key,fallback))

func _c(key:String,fallback:Color) -> Color:
	var value:Variant = data.get(key,fallback)
	return value if value is Color else fallback

func _k() -> float:
	return clampf(t / life,0.0,1.0)

func _burst(pos:Vector2,count:int,speed_min:float,speed_max:float,lifetime:float,size:float,color:Color,k:int = 0,drag:float = 3.0,gravity:float = 0.0,spread:float = TAU,dir:float = 0.0) -> void:
	for i:int in count:
		var a:float = dir + _rng.randf_range(-spread * 0.5,spread * 0.5)
		_parts.emit(pos,Vector2.from_angle(a) * _rng.randf_range(speed_min,speed_max),lifetime * _rng.randf_range(0.6,1.2),size * _rng.randf_range(0.6,1.3),color,k,drag,gravity)

## 烟团参数：[角度, 距离(半径倍数), 尺寸(半径倍数), 种子]
func _make_puffs(n:int,dist_min:float,dist_max:float,size_min:float,size_max:float) -> void:
	for i:int in n:
		_cache2.append([TAU * i / n + _rng.randf_range(-0.4,0.4),_rng.randf_range(dist_min,dist_max),_rng.randf_range(size_min,size_max),_rng.randf() * 50.0])

# ================================================================= 着色器面片
func _qd(qname:String,mode:int,layer:int,pos:Vector2,size:Vector2,rot:float,params:Dictionary) -> void:
	var s:Sprite2D = _qs.get(qname)
	if s == null:
		s = V.quad(self,mode,layer)
		_qs[qname] = s
	if not params.has("time"): params["time"] = t
	if not params.has("seed"): params["seed"] = float(_seed % 997) * 0.173
	V.qset(s,pos,size,rot,params)
	_qused[qname] = true

## 沿线段 a→b 铺一张面片（UV.x 从 a 到 b，高度 height 像素）。
func _ql(qname:String,mode:int,layer:int,a:Vector2,b:Vector2,height:float,params:Dictionary) -> void:
	_qd(qname,mode,layer,(a + b) * 0.5,Vector2(a.distance_to(b),height),(b - a).angle(),params)

func _update_quads() -> void:
	_qused.clear()
	_quads(_k())
	for qname:Variant in _qs.keys():
		if not _qused.has(qname): (_qs[qname] as Sprite2D).visible = false

## 由一个主色生成四阶配色。
static func _pal_from(c:Color) -> Dictionary:
	return {"c0":Color(1,1,1).lerp(c,0.12),"c1":c.lightened(0.35),"c2":c,"c3":c.darkened(0.85)}

# ================================================================= 初始化
func _init_kind() -> void:
	match kind:
		"ripple":
			_burst(_v("pos"),6,90.0,170.0,0.35,2.5,Color(0.6,0.95,1.0),2,9.0)
		"red_burst":
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",80.0)
			_burst(p,30,r * 2.0,r * 5.5,0.5,3.5,Color(1.0,0.4,0.25),2,4.0)
			_burst(p,8,r * 1.0,r * 3.0,0.9,3.0,Color(0.25,0.06,0.06,0.9),1,3.0,260.0)
			_make_puffs(6,0.35,0.7,1.0,1.5)
		"purple_beam":
			var a:Vector2 = _v("a")
			_burst(a,24,120.0,420.0,0.6,4.0,Color(0.85,0.6,1.0),2,3.0)
		"slash":
			var a2:Vector2 = _v("a")
			var b2:Vector2 = _v("b")
			_cache = [_rng.randf_range(-1.0,1.0) * a2.distance_to(b2) * 0.06]
			var mid:Vector2 = a2.lerp(b2,0.5)
			var n:Vector2 = (b2 - a2).orthogonal().normalized()
			for i2:int in 6:
				_parts.emit(mid + (b2 - a2) * _rng.randf_range(-0.3,0.3),n * _rng.randf_range(-160,160) + (b2 - a2).normalized() * _rng.randf_range(60,220),0.3,2.2,_c("color",Color.WHITE),2,5.0)
			# 血点
			for i3:int in 5:
				_parts.emit(mid + (b2 - a2) * _rng.randf_range(-0.2,0.2),n * _rng.randf_range(-90,90) + Vector2(0,-_rng.randf_range(20,80)),0.5,2.2,Color(0.55,0.0,0.05,0.95),1,2.0,420.0)
		"cleave":
			# 捌：按对象强度“切块”——两组交叉的平行斩线依次落下，最后整块碎开。
			var p3:Vector2 = _v("pos")
			var r3:float = _f("radius",34.0)
			var base_ang:float = _rng.randf() * PI
			for i3:int in 10:
				var grp:int = i3 % 2
				var ang3:float = base_ang + (PI * 0.5 + _rng.randf_range(-0.18,0.18)) * grp + _rng.randf_range(-0.08,0.08)
				var lane:float = (float(i3 >> 1) - 2.0) * r3 * 0.42 + _rng.randf_range(-3,3)
				_cache.append([ang3,_rng.randf_range(1.1,1.5),i3 * 0.028 + _rng.randf() * 0.012,lane])
			_burst(p3,24,140.0,460.0,0.45,2.6,Color(1.0,0.35,0.4),2,5.0)
			_burst(p3,16,40.0,180.0,0.8,2.6,Color(0.5,0.0,0.05,0.95),1,3.0,380.0)
		"web":
			var p4:Vector2 = _v("pos")
			var r4:float = _f("radius",150.0)
			var spokes:int = 14
			for i4:int in spokes:
				var ang:float = TAU * i4 / spokes + _rng.randf_range(-0.12,0.12)
				var pts:PackedVector2Array = V.bolt(_rng,p4,p4 + Vector2.from_angle(ang) * r4 * _rng.randf_range(0.85,1.1),r4 * 0.06,4)
				_cache.append(pts)
			_burst(p4,26,60.0,r4 * 2.2,0.8,3.0,Color(0.3,0.26,0.24,0.85),1,3.0,260.0)
			_burst(p4,24,r4 * 1.5,r4 * 3.5,0.4,2.2,Color(1,0.95,0.95),2,5.0)
			_make_puffs(8,0.55,0.95,0.45,0.7)
		"fuga_burst":
			var p5:Vector2 = _v("pos")
			var r5:float = _f("radius",160.0)
			_burst(p5,46,r5 * 1.5,r5 * 4.0,0.9,3.0,Color(1.0,0.75,0.3),2,2.0,-60.0)
			for i5:int in 6:
				_cache.append([_rng.randf_range(-r5 * 0.75,r5 * 0.75),_rng.randf_range(0.6,1.2),_rng.randf_range(0.02,0.22)])
			_make_puffs(7,0.3,0.8,0.8,1.2)
		"world_slash":
			var a6:Vector2 = _v("a")
			var b6:Vector2 = _v("b")
			var n6:Vector2 = (b6 - a6).orthogonal().normalized()
			for i6:int in 50:
				var at:Vector2 = a6.lerp(b6,_rng.randf())
				var side:float = 1.0 if _rng.randf() < 0.5 else -1.0
				_parts.emit(at,n6 * side * _rng.randf_range(80,420) + (b6 - a6).normalized() * _rng.randf_range(-60,60),0.7,_rng.randf_range(2.0,3.5),Color(1,0.95,0.95),2,3.0)
			for i7:int in 26:
				_cache.append([_rng.randf(),_rng.randf_range(-1.0,1.0),_rng.randf_range(8,26),_rng.randf() * TAU])
			# 空间裂纹：从主斩线斜向崩开的短裂缝（不是平行线）
			for i8:int in 9:
				var sd8:float = 1.0 if i8 % 2 == 0 else -1.0
				_cache2.append([_rng.randf_range(0.08,0.92),sd8,_rng.randf_range(0.3,0.85) * (1.0 if _rng.randf() < 0.5 else -1.0),_rng.randf_range(70.0,210.0),_rng.randf_range(0.02,0.12)])
		"black_flash":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",70.0)
			_burst(p8,22,r8 * 2.0,r8 * 7.0,0.4,3.0,Color(1.0,0.12,0.18),2,5.0)
			_burst(p8,18,r8 * 1.5,r8 * 5.0,0.55,r8 * 0.06,Color(0.02,0.0,0.0,0.95),1,5.0)
		"heal":
			pass
		"thunder":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",70.0)
			_burst(p9,24,r9 * 1.5,r9 * 5.0,0.5,2.5,Color(0.75,0.9,1.0),2,4.0,200.0)
			_make_puffs(5,0.3,0.7,0.6,0.9)
		"teleport":
			var a10:Vector2 = _v("a")
			var b10:Vector2 = _v("b")
			for i10:int in 12:
				_parts.emit(a10.lerp(b10,_rng.randf()),Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10,50),0.4,2.5,Color(0.6,0.95,1.0),0,2.0)
			_burst(b10,12,120.0,260.0,0.35,2.2,Color(0.7,0.95,1.0),2,6.0)
		"wheel_turn":
			var p11:Vector2 = _v("pos")
			_burst(p11,18,60.0,200.0,0.8,3.0,Color(1.0,0.85,0.4),3,3.0)
		"shockwave":
			var p12:Vector2 = _v("pos")
			var r12:float = _f("radius",200.0)
			var c12:Color = _c("color",Color(0.6,0.9,1.0))
			_burst(p12,int(clampf(r12 / 7.0,6,32)),r12 * 1.2,r12 * 2.4,life * 0.9,2.5,c12.lightened(0.3),2,3.0)
			if r12 >= 60.0: _make_puffs(int(clampf(r12 / 18.0,6,14)),0.8,1.0,0.22,0.32)
		"text":
			pass

# ================================================================= 持续发射
func _tick_kind(delta:float) -> void:
	var k:float = _k()
	_emit_acc += delta
	match kind:
		"purple_beam":
			if k < 0.5 and _emit_acc > 0.016:
				_emit_acc = 0.0
				var a:Vector2 = _v("a")
				var b:Vector2 = _v("b")
				var head:Vector2 = a.lerp(b,V.out_cubic(k / 0.42))
				var n:Vector2 = (b - a).orthogonal().normalized()
				var w:float = _f("width",90.0)
				for i:int in 3:
					var at:Vector2 = a.lerp(head,_rng.randf())
					_parts.emit(at + n * _rng.randf_range(-w,w) * 0.5,n * _rng.randf_range(-1,1) * 160.0,0.45,_rng.randf_range(2,4),Color(0.8,0.55,1.0),2,2.0)
				_parts.emit(head + n * _rng.randf_range(-w,w) * 0.8,(head - a).normalized() * -120.0 + n * _rng.randf_range(-200,200),0.35,2.5,Color(1.0,0.85,1.0),2,3.0)
		"fuga_burst":
			if k > 0.1 and k < 0.6 and _emit_acc > 0.03:
				_emit_acc = 0.0
				var p:Vector2 = _v("pos")
				var r:float = _f("radius",160.0)
				_parts.emit(p + Vector2(_rng.randf_range(-r,r) * 0.7,-_rng.randf_range(0,r) * 0.6),Vector2(_rng.randf_range(-40,40),-_rng.randf_range(120,300)),0.8,2.5,Color(1.0,0.8,0.35),2,1.0,-60.0)
		"heal":
			if k < 0.8 and _emit_acc > 0.03:
				_emit_acc = 0.0
				var p3:Vector2 = _v("pos")
				var r3:float = _f("radius",30.0)
				var a3:float = _rng.randf() * TAU
				_parts.emit(p3 + Vector2.from_angle(a3) * r3 * _rng.randf_range(0.3,1.2),Vector2(cos(a3) * 20.0,-_rng.randf_range(50,110)),0.9,_rng.randf_range(2.0,4.0),Color(0.5,1.0,0.6),3 if _rng.randf() < 0.4 else 0,1.0)
		"thunder":
			if k < 0.55 and _emit_acc > 0.05:
				_emit_acc = 0.0
				_burst(_v("pos"),4,80.0,260.0,0.3,2.0,Color(0.8,0.95,1.0),2,4.0,300.0)
		"wheel_turn":
			if k < 0.6 and _emit_acc > 0.04:
				_emit_acc = 0.0
				var p4:Vector2 = _v("pos")
				var r4:float = _f("radius",22.0) * 2.4
				var a4:float = _rng.randf() * TAU
				_parts.emit(p4 + Vector2.from_angle(a4) * r4,Vector2.from_angle(a4 + PI * 0.5) * 60.0,0.6,2.5,Color(1.0,0.9,0.5),3,2.0)

# ================================================================= 着色器面片编排（每帧）
func _quads(k:float) -> void:
	match kind:
		"ripple":
			# 无下限：两圈涟漪从外向内收缩到接触点，空间“凝固”。
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",24.0)
			for i:int in 2:
				var kk:float = V.seg(k,i * 0.18,i * 0.18 + 0.75)
				if kk <= 0.0 or kk >= 1.0: continue
				_qd("rip%d" % i,Q.RING,2,p,Vector2.ONE * r * 4.4,0.0,V.pal("cyan",{"alpha":1.3 * (1.0 - kk),"p0":Vector4(lerpf(0.95,0.28,V.out_cubic(kk)),0.07,0.3,0.0),"p1":Vector4(0.0,0.0,0.7,0.0)}))
			_qd("dot",Q.ORB,2,p,Vector2.ONE * r * 1.6,0.0,V.pal("cyan",{"alpha":1.0 - V.seg(k,0.0,0.35),"p0":Vector4(0.4,-2.0,0.5,0.0),"p1":Vector4(4.0,0.25,0.8,0.0)}))
		"red_burst":
			var p2:Vector2 = _v("pos")
			var r2:float = _f("radius",80.0)
			# 烟团先画（在光之下），被爆心的光压亮
			for i2:int in _cache2.size():
				var sp:Array = _cache2[i2]
				var kk2:float = V.seg(k,0.06,1.0)
				var at:Vector2 = p2 + Vector2.from_angle(float(sp[0])) * r2 * float(sp[1]) * (0.4 + 0.6 * V.out_cubic(kk2 / 0.5)) + Vector2(0,-r2 * 0.3 * kk2)
				_qd("smk%d" % i2,Q.SMOKE,1,at,Vector2.ONE * r2 * float(sp[2]),0.0,{"seed":float(sp[3]),"alpha":0.7,"c1":Color(0.75,0.42,0.38),"c2":Color(0.42,0.16,0.16),"c3":Color(0.1,0.0,0.02),"p0":Vector4(0.5 + 0.4 * V.out_cubic(kk2),V.seg(kk2,0.1,0.8),0.8,0.6)})
			var fl:float = 1.0 - V.seg(k,0.0,0.32)
			_qd("core",Q.ORB,2,p2,Vector2.ONE * r2 * 2.8,0.0,V.pal("red",{"alpha":1.4 * fl,"p0":Vector4(lerpf(0.22,0.62,V.out_expo(k / 0.14)),2.2,0.9,0.6),"p1":Vector4(7.0,0.3,0.8,0.0)}))
			var e2:float = V.out_expo(k / 0.45)
			_qd("ring",Q.RING,2,p2,Vector2.ONE * r2 * 4.4,0.0,V.pal("red",{"alpha":1.2 * (1.0 - V.seg(k,0.2,0.55)),"p0":Vector4(0.1 + 0.85 * e2,0.12 * (1.0 - k) + 0.02,0.1 + 0.75 * V.seg(k,0.15,0.55),0.0),"p1":Vector4(0.012,0.5,0.6,0.0)}))
			_qd("ring2",Q.RING,2,p2,Vector2.ONE * r2 * 3.0,0.0,V.pal("white",{"alpha":1.0 - V.seg(k,0.0,0.35),"p0":Vector4(0.2 + 0.75 * V.out_expo(k / 0.22),0.05,0.3,0.0),"p1":Vector4(0.0,0.0,0.5,0.0)}))
			_qd("focus",Q.FOCUS,2,p2,Vector2.ONE * r2 * 7.0,0.0,{"alpha":0.85 * (1.0 - V.seg(k,0.0,0.22)),"c0":Color(1,0.9,0.85),"p0":Vector4(0.3,120.0,0.35,0.0),"p1":Vector4(24.0,0.25,0,0)})
		"purple_beam":
			_quads_purple(k)
		"slash":
			var a3:Vector2 = _v("a")
			var b3:Vector2 = _v("b")
			var col3:Color = _c("color",Color(1,1,1))
			var ext:Vector2 = (b3 - a3) * 0.06
			var h3:float = 48.0
			var bulge:float = (float(_cache[0]) if not _cache.is_empty() else 0.0) / (h3 * 0.5)
			var gap3:float = (_f("width",3.0) * 1.1 + 1.6) / (h3 * 0.5)
			var rev3:float = V.out_expo(k / 0.2)
			var era3:float = V.in_cubic(V.seg(k,0.32,1.0))
			var sp3:Dictionary = {"c0":Color(1,1,1),"c1":col3.lerp(Color(1,0.3,0.35),0.35),"c2":Color(1.0,0.12,0.22),"c3":Color(0,0,0)}
			_ql("cut",Q.CUT,2,a3 - ext,b3 + ext,h3,_merge(sp3,{"p0":Vector4(gap3 * (1.0 - 0.6 * era3),era3,rev3,0.5),"p1":Vector4(1.6,5.0,0.0,bulge)}))
			# 回声斩：两道细斩线稍晚落在两侧（解 是看不见的连续斩击）
			var n3:Vector2 = (b3 - a3).orthogonal().normalized()
			for e3:int in 2:
				var sgn:float = -1.0 if e3 == 0 else 1.0
				var kd:float = V.seg(k,0.08 + e3 * 0.07,0.8)
				if kd <= 0.0 or kd >= 1.0: continue
				var off3:Vector2 = n3 * sgn * (11.0 + _f("width",3.0) * 2.0) + (b3 - a3) * 0.07 * sgn
				_ql("echo%d" % e3,Q.CUT,2,a3 + off3,b3 + off3,h3 * 0.7,_merge(sp3,{"alpha":0.85,"p0":Vector4(gap3 * 0.45,V.in_cubic(V.seg(kd,0.3,1.0)),V.out_expo(kd / 0.25),0.4),"p1":Vector4(1.0,3.5,0.0,bulge * 0.8)}))
		"cleave":
			var p4:Vector2 = _v("pos")
			var r4:float = _f("radius",34.0) * 1.6
			var sp4:Dictionary = {"c0":Color(1,1,1),"c1":Color(1.0,0.25,0.32),"c2":Color(1.0,0.05,0.15),"c3":Color(0,0,0)}
			for ci:int in _cache.size():
				var cut:Array = _cache[ci]
				var ang:float = float(cut[0])
				var kk4:float = V.seg(t,float(cut[2]),float(cut[2]) + 0.42)
				if kk4 <= 0.0 or kk4 >= 1.0: continue
				var dir:Vector2 = Vector2.from_angle(ang) * r4 * float(cut[1])
				var shift:Vector2 = dir.orthogonal().normalized() * float(cut[3])
				_ql("c%d" % ci,Q.CUT,2,p4 - dir + shift,p4 + dir + shift,34.0,_merge(sp4,{"p0":Vector4(0.13 * (1.0 - V.seg(kk4,0.4,1.0) * 0.6),V.in_cubic(V.seg(kk4,0.45,1.0)),V.out_expo(kk4 / 0.22),0.45),"p1":Vector4(1.4,4.5,0.0,0.06)}))
			_qd("flash",Q.ORB,2,p4,Vector2.ONE * r4 * 2.2,0.0,V.pal("blood",{"alpha":1.0 - V.seg(k,0.0,0.3),"p0":Vector4(lerpf(0.2,0.45,V.out_expo(k / 0.1)),1.5,0.7,0.0),"p1":Vector4(8.0,0.3,0.7,0.0)}))
		"web":
			var p5:Vector2 = _v("pos")
			var r5:float = _f("radius",150.0)
			for i5:int in _cache2.size():
				var sp5:Array = _cache2[i5]
				var kk5:float = V.seg(k,0.05,1.0)
				var at5:Vector2 = p5 + Vector2.from_angle(float(sp5[0])) * r5 * float(sp5[1]) * V.out_cubic(kk5 / 0.4)
				_qd("dust%d" % i5,Q.SMOKE,1,at5,Vector2.ONE * r5 * float(sp5[2]),0.0,{"seed":float(sp5[3]),"alpha":0.6,"c1":Color(0.62,0.56,0.52),"c2":Color(0.33,0.28,0.26),"c3":Color(0.1,0.08,0.07),"p0":Vector4(0.55 + 0.35 * kk5,V.seg(kk5,0.25,1.0),0.85,0.6)})
			_qd("ring",Q.RING,2,p5,Vector2.ONE * r5 * 2.6,0.0,V.pal("white",{"c1":Color(1.0,0.75,0.75),"c2":Color(1.0,0.3,0.35),"alpha":1.0 - V.seg(k,0.1,0.42),"p0":Vector4(0.15 + 0.8 * V.out_expo(k / 0.35),0.06,0.3 + 0.5 * k,0.0),"p1":Vector4(0.008,0.3,0.5,0.0)}))
		"fuga_burst":
			_quads_fuga(k)
		"world_slash":
			var a7:Vector2 = _v("a")
			var b7:Vector2 = _v("b")
			var w7:float = _f("width",70.0)
			var n7:Vector2 = (b7 - a7).orthogonal().normalized()
			var open7:float = V.out_expo(k / 0.05) * (1.0 - V.in_cubic(V.seg(k,0.5,0.82)))
			var sp7:Dictionary = {"c0":Color(1,1,1),"c1":Color(1.0,0.1,0.18),"c2":Color(1.0,0.55,0.6),"c3":Color(0,0,0)}
			_ql("cut",Q.CUT,2,a7,b7,w7 * 3.0,_merge(sp7,{"alpha":1.0 if open7 > 0.0 else 0.0,"p0":Vector4(0.2 * open7,0.0,V.out_expo(k / 0.045),0.12),"p1":Vector4(2.5,16.0,1.0,0.0)}))
			var dir7:Vector2 = (b7 - a7).normalized()
			for hi:int in _cache2.size():
				var fr:Array = _cache2[hi]
				var kh:float = V.seg(k,float(fr[4]),float(fr[4]) + 0.55)
				if kh <= 0.0 or kh >= 1.0: continue
				var st7:Vector2 = a7.lerp(b7,float(fr[0])) + n7 * float(fr[1]) * w7 * 0.12
				var d7:Vector2 = dir7.rotated(float(fr[2])) * float(fr[1]) * signf(float(fr[2]))
				if d7.dot(n7 * float(fr[1])) < 0.0: d7 = -d7
				var en7:Vector2 = st7 + d7 * float(fr[3]) * V.out_expo(kh / 0.12)
				_ql("hair%d" % hi,Q.CUT,2,st7,en7,30.0,_merge(sp7,{"alpha":1.0 - V.seg(kh,0.5,1.0),"p0":Vector4(0.1,V.in_cubic(V.seg(kh,0.45,1.0)),1.0,0.6),"p1":Vector4(1.2,6.0,0.6,0.0)}))
			var mid7:Vector2 = a7.lerp(b7,0.5)
			_qd("ink",Q.FOCUS,2,mid7,Vector2.ONE * 2600.0,0.0,{"alpha":1.0 - V.seg(k,0.02,0.3),"c3":Color(0,0,0),"p0":Vector4(0.28,200.0,0.45,1.0),"p1":Vector4(24.0,0.25,0,0)})
		"black_flash":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",70.0)
			_qd("ink",Q.FOCUS,1,p8,Vector2.ONE * r8 * 9.0,0.0,{"alpha":1.0 - V.seg(k,0.04,0.36),"c3":Color(0,0,0),"p0":Vector4(0.34,130.0,0.55,1.0),"p1":Vector4(24.0,0.3,0,0)})
			_qd("lines",Q.FOCUS,1,p8,Vector2.ONE * r8 * 6.0,0.0,{"alpha":1.0 - V.seg(k,0.0,0.16),"c0":Color(1,0.85,0.85),"p0":Vector4(0.3,90.0,0.35,0.0),"p1":Vector4(30.0,0.2,0,0)})
			_qd("ring",Q.RING,1,p8,Vector2.ONE * r8 * 5.2,0.0,V.pal("black",{"alpha":1.2 * (1.0 - V.seg(k,0.08,0.3)),"p0":Vector4(0.12 + 0.83 * V.out_expo(k / 0.3),0.08 * (1.0 - k) + 0.02,0.25 + 0.6 * k,0.0),"p1":Vector4(0.014,0.4,0.5,0.0)}))
		"thunder":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",70.0)
			for i9:int in _cache2.size():
				var sp9:Array = _cache2[i9]
				var kk9:float = V.seg(k,0.05,1.0)
				_qd("dust%d" % i9,Q.SMOKE,1,p9 + Vector2.from_angle(float(sp9[0])) * r9 * float(sp9[1]) * V.out_cubic(kk9 / 0.4) + Vector2(0,-r9 * 0.3 * kk9),Vector2.ONE * r9 * float(sp9[2]) * 1.6,0.0,{"seed":float(sp9[3]),"c1":Color(0.55,0.6,0.7),"c2":Color(0.25,0.28,0.36),"c3":Color(0.05,0.06,0.1),"p0":Vector4(0.5 + 0.35 * kk9,V.seg(kk9,0.3,1.0),0.8,0.6)})
			var strikes:Array[float] = [0.0,0.18,0.34]
			for si:int in strikes.size():
				var ks:float = V.seg(k,strikes[si],strikes[si] + 0.4)
				if ks <= 0.0 or ks >= 1.0: continue
				_qd("ring%d" % si,Q.RING,2,p9,Vector2.ONE * r9 * 3.4,0.0,V.pal("cyan",{"alpha":1.1 * (1.0 - V.seg(ks,0.1,0.55)),"p0":Vector4(0.12 + 0.83 * V.out_expo(ks / 0.5),0.07 * (1.0 - ks) + 0.015,0.3 + 0.5 * ks,0.0),"p1":Vector4(0.01,0.8,0.6,0.0)}))
				_qd("flash%d" % si,Q.ORB,2,p9,Vector2.ONE * r9 * 1.8,0.0,V.pal("cyan",{"alpha":1.2 * (1.0 - V.seg(ks,0.0,0.4)),"p0":Vector4(0.38,0.0,0.9,0.0),"p1":Vector4(10.0,0.35,0.9,0.0)}))
		"teleport":
			var a10:Vector2 = _v("a")
			var b10:Vector2 = _v("b")
			_ql("trail",Q.BEAM,1,a10,b10,26.0,V.pal("cyan",{"alpha":1.0 - V.seg(k,0.0,0.4),"p0":Vector4(0.35,14.0,0.3,1.0),"p1":Vector4(V.out_cubic(k / 0.4),0.4,0.7,0.0),"p2":Vector4(0.0,0.05,0,0)}))
			_qd("ring",Q.RING,2,b10,Vector2.ONE * 190.0,0.0,V.pal("cyan",{"alpha":1.2 * (1.0 - V.seg(k,0.15,0.5)),"p0":Vector4(0.12 + 0.83 * V.out_expo(k / 0.4),0.07,0.3 + 0.5 * k,0.0),"p1":Vector4(0.012,0.6,0.6,0.0)}))
			_qd("lines",Q.FOCUS,2,b10,Vector2.ONE * 300.0,0.0,{"alpha":0.9 * (1.0 - V.seg(k,0.0,0.3)),"c0":Color(0.75,0.97,1.0),"p0":Vector4(0.22,70.0,0.3,0.0),"p1":Vector4(30.0,0.2,0,0)})
			_qd("pinch",Q.ORB,2,a10,Vector2.ONE * 90.0,0.0,V.pal("cyan",{"alpha":1.0 - V.seg(k,0.0,0.45),"p0":Vector4(lerpf(0.55,0.05,V.out_cubic(k / 0.45)),-3.0,0.6,0.8),"p1":Vector4(-10.0,0.2,0.8,0.0)}))
		"wheel_turn":
			var p11:Vector2 = _v("pos")
			var r11:float = _f("radius",22.0) * 2.4
			var snap:float = V.seg(k,0.42,0.9)
			if snap > 0.0 and snap < 1.0:
				_qd("ring",Q.RING,2,p11,Vector2.ONE * r11 * 5.0,0.0,V.pal("gold",{"alpha":1.2 * (1.0 - V.seg(snap,0.1,0.6)),"p0":Vector4(0.2 + 0.75 * V.out_expo(snap / 0.5),0.06,0.3 + 0.5 * snap,0.0),"p1":Vector4(0.01,0.9,0.6,0.0)}))
			_qd("glow",Q.ORB,1,p11,Vector2.ONE * r11 * 3.2,0.0,V.pal("gold",{"alpha":0.55 * (1.0 - V.seg(k,0.6,1.0)) * V.out_cubic(k / 0.2),"p0":Vector4(0.25,0.0,1.0,0.0),"p1":Vector4(2.0,0.2,0.9,0.0),"p2":Vector4(0.3,3.0,0,0)}))
		"shockwave":
			var p12:Vector2 = _v("pos")
			var r12:float = _f("radius",200.0)
			var c12:Color = _c("color",Color(0.6,0.9,1.0))
			var dark:bool = c12.get_luminance() < 0.3
			var e12:float = V.out_expo(k)
			for i12:int in _cache2.size():
				var sp12:Array = _cache2[i12]
				_qd("dust%d" % i12,Q.SMOKE,1,p12 + Vector2.from_angle(float(sp12[0])) * r12 * e12 * float(sp12[1]),Vector2.ONE * r12 * float(sp12[2]),0.0,{"seed":float(sp12[3]),"c1":Color(0.62,0.6,0.62),"c2":Color(0.32,0.3,0.34),"c3":Color(0.08,0.07,0.09),"p0":Vector4(0.45 + 0.4 * k,V.seg(k,0.3,1.0),0.75,0.5)})
			var pal12:Dictionary = _pal_from(Color(0.55,0.3,0.9) if dark else c12)
			if dark: pal12["c3"] = Color(0.02,0.0,0.05)
			_qd("ring",Q.RING,2,p12,Vector2.ONE * r12 * 2.3,0.0,_merge(pal12,{"alpha":1.25 * (1.0 - V.seg(k,0.15,0.6)),"p0":Vector4(0.08 + 0.87 * e12,0.13 * (1.0 - k) + 0.025,0.15 + 0.7 * k,0.0 if not dark else 0.15),"p1":Vector4(0.01,0.6,0.6,0.7 if dark else 0.0)}))
			_qd("ring2",Q.RING,2,p12,Vector2.ONE * r12 * 1.6,0.0,_merge(pal12,{"alpha":0.7 * (1.0 - V.seg(k,0.0,0.35)),"p0":Vector4(0.1 + 0.85 * V.out_cubic(k),0.05,0.4,0.0),"p1":Vector4(0.0,0.0,0.4,0.0)}))
		"heal":
			var p13:Vector2 = _v("pos")
			var r13:float = _f("radius",30.0)
			_qd("ring",Q.RING,2,p13,Vector2.ONE * r13 * 4.0,0.0,V.pal("green",{"alpha":1.0 - V.seg(k,0.2,0.7),"p0":Vector4(0.2 + 0.75 * V.out_cubic(k),0.06,0.35,0.0),"p1":Vector4(0.0,0.5,0.6,0.0)}))

func _merge(a:Dictionary,b:Dictionary) -> Dictionary:
	var d:Dictionary = a.duplicate()
	d.merge(b,true)
	return d

# ================================================================= 虚式·茈
func _quads_purple(k:float) -> void:
	var a:Vector2 = _v("a")
	var b:Vector2 = _v("b")
	var w:float = _f("width",90.0)
	var L:float = maxf(a.distance_to(b),1.0)
	var dir:Vector2 = (b - a) / L
	var n:Vector2 = dir.orthogonal()
	var travel:float = V.out_cubic(k / 0.42)
	var head:Vector2 = a.lerp(b,travel)
	var alive:float = 1.0 - V.seg(k,0.5,0.82)
	var thin:float = lerpf(1.0,0.25,V.seg(k,0.42,0.82))
	# 被抹消的地面：一道边缘发紫光的虚空沟
	var scar:float = V.seg(k,0.25,0.45) * (1.0 - V.seg(k,0.72,1.0))
	_ql("scar",Q.CUT,0,a,b,w * 1.6,{"alpha":scar,"c0":Color(0.95,0.8,1.0),"c1":Color(0.65,0.25,1.0),"c2":Color(0.95,0.35,0.85),"c3":Color(0.02,0.0,0.05),"p0":Vector4(0.26 * lerpf(1.0,0.5,V.seg(k,0.5,1.0)),0.0,travel,0.3),"p1":Vector4(1.5,10.0,0.7,0.0)})
	# 光束主体
	_ql("beam",Q.BEAM,1,a,b,w * 2.4,V.pal("purple",{"alpha":1.25 * alive,"p0":Vector4(0.42 * thin,10.0,0.35,travel),"p1":Vector4(0.0,0.02,0.9,0.4),"p2":Vector4(0.0,w * 0.6 / L,0,0)}))
	# 前进的球体
	var orb:float = 1.0 - V.seg(k,0.4,0.52)
	var pulse:float = 1.0 + 0.05 * sin(t * 45.0)
	_qd("orbglow",Q.ORB,2,head,Vector2.ONE * w * 7.0,0.0,V.pal("purple",{"alpha":0.55 * orb,"p0":Vector4(0.2,0.0,0.0,0.0),"p1":Vector4(0.0,0.0,1.0,0.0)}))
	_qd("orb",Q.ORB,2,head,Vector2.ONE * w * 5.0 * pulse,0.0,V.pal("purple",{"alpha":1.4 * orb,"p0":Vector4(0.64,1.0,0.45,1.2),"p1":Vector4(4.0,0.1,0.9,0.95),"p2":Vector4(0.0,2.2,0,0)}))
	# 发射瞬间：苍与赫旋转合一
	var merge:float = 1.0 - V.seg(k,0.0,0.14)
	if merge > 0.0:
		var rot:Vector2 = Vector2.from_angle(t * 38.0) * w * 0.6 * merge
		_qd("mb",Q.ORB,2,a + rot,Vector2.ONE * w * 1.5,0.0,V.pal("blue",{"alpha":merge * 1.2,"p0":Vector4(0.45,-2.0,0.5,0.6),"p1":Vector4(8.0,0.2,0.8,0.8)}))
		_qd("mr",Q.ORB,2,a - rot,Vector2.ONE * w * 1.5,0.0,V.pal("red",{"alpha":merge * 1.2,"p0":Vector4(0.45,2.0,0.5,0.6),"p1":Vector4(8.0,0.2,0.8,0.8)}))
	_qd("ring",Q.RING,2,a,Vector2.ONE * w * 6.5,0.0,V.pal("purple",{"alpha":1.2 * (1.0 - V.seg(k,0.12,0.45)),"p0":Vector4(0.1 + 0.85 * V.out_expo(k / 0.5),0.08,0.2 + 0.6 * k,0.0),"p1":Vector4(0.01,0.6,0.6,0.0)}))
	_qd("focus",Q.FOCUS,2,a,Vector2.ONE * w * 16.0,0.0,{"alpha":0.9 * (1.0 - V.seg(k,0.0,0.25)),"c0":Color(0.95,0.85,1.0),"p0":Vector4(0.12,150.0,0.4,0.0),"p1":Vector4(24.0,0.2,0,0)})
	# 终点：球体撞出画面时的冲击
	var hit:float = V.seg(k,0.36,0.8)
	if hit > 0.0 and hit < 1.0:
		_qd("endring",Q.RING,2,b - dir * w,Vector2.ONE * w * 7.0,0.0,V.pal("purple",{"alpha":1.0 - V.seg(hit,0.1,0.6),"p0":Vector4(0.1 + 0.85 * V.out_expo(hit / 0.5),0.09,0.3 + 0.5 * hit,0.0),"p1":Vector4(0.01,0.5,0.6,0.0)}))
	# 光束两侧的能量纹（两条细光束，横向错开）
	for side:int in 2:
		var s:float = 1.0 if side == 0 else -1.0
		var off:Vector2 = n * s * w * 0.55 * thin
		_ql("edge%d" % side,Q.BEAM,1,a + off,b + off,w * 0.5,V.pal("purple",{"alpha":0.9 * alive,"p0":Vector4(0.28,16.0,0.8,travel),"p1":Vector4(0.0,0.05,0.4,0.0),"p2":Vector4(0.0,0.01,0,0),"seed":float(side) * 7.3}))

# ================================================================= 开·竈
func _quads_fuga(k:float) -> void:
	var p:Vector2 = _v("pos")
	var r:float = _f("radius",160.0)
	var grow:float = V.out_expo(k / 0.18)
	var fade:float = V.seg(k,0.42,1.0)
	# 滚滚黑烟（在火之下，火熄灭后仍在上升）
	for i:int in _cache2.size():
		var sp:Array = _cache2[i]
		var kk:float = V.seg(k,0.15,1.0)
		var at:Vector2 = p + Vector2.from_angle(float(sp[0])) * r * float(sp[1]) * (0.5 + 0.5 * V.out_cubic(kk / 0.4)) + Vector2(0,-r * (0.3 + 0.9 * kk))
		_qd("smk%d" % i,Q.SMOKE,0,at,Vector2.ONE * r * float(sp[2]),0.0,{"seed":float(sp[3]),"c1":Color(0.4,0.3,0.27),"c2":Color(0.16,0.1,0.09),"c3":Color(0.04,0.02,0.02),"p0":Vector4(0.5 + 0.4 * kk,V.seg(kk,0.35,1.0),0.9,0.7)})
	# 火焰穹顶：赛璐璐色阶的爆炎球，边缘翻滚、外焰尖刺、深色墨线
	var dc:Vector2 = p + Vector2(0,-r * 0.3)
	var dome_r:float = lerpf(0.22,0.6,grow) * (1.0 - 0.3 * fade)
	_qd("dome",Q.ORB,1,dc,Vector2.ONE * r * 3.4,0.0,V.pal("fire",{"alpha":1.3 * (1.0 - V.seg(k,0.55,0.92)),"p0":Vector4(dome_r,0.8,0.9 * (1.0 - fade),1.0),"p1":Vector4(1.4,0.38,0.8,0.95),"p2":Vector4(0.0,2.3,0,0)}))
	# 火舌：沿穹顶上半圈向外喷出的火柱
	for j:int in _cache.size():
		var pl:Array = _cache[j]
		var kk2:float = V.seg(k,float(pl[2]),float(pl[2]) + 0.62)
		if kk2 <= 0.0 or kk2 >= 1.0: continue
		var hs:float = float(pl[1])
		var ang:float = -PI * 0.5 + clampf(float(pl[0]) / (r * 0.75),-1.0,1.0) * 1.15
		var dir:Vector2 = Vector2.from_angle(ang)
		var hh:float = r * 1.9 * hs
		_qd("pil%d" % j,Q.FIRE,0,dc + dir * (r * 0.75 + hh * 0.42),Vector2(r * 0.75,hh),ang + PI * 0.5,V.pal("fire",{"seed":float(j) * 3.7,"p0":Vector4(2.8,0.5,V.out_cubic(kk2 / 0.3) * 0.85,0.0),"p1":Vector4(V.seg(kk2,0.45,1.0) * 0.9,0.07,0.3,0.9)}))
	# 爆心闪光、冲击环、集中线
	var fl:float = 1.0 - V.seg(k,0.0,0.16)
	_qd("flash",Q.ORB,2,p,Vector2.ONE * r * 2.4,0.0,V.pal("fire",{"alpha":1.5 * fl,"p0":Vector4(lerpf(0.3,0.6,V.out_expo(k / 0.1)),1.0,0.8,0.0),"p1":Vector4(6.0,0.3,1.0,0.0)}))
	_qd("ring",Q.RING,2,p,Vector2.ONE * r * 4.2,0.0,V.pal("fire",{"alpha":1.2 * (1.0 - V.seg(k,0.1,0.4)),"p0":Vector4(0.1 + 0.85 * V.out_expo(k / 0.4),0.09 * (1.0 - k) + 0.02,0.15 + 0.7 * k,0.0),"p1":Vector4(0.012,0.7,0.6,0.0)}))
	_qd("focus",Q.FOCUS,2,p,Vector2.ONE * r * 8.0,0.0,{"alpha":0.9 * (1.0 - V.seg(k,0.0,0.2)),"c0":Color(1.0,0.9,0.7),"p0":Vector4(0.25,140.0,0.4,0.0),"p1":Vector4(24.0,0.25,0,0)})

# ================================================================= 普通层（暗部/实体）
func _draw() -> void:
	var k:float = _k()
	_parts.draw_normal(self)
	match kind:
		"world_slash":
			# 被斩开的空间碎片：黑色碎块 + 白色描边，向两侧飞散。
			var a2:Vector2 = _v("a")
			var b2:Vector2 = _v("b")
			var n2:Vector2 = (b2 - a2).orthogonal().normalized()
			for sh:Variant in _cache:
				var u:float = float(sh[0])
				var side:float = float(sh[1])
				var size:float = float(sh[2])
				var rot:float = float(sh[3]) + t * 4.0 * side
				var fly:float = V.out_cubic(V.seg(k,0.05,0.8)) * 120.0 * side
				var c:Vector2 = a2.lerp(b2,u) + n2 * fly
				var fa:float = 1.0 - V.seg(k,0.4,1.0)
				if fa <= 0.0: continue
				var pts:PackedVector2Array = [c + Vector2.from_angle(rot) * size,c + Vector2.from_angle(rot + 2.2) * size * 0.4,c + Vector2.from_angle(rot + PI) * size * 0.8,c + Vector2.from_angle(rot + 4.0) * size * 0.3]
				draw_colored_polygon(pts,Color(0.0,0.0,0.02,0.8 * fa))
				draw_polyline(pts + PackedVector2Array([pts[0]]),Color(1,1,1,0.7 * fa),1.0,true)
		"black_flash":
			var p3:Vector2 = _v("pos")
			var r3:float = _f("radius",70.0)
			V.sprite(self,"k_scorch02",p3,r3 * 2.4 * V.out_expo(k / 0.1),Color(0,0,0,0.8 * (1.0 - V.seg(k,0.2,1.0))),t * 2.0)
		"web":
			var p4:Vector2 = _v("pos")
			var r4:float = _f("radius",150.0)
			var grow:float = V.out_cubic(k / 0.25)
			var fade4:float = 1.0 - V.seg(k,0.55,1.0)
			V.sprite(self,"k_dirt02",p4,r4 * 1.4 * V.out_cubic(k / 0.2),Color(0.16,0.12,0.1,0.75 * fade4),float(_seed % 7))
			for pts4:Variant in _cache:
				var poly:PackedVector2Array = pts4
				var n4:int = maxi(2,int(poly.size() * grow))
				draw_polyline(poly.slice(0,n4),Color(0.06,0.03,0.03,0.9 * fade4),4.0,true)
			for ringi:int in 3:
				var rr:float = r4 * (ringi + 1) / 3.5 * grow
				var pts5:PackedVector2Array = []
				for pts6:Variant in _cache:
					var q:PackedVector2Array = pts6
					var idx:int = mini(q.size() - 1,int(q.size() * (ringi + 1) / 3.5))
					pts5.append(p4 + (q[idx] - p4).limit_length(rr))
				if pts5.size() > 2:
					pts5.append(pts5[0])
					draw_polyline(pts5,Color(0.08,0.04,0.04,0.7 * fade4),2.5,true)
		"red_burst":
			var p7:Vector2 = _v("pos")
			var r7:float = _f("radius",80.0)
			var scorch:float = V.seg(k,0.05,0.2) * (1.0 - V.seg(k,0.5,1.0))
			if scorch > 0.0: V.sprite(self,"k_scorch01",p7,r7 * 1.6,Color(0.1,0.02,0.02,0.55 * scorch),float(_seed % 5))
		"fuga_burst":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",160.0)
			var sc:float = V.seg(k,0.1,0.3) * (1.0 - V.seg(k,0.7,1.0))
			if sc > 0.0: V.sprite(self,"k_scorch03",p8 + Vector2(0,r8 * 0.2),r8 * 2.2,Color(0.08,0.02,0.0,0.7 * sc),float(_seed % 5),Vector2(1.0,0.6))
		"wheel_turn":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",22.0) * 2.4
			var appear:float = V.out_back(k / 0.25)
			var fade9:float = 1.0 - V.seg(k,0.6,1.0)
			var rot9:float = V.out_back(V.seg(k,0.1,0.55),2.2) * TAU / 8.0
			V.dharma_wheel(self,p9,r9 * appear,rot9,fade9)
		"text":
			_draw_text(self,false)

# ================================================================= 顶层（普通混合，在叠加光之上）
func _draw_top() -> void:
	var ci:CanvasItem = _top
	var k:float = _k()
	match kind:
		"black_flash":
			# 黑闪：黑色闪电 + 红色描边（原作配色），分叉，每 45ms 重抖一次。
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",70.0)
			var alpha:float = 1.0 - V.seg(k,0.4,1.0)
			var grow:float = V.out_expo(k / 0.12)
			_drng.seed = _seed + int(t / 0.045) * 7
			for i:int in 9:
				var ang:float = TAU * i / 9.0 + _drng.randf_range(-0.3,0.3)
				var length:float = r * _drng.randf_range(1.8,3.8) * grow
				var pts:PackedVector2Array = V.bolt(_drng,p + Vector2.from_angle(ang) * r * 0.15,p + Vector2.from_angle(ang) * length,r * 0.22,4)
				var bw:float = _drng.randf_range(0.7,1.4)
				ci.draw_polyline(pts,Color(0.95,0.05,0.12,alpha),8.0 * bw,true)
				ci.draw_polyline(pts,Color(0,0,0,alpha),3.5 * bw,true)
				if pts.size() > 8:
					var j:int = _drng.randi_range(int(pts.size() / 3.0),int(pts.size() * 2.0 / 3.0))
					var bp:PackedVector2Array = V.bolt(_drng,pts[j],pts[j] + Vector2.from_angle(ang + _drng.randf_range(-0.9,0.9)) * length * 0.45,r * 0.12,3)
					ci.draw_polyline(bp,Color(0.95,0.05,0.12,alpha),4.5,true)
					ci.draw_polyline(bp,Color(0,0,0,alpha),1.8,true)
			var core_a:float = 1.0 - V.seg(k,0.05,0.4)
			if core_a > 0.0:
				ci.draw_circle(p,r * 0.34 * grow,Color(0.95,0.05,0.12,core_a))
				ci.draw_circle(p,r * 0.26 * grow,Color(0,0,0,core_a))
		"cleave":
			# 切块落下后，目标位置的“碎块”向外错开一瞬。
			var p2:Vector2 = _v("pos")
			var r2:float = _f("radius",34.0)
			var sp:float = V.seg(k,0.35,0.6) * (1.0 - V.seg(k,0.6,1.0))
			if sp > 0.0:
				_drng.seed = _seed * 3
				for c:int in 6:
					var a:float = TAU * c / 6.0 + _drng.randf_range(-0.3,0.3)
					var q:Vector2 = p2 + Vector2.from_angle(a) * r2 * (0.35 + 0.5 * sp)
					var s:float = r2 * _drng.randf_range(0.18,0.3)
					var pts2:PackedVector2Array = [q + Vector2(-s,-s * 0.6).rotated(a),q + Vector2(s,-s * 0.4).rotated(a),q + Vector2(s * 0.7,s * 0.6).rotated(a),q + Vector2(-s * 0.8,s * 0.5).rotated(a)]
					ci.draw_colored_polygon(pts2,Color(0.12,0.0,0.02,0.75 * sp))
					ci.draw_polyline(pts2 + PackedVector2Array([pts2[0]]),Color(1,0.4,0.45,0.9 * sp),1.2,true)
		"teleport":
			# 瞬移残影：沿路径留下几道逐渐变淡的青色残像，越靠近落点越实。
			var face:String = str(data.get("face",""))
			if not face.is_empty() and ResourceLoader.exists(face):
				var tex:Texture2D = load(face)
				var fs:float = _f("fsize",40.0)
				var ga:Vector2 = _v("a")
				var gb:Vector2 = _v("b")
				for gi:int in 5:
					var gu:float = (float(gi) + 0.5) / 5.0
					var ga2:float = (0.35 + 0.45 * gu) * (1.0 - V.seg(k,0.05 + 0.12 * gu,0.45 + 0.2 * gu))
					if ga2 <= 0.0: continue
					var gp:Vector2 = ga.lerp(gb,gu) + Vector2(0,-2.0 * sin(gu * PI))
					var gs:float = fs * (1.0 + 0.12 * V.seg(k,0.0,0.5))
					ci.draw_texture_rect(tex,Rect2(gp - Vector2.ONE * gs * 0.5,Vector2.ONE * gs),false,Color(0.5,0.9,1.0,ga2))
			# 出发点：空间向内折叠成一个黑点（蓝色边）。
			var a3:Vector2 = _v("a")
			var pinch:float = 1.0 - V.seg(k,0.0,0.5)
			if pinch > 0.0:
				var rr:float = lerpf(20.0,1.5,V.out_cubic(k / 0.5))
				ci.draw_circle(a3,rr + 2.5,Color(0.6,0.95,1.0,0.9 * pinch))
				ci.draw_circle(a3,rr,Color(0,0.02,0.05,0.95 * pinch))

# ================================================================= 叠加层（光）
func _draw_add() -> void:
	var ci:CanvasItem = _add
	var k:float = _k()
	match kind:
		"ripple":
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",24.0)
			for j:int in 6:
				var ang:float = TAU * j / 6.0 + t * 1.5
				V.sparkle(ci,p + Vector2.from_angle(ang) * r * 0.9 * (1.0 - k),3.0 * (1.0 - k),Color(0.9,1,1,0.9 * (1.0 - k)),ang)
		"purple_beam":
			var flash:float = 1.0 - V.seg(k,0.0,0.1)
			if flash > 0.0: ci.draw_rect(V.screen_rect(self),Color(0.6,0.3,1.0,0.2 * flash))
		"slash":
			var a4:Vector2 = _v("a")
			var b4:Vector2 = _v("b")
			if k < 0.3: V.sprite(ci,"k_star08",a4.lerp(b4,V.out_expo(k / 0.2)),a4.distance_to(b4) * 0.3 * (1.0 - k / 0.3),Color(1,1,1,1.0 - k / 0.3),t * 8.0)
		"web":
			var p6:Vector2 = _v("pos")
			var grow6:float = V.out_cubic(k / 0.25)
			var fade6:float = 1.0 - V.seg(k,0.4,1.0)
			for pts6:Variant in _cache:
				var poly6:PackedVector2Array = pts6
				var n6:int = maxi(2,int(poly6.size() * grow6))
				ci.draw_polyline(poly6.slice(0,n6),Color(1,0.85,0.85,0.85 * fade6),1.3,true)
				# 沿辐条奔跑的斩击光点
				var run:float = fmod(t * 3.0 + float(poly6.size() % 7) * 0.13,1.0)
				var idx6:int = int(run * (n6 - 1))
				V.core(ci,poly6[idx6],5.0,Color(1,1,1,fade6))
			if k < 0.2: V.sparkle(ci,p6,40.0 * (1.0 - k / 0.2),Color(1,0.9,0.9,1.0 - k / 0.2),0.3)
		"fuga_burst":
			var fl:float = 1.0 - V.seg(k,0.0,0.12)
			if fl > 0.0: ci.draw_rect(V.screen_rect(self),Color(1.0,0.5,0.1,0.18 * fl))
		"world_slash":
			var flash7:float = 1.0 - V.seg(k,0.0,0.12)
			if flash7 > 0.0: ci.draw_rect(V.screen_rect(self),Color(1,0.95,0.95,0.12 * flash7))
		"black_flash":
			var flash8:float = 1.0 - V.seg(k,0.0,0.12)
			if flash8 > 0.0: ci.draw_rect(V.screen_rect(self),Color(0.5,0.0,0.05,0.25 * flash8))
			V.sprite(ci,"k_star08",_v("pos"),_f("radius",70.0) * 2.0 * (1.0 - k),Color(1.0,0.85,0.85,1.0 - k),t * 4.0)
		"heal":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",30.0)
			var e9:float = V.out_back(k / 0.3)
			var f9:float = 1.0 - V.seg(k,0.5,1.0)
			V.sprite(ci,"k_magic02",p9,r9 * 3.4 * e9,Color(0.45,1.0,0.6,0.8 * f9),t * 1.5)
			for i9:int in 3:
				var kk9:float = V.seg(k,i9 * 0.15,i9 * 0.15 + 0.6)
				if kk9 > 0.0 and kk9 < 1.0:
					var yy:float = -r9 * 1.5 * V.out_cubic(kk9)
					var pc:Vector2 = p9 + Vector2((i9 - 1) * r9 * 0.6,yy)
					var s9:float = 7.0 * (1.0 - kk9 * 0.5)
					ci.draw_line(pc - Vector2(s9,0),pc + Vector2(s9,0),Color(0.6,1,0.7,1.0 - kk9),3.0,true)
					ci.draw_line(pc - Vector2(0,s9),pc + Vector2(0,s9),Color(0.6,1,0.7,1.0 - kk9),3.0,true)
		"thunder":
			var p10:Vector2 = _v("pos")
			var r10:float = _f("radius",70.0)
			var strikes:Array[float] = [0.0,0.18,0.34]
			for si:int in strikes.size():
				var kk10:float = V.seg(k,strikes[si],strikes[si] + 0.22)
				if kk10 <= 0.0 or kk10 >= 1.0: continue
				_drng.seed = _seed + si * 31 + int(t / 0.04)
				var top:Vector2 = p10 + Vector2(_drng.randf_range(-60,60),-520)
				var pts10:PackedVector2Array = V.bolt(_drng,top,p10 + Vector2(_drng.randf_range(-r10,r10) * 0.3,0),60.0,6)
				V.draw_bolt(ci,pts10,3.0 * (1.0 - kk10) + 1.2,Color(0.55,0.75,1.0,1.0 - kk10),Color(1,1,1,1.0 - kk10))
				for bi:int in 3:
					var from_i:int = _drng.randi_range(4,pts10.size() - 8)
					var br:PackedVector2Array = V.bolt(_drng,pts10[from_i],pts10[from_i] + Vector2(_drng.randf_range(-90,90),_drng.randf_range(20,120)),20.0,4)
					V.draw_bolt(ci,br,1.2,Color(0.55,0.75,1.0,0.7 * (1.0 - kk10)),Color(1,1,1,0.8 * (1.0 - kk10)))
				V.sprite_line(ci,"k_spark06" if si % 2 == 0 else "k_spark05",top,p10,r10 * 1.1,Color(0.7,0.85,1.0,0.8 * (1.0 - kk10)),true)
				if kk10 < 0.3: ci.draw_rect(V.screen_rect(self),Color(0.7,0.85,1.0,0.1 * (1.0 - kk10 / 0.3)))
			V.sprite(ci,"k_scorch01",p10,r10 * 2.2 * V.out_expo(k / 0.2),Color(0.6,0.8,1.0,0.6 * (1.0 - k)))
		"teleport":
			var b11:Vector2 = _v("b")
			V.core(ci,b11,20.0 * (1.0 - V.seg(k,0.0,0.3)),Color(1,1,1,1.0 - V.seg(k,0.0,0.3)))
		"wheel_turn":
			var p12:Vector2 = _v("pos")
			var r12:float = _f("radius",22.0) * 2.4
			var appear:float = V.out_back(k / 0.25)
			var fade12:float = 1.0 - V.seg(k,0.6,1.0)
			var rot12:float = V.out_back(V.seg(k,0.1,0.55),2.2) * TAU / 8.0
			V.dharma_wheel_glow(ci,p12,r12 * appear,rot12,fade12)
		"text":
			_draw_text(ci,true)
	_parts.draw_add(ci)

# ================================================================= 文字
func _draw_text(ci:CanvasItem,additive:bool) -> void:
	var p:Vector2 = _v("pos")
	var text:String = str(data.get("text",""))
	var size:int = int(data.get("size",34))
	var c:Color = _c("color",Color.WHITE)
	var font:Font = ThemeDB.fallback_font
	var k:float = _k()
	var big:bool = size >= 30
	var alpha:float = clampf(minf(1.0,t * 8.0) * minf(1.0,(life - t) * 3.0),0.0,1.0)
	var width:float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	var pop:float = V.out_back(minf(1.0,t / 0.22),2.5)
	var rise:float = 0.0 if big else -14.0 * V.out_cubic(k)
	var origin:Vector2 = p + Vector2(0,rise)
	if big:
		# 领域名：毛笔墨带自左向右刷开，文字逐字浮现，外发光。
		var brush:float = V.out_cubic(t / 0.35)
		var band_w:float = (width + size * 2.0) * brush
		var left:Vector2 = origin + Vector2(-(width + size * 2.0) * 0.5,0.0)
		if not additive:
			var pts:PackedVector2Array = []
			var steps:int = 24
			for i:int in steps + 1:
				var u:float = float(i) / steps
				pts.append(left + Vector2(band_w * u,-size * 0.62 * (0.85 + 0.15 * sin(u * 17.0 + _seed))))
			for i2:int in range(steps,-1,-1):
				var u2:float = float(i2) / steps
				pts.append(left + Vector2(band_w * u2,size * 0.62 * (0.85 + 0.15 * cos(u2 * 13.0 + _seed))))
			if band_w > 2.0: ci.draw_colored_polygon(pts,Color(0.02,0.0,0.02,0.78 * alpha))
			var shown:int = int(ceil(text.length() * V.seg(t,0.12,0.12 + 0.05 * text.length())))
			var x:float = -width * 0.5
			for ch:int in text.length():
				var cs:String = text.substr(ch,1)
				var cw:float = font.get_string_size(cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
				if ch < shown:
					var ct:float = clampf((t - 0.12 - 0.05 * ch) / 0.18,0.0,1.0)
					var scl:float = lerpf(1.6,1.0,V.out_cubic(ct))
					var at:Vector2 = origin + Vector2(x,size * 0.35)
					ci.draw_set_transform(at + Vector2(cw * 0.5,-size * 0.35),0.0,Vector2(scl,scl))
					ci.draw_string_outline(font,Vector2(-cw * 0.5,size * 0.35),cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size,JJK_FONT_OUTLINE,Color(0,0,0,0.9 * alpha * ct))
					ci.draw_string(font,Vector2(-cw * 0.5,size * 0.35),cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(c,alpha * ct))
					ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
				x += cw
		else:
			V.streak(ci,origin + Vector2(-width * 0.6,0),origin + Vector2(width * 0.6,0),size * 2.2,Color(c,0.35 * alpha))
			var sweep:float = V.seg(t,0.2,0.9)
			if sweep > 0.0 and sweep < 1.0:
				var sx:float = lerpf(-width * 0.6,width * 0.6,sweep)
				V.streak(ci,origin + Vector2(sx - 30,-size * 0.4),origin + Vector2(sx + 30,size * 0.4),size * 0.6,Color(1,1,1,0.6 * alpha))
		return
	if additive:
		V.glow(ci,origin,width * 0.7 + size,Color(c,0.25 * alpha))
		return
	ci.draw_set_transform(origin,0.0,Vector2(pop,pop))
	var at2:Vector2 = Vector2(-width * 0.5,size * 0.35)
	ci.draw_string_outline(font,at2 + Vector2(2,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,6,Color(0,0,0,0.5 * alpha))
	ci.draw_string_outline(font,at2,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,5,Color(0,0,0,0.9 * alpha))
	ci.draw_string(font,at2,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(c,alpha))
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

# ================================================================= 演出：扭曲 / 后处理 / 震屏 / 顿帧 / 推镜
func _juice() -> void:
	match kind:
		"red_burst":
			var r:float = _f("radius",80.0)
			V.distort(self,0,_v("pos"),Vector2.ONE * r * 5.0,0.45,30.0)
			V.shake(self,7.0)
			V.zoom_punch(self,_v("pos"),0.35)
		"purple_beam":
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			var w:float = _f("width",90.0)
			var big:float = clampf(w / 90.0,0.6,2.0)
			V.screen(self,a,life,{"blur":0.012 * big,"flash":Color(0.8,0.6,1.0,0.4),"flash_time":0.14,"vignette":0.35,"tint":Color(0.7,0.5,1.0,0.25)},Vector3(0.05,0.35,1.0))
			V.distort(self,0,a,Vector2.ONE * w * 7.0,0.6,40.0 * big)
			V.distort(self,2,a.lerp(b,0.5),Vector2(a.distance_to(b),w * 2.4),life,7.0 * big,{"rot_angle":(b - a).angle()})
			V.shake(self,12.0 * big,(b - a))
			V.hitstop(self,1.0,a)
			V.zoom_punch(self,a,0.8)
		"cleave":
			V.distort(self,0,_v("pos"),Vector2.ONE * _f("radius",34.0) * 5.0,0.35,14.0)
			V.shake(self,3.0)
		"web":
			V.distort(self,0,_v("pos"),Vector2.ONE * _f("radius",150.0) * 2.6,0.5,16.0)
			V.shake(self,5.0)
		"fuga_burst":
			var r5:float = _f("radius",160.0)
			V.distort(self,0,_v("pos"),Vector2.ONE * r5 * 5.0,0.6,42.0)
			V.screen(self,_v("pos"),0.7,{"blur":0.01,"tint":Color(1.0,0.55,0.25,0.22),"flash":Color(1.0,0.75,0.4,0.35),"flash_time":0.1,"vignette":0.3})
			V.shake(self,12.0)
			V.hitstop(self,0.8,_v("pos"))
			V.zoom_punch(self,_v("pos"),0.7)
		"world_slash":
			var a6:Vector2 = _v("a")
			var b6:Vector2 = _v("b")
			var mid:Vector2 = a6.lerp(b6,0.5)
			V.screen(self,mid,0.9,{"invert":1.0,"invert_time":0.07,"blur":0.0,"flash":Color(1,1,1,0.3),"flash_time":0.05,"desat":0.35},Vector3(0.02,0.25,1.0))
			V.distort(self,2,mid,Vector2(a6.distance_to(b6),_f("width",70.0) * 4.0),life,26.0,{"rot_angle":(b6 - a6).angle()})
			V.shake(self,18.0,(b6 - a6).orthogonal())
			V.hitstop(self,1.0,mid)
			V.zoom_punch(self,mid,0.6)
		"black_flash":
			var p8:Vector2 = _v("pos")
			V.screen(self,p8,0.4,{"invert":1.0,"invert_time":0.07,"blur":0.008,"tint":Color(1.0,0.3,0.3,0.2)},Vector3(0.02,0.2,1.0))
			V.distort(self,0,p8,Vector2.ONE * _f("radius",70.0) * 4.5,0.4,32.0)
			V.shake(self,9.0)
			V.hitstop(self,1.0,p8)
			V.zoom_punch(self,p8,0.9)
		"thunder":
			var p10:Vector2 = _v("pos")
			V.distort(self,0,p10,Vector2.ONE * _f("radius",70.0) * 4.0,0.4,20.0)
			V.screen(self,p10,0.3,{"flash":Color(0.8,0.9,1.0,0.35),"flash_time":0.08})
			V.shake(self,6.0)
		"teleport":
			V.distort(self,0,_v("b"),Vector2.ONE * 160.0,0.35,18.0)
		"shockwave":
			var r13:float = _f("radius",200.0)
			if r13 >= 60.0: V.distort(self,0,_v("pos"),Vector2.ONE * r13 * 2.3,life,16.0 + r13 * 0.04)
		"wheel_turn":
			V.distort(self,0,_v("pos"),Vector2.ONE * 160.0,0.5,12.0)
