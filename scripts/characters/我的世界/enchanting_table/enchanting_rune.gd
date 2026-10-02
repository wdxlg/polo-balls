extends ball
## 附魔台射出的原版附魔符文（particle/sga_*.png，颜色按原版 EnchantmentTableParticle：
## 灰度取原版范围的亮端 0.65–1.0，红绿 ×0.9）。投射物契约与三废石石块一致：逐帧扫掠接触、权威端 RPC 生成、
## 名字确定。符文穿过墙体，出生后在书旁悬停 hover_time 再慢速飞出，按较小的 turn_rate 略微追踪目标
## （目标急转可能被甩开）。飞行时字形轻微脉动，身后飘出原版附魔字形碎片和星芒（rune_particles.gd），
## 送达时散开一圈；粒子各端本地生成。
## polarity  1：只接触敌人，走公共 hitbox 造成伤害（投射物附魔、护盾、格挡照常）。
## polarity -1：只接触友军，送达时回复 heal_amount。
## polarity  0（手控直射）：接触到的第一个敌人或友军按其身份结算。
## 每次生效都回调附魔台 on_rune_landed(目标) 推进该目标的计数。
const GLYPHS:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/enchanting_table/sga_a.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_b.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_c.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_d.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_e.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_f.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_g.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_h.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_i.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_j.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_k.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_l.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_m.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_n.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_o.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_p.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_q.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_r.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_s.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_t.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_u.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_v.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_w.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_x.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_y.png"),
	preload("res://Images/characters/我的世界/enchanting_table/sga_z.png"),
]
## 回复符文带一点绿色，便于和伤害符文区分（贴图本身是原版白色字形）。
const HEAL_TINT:Color = Color(0.75,1.0,0.75)
const PARTICLES_PATH:String = "res://scripts/characters/我的世界/enchanting_table/rune_particles.gd"
const TRAIL_INTERVAL:float = 0.045
@export var polarity:int = 1
@export var heal_amount:float = 0.0
@export var life:float = 5.5
@export var hover_time:float = 0.25
@export var turn_rate:float = 1.4
@export var glyph:int = 0
@export var shade:float = 0.7
var target_ref:WeakRef = null
var hits:int = 0
var heals:int = 0
var _age:float = 0.0
var _spent:bool = false
var _resolving_hit:bool = false
var _fx_clock:float = 0.0
var _trail_left:float = 0.0
var _last_fx_position:Vector2 = Vector2.INF

func _ready() -> void:
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Dead_Audio = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	motion_blur_enabled = false
	motion_stretch_enabled = false
	AfterImage_Speed = 0.0
	super._ready()
	health_bar.hide()
	collision_layer = 0
	collision_mask = 0
	self_hurtbox.collision_layer = 0
	self_hurtbox.collision_mask = 0
	self_hurtbox.set_deferred("monitorable",false)
	self_hurtbox.set_deferred("monitoring",false)
	self_hitbox.collision_layer = 0
	self_hitbox.collision_mask = 0
	self_hitbox.set_deferred("monitorable",false)
	self_hitbox.set_deferred("monitoring",false)
	add_to_group(&"MCEnchantingRune")
	add_to_group(&"BattleTransient")
	if image is Sprite2D:
		image.texture = GLYPHS[posmod(glyph,GLYPHS.size())]
		image.rotation = 0.0
	_refresh_color()

func _refresh_color() -> void:
	if image == null: return
	var color:Color = Color(shade*0.9,shade*0.9,shade)
	if polarity < 0: color *= HEAL_TINT
	color.a = clampf(_age/maxf(hover_time,0.01),0.0,1.0) if hover_time > 0.0 else 1.0
	image.self_modulate = color

func owner_unit() -> ball:
	return Master if is_instance_valid(Master) else self

func target() -> ball:
	var node:Variant = target_ref.get_ref() if target_ref != null else null
	return node as ball if is_instance_valid(node) and node is ball and not node.is_queued_for_deletion() and node.health > 0 else null

