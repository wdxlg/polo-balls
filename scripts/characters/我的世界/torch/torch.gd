extends "res://scripts/characters/我的世界/new5/base.gd"
# 火把（原版 torch / soul_torch 贴图）：火焰尖端持续燃烧，周期性向四周掉落火星，落地成火（torch_fire.gd）。
# 地图外围的灵魂沙（soul_sand_field.gd）随机向内蔓延；站在灵魂沙上积累脚下进度条，满后永久变成灵魂火把：
# 掉火星更快，落在灵魂沙上的火星变成伤害与燃烧翻倍的灵魂火。灵魂火把碰到自己的灵魂火会化作火焰，
# 依次冲向最近的、未被墙挡住的下一团灵魂火（每团每轮一次，不消耗），扫到的敌人受伤、燃烧并被击退；结束后冷却。
# 没有主动键：手控只接管移动，火星、充能与连冲照常自动进行。
const FIELD = preload("res://scripts/characters/我的世界/torch/soul_sand_field.gd")
const FIRE = preload("res://scripts/characters/我的世界/torch/torch_fire.gd")
const SPARK = preload("res://scripts/characters/我的世界/torch/torch_spark.gd")
const TORCH_AUDIO = preload("res://scripts/characters/我的世界/torch/torch_audio.gd")
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const PAIRS = preload("res://classes/body_collision_exclusions.gd")
const BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
const VFX = preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
const SOUL_PARTICLE = preload("res://scripts/effects/我的世界/灵魂粒子.gd")
const RUNTIME = preload("res://scripts/effects/我的世界/mc_explosion.gd")
const SOUL_TORCH_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/torch/soul_torch.png")
const FLAME:Texture2D = preload("res://Images/characters/我的世界/torch/flame.png")
const SOUL_FLAME:Texture2D = preload("res://Images/characters/我的世界/torch/soul_fire_flame.png")
const PARTICLES = preload("res://scripts/characters/我的世界/torch/torch_particles.gd")
## 冲刺火焰形态：没有贴图，由原版灵魂火苗粒子在火把位置随机密集生成（越靠中心越密）。
const DASH_BODY_RATE:float = 280.0 # 每秒生成的火苗数
## 火焰尖端（贴图第 6–7 行）相对 Image 的局部坐标，已含场景里的 offset，单位为贴图像素。
const TIP_TEXEL:Vector2 = Vector2(0.0,-4.0)
const TIP_FLAME_TEXEL:Vector2 = Vector2(0.0,-6.2)
const TIP_FLAME_SCALE:float = 0.42
const SOUL_BAR_COLOR:Color = Color("50e8ee")
const FLAME_FORM_CELLS:float = 1.3

@export var spark_interval:float = 0.6
@export var soul_spark_interval:float = 0.3
@export var spark_min_cells:float = 0.6
@export var spark_max_cells:float = 2.6
@export var spark_flight:float = 0.6
## 火星抛物线顶点高度 = spark_arc + 水平距离 × spark_arc_per_distance（先升后落）。
@export var spark_arc:float = 12.0
@export var spark_arc_per_distance:float = 0.55
@export var fire_duration:float = 8.0
## 火的伤害半径（格）：0.5 即火焰所在那一格的内切圆。
@export var fire_radius_cells:float = 0.5
@export var fire_tick_multiplier:float = 0.5
@export var burn_seconds:float = 3.0
@export var burn_tick_multiplier:float = 0.3
## 灵魂火的地面伤害与燃烧倍率。
@export var soul_multiplier:float = 2.0
## 站在灵魂沙上积满进度条所需秒数（离开不回退）。
@export var soul_charge_seconds:float = 8.0
@export var dash_speed:float = 420.0
@export var dash_damage_multiplier:float = 3.0
@export var dash_cooldown:float = 3.0
@export var dash_max_hops:int = 32
@export var dash_max_seconds:float = 8.0
@export var ignite_sound_gap:float = 0.9

