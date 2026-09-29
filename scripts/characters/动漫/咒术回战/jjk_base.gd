extends "res://scripts/characters/我的世界/new5/base.gd"
## 咒术回战角色公共层：咒力、反转术式、黑闪、术式烧断、领域/术式弹/特效的联机生成、
## 长按输入、头顶咒力条。具体术式在各角色脚本里实现。
const JJK = preload("res://scripts/characters/动漫/咒术回战/jjk_common.gd")
const FX = preload("res://scripts/characters/动漫/咒术回战/jjk_fx.gd")
const DOMAIN = preload("res://scripts/characters/动漫/咒术回战/jjk_domain.gd")
const V = preload("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd")
const PROJECTILE = preload("res://scripts/characters/动漫/咒术回战/jjk_projectile.gd")
const KNOCKBACK = preload("res://scripts/effects/knockback_effect.gd")

@export_category("咒术 / 咒力")
@export var cursed_energy_max:float = 1000.0
@export var cursed_energy_regen:float = 30.0
@export var rct_heal_ratio_per_second:float = 0.03
@export var rct_energy_per_health:float = 0.08
@export var black_flash_chance:float = 0.15
@export var black_flash_zone_chance:float = 0.4
@export var black_flash_zone_seconds:float = 12.0
@export var burnout_seconds:float = 3.0
@export var max_domains_per_battle:int = 5
@export var intro_sound:String = ""

var cursed_energy:float = 1000.0
var burnout_left:float = 0.0
var black_flash_zone_left:float = 0.0
var black_flash_count:int = 0
var domains_used:int = 0
var my_domain_id:int = 0
var _serial:int = 0
var _rct_carry:float = 0.0
var _held:Dictionary = {}
var _projectiles:Dictionary = {}
var _domains:Dictionary = {}
var _overlay:Node2D
var _overlay_add:Node2D
var _ovq:Dictionary = {}
var _ovq_used:Dictionary = {}
## 纯视觉粒子（世界坐标），只在绘制层使用，不参与任何判定。
var vparts:V.Parts = V.Parts.new()
var _vclock_last:float = -1.0
var vdelta:float = 0.0
var _vrng:RandomNumberGenerator = RandomNumberGenerator.new()
var _intro_played:bool = false
var _ai_think:float = 0.0

