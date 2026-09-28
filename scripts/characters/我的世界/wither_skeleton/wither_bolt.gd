extends Node2D
## 凋灵骷髅头部远程弹：弹体没有固定贴图，而是在弹体位置周围半径 BODY_RADIUS 内持续随机生成
## 凋灵头颅拖尾同款烟雾粒子（原版 big_smoke_0，同色；随机位置/大小/寿命），每粒沿切向绕中心
## 漂移，整体呈旋转的粒子团；另按与凋灵头颅相同的距离采样留下同款拖尾。
## 轨迹（2026-09-28）：先向后上方弹出（背离瞄准方向、偏向屏幕上方一侧），被朝瞄准方向的恒定
## 拉力拉回形成抛物线，前向速度达到巡航速度后直线巡航。小幅追踪：瞄准方向/巡航方向每秒最多转
## TURN_RATE 弧度朝目标当前位置。
## 伤害/凋零由发射者 deal_bolt_hit 结算（权威端）；联机客户端生成纯视觉副本，按同一运动学前进，
## 由权威端 end 同步收尾。拖尾复用已提交的原版粒子节点（末影粒子.gd）运动/淡出/清理。
const PARTICLE = preload("res://scripts/effects/我的世界/末影粒子.gd")
const SMOKE:Texture2D = preload("res://Images/characters/我的世界/wither/big_smoke_0.png")
const EXPLOSION = preload("res://scripts/effects/我的世界/mc_explosion.gd")
# 与凋灵头颅拖尾一致：间距 6、后移半径、寿命 0.5、宽 8、向后漂移 12、深灰 0.22/0.85。
const TRAIL_SPACING:float = 6.0
const TRAIL_LIFETIME:float = 0.5
const TRAIL_WIDTH:float = 8.0
const TRAIL_DRIFT:float = 12.0
const TINT:Color = Color(0.22,0.22,0.22,0.85)
const TRAIL_GROUP:StringName = &"MCWitherSkeletonBoltTrail"
const TRAIL_CAP:int = 384 # 本体加密后提高上限（两发同屏仍够用）
static var _jitter := RandomNumberGenerator.new() # 纯视觉：粒子角度/拖尾大小，不占用战斗 RNG
static var _jitter_seeded:bool = false
const BODY_RADIUS:float = 6.0 # 弹团视觉半径（=凋灵头颅直径 12 的一半）
const HIT_RADIUS:float = 5.0
# 弹体粒子发射器（2026-09-28 修订：取代固定 9 粒旋转团）。
const BODY_GROUP:StringName = &"MCWitherSkeletonBoltBody"
const BODY_RATE:float = 220.0 # 粒子/秒（战斗时间）；第四轮：80→220，本体更密
const BODY_LAUNCH_BURST:int = 16 # 出膛瞬间先补一团，第一帧就可见
const BODY_LIFETIME:Vector2 = Vector2(0.12,0.24)
const BODY_WIDTH:Vector2 = Vector2(6.0,7.5) # 小范围随机
const TRAIL_WIDTH_JITTER:Vector2 = Vector2(0.88,1.12) # 拖尾粒子大小小范围随机（×8）
const BODY_SWIRL:float = 5.0 # 寿命内切向漂移距离：所有粒子同向绕中心 → 旋转感
const BODY_SPREAD:float = 1.5 # 轻微外扩

var source_ref:WeakRef
var target_ref:WeakRef
var heading:Vector2 = Vector2.RIGHT # 当前运动方向
var aim:Vector2 = Vector2.RIGHT # 拉力方向（发射时朝目标，之后小幅追踪）
var velocity:Vector2 = Vector2.ZERO
var cruising:bool = false
var launch_speed:float = 100.0
var launch_angle:float = deg_to_rad(40.0)
var pull:float = 240.0
var speed:float = 120.0
var turn_rate:float = 1.4
var life:float = 3.0
var serial:int = 0
var visual_only:bool = false
var finished:bool = false
var traveled:float = 0.0
var _trail_carry:float = 0.0
var _emit_carry:float = 0.0
var _burst_pending:bool = true # 首个物理帧（位置已设好）在出膛点补一团
var _rng := RandomNumberGenerator.new() # 纯视觉，不占用战斗 RNG

