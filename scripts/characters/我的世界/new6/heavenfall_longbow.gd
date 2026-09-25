extends "res://scripts/characters/我的世界/new5/base.gd"
# 天堂陨落长弓（无尽贪婪 infinity_bow 贴图，9 帧星云动画原样播放）：
# 中速拉弓，箭体中等伤害并轻微追踪、可穿过1次障碍物；命中或消失时落箭雨（低伤害），
# 并沿射击方向撕开空间裂隙；完全展开后、闭合前本体受击会闪避到最近可用的成熟裂隙并反打。
const BOLT: PackedScene = preload("res://scenes/shooter/我的世界/天陨箭矢.tscn")
const COMBAT_FX = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
# Same native longbow/rift teal, pale cyan and silver palette; no new texture art.
const SHOT_RING_PALETTE:Array[Color] = [Color("14534f"),Color("83dbd6"),Color("c8c8c8")]
const FALL: PackedScene = preload("res://scenes/shooter/我的世界/天陨箭.tscn")
const RIFT: PackedScene = preload("res://scenes/shooter/我的世界/天陨裂隙.tscn")
const TRANSIT = preload("res://scripts/characters/我的世界/new6/heavenfall_transit.gd")
const ARRIVAL_RING = preload("res://scripts/characters/我的世界/new6/heavenfall_ring.gd")
const WAVE_AUDIO = preload("res://scripts/characters/我的世界/new6/heavenfall_wave_audio.gd")
const STRIP_IDLE: Texture2D = preload("res://Images/characters/我的世界/new6/av_bow_idle.png")
const STRIP_PULL0: Texture2D = preload("res://Images/characters/我的世界/new6/av_bow_pull0.png")
const STRIP_PULL1: Texture2D = preload("res://Images/characters/我的世界/new6/av_bow_pull1.png")
const STRIP_PULL2: Texture2D = preload("res://Images/characters/我的世界/new6/av_bow_pull2.png")
const FX = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")
# 无尽贪婪弓与原版弓同为斜向构图，+135° 后弓弧朝敌人（已逐像素核对箭向）。
const TEX_OFFSET: float = PI * 0.75
const STRIP_FRAMES: int = 9
# 松弦后坐与 bow.gd 完全一致：欠阻尼弹簧 exp(-RECOIL_DECAY*t)*sin(RECOIL_OMEGA*t)，
# 6Hz 振荡，约 32ms 到达最大后移，随后每半周期衰减到 30%，0.45s 内弹性归位。
const RECOIL_OMEGA: float = TAU * 6.0
const RECOIL_DECAY: float = 14.4
const RECOIL_LIFETIME: float = 0.45

@export var shoot_range: float = 300.0
@export var draw_time: float = 0.5
@export var cooldown: float = 1.65
@export var bolt_speed: float = 620.0
@export var bolt_damage_mult: float = 2.0
@export var homing_turn: float = 120.0
@export var homing_range: float = 220.0
@export var bolt_max_dist: float = 560.0
@export var rain_count: int = 7
@export var rain_radius: float = 60.0
@export var rain_damage_mult: float = 0.7
@export var rain_aoe: float = 22.0
@export var rain_delay: float = 0.38
@export var rift_length: float = 90.0 # 整簇裂纹的近似直径，不是单向射线长度。
@export var rift_lifetime: float = 6.0
@export var rift_max_active: int = 4
@export var rift_dodge_cooldown: float = 0.9
@export var rift_blast_radius: float = 38.0 # 95 的 0.8 倍
@export var rift_blast_tick_damage: float = 2.0 # 到达圆圈每一跳的固定伤害
@export var rift_blast_knockback: float = 3.0 # 每一跳的微小击退距离
@export var rift_blast_knockback_speed: float = 120.0
@export var rift_safe_margin: float = 26.0
@export var rift_branch_count_min: int = 3
@export var rift_branch_count_max: int = 5
# 箭从弓身前方生成：实机量得弓弧绕本体中心，弓头沿面向轴仅约 0.5px、侧向约 11px，
# 取 12 让箭尾贴住弓弦，既有分离感又不会飞在弓前。
@export var muzzle_offset: float = 12.0
@export var draw_move_ratio: float = 0.55
@export var recoil_shift: float = 36.0
@export var recoil_tilt: float = 0.16