var soul_charge:float = 0.0
var soul_form:bool = false
var dashing:bool = false
var dash_hops:int = 0
var _field:Node2D
var _spark_wait:float = 0.8
var _fire_seq:int = 0
var _fires:Dictionary = {}
var _fire_cells:Dictionary = {}
var _event_serial:int = 0
var _last_event_serial:int = 0
var _ignite_wait:float = 0.0
var _dash_target:Variant = null
var _dash_goal:Vector2 = Vector2.INF
var _dash_visited:Dictionary = {}
var _dash_hit:Dictionary = {}
var _dash_age:float = 0.0
var _dash_cooldown_left:float = 0.0
var _dash_pairs:Array[PhysicsBody2D] = []
var _tip_flame:Sprite2D
var _shown_dash:bool = false
var _fx_rng := RandomNumberGenerator.new()
var _flame_wait:float = 0.0
var _smoke_wait:float = 0.4
var _trail_from:Vector2 = Vector2.INF
var _trail_carry:float = 0.0
var _trail_count:int = 0
var _form_heading:float = 0.0
var _form_last:Vector2 = Vector2.INF
var _body_carry:float = 0.0
var _drawn_charge:float = -1.0
var _drawn_soul:bool = false


func _ready() -> void:
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	Unique_Death_Audio = AUDIO.EVENTS["entity.item.break"][0].stream
	super._ready()
	add_to_group("MCTorch")
	_fx_rng.randomize()
	_spark_wait = spark_interval
	if image is Sprite2D:
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_flame_visuals()
	_ensure_field.call_deferred()


func _build_flame_visuals() -> void:
	if not image is Sprite2D: return
	_tip_flame = Sprite2D.new()
	_tip_flame.name = "TipFlame"
	_tip_flame.texture = FLAME
	_tip_flame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tip_flame.position = TIP_FLAME_TEXEL
	_tip_flame.scale = Vector2.ONE * TIP_FLAME_SCALE
	image.add_child(_tip_flame)


func _ensure_field() -> void:
	if not is_inside_tree() or health <= 0: return
	if is_instance_valid(_field) and not _field.is_queued_for_deletion() and not bool(_field.get("_retiring")): return
	_field = FIELD.ensure(self)


func soul_sand_field() -> Node2D:
	return _field if is_instance_valid(_field) else null


func body_rect() -> Rect2:
	var shape_node:CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null: return Rect2(global_position - Vector2.ONE * 4.0,Vector2.ONE * 8.0)
	return shape_node.global_transform * shape_node.shape.get_rect()


func tip_world_position() -> Vector2:
	if image == null or not is_instance_valid(image): return global_position + Vector2(0.0,-8.0)
	return image.global_transform * TIP_TEXEL


func cell_size() -> float:
	if is_instance_valid(_field):
		var size:Vector2 = _field.get("grid_size")
		return minf(size.x,size.y)
	return 16.0


func cell_key(point:Vector2) -> Vector2i:
	if is_instance_valid(_field): return _field.call("cell_of",point)
	return Vector2i((point / 16.0).floor())


func snap_to_cell(point:Vector2) -> Vector2:
	if is_instance_valid(_field): return _field.call("cell_center",_field.call("cell_of",point))
	return ((point / 16.0).floor() + Vector2(0.5,0.5)) * 16.0


func dash_radius() -> float:
	return cell_size() * 0.5


func step_mob(delta:float) -> void:
	_ensure_field()
	_prune_fires()
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta,0.0)
	_ignite_wait = maxf(_ignite_wait - delta,0.0)
	if dashing:
		_advance_dash(delta)
		return
	_charge_soul(delta)
	_tick_sparks(delta)
	_try_begin_dash()


func move(speed:float,delta:float) -> void:
	if dashing: return
	super.move(speed,delta)


func stand(delta:float) -> void:
	if dashing: return
	super.stand(delta)


# --- 灵魂沙充能 ---

