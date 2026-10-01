extends Node2D
## 可复用的我的世界烟花：按 Java 1.21.4 的烟花火箭和烟花粒子规则模拟（20 tick/秒）。
## 不注册 class_name，用 load() 取脚本：
##   FW.launch(parent, from, options)  火箭从 from 升空，飞行结束后炸开
##   FW.burst(parent, at, options)     直接在 at 炸开（只要最后的特效）
##   FW.celebrate(parent, options)     比赛结束：从屏幕下方随机放一批火箭
## 选项都可省略（缺省随机）：
##   explosions:Array[Dictionary] 每个 {shape, colors, fade_colors, trail, twinkle}；只有一个爆炸时可直接写在 options 里
##   shape: small_ball / large_ball / star / creeper / burst；colors / fade_colors: Color 或染料名
##   flight:int 1..3（火药数）；velocity:Vector2 初速度（格/tick，y 向上为正）
##   unit: 每格像素；particle_scale: 粒子放大；screen_space: 坐标按屏幕像素，节点挂在世界画布里跟随镜头（录制画面也能拍到）
##   sound:bool；listener_distance: 听者距离（格），≥16 用远处音效，>10 声音按距离延迟；volume_db；seed；pausable

const SELF_PATH:String = "res://scripts/effects/我的世界/mc_firework.gd"
const TEXTURE_DIR:String = "res://Images/effects/我的世界/firework/"
const AUDIO_DIR:String = "res://audio/effects/我的世界/firework/"
const TICK:float = 0.05
const SHAPES:Array[String] = ["small_ball","large_ball","star","creeper","burst"]
const DYE_COLORS:Dictionary = {
	"white":Color8(0xF0,0xF0,0xF0),"orange":Color8(0xEB,0x88,0x44),"magenta":Color8(0xC3,0x54,0xCD),
	"light_blue":Color8(0x66,0x89,0xD3),"yellow":Color8(0xDE,0xCF,0x2A),"lime":Color8(0x41,0xCD,0x34),
	"pink":Color8(0xD8,0x81,0x98),"gray":Color8(0x43,0x43,0x43),"light_gray":Color8(0xAB,0xAB,0xAB),
	"cyan":Color8(0x28,0x76,0x97),"purple":Color8(0x7B,0x2F,0xBE),"blue":Color8(0x25,0x31,0x92),
	"brown":Color8(0x51,0x30,0x1A),"green":Color8(0x3B,0x51,0x1A),"red":Color8(0xB3,0x31,0x2C),
	"black":Color8(0x1E,0x1B,0x1B),
}
## 随机烟花只挑在亮色地图上也看得清的颜色（指定颜色时 16 种染料都能用）。
const BRIGHT_DYES:Array[String] = ["white","orange","magenta","light_blue","yellow","lime","pink","cyan","purple","red"]
const STAR_POINTS:Array[Vector2] = [Vector2(0.0,1.0),Vector2(0.3455,0.309),Vector2(0.9511,0.309),Vector2(0.3795918367346939,-0.12653061224489795),Vector2(0.6122448979591837,-0.8040816326530612),Vector2(0.0,-0.35918367346938773)]
const CREEPER_POINTS:Array[Vector2] = [Vector2(0.0,0.2),Vector2(0.2,0.2),Vector2(0.2,0.6),Vector2(0.6,0.6),Vector2(0.6,0.2),Vector2(0.2,0.2),Vector2(0.2,0.0),Vector2(0.4,0.0),Vector2(0.4,-0.6),Vector2(0.2,-0.6),Vector2(0.2,-0.4),Vector2(0.0,-0.4)]