var facing: Vector2 = Vector2.RIGHT
var drawing: float = 0.0
var _cool: float = 0.0
var _atlas_idle: Array[AtlasTexture] = []
var _atlas_pull: Array = []
var _rifts: Array = []
var _rift_seq: int = 0
var _rift_cool: float = 0.0
var _rift_grace: float = 0.0
var _rift_guard: int = 0
var _rift_transit: Node2D
var _transit_rift: WeakRef
var _last_transit_id: int = 0
var _transit_blast_done: bool = false
var _arrival_ring: WeakRef
# 后坐状态：强度、方向（松弦瞬间的 -facing）、倾斜方向、松弦时刻（与 _view_clock 同一时间轴）。
var _recoil_power: float = 0.0
var _recoil_dir: Vector2 = Vector2.ZERO
var _recoil_tilt_sign: float = 1.0
var _recoil_start: float = -RECOIL_LIFETIME
var _shot_seq: int = 0
var _last_shot_charge: float = 0.0
var _visual_synced: bool = false
var _rest_image_position: Vector2
var _rest_image_cached: bool = false


func _ready() -> void:
	super._ready()
	if direction.length_squared() > 0.001:
		facing = direction.normalized()
	if image is Sprite2D:
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_atlas_idle = _strip_frames(STRIP_IDLE)
	_atlas_pull = [_strip_frames(STRIP_PULL0), _strip_frames(STRIP_PULL1), _strip_frames(STRIP_PULL2)]


func _strip_frames(strip: Texture2D) -> Array[AtlasTexture]:
	var out: Array[AtlasTexture] = []
	for i in range(STRIP_FRAMES):
		var at := AtlasTexture.new()
		at.atlas = strip
		at.region = Rect2(0, i * 16, 16, 16)
		at.filter_clip = true
		out.append(at)
	return out


func step_mob(delta: float) -> void:
	_cool -= delta
	_rift_cool -= delta
	_rift_grace = maxf(_rift_grace - delta, 0.0)
	if is_rift_transiting():
		drawing = 0.0
		return
	var want_fire: bool = false
	if is_player_controlled() and has_player_control_aim():
		facing = player_control_aim_direction(facing)
		want_fire = true
	else:
		var target: ball = U.nearest(self)
		# 索敌不受地形遮挡；实际穿墙次数仍由箭矢自己的碰撞逻辑限制。
		if target != null and global_position.distance_to(target.global_position) <= shoot_range + U.radius(target):
			facing = (target.global_position - global_position).normalized()
			want_fire = true
	if want_fire and can_act() and _cool <= 0.0:
		drawing += delta
		if drawing >= draw_time:
			drawing = 0.0
			_cool = cooldown
			_fire()
	else:
		drawing = maxf(0.0, drawing - delta * 4.0)


