extends Node2D
## 凋灵骷髅头部远程弹：弹体本身就是凋灵头颅拖尾烟雾粒子（原版 big_smoke_0，同色同宽）的聚合团，
## 飞行时按与凋灵头颅相同的距离采样留下同款拖尾。小幅追踪：每秒最多转 TURN_RATE 弧度。
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
const TRAIL_CAP:int = 256
const BODY_RADIUS:float = 6.0 # 弹团视觉半径（=凋灵头颅直径 12 的一半）
const HIT_RADIUS:float = 5.0
# 聚合团：中心 1 粒 + 内环 3 粒 + 外环 5 粒，都是拖尾同款粒子。
const BODY_LAYOUT:Array = [[0.0,0.0,1.0],[2.6,0.0,0.9],[2.6,2.094,0.9],[2.6,4.189,0.9],
	[4.6,0.63,0.75],[4.6,1.89,0.75],[4.6,3.14,0.75],[4.6,4.4,0.75],[4.6,5.65,0.75]]

var source_ref:WeakRef
var target_ref:WeakRef
var heading:Vector2 = Vector2.RIGHT
var speed:float = 200.0
var turn_rate:float = 1.4
var life:float = 3.0
var serial:int = 0
var visual_only:bool = false
var finished:bool = false
var traveled:float = 0.0
var _trail_carry:float = 0.0
var _spin:float = 0.0
var _body:Array[Sprite2D] = []

func configure(source:Node,direction:Vector2,target:Node,bolt_speed:float,bolt_turn:float,bolt_life:float,id:int,only_visual:bool) -> void:
	source_ref = weakref(source)
	target_ref = weakref(target) if is_instance_valid(target) else null
	heading = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	speed = bolt_speed
	turn_rate = bolt_turn
	life = bolt_life
	serial = id
	visual_only = only_visual
	if not visual_only: add_to_group("AI_Hazard")

func _ready() -> void:
	z_index = 8
	add_to_group("BattleTransient")
	add_to_group("MCWitherSkeletonBolt")
	for i:int in range(BODY_LAYOUT.size()):
		var sprite := Sprite2D.new()
		sprite.texture = SMOKE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.self_modulate = TINT
		add_child(sprite)
		_body.append(sprite)
	_layout_body()

func _source() -> ball:
	var node:Variant = source_ref.get_ref() if source_ref != null else null
	return node as ball if is_instance_valid(node) and node is ball and node.health > 0 else null

func current_target() -> ball:
	var node:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(node) or not node is ball or node.health <= 0: return null
	return node

## 小幅追踪：朝目标当前位置转向，但每秒最多 turn_rate 弧度；目标消失后直飞。
func steer(delta:float) -> void:
	var target:ball = current_target()
	if target == null: return
	var wanted:Vector2 = global_position.direction_to(target.global_position)
	if wanted.is_zero_approx(): return
	var angle:float = heading.angle_to(wanted)
	heading = heading.rotated(clampf(angle,-turn_rate*delta,turn_rate*delta)).normalized()

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
	steer(delta)
	var start:Vector2 = global_position
	var end:Vector2 = start+heading*speed*delta
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

func _process(delta:float) -> void:
	if finished: return
	var source:ball = _source()
	if source != null and source.is_combat_runtime_active(): _spin += delta*5.0
	_layout_body()

func _layout_body() -> void:
	# 粒子团缓慢旋转、轻微呼吸，读作“一团拖尾粒子”而不是实心贴图。
	for i:int in range(_body.size()):
		var spec:Array = BODY_LAYOUT[i]
		var radius:float = float(spec[0])*(1.0+0.12*sin(_spin*1.7+float(i)))
		var angle:float = float(spec[1])+_spin*(1.0 if i < 4 else -0.7)
		var width:float = TRAIL_WIDTH*float(spec[2])
		_body[i].position = Vector2.RIGHT.rotated(angle)*radius
		_body[i].scale = Vector2.ONE*(width/float(SMOKE.get_width()))

func _emit_trail(from:Vector2,to:Vector2) -> void:
	# 距离采样（与凋灵头颅相同：帧率不影响密度），点位于弹团后方半径处。
	var length:float = from.distance_to(to)
	if length <= 0.0: return
	var direction:Vector2 = from.direction_to(to)
	var along:float = TRAIL_SPACING-fposmod(_trail_carry,TRAIL_SPACING)
	var count:int = 0
	while along <= length and count < 48:
		spawn_smoke(self,from+direction*(along-BODY_RADIUS),-direction*TRAIL_DRIFT,TRAIL_LIFETIME,TRAIL_WIDTH)
		along += TRAIL_SPACING
		count += 1
	_trail_carry = fposmod(_trail_carry+length,TRAIL_SPACING)

static func spawn_smoke(context:Node,point:Vector2,motion:Vector2,lifetime:float,width:float) -> void:
	if context.get_tree() == null or context.get_tree().current_scene == null: return
	if context.get_tree().get_nodes_in_group(TRAIL_GROUP).size() >= TRAIL_CAP: return
	var particle:Sprite2D = PARTICLE.new()
	EXPLOSION.runtime_container(context).add_child(particle)
	particle.frames = [SMOKE]
	particle.setup(point,motion,maxf(lifetime,0.01),1.0)
	particle._pixel_width = clampf(width,1.0,32.0)
	particle.scale = Vector2.ONE*(particle._pixel_width/float(SMOKE.get_width()))
	particle.self_modulate = TINT
	particle.z_index = 8
	particle.remove_from_group("MCEnderParticle")
	particle.add_to_group(TRAIL_GROUP)

## 收尾：弹团散成同款粒子（向四周飘散），节点释放。
func dissipate(point:Vector2) -> void:
	if finished: return
	finished = true
	remove_from_group("AI_Hazard")
	for i:int in range(BODY_LAYOUT.size()):
		var spec:Array = BODY_LAYOUT[i]
		var offset:Vector2 = Vector2.RIGHT.rotated(float(spec[1])+_spin)*maxf(float(spec[0]),1.0)
		spawn_smoke(self,point+offset,offset.normalized()*10.0,TRAIL_LIFETIME*0.7,TRAIL_WIDTH*float(spec[2]))
	queue_free()

func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	var source:ball = _source()
	if finished or visual_only or source == null: return {}
	return {"shape":"circle","position":global_position,"velocity":heading*speed,"radius":HIT_RADIUS,
		"damage":source.call("bolt_damage"),"source":source,"danger_duration":0.1,"kind":"wither_skeleton_bolt"}
