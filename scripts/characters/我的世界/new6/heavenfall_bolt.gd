extends Area2D
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")
# 天堂箭矢：普通箭外观，飞行中轻微追踪；
# 第一次撞到障碍物不再反弹，而是穿过去一次：穿越途中按真实路径边穿边留下快速闭合的
# 空间裂隙（先开的先闭合）；若穿过的是地图外墙，箭在离开屏幕时直接消失。
# 地图内部的空洞/隔墙同样由安全墙围成：沿直线还能回到地面时，整段空洞算作这一次穿透，
# 回到地面后照常飞行、追踪和命中；前方射程内再也没有地面才是真正的外墙。
# 命中人物、或被第二个障碍物拦下时，仍在终点落下一轮箭雨并沿射击方向撕开空间裂隙。
const TEX: Texture2D = preload("res://Images/characters/我的世界/new6/天陨箭_纯白.png") # 普通箭剪影，纯白
const GLOW_TEX: Texture2D = preload("res://Images/characters/我的世界/new6/天陨箭_光晕.png") # 身后同变换的加性白光晕
const FALL: PackedScene = preload("res://scenes/shooter/我的世界/天陨箭.tscn")
const TEAR: GDScript = preload("res://scripts/characters/我的世界/new6/heavenfall_pierce_rift.gd")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const HEAVEN_COLLISION = preload("res://scripts/characters/我的世界/new6/heavenfall_collision.gd")
const FX = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")
# 与普通骷髅箭完全一致的外观参数（1024 贴图缩到约 16 世界像素，构图斜 45°）。
const SPRITE_SCALE: float = 0.016
const SPRITE_TILT: float = PI * 0.25
const BASE_Z_INDEX: int = 8
const REENTRY_CLEARANCE: float = 1.0
const MAP_EXIT_Z_INDEX: int = 91 # 仅出地图的箭在遮罩 z=90 之后、血条/边框之前绘制。

var _src_ref: WeakRef
var _team: String = ""
var _dir: Vector2 = Vector2.RIGHT
var _speed: float = 620.0
var _damage: float = 10.0
var _homing_turn: float = 120.0
var _homing_range: float = 220.0
var _max_dist: float = 560.0
var _travelled: float = 0.0
var _rain_count: int = 7
var _rain_radius: float = 60.0
var _rain_damage: float = 4.0
var _rain_aoe: float = 22.0
var _rain_delay: float = 0.38
var _dead: bool = false
var _interaction_stopped: bool = false
var _pierce_used: bool = false
var _pierce_active: bool = false
var _pierce_rid: RID = RID()
var _pierce_body: Object = null
var _pierce_last_point: Vector2 = Vector2.ZERO
var _pierce_reentry: Vector2 = Vector2.INF # 穿地图内部空洞时重新回到地面的点
var _tear_ref: WeakRef
var _leave_offscreen: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("BattleTransient")
	z_index = BASE_Z_INDEX
	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = GLOW_TEX
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	glow.rotation = SPRITE_TILT
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	add_child(glow)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = TEX
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.rotation = SPRITE_TILT
	add_child(sprite)
	_rng.randomize()


# Keep the old positional argument for test fixtures; bolt hits never cause knockback.
func configure(source: ball, team: String, direction: Vector2, speed: float, damage: float, _unused_knockback: float, homing_turn: float, homing_range: float, max_dist: float, rain_count: int, rain_radius: float, rain_damage: float, rain_aoe: float, rain_delay: float) -> void:
	_src_ref = weakref(source) if source != null else null
	_team = team
	_dir = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_speed = maxf(speed, 1.0)
	_damage = maxf(damage, 0.0)
	_homing_turn = maxf(homing_turn, 0.0)
	_homing_range = maxf(homing_range, 0.0)
	_max_dist = maxf(max_dist, 10.0)
	_rain_count = maxi(rain_count, 1)
	_rain_radius = maxf(rain_radius, 4.0)
	_rain_damage = maxf(rain_damage, 0.0)
	_rain_aoe = maxf(rain_aoe, 4.0)
	_rain_delay = maxf(rain_delay, 0.05)
	rotation = _dir.angle()


func has_pierced() -> bool:
	return _pierce_used


func is_inside_obstacle() -> bool:
	return _pierce_active and _inside_pierced_body()


func is_leaving_screen() -> bool:
	return _leave_offscreen