## 一组火花（打包数组，避免每个粒子一个对象）。模拟和绘制都在类内部做，
## 外部写 obj.packed[i] 会触发整数组写时复制。
class SparkSet:
	const TRAIL:int = 1
	const TWINKLE:int = 2
	const FADE:int = 4
	const CAP:int = 6000
	var x := PackedFloat32Array(); var y := PackedFloat32Array()
	var ox := PackedFloat32Array(); var oy := PackedFloat32Array()
	var vx := PackedFloat32Array(); var vy := PackedFloat32Array()
	var r := PackedFloat32Array(); var g := PackedFloat32Array(); var b := PackedFloat32Array()
	var fr := PackedFloat32Array(); var fg := PackedFloat32Array(); var fb := PackedFloat32Array()
	var a := PackedFloat32Array(); var size := PackedFloat32Array()
	var age := PackedInt32Array(); var life := PackedInt32Array(); var flags := PackedInt32Array()
	func count() -> int: return x.size()
	func add(px:float,py:float,pvx:float,pvy:float,plife:int,page:int,color:Color,fade:Color,pflags:int,psize:float) -> void:
		if x.size() >= CAP: return
		x.append(px); y.append(py); ox.append(px); oy.append(py); vx.append(pvx); vy.append(pvy)
		r.append(color.r); g.append(color.g); b.append(color.b); fr.append(fade.r); fg.append(fade.g); fb.append(fade.b)
		a.append(0.99); size.append(psize); age.append(page); life.append(plife); flags.append(pflags)
	## Particle.tick + SimpleAnimatedParticle.tick + SparkParticle.tick（拖尾子火花放进 trails）。
	func tick(random:RandomNumberGenerator, trails:SparkSet) -> void:
		var n:int = x.size()
		if n == 0: return
		var alive := PackedByteArray()
		alive.resize(n)
		var removed:bool = false
		for i:int in range(n):
			ox[i] = x[i]; oy[i] = y[i]
			var old_age:int = age[i]
			var span:int = life[i]
			age[i] = old_age + 1
			if old_age >= span:
				removed = true
				continue
			alive[i] = 1
			var now_age:int = old_age + 1
			vy[i] -= 0.004
			x[i] += vx[i]; y[i] += vy[i]
			vx[i] *= 0.91; vy[i] *= 0.91
			var half:int = span / 2
			var bits:int = flags[i]
			if now_age > half:
				a[i] = 1.0 - float(now_age - half) / float(span)
				if bits & FADE:
					r[i] += (fr[i] - r[i]) * 0.2
					g[i] += (fg[i] - g[i]) * 0.2
					b[i] += (fb[i] - b[i]) * 0.2
			if trails != null and bits & TRAIL and now_age < half and (now_age + span) % 2 == 0:
				var child_life:int = 48 + random.randi_range(0,11)
				trails.add(x[i],y[i],0.0,0.0,child_life,child_life / 2,Color(r[i],g[i],b[i]),Color(fr[i],fg[i],fb[i]),bits & (TWINKLE | FADE),0.1 * (random.randf() * 0.5 + 0.5) * 2.0 * 0.75)
		if removed: _keep(alive)
	func draw_on(canvas:CanvasItem, frames:Array[Texture2D], unit:float, px_scale:float, partial:float) -> void:
		if frames.size() != 8: return
		for i:int in range(x.size()):
			var now_age:int = age[i]
			var span:int = life[i]
			if flags[i] & TWINKLE and now_age >= span / 3 and ((now_age + span) / 3) % 2 != 0: continue
			var cx:float = lerpf(ox[i],x[i],partial) * unit
			var cy:float = -lerpf(oy[i],y[i],partial) * unit
			var extent:float = size[i] * px_scale
			canvas.draw_texture_rect(frames[clampi(now_age * 7 / maxi(span,1),0,7)],Rect2(cx - extent,cy - extent,extent * 2.0,extent * 2.0),false,Color(r[i],g[i],b[i],a[i]))
	func _keep(alive:PackedByteArray) -> void:
		var w:int = 0
		for i:int in range(x.size()):
			if alive[i] == 0: continue
			if w != i:
				x[w]=x[i]; y[w]=y[i]; ox[w]=ox[i]; oy[w]=oy[i]; vx[w]=vx[i]; vy[w]=vy[i]
				r[w]=r[i]; g[w]=g[i]; b[w]=b[i]; fr[w]=fr[i]; fg[w]=fg[i]; fb[w]=fb[i]
				a[w]=a[i]; size[w]=size[i]; age[w]=age[i]; life[w]=life[i]; flags[w]=flags[i]
			w += 1
		x.resize(w); y.resize(w); ox.resize(w); oy.resize(w); vx.resize(w); vy.resize(w)
		r.resize(w); g.resize(w); b.resize(w); fr.resize(w); fg.resize(w); fb.resize(w)
		a.resize(w); size.resize(w); age.resize(w); life.resize(w); flags.resize(w)