func _is_enemy(unit:Variant) -> bool:
	var source:ball = owner_unit()
	if source != self and source.has_method(&"is_rune_enemy"): return bool(source.call(&"is_rune_enemy",unit))
	return is_instance_valid(unit) and unit is ball and SubmissionCharacterTools.is_enemy(source,unit)

func _is_ally(unit:Variant) -> bool:
	var source:ball = owner_unit()
	if source != self and source.has_method(&"is_rune_ally"): return bool(source.call(&"is_rune_ally",unit))
	return false

func accepts(unit:Variant) -> bool:
	if not is_instance_valid(unit) or not (unit is ball) or unit == self or unit == owner_unit(): return false
	if polarity > 0: return _is_enemy(unit)
	if polarity < 0: return _is_ally(unit)
	return _is_enemy(unit) or _is_ally(unit)

func _process(delta:float) -> void:
	_refresh_color()
	if _spent or not visible: return
	var game:Node = get_node_or_null("/root/Game")
	if get_tree().paused or (game != null and bool(game.get("now_stop_state"))): return
	_fx_clock += delta
	if image != null: image.scale = Vector2.ONE*(1.0 + 0.12*sin(_fx_clock*9.0 + float(glyph)))
	var moved:Vector2 = global_position - _last_fx_position if _last_fx_position.is_finite() else Vector2.ZERO
	_last_fx_position = global_position
	_trail_left -= delta
	if _trail_left > 0.0 or moved.length_squared() <= 0.0001: return
	_trail_left = TRAIL_INTERVAL
	var fx:Node2D = (load(PARTICLES_PATH) as Script).call("find_or_create",self)
	if fx != null: fx.call("trail",global_position,moved,shade,polarity < 0,_fx_scale())

func _fx_scale() -> float:
	return clampf(absf(global_transform.get_scale().x),0.2,4.0)

func tick_physics(state:State,delta:float) -> void:
	if _spent or not is_multiplayer_authority(): return
	if health <= 0 or state == State.Die:
		expire()
		return
	if not is_combat_runtime_active(): return
	_age += delta
	life -= delta
	if life <= 0.0 or Speed <= 0.0 or not direction.is_finite() or direction.length_squared() <= 0.000001:
		expire()
		return
	if _age < hover_time: return
	var aim:ball = target()
	if aim != null and _pierced(aim):
		# Piercing continuations move on to the nearest unit they have not passed through yet.
		aim = _next_target()
		target_ref = weakref(aim) if aim != null else null
	if aim != null and turn_rate > 0.0:
		var wanted:Vector2 = global_position.direction_to(ball.body_point(aim,global_position))
		if not wanted.is_zero_approx():
			var turn:float = clampf(direction.angle_to(wanted),-turn_rate*delta,turn_rate*delta)
			direction = direction.normalized().rotated(turn)
	super.tick_physics(state,delta)

func _pierced(unit:Node) -> bool:
	return has_meta("mc_pierce_ignore") and (get_meta("mc_pierce_ignore") as Array).has(unit.get_instance_id())

func _next_target() -> ball:
	var best:float = INF
	var result:ball = null
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not accepts(candidate) or _pierced(candidate) or (candidate as ball).health <= 0: continue
		var distance:float = global_position.distance_squared_to((candidate as ball).global_position)
		if distance < best:
			best = distance
			result = candidate as ball
	return result

static func contact_t(from:Vector2,to:Vector2,center:Vector2,radius:float) -> float:
	var offset:Vector2 = from - center
	if offset.length_squared() <= radius*radius: return 0.0
	var segment:Vector2 = to - from
	var a:float = segment.length_squared()
	if a <= 0.000001: return -1.0
	var b:float = offset.dot(segment)
	var discriminant:float = b*b - a*(offset.length_squared() - radius*radius)
	if discriminant < 0.0: return -1.0
	var t:float = (-b - sqrt(discriminant))/a
	return t if t >= 0.0 and t <= 1.0 else -1.0