func _charge_soul(delta:float) -> void:
	if soul_form or not is_instance_valid(_field): return
	if not bool(_field.call("touches_rect",body_rect())): return
	soul_charge = minf(soul_charge + delta * preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self) / maxf(soul_charge_seconds,0.1),1.0)
	if soul_charge >= 1.0: _become_soul()


func _become_soul() -> void:
	if soul_form: return
	_spark_wait = minf(_spark_wait,soul_spark_interval)
	_event_serial += 1
	var index:int = _voice_rng.randi_range(0,TORCH_AUDIO.variant_count(TORCH_AUDIO.KIND_SOUL) - 1)
	if multiplayer.has_multiplayer_peer(): _receive_soul_form.rpc(_event_serial,index)
	_receive_soul_form(_event_serial,index)


@rpc("authority","call_remote","reliable")
func _receive_soul_form(serial:int,index:int) -> void:
	if serial <= _last_event_serial: return
	_last_event_serial = serial
	soul_form = true
	soul_charge = 1.0
	_apply_soul_visual()
	TORCH_AUDIO.play(self,TORCH_AUDIO.KIND_SOUL,index,global_position)
	_soul_burst()


func _apply_soul_visual() -> void:
	if image is Sprite2D: (image as Sprite2D).texture = SOUL_TORCH_TEXTURE
	if is_instance_valid(_tip_flame): _tip_flame.texture = SOUL_FLAME
	queue_redraw()


func _soul_burst() -> void:
	if not is_inside_tree() or get_tree().current_scene == null: return
	var container:Node2D = RUNTIME.runtime_container(self)
	for i:int in range(mini(10,SOUL_PARTICLE.room(get_tree()))):
		var angle:float = _fx_rng.randf() * TAU
		var soul := SOUL_PARTICLE.new()
		container.add_child(soul)
		soul.setup(global_position + Vector2.RIGHT.rotated(angle) * _fx_rng.randf_range(2.0,7.0),Vector2.RIGHT.rotated(angle) * _fx_rng.randf_range(4.0,10.0),
			_fx_rng.randf_range(0.7,1.1),7.0,_fx_rng.randf_range(10.0,18.0))
		soul.from_frame(3)


# --- 火星与火 ---

func _tick_sparks(delta:float) -> void:
	if is_damage_output_disabled(): return
	_spark_wait -= delta
	if _spark_wait > 0.0: return
	_spark_wait += maxf(soul_spark_interval if soul_form else spark_interval,0.05)
	launch_spark()


## 权威端：挑落点并广播一颗火星。灵魂火只在已是灵魂火把且落点为灵魂沙时生成。
func launch_spark() -> void:
	var land:Vector2 = _pick_landing()
	var soul_fire:bool = soul_form and is_instance_valid(_field) and bool(_field.call("has_sand_at",land))
	_fire_seq += 1
	var sound:bool = _ignite_wait <= 0.0
	if sound: _ignite_wait = ignite_sound_gap
	var from:Vector2 = tip_world_position()
	if multiplayer.has_multiplayer_peer(): _receive_spark.rpc(_fire_seq,from,land,soul_fire,sound)
	_receive_spark(_fire_seq,from,land,soul_fire,sound)


@rpc("authority","call_remote","reliable")
func _receive_spark(id:int,from:Vector2,land:Vector2,soul_fire:bool,sound:bool) -> void:
	if not is_inside_tree() or get_tree().current_scene == null: return
	var spark := SPARK.new()
	spark.setup(self,id,from,land,spark_flight,spark_arc + from.distance_to(land) * spark_arc_per_distance,soul_fire,sound)
	RUNTIME.runtime_container(self).add_child(spark)
	TORCH_AUDIO.play(self,TORCH_AUDIO.KIND_POP,0,from,0.85 + 0.075 * float(id % 5))


