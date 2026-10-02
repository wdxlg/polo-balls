extends Node2D
## 安山岩的地面石头波纹：波头从安山岩脚下出发，沿地面追向队友当前位置，一路隆起
## 安山岩像素小石块（升起、落下、淡出）。波头抵达队友时才生效：权威端结算治疗或急迫，
## 并在队友脚下冒出几个石头凸起（不画扩散圆圈）；客机只播放同一段表现。目标死亡或消失时波纹作废。
## 治疗量在抵达时按目标当时的缺血比例计算：base × (1 + heal_missing_scale × 缺血比例)。
const STATUS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const STONE_AUDIO = preload("res://scripts/characters/我的世界/useless_stones/useless_stones_audio.gd")
const FACE:Texture2D = preload("res://Images/characters/我的世界/useless_stones/andesite.png")
const HEAL:int = 0
const HASTE:int = 1
## 以下尺寸都是“单位缩放 1”下的世界像素，实际按安山岩根缩放换算。
const BUMP_SPACING:float = 6.0
const BUMP_SIZE:float = 5.5
const BUMP_RISE:float = 4.0
const BUMP_LIFE:float = 0.42
const ARRIVE_RADIUS:float = 4.0
const MAX_TRAVEL_TIME:float = 4.0

var kind:int = HEAL
var amount_base:float = 0.0
var heal_missing_scale:float = 6.0
var haste_level:int = 3
var haste_duration:float = 5.0
var speed:float = 300.0
var unit_scale:float = 1.0
var authoritative:bool = false
var front:Vector2 = Vector2.ZERO
var arrived:bool = false
var delivered:bool = false
var healed:int = 0
var bumps:Array[Dictionary] = []
var _source_ref:WeakRef
var _target_ref:WeakRef
var _since_bump:float = 0.0
var _travel:float = 0.0
var _serial:int = 0
var _bump_count:int = 0
var _rng := RandomNumberGenerator.new()

static func launch(parent:Node,source:Node2D,target:Node2D,ripple_kind:int,options:Dictionary) -> Node2D:
	if not is_instance_valid(parent) or not is_instance_valid(target): return null
	var ripple:Node2D = (load("res://scripts/characters/我的世界/useless_stones/andesite_ripple.gd") as GDScript).new()
	ripple.name = "AndesiteRipple"
	ripple.kind = ripple_kind
	ripple._source_ref = weakref(source) if is_instance_valid(source) else null
	ripple._target_ref = weakref(target)
	ripple.front = options.get("start",source.global_position if is_instance_valid(source) else target.global_position)
	for key:String in ["amount_base","heal_missing_scale","haste_level","haste_duration","speed","unit_scale","authoritative"]:
		if options.has(key): ripple.set(key,options[key])
	ripple._serial = int(options.get("serial",0))
	ripple._rng.seed = absi(hash(str(ripple._serial)+":"+str(ripple_kind)))
	parent.add_child(ripple)
	return ripple

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 1
	add_to_group(&"BattleTransient")
	add_to_group(&"MCAndesiteRipple")
	_add_bump(front)

func source_unit() -> Node2D:
	var unit:Variant = _source_ref.get_ref() if _source_ref != null else null
	return unit if is_instance_valid(unit) else null

func target_unit() -> Node2D:
	var unit:Variant = _target_ref.get_ref() if _target_ref != null else null
	if not is_instance_valid(unit) or unit.is_queued_for_deletion() or not unit.is_inside_tree(): return null
	if float(unit.get("health")) <= 0.0: return null
	return unit

func _combat_paused() -> bool:
	var game:Node = get_node_or_null("/root/Game")
	if game != null and bool(game.get("now_stop_state")): return true
	return get_tree().paused

func _physics_process(delta:float) -> void:
	if _combat_paused(): return
	for bump:Dictionary in bumps: bump.age = float(bump.age)+delta
	bumps = bumps.filter(func(b:Dictionary) -> bool: return float(b.age) < BUMP_LIFE)
	if not arrived: _advance(delta)
	if arrived and bumps.is_empty():
		queue_free()
		return
	queue_redraw()