func configure(source:Node,direction:Vector2,target:Node,bolt_speed:float,bolt_turn:float,bolt_life:float,id:int,only_visual:bool,
		bolt_launch_speed:float = 100.0,bolt_launch_angle:float = deg_to_rad(40.0),bolt_pull:float = 240.0) -> void:
	source_ref = weakref(source)
	target_ref = weakref(target) if is_instance_valid(target) else null
	aim = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	speed = bolt_speed
	launch_speed = bolt_launch_speed
	launch_angle = bolt_launch_angle
	pull = bolt_pull
	velocity = launch_velocity(aim,launch_speed,launch_angle)
	heading = velocity.normalized()
	cruising = false
	turn_rate = bolt_turn
	life = bolt_life
	serial = id
	visual_only = only_visual
	if not visual_only: add_to_group("AI_Hazard")

## 向后上方：背离瞄准方向 launch_angle，偏向屏幕上方的那一侧（竖直发射时偏向右侧）。
## 纯函数，权威端与客户端视觉副本得到同一初速度。
static func launch_velocity(direction:Vector2,magnitude:float,angle:float) -> Vector2:
	var forward:Vector2 = direction.normalized()
	var side:Vector2 = forward.orthogonal()
	if side.y > 0.0001 or (absf(side.y) <= 0.0001 and side.x < 0.0): side = -side
	return (-forward*cos(angle)+side*sin(angle))*magnitude

func _ready() -> void:
	z_index = 8
	add_to_group("BattleTransient")
	add_to_group("MCWitherSkeletonBolt")
	_rng.randomize()

func _source() -> ball:
	var node:Variant = source_ref.get_ref() if source_ref != null else null
	return node as ball if is_instance_valid(node) and node is ball and node.health > 0 else null

func current_target() -> ball:
	var node:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(node) or not node is ball or node.health <= 0: return null
	return node

## 小幅追踪：把方向朝目标当前位置转，但每秒最多 turn_rate 弧度；目标消失后保持。
func turn_toward_target(direction:Vector2,delta:float) -> Vector2:
	var target:ball = current_target()
	if target == null: return direction
	var wanted:Vector2 = global_position.direction_to(target.global_position)
	if wanted.is_zero_approx(): return direction
	var angle:float = direction.angle_to(wanted)
	return direction.rotated(clampf(angle,-turn_rate*delta,turn_rate*delta)).normalized()

## 推进一步：抛物线阶段 = 恒定拉力积分；前向速度达到巡航速度后改为匀速巡航。
func advance_velocity(delta:float) -> void:
	aim = turn_toward_target(aim,delta)
	if not cruising:
		velocity += aim*pull*delta
		if velocity.dot(aim) > 0.0 and velocity.length() >= speed:
			velocity = velocity.normalized()*speed
			cruising = true
	else:
		velocity = turn_toward_target(velocity.normalized(),delta)*speed
	if not velocity.is_zero_approx(): heading = velocity.normalized()

func _physics_process(delta:float) -> void:
	if finished or delta <= 0.0: return
	var source:ball = _source()
	if source == null:
		dissipate(global_position)
		return
	if not source.is_combat_runtime_active(): return
	life -= delta
	if life <= 0.0:
		if not visual_only: source.call("_finish_bolt",self,global_position,false)
		dissipate(global_position)
		return
	if _burst_pending:
		_burst_pending = false
		emit_body(global_position,global_position,BODY_LAUNCH_BURST)
	advance_velocity(delta)
	var start:Vector2 = global_position
	var end:Vector2 = start+velocity*delta
	if not visual_only:
		var hit:Dictionary = _trace(source,start,end)
		if not hit.is_empty():
			var point:Vector2 = hit.position
			_emit_trail(start,point)
			global_position = point
			var victim:ball = hit.get("collider") as ball
			if victim != null: source.call("deal_bolt_hit",victim,point)
			source.call("_finish_bolt",self,point,victim != null)
			dissipate(point)
			return
	_emit_trail(start,end)
	traveled += start.distance_to(end)
	global_position = end
	_emit_carry += BODY_RATE*delta
	var count:int = int(_emit_carry)
	_emit_carry -= float(count)
	emit_body(start,end,count)

## 在本帧运动段上随机取点，再在半径 BODY_RADIUS 圆盘内随机偏移生成粒子（面积均匀）。
func emit_body(from:Vector2,to:Vector2,count:int) -> void:
	for i:int in range(count):
		var center:Vector2 = from.lerp(to,_rng.randf())
		var offset:Vector2 = Vector2.RIGHT.rotated(_rng.randf()*TAU)*BODY_RADIUS*sqrt(_rng.randf())
		var radial:Vector2 = offset.normalized() if offset.length() > 0.3 else Vector2.RIGHT.rotated(_rng.randf()*TAU)
		var motion:Vector2 = radial.orthogonal()*BODY_SWIRL*_rng.randf_range(0.6,1.0)+radial*BODY_SPREAD
		var particle:Sprite2D = spawn_smoke(self,center+offset,motion,
			_rng.randf_range(BODY_LIFETIME.x,BODY_LIFETIME.y),_rng.randf_range(BODY_WIDTH.x,BODY_WIDTH.y))
		if particle != null: particle.add_to_group(BODY_GROUP)