func _pick_landing() -> Vector2:
	var origin:Vector2 = global_position
	var spare:Vector2 = Vector2.INF
	for i:int in range(10):
		var offset:Vector2 = Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(spark_min_cells,maxf(spark_max_cells,spark_min_cells)) * cell_size()
		var point:Vector2 = snap_to_cell(origin + offset)
		if not _landing_ok(origin,point): continue
		if not _fire_cells.has(cell_key(point)): return point
		if spare == Vector2.INF: spare = point
	return spare if spare != Vector2.INF else snap_to_cell(origin)


func _landing_ok(origin:Vector2,point:Vector2) -> bool:
	if is_instance_valid(_field) and not bool(_field.call("is_floor_at",point)): return false
	if not U.line_clear(self,origin,point): return false
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_point(query,1).is_empty()


## 各端：火星落地后在本端生火；同一格只保留最新的一团。
func spark_landed(id:int,land:Vector2,soul_fire:bool,sound:bool) -> void:
	if not is_inside_tree() or health <= 0 or get_tree().current_scene == null: return
	var key:Vector2i = cell_key(land)
	var old:Variant = _fire_cells.get(key)
	if is_instance_valid(old):
		_fires.erase(int((old as Node).get("fire_id")))
		(old as Node).queue_free()
	var fire := FIRE.new()
	fire.name = "TorchFire_%d_%d" % [get_instance_id(),id]
	RUNTIME.runtime_container(self).add_child(fire)
	var k:float = soul_multiplier if soul_fire else 1.0
	fire.setup_torch(self,id,land,soul_fire,cell_size() * fire_radius_cells,fire_duration,fire_tick_multiplier * k,burn_seconds,burn_tick_multiplier * k)
	fire.cell = key
	_fires[id] = fire
	_fire_cells[key] = fire
	if sound: TORCH_AUDIO.play(self,TORCH_AUDIO.KIND_IGNITE,0,land,0.85 if soul_fire else 1.0)


func _prune_fires() -> void:
	for id:Variant in _fires.keys():
		var fire:Variant = _fires[id]
		if not is_instance_valid(fire) or (fire as Node).is_queued_for_deletion(): _fires.erase(id)
	for key:Variant in _fire_cells.keys():
		var fire:Variant = _fire_cells[key]
		if not is_instance_valid(fire) or (fire as Node).is_queued_for_deletion(): _fire_cells.erase(key)


func live_fires() -> Array:
	var result:Array = []
	for fire:Variant in _fires.values():
		if is_instance_valid(fire) and not (fire as Node).is_queued_for_deletion() and fire.time_left() > 0.0: result.append(fire)
	return result


func soul_fires() -> Array:
	var result:Array = []
	for fire:Variant in live_fires():
		if fire.soul and fire.time_left() > 0.15: result.append(fire)
	return result


# --- 灵魂火连冲 ---

func _try_begin_dash() -> void:
	if not soul_form or _dash_cooldown_left > 0.0 or is_damage_output_disabled() or is_hard_controlled() or dizziness: return
	var rect:Rect2 = body_rect()
	for fire:Variant in soul_fires():
		var center:Vector2 = fire.damage_center()
		if center.distance_to(center.clamp(rect.position,rect.end)) <= fire.damage_radius():
			_begin_dash(fire)
			return


func _begin_dash(first:Variant) -> void:
	_dash_visited = {int(first.fire_id):true}
	var next:Variant = _next_dash_fire(global_position)
	if next == null: return
	dashing = true
	dash_hops = 0
	_dash_hit.clear()
	_dash_age = 0.0
	_set_dash_target(next)
	_acquire_pass_through()
	_emit_dash_event(0)


func _set_dash_target(fire:Variant) -> void:
	_dash_target = fire
	_dash_visited[int(fire.fire_id)] = true
	_dash_goal = fire.damage_center()