@rpc("authority", "call_remote", "reliable")
func _spawn_shot_ring(point:Vector2,shot_direction:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null: return
	# Freeze the authoritative launch point, not the moving/recoiling bow sprite.
	var ring:Node2D = COMBAT_FX.expanding_ring(world,point,8.0,
		{"name":"HeavenfallShotRing","palette":SHOT_RING_PALETTE,"end_scale":3.0,"lifetime":0.38,
		 "direction":shot_direction,"depth_ratio":0.35})
	ring.add_to_group("HeavenfallShotRing")



func _fire() -> void:
	if not is_multiplayer_authority(): return
	var world: Node = get_tree().current_scene
	if world == null:
		return
	var bolt: Area2D = BOLT.instantiate() as Area2D
	world.add_child(bolt, true)
	bolt.global_position = global_position + facing * muzzle_offset
	_spawn_shot_ring(bolt.global_position,facing)
	if multiplayer.has_multiplayer_peer(): _spawn_shot_ring.rpc(bolt.global_position,facing)
	# 旧箭矢接口保留参数位置，但箭体不再击退；瞬移到达的冲击仍由到达圆圈单独结算。
	bolt.call("configure", self, Team, facing, bolt_speed, attack_damage(bolt_damage_mult), 0.0, homing_turn, homing_range, bolt_max_dist, rain_count, rain_radius, attack_damage(rain_damage_mult), rain_aoe, rain_delay)
	# 出箭点取自静止弓身；箭离弦后弓才被震回（本弓只在拉满后松弦，强度恒为 1）。
	_shot_seq += 1
	_start_recoil(1.0, facing, clock)
	play_sound("entity.heavenfall.shoot", -4.0)
	FX.burst(world, "magic", global_position + facing * (muzzle_offset + 4.0), facing, 5, 80.0, 0.35, 7.0)


func _start_recoil(power: float, aim: Vector2, at: float) -> void:
	_recoil_power = clampf(power, 0.0, 1.0)
	_recoil_dir = -aim.normalized() if aim.length_squared() > 0.000001 else Vector2.ZERO
	# 交替向两侧后仰，连续射击时不会永远往同一边歪。
	_recoil_tilt_sign = -_recoil_tilt_sign
	_recoil_start = at
	_last_shot_charge = _recoil_power


# 归一化后坐曲线：0 → 1（最大后移）→ 反向小幅前冲 → 衰减归零。与 bow.gd 相同。
static func recoil_curve(age: float) -> float:
	if age <= 0.0 or age >= RECOIL_LIFETIME:
		return 0.0
	var peak_age: float = atan(RECOIL_OMEGA / RECOIL_DECAY) / RECOIL_OMEGA
	var peak: float = exp(-RECOIL_DECAY * peak_age) * sin(RECOIL_OMEGA * peak_age)
	return exp(-RECOIL_DECAY * age) * sin(RECOIL_OMEGA * age) / peak


# 当前后坐波形（已乘强度）；不在后坐中为 0。
# 时间轴用 _view_clock：暂停时冻结，客户端与权威端节奏一致。
func recoil_wave() -> float:
	if _recoil_power <= 0.0 or health <= 0:
		return 0.0
	return _recoil_power * recoil_curve(_view_clock - _recoil_start)


func spawn_heaven_rain(points: PackedVector2Array, damage: float, aoe: float, delay: float) -> void:
	_spawn_rain(points, damage, aoe, delay)
	if multiplayer.has_multiplayer_peer():
		_spawn_rain_rpc.rpc(points, damage, aoe, delay)


func _spawn_rain(points: PackedVector2Array, damage: float, aoe: float, delay: float) -> void:
	var world: Node = get_tree().current_scene
	if world == null:
		return
	for i in range(points.size()):
		var arrow: Area2D = FALL.instantiate() as Area2D
		world.add_child(arrow, true)
		# 传索引：箭雨在一段时间内陆续落地，而不是一齐砸下。
		arrow.call("configure", self, Team, points[i], delay, damage, aoe, i, points.size())


@rpc("authority", "call_remote", "reliable")
func _spawn_rain_rpc(points: PackedVector2Array, damage: float, aoe: float, delay: float) -> void:
	if health <= 0:
		return
	_spawn_rain(points, damage, aoe, delay)


func spawn_heaven_rift(origin: Vector2, direction: Vector2) -> void:
	if not is_multiplayer_authority() or health <= 0:
		return
	var pts: PackedVector2Array = _build_rift_path(origin, direction)
	if pts.size() < 2:
		return
	var branches: Array = _grow_rift_branches(pts)
	var anchor: Vector2 = _snap_rift_anchor(pts)
	_rift_seq += 1
	_spawn_rift(_rift_seq, pts, branches, anchor, rift_lifetime)
	if multiplayer.has_multiplayer_peer():
		_spawn_rift_rpc.rpc(_rift_seq, pts, branches, anchor, rift_lifetime)


func _spawn_rift(id: int, pts: PackedVector2Array, branches: Array, anchor: Vector2, lifetime: float) -> void:
	var world: Node = get_tree().current_scene
	if world == null:
		return
	var rift: Node2D = RIFT.instantiate() as Node2D
	world.add_child(rift, true)
	rift.call("configure", self, id, pts, branches, anchor, lifetime)
	# Each peer plays once at the actual opening, not at the distant bow.
	AUDIO.play(rift, "entity.heavenfall.rift", pts[0], -3.0, false, false, true)
	_rifts.append(weakref(rift))
	_prune_rifts()
	while _live_rift_count() > maxi(rift_max_active, 1):
		var oldest: Variant = _oldest_rift()
		if oldest == null:
			break
		oldest.call("close_quietly")
		_prune_rifts()


@rpc("authority", "call_remote", "reliable")
func _spawn_rift_rpc(id: int, pts: PackedVector2Array, branches: Array, anchor: Vector2, lifetime: float) -> void:
	if health <= 0:
		return
	_spawn_rift(id, pts, branches, anchor, lifetime)


func _consume_rift(rift: Node) -> void:
	var id: int = int(rift.get("rift_id"))
	rift.call("consume")
	if id > 0 and multiplayer.has_multiplayer_peer():
		_consume_rift_rpc.rpc(id)


@rpc("authority", "call_remote", "reliable")
func _consume_rift_rpc(id: int) -> void:
	for w in _rifts:
		var r: Variant = w.get_ref() if w != null else null
		if is_instance_valid(r) and int(r.get("rift_id")) == id and r.has_method("consume"):
			r.call("consume")
	_prune_rifts()


func _heaven_arena_rect() -> Rect2:
	var world: Node = get_tree().current_scene
	if world != null and world.has_method("return_map_world_rect"):
		var maps: Variant = world.get("map_group")
		var key: Variant = world.get("now_choose_map")
		if maps is Dictionary and maps.has(key):
			return world.call("return_map_world_rect", maps[key])
	return Rect2(global_position - Vector2(240, 180), Vector2(480, 360))


func _heaven_circle_clear(point: Vector2, radius: float) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _heaven_body_clear(point: Vector2) -> bool:
	if collision_shape_2d == null or collision_shape_2d.shape == null:
		return _heaven_circle_clear(point, 18.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape_2d.shape
	query.transform = collision_shape_2d.global_transform
	query.transform.origin += point - global_position
	query.collision_mask = 3
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _build_rift_path(origin: Vector2, direction: Vector2) -> PackedVector2Array:
	# 视觉裂纹完全独立于地形：不推离命中点、不碰撞、不反射、不裁到地图边界。
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	dir = dir.rotated(rng.randf_range(-0.24, 0.24))
	return _grow_crack_limb(origin, dir, maxf(rift_length, 12.0) * 0.5)


func _grow_rift_branches(pts: PackedVector2Array) -> Array:
	var out: Array = []
	if pts.size() < 2:
		return out
	var center: Vector2 = pts[0]
	var base_angle: float = (pts[pts.size() - 1] - center).angle()
	var lo: int = clampi(mini(rift_branch_count_min, rift_branch_count_max), 3, 5)
	var hi: int = clampi(maxi(rift_branch_count_min, rift_branch_count_max), lo, 5)
	var count: int = rng.randi_range(lo, hi) + 1
	var rays: Array = [pts]
	for i in range(1, count):
		var angle: float = base_angle + TAU * float(i) / float(count) + rng.randf_range(-0.22, 0.22)
		var length: float = maxf(rift_length, 12.0) * 0.5 * rng.randf_range(0.60, 0.96)
		var ray: PackedVector2Array = _grow_crack_limb(center, Vector2.RIGHT.rotated(angle), length)
		out.append(ray)
		rays.append(ray)
	# 少量二级裂纹从主裂纹分出，既不均匀排布，也不生成装饰性的圆环/星形图案。
	for ray: PackedVector2Array in rays:
		if out.size() >= 8 or rng.randf() > 0.52:
			continue
		var sample: Dictionary = _rift_path_sample(ray, rng.randf_range(0.35, 0.65))
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var dir: Vector2 = (sample["tangent"] as Vector2).rotated(side * rng.randf_range(0.52, 1.0))
		out.append(_grow_crack_limb(sample["point"], dir, maxf(rift_length, 12.0) * rng.randf_range(0.10, 0.19)))
	return out


func _grow_crack_limb(start: Vector2, dir: Vector2, length: float, _arena: Rect2 = Rect2()) -> PackedVector2Array:
	# 分段断裂：长短不一的直段与偏折，避免笔直三角带和规则锯齿。
	var forward: Vector2 = dir.normalized() if dir.length_squared() > 0.000001 else Vector2.RIGHT
	var normal := Vector2(-forward.y, forward.x)
	var count: int = clampi(int(ceil(length / 7.0)), 3, 9)
	var weights := PackedFloat32Array()
	var total: float = 0.0
	for i in range(count):
		var weight: float = rng.randf_range(0.60, 1.40)
		weights.append(weight)
		total += weight
	var points := PackedVector2Array([start])
	var travelled: float = 0.0
	var lateral: float = 0.0
	for i in range(count):
		travelled += weights[i]
		var t: float = travelled / total
		lateral = lerpf(lateral, rng.randf_range(-0.14, 0.14) * length, 0.72)
		points.append(start + forward * length * t + normal * lateral)
	return points


func _rift_path_sample(pts: PackedVector2Array, t: float) -> Dictionary:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var want: float = clampf(t, 0.0, 1.0) * total
	for i in range(pts.size() - 1):
		var seg: float = pts[i].distance_to(pts[i + 1])
		if want <= seg or i == pts.size() - 2:
			var tangent: Vector2 = (pts[i + 1] - pts[i]).normalized() if seg > 0.001 else Vector2.RIGHT
			return {"point": pts[i].lerp(pts[i + 1], clampf(want / maxf(seg, 0.001), 0.0, 1.0)), "tangent": tangent}
		want -= seg
	return {"point": pts[pts.size() - 1], "tangent": Vector2.RIGHT}


func _rift_anchor_mid(pts: PackedVector2Array) -> Vector2:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	if total < 0.001:
		return pts[0]
	var want: float = total * 0.5
	for i in range(pts.size() - 1):
		var seg: float = pts[i].distance_to(pts[i + 1])
		if want <= seg:
			return pts[i].lerp(pts[i + 1], want / maxf(seg, 0.001))
		want -= seg
	return pts[pts.size() - 1]


func _snap_rift_anchor(pts: PackedVector2Array) -> Vector2:
	var arena: Rect2 = _heaven_arena_rect().grow(-maxf(rift_safe_margin, 4.0))
	var mid: Vector2 = pts[0] # 中央连接开口位于实际命中点；安全落点仍独立检查。
	var candidates := PackedVector2Array([mid])
	for ring in range(1, 6):
		var radius: float = float(ring) * 8.0
		for k in range(8):
			candidates.append(mid + Vector2.RIGHT.rotated(TAU * float(k) / 8.0 + float(ring) * 0.4) * radius)
	for c in candidates:
		var p := Vector2(clampf(c.x, arena.position.x + 0.01, arena.end.x - 0.01), clampf(c.y, arena.position.y + 0.01, arena.end.y - 0.01))
		if _heaven_body_clear(p):
			return p
	return mid


func _prune_rifts() -> void:
	for i in range(_rifts.size() - 1, -1, -1):
		var w: Variant = _rifts[i]
		var r: Variant = w.get_ref() if w != null else null
		if not is_instance_valid(r) or (not bool(r.call("is_open")) and not bool(r.call("is_reserved"))):
			_rifts.remove_at(i)


func _live_rift_count() -> int:
	var n: int = 0
	for w in _rifts:
		var r: Variant = w.get_ref() if w != null else null
		if is_instance_valid(r) and bool(r.call("is_open")):
			n += 1
	return n


func _oldest_rift() -> Variant:
	for w in _rifts:
		var r: Variant = w.get_ref() if w != null else null
		if is_instance_valid(r) and bool(r.call("is_open")):
			return r
	return null


func _can_rift_dodge() -> bool:
	return is_multiplayer_authority() and health > 0 and is_combat_runtime_active()


func _try_rift_dodge() -> bool:
	if _rift_guard > 0:
		return false
	if is_rift_transiting():
		return true
	if _rift_grace > 0.0:
		return true
	if not _can_rift_dodge() or _rift_cool > 0.0:
		return false
	_prune_rifts()
	var arena: Rect2 = _heaven_arena_rect().grow(-maxf(rift_safe_margin, 4.0))
	var best: Variant = null
	var best_d: float = INF
	for w in _rifts:
		var r: Variant = w.get_ref() if w != null else null
		if not is_instance_valid(r) or not bool(r.call("can_transit")):
			continue
		var dest: Vector2 = r.get("landing")
		if not arena.has_point(dest) or not _heaven_body_clear(dest):
			continue
		var d: float = global_position.distance_to(dest)
		if d < best_d:
			best_d = d
			best = r
	if best == null:
		return false
	var target: Vector2 = best.get("landing")
	var origin: Vector2 = global_position
	_rift_cool = maxf(rift_dodge_cooldown, 0.1)
	_rift_grace = 0.12
	var id: int = int(best.get("rift_id"))
	var points: PackedVector2Array = best.get("_points")
	var opening: Vector2 = points[0] if not points.is_empty() else target
	if multiplayer.has_multiplayer_peer():
		_apply_rift_dodge.rpc(origin, target, id, opening)
	else:
		_apply_rift_dodge(origin, target, id, opening)
	return true


func is_rift_transiting() -> bool:
	return is_instance_valid(_rift_transit) and not _rift_transit.is_queued_for_deletion()


@rpc("authority", "call_local", "reliable")
func _apply_rift_dodge(origin: Vector2, target: Vector2, id: int = 0, opening: Vector2 = Vector2.INF) -> void:
	if health <= 0.0 or is_rift_transiting() or (id > 0 and id == _last_transit_id):
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return
	var chosen_rift: Variant = null
	for w in _rifts:
		var candidate: Variant = w.get_ref() if w != null else null
		if is_instance_valid(candidate) and int(candidate.get("rift_id")) == id:
			chosen_rift = candidate
			break
	if is_multiplayer_authority():
		# Revalidate at commitment, before changing invulnerability/action state.
		if chosen_rift == null or not bool(chosen_rift.call("reserve_transit")):
			return
	elif chosen_rift != null:
		# Packet authority already confirmed maturity; don't veto on local age.
		if not bool(chosen_rift.call("reserve_transit", true)): chosen_rift = null
	_last_transit_id = id
	_transit_blast_done = false
	_arrival_ring = null
	drawing = 0.0
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_transit_rift = weakref(chosen_rift) if chosen_rift != null else null
	_rift_transit = TRANSIT.new()
	world.add_child(_rift_transit)
	_rift_transit.call("setup", self, origin, target, target if not opening.is_finite() else opening)
	_rift_transit.connect("crossed_screen", _land_rift_transit)
	_rift_transit.connect("recovered", _finish_rift_transit)
	# One local cue per peer/action; keep it at departure, not the later landing.
	AUDIO.play(_rift_transit, "entity.heavenfall.teleport", origin, -3.0, false, true, true)


func _process(delta: float) -> void:
	if health <= 0.0:
		_cancel_rift_transit()
	super._process(delta)
	_advance_rift_transit(delta)


func _advance_rift_transit(delta: float) -> void:
	if health <= 0.0:
		_cancel_rift_transit()
		return
	if is_rift_transiting() and is_combat_runtime_active():
		_rift_transit.call("advance", delta)


func _land_rift_transit() -> void:
	if not is_rift_transiting():
		return
	var target: Vector2 = _rift_transit.get("target")
	# Revalidate after the launch: a moving enemy or newly-created wall may have
	# occupied the old safe anchor. Visual emergence still begins at the mouth.
	if is_multiplayer_authority() and not _heaven_body_clear(target):
		var points := PackedVector2Array([_rift_transit.get("opening")])
		target = _snap_rift_anchor(points)
		if not _heaven_arena_rect().grow(-maxf(rift_safe_margin, 4.0)).has_point(target) or not _heaven_body_clear(target):
			if multiplayer.has_multiplayer_peer():
				_retarget_rift_transit.rpc(_last_transit_id, Vector2.INF)
			else:
				_retarget_rift_transit(_last_transit_id, Vector2.INF)
			return # Abort without an arrival attack if every landing became blocked.
		if multiplayer.has_multiplayer_peer():
			_retarget_rift_transit.rpc(_last_transit_id, target)
		else:
			_retarget_rift_transit(_last_transit_id, target)
	global_position = target
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	reset_physics_interpolation()
	_emit_rift_arrival()


@rpc("authority", "call_local", "reliable")
func _retarget_rift_transit(id: int, target: Vector2) -> void:
	if not is_rift_transiting() or id != _last_transit_id:
		return
	if not target.is_finite():
		_cancel_rift_transit()
		return
	_rift_transit.set("target", target)
	var ring: Variant = _arrival_ring.get_ref() if _arrival_ring != null else null
	if is_instance_valid(ring): ring.global_position = target
	if bool(_rift_transit.get("crossed")):
		global_position = target
		reset_physics_interpolation()


func _emit_rift_arrival() -> void:
	# Release on the SAME frame as the teleport, not after emergence/recovery.
	if _transit_blast_done or not is_rift_transiting() or health <= 0.0:
		return
	_transit_blast_done = true
	var world: Node = get_tree().current_scene
	if world == null: return
	var rift: Variant = _transit_rift.get_ref() if _transit_rift != null else null
	var cosmic_age: float = float(rift.get("_age")) if is_instance_valid(rift) else _view_clock
	var target: Vector2 = _rift_transit.get("target")
	var ring: Node2D = ARRIVAL_RING.new()
	world.add_child(ring)
	# 圆圈自己在落位当帧发出第一跳，之后每隔 tick_interval 一跳；
	# 每个 peer 都重放圆圈，但只有权威端在 _on_arrival_tick 里真正结算。
	ring.connect("tick", _on_arrival_tick)
	ring.call("configure", target, maxf(rift_blast_radius, 12.0), _rift_transit.get("opening"), cosmic_age, _last_transit_id)
	_arrival_ring = weakref(ring)
	# One energy-release cue on actual arrival, not one explosion per damage tick.
	WAVE_AUDIO.play(ring, target)


func _on_arrival_tick(point: Vector2, radius: float, _index: int) -> void:
	# 每一跳：固定伤害 + 微小向外击退，持续把敌人往圈外推。
	if not is_multiplayer_authority() or health <= 0.0 or not is_combat_runtime_active():
		return
	_rift_guard += 1
	_rift_blast_damage(point, radius)
	_rift_guard -= 1


func _finish_rift_transit() -> void:
	if not is_rift_transiting():
		return
	var transit: Node2D = _rift_transit
	var rift: Variant = _transit_rift.get_ref() if _transit_rift != null else null
	transit.call("restore")
	_rift_transit = null
	transit.queue_free()
	_rift_grace = maxf(_rift_grace, 0.08)
	# The wave is already expanding; let the body finish exiting before closing.
	if is_instance_valid(rift): rift.call("consume")
	_transit_rift = null
	_prune_rifts()


func _cancel_rift_transit() -> void:
	if is_instance_valid(_rift_transit):
		_rift_transit.call("restore")
		_rift_transit.queue_free()
	_rift_transit = null
	var rift: Variant = _transit_rift.get_ref() if _transit_rift != null else null
	if is_instance_valid(rift): rift.call("close_quietly")
	_transit_rift = null


func Die() -> void:
	_cancel_rift_transit()
	super.Die()


func _exit_tree() -> void:
	_cancel_rift_transit()
	super._exit_tree()


func _rift_blast_damage(center: Vector2, radius: float = -1.0) -> void:
	# 这里只结算“这一跳”；圆圈按 tick_interval 反复调用，持续伤害＋持续微小击退。
	var reach: float = maxf(rift_blast_radius, 0.0) if radius < 0.0 else maxf(radius, 0.0)
	var dmg: float = maxf(rift_blast_tick_damage, 0.0)
	for other: Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self, other):
			continue
		var victim: ball = other as ball
		if victim.global_position.distance_to(center) > reach + U.radius(victim):
			continue
		if U.damage(self, victim, dmg, center):
			var push: Vector2 = victim.global_position - center
			if push.length_squared() < 0.001:
				push = Vector2.RIGHT
			victim.apply_knockback(push.normalized(), rift_blast_knockback, rift_blast_knockback_speed, 0, 0, {"source": self, "stop_on_character": true})
			FX.hit_sfx(self, victim.global_position, dmg)


func can_receive_hit_contact(_incoming_hit: hitbox, _contact_hurtbox: hurtbox) -> bool:
	return not _try_rift_dodge()


func can_receive_hit_from(_incoming_hit: hitbox) -> bool:
	return not _try_rift_dodge()


func on_incoming_hit_rejected(_incoming_hit: hitbox) -> void:
	pass


func should_destroy_projectile_on_rejected_hit(_incoming_hit: hitbox) -> bool:
	return false


func try_full_projectile_dodge(_projectile: Node = null) -> bool:
	return _try_rift_dodge()


func receive_positional_damage(damage: float, impact_position: Vector2, ignore_block: bool = false, source: Node = null) -> bool:
	if damage > 0.0 and _try_rift_dodge():
		return false
	return super.receive_positional_damage(damage, impact_position, ignore_block, source)


func receive_spatial_damage(damage: float, damage_space: Variant, ignore_block: bool = false, raw_health: bool = false) -> bool:
	if not raw_health and damage > 0.0 and _try_rift_dodge():
		return false
	return super.receive_spatial_damage(damage, damage_space, ignore_block, raw_health)


func take_damage(damage: float, ignore_block: bool = false) -> void:
	if damage > 0.0 and _try_rift_dodge():
		return
	super.take_damage(damage, ignore_block)


func move(speed_value: float, delta: float) -> void:
	if is_rift_transiting():
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	if drawing > 0.0:
		super.move(speed_value * draw_move_ratio, delta)
	else:
		super.move(speed_value, delta)


func stand(delta: float) -> void:
	if is_rift_transiting():
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.stand(delta)


func visual_mob() -> void:
	if image == null or not is_instance_valid(image):
		return
	if not _rest_image_cached:
		_rest_image_position = image.position
		_rest_image_cached = true
	var ratio: float = clampf(drawing / maxf(draw_time, 0.01), 0.0, 1.0)
	var anim_set: Array = _atlas_idle
	var fps: float = 10.0
	if ratio > 0.05:
		fps = 12.0
		if ratio < 0.4:
			anim_set = _atlas_pull[0]
		elif ratio < 0.8:
			anim_set = _atlas_pull[1]
		else:
			anim_set = _atlas_pull[2]
	if anim_set.is_empty():
		return
	image.texture = anim_set[int(_view_clock * fps) % anim_set.size()]
	set_character_visual_flip_h(false)
	var angle: float = facing.angle() + TEX_OFFSET
	var pose: Vector2 = _rest_image_position
	# 松弦后坐：与 bow.gd 相同的欠阻尼弹簧，只动贴图的旋转与位置。
	var wave: float = recoil_wave()
	if wave != 0.0:
		angle += _recoil_tilt_sign * recoil_tilt * wave
		pose += _recoil_dir * (recoil_shift * wave)
	image.rotation = angle
	if not image.position.is_equal_approx(pose):
		image.position = pose


func visual_state() -> Dictionary:
	return {"time": clock, "facing": facing, "drawing": drawing, "shot": _shot_seq, "kick": _last_shot_charge}


func accept_visual(data: Dictionary) -> void:
	super.accept_visual(data)
	facing = data.get("facing", facing)
	drawing = float(data.get("drawing", 0.0))
	var shot: int = int(data.get("shot", _shot_seq))
	if shot != _shot_seq:
		# 刚加入的客户端不补放历史上的后坐；之后每次新松弦从收到的这一刻重放一次。
		if _visual_synced:
			_start_recoil(float(data.get("kick", 1.0)), facing, _view_clock)
		_shot_seq = shot
	_visual_synced = true