func _ready() -> void:
	super._ready()
	cursed_energy = cursed_energy_max
	add_to_group("JJKUnit")
	if image is Sprite2D: (image as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay = Node2D.new()
	_overlay.name = "JJKOverlay"
	_overlay.top_level = true
	_overlay.z_as_relative = false
	_overlay.z_index = 60
	add_child(_overlay)
	_overlay.draw.connect(_on_overlay_draw)
	_overlay_add = V.make_add_layer(_overlay,_on_overlay_add_draw)

# ---------------------------------------------------------------- 每帧
func step_mob(delta:float) -> void:
	if not is_combat_runtime_active(): return
	if not _intro_played:
		_intro_played = true
		if not intro_sound.is_empty(): sfx(intro_sound,-2.0)
	burnout_left = maxf(0.0,burnout_left - delta)
	black_flash_zone_left = maxf(0.0,black_flash_zone_left - delta)
	cursed_energy = minf(cursed_energy_max,cursed_energy + cursed_energy_regen * delta * (1.5 if black_flash_zone_left > 0.0 else 1.0))
	_step_rct(delta)
	for key:Variant in _held.keys(): _held[key] = float(_held[key]) + delta
	if not is_player_controlled() and not _held.is_empty():
		for key2:Variant in _held.keys(): on_hold_released(int(key2),float(_held[key2]))
		_held.clear()
	jjk_step(delta)
	if not is_player_controlled() and can_act():
		_ai_think -= delta
		if _ai_think <= 0.0:
			_ai_think = 0.1
			jjk_ai()

func _step_rct(delta:float) -> void:
	if health >= Max_health or health <= 0 or rct_heal_ratio_per_second <= 0.0: return
	if cursed_energy < cursed_energy_max * 0.08: return
	_rct_carry += float(Max_health) * rct_heal_ratio_per_second * delta
	if _rct_carry >= 1.0:
		var amount:int = int(_rct_carry)
		_rct_carry -= amount
		var healed:int = heal(amount)
		cursed_energy = maxf(0.0,cursed_energy - healed * rct_energy_per_health)

## 子类覆写。
func jjk_step(_delta:float) -> void: pass
func jjk_ai() -> void: pass
func on_projectile_impact(_kind:String,_target:ball,_point:Vector2) -> void: pass
func on_domain_closed(_kind:String,_broken:bool) -> void: pass
func draw_overlay(_o:Node2D) -> void: pass
## 叠加混合（发光）层的绘制钩子；o 为叠加层节点，坐标为世界坐标。
func draw_overlay_add(_o:Node2D) -> void: pass
## 每个画面帧调用一次，用于发射纯视觉粒子（vdelta 为画面时间步长）。
func visual_particles(_dt:float) -> void: pass
## 子类在这里调用 ovq() 布置着色器面片（每帧；未调用的面片自动隐藏）。
func visual_quads() -> void: pass

## 覆盖层着色器面片（按名字复用）。layer: 1 = 覆盖层最底，2 = 最上。
func ovq(qname:String,mode:int,layer:int,pos:Vector2,size:Vector2,rot:float,params:Dictionary) -> void:
	if not is_instance_valid(_overlay) or DisplayServer.get_name() == "headless": return
	var sp:Sprite2D = _ovq.get(qname)
	if sp == null:
		sp = V.quad(_overlay,mode,layer)
		_ovq[qname] = sp
	if not params.has("time"): params["time"] = _view_clock
	if not params.has("seed"): params["seed"] = float(get_instance_id() % 97) * 0.53
	V.qset(sp,pos,size,rot,params)
	_ovq_used[qname] = true

# ---------------------------------------------------------------- 资源
func spend(amount:float) -> bool:
	if cursed_energy < amount: return false
	cursed_energy -= amount
	return true

func technique_ready() -> bool:
	return burnout_left <= 0.0

func can_open_domain() -> bool:
	return technique_ready() and domains_used < max_domains_per_battle and not _has_own_domain()

func _has_own_domain() -> bool:
	for id:Variant in _domains.keys():
		var d:Node = _domains[id]
		if is_instance_valid(d) and d.get("domain_kind") != "uv_instant" and bool(d.call("is_active")): return true
	return false

func own_domain() -> Node:
	for id:Variant in _domains.keys():
		var d:Node = _domains[id]
		if is_instance_valid(d) and d.get("domain_kind") != "uv_instant" and bool(d.call("is_active")): return d
	return null

## 黑闪：近身打击时掷骰；成功返回 2.5 倍率并进入“极之番”状态。
func roll_black_flash(point:Vector2) -> float:
	var chance:float = black_flash_zone_chance if black_flash_zone_left > 0.0 else black_flash_chance
	if rng.randf() >= chance: return 1.0
	black_flash_count += 1
	black_flash_zone_left = black_flash_zone_seconds
	cursed_energy = minf(cursed_energy_max,cursed_energy + cursed_energy_max * 0.15)
	burnout_left = maxf(0.0,burnout_left - 2.0)
	sfx("black_flash",0.0)
	sfx("black_flash_hit",-2.0)
	fx("black_flash",{"pos":point,"radius":70.0},0.45)
	fx("text",{"pos":point + Vector2(0,-40),"text":"Black Flash" if JJK.english() else "黑闪","size":26,"color":Color(1.0,0.2,0.25),"world":true},0.9)
	return 2.5

func is_player_controlled_and_active() -> bool:
	return is_player_controlled() and can_act()

# ---------------------------------------------------------------- 长按输入
## 左/右/中键被 Game 以长按重复调用；首次按下时 on_press，松开时 on_hold_released。
func press(index:int) -> void:
	if not is_player_controlled(): return
	if _held.has(index): return
	_held[index] = 0.0
	# 按下时技能未就绪（冷却/咒力不足）：不进入长按，长按重复时会再次尝试。
	if not on_press(index): _held.erase(index)

func held_time(index:int) -> float:
	return float(_held.get(index,-1.0))

func is_held(index:int) -> bool:
	return _held.has(index)

func player_control_action_released(index:int) -> void:
	if not _held.has(index): return
	var time:float = float(_held[index])
	_held.erase(index)
	on_hold_released(index,time)

func player_control_action_cancelled(index:int) -> void:
	_held.erase(index)

func on_press(_index:int) -> bool: return false
func on_hold_released(_index:int,_time:float) -> void: pass

# ---------------------------------------------------------------- 网络：音效/特效
func sfx(key:String,volume_db:float = 0.0) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.has_multiplayer_peer(): _jjk_sound.rpc(key,global_position,volume_db)
	_jjk_sound(key,global_position,volume_db)

@rpc("authority","call_remote","reliable")
func _jjk_sound(key:String,point:Vector2,volume_db:float) -> void:
	JJK.play_local(self,key,point,volume_db)

## 大招过场特写（纯视觉）。right=true 从右侧切入。
func cutin(title_zh:String,title_en:String,sub_zh:String,sub_en:String,color:Color,right:bool = false) -> void:
	var face_path:String = ""
	if image is Sprite2D and (image as Sprite2D).texture != null: face_path = (image as Sprite2D).texture.resource_path
	var en:bool = JJK.english()
	fx("cutin",{"face":face_path,"title":title_en if en else title_zh,"sub":sub_en if en else sub_zh,"color":color,"right":right,"world":true},1.25)

func fx(kind:String,data:Dictionary,duration:float) -> void:
	if not is_multiplayer_authority(): return
	data = data.duplicate()
	if not data.has("seed"): data["seed"] = rng.randi()
	if multiplayer.has_multiplayer_peer(): _jjk_fx.rpc(kind,data,duration)
	_jjk_fx(kind,data,duration)

@rpc("authority","call_remote","reliable")
func _jjk_fx(kind:String,data:Dictionary,duration:float) -> void:
	FX.spawn(self,kind,data,duration)

# ---------------------------------------------------------------- 网络：术式弹
func launch(kind:String,from:Vector2,velocity_value:Vector2,radius_value:float,life_value:float) -> int:
	if not is_multiplayer_authority(): return 0
	_serial += 1
	if multiplayer.has_multiplayer_peer(): _jjk_launch.rpc(_serial,kind,from,velocity_value,radius_value,life_value)
	_jjk_launch(_serial,kind,from,velocity_value,radius_value,life_value)
	return _serial

@rpc("authority","call_remote","reliable")
func _jjk_launch(id:int,kind:String,from:Vector2,velocity_value:Vector2,radius_value:float,life_value:float) -> void:
	var p:PROJECTILE = PROJECTILE.new()
	p.name = "JJKShot_%d" % id
	p.caster = self
	p.id = id
	p.kind = kind
	p.velocity = velocity_value
	p.radius = radius_value
	p.life = life_value
	p.authority = is_multiplayer_authority()
	add_child(p)
	p.global_position = from
	_projectiles[id] = p

func on_jjk_projectile_end(id:int,kind:String,target:ball,point:Vector2) -> void:
	_projectiles.erase(id)
	if multiplayer.has_multiplayer_peer(): _jjk_projectile_end.rpc(id)
	on_projectile_impact(kind,target,point)

@rpc("authority","call_remote","reliable")
func _jjk_projectile_end(id:int) -> void:
	var p:Node = _projectiles.get(id)
	_projectiles.erase(id)
	if is_instance_valid(p): p.call("end_remote")

# ---------------------------------------------------------------- 网络：领域
func open_domain(kind:String,center:Vector2,radius_value:float,duration:float) -> Node:
	if not is_multiplayer_authority(): return null
	_serial += 1
	if kind != "uv_instant": domains_used += 1
	if multiplayer.has_multiplayer_peer(): _jjk_domain_open.rpc(_serial,kind,center,radius_value,duration)
	_jjk_domain_open(_serial,kind,center,radius_value,duration)
	my_domain_id = _serial
	return _domains.get(_serial)

@rpc("authority","call_remote","reliable")
func _jjk_domain_open(id:int,kind:String,center:Vector2,radius_value:float,duration:float) -> void:
	var d:DOMAIN = DOMAIN.new()
	d.name = "JJKDomain_%d" % id
	d.caster = self
	d.id = id
	d.domain_kind = kind
	d.center = center
	d.radius = radius_value
	d.duration = duration
	d.authority = is_multiplayer_authority()
	add_child(d)
	_domains[id] = d

func on_jjk_domain_end(id:int,broken:bool) -> void:
	var d:Node = _domains.get(id)
	var kind:String = str(d.get("domain_kind")) if is_instance_valid(d) else ""
	_domains.erase(id)
	if multiplayer.has_multiplayer_peer(): _jjk_domain_close.rpc(id,broken)
	if kind != "uv_instant":
		burnout_left = maxf(burnout_left,burnout_seconds + (2.0 if broken else 0.0))
		fx("text",{"pos":global_position + Vector2(0,-60),"text":"Burnout" if JJK.english() else "术式烧断","size":20,"color":Color(1,0.6,0.5)},1.2)
	on_domain_closed(kind,broken)

@rpc("authority","call_remote","reliable")
func _jjk_domain_close(id:int,broken:bool) -> void:
	var d:Node = _domains.get(id)
	_domains.erase(id)
	if is_instance_valid(d): d.call("end_remote",broken)

# ---------------------------------------------------------------- 视觉同步
func visual_state() -> Dictionary:
	var data:Dictionary = super.visual_state()
	data["ce"] = cursed_energy
	data["bo"] = burnout_left
	data["bf"] = black_flash_zone_left
	var doms:Dictionary = {}
	for id:Variant in _domains.keys():
		var d:Node = _domains[id]
		if is_instance_valid(d): doms[id] = [float(d.get("barrier_hp")),float(d.get("flip_left")),bool(d.get("shrunk"))]
	data["dm"] = doms
	return data

func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	cursed_energy = float(data.get("ce",cursed_energy))
	burnout_left = float(data.get("bo",burnout_left))
	black_flash_zone_left = float(data.get("bf",black_flash_zone_left))
	var doms:Variant = data.get("dm",{})
	if doms is Dictionary:
		for id:Variant in doms.keys():
			var d:Node = _domains.get(id)
			var v:Variant = doms[id]
			if is_instance_valid(d) and v is Array and v.size() >= 3:
				d.set("barrier_hp",float(v[0]))
				d.set("flip_left",float(v[1]))
				d.set("shrunk",bool(v[2]))

func client_visual_step(delta:float) -> void:
	burnout_left = maxf(0.0,burnout_left - delta)
	black_flash_zone_left = maxf(0.0,black_flash_zone_left - delta)

func visual_mob() -> void:
	if not is_instance_valid(_overlay): return
	_overlay.global_position = Vector2.ZERO
	_overlay.visible = health > 0
	if _vclock_last < 0.0: _vclock_last = _view_clock
	vdelta = clampf(_view_clock - _vclock_last,0.0,0.1)
	_vclock_last = _view_clock
	if vdelta > 0.0 and health > 0:
		visual_particles(vdelta)
		vparts.step(vdelta)
	_ovq_used.clear()
	if health > 0: visual_quads()
	for qn:Variant in _ovq.keys():
		if not _ovq_used.has(qn): (_ovq[qn] as Sprite2D).visible = false
	_overlay.queue_redraw()
	if is_instance_valid(_overlay_add): _overlay_add.queue_redraw()

func _on_overlay_draw() -> void:
	if health <= 0: return
	var o:Node2D = _overlay
	var base:Vector2 = global_position + Vector2(-24,20)
	o.draw_rect(Rect2(base,Vector2(48,5)),Color(0,0,0,0.6))
	var ratio:float = clampf(cursed_energy / maxf(cursed_energy_max,1.0),0.0,1.0)
	var col:Color = Color(0.55,0.4,1.0) if burnout_left <= 0.0 else Color(0.5,0.5,0.5)
	o.draw_rect(Rect2(base + Vector2(1,1),Vector2(46 * ratio,3)),col)
	if burnout_left > 0.0:
		o.draw_line(base + Vector2(0,7),base + Vector2(48 * clampf(burnout_left / maxf(burnout_seconds + 2.0,0.1),0,1),7),Color(1.0,0.4,0.3,0.9),2.0)
	if black_flash_zone_left > 0.0:
		# 黑闪状态（the zone）：黑红两色的火花电弧绕身闪烁。
		_vrng.seed = int(_view_clock * 22.0) + get_instance_id()
		for i:int in 3:
			var a:float = _vrng.randf() * TAU
			var pts:PackedVector2Array = V.bolt(_vrng,global_position + Vector2.from_angle(a) * 18.0,global_position + Vector2.from_angle(a + _vrng.randf_range(0.6,1.4)) * 30.0,6.0,3)
			o.draw_polyline(pts,Color(0,0,0,0.9),3.0,true)
	draw_overlay(o)
	vparts.draw_normal(o)

func _on_overlay_add_draw() -> void:
	if health <= 0: return
	var o:Node2D = _overlay_add
	if black_flash_zone_left > 0.0:
		V.glow(o,global_position,40.0,Color(0.9,0.05,0.1,0.35 + 0.15 * sin(_view_clock * 12.0)))
		_vrng.seed = int(_view_clock * 22.0) + get_instance_id() + 7
		for i:int in 3:
			var a:float = _vrng.randf() * TAU
			var pts:PackedVector2Array = V.bolt(_vrng,global_position + Vector2.from_angle(a) * 18.0,global_position + Vector2.from_angle(a + _vrng.randf_range(0.6,1.4)) * 30.0,6.0,3)
			V.draw_bolt(o,pts,1.5,Color(1.0,0.1,0.15,0.9),Color(1,0.8,0.8,1))
	draw_overlay_add(o)
	vparts.draw_add(o)

# ---------------------------------------------------------------- AI 工具
func ai_target() -> ball:
	var t:ball = JJK.nearest_enemy(self)
	if is_instance_valid(t):
		Target_Enemy = t
		Nearest_Enemy = t
	return t

func steer(dir:Vector2) -> void:
	if dir.length_squared() > 0.0001: direction = dir.normalized()

func steer_keep_distance(target:ball,desired:float,band:float = 40.0) -> void:
	if not is_instance_valid(target): return
	var to:Vector2 = target.global_position - global_position
	var d:float = to.length()
	var side:Vector2 = to.orthogonal().normalized() * (1.0 if int(clock / 2.5) % 2 == 0 else -1.0)
	if d > desired + band: steer(to.normalized() * 0.8 + side * 0.3)
	elif d < desired - band: steer(-to.normalized() * 0.8 + side * 0.4)
	else: steer(side)

func aim_point(fallback:Vector2) -> Vector2:
	if is_player_controlled(): return player_control_aim_world_position(fallback)
	return fallback

func aim_dir(fallback:Vector2) -> Vector2:
	if is_player_controlled(): return player_control_aim_direction(fallback)
	return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector2.RIGHT

## 预测直线弹的提前量。
func lead(target:ball,speed:float) -> Vector2:
	if not is_instance_valid(target): return global_position + direction * 100.0
	var d:float = global_position.distance_to(target.global_position)
	return target.global_position + target.velocity * clampf(d / maxf(speed,1.0),0.0,1.2)

func Die() -> void:
	for id:Variant in _domains.keys():
		var d:Node = _domains[id]
		if is_instance_valid(d) and is_multiplayer_authority(): d.call("finish",false)
	super.Die()

func get_preview_texture() -> Texture2D:
	return (image as Sprite2D).texture if image is Sprite2D else null