## 最近的、本轮未经过、直线不被墙挡住的灵魂火；被挡住的这次跳过，换个位置还可再选。
func _next_dash_fire(from:Vector2) -> Variant:
	var candidates:Array = []
	for fire:Variant in soul_fires():
		if not _dash_visited.has(int(fire.fire_id)): candidates.append(fire)
	candidates.sort_custom(func(a:Variant,b:Variant) -> bool: return from.distance_squared_to(a.damage_center()) < from.distance_squared_to(b.damage_center()))
	for fire:Variant in candidates:
		if U.line_clear(self,from,fire.damage_center()): return fire
	return null


func _retarget() -> bool:
	var next:Variant = _next_dash_fire(global_position)
	if next == null: return false
	_set_dash_target(next)
	return true


func _advance_dash(delta:float) -> void:
	_dash_age += delta
	if is_hard_controlled() or dizziness or is_damage_output_disabled() or _dash_age > dash_max_seconds:
		_end_dash()
		return
	if not is_instance_valid(_dash_target) or (_dash_target as Node).is_queued_for_deletion():
		if not _retarget(): _end_dash()
		return
	var start:Vector2 = global_position
	var offset:Vector2 = _dash_goal - start
	var step:float = maxf(dash_speed,1.0) * motion_scaled_delta(delta)
	var motion:Vector2 = offset if offset.length() <= step else offset.normalized() * step
	var collision:KinematicCollision2D = move_and_collide(motion)
	if collision != null and collision.get_collider() is ball:
		_pass_through(collision.get_collider() as PhysicsBody2D)
		collision = move_and_collide(collision.get_remainder())
	velocity = (global_position - start) / maxf(delta,0.0001)
	_dash_sweep(start,global_position)
	if collision != null:
		# 被墙或障碍挡住：放弃这一团，从当前位置改冲下一团。
		if not _retarget(): _end_dash()
		return
	if global_position.distance_to(_dash_goal) <= 0.5:
		dash_hops += 1
		if dash_hops >= dash_max_hops or not _retarget(): _end_dash()
		else: _emit_dash_event(1)


func _dash_sweep(a:Vector2,b:Vector2) -> void:
	if a.distance_squared_to(b) < 0.0001: return
	var heading:Vector2 = (b - a).normalized()
	for contact:Dictionary in SWEEP.contacts(self,a,b,dash_radius(),_dash_hit):
		var target:ball = contact.get("target") as ball
		if target == null or _dash_hit.has(target.get_instance_id()): continue
		_dash_hit[target.get_instance_id()] = true
		_dash_strike(target,contact.get("point",target.global_position),heading)


## 每轮连冲每个敌人一次：直接穿过，造成火焰伤害和灵魂火强度的燃烧，没有击退。
func _dash_strike(target:ball,point:Vector2,_heading:Vector2) -> void:
	if not U.enemy(self,target): return
	if not target.receive_fire_positional_damage(attack_damage(dash_damage_multiplier),point,false,self,{"carrier":"body_contact"}): return
	FIRE.apply_burn(self,target,burn_seconds,attack_damage(burn_tick_multiplier * soul_multiplier),true)
	_emit_dash_event(3)


func _acquire_pass_through() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node != self and node is PhysicsBody2D: _pass_through(node as PhysicsBody2D)


func _pass_through(body:PhysicsBody2D) -> void:
	if not is_instance_valid(body) or body == self or _dash_pairs.has(body): return
	PAIRS.acquire(self,body,self)
	_dash_pairs.append(body)


func _release_pass_through() -> void:
	for body:PhysicsBody2D in _dash_pairs:
		if is_instance_valid(body): PAIRS.release(self,body,self)
	_dash_pairs.clear()


func _end_dash() -> void:
	if not dashing: return
	dashing = false
	_dash_target = null
	_dash_goal = Vector2.INF
	_release_pass_through()
	_dash_cooldown_left = dash_cooldown
	velocity = Vector2.ZERO
	_emit_dash_event(2)