func _physics_process(delta: float) -> void:
	if _dead or Game.now_stop_state or get_tree().paused:
		return
	if not is_multiplayer_authority():
		return
	_interaction_stopped = false
	var src: ball = _src_ref.get_ref() if _src_ref != null else null
	var step: float = _speed * maxf(delta, 0.0)
	if _leave_offscreen:
		_advance_map_exit(step)
		return
	# 地图内部空洞：沿直线整段穿过（途中不转向、不命中），回到地面后本帧剩余距离照常飞行。
	if _pierce_active and _pierce_reentry.is_finite():
		var remaining: float = maxf((_pierce_reentry - global_position).dot(_dir), 0.0)
		if step < remaining:
			rotation = _dir.angle()
			global_position += _dir * step
			_travelled += step
			_track_pierce(global_position)
			return
		global_position = _pierce_reentry
		_travelled += remaining
		step -= remaining
		_finish_pierce()
		z_index = BASE_Z_INDEX
	# 正在穿墙时不再转向：路径就是裂隙的形状。
	if not _pierce_active and is_instance_valid(src) and _homing_range > 0.0 and _homing_turn > 0.0:
		var tgt: ball = _homing_target(src)
		if tgt != null:
			var want: Vector2 = (ball.body_point(tgt,global_position) - global_position).normalized()
			_dir = Vector2.RIGHT.rotated(rotate_toward(_dir.angle(), want.angle(), deg_to_rad(_homing_turn) * maxf(delta, 0.0)))
	rotation = _dir.angle()
	var start: Vector2 = global_position
	var finish: Vector2 = start + _dir * step
	if get_tree().has_group("MinecraftWoolSheep") and load("res://scripts/characters/我的世界/new6/wool_projectile.gd").sweep(self,start,finish): return
	var hit: Dictionary = HEAVEN_COLLISION.projectile(self, src, start, finish, _pierce_exclusions())
	var contacted: ball = hit.get("victim") as ball
	if is_instance_valid(src) and is_instance_valid(contacted):
		global_position = hit.get("position", finish)
		_travelled += (global_position - start).length()
		if not PROJECTILE_API.defense(self,contacted,global_position).is_empty(): return
		_hit_character(src, contacted)
		_expire()
		return
	# Only use the legacy allowance when the physical sweep found no blocker.
	if hit.is_empty() and is_instance_valid(src) and _scan_hit(src, start, finish):
		global_position = finish
		_travelled += step
		_expire()
		return
	if _interaction_stopped: return
	if _pierce_active:
		# 已经钻出障碍物就收口；裂隙只覆盖真正穿过的那段路径。
		if not _inside_pierced_body():
			_finish_pierce()
	elif not hit.is_empty():
		if _pierce_used:
			# 只穿一次：第二个障碍物照旧拦下箭矢。
			global_position = hit.get("position", finish)
			_travelled += (global_position - start).length()
			_expire()
			return
		else:
			_begin_pierce(hit)
	global_position = finish
	_travelled += (finish - start).length()
	if _pierce_active:
		if _inside_pierced_body():
			_track_pierce(finish)
		else:
			_finish_pierce()
	if _leave_offscreen:
		if _offscreen():
			_vanish()
		return
	if _travelled >= _max_dist:
		_expire()


func _advance_map_exit(distance: float) -> void:
	# 出墙后只沿原方向飞离屏幕：不追踪、不命中地图外对象，也不再按射程提前终结。
	rotation = _dir.angle()
	global_position += _dir * distance
	_travelled += distance
	if _pierce_active:
		if _inside_pierced_body():
			_track_pierce(global_position)
		else:
			_finish_pierce()
	if _offscreen():
		_vanish()


func _pierce_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if _pierce_active and _pierce_rid.is_valid():
		out.append(_pierce_rid)
	return out


func _inside_pierced_body() -> bool:
	# 正在穿的那个障碍物已经从弹道里排除，所以要另外判断箭是不是还在它体内。
	if not _pierce_rid.is_valid():
		return false
	if not is_instance_valid(_pierce_body):
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	for found: Dictionary in space.intersect_point(query, 64):
		if found.get("rid", RID()) == _pierce_rid:
			return true
	return false


func _offscreen() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return true
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		return true
	# 与 get_visible_rect 同为逻辑视口坐标；包含相机、父级、旋转及缩放。
	# 必须整个箭身离屏，不能只用中心点或固定像素余量判断。
	var screen_bounds: Rect2 = sprite.get_global_transform_with_canvas() * sprite.get_rect()
	return not viewport.get_visible_rect().intersects(screen_bounds, true)


func _is_boundary(hit: Dictionary) -> bool:
	var world: Node = get_tree().current_scene
	if world == null or not world.has_method("map_island_rects"):
		return false
	return U.boundary_hit(self, hit)


