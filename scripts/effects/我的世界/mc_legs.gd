extends RefCounted
## 独立腿部步态（所有带腿动画的 MC 角色共用）。
## - 腿的相位只由真实位移推进，与攻击/施法/喝药等上半身动作无关：移动就迈腿，攻击时也不停。
## - 速率以角色自己的标准移速为准：相位增量 = 位移 / (标准移速 × 步态周期)，
##   即 腿速 = 实际移速 / 标准移速；标准移速 = 面板基础 Speed × 普通角色公共 0.6 实际移动倍率。
## - 停下后把当前这一步收完到最近的并腿相位，然后回到静止初始姿势（at_rest）。
## - 上半身动作帧 + 当前相位的腿，由离线烘焙的分层数据合成为一张完整帧
##   （Images/characters/我的世界/leg_layers/<set>.gd，scripts/training/mc_leg_layers 生成），
##   因此着色器朝向/受击色、残影、死亡快照、地面阴影仍然只看 sprite.texture。
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
const LAYER_DIR:String = "res://Images/characters/我的世界/leg_layers/"
## 防止超高速时腿部频闪的上限（标准速度的倍数）。
const MAX_RATE:float = 4.0
## 停步收腿速度（相对原生步频）。
const SETTLE_RATE:float = 1.8
## 物理帧与渲染帧不同步时，短暂无位移仍算在走。
const MOVE_HOLD:float = 0.12
const CACHE_PER_SET:int = 96

var phase:float = 0.25
var moving:bool = false
var at_rest:bool = true
var cycle:float = 1.0
var neutral:Array = [0.25,0.75]
## 最近一次的实际/标准速度比（仅供调试与测试）。
var rate:float = 0.0
var _last:Vector2 = Vector2.ZERO
var _primed:bool = false
var _hold:float = 0.0
var _acc_d:float = 0.0
var _acc_t:float = 0.0

static var _sets:Dictionary = {}
static var _cache:Dictionary = {}

static func create(cycle_seconds:float = 1.0, neutral_phases:Array = [0.25,0.75]) -> RefCounted:
	var g:RefCounted = load("res://scripts/effects/我的世界/mc_legs.gd").new()
	g.configure(cycle_seconds,neutral_phases)
	return g

## 用烘焙数据配置：周期 = 走路片段时长，并腿相位 = 烘焙检测出的站立相位。
static func for_set(key:String, cycle_seconds:float) -> RefCounted:
	var data:Variant = layer_data(key)
	var phases:Array = [0.25,0.75]
	if data != null and int(data.WALK) > 0 and not (data.NEUTRAL as Array).is_empty():
		phases = []
		for i:int in data.NEUTRAL: phases.append(float(i)/float(data.WALK))
	return create(cycle_seconds,phases)

func configure(cycle_seconds:float, neutral_phases:Array) -> void:
	cycle = maxf(cycle_seconds,0.05)
	neutral = neutral_phases.duplicate() if not neutral_phases.is_empty() else [0.0]
	neutral.sort()
	phase = float(neutral[0])

static func standard_speed(unit:Node) -> float:
	var base:float = FOOTSTEP.base_speed(unit)
	if unit is ball and (unit as ball).Type == ball.Ball_Type.Ball:
		base *= ball.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	return maxf(base,1.0)

## 暂停/非战斗等不推进时调用：只同步位置，避免恢复时把累积位移当成一步。
func observe(unit:Node2D) -> void:
	if is_instance_valid(unit):
		_last = unit.global_position
		_primed = true

## allow=false：眩晕/腾空/被冻结等腿不该迈的状态（位移照常吞掉，腿按停步收回）。
func tick(unit:Node2D, delta:float, allow:bool = true) -> void:
	if not is_instance_valid(unit): return
	var pos:Vector2 = unit.global_position
	if not _primed:
		_last = pos
		_primed = true
	var moved:float = pos.distance_to(_last)
	_last = pos
	if delta <= 0.0: return
	var standard:float = standard_speed(unit)
	# 瞬移/传送/大幅击飞不是走路。
	if not allow or moved > maxf(48.0,standard*delta*12.0): moved = 0.0
	_acc_d += moved
	_acc_t += delta
	if _acc_t >= 0.1:
		rate = _acc_d/_acc_t/standard
		_acc_d = 0.0
		_acc_t = 0.0
	if moved > 0.02:
		_hold = MOVE_HOLD
		moving = true
		at_rest = false
		var step:float = minf(moved/(standard*cycle),MAX_RATE*delta/cycle)
		phase = fposmod(phase+step,1.0)
		return
	_hold = maxf(_hold-delta,0.0)
	moving = _hold > 0.0
	if moving or at_rest: return
	_settle(delta)

