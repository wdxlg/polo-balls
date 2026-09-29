extends Area2D
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")
# 天陨落箭（纯白发光剪影）：按计划陆续从画面上缘之外坠入，形成持续一段时间的箭雨；
# 下落是真实的速度积分（重力加速），不是按时间参数化的位移动画，
# 且仍按 delay 精确落地（快于纯重力用时给初速度，慢则先在屏幕外悬停）。
# 绘制层级高于地图外遮罩（z=90），坠落途中经过岛外虚空不会被裁掉。
# 落地造成小范围伤害并轻微减速，同时在落点从中心撕开网状小裂缝；
# 箭钻进裂缝里消失，小裂缝随后慢慢闭合。坠落途中不带烟雾尾迹；
# 落地不用暴击粒子，只有小范围地板色碎屑喷发：无冲击圈无爆射线，
# 中心力大飞得高、四周力小飞得低。
const TEX: Texture2D = preload("res://Images/characters/我的世界/new6/天陨箭_纯白.png") # 普通箭剪影，纯白
const GLOW_TEX: Texture2D = preload("res://Images/characters/我的世界/new6/天陨箭_光晕.png") # 身后同变换的加性白光晕
const CLIP_SHADER: Shader = preload("res://shaders/heavenfall_arrow_clip.gdshader")
const CLIP_ADD_SHADER: Shader = preload("res://shaders/heavenfall_arrow_clip_add.gdshader")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const FX = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")
const DEBRIS_FX: GDScript = preload("res://scripts/characters/我的世界/new6/heavenfall_arrow_debris.gd")
const RIFT: GDScript = preload("res://scripts/characters/我的世界/new6/heavenfall_rain_rift.gd")
const SKY_BAND: GDScript = preload("res://scripts/characters/我的世界/new6/heavenfall_sky_band.gd")

const FALL_HEIGHT: float = 170.0 # 最小下落高度：画面上缘离落点很近时仍保留一段加速距离
const OFFSCREEN_MARGIN: float = 32.0 # 出生点在画面上缘之外再多留一段，整支箭完全在屏幕外
const GRAVITY: float = 2400.0
const RAIN_SPREAD: float = 0.90 # 同一轮箭雨的落地时刻铺开的窗口
const RIFT_LENGTH: float = 10.0 # 落点网状裂纹的半径
const BURROW_TIME: float = 0.16 # 箭钻进裂缝的时长
const BURROW_DEPTH: float = 14.0 # 钻入深度（约一支箭的长度）
const DEBRIS_RADIUS: float = 8.0 # 落地碎屑半径：只在箭点周围一小圈
const OVER_MASK_Z_INDEX: int = 91 # 与出地图的主箭同层：地图外遮罩（z=90）不裁掉坠落途中的落箭。

var _src_ref: WeakRef
var _team: String = ""
var _point: Vector2 = Vector2.ZERO
var _delay: float = 0.38
var _damage: float = 4.0
var _radius: float = 22.0
var _slow_ratio: float = 0.7
var _slow_duration: float = 0.8
var _hold: float = 0.0
var _vy: float = 0.0
var _falling: bool = false
var _landed: bool = false
var _burrow_t: float = 0.0
var _redirected: bool = false
var _redirect_velocity: Vector2 = Vector2.ZERO
var _redirect_left: float = 2.0


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("HeavenfallRainArrow") # 天穹带轮询：有箭雨在途则星空带显现
	SKY_BAND.ensure(get_tree().current_scene)
	z_index = OVER_MASK_Z_INDEX
	rotation = Vector2.DOWN.angle()
	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = GLOW_TEX
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.scale = Vector2(0.016, 0.016)
	glow.rotation = PI * 0.25
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CLIP_ADD_SHADER # blend_add + 与箭身同一条钻地裁剪线
	glow.material = glow_mat
	add_child(glow)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = TEX
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(0.016, 0.016) # 与普通骷髅箭一致
	sprite.rotation = PI * 0.25
	var body_mat := ShaderMaterial.new()
	body_mat.shader = CLIP_SHADER
	sprite.material = body_mat
	add_child(sprite)


func configure(source: ball, team: String, point: Vector2, delay: float, damage: float, radius: float, index: int = 0, total: int = 1) -> void:
	_src_ref = weakref(source) if source != null else null
	_team = team
	_point = point
	_delay = maxf(delay, 0.05)
	_damage = maxf(damage, 0.0)
	_radius = maxf(radius, 4.0)
	# 箭从画面上缘之外进入，而不是在落点上方固定距离处凭空出现：
	# 高度按当前可见视口实时计算（上缘很近时仍保留最小高度）。
	var height: float = FALL_HEIGHT
	if is_inside_tree():
		var screen_top: float = (get_viewport().get_canvas_transform().affine_inverse() * Vector2.ZERO).y
		height = maxf(FALL_HEIGHT, _point.y - screen_top + OFFSCREEN_MARGIN)
	# delay 仍是“第一支箭的落地时刻”：慢于纯重力用时就先悬停再落（hold，在屏幕外不可见），
	# 快于纯重力用时给一个初速度（重力照常生效），两种情况都精确在 delay 落地。
	var gravity_time: float = sqrt(2.0 * height / GRAVITY)
	_vy = maxf(0.0, (height - 0.5 * GRAVITY * _delay * _delay) / _delay)
	_hold = maxf(0.0, _delay - gravity_time)
	# 后续箭按索引铺开落地时刻，形成一段时间内不断落下的箭雨。
	if index > 0:
		_hold += RAIN_SPREAD * float(index) / float(maxi(total - 1, 1))
	global_position = _point + Vector2(0, -height)
	visible = false