var unit:float = 16.0
var particle_scale:float = 1.0
var screen_space:bool = false
var sound_enabled:bool = true
var listener_distance:float = 0.0
var volume_db:float = 0.0
var pausable:bool = false
var auto_free:bool = true
var rng := RandomNumberGenerator.new()

## 主火花每帧插值重绘；拖尾留下的静止火花只在 tick 时重绘（数量多、几乎不动）。
var sparks := SparkSet.new()
var trail_sparks := SparkSet.new()
var rockets:Array[Dictionary] = []
var starters:Array[Dictionary] = []
var flashes:Array[Dictionary] = []
var _sounds:Array[Dictionary] = []
var _schedule:Array[Dictionary] = []
var _show_view:Vector2 = Vector2.ZERO
var tick_count:int = 0
var _accum:float = 0.0
var _last_usec:int = 0
var _players:int = 0
var _trail_layer:Node2D
var _frames:Array[Texture2D] = []
var _flash_texture:Texture2D
var _rocket_texture:Texture2D

static func launch(parent:Node, from:Vector2, options:Dictionary = {}) -> Node2D:
	var node = _create(parent,options)
	node.add_rocket(from,options)
	return node

static func burst(parent:Node, at:Vector2, options:Dictionary = {}) -> Node2D:
	var node = _create(parent,options)
	node.add_burst(at,options)
	return node

## 从屏幕底部随机放 count 支火箭（duration 秒内放完，开头先齐射几支）。
static func celebrate(parent:Node, options:Dictionary = {}) -> Node2D:
	var settings:Dictionary = options.duplicate()
	settings["screen_space"] = true
	if not settings.has("listener_distance"): settings["listener_distance"] = 20.0
	var node = _create(parent,settings)
	node.name = "MinecraftFireworkShow"
	node.plan_show(int(settings.get("count",node.rng.randi_range(10,14))),float(settings.get("duration",2.6)),settings)
	return node

static func _create(parent:Node, options:Dictionary) -> Node2D:
	var node = (load(SELF_PATH) as GDScript).new()
	node.configure(options)
	parent.add_child(node)
	return node

static func random_explosion(random:RandomNumberGenerator) -> Dictionary:
	var roll:float = random.randf()
	var shape:String = "small_ball" if roll < 0.30 else "large_ball" if roll < 0.55 else "star" if roll < 0.70 else "creeper" if roll < 0.80 else "burst"
	var colors:Array = []
	for i:int in range(random.randi_range(1,3)): colors.append(DYE_COLORS[BRIGHT_DYES[random.randi() % BRIGHT_DYES.size()]])
	var fades:Array = []
	if random.randf() < 0.4:
		for i:int in range(random.randi_range(1,2)): fades.append(DYE_COLORS[BRIGHT_DYES[random.randi() % BRIGHT_DYES.size()]])
	return {"shape":shape,"colors":colors,"fade_colors":fades,"trail":random.randf() < 0.35,"twinkle":random.randf() < 0.35}