func _settle(delta:float) -> void:
	var target:float = -1.0
	for n:float in neutral:
		if n >= phase - 0.0001:
			target = n
			break
	if target < 0.0: target = float(neutral[0]) + 1.0
	var step:float = delta*SETTLE_RATE/cycle
	if phase + step >= target:
		phase = fposmod(target,1.0)
		at_rest = true
	else:
		phase += step

## 立刻回到静止（死亡、复位、变身等）。
func reset_rest() -> void:
	phase = float(neutral[0])
	at_rest = true
	moving = false
	_hold = 0.0

func walk_index(count:int) -> int:
	if count <= 0: return 0
	return posmod(int(floor(phase*float(count)+0.0001)),count)

# ---------------------------------------------------------------- layers

static func layer_data(key:String) -> Variant:
	if key.is_empty(): return null
	if _sets.has(key): return (_sets[key] as Dictionary).get("data")
	var path:String = LAYER_DIR + key + ".gd"
	var entry:Dictionary = {}
	if ResourceLoader.exists(path): entry["data"] = load(path)
	_sets[key] = entry
	return entry.get("data")

static func has_upper(key:String, clip:StringName) -> bool:
	var data:Variant = layer_data(key)
	return data != null and (data.UPPER as Dictionary).has(clip)

static func _atlas(key:String) -> Image:
	var entry:Dictionary = _sets.get(key,{})
	if entry.has("atlas"): return entry["atlas"]
	var data:Variant = entry.get("data")
	if data == null: return null
	var img:Image = Image.new()
	if img.load_webp_from_buffer(Marshalls.base64_to_raw(String(data.WEBP))) != OK: return null # lossless WebP
	if img.get_format() != Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
	entry["atlas"] = img
	return img

## 预热：首帧合成前解码图集（角色生成时调用，避免攻击瞬间解码）。
static func prewarm(key:String) -> void:
	if layer_data(key) != null: _atlas(key)

static func _blend(dst:Image, atlas:Image, r:Array) -> void:
	if r.size() < 6: return
	dst.blend_rect(atlas,Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])),Vector2i(int(r[4]),int(r[5])))

## 上半身动作帧 clip/index + 第 leg_index 个走路相位的腿 → 完整帧。没有该片段数据时返回 null。
static func compose(key:String, clip:StringName, index:int, leg_index:int, variant:int = -1) -> Texture2D:
	var data:Variant = layer_data(key)
	if data == null: return null
	var frames:Array = (data.UPPER as Dictionary).get(clip,[])
	if frames.is_empty(): return null
	index = clampi(index,0,frames.size()-1)
	var frame:Array = frames[index]
	var legs_all:Array = data.LEGS
	var v:int = clampi(int(frame[2]) if variant < 0 else variant,0,legs_all.size()-1)
	var legs:Array = legs_all[v]
	if legs.is_empty(): return null
	leg_index = posmod(leg_index,legs.size())
	var cache:Dictionary = _cache.get(key,{})
	if cache.is_empty():
		cache = {"map":{},"order":[]}
		_cache[key] = cache
	var map:Dictionary = cache["map"]
	var ck:String = "%s|%d|%d|%d" % [clip,index,v,leg_index]
	if map.has(ck):
		var order:Array = cache["order"]
		order.erase(ck)
		order.append(ck)
		return map[ck]
	var atlas:Image = _atlas(key)
	if atlas == null: return null
	var size:Vector2i = data.SIZE
	var img:Image = Image.create_empty(size.x,size.y,false,Image.FORMAT_RGBA8)
	_blend(img,atlas,frame[1])
	_blend(img,atlas,legs[leg_index])
	_blend(img,atlas,frame[0])
	var tex:ImageTexture = ImageTexture.create_from_image(img)
	# 残影/阴影按 RID 缓存源图：直接登记已有 Image（免 GPU 回读），淘汰时同步移除，避免陈旧/泄漏。
	ball._shared_after_image_source_image_cache[str(tex.get_rid())] = img
	map[ck] = tex
	var order2:Array = cache["order"]
	order2.append(ck)
	while order2.size() > CACHE_PER_SET:
		var old:String = order2.pop_front()
		var old_tex:Texture2D = map.get(old)
		map.erase(old)
		if old_tex != null: ball._shared_after_image_source_image_cache.erase(str(old_tex.get_rid()))
	return tex

## 合成帧登记在残影源图缓存里的 Image（测试/调试用）。
static func cached_source_image(tex:Texture2D) -> Image:
	if tex == null: return null
	return ball._shared_after_image_source_image_cache.get(str(tex.get_rid())) as Image