func _physics_process(delta: float) -> void:
	if Game.now_stop_state or get_tree().paused:
		return
	if _landed:
		_burrow(delta)
		return
	if _redirected:
		_advance_redirected(delta)
		return
	if not _falling:
		_hold -= maxf(delta, 0.0)
		if _hold > 0.0:
			return
		_falling = true
		visible = true
		# Local visual replay on each peer: no sound during the hidden stagger wait.
		# Per-arrow throttling keeps simultaneous bows from muting each other.
		AUDIO.play(self, "entity.heavenfall.rain_shoot", global_position, -4.0, false, false, true)
	# 真实重力：速度积分决定位置，不是按剩余时间参数化的动画。
	_vy += GRAVITY * maxf(delta, 0.0)
	global_position.y += _vy * maxf(delta, 0.0)
	if global_position.y >= _point.y:
		_land()


func _land() -> void:
	if _landed:
		return
	_landed = true
	global_position.y = _point.y
	_burrow_t = 0.0
	var world: Node = get_tree().current_scene
	if world != null:
		# 落地不再用暴击/烟雾粒子，也没有冲击圈/爆射线：只有地板色方块碎屑，
		# 范围很小，且越靠中心力越大（飞得越高）、四周力小飞得低。
		var debris: Node2D = DEBRIS_FX.new()
		world.add_child(debris)
		debris.call("setup", _point, DEBRIS_RADIUS)
		# 落点从中心撕开网状小裂缝：箭钻进去，裂缝慢慢闭合后自行消失。
		var crack: Node2D = RIFT.new()
		crack.name = "RainCrack"
		world.add_child(crack)
		crack.call("configure_impact", _point, randi(), RIFT_LENGTH)
	# 钻入开始：从裂缝口（落点）那道水平线裁掉已进入地下的部分——
	# 箭身与光晕同一条裁剪线，实体的“插进地里”，不是半透明穿过。
	for mat: ShaderMaterial in [sprite_material(), glow_material()]:
		if mat != null:
			mat.set_shader_parameter("clip_enabled", true)
			mat.set_shader_parameter("clip_y", _point.y)
	# Ground contact opens a small crack: no arrow-impact sound here.
	AUDIO.play(self, "entity.heavenfall.rain_rift", _point, -6.0, false, false, true)
	if is_multiplayer_authority():
		var src: ball = _src_ref.get_ref() if _src_ref != null else null
		if is_instance_valid(src):
			for other: Node in get_tree().get_nodes_in_group("Ball"):
				if not U.enemy(src, other):
					continue
				var victim: ball = other as ball
				# Fixed 24px body allowance: U.radius() collapses outside crowded combat.
				if ball.body_point(victim,_point).distance_to(_point) > _radius + 24.0:
					continue
				if U.damage(src, victim, _damage, _point):
					U.slow(src, victim, _slow_ratio, _slow_duration, "天陨减速")
					FX.hit_sfx(src, victim.global_position, _damage)


func _burrow(delta: float) -> void:
	# 箭沿坠落方向钻进裂缝：裁剪线以下的部分不绘制（钻进地下），箭整体保持
	# 不透明地下沉，完全没入后消失；不再用半透明淡出穿过裂缝。
	_burrow_t += maxf(delta, 0.0)
	var step: float = clampf(_burrow_t / BURROW_TIME, 0.0, 1.0)
	global_position.y = _point.y + BURROW_DEPTH * step
	if _burrow_t >= BURROW_TIME:
		queue_free()


func sprite_material() -> ShaderMaterial:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	return sprite.material as ShaderMaterial if sprite != null else null


func glow_material() -> ShaderMaterial:
	var glow: Sprite2D = get_node_or_null("Glow") as Sprite2D
	return glow.material as ShaderMaterial if glow != null else null

# Explicit motion capability: a falling arrow is not a direction/speed field guess.
func get_projectile_velocity() -> Vector2:
	if _landed: return Vector2.ZERO
	if _redirected: return _redirect_velocity
	return Vector2.DOWN*_vy if _falling else Vector2.ZERO

func set_projectile_velocity(motion:Vector2) -> void:
	_redirected = true
	_redirect_velocity = motion
	_falling = true
	_hold = 0.0
	visible = true
	if not motion.is_zero_approx(): rotation = motion.angle()

func relaunch_projectile(point:Vector2,target:ball) -> void:
	global_position = point
	_redirect_left = 2.0
	set_projectile_velocity(point.direction_to(ball.body_point(target,point))*maxf(_vy,300.0))

func _advance_redirected(delta:float) -> void:
	if not is_multiplayer_authority(): return
	var start:Vector2 = global_position
	var finish:Vector2 = start+_redirect_velocity*maxf(delta,0.0)
	if get_tree().has_group("MinecraftWoolSheep") and load("res://scripts/characters/我的世界/new6/wool_projectile.gd").sweep(self,start,finish): return
	var src:ball = _src_ref.get_ref() if _src_ref != null else null
	var hit:Dictionary = load("res://scripts/characters/我的世界/new6/heavenfall_collision.gd").projectile(self,src,start,finish)
	var victim:ball = hit.get("victim") as ball
	if is_instance_valid(victim):
		var response:String = PROJECTILE_API.defense(self,victim,hit.get("position",finish))
		if response == "dodge":
			global_position = finish
			return
		if not response.is_empty(): return
	global_position = hit.get("position",finish)
	_redirect_left -= maxf(delta,0.0)
	if not hit.is_empty() or _redirect_left <= 0.0:
		_point = global_position
		_land()