## 0 开始、1 下一跳、2 结束、3 烧伤一个敌人（只播音效）。
func _emit_dash_event(kind:int) -> void:
	_event_serial += 1
	if multiplayer.has_multiplayer_peer(): _receive_dash_event.rpc(_event_serial,kind,global_position)
	_receive_dash_event(_event_serial,kind,global_position)


@rpc("authority","call_remote","reliable")
func _receive_dash_event(serial:int,kind:int,point:Vector2) -> void:
	if serial <= _last_event_serial: return
	_last_event_serial = serial
	if not is_multiplayer_authority(): dashing = kind != 2
	if kind == 2: TORCH_AUDIO.play(self,TORCH_AUDIO.KIND_FIZZ,0,point)
	elif kind == 3: TORCH_AUDIO.play(self,TORCH_AUDIO.KIND_HURT_FIRE,serial % TORCH_AUDIO.variant_count(TORCH_AUDIO.KIND_HURT_FIRE),point)
	else: TORCH_AUDIO.play(self,TORCH_AUDIO.KIND_DASH,0,point,1.0 + 0.06 * float(serial % 3))


# --- 表现 ---

func _process(delta:float) -> void:
	super._process(delta)
	if image == null or not is_instance_valid(image): return
	_update_flame_particles(delta)
	_update_dash_trail()
	if not is_equal_approx(_drawn_charge,soul_charge) or _drawn_soul != soul_form: queue_redraw()


func visual_mob() -> void:
	if image == null or not is_instance_valid(image): return
	if _shown_dash != dashing and health > 0:
		_shown_dash = dashing
		image.visible = not dashing
		_form_last = Vector2.INF
		_body_carry = 0.0
	if is_instance_valid(_tip_flame):
		var t:float = Time.get_ticks_msec() * 0.001 + float(get_instance_id() % 97)
		var flicker:float = 1.0 + 0.1 * sin(t * 21.0) + 0.06 * sin(t * 37.0 + 1.3)
		_tip_flame.scale = Vector2(TIP_FLAME_SCALE * (1.0 - 0.4 * (flicker - 1.0)),TIP_FLAME_SCALE * flicker)
		_tip_flame.position = TIP_FLAME_TEXEL + Vector2(0.0,-0.6 * (flicker - 1.0) * 4.0)


## 原版火把：尖端持续冒火苗和烟（火苗原地缩小，烟 generic_7→0 向上飘散）。
func _update_flame_particles(delta:float) -> void:
	if health <= 0 or dashing or not image.visible or not is_combat_runtime_active(): return
	var fx:Node2D = PARTICLES.find_or_create(self)
	if fx == null: return
	var tip:Vector2 = tip_world_position()
	_flame_wait -= delta
	if _flame_wait <= 0.0:
		_flame_wait = _fx_rng.randf_range(0.1,0.2) * (0.75 if soul_form else 1.0)
		fx.flame(tip + Vector2(_fx_rng.randf_range(-0.8,0.8),_fx_rng.randf_range(-1.5,0.0)),soul_form,_fx_rng.randf_range(2.6,3.4))
	_smoke_wait -= delta
	if _smoke_wait <= 0.0:
		_smoke_wait = _fx_rng.randf_range(0.12,0.22)
		fx.smoke(tip + Vector2(_fx_rng.randf_range(-1.0,1.0),-3.0))