func configure(options:Dictionary) -> void:
	unit = maxf(float(options.get("unit",unit)),0.01)
	particle_scale = float(options.get("particle_scale",particle_scale))
	screen_space = bool(options.get("screen_space",screen_space))
	sound_enabled = bool(options.get("sound",sound_enabled))
	listener_distance = float(options.get("listener_distance",listener_distance))
	volume_db = float(options.get("volume_db",volume_db))
	pausable = bool(options.get("pausable",pausable))
	if options.has("seed"): rng.seed = int(options.seed)
	else: rng.randomize()

func _init() -> void:
	name = "MinecraftFirework"
	top_level = true
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i:int in range(7,-1,-1): _frames.append(load(TEXTURE_DIR + "spark_%d.png" % i) as Texture2D)
	_flash_texture = load(TEXTURE_DIR + "flash.png") as Texture2D
	_rocket_texture = load(TEXTURE_DIR + "firework_rocket.png") as Texture2D
	_trail_layer = Node2D.new()
	_trail_layer.name = "Trails"
	_trail_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_trail_layer.draw.connect(_draw_trail_layer)
	add_child(_trail_layer)

func _ready() -> void:
	_last_usec = Time.get_ticks_usec()
	_follow_screen()

## 画布坐标 ↔ 方块坐标（y 向上为正，和我的世界一致）。
func to_blocks(local:Vector2) -> Vector2: return Vector2(local.x / unit, -local.y / unit)
func to_local_px(blocks:Vector2) -> Vector2: return Vector2(blocks.x * unit, -blocks.y * unit)

func add_rocket(from:Vector2, options:Dictionary = {}) -> void:
	var flight:int = clampi(int(options.get("flight",rng.randi_range(1,2))),0,3)
	var start:Vector2 = to_blocks(from)
	var velocity:Vector2 = options.get("velocity",Vector2(rng.randfn(0.0,1.0) * 0.001,0.05))
	rockets.append({"x":start.x,"y":start.y,"ox":start.x,"oy":start.y,"vx":velocity.x,"vy":velocity.y,"life":0,
		"lifetime":10 * (flight + 1) + rng.randi_range(0,5) + rng.randi_range(0,6),
		"accelerate":not bool(options.get("shot_at_angle",false)),"explosions":_explosions_from(options)})

func add_burst(at:Vector2, options:Dictionary = {}) -> void:
	var p:Vector2 = to_blocks(at)
	var velocity:Vector2 = options.get("velocity",Vector2.ZERO)
	_add_starter(p.x,p.y,velocity.x,velocity.y,_explosions_from(options))

func plan_show(count:int, duration:float, options:Dictionary = {}) -> void:
	_show_view = get_viewport_rect().size if is_inside_tree() else Vector2(540,960)
	unit = float(options.get("unit",_show_view.y / 40.0))
	particle_scale = float(options.get("particle_scale",1.5))
	var opening:int = mini(3,count)
	for i:int in range(count):
		var at:float = 0.0 if i < opening else rng.randf_range(0.25,maxf(duration,0.3))
		_schedule.append({"tick":int(round(at / TICK)) + (i % opening if i < opening else 0) * 3})
	_schedule.sort_custom(func(l:Dictionary,r:Dictionary) -> bool: return int(l.tick) < int(r.tick))

func is_finished() -> bool:
	return rockets.is_empty() and starters.is_empty() and flashes.is_empty() and sparks.count() == 0 and trail_sparks.count() == 0 and _sounds.is_empty() and _schedule.is_empty() and _players == 0

## 测试/离线逐 tick 推进。
func step_ticks(count:int) -> void:
	for i:int in range(count): _tick()
	queue_redraw()
	_trail_layer.queue_redraw()

func _process(_delta:float) -> void:
	# 和门转场一样用 Time：离线录制会把它换成模拟时间；游戏暂停/慢放时烟花照常。
	var now:int = Time.get_ticks_usec()
	var frame:float = clampf(float(now - _last_usec) / 1000000.0,0.0,0.25)
	_last_usec = now
	_follow_screen()
	if pausable and get_tree().paused: return
	_accum += frame
	var ticked:bool = false
	while _accum >= TICK:
		_accum -= TICK
		_tick()
		ticked = true
	if ticked: _trail_layer.queue_redraw()
	queue_redraw()
	if auto_free and is_finished(): queue_free()