func _advance(delta:float) -> void:
	var target:Node2D = target_unit()
	_travel += delta
	if target == null or _travel > MAX_TRAVEL_TIME:
		arrived = true
		return
	var goal:Vector2 = target.global_position
	var step:float = maxf(speed*unit_scale,1.0)*delta
	var spacing:float = BUMP_SPACING*unit_scale
	var remaining:float = front.distance_to(goal)
	while step > 0.0 and remaining > ARRIVE_RADIUS*unit_scale:
		var move:float = minf(step,minf(spacing-_since_bump,remaining))
		front = front.move_toward(goal,move)
		step -= move
		remaining -= move
		_since_bump += move
		if _since_bump >= spacing-0.001:
			_since_bump = 0.0
			_add_bump(front)
	if remaining <= ARRIVE_RADIUS*unit_scale:
		front = goal
		_arrive(target)

func _add_bump(point:Vector2) -> void:
	var cells:int = int(FACE.get_width()/4)
	var region := Rect2(Vector2(_rng.randi_range(0,cells-1),_rng.randi_range(0,cells-1))*4.0,Vector2(4,4))
	var side:Vector2 = Vector2(_rng.randf_range(-1.2,1.2),_rng.randf_range(-0.6,0.6))*unit_scale
	bumps.append({"position":point+side,"age":0.0,"size":BUMP_SIZE*unit_scale*_rng.randf_range(0.75,1.1),"region":region})
	_bump_count += 1
	if _bump_count % 4 == 1: STONE_AUDIO.play(self,STONE_AUDIO.STEP_SOUND,_serial+_bump_count,point,_rng.randf_range(0.9,1.1),{"keep_after_source":true})

func _arrive(target:Node2D) -> void:
	if arrived: return
	arrived = true
	if authoritative: _deliver(target)
	# 抵达只冒三个石头凸起并响放置声；治疗与急迫不画扩散圆圈（user 2026-10-02）。
	for i:int in range(3): _add_bump(target.global_position+Vector2.RIGHT.rotated(TAU*float(i)/3.0+0.4)*5.0*unit_scale)
	STONE_AUDIO.play(self,STONE_AUDIO.PLACE_SOUND,_serial,target.global_position,1.15 if kind == HEAL else 0.95,{"keep_after_source":true,"volume_db":-6.0})

func _deliver(target:Node2D) -> void:
	if delivered or not target.is_multiplayer_authority(): return
	delivered = true
	match kind:
		HEAL:
			var max_health:float = maxf(float(target.get("Max_health")),1.0)
			var missing:float = clampf(1.0-float(target.get("health"))/max_health,0.0,1.0)
			var amount:int = int(round(maxf(amount_base,0.0)*(1.0+maxf(heal_missing_scale,0.0)*missing)))
			if amount > 0 and missing > 0.0 and target.has_method("heal"): healed = int(target.call("heal",amount))
		HASTE:
			var source:Node = source_unit()
			STATUS.apply_effect(target as ball,"haste",haste_level,haste_duration,source if source != null else target)

func _draw() -> void:
	for bump:Dictionary in bumps:
		var t:float = clampf(float(bump.age)/BUMP_LIFE,0.0,1.0)
		var rise:float = sin(PI*minf(t*1.5,1.0))*BUMP_RISE*unit_scale
		var alpha:float = 1.0-smoothstep(0.62,1.0,t)
		var size:float = float(bump.size)
		var at:Vector2 = bump.position
		draw_set_transform(at,0.0,Vector2(1.0,0.45))
		draw_circle(Vector2.ZERO,size*0.62,Color(0.0,0.0,0.0,0.22*alpha))
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
		var rect := Rect2(at-Vector2(size*0.5,size*0.75+rise),Vector2(size,size))
		draw_texture_rect_region(FACE,rect,bump.region,Color(1.0,1.0,1.0,alpha))