## 同凋灵头颅：射线查询身体/墙（mask 3），跳过发射者与非敌方单位；非单位碰撞即墙。
func _trace(source:ball,start:Vector2,end:Vector2) -> Dictionary:
	var excluded:Array[RID] = [source.get_rid()]
	for n:int in range(12):
		var query := PhysicsRayQueryParameters2D.create(start,end,3,excluded)
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return {}
		var collider:Variant = hit.get("collider")
		if collider is ball and (collider.health <= 0 or not source.call("is_bolt_enemy",collider)):
			excluded.append((collider as ball).get_rid())
			continue
		return hit
	return {}


func _emit_trail(from:Vector2,to:Vector2) -> void:
	# 距离采样（与凋灵头颅相同：帧率不影响密度），点位于弹团后方半径处。
	var length:float = from.distance_to(to)
	if length <= 0.0: return
	var direction:Vector2 = from.direction_to(to)
	var along:float = TRAIL_SPACING-fposmod(_trail_carry,TRAIL_SPACING)
	var count:int = 0
	while along <= length and count < 48:
		spawn_smoke(self,from+direction*(along-BODY_RADIUS),-direction*TRAIL_DRIFT,TRAIL_LIFETIME,
			TRAIL_WIDTH*jitter_rng().randf_range(TRAIL_WIDTH_JITTER.x,TRAIL_WIDTH_JITTER.y))
		along += TRAIL_SPACING
		count += 1
	_trail_carry = fposmod(_trail_carry+length,TRAIL_SPACING)

static func jitter_rng() -> RandomNumberGenerator:
	if not _jitter_seeded:
		_jitter.randomize()
		_jitter_seeded = true
	return _jitter

## 每粒随机角度（0–360°）；大小由调用方在小范围内随机。
static func spawn_smoke(context:Node,point:Vector2,motion:Vector2,lifetime:float,width:float) -> Sprite2D:
	if context.get_tree() == null or context.get_tree().current_scene == null: return null
	if context.get_tree().get_nodes_in_group(TRAIL_GROUP).size() >= TRAIL_CAP: return null
	var particle:Sprite2D = PARTICLE.new()
	EXPLOSION.runtime_container(context).add_child(particle)
	particle.frames = [SMOKE]
	particle.setup(point,motion,maxf(lifetime,0.01),1.0)
	particle._pixel_width = clampf(width,1.0,32.0)
	particle.scale = Vector2.ONE*(particle._pixel_width/float(SMOKE.get_width()))
	particle.self_modulate = TINT
	particle.rotation = jitter_rng().randf()*TAU # setup 只设位置；粒子自身 _process 不改角度
	particle.z_index = 8
	particle.remove_from_group("MCEnderParticle")
	particle.add_to_group(TRAIL_GROUP)
	return particle

## 收尾：弹团散成同款粒子（向四周飘散），节点释放。
func dissipate(point:Vector2) -> void:
	if finished: return
	finished = true
	remove_from_group("AI_Hazard")
	for i:int in range(10):
		var offset:Vector2 = Vector2.RIGHT.rotated(_rng.randf()*TAU)*BODY_RADIUS*sqrt(_rng.randf())
		var outward:Vector2 = offset.normalized() if offset.length() > 0.3 else Vector2.RIGHT.rotated(_rng.randf()*TAU)
		var burst:Sprite2D = spawn_smoke(self,point+offset,outward*_rng.randf_range(6.0,12.0),_rng.randf_range(0.25,0.4),_rng.randf_range(BODY_WIDTH.x,BODY_WIDTH.y))
		if burst != null: burst.add_to_group(BODY_GROUP)
	queue_free()

func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	var source:ball = _source()
	if finished or visual_only or source == null: return {}
	return {"shape":"circle","position":global_position,"velocity":velocity,"radius":HIT_RADIUS,
		"damage":source.call("bolt_damage"),"source":source,"danger_duration":0.1,"kind":"wither_skeleton_bolt"}