func _follow_screen() -> void:
	if not screen_space or not is_inside_tree() or get_canvas_layer_node() != null: return
	var viewport:Viewport = get_viewport()
	global_transform = (viewport.global_canvas_transform * viewport.get_canvas_transform()).affine_inverse()

func _tick() -> void:
	tick_count += 1
	while not _schedule.is_empty() and int(_schedule[0].tick) <= tick_count:
		_schedule.pop_front()
		_launch_show_rocket()
	for i:int in range(rockets.size() - 1,-1,-1):
		var rocket:Dictionary = rockets[i]
		rocket.ox = rocket.x; rocket.oy = rocket.y
		if rocket.accelerate:
			rocket.vx *= 1.15
			rocket.vy += 0.04
		rocket.x += rocket.vx; rocket.y += rocket.vy
		if int(rocket.life) == 0: _play("launch1",0,-4.0,1.0)
		rocket.life += 1
		_add_spark(sparks,rocket.x,rocket.y,rng.randfn(0.0,1.0) * 0.05,-float(rocket.vy) * 0.5,Color.WHITE,[],false,false)
		if int(rocket.life) > int(rocket.lifetime):
			rockets.remove_at(i)
			_add_starter(rocket.x,rocket.y,rocket.vx,rocket.vy,rocket.explosions)
	for i:int in range(starters.size() - 1,-1,-1):
		if _tick_starter(starters[i]): starters.remove_at(i)
	for i:int in range(flashes.size() - 1,-1,-1):
		var flash:Dictionary = flashes[i]
		flash.age += 1
		if int(flash.age) > 4: flashes.remove_at(i)
	sparks.tick(rng,trail_sparks)
	trail_sparks.tick(rng,null)
	for i:int in range(_sounds.size() - 1,-1,-1):
		if int(_sounds[i].tick) <= tick_count:
			var row:Dictionary = _sounds[i]
			_sounds.remove_at(i)
			_start_player(str(row.name),float(row.db),float(row.pitch))

func _launch_show_rocket() -> void:
	var view:Vector2 = _show_view if _show_view.x > 0.0 else get_viewport_rect().size
	var from:Vector2 = Vector2(rng.randf_range(view.x * 0.15,view.x * 0.85),view.y + unit * 0.5)
	add_rocket(from,{"flight":rng.randi_range(1,2)})

func _add_starter(x:float, y:float, vx:float, vy:float, explosions:Array) -> void:
	var twinkle:bool = false
	for e:Dictionary in explosions: twinkle = twinkle or bool(e.twinkle)
	starters.append({"x":x,"y":y,"vx":vx,"vy":vy,"life":0,"lifetime":explosions.size() * 2 - 1,"explosions":explosions,"twinkle":twinkle})

## FireworkParticles.Starter：第 0 tick 出爆炸声，每 2 tick 炸开一个爆炸，结束时有闪烁就出噼啪声。
func _tick_starter(s:Dictionary) -> bool:
	var explosions:Array = s.explosions
	var life:int = int(s.life)
	var far:bool = listener_distance >= 16.0
	if life == 0:
		var large:bool = explosions.size() >= 3
		for e:Dictionary in explosions: large = large or str(e.shape) == "large_ball"
		var sound:String = ("largeblast" if large else "blast") + ("_far1" if far else "1")
		_play(sound,_distance_delay(),0.0,0.95 + rng.randf() * 0.1)
	if life % 2 == 0 and life / 2 < explosions.size():
		_explode(explosions[life / 2],float(s.x),float(s.y),float(s.vx),float(s.vy))
	s.life = life + 1
	if int(s.life) > int(s.lifetime):
		if bool(s.twinkle): _play("twinkle_far1" if far else "twinkle1",_distance_delay(),-2.0,0.9 + rng.randf() * 0.15)
		return true
	return false