func _begin_pierce(hit: Dictionary) -> void:
	_pierce_used = true
	_pierce_active = true
	_pierce_rid = hit.get("rid", RID())
	_pierce_body = hit.get("collider")
	var entry: Vector2 = hit.get("position", global_position)
	# 地图安全墙既围外圈也围内部空洞：先沿直线找回到地面的点，找得到就是内部空洞；
	# 找不到才是穿过地图外墙，箭不会留在世界里，离开屏幕就消失。
	var boundary: bool = _is_boundary(hit)
	_pierce_reentry = _ground_reentry(entry) if boundary else Vector2.INF
	_leave_offscreen = boundary and not _pierce_reentry.is_finite()
	if boundary:
		z_index = MAP_EXIT_Z_INDEX
	_pierce_last_point = entry
	var entry_delay: float = global_position.distance_to(entry) / _speed
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_parent()
	if world == null:
		return
	var tear: Node2D = TEAR.new()
	tear.name = "PierceTear"
	world.add_child(tear)
	# 穿入点先开一个口，之后每一帧按实际路径往前长。
	tear.call("configure", entry, _dir, _rng.randi(), _speed, entry_delay, _pierce_body)
	_tear_ref = weakref(tear)


func _ground_reentry(entry: Vector2) -> Vector2:
	# 穿墙时不转向，路径是直线：取射程内第一块从前方进入的地面矩形。
	var world: Node = get_tree().current_scene
	if world == null or not world.has_method("current_map_island_rects"):
		return Vector2.INF
	var reach: float = maxf(_max_dist - _travelled, 0.0)
	var best: float = INF
	for rect: Rect2 in world.call("current_map_island_rects"):
		var t: float = _ray_enters_rect(entry, _dir, rect)
		if t <= reach and t < best:
			best = t
	# 多走 1px 真正站到地面上：停在远侧安全墙表面时，下一帧弹道会从墙面起算而被当成第二个障碍物。
	return entry + _dir * (best + REENTRY_CLEARANCE) if is_finite(best) else Vector2.INF


static func _ray_enters_rect(origin: Vector2, dir: Vector2, rect: Rect2) -> float:
	# 射线进入矩形的距离；刚离开的那块地面（入口在其边上）和身后的矩形都不算。
	var t_near: float = -INF
	var t_far: float = INF
	for axis: int in range(2):
		var o: float = origin[axis]
		var d: float = dir[axis]
		var lo: float = rect.position[axis]
		var hi: float = rect.end[axis]
		if absf(d) < 0.000001:
			if o <= lo or o >= hi:
				return INF
			continue
		var t1: float = (lo - o) / d
		var t2: float = (hi - o) / d
		t_near = maxf(t_near, minf(t1, t2))
		t_far = minf(t_far, maxf(t1, t2))
	if t_near <= 0.25 or t_far <= t_near:
		return INF
	return t_near


func _track_pierce(point: Vector2) -> void:
	_pierce_last_point = point
	var tear: Node2D = _tear_ref.get_ref() if _tear_ref != null else null
	if is_instance_valid(tear):
		tear.call("add_sample", point, _dir)


func _finish_pierce() -> void:
	if not _pierce_active:
		return
	_pierce_active = false
	var tear: Node2D = _tear_ref.get_ref() if _tear_ref != null else null
	if not is_instance_valid(tear):
		return
	# The arrow may be many pixels beyond a thin wall in this physics step.
	# Finish on the actual back face, never on the remaining frame endpoint;
	# also include that face when earlier frames already supplied many samples.
	# 墙内消失（出屏）时 _pierce_exit_point 会沿飞行方向补到真实穿出面。
	var endpoint: Vector2 = _pierce_exit_point()
	_pierce_reentry = Vector2.INF
	tear.call("add_sample", endpoint, _dir)
	tear.call("finish")


