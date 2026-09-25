extends Node2D

# 统一命中反馈层：保留闪白限频，删除此前的黄色爆点/光芒/冲击圈。
# 暴击粒子使用用户提供的 8x8 原生像素图案，单节点批量绘制，无碰撞/伤害逻辑。
const CRITICAL_TEXTURE:Texture2D = preload("res://Images/paricle/critical_hit.png")
const MAX_IMPACTS:int = 32
const MAX_CRITICAL_PARTICLES:int = 384
const MAX_CRITICAL_PARTICLES_PER_UNIT:int = 64
const CRITICAL_DAMAGE_THRESHOLD:float = 50.0
const CRITICAL_FADE_SECONDS:float = 0.075
var _impacts:Array[Dictionary] = []
var _particles:Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 98
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize() # 独立视觉 RNG，不消耗战斗/AI 随机序列。
	set_process(false)

func critical_particle_count(actual_damage:float,blocked:bool = false) -> int:
	if blocked or not is_finite(actual_damage) or actual_damage <= CRITICAL_DAMAGE_THRESHOLD:
		return 0
	# 确定性数量随伤害单调增加；随机只作用于位置、速度、大小与寿命。
	return clampi(4 + int(floor((minf(actual_damage,550.0) - CRITICAL_DAMAGE_THRESHOLD) / 20.0)),4,24)

func add_impact(unit_id:int,origin:Vector2,radius:float,strength:float,_heavy:bool,blocked:bool,actual_damage:float = 0.0) -> bool:
	var now:int = Time.get_ticks_usec()
	_prune(now)
	for index:int in range(_impacts.size()):
		var existing:Dictionary = _impacts[index]
		if int(existing["unit"]) != unit_id:
			continue
		var critical_upgrade:bool = (critical_particle_count(actual_damage,blocked) > 0
			and critical_particle_count(float(existing["damage"]),bool(existing["blocked"])) == 0)
		if now - int(existing["born"]) < 65000 and not critical_upgrade:
			return false
		_impacts.remove_at(index)
		break
	if _impacts.size() >= MAX_IMPACTS:
		_impacts.pop_front()
	_impacts.append({"unit":unit_id,"born":now,"damage":actual_damage,"blocked":blocked,"strength":strength})
	var count:int = critical_particle_count(actual_damage,blocked)
	if count > 0:
		_spawn_critical_particles(unit_id,origin,radius,count,now)
	set_process(true)
	queue_redraw()
	return true

func add_visual_critical_burst(emitter_id:int,origin:Vector2,options:Dictionary = {}) -> void:
	# Visual-only CRIT burst: does not manufacture damage or bypass hit thresholds.
	var now:int = Time.get_ticks_usec()
	_prune(now)
	_spawn_critical_particles(emitter_id,origin,float(options.get("radius",6.0)),clampi(int(options.get("count",12)),1,24),now,options)
	set_process(true)
	queue_redraw()

func _spawn_critical_particles(unit_id:int,origin:Vector2,radius:float,count:int,now:int,options:Dictionary = {}) -> void:
	var unit_count:int = 0
	for particle:Dictionary in _particles:
		if int(particle["unit"]) == unit_id:
			unit_count += 1
	count = mini(count,maxi(MAX_CRITICAL_PARTICLES_PER_UNIT - unit_count,0))
	while _particles.size() + count > MAX_CRITICAL_PARTICLES:
		_particles.pop_front()
	var body_radius:float = clampf(radius,6.0,34.0)
	var spawn_points:PackedVector2Array = PackedVector2Array()
	if count > 0 and is_instance_id_valid(unit_id):
		var source:Object = instance_from_id(unit_id)
		if is_instance_valid(source) and source.has_method("sample_critical_particle_origins"):
			spawn_points = source.call("sample_critical_particle_origins",count,_rng)
	var angle_phase:float = _rng.randf_range(0.0,TAU)
	for index:int in range(count):
		# 无有效图像时按全身圆面均匀采样；sqrt 消除半径均匀采样造成的中心聚集。
		var angle:float = angle_phase + TAU * (float(index) + _rng.randf()) / float(maxi(count,1))
		var offset:Vector2 = Vector2.from_angle(angle) * maxf(radius,6.0) * sqrt(_rng.randf()) * 0.95
		var spawn_position:Vector2 = spawn_points[index] if index < spawn_points.size() else origin + offset
		var side:float = -1.0 if index % 2 == 0 else 1.0
		var velocity:Vector2 = Vector2(side * _rng.randf_range(float(options.get("side_min",45.0)),float(options.get("side_max",85.0))),-_rng.randf_range(float(options.get("up_min",40.0)),float(options.get("up_max",70.0))))
		# Minecraft 普通暴击的棕灰色乘色；保留贴图本身白/灰像素的层次，不做金黄发光。
		# 施法者技能（如尖牙闭合）可要求中性灰白，接近原版 CRIT 贴图的原始亮度。
		var tone:float = _rng.randf_range(float(options.get("tone_min",0.60)),float(options.get("tone_max",0.90)))
		_particles.append({"unit":unit_id,"born":now,"origin":spawn_position,
			"velocity":velocity,"gravity":_rng.randf_range(float(options.get("gravity_min",390.0)),float(options.get("gravity_max",450.0))),
			"life":_rng.randf_range(0.29,0.37),
			"size":_rng.randf_range(7.0,9.4) * clampf(body_radius / 18.0,0.80,1.25),
			"color":(Color(tone,tone,tone,1.0) if bool(options.get("neutral_tone",false)) else Color(tone,tone * 0.60,tone * 0.60,1.0))})

func _prune(now:int) -> void:
	for index:int in range(_impacts.size() - 1,-1,-1):
		if now - int(_impacts[index]["born"]) >= 65000:
			_impacts.remove_at(index)
	for index:int in range(_particles.size() - 1,-1,-1):
		if float(now - int(_particles[index]["born"])) * 0.000001 >= float(_particles[index]["life"]):
			_particles.remove_at(index)

func _process(_delta:float) -> void:
	_prune(Time.get_ticks_usec())
	queue_redraw()
	if _impacts.is_empty() and _particles.is_empty():
		set_process(false)

func critical_particle_position(particle:Dictionary,age:float) -> Vector2:
	return (particle["origin"] as Vector2) + (particle["velocity"] as Vector2) * age + Vector2(0.0,0.5 * float(particle["gravity"]) * age * age)

func critical_particle_alpha(age:float,life:float) -> float:
	return 1.0 - smoothstep(maxf(life - CRITICAL_FADE_SECONDS,0.0),life,age)

func _draw() -> void:
	var now:int = Time.get_ticks_usec()
	for particle:Dictionary in _particles:
		var age:float = maxf(float(now - int(particle["born"])) * 0.000001,0.0)
		var life:float = float(particle["life"])
		var tint:Color = particle["color"]
		tint.a = critical_particle_alpha(age,life)
		if tint.a <= 0.001:
			continue
		# 与 Minecraft 一样略微转暗，末尾仅快速渐隐；粒子图案不旋转成大十字光斑。
		tint.g *= pow(0.96,age * 20.0)
		tint.b *= pow(0.90,age * 20.0)
		var size:Vector2 = Vector2.ONE * float(particle["size"])
		var position_value:Vector2 = critical_particle_position(particle,age)
		draw_texture_rect(CRITICAL_TEXTURE,Rect2(position_value - size * 0.5,size),false,tint)