func _explode(e:Dictionary, x:float, y:float, vx:float, vy:float) -> void:
	var colors:Array = e.colors
	var fades:Array = e.fade_colors
	var trail:bool = bool(e.trail)
	var twinkle:bool = bool(e.twinkle)
	match str(e.shape):
		"large_ball": _ball(x,y,0.5,4,colors,fades,trail,twinkle)
		"star": _shape(x,y,0.5,STAR_POINTS,colors,fades,trail,twinkle,false)
		"creeper": _shape(x,y,0.5,CREEPER_POINTS,colors,fades,trail,twinkle,true)
		"burst": _burst(x,y,vx,vy,colors,fades,trail,twinkle)
		_: _ball(x,y,0.25,2,colors,fades,trail,twinkle)
	flashes.append({"x":x,"y":y,"age":0,"color":colors[0] as Color})

func _ball(x:float, y:float, speed:float, size:int, colors:Array, fades:Array, trail:bool, twinkle:bool) -> void:
	for i:int in range(-size,size + 1):
		for j:int in range(-size,size + 1):
			var k:int = -size
			while k <= size:
				var dx:float = j + (rng.randf() - rng.randf()) * 0.5
				var dy:float = i + (rng.randf() - rng.randf()) * 0.5
				var dz:float = k + (rng.randf() - rng.randf()) * 0.5
				var d:float = sqrt(dx * dx + dy * dy + dz * dz) / speed + rng.randfn(0.0,1.0) * 0.05
				_add_spark(sparks,x,y,dx / d,dy / d,colors,fades,trail,twinkle)
				if i != -size and i != size and j != -size and j != size: k += size * 2 - 1
				k += 1

func _shape(x:float, y:float, speed:float, points:Array[Vector2], colors:Array, fades:Array, trail:bool, twinkle:bool, creeper:bool) -> void:
	_add_spark(sparks,x,y,points[0].x * speed,points[0].y * speed,colors,fades,trail,twinkle)
	var start:float = rng.randf() * PI
	var spread:float = 0.034 if creeper else 0.34
	for turn:int in range(3):
		var angle:float = start + turn * PI * spread
		var previous:Vector2 = points[0]
		for j:int in range(1,points.size()):
			var t:float = 0.25
			while t <= 1.0:
				var px:float = lerpf(previous.x,points[j].x,t) * speed
				var py:float = lerpf(previous.y,points[j].y,t) * speed
				# 3D 绕竖轴转后投影到屏幕：横向乘 cos，纵深丢掉。
				var across:float = px * cos(angle)
				_add_spark(sparks,x,y,-across,py,colors,fades,trail,twinkle)
				_add_spark(sparks,x,y,across,py,colors,fades,trail,twinkle)
				t += 0.25
			previous = points[j]

func _burst(x:float, y:float, vx:float, vy:float, colors:Array, fades:Array, trail:bool, twinkle:bool) -> void:
	var drift:float = rng.randfn(0.0,1.0) * 0.05
	for i:int in range(70):
		_add_spark(sparks,x,y,vx * 0.5 + rng.randfn(0.0,1.0) * 0.15 + drift,vy * 0.5 + rng.randf() * 0.5,colors,fades,trail,twinkle)

func _add_spark(target:SparkSet, x:float, y:float, vx:float, vy:float, color_value:Variant, fades:Array, trail:bool, twinkle:bool) -> void:
	var color:Color = color_value as Color if color_value is Color else (color_value as Array)[rng.randi() % (color_value as Array).size()] as Color
	var flags:int = (SparkSet.TRAIL if trail else 0) | (SparkSet.TWINKLE if twinkle else 0)
	var fade:Color = color
	if not fades.is_empty():
		fade = fades[rng.randi() % fades.size()] as Color
		flags |= SparkSet.FADE
	target.add(x,y,vx,vy,48 + rng.randi_range(0,11),0,color,fade,flags,0.1 * (rng.randf() * 0.5 + 0.5) * 2.0 * 0.75)

