extends ball
## 时钟：只有身体碰撞伤害，伤害随实际移动速度提高。
## 被动「时间加速」：战斗中时间流速持续提高、没有上限；非时钟角色不受影响，投射物、药水状态、
## 场上危险物与世界时间按倍率多跑物理步（time_field.gd），时钟自身同样多跑。
## 被动「时光倒流」：每隔一段时钟时间沿走过的路径快速倒回，恢复这段时间损失的生命。
## 速度足够快时留下残影；此后所有残影（含倒流残影）都有实体碰撞并造成伤害。
const FIELD = preload("res://scripts/characters/我的世界/clock/time_field.gd")
const GHOST = preload("res://scripts/characters/我的世界/clock/afterimage.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const ITEM_DEATH = preload("res://scripts/effects/我的世界/item_fragments.gd")
const SFX = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const HAT:AudioStream = preload("res://audio/characters/时钟/note_block.hat.ogg")
const WARP:Array[AudioStream] = [preload("res://audio/characters/末影人/enderman.teleport_1.ogg"),preload("res://audio/characters/末影人/enderman.teleport_2.ogg")]
const FRAME_PATH:String = "res://Images/characters/我的世界/时钟/clock_%02d.png"
const GROUP:StringName = &"MCClock"
const HURTBOX_MASK:int = 2

@export_category("时钟 - 时间加速")
@export var time_accel_per_second:float = 0.3 # 无上限
@export_category("时钟 - 时光倒流")
@export var rewind_interval:float = 4.5
@export var rewind_span:float = 1.0
@export var rewind_duration:float = 0.25
@export_category("时钟 - 速度与残影")
@export var speed_damage_min:float = 0.6
@export var speed_damage_max:float = 3.0
@export var ghost_speed_ratio:float = 3.0
@export var ghost_max_alive:int = 40
@export var ghost_spacing:float = 16.0
@export var ghost_life:float = 0.4
@export var ghost_damage_ratio:float = 0.6
@export var ghost_hit_guard:float = 0.45

static var _frames:Array[Texture2D] = []

var time_scale:float = 1.0
var rewind_count:int = 0
var _measured_speed:float = 0.0
var _last_pos:Vector2
var _real_t:float = 0.0
var _clock_t:float = 0.0
var _hist_pos:PackedVector2Array = PackedVector2Array()
var _hist_hp:PackedInt32Array = PackedInt32Array()
var _hist_t:PackedFloat64Array = PackedFloat64Array()
var _rewind_left:float = 4.5
var _rewinding:bool = false
var _rewind_path:PackedVector2Array = PackedVector2Array()
var _rewind_elapsed:float = 0.0
var _rewind_idx:int = 0
var _rewind_hp:int = 0
var _rewind_armed:bool = false
var _ghosts:Array[Dictionary] = []
var _ghost_hits:Dictionary = {}
var _ghost_travel:float = 0.0
var _next_tick_mark:float = 2.0
var _warp_quiet_until:float = 0.0
var _sync_wait:float = 0.0
var _query := PhysicsShapeQueryParameters2D.new()
var _query_shape := CircleShape2D.new()


static func frame_texture(index:int) -> Texture2D:
	if _frames.is_empty():
		for i:int in 64: _frames.append(load(FRAME_PATH % i) as Texture2D)
	return _frames[posmod(index,64)]


func get_preview_texture() -> Texture2D: return frame_texture(0)


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	_last_pos = global_position
	_rewind_left = rewind_interval
	if image is Sprite2D: (image as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_query.shape = _query_shape
	_query.collision_mask = HURTBOX_MASK
	_query.collide_with_bodies = false
	_query.collide_with_areas = true
	FIELD.ensure(self)


func clock_running() -> bool:
	return health > 0 and is_inside_tree() and is_combat_runtime_active()


func base_travel_speed() -> float:
	return maxf(Speed,1.0) * (CHARACTER_BASE_MOVE_SPEED_MULTIPLIER if Type == Ball_Type.Ball else 1.0)


func speed_ratio() -> float:
	return _measured_speed / base_travel_speed()


func current_hit_damage_multiplier() -> float:
	return clampf(speed_ratio(),speed_damage_min,speed_damage_max)


func ghosts_armed() -> bool:
	return speed_ratio() >= ghost_speed_ratio


# ---------------------------------------------------------------- 每个真实物理帧一次
func _physics_process(delta:float) -> void:
	var running:bool = clock_running()
	var step:Vector2 = global_position - _last_pos
	_last_pos = global_position
	if not running: return
	_real_t += delta
	if not _rewinding and step.length() < 240.0:
		var sample:float = step.length() / maxf(delta,0.0001)
		_measured_speed = lerpf(_measured_speed,sample,1.0 - exp(-delta / 0.12))
	if not is_multiplayer_authority(): return
	time_scale += time_accel_per_second * delta
	if time_scale >= _next_tick_mark:
		_next_tick_mark = floorf(time_scale) + 1.0
		_emit_tick(0.7 + 0.1 * time_scale)
	if not _rewinding:
		_ghost_travel += step.length()
		if ghosts_armed() and _ghost_travel >= ghost_spacing:
			# 高速时一帧走得远：沿本帧位移等距补残影，单帧最多 4 个。
			var count:int = mini(int(_ghost_travel / ghost_spacing),4)
			for i:int in count:
				_spawn_ghost(global_position - step * (float(i + 1) / float(count)),true)
			_ghost_travel = 0.0
		elif not ghosts_armed():
			_ghost_travel = minf(_ghost_travel,ghost_spacing)
	_hit_with_ghosts()
	_sync_wait -= delta
	if _sync_wait <= 0.0:
		_sync_wait = 0.25
		if multiplayer.has_multiplayer_peer(): _clock_sync.rpc(time_scale)


@rpc("authority","call_remote","unreliable_ordered")
func _clock_sync(k:float) -> void:
	time_scale = maxf(k,1.0)


# ---------------------------------------------------------------- 时钟时间（随加速多跑）
func tick_physics(state:State,delta:float) -> void:
	if clock_running() and is_multiplayer_authority():
		_clock_t += delta
		_record_history()
		if not _rewinding and not dizziness:
			_rewind_left -= delta
			if _rewind_left <= 0.0 and not _start_rewind(): _rewind_left = 0.5
	super.tick_physics(state,delta)


func move(speed_value:float,delta:float) -> void:
	if _rewinding:
		_step_rewind(delta)
		return
	super.move(speed_value,delta)


func _record_history() -> void:
	_hist_pos.append(global_position)
	_hist_hp.append(health)
	_hist_t.append(_clock_t)
	var cut:int = 0
	while cut < _hist_t.size() and _hist_t[cut] < _clock_t - rewind_span: cut += 1
	if cut > 0:
		_hist_pos = _hist_pos.slice(cut)
		_hist_hp = _hist_hp.slice(cut)
		_hist_t = _hist_t.slice(cut)


func _start_rewind() -> bool:
	if _hist_pos.size() < 8 or apply_transport_pose(): return false
	if not _spot_free(_hist_pos[0]): return false
	_rewind_path = _hist_pos.duplicate()
	_rewind_path.reverse()
	_rewind_hp = _hist_hp[0]
	_rewind_armed = ghosts_armed()
	_rewind_elapsed = 0.0
	_rewind_idx = 0
	_rewinding = true
	rewind_count += 1
	_emit_warp()
	return true


func _step_rewind(delta:float) -> void:
	velocity = Vector2.ZERO
	_rewind_elapsed += delta
	var n:int = _rewind_path.size()
	var f:float = clampf(_rewind_elapsed / maxf(rewind_duration,0.01),0.0,1.0)
	var idx:int = int(round(f * float(n - 1)))
	for i:int in range(_rewind_idx + 1,idx + 1):
		if i % 3 == 0: _spawn_ghost(_rewind_path[i - 1],_rewind_armed)
	_rewind_idx = idx
	global_position = _rewind_path[idx]
	if f >= 1.0: _finish_rewind()


func _finish_rewind() -> void:
	_rewinding = false
	if health > 0 and _rewind_hp > health: heal(float(_rewind_hp - health))
	_hist_pos.clear()
	_hist_hp.clear()
	_hist_t.clear()
	_rewind_left = rewind_interval
	_last_pos = global_position
	_ghost_travel = 0.0


func _spot_free(point:Vector2) -> bool:
	if collision_shape_2d == null or collision_shape_2d.shape == null: return true
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = collision_shape_2d.shape
	q.transform = collision_shape_2d.global_transform
	q.transform.origin += point - global_position
	q.collision_mask = collision_mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(q,16):
		var body:Variant = hit.get("collider")
		if body is ball or (body is Node and (body as Node).has_meta("clock_afterimage")): continue
		return false
	return true


# ---------------------------------------------------------------- 残影
func ghost_radius() -> float:
	var shape:Shape2D = collision_shape_2d.shape if collision_shape_2d != null else null
	var gs:Vector2 = collision_shape_2d.global_scale.abs() if collision_shape_2d != null else Vector2.ONE
	if shape is RectangleShape2D: return maxf(minf((shape as RectangleShape2D).size.x*gs.x,(shape as RectangleShape2D).size.y*gs.y)*0.5,6.0)
	if shape is CircleShape2D: return maxf((shape as CircleShape2D).radius*maxf(gs.x,gs.y),6.0)
	return maxf(get_crowd_separation_radius_world(),6.0)


func _current_frame() -> int:
	return int(get_meta("clock_frame",0))


func _spawn_ghost(point:Vector2,armed:bool) -> void:
	if _ghosts.size() >= ghost_max_alive: return
	var mult:float = current_hit_damage_multiplier()
	_ghosts.append({"pos":point,"until":_real_t + ghost_life,"armed":armed,"mult":mult})
	if multiplayer.has_multiplayer_peer(): _clock_ghost.rpc(point,_current_frame(),armed)
	_clock_ghost(point,_current_frame(),armed)


@rpc("authority","call_remote","unreliable")
func _clock_ghost(point:Vector2,frame:int,armed:bool) -> void:
	var scene:Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null or not (image is Sprite2D): return
	var g:Node2D = GHOST.new()
	scene.add_child(g)
	var solid:float = ghost_radius() * 0.9 if armed and is_multiplayer_authority() else 0.0
	g.setup(self,frame_texture(frame),image.global_scale,point,ghost_life,armed,solid,_effective_z(image) - 1)


## 残影挂在场景根下，用绝对层级；取本体实际层级减一，保证画在人物下面、地图上面。
static func _effective_z(node:Node) -> int:
	var z:int = 0
	while node is CanvasItem:
		z += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative: break
		node = node.get_parent()
	return z


func _hit_with_ghosts() -> void:
	var keep:Array[Dictionary] = []
	for g:Dictionary in _ghosts:
		if float(g.until) > _real_t: keep.append(g)
	_ghosts = keep
	if is_damage_output_disabled(): return
	_query_shape.radius = ghost_radius()
	var space:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for g:Dictionary in _ghosts:
		if not bool(g.armed): continue
		_query.transform = Transform2D(0.0,Vector2(g.pos))
		for entry:Dictionary in space.intersect_shape(_query,32):
			var area:Variant = entry.get("collider")
			if not area is hurtbox: continue
			var target:Variant = area.get_parent()
			if not U.enemy(self,target): continue
			var id:int = target.get_instance_id()
			if float(_ghost_hits.get(id,-INF)) > _real_t: continue
			_ghost_hits[id] = _real_t + ghost_hit_guard
			var point:Vector2 = ball.body_point(target,Vector2(g.pos))
			U.damage(self,target,attack_damage(float(g.mult) * ghost_damage_ratio),point)


# ---------------------------------------------------------------- 声音
func _emit_tick(pitch:float) -> void:
	if multiplayer.has_multiplayer_peer(): _clock_tick.rpc(pitch)
	_clock_tick(pitch)


@rpc("authority","call_remote","reliable")
func _clock_tick(pitch:float) -> void:
	SFX.queue_stream(self,HAT,global_position,{"volume_db":-6.0,"pitch":clampf(pitch,0.5,2.0),"max_distance":1400.0})


func _emit_warp() -> void:
	# 高倍速下倒流很频繁：同一声音播完前不重复触发。
	if _real_t < _warp_quiet_until: return
	_warp_quiet_until = _real_t + WARP[0].get_length() / 1.15
	if multiplayer.has_multiplayer_peer(): _clock_warp.rpc()
	_clock_warp()


@rpc("authority","call_remote","reliable")
func _clock_warp() -> void:
	SFX.queue_stream(self,WARP.pick_random(),global_position,{"volume_db":-7.0,"pitch":1.15,"max_distance":1400.0})


# ---------------------------------------------------------------- 表盘
func _process(delta:float) -> void:
	if not (image is Sprite2D): return
	var frame:int = _current_frame()
	var cycle:Variant = get_tree().current_scene.get("day_night_cycle") if get_tree().current_scene != null else null
	if cycle is Node and "minutes" in cycle:
		# 原版表盘第 0 帧太阳朝上（正午）；32 帧为午夜。
		frame = int(round((float(cycle.minutes) - 720.0) / 1440.0 * 64.0))
	elif health > 0 and is_combat_runtime_active():
		set_meta("clock_spin",float(get_meta("clock_spin",0.0)) + delta * 4.0 * time_scale)
		frame = int(get_meta("clock_spin"))
	frame = posmod(frame,64)
	set_meta("clock_frame",frame)
	(image as Sprite2D).texture = frame_texture(frame)


# ---------------------------------------------------------------- 威胁 / 介绍 / 死亡
func get_debug_attack_regions() -> Array:
	if health <= 0: return []
	var r:float = ghost_radius()
	var out:Array = [{"shape":"circle","position":global_position,"radius":r,"damage":attack_damage(current_hit_damage_multiplier()),"kind":"clock_body"}]
	for g:Dictionary in _ghosts:
		if bool(g.armed): out.append({"shape":"circle","position":g.pos,"radius":r,"damage":attack_damage(float(g.mult) * ghost_damage_ratio),"kind":"clock_afterimage"})
	return out


func get_ai_attack_threats(_receiver:Node = null) -> Array: return get_debug_attack_regions()


func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_CLOCK")


func Die() -> void:
	if has_meta("clock_dead"): return
	set_meta("clock_dead",true)
	_rewinding = false
	ITEM_DEATH.spawn(self)
	super.Die()