## 符文是魔法字形，不被墙阻挡；只扫掠角色。
func move(speed:float,delta:float) -> void:
	if _spent or delta <= 0.0: return
	var from:Vector2 = global_position
	velocity = direction*maxf(speed,0.0) + Repel
	var to:Vector2 = from + velocity*delta
	if get_tree().has_group("MinecraftAllay"):
		var capture:Script = load("res://scripts/characters/我的世界/allay/capture.gd")
		if capture.sweep(self,from,to): return
	var candidates:Array[Dictionary] = []
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not accepts(candidate): continue
		var unit:ball = candidate as ball
		var t:float = contact_t(from,to,ball.body_point_seg(unit,from,to),maxf(unit.get_crowd_separation_radius_world(),3.0) + 2.0)
		if t >= 0.0: candidates.append({"target":unit,"t":t})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return float(a.t) < float(b.t))
	for hit:Dictionary in candidates:
		var unit:Variant = hit.target
		if not is_instance_valid(unit) or unit.is_queued_for_deletion(): continue
		global_position = from.lerp(to,float(hit.t))
		if _is_enemy(unit): self_hitbox.try_hit_hurtbox(unit.self_hurtbox)
		else: _heal(unit)
		if _spent or is_queued_for_deletion(): return
	global_position = to

func _heal(unit:ball) -> void:
	if _spent or not is_multiplayer_authority(): return
	if heal_amount > 0.0: unit.heal(heal_amount)
	heals += 1
	var source:ball = owner_unit()
	if source != self and source.has_method(&"on_rune_landed"): source.call(&"on_rune_landed",unit)
	expire()

func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if _spent or _resolving_hit or not is_multiplayer_authority(): return
	var unit:ball = _hurtbox_target_ball(hurt)
	if not _is_enemy(unit) or (polarity < 0): return
	_resolving_hit = true
	super._on_hitbox_on_hit(hurt)
	_resolving_hit = false
	hits += 1
	var source:ball = owner_unit()
	var alive:bool = is_instance_valid(unit) and not unit.is_queued_for_deletion()
	if alive and source != self and source.has_method(&"on_rune_landed"): source.call(&"on_rune_landed",unit)
	expire()

func can_receive_hit_contact(_incoming:hitbox,_contact:hurtbox) -> bool: return false
func can_receive_hit_from(_incoming:hitbox) -> bool: return false
func on_incoming_hit_rejected(_incoming:hitbox) -> void: pass
func should_destroy_projectile_on_rejected_hit(_incoming:hitbox) -> bool: return false

func on_projectile_blocked_by(target_unit:ball,_point:Vector2) -> void:
	if _spent or not is_multiplayer_authority(): return
	if is_instance_valid(target_unit) and not _is_enemy(target_unit): return
	expire()

func Die() -> void: expire()
func when_collide(_speed:float,_collision:KinematicCollision2D) -> void: pass
func expire() -> void:
	if _spent: return
	var landed:bool = hits > 0 or heals > 0
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0: _retire.rpc(landed,global_position)
	_retire(landed,global_position)

@rpc("authority","call_remote","reliable")
func _retire(landed:bool = false,point:Vector2 = Vector2.INF) -> void:
	if _spent: return
	_spent = true
	if landed and is_inside_tree():
		var fx:Node2D = (load(PARTICLES_PATH) as Script).call("find_or_create",self)
		if fx != null: fx.call("burst",point if point.is_finite() else global_position,polarity < 0,shade,_fx_scale())
	hide()
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	self_hitbox.set_deferred("monitoring",false)
	self_hitbox.set_deferred("monitorable",false)
	self_hurtbox.set_deferred("monitoring",false)
	self_hurtbox.set_deferred("monitorable",false)
	state_machine.set_physics_process(false)
	queue_free()