func _distance_delay() -> int:
	# ClientLevel.playLocalSound(distanceDelay)：超过 10 格按 40 格/秒延迟。
	return int(listener_distance / 40.0 * 20.0) if listener_distance > 10.0 else 0

func _play(sound_name:String, delay_ticks:int, db:float, pitch:float) -> void:
	if not sound_enabled: return
	if delay_ticks <= 0: _start_player(sound_name,db,pitch)
	else: _sounds.append({"tick":tick_count + delay_ticks,"name":sound_name,"db":db,"pitch":pitch})

func _start_player(sound_name:String, db:float, pitch:float) -> void:
	var stream:AudioStream = load(AUDIO_DIR + sound_name + ".ogg") as AudioStream
	if stream == null: return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = db + volume_db
	player.pitch_scale = pitch
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = &"GameplayRecord" if AudioServer.get_bus_index(&"GameplayRecord") >= 0 else &"Master"
	_players += 1
	player.finished.connect(func() -> void:
		_players -= 1
		player.queue_free())
	add_child(player)
	player.play()

func _explosions_from(options:Dictionary) -> Array:
	var raw:Array = options.get("explosions",[]) if options.get("explosions",[]) is Array else []
	if raw.is_empty(): raw = [options]
	var result:Array = []
	for value:Variant in raw:
		var e:Dictionary = value if value is Dictionary else {}
		var fallback:Dictionary = random_explosion(rng)
		var shape:String = str(e.get("shape",fallback.shape))
		var colors:Array = _colors(e.get("colors",[]))
		result.append({"shape":shape if SHAPES.has(shape) else "small_ball",
			"colors":colors if not colors.is_empty() else fallback.colors,
			"fade_colors":_colors(e.get("fade_colors",fallback.fade_colors if not e.has("colors") else [])),
			"trail":bool(e.get("trail",fallback.trail)),"twinkle":bool(e.get("twinkle",fallback.twinkle))})
	return result

func _colors(values:Variant) -> Array:
	var out:Array = []
	if not values is Array: values = [values]
	for value:Variant in values:
		if value is Color: out.append(value)
		elif value is String or value is StringName:
			if DYE_COLORS.has(str(value)): out.append(DYE_COLORS[str(value)])
	return out

func _partial() -> float: return clampf(_accum / TICK,0.0,1.0)

func _draw() -> void:
	var partial:float = _partial()
	for flash:Dictionary in flashes:
		var phase:float = float(flash.age) + partial - 1.0
		var half:float = 7.1 * sin(phase * 0.25 * PI)
		if half <= 0.0: continue
		var color:Color = flash.color
		color.a = clampf(0.6 - phase * 0.125,0.0,1.0)
		var center:Vector2 = to_local_px(Vector2(flash.x,flash.y))
		var extent:Vector2 = Vector2.ONE * half * unit
		draw_texture_rect(_flash_texture,Rect2(center - extent,extent * 2.0),false,color)
	sparks.draw_on(self,_frames,unit,unit * particle_scale,partial)
	if _rocket_texture != null:
		var rocket_size:Vector2 = Vector2.ONE * unit * 0.75 * particle_scale
		for rocket:Dictionary in rockets:
			var p:Vector2 = to_local_px(Vector2(lerpf(rocket.ox,rocket.x,partial),lerpf(rocket.oy,rocket.y,partial)))
			draw_set_transform(p,Vector2(float(rocket.vx),-float(rocket.vy)).angle() + PI * 0.5)
			draw_texture_rect(_rocket_texture,Rect2(-rocket_size * 0.5,rocket_size),false)
		draw_set_transform(Vector2.ZERO)

func _draw_trail_layer() -> void:
	trail_sparks.draw_on(_trail_layer,_frames,unit,unit * particle_scale,1.0)