## 冲刺火焰：火把位置持续随机密集生成灵魂火苗组成火团，并按移动距离在身后留下火苗与烟。
func _update_dash_trail() -> void:
	if not dashing or health <= 0:
		_trail_from = Vector2.INF
		return
	_update_flame_form()
	if _trail_from == Vector2.INF:
		_trail_from = global_position
		return
	var fx:Node2D = PARTICLES.find_or_create(self)
	var sample:Dictionary = VFX.sample_smoke_trail(_trail_from,global_position,1.4,0.0,_trail_carry)
	_trail_carry = float(sample.distance)
	_trail_from = global_position
	if fx == null: return
	var back:Vector2 = -Vector2.from_angle(_form_heading)
	var side:Vector2 = back.orthogonal()
	var half:float = cell_size() * FLAME_FORM_CELLS * 0.4
	for point:Vector2 in sample.points:
		_trail_count += 1
		var at:Vector2 = point + side * _fx_rng.randf_range(-half,half)
		fx.moving_flame(at,true,back * _fx_rng.randf_range(8.0,26.0) + side * _fx_rng.randf_range(-6.0,6.0),_fx_rng.randf_range(0.35,0.75),_fx_rng.randf_range(3.5,6.0))
		if _trail_count % 3 == 0: fx.smoke(at + back * 4.0)


## 火团本体：每秒 DASH_BODY_RATE 个灵魂火苗随机落在火把周围的圆内（半径越小越密），
## 寿命很短并略向身后飘，连成一团跳动的火。
func _update_flame_form() -> void:
	var pos:Vector2 = global_position
	if _form_last != Vector2.INF and pos.distance_squared_to(_form_last) > 0.04:
		_form_heading = (pos - _form_last).angle()
	elif _form_last == Vector2.INF and _dash_goal.is_finite() and _dash_goal.distance_squared_to(pos) > 0.04:
		_form_heading = (_dash_goal - pos).angle()
	_form_last = pos
	var fx:Node2D = PARTICLES.find_or_create(self)
	if fx == null: return
	var radius:float = cell_size() * FLAME_FORM_CELLS * 0.5
	var back:Vector2 = -Vector2.from_angle(_form_heading)
	_body_carry += DASH_BODY_RATE * get_process_delta_time()
	while _body_carry >= 1.0:
		_body_carry -= 1.0
		var r:float = radius * pow(_fx_rng.randf(),0.8)
		var at:Vector2 = pos + Vector2.from_angle(_fx_rng.randf() * TAU) * r
		var size:float = lerpf(6.0,3.0,r / radius) * _fx_rng.randf_range(0.85,1.15)
		fx.moving_flame(at,true,back * _fx_rng.randf_range(4.0,14.0) + Vector2(_fx_rng.randf_range(-3.0,3.0),-_fx_rng.randf_range(2.0,8.0)),_fx_rng.randf_range(0.16,0.32),size)


func _draw() -> void:
	_drawn_charge = soul_charge
	_drawn_soul = soul_form
	if soul_form or health <= 0: return
	var rect:Rect2 = BAR.below_body(self,get_node_or_null("CollisionShape2D") as CollisionShape2D)
	BAR.paint(self,rect,soul_charge,0.0,SOUL_BAR_COLOR)


func visual_state() -> Dictionary:
	return {"time":clock,"charge":soul_charge,"soul":soul_form,"dash":dashing,"dash_to":_dash_goal}


func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	soul_charge = float(data.get("charge",soul_charge))
	dashing = bool(data.get("dash",dashing))
	_dash_goal = data.get("dash_to",_dash_goal)
	if bool(data.get("soul",false)) and not soul_form:
		soul_form = true
		_apply_soul_visual()


func get_debug_attack_regions() -> Array:
	var result:Array = []
	if health <= 0 or not dashing or not _dash_goal.is_finite(): return result
	result.append({"shape":"segment","start":global_position,"end":_dash_goal,"radius":dash_radius(),
		"damage":attack_damage(dash_damage_multiplier),"kind":"torch_flame_dash"})
	return result


func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_TORCH")


func Die() -> void:
	if is_multiplayer_authority(): _end_dash()
	for fire:Variant in _fires.values():
		if is_instance_valid(fire): fire.extinguish(0.4)
	super.Die()


func _exit_tree() -> void:
	_release_pass_through()
	for fire:Variant in _fires.values():
		if is_instance_valid(fire): (fire as Node).queue_free()
	_fires.clear()
	_fire_cells.clear()
	super._exit_tree()


@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	ITEM_DEATH.spawn(self)