func _pierce_exit_point() -> Vector2:
	if _pierce_reentry.is_finite():
		return _pierce_reentry
	if not _pierce_rid.is_valid() or not is_instance_valid(_pierce_body):
		return _pierce_last_point
	# A reverse ray finds the true exit of rectangles, circles, rotated/scaled
	# bodies and tile collision polygons alike; unrelated bodies are not exits.
	# 箭还身在障碍物里（例如整支箭刚出屏就消失）时，直接反向射线只会打到入口面，
	# 而 hit_from_inside 从体内出发又只会把命中点报在起点：改为从远处射回箭位置，
	# 命中的第一个被穿体表面就是真实穿出面，把裂隙补完整而不是断在箭消失的位置。
	var origin: Vector2 = global_position
	var target: Vector2 = _pierce_last_point
	if _inside_pierced_body():
		origin = global_position + _dir * 1024.0
		target = global_position
	if origin.distance_squared_to(target) < 0.000001:
		return _pierce_last_point
	var query := PhysicsRayQueryParameters2D.create(origin, target, 1)
	query.collide_with_areas = false
	query.hit_from_inside = true
	var excluded: Array[RID] = [get_rid()]
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for _attempt in range(64):
		query.exclude = excluded
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty(): break
		var rid: RID = hit.get("rid", RID())
		if rid == _pierce_rid:
			var point: Vector2 = hit.get("position", _pierce_last_point)
			# 从表面出发的边界情况不能让裂隙反向折回。
			if (point - _pierce_last_point).dot(_dir) < -0.0001: break
			return point
		if not rid.is_valid() or excluded.has(rid): break
		excluded.append(rid)
	# If terrain disappeared/moved, retain only the already traversed path.
	return _pierce_last_point


func _homing_target(src: ball) -> ball:
	var best: ball = null
	var best_ang: float = deg_to_rad(75.0)
	for other: Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(src, other) or PROJECTILE_CONTACT.ignores(other):
			continue
		var to: Vector2 = ball.body_point((other as ball),global_position) - global_position
		if to.length() > _homing_range:
			continue
		var ang: float = absf(_dir.angle_to(to))
		if ang < best_ang:
			best_ang = ang
			best = other
	return best


func _scan_hit(src: ball, a: Vector2, b: Vector2) -> bool:
	for other: Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(src, other) or PROJECTILE_CONTACT.ignores(other):
			continue
		var victim: ball = other as ball
		# Fixed body allowance: U.radius() collapses to 3px outside crowded combat.
		if U.segment_distance(ball.body_point_seg(victim,a,b), a, b) > 26.0:
			continue
		var response:String = PROJECTILE_API.defense(self,victim,a)
		if response == "dodge": continue
		if not response.is_empty():
			_interaction_stopped = true
			return false
		_hit_character(src, victim)
		return true
	return false


func _hit_character(src: ball, victim: ball) -> void:
	if not src.is_damage_output_disabled() and victim.receive_positional_damage(_damage,global_position,false,self):
		AUDIO.play(self, "entity.arrow.hit", global_position, -4.0)
		FX.hit_sfx(src, victim.global_position, _damage)


func _vanish() -> void:
	# 出屏消失：没有箭雨、没有终点裂隙，只有留在穿墙路径上的那道裂隙。
	if _dead:
		return
	_dead = true
	_finish_pierce()
	queue_free()


func _expire() -> void:
	if _dead or is_queued_for_deletion():
		return
	_dead = true
	_finish_pierce()
	var pts := PackedVector2Array()
	for i in range(_rain_count):
		var ang: float = _rng.randf() * TAU
		var rr: float = _rain_radius * sqrt(_rng.randf())
		pts.append(global_position + Vector2.RIGHT.rotated(ang) * rr)
	var src: ball = _src_ref.get_ref() if _src_ref != null else null
	if is_instance_valid(src) and src.has_method("spawn_heaven_rain"):
		src.call("spawn_heaven_rain", pts, _rain_damage, _rain_aoe, _rain_delay)
	else:
		_spawn_local(src, pts)
	if is_instance_valid(src) and src.has_method("spawn_heaven_rift"):
		src.call("spawn_heaven_rift", global_position, _dir)
	var world: Node = get_tree().current_scene
	if world != null:
		FX.burst(world, "magic", global_position, _dir, 5, 70.0, 0.35, 7.0)
	queue_free()


func _spawn_local(src: ball, pts: PackedVector2Array) -> void:
	var world: Node = get_tree().current_scene
	if world == null:
		return
	for i in range(pts.size()):
		var arrow: Area2D = FALL.instantiate() as Area2D
		world.add_child(arrow, true)
		arrow.call("configure", src, _team, pts[i], _rain_delay, _rain_damage, _rain_aoe, i, pts.size())

# Native relaunch hook: clear collision handles, keep captured damage/rain/pierce budget.
func relaunch_projectile(point:Vector2,_target:ball) -> void:
	global_position = point
	_pierce_active = false
	_pierce_rid = RID()
	_pierce_body = null
	_tear_ref = null
	_leave_offscreen = false
	_pierce_reentry = Vector2.INF
	z_index = BASE_Z_INDEX
	_travelled = 0.0
	_interaction_stopped = false
